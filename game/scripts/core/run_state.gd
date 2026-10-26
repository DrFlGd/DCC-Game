extends Node
## Autoload `RunState`: the single source of truth for the current run.
##
## Pure state plus progression math. No drawing, no input, no scene nodes.
## Systems mutate the run through the methods below so that every change is
## announced on `Events`. Fields may be read freely; writing them directly is
## reserved for `Game` (floor/room bookkeeping) and tests.
##
## Determinism: `rng` is reseeded from `seed` in start_run() and is the only
## RNG used for combat rolls. Floor, obstacle and encounter generation use
## their own seeded RNGs derived from floor_seed().
const RPG = preload("res://scripts/rpg_rules.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const CONFIG_PATH := "res://data/prototype_rules.json"
const DEFAULT_SEED := 424242
## run_time_seconds only advances while Game is RUNNING (advance_clock).
## ticks_granted = every floor budget assigned by reset_for_floor() plus every
## in-floor grant (first-entry grants, positive add_ticks).
const TELEMETRY_KEYS := ["rooms_entered", "shots_fired", "melee_swings", "kills",
    "damage_dealt", "damage_taken", "ticks_spent", "run_time_seconds",
    "floors_cleared", "ticks_granted", "dodges", "failsafe_despawns", "items_collected",
    "loot_boxes_opened", "credits_earned", "skills_learned", "skills_used"]
## Telemetry keys snapshotted per floor for the intermission recap.
const FLOOR_KEYS := ["rooms_entered", "kills", "damage_dealt", "damage_taken",
    "ticks_spent", "ticks_granted", "run_time_seconds"]

## Parsed prototype_rules.json (see game/README.md for every key).
var config: Dictionary = {}
## Combat dice. Consumed in a fixed order by Combat, so same seed + same inputs
## reproduce the same rolls.
var rng := RandomNumberGenerator.new()
@warning_ignore("shadowed_global_identifier")
var seed := 0
## 1-based floor depth.
var depth := 1
## Generator.generate() result for the current floor (rooms, start_id, ...).
@warning_ignore("shadowed_global_identifier")
var floor: Dictionary = {}
var current_room_id := 0
## Remaining collapse budget.
var ticks := 0
## Starting budget of the current floor (RunRules.floor_budget; 0 until set).
var floor_budget := 0
## Zero-clock grace state for this floor (CollapsePolicy.grace_initial()
## shape: active, remaining, duration, count, wave_timer, elapsed, outcome).
## Driven by the CollapseClock node; reset by reset_for_floor().
var grace: Dictionary = Collapse.grace_initial()
var xp := 0
var level := 1
## STR/DEX/CON/INT/WIS/CHA -> int.
var ability_scores: Dictionary = {}
var hp := 12
var max_hp := 12
var ac := 12
var proficiency := 2
var pending_stat_points := 0
var boss_defeated := false
## "running", "victory", "collapsed", "defeated" or "abandoned".
## ("escaped" was the single-floor prototype's success outcome; no longer used.)
var outcome := "running"
## Why the run ended: the killer's definition id for "defeated",
## "collapse on floor N", "abandoned", or "" for victory / running.
var cause := ""
## One floor_stats() record per finished floor (cleared or failed), in order.
var floor_history: Array[Dictionary] = []
## room_id -> true for rooms entered on this floor.
var visited: Dictionary = {}
## room_id -> {"blocked": Dictionary, "props": Array, "enemies": Array}.
## Persisted so obstacles and enemy HP survive revisits.
var room_states: Dictionary = {}
## Every CollapsePolicy.evaluate() entry applied on this floor, in order.
var tick_ledger: Array[Dictionary] = []
## The crawler's inventory (Wave 2B). Read and change it through
## scripts/inventory.gd, which documents the shape: melee, ranged, active,
## active_state, passives [{id, count}], consumables [{id, count}], selected,
## credits, effect_cooldowns. Empty until Game's ItemSystem fills the starting
## loadout on run_started.
var inventory: Dictionary = {}
## The crawler's active statuses (Wave 2B): status id -> EffectResolver
## instance. Changed only through scripts/status_system.gd. Cleared per run
## and per floor.
var statuses: Dictionary = {}
## Passive stat modifiers from items and skills (EffectResolver modifier
## records). sync_progression() applies them to max_hp and ac; set them with
## set_stat_modifiers().
var stat_modifiers: Array = []
## Learned skills (Wave 2F): [{"id": "skl_...", "rank": N}] (a plain id
## still reads as rank 1). Changed through scripts/skill_system.gd. Persist
## across floors; reset per run.
var skills: Array = []
## Banked (unspent) skill points and every point earned this run (Wave 2F).
## Each level-up grants `skills.points_per_level` (1).
var skill_points := 0
var skill_points_earned := 0
## Active skill id per slot (use_skill_1, use_skill_2; "" = empty). Per run.
var skill_slots: Array = ["", ""]
## Active skill id -> seconds of cooldown left. Cleared per run and per floor.
var skill_cooldowns: Dictionary = {}
## Counters for tuning; see TELEMETRY_KEYS. Updated from Events signals.
var telemetry: Dictionary = {}
## Wave 2D stamina pool (COMBAT_AND_RPG §3): spent by dodge and skills only,
## refilled at every floor start. Tunables in `feel.stamina`.
var stamina := 100.0
var max_stamina := 100.0
## Seconds since the last spend_stamina(); regen waits for `regen_delay`.
var stamina_idle := 0.0
## Telemetry values when the current floor started (see floor_stats()).
var _floor_baseline: Dictionary = {}
var _floor_closed := false


func _init() -> void:
    _reset_telemetry()


func _enter_tree() -> void:
    # _enter_tree (not _ready) so the hooks exist before a --script test's
    # _initialize() runs; autoload _ready() only fires on the first frame.
    _connect(Events.projectile_fired, _on_projectile_fired)
    _connect(Events.melee_swung, _on_melee_swung)
    _connect(Events.enemy_damaged, _on_enemy_damaged)
    _connect(Events.enemy_killed, _on_enemy_killed)
    _connect(Events.room_entered, _on_room_entered)
    _connect(Events.floor_cleared, _on_floor_cleared)
    _connect(Events.dodged, _on_dodged)
    _connect(Events.item_picked_up, _on_item_picked_up)
    _connect(Events.loot_box_opened, _on_loot_box_opened)
    _connect(Events.credits_changed, _on_credits_changed)


func load_config(path: String = CONFIG_PATH) -> bool:
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        push_error("Invalid " + path)
        return false
    config = parsed
    return true


func ensure_config() -> bool:
    return true if not config.is_empty() else load_config()


## Resets every per-run field and announces `run_started`. Floor generation is
## Game's job; it calls reset_for_floor(depth, budget) and fills `floor`
## afterwards. `start_ticks` is only a provisional clock until that budget is
## set (and the value RunState alone uses, e.g. in unit tests).
func start_run(new_seed: int) -> void:
    ensure_config()
    seed = new_seed
    rng.seed = new_seed
    ticks = int(config.get("start_ticks", 26))
    xp = 0
    pending_stat_points = 0
    ability_scores = config.get("player_ability_scores", RPG.player_base_scores()).duplicate(true)
    sync_progression()
    hp = max_hp
    outcome = "running"
    cause = ""
    floor_history.clear()
    floor_budget = 0
    inventory = {}
    statuses = {}
    stat_modifiers = []
    skills = []
    skill_points = 0
    skill_points_earned = 0
    skill_slots = []
    for _slot in range(maxi(1, int(config.get("skills", {}).get("slots", 2)))):
        skill_slots.append("")
    skill_cooldowns = {}
    tick_ledger.clear()
    _reset_telemetry()
    reset_for_floor(1)
    Events.run_started.emit(seed)


## Clears per-floor state (visited rooms, room states, boss flag, tick ledger).
## XP, level, ability scores, HP, inventory, skills, skill points and skill
## slots persist; skill cooldowns are cleared like the stamina refill. With
## `budget` >= 0 the clock is set to that fresh floor budget (leftover ticks do
## not carry over) and counted as ticks_granted; with the default -1 the clock
## is left alone.
func reset_for_floor(new_depth: int, budget: int = -1) -> void:
    depth = maxi(1, new_depth)
    floor = {}
    current_room_id = 0
    visited.clear()
    room_states.clear()
    boss_defeated = false
    tick_ledger.clear()
    statuses = {}
    skill_cooldowns = {}
    # Before the budget is set, so its ticks_changed never reads as a stabilise.
    grace = Collapse.grace_initial()
    if budget >= 0:
        floor_budget = budget
        _bump("ticks_granted", budget)
        _set_ticks(budget, "floor %d budget" % depth)
    refill_stamina()
    _floor_closed = false
    _floor_baseline = {}
    for key in FLOOR_KEYS:
        _floor_baseline[key] = telemetry.get(key, 0)


# --- Stamina (Wave 2D) ---------------------------------------------------------

## `feel.stamina` with defaults (max 100, 30/s after 0.6 s, +10 % per WIS mod).
func stamina_config() -> Dictionary:
    var result := {"max": 100.0, "regen_per_second": 30.0, "regen_delay": 0.6,
        "wis_regen_per_mod": 0.1}
    result.merge(config.get("feel", {}).get("stamina", {}), true)
    return result


## Spends `cost` stamina if the pool holds that much. Returns false (and spends
## nothing) otherwise. Any spend restarts the regen delay.
func spend_stamina(cost: float) -> bool:
    if cost <= 0.0:
        return true
    if stamina + 0.0001 < cost:
        return false
    stamina = maxf(0.0, stamina - cost)
    stamina_idle = 0.0
    Events.stamina_changed.emit(stamina, max_stamina)
    return true


## Regen per second: regen_per_second x (1 + wis_regen_per_mod x positive WIS mod).
func stamina_regen_rate() -> float:
    var settings: Dictionary = stamina_config()
    var wis: int = maxi(0, RPG.modifier(int(ability_scores.get("WIS", 10))))
    return float(settings["regen_per_second"]) * (1.0 + float(settings["wis_regen_per_mod"]) * wis)


## Game calls this only while RUNNING (and not during hit-stop).
func regen_stamina(delta: float) -> void:
    stamina_idle += delta
    if stamina >= max_stamina:
        return
    var delay: float = float(stamina_config()["regen_delay"])
    if stamina_idle < delay:
        return
    var usable: float = minf(delta, stamina_idle - delay)
    var before: float = stamina
    stamina = minf(max_stamina, stamina + stamina_regen_rate() * usable)
    if int(stamina) != int(before) or stamina >= max_stamina:
        Events.stamina_changed.emit(stamina, max_stamina)


func refill_stamina() -> void:
    max_stamina = float(stamina_config()["max"])
    stamina = max_stamina
    stamina_idle = 0.0
    Events.stamina_changed.emit(stamina, max_stamina)


## True while the zero-clock grace period runs (doors unlock, entries free).
func grace_active() -> bool:
    return bool(grace.get("active", false))


## Seed for generating floor `depth`. Depth 1 uses the run seed unchanged so
## existing seeds reproduce. Deeper floors use a provisional derivation.
func floor_seed(for_depth: int = -1) -> int:
    var d: int = depth if for_depth < 1 else for_depth
    return seed if d <= 1 else int((seed + (d - 1) * 1000003) % 2147483647)


func current_room() -> Dictionary:
    return room_states.get(current_room_id, {})


func current_room_kind() -> String:
    if floor.is_empty():
        return ""
    return String(floor["rooms"][current_room_id]["kind"])


## Recomputes level, max HP, AC and proficiency from XP and ability scores.
func sync_progression() -> void:
    var progression: Dictionary = RPG.player_progression(xp, ability_scores)
    level = int(progression["level"])
    proficiency = int(progression["proficiency"])
    # Wave 2B: item and skill passives (add, then multiply, then set).
    var derived: Dictionary = Resolver.apply_stat_modifiers(
        {"max_hp": int(progression["max_hp"]), "ac": int(progression["ac"])}, stat_modifiers)
    max_hp = maxi(1, int(derived["max_hp"]))
    ac = int(derived["ac"])


## Replaces the passive stat modifiers (Wave 2B) and re-derives max HP and AC.
## A max-HP gain heals by the same amount; a loss clamps HP to the new maximum.
func set_stat_modifiers(modifiers: Array) -> void:
    var old_max: int = max_hp
    stat_modifiers = modifiers.duplicate(true)
    sync_progression()
    if max_hp > old_max and hp > 0:
        hp = mini(max_hp, hp + max_hp - old_max)
    hp = mini(hp, max_hp)


## Adds `amount` to a telemetry counter in TELEMETRY_KEYS (for feature nodes).
func count(key: String, amount: int = 1) -> void:
    _bump(key, amount)


## Adds XP; emits `xp_gained`, then `level_up` once per award that crosses one or
## more thresholds (stat points and skill points for every level gained are
## banked; `skills.points_per_level` skill points per level, default 1).
func award_xp(amount: int) -> void:
    var gained: int = maxi(0, amount)
    var prior_level: int = level
    var old_max: int = max_hp
    xp += gained
    sync_progression()
    Events.xp_gained.emit(gained, xp)
    if level > prior_level:
        hp = mini(max_hp, hp + (max_hp - old_max))
        var earned_levels: int = level - prior_level
        pending_stat_points += earned_levels * maxi(0, int(config.get("stat_points_per_level", 2)))
        var skill_gain: int = earned_levels * maxi(0, int(config.get("skills", {}).get(
            "points_per_level", 1)))
        skill_points += skill_gain
        skill_points_earned += skill_gain
        Events.level_up.emit(level, pending_stat_points)


## Applies a staged level-up allocation. Returns false (and changes nothing) if
## RPG.apply_allocation rejects it. Raising CON heals by the max-HP gain.
func apply_stat_allocation(changes: Dictionary) -> bool:
    var cap: int = int(config.get("stat_score_cap", 20))
    var next_scores: Dictionary = RPG.apply_allocation(ability_scores, changes,
        pending_stat_points, cap)
    if next_scores.is_empty():
        return false
    var old_max: int = max_hp
    ability_scores = next_scores
    pending_stat_points = 0
    sync_progression()
    hp = mini(max_hp, hp + maxi(0, max_hp - old_max))
    Events.stats_changed.emit(ability_scores.duplicate(true))
    return true


## Removes HP (clamped at 0) and emits `player_damaged`; emits `player_died`
## when HP reaches 0. Returns the damage applied (0 if already dead).
func apply_damage_to_player(amount: int, source: String = "") -> int:
    if amount <= 0 or hp <= 0:
        return 0
    hp = maxi(0, hp - amount)
    telemetry["damage_taken"] = int(telemetry["damage_taken"]) + amount
    Events.player_damaged.emit(amount, source)
    if hp == 0:
        Events.player_died.emit(source)
    return amount


## Restores HP up to max_hp. Returns the HP actually restored.
func heal_player(amount: int) -> int:
    if amount <= 0 or hp <= 0:
        return 0
    var healed: int = mini(amount, max_hp - hp)
    hp += healed
    if healed > 0:
        Events.player_healed.emit(healed)
    return healed


## Records a CollapsePolicy entry for a door transition and applies its result.
## Only ticks actually removed (`charged`, the cost clamped at 0) count as spent.
func apply_tick_entry(entry: Dictionary) -> void:
    tick_ledger.append(entry)
    telemetry["ticks_spent"] = int(telemetry["ticks_spent"]) \
        + int(entry.get("charged", entry.get("cost", 0)))
    _bump("ticks_granted", maxi(0, int(entry.get("grant", 0))))
    _set_ticks(int(entry["after"]), String(entry.get("reason", "")))


## Adds (or with a negative value removes) ticks outside door transitions,
## e.g. items, shrines or hazards. Clamped at 0. `reason` doubles as the
## ledger source (`item:<id>`, `skill:<id>`, `shrine`, `hazard:<id>`,
## `room_clear`). Zero-clock handling stays with the CollapseClock node, which
## listens to `ticks_changed`: reaching 0 starts grace, and any positive
## amount during grace stabilises the floor.
func add_ticks(amount: int, reason: String) -> void:
    var before: int = ticks
    var next: int = maxi(0, ticks + amount)
    if next < ticks:
        telemetry["ticks_spent"] = int(telemetry["ticks_spent"]) + ticks - next
    else:
        _bump("ticks_granted", next - ticks)
    if next != before:
        tick_ledger.append({"source": reason, "reason": reason, "before": before,
            "after": next, "amount": amount, "modifiers": []})
    _set_ticks(next, reason)


## Game calls this only while RUNNING, so menus and screens never count.
func advance_clock(delta: float) -> void:
    telemetry["run_time_seconds"] = float(telemetry["run_time_seconds"]) + delta


## Recap of the current floor: rooms explored / total, budget, ticks left,
## and the FLOOR_KEYS telemetry gained since reset_for_floor().
func floor_stats() -> Dictionary:
    var result: Dictionary = {
        "depth": depth, "rooms_explored": visited.size(),
        "rooms_total": floor.get("rooms", []).size(), "budget": floor_budget,
        "ticks_left": ticks, "boss_defeated": boss_defeated,
        "grace_triggered": int(grace.get("count", 0)),
        "grace_outcome": String(grace.get("outcome", "")),
        "grace_time_used": float(grace.get("elapsed", 0.0))
    }
    for key in FLOOR_KEYS:
        var gained = telemetry.get(key, 0) - _floor_baseline.get(key, 0)
        result[key] = float(gained) if key == "run_time_seconds" else int(gained)
    return result


## Appends floor_stats() plus `result` ("cleared" or the run outcome) to
## floor_history once per floor and returns the record.
func close_floor(result: String) -> Dictionary:
    var record: Dictionary = floor_stats()
    record["result"] = result
    if not _floor_closed:
        _floor_closed = true
        floor_history.append(record)
    return record


## Intermission heal (GAME_DESIGN §4): restores run.intermission_heal_ratio of
## the *missing* HP, rounded up. Returns the HP restored.
func intermission_heal() -> int:
    var ratio: float = float(config.get("run", {}).get("intermission_heal_ratio", 0.5))
    return heal_player(int(ceil(float(max_hp - hp) * clampf(ratio, 0.0, 1.0))))


## Marks the run finished and emits `run_ended` with summary(). Closes the
## current floor's record if the exit did not already.
func end_run(new_outcome: String, new_cause: String = "") -> Dictionary:
    outcome = new_outcome
    cause = new_cause
    close_floor(new_outcome)
    var result: Dictionary = summary()
    Events.run_ended.emit(outcome, result)
    return result


## Values shown by the pause and character pages (window size is added by Game).
func progression_context() -> Dictionary:
    return {
        "depth": depth, "target_depth": int(config.get("run", {}).get("target_depth", 6)),
        "room_id": current_room_id, "ticks": ticks,
        "level": level, "xp": xp,
        "next_xp": RPG.next_level_xp(level) if level < 20 else "MAX",
        "hp": hp, "max_hp": max_hp, "ac": ac, "proficiency": proficiency,
        "melee_bonus": RPG.attack_bonus(ability_scores, "STR", level),
        "ranged_bonus": RPG.attack_bonus(ability_scores, "DEX", level),
        "skill_points": skill_points
    }


## Snapshot for the run summary screen, telemetry export and tests: every
## TELEMETRY_KEYS counter (floors_cleared, ticks_granted, run_time_seconds, ...)
## plus the fields below. `floors` is floor_history (one record per floor).
func summary() -> Dictionary:
    var result: Dictionary = telemetry.duplicate(true)
    result.merge({
        "seed": seed, "depth": depth, "outcome": outcome, "cause": cause,
        "target_depth": int(config.get("run", {}).get("target_depth", 6)),
        "floor_budget": floor_budget, "floors": floor_history.duplicate(true),
        "rooms_total": floor.get("rooms", []).size(), "level": level,
        "xp": xp, "hp": hp, "max_hp": max_hp, "ticks": ticks,
        "rooms_visited": visited.size(), "boss_defeated": boss_defeated,
        "ability_scores": ability_scores.duplicate(true),
        "inventory": inventory.duplicate(true), "skills": skills.duplicate(true),
        "skill_points": skill_points, "skill_points_earned": skill_points_earned,
        "skill_slots": skill_slots.duplicate(),
        "ledger_entries": tick_ledger.size(),
        "grace_triggered": int(grace.get("count", 0)),
        "grace_outcome": String(grace.get("outcome", "")),
        "grace_time_used": float(grace.get("elapsed", 0.0))
    })
    return result


func _set_ticks(value: int, reason: String) -> void:
    var before: int = ticks
    ticks = value
    if before != ticks:
        Events.ticks_changed.emit(before, ticks, reason)


func _reset_telemetry() -> void:
    telemetry = {}
    for key in TELEMETRY_KEYS:
        telemetry[key] = 0.0 if key == "run_time_seconds" else 0


func _bump(key: String, amount: int = 1) -> void:
    telemetry[key] = int(telemetry.get(key, 0)) + amount


func _connect(event: Signal, handler: Callable) -> void:
    if not event.is_connected(handler):
        event.connect(handler)


func _on_projectile_fired(owner_kind: String, _data: Dictionary) -> void:
    if owner_kind == "player":
        _bump("shots_fired")


func _on_melee_swung(owner_kind: String, _position: Vector2, _direction: Vector2) -> void:
    if owner_kind == "player":
        _bump("melee_swings")


func _on_enemy_damaged(_instance_id: String, amount: int, _critical: bool) -> void:
    _bump("damage_dealt", amount)


func _on_enemy_killed(_definition_id: String, _xp: int, _position: Vector2) -> void:
    _bump("kills")


func _on_dodged(_direction: Vector2) -> void:
    _bump("dodges")


## Door-lock failsafe (COMBAT_AND_RPG §9): `count` unreachable hostiles removed.
func record_failsafe_despawn(count: int) -> void:
    _bump("failsafe_despawns", count)


func _on_floor_cleared(_depth: int) -> void:
    _bump("floors_cleared")


func _on_item_picked_up(_item_id: String) -> void:
    _bump("items_collected")


func _on_loot_box_opened(_room_id: int, _loot_ids: Array) -> void:
    _bump("loot_boxes_opened")


func _on_credits_changed(amount: int, _total: int) -> void:
    if amount > 0:
        _bump("credits_earned", amount)


func _on_room_entered(_room_id: int, _kind: String, _entry: Dictionary, first_visit: bool) -> void:
    if first_visit:
        _bump("rooms_entered")
