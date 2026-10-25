extends RefCounted
## Statuses on actors (Wave 2B, COMBAT_AND_RPG §7, CONTENT_RULES §4).
##
## The crawler's map is `RunState.statuses`; an enemy's is `enemy["statuses"]`
## (created on first use). Both hold EffectResolver.apply_status() instances.
## A `target` argument is "player" (or the Player node) or an enemy dictionary.
##
## - apply(target, effect, source, extra): applies an apply_status effect (or a
##   `set` cleanse). Bosses ignore stunned/rooted and take half-length slows;
##   elites take half-length stuns; WIS shortens harmful statuses on the crawler
##   by 10 % per positive modifier (minimum 50 %); at most 6 distinct statuses.
##   A stun on an enemy also puts its AI in the "stunned" state.
## - tick_all(combat, delta): ticks every status of the crawler and the current
##   room's enemies; periodic damage goes through combat.apply_damage() with
##   context {source: "status:<id>", status, damage_type}; periodic heals use
##   RunState.heal_player().
## - Queries: has_status, has_flag (blocks_actions, invulnerable, untargetable,
##   absorbs_damage), speed_multiplier, player_modifiers, decoy_position.
## - absorb(target, amount): spends `shielded` pools; returns the damage left.
## Every add/remove emits Events.status_changed(target_key, status_id, active).
## Autoloads are looked up at runtime, so tests may preload this module.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const RPG = preload("res://scripts/rpg_rules.gd")

const MAX_DISTINCT := 6
const BOSS_IMMUNE := ["stunned", "rooted"]
const DAMAGE_TYPE_BY_TAG := {"fire": "fire", "toxic": "toxic", "arcane": "arcane"}
## Marker colours (renderer and HUD).
const COLORS := {"burning": Color("#ff7a2e"), "poisoned": Color("#9bd34a"),
    "bleeding": Color("#e0404a"), "slowed": Color("#6fb6ff"), "stunned": Color("#ffe066"),
    "shielded": Color("#7fe6ff"), "hasted": Color("#f5f5f5"), "evasive": Color("#c9a6ff"),
    "concealed": Color("#9aa4b4")}


static func _autoload(node_name: String) -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root.get_node_or_null(node_name) if tree != null else null


static func _emit(target, status_id: String, active: bool) -> void:
    var events: Node = _autoload("Events")
    if events != null:
        events.emit_signal("status_changed", target_key(target), status_id, active)


## Gameplay clock for applied_at/cooldowns: RunState run time (frozen in menus).
static func now() -> float:
    var rs: Node = _autoload("RunState")
    return float(rs.telemetry.get("run_time_seconds", 0.0)) if rs != null else 0.0


static func is_player(target) -> bool:
    return not target is Dictionary


static func target_key(target) -> String:
    return String(target.get("instance_id", "enemy")) if target is Dictionary else "player"


static func statuses_of(target) -> Dictionary:
    if target is Dictionary:
        if not target.get("statuses") is Dictionary:
            target["statuses"] = {}
        return target["statuses"]
    return _autoload("RunState").statuses


static func _store(target, statuses: Dictionary) -> void:
    if target is Dictionary:
        target["statuses"] = statuses
    else:
        _autoload("RunState").statuses = statuses


## Applies `effect` ({status, operation "apply_status" | "set", magnitude,
## duration, stacking}; a bare {status} uses the definition defaults). `extra`
## keys are stored on the instance (e.g. decoy_pos). Returns true when the
## target's statuses changed.
static func apply(target, effect: Dictionary, source: String = "", extra: Dictionary = {}) -> bool:
    var status_id: String = String(effect.get("status", ""))
    var db: Dictionary = ContentDB.default_db()
    var definition: Dictionary = ContentDB.status(status_id, db)
    if definition.is_empty():
        return false
    if target is Dictionary and int(target.get("hp", 1)) <= 0:
        return false
    var current: Dictionary = statuses_of(target)
    var spec: Dictionary = effect.duplicate(true)
    if not spec.has("operation"):
        spec["operation"] = "apply_status"
    if String(spec["operation"]) == "set":
        var cleansed: Dictionary = Resolver.apply_status(current, spec, now(), db)
        _store(target, cleansed)
        if current.has(status_id) and not cleansed.has(status_id):
            _emit(target, status_id, false)
        return current.has(status_id)
    var factor := 1.0
    if target is Dictionary:
        if bool(target.get("boss", false)):
            if BOSS_IMMUNE.has(status_id):
                return false
            if status_id == "slowed":
                factor = 0.5
        elif String(target.get("elite", "")) != "" and status_id == "stunned":
            factor = 0.5
    elif String(definition.get("kind", "")) == "debuff":
        var rs: Node = _autoload("RunState")
        var wis: int = maxi(0, RPG.modifier(int(rs.ability_scores.get("WIS", 10))))
        factor = maxf(0.5, 1.0 - 0.1 * float(wis))
    if factor != 1.0:
        var duration: float = float(spec.get("duration", 0.0))
        if duration <= 0.0:
            duration = float(definition.get("default_duration", 1.0))
        spec["duration"] = duration * factor
    var had: bool = current.has(status_id)
    if not had and current.size() >= MAX_DISTINCT:
        return false
    var updated: Dictionary = Resolver.apply_status(current, spec, now(), db)
    if not had:
        updated[status_id]["source"] = source
        updated[status_id].merge(extra, true)
    _store(target, updated)
    if target is Dictionary and status_id == "stunned" and not had:
        # The 2C state machine already knows "stunned": it cancels the wind-up
        # and stands still until state_length passes.
        target["state"] = "stunned"
        target["state_time"] = 0.0
        target["state_length"] = float(updated[status_id]["remaining"])
        target["attack"] = ""
        target["queued"] = ""
    if not had:
        _emit(target, status_id, true)
    return true


