extends Node
## SkillSystem (Wave 2F): skill points, learning rules, the two active-skill
## slots and their cooldowns (COMBAT_AND_RPG §11, CONTENT_RULES §6).
## Child of Game (created by Game._ready, after ItemSystem).
##
## State lives in RunState: `skills` ([{id, rank}]), `skill_points` (banked),
## `skill_points_earned`, `skill_slots` (active skill id per slot, "" = empty)
## and `skill_cooldowns` (id -> seconds left). Level-ups grant
## `skills.points_per_level` points (RunState.award_xp).
##
## - Rules (static, pure over RunState): can_learn(id) -> {ok, reason, detail,
##   cost, rank, next_rank}; learn(id) spends `cost` points, raises the rank by
##   one (ranks replace each other: Loadout.current() only ever carries the
##   current rank's effects), auto-assigns a new active skill to the first free
##   slot, counts `skills_learned` and emits Events.skill_learned(id, rank).
##   ItemSystem listens to skill_learned and recomputes passive stats.
## - Actives: use_skill(id) / use_slot(i) check blocks_actions (stunned), the
##   cooldown, a dash skill's can_dodge(), then RunState.spend_stamina(); they
##   run the current rank's on_use effects through EffectRunner.fire_skill(),
##   start the rank's cooldown, count `skills_used` and emit
##   Events.skill_used(id, rank). A skill listed under `skills.dashes` also
##   dashes (player.start_dash + combat.on_player_dodged, so on_dodge fires);
##   an `evasive` status from its effects becomes the dash's i-frames.
## - Cooldowns tick in update() (RUNNING only) and are cleared per floor.
##   cooldown_reduction effects with stat "skills" (or "all") shorten them
##   (EffectRunner).
## - INT scales every skill effect's magnitude (Loadout.skill_magnitude_mult).
## Determinism: nothing here rolls; only effect `chance` rolls use
## RunState.rng, in trigger order (as in 2B).
## Autoloads are looked up at runtime, so tests may preload this module.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const EffectRunner = preload("res://scripts/effect_runner.gd")

const DEFAULT_SLOTS := 2
## Input Map action per slot (index = slot).
const SLOT_ACTIONS := ["use_skill_1", "use_skill_2"]
const SLOT_KEYS := ["Z", "X"]
## can_learn() / use_skill() reasons, for UI text.
const REASONS := {
    "ok": "", "unknown": "Unknown skill.", "max_rank": "Maxed out.",
    "level": "Needs level %d.", "prerequisite": "Needs %s.",
    "prerequisite_rank": "Needs %s rank %d.", "points": "Needs %d skill point%s.",
    "not_learned": "Not learned.", "passive": "Passive skills are always on.",
    "stunned": "You are in no state to do that.", "cooldown": "%s is recharging (%.1fs).",
    "stamina": "Not enough stamina for %s (%d needed).", "busy": "Busy dashing.",
    "empty": "Nothing in that slot."
}

var game


# --- Lookups --------------------------------------------------------------------

static func run_state() -> Node:
    return Inventory.run_state()


## `skills` in prototype_rules.json with defaults.
static func config() -> Dictionary:
    var result := {"points_per_level": 1, "slots": DEFAULT_SLOTS, "int_magnitude_per_mod": 0.1,
        "dashes": {}}
    var rs: Node = run_state()
    if rs != null:
        result.merge(rs.config.get("skills", {}), true)
    return result


static func slot_count() -> int:
    return clampi(int(config()["slots"]), 1, SLOT_ACTIONS.size())


## RunState.skills as [{id, rank}] (plain "skl_id" entries become rank 1;
## the list is normalised in place so later writes stick).
static func learned() -> Array:
    var rs: Node = run_state()
    for i in range(rs.skills.size()):
        var entry = rs.skills[i]
        if not entry is Dictionary:
            rs.skills[i] = {"id": String(entry), "rank": 1}
    return rs.skills


static func rank_of(id: String) -> int:
    for entry in learned():
        if String(entry.get("id", "")) == id:
            return int(entry.get("rank", 1))
    return 0


static func points() -> int:
    return int(run_state().skill_points)


## Rank `rank`'s cooldown override, else the skill's `cooldown` (seconds).
static func cooldown_for(id: String, rank: int = -1) -> float:
    var record: Dictionary = ContentDB.skill(id)
    var ranks: Array = record.get("ranks", [])
    var chosen: int = rank if rank > 0 else maxi(1, rank_of(id))
    if chosen >= 1 and chosen <= ranks.size() and ranks[chosen - 1].has("cooldown"):
        return float(ranks[chosen - 1]["cooldown"])
    return float(record.get("cooldown", 0.0))


static func stamina_cost(id: String) -> float:
    return float(ContentDB.skill(id).get("stamina_cost", 0.0))


static func cooldown_left(id: String) -> float:
    return float(run_state().skill_cooldowns.get(id, 0.0))


# --- Learning -------------------------------------------------------------------

## Whether one more rank of `id` can be learned now: {ok, reason, detail,
## cost, rank, next_rank}. Checks, in order: known id, max_rank,
## unlock_level, every prerequisite (skill learned, then its rank), cost vs.
## banked points.
static func can_learn(id: String) -> Dictionary:
    var rs: Node = run_state()
    var record: Dictionary = ContentDB.skill(id)
    var rank: int = rank_of(id)
    var result := {"ok": false, "reason": "unknown", "detail": REASONS["unknown"], "cost": 0,
        "rank": rank, "next_rank": rank + 1}
    if record.is_empty():
        return result
    var cost: int = int(record.get("cost", 1))
    result["cost"] = cost
    if rank >= int(record.get("max_rank", 1)):
        return _reason(result, "max_rank", REASONS["max_rank"])
    if rank == 0 and rs.level < int(record.get("unlock_level", 1)):
        return _reason(result, "level", REASONS["level"] % int(record.get("unlock_level", 1)))
    for requirement in record.get("prerequisites", []):
        var needed: String = String(requirement.get("skill", ""))
        var needed_rank: int = int(requirement.get("rank", 1))
        var have: int = rank_of(needed)
        var label: String = String(ContentDB.skill(needed).get("name", needed))
        if have <= 0:
            return _reason(result, "prerequisite", REASONS["prerequisite"] % label)
        if have < needed_rank:
            return _reason(result, "prerequisite_rank",
                REASONS["prerequisite_rank"] % [label, needed_rank])
    if int(rs.skill_points) < cost:
        return _reason(result, "points", REASONS["points"] % [cost, "" if cost == 1 else "s"])
    result["ok"] = true
    result["reason"] = "ok"
    result["detail"] = ""
    return result


static func _reason(result: Dictionary, reason: String, detail: String) -> Dictionary:
    result["reason"] = reason
    result["detail"] = detail
    return result


## Learns one rank of `id` (can_learn() first). Returns can_learn()'s result
## with `rank` set to the new rank on success.
static func learn(id: String) -> Dictionary:
    var check: Dictionary = can_learn(id)
    if not bool(check["ok"]):
        return check
    var rs: Node = run_state()
    rs.skill_points = int(rs.skill_points) - int(check["cost"])
    var rank: int = int(check["next_rank"])
    var found := false
    for entry in learned():
        if String(entry["id"]) == id:
            entry["rank"] = rank
            found = true
    if not found:
        rs.skills.append({"id": id, "rank": rank})
    if String(ContentDB.skill(id).get("kind", "")) == "active" and slot_of(id) < 0:
        var free: int = slots().find("")
        if free >= 0:
            rs.skill_slots[free] = id
    rs.count("skills_learned")
    check["rank"] = rank
    Inventory.emit("skill_learned", [id, rank])
    return check


# --- Slots ----------------------------------------------------------------------

## RunState.skill_slots sized to slot_count() (the same array, so edits stick).
static func slots() -> Array:
    var rs: Node = run_state()
    var size: int = slot_count()
    while rs.skill_slots.size() < size:
        rs.skill_slots.append("")
    if rs.skill_slots.size() > size:
        rs.skill_slots.resize(size)
    return rs.skill_slots


static func slot_of(id: String) -> int:
    return slots().find(id)