## Applies status `status_id` with its definition defaults (hazards, enemy attacks).
static func apply_default(target, status_id: String, source: String = "") -> bool:
    return apply(target, {"status": status_id}, source)


static func has_status(target, status_id: String) -> bool:
    return statuses_of(target).has(status_id)


static func has_flag(target, flag: String) -> bool:
    return Resolver.has_flag(statuses_of(target), flag)


## Move-speed multiplier from statuses (slowed x0.6, hasted x1.3, ...).
static func speed_multiplier(target) -> float:
    var statuses: Dictionary = statuses_of(target)
    if statuses.is_empty():
        return 1.0
    var mods: Array[Dictionary] = Resolver.status_modifiers(statuses, ContentDB.default_db())
    return float(Resolver.apply_stat_modifiers({"move_speed": 1.0}, mods)["move_speed"])


## The crawler's status stat modifiers (for attack profiles and player stats).
static func player_modifiers() -> Array[Dictionary]:
    var rs: Node = _autoload("RunState")
    if rs == null or rs.statuses.is_empty():
        return []
    return Resolver.status_modifiers(rs.statuses, ContentDB.default_db())


## Where enemies aim while the crawler is concealed, or Vector2.INF.
static func decoy_position() -> Vector2:
    var rs: Node = _autoload("RunState")
    if rs == null or not rs.statuses.has("concealed"):
        return Vector2.INF
    return rs.statuses["concealed"].get("decoy_pos", Vector2.INF)


## Spends shield pools against `amount`; returns the damage left for HP.
static func absorb(target, amount: int) -> int:
    var current: Dictionary = statuses_of(target)
    if amount <= 0 or not Resolver.has_flag(current, "absorbs_damage"):
        return amount
    var result: Dictionary = Resolver.absorb_damage(current, amount)
    _store(target, result["statuses"])
    for status_id in current.keys():
        if not result["statuses"].has(status_id):
            _emit(target, String(status_id), false)
    return int(result["remaining_damage"])


static func clear(target) -> void:
    var current: Dictionary = statuses_of(target)
    _store(target, {})
    for status_id in current.keys():
        _emit(target, String(status_id), false)


## Ticks one actor. Returns the total periodic damage dealt.
static func tick(target, delta: float, combat) -> int:
    var current: Dictionary = statuses_of(target)
    if current.is_empty():
        return 0
    var result: Dictionary = Resolver.tick_statuses(current, delta)
    _store(target, result["statuses"])
    for status_id in result["expired"]:
        _emit(target, String(status_id), false)
    var dealt := 0
    var rs: Node = _autoload("RunState")
    for event in result["periodic"]:
        var amount: int = int(event["amount"])
        var status_id: String = String(event["status"])
        if amount <= 0:
            continue
        if String(event["operation"]) == "heal":
            if is_player(target):
                rs.heal_player(amount)
            elif int(target["hp"]) > 0:
                target["hp"] = mini(int(target["max_hp"]), int(target["hp"]) + amount)
            continue
        if combat == null:
            continue
        if is_player(target):
            if rs.hp <= 0:
                break
            dealt += int(combat.apply_damage(combat.player, amount, _dot_context(status_id, current)))
        else:
            if int(target["hp"]) <= 0:
                break
            dealt += int(combat.apply_damage(target, amount, _dot_context(status_id, current)))
    return dealt


## Ticks the crawler and every enemy of the current room.
static func tick_all(combat, delta: float) -> void:
    var rs: Node = _autoload("RunState")
    if rs.hp > 0:
        tick("player", delta, combat)
    for foe in combat.enemies().duplicate():
        if int(foe["hp"]) > 0:
            tick(foe, delta, combat)


static func _dot_context(status_id: String, statuses: Dictionary) -> Dictionary:
    var definition: Dictionary = ContentDB.status(status_id)
    var damage_type := "physical"
    for tag in definition.get("tags", []):
        if DAMAGE_TYPE_BY_TAG.has(String(tag)):
            damage_type = DAMAGE_TYPE_BY_TAG[String(tag)]
    var source: String = String(statuses.get(status_id, {}).get("source", ""))
    return {"source": "status:" + status_id, "status": status_id, "damage_type": damage_type,
        "applied_by": source}