## Puts learned active skill `id` into `slot`; a skill already in another slot
## swaps places with the one it displaces. Returns false when not allowed.
static func assign_slot(id: String, slot: int) -> bool:
    var bound: Array = slots()
    if slot < 0 or slot >= bound.size() or rank_of(id) <= 0 \
            or String(ContentDB.skill(id).get("kind", "")) != "active":
        return false
    var previous: int = bound.find(id)
    var displaced: String = String(bound[slot])
    bound[slot] = id
    if previous >= 0 and previous != slot:
        bound[previous] = displaced
    return true


# --- Using actives --------------------------------------------------------------

## Whether active skill `id` could be used now (no side effects):
## {ok, reason, detail}. `can_dash` is the player's can_dodge() for dash skills.
static func can_use(id: String, can_dash: bool = true) -> Dictionary:
    var record: Dictionary = ContentDB.skill(id)
    var name: String = String(record.get("name", id))
    if id == "":
        return {"ok": false, "reason": "empty", "detail": REASONS["empty"]}
    if rank_of(id) <= 0:
        return {"ok": false, "reason": "not_learned", "detail": REASONS["not_learned"]}
    if String(record.get("kind", "")) != "active":
        return {"ok": false, "reason": "passive", "detail": REASONS["passive"]}
    if StatusSystem.has_flag("player", "blocks_actions"):
        return {"ok": false, "reason": "stunned", "detail": REASONS["stunned"]}
    if cooldown_left(id) > 0.0:
        return {"ok": false, "reason": "cooldown",
            "detail": REASONS["cooldown"] % [name, cooldown_left(id)]}
    if config()["dashes"].has(id) and not can_dash:
        return {"ok": false, "reason": "busy", "detail": REASONS["busy"]}
    if run_state().stamina + 0.0001 < stamina_cost(id):
        return {"ok": false, "reason": "stamina",
            "detail": REASONS["stamina"] % [name, int(stamina_cost(id))]}
    return {"ok": true, "reason": "ok", "detail": ""}


## Uses active skill `id`: checks can_use(), spends the stamina, runs the
## current rank's on_use effects (EffectRunner.fire_skill), starts the rank's
## cooldown, dashes for skills under `skills.dashes`, counts `skills_used` and
## emits Events.skill_used(id, rank). `move_axis` picks a dash direction (the
## aim when still). Returns {ok, reason, detail}; a refusal changes nothing.
func use_skill(id: String, move_axis: Vector2 = Vector2.ZERO) -> Dictionary:
    var player = game.player if game != null else null
    var dash: Dictionary = config()["dashes"].get(id, {})
    var check: Dictionary = can_use(id, player == null or player.can_dodge())
    if not bool(check["ok"]):
        if check["reason"] != "empty":
            Inventory.emit("message", [String(check["detail"]), "info"])
        return check
    var rs: Node = run_state()
    if not rs.spend_stamina(stamina_cost(id)):
        return {"ok": false, "reason": "stamina", "detail": REASONS["stamina"] % [
            String(ContentDB.skill(id).get("name", id)), int(stamina_cost(id))]}
    var rank: int = rank_of(id)
    var combat = game.combat if game != null else null
    EffectRunner.fire_skill(combat, id, rank, "on_use")
    rs.skill_cooldowns[id] = cooldown_for(id, rank)
    if player != null:
        if rs.statuses.has("evasive"):
            player.dodge_iframes = maxf(player.dodge_iframes,
                float(rs.statuses["evasive"].get("remaining", 0.0)))
        if not dash.is_empty():
            var direction: Vector2 = player.dodge_direction_for(move_axis)
            player.start_dash(direction, float(dash.get("distance", 32.0)),
                float(dash.get("duration", 0.18)), 0.0, float(dash.get("recovery", 0.05)))
            if combat != null:
                combat.on_player_dodged(direction)
    rs.count("skills_used")
    Inventory.emit("skill_used", [id, rank])
    Inventory.emit("message", ["Activated %s." % String(ContentDB.skill(id).get("name", id)),
        "progression"])
    return {"ok": true, "reason": "ok", "detail": ""}


## Uses the skill bound to `slot` (0-based).
func use_slot(slot: int, move_axis: Vector2 = Vector2.ZERO) -> Dictionary:
    var bound: Array = slots()
    if slot < 0 or slot >= bound.size():
        return {"ok": false, "reason": "empty", "detail": REASONS["empty"]}
    return use_skill(String(bound[slot]), move_axis)


## Counts every active cooldown down (Game calls it only while RUNNING).
static func tick_cooldowns(delta: float) -> void:
    reduce_cooldowns(delta)


## Takes `seconds` off every skill cooldown (cooldown_reduction "skills").
static func reduce_cooldowns(seconds: float) -> void:
    var cooldowns: Dictionary = run_state().skill_cooldowns
    for id in cooldowns.keys():
        var left: float = float(cooldowns[id]) - seconds
        if left <= 0.000001:
            cooldowns.erase(id)
        else:
            cooldowns[id] = left


func setup(game_node) -> void:
    game = game_node


## Per-frame step while Game is RUNNING.
func update(delta: float) -> void:
    tick_cooldowns(delta)


# --- Views ----------------------------------------------------------------------

## Plain view model for the level-up overlay, the pause-menu Skills page and
## the HUD: {points, earned, slots: [...], skills: [...]}.
## skills[]: id, name, kind, rank, max_rank, cost, unlock_level, description,
## effects (current rank's effect descriptions), next (next rank's), learnable,
## reason, detail, slot, cooldown, stamina_cost. slots[]: slot, key, id, name,
## cooldown, cooldown_left, stamina_cost, affordable, ready.
static func describe() -> Dictionary:
    var rs: Node = run_state()
    var view := {"points": int(rs.skill_points), "earned": int(rs.skill_points_earned),
        "slots": describe_slots(), "skills": []}
    for record in ContentDB.default_db().get("skills", []):
        var id: String = String(record.get("id", ""))
        var rank: int = rank_of(id)
        var check: Dictionary = can_learn(id)
        view["skills"].append({"id": id, "name": String(record.get("name", id)),
            "kind": String(record.get("kind", "passive")), "rank": rank,
            "max_rank": int(record.get("max_rank", 1)), "cost": int(record.get("cost", 1)),
            "unlock_level": int(record.get("unlock_level", 1)),
            "description": String(record.get("description", "")),
            "effects": _effect_lines(record, rank), "next": _effect_lines(record, rank + 1),
            "learnable": bool(check["ok"]), "reason": String(check["reason"]),
            "detail": String(check["detail"]), "slot": slot_of(id),
            "cooldown": cooldown_for(id, maxi(1, rank)), "stamina_cost": stamina_cost(id)})
    return view


## The slots part of describe() (the HUD reads it every frame).
static func describe_slots() -> Array:
    var rs: Node = run_state()
    var result: Array = []
    var bound: Array = slots()
    for i in range(bound.size()):
        var id: String = String(bound[i])
        var entry := {"slot": i, "key": SLOT_KEYS[i] if i < SLOT_KEYS.size() else str(i + 1),
            "id": id, "name": "", "cooldown": 0.0, "cooldown_left": 0.0, "stamina_cost": 0.0,
            "affordable": false, "ready": false}
        if id != "":
            entry["name"] = String(ContentDB.skill(id).get("name", id))
            entry["cooldown"] = cooldown_for(id)
            entry["cooldown_left"] = cooldown_left(id)
            entry["stamina_cost"] = stamina_cost(id)
            entry["affordable"] = rs.stamina + 0.0001 >= stamina_cost(id)
            entry["ready"] = cooldown_left(id) <= 0.0 and bool(entry["affordable"])
        result.append(entry)
    return result


static func _effect_lines(record: Dictionary, rank: int) -> Array:
    var ranks: Array = record.get("ranks", [])
    var lines: Array = []
    if rank < 1 or rank > ranks.size():
        return lines
    for effect_id in ranks[rank - 1].get("effects", []):
        var text: String = String(ContentDB.effect(String(effect_id)).get("description", ""))
        if text != "":
            lines.append(text)
    return lines
