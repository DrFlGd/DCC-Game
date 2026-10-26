extends RefCounted
## Pure evaluation of the standard effect model (see docs/design/CONTENT_RULES.md).
## Nothing here touches the scene tree; every random roll uses a caller-supplied
## RandomNumberGenerator so results are reproducible from a seed.
const RPG = preload("res://scripts/rpg_rules.gd")

const STAT_OPERATIONS := ["add", "multiply", "set"]
const EPSILON := 0.000001

## Parses "refresh", "ignore" or "stack_count:N". Returns {"mode": "", "max": 0} when invalid.
static func parse_stacking(stacking) -> Dictionary:
    var text: String = String(stacking) if stacking != null else ""
    if text == "refresh" or text == "ignore":
        return {"mode": text, "max": 1}
    if text.begins_with("stack_count:"):
        var tail: String = text.substr(12)
        if tail.is_valid_int() and int(tail) >= 1:
            return {"mode": "stack_count", "max": int(tail)}
    return {"mode": "", "max": 0}

## Returns true when every key of `condition` holds for `context` (keys are ANDed).
## An empty or missing condition always passes. Unknown keys fail closed.
## `chance` is evaluated last so a roll is only consumed when everything else passed.
## Without an RNG (argument or context["rng"]) a chance below 1.0 fails.
static func evaluate_condition(condition, context: Dictionary,
        rng: RandomNumberGenerator = null) -> bool:
    if condition == null or not condition is Dictionary:
        return true
    var rules: Dictionary = condition
    for key in rules.keys():
        var value = rules[key]
        match String(key):
            "chance":
                pass
            "hp_below_pct":
                var below: float = _hp_pct(context)
                if below < 0.0 or below >= float(value):
                    return false
            "hp_above_pct":
                var above: float = _hp_pct(context)
                if above < 0.0 or above <= float(value):
                    return false
            "target_tag":
                if not _contains(context.get("target_tags", []), String(value)):
                    return false
            "weapon_tag":
                if not _contains(context.get("weapon_tags", []), String(value)):
                    return false
            "status_present":
                if not _contains(context.get("target_statuses", {}), String(value)):
                    return false
            "status_absent":
                if _contains(context.get("target_statuses", {}), String(value)):
                    return false
            "slot":
                if String(context.get("slot", "")) != String(value):
                    return false
            "ticks_below":
                if not context.has("ticks") or int(context["ticks"]) >= int(value):
                    return false
            "depth_at_least":
                if int(context.get("depth", 0)) < int(value):
                    return false
            "room_kind":
                if String(context.get("room_kind", "")) != String(value):
                    return false
            "nearby_enemies_at_least":
                if int(context.get("nearby_enemies", 0)) < int(value):
                    return false
            _:
                return false
    if rules.has("chance"):
        var probability: float = float(rules["chance"])
        if probability >= 1.0:
            return true
        if probability <= 0.0:
            return false
        var roller: RandomNumberGenerator = rng
        if roller == null and context.get("rng") is RandomNumberGenerator:
            roller = context["rng"]
        if roller == null:
            return false
        return roller.randf() < probability
    return true

## Gathers the effects from equipped records that fire on `trigger`.
## Each entry is {"id": source_id, "effects": [effect ids or inline effect dictionaries],
## "stacks": optional copies, "magnitude_mult": optional scale}; ContentDB.loadout()
## builds these. Context keys used:
## "effect_defs" (id -> effect) or "db" (a ContentDB.load_all() result), "rng", "now",
## "cooldowns" (cooldown_key -> ready time), plus any condition inputs.
## The effect's `stacking` caps how many copies of one effect id contribute
## (refresh/ignore: 1, stack_count:N: N). Effects still on cooldown are skipped.
## Returned modifiers are copies of the effect with "effect_id", "source" and "cooldown_key".
static func collect_modifiers(equipped: Array[Dictionary], trigger: String,
        context: Dictionary) -> Array[Dictionary]:
    var defs: Dictionary = _effect_defs(context)
    var rng: RandomNumberGenerator = null
    if context.get("rng") is RandomNumberGenerator:
        rng = context["rng"]
    var now: float = float(context.get("now", 0.0))
    var cooldowns: Dictionary = context.get("cooldowns", {})
    var counts: Dictionary = {}
    var result: Array[Dictionary] = []
    for entry in equipped:
        var source: String = String(entry.get("id", ""))
        var copies: int = maxi(1, int(entry.get("stacks", 1)))
        for reference in entry.get("effects", []):
            var effect: Dictionary = {}
            if reference is Dictionary:
                effect = reference
            else:
                effect = defs.get(String(reference), {})
            if effect.is_empty() or String(effect.get("trigger", "")) != trigger:
                continue
            var effect_id: String = String(effect.get("id", "" if reference is Dictionary else String(reference)))
            var key: String = source + ":" + effect_id
            if cooldowns.has(key) and float(cooldowns[key]) > now + EPSILON:
                continue
            var limit: int = maxi(1, int(parse_stacking(effect.get("stacking", "ignore"))["max"]))
            for _copy in range(copies):
                if int(counts.get(effect_id, 0)) >= limit:
                    break
                if not evaluate_condition(effect.get("condition", {}), context, rng):
                    continue
                counts[effect_id] = int(counts.get(effect_id, 0)) + 1
                var modifier: Dictionary = effect.duplicate(true)
                if entry.has("magnitude_mult"):
                    scale_magnitude(modifier, float(entry["magnitude_mult"]))
                modifier["effect_id"] = effect_id
                modifier["source"] = source
                modifier["cooldown_key"] = key
                result.append(modifier)
    return result

## Wave 2F `magnitude_mult` hook (INT scaling of skill effects): scales
## `effect` in place. add, heal, damage, cooldown_reduction and additive
## projectile modifiers multiply their magnitude; multiply operations scale
## their distance from 1 (x0.9 becomes x0.89 at 1.1); apply_status scales a
## positive magnitude (shield pool, DoT per tick). set and grant_ticks are
## never scaled. An entry's "magnitude_mult" (ContentDB.loadout) applies it in
## collect_modifiers().
static func scale_magnitude(effect: Dictionary, mult: float) -> void:
    if absf(mult - 1.0) <= EPSILON or not effect.has("magnitude"):
        return
    var magnitude: float = float(effect["magnitude"])
    var operation: String = String(effect.get("operation", ""))
    if operation == "spawn_projectile_modifier":
        operation = String(effect.get("apply", "add"))
    match operation:
        "multiply":
            effect["magnitude"] = 1.0 + (magnitude - 1.0) * mult
        "add", "heal", "damage", "cooldown_reduction":
            effect["magnitude"] = magnitude * mult
        "apply_status":
            if magnitude > 0.0:
                effect["magnitude"] = magnitude * mult
        _:
            return
    effect["magnitude_mult"] = mult

## Returns a copy of `cooldowns` with every fired modifier that has a cooldown set to
## become ready at now + cooldown.
static func start_cooldowns(cooldowns: Dictionary, modifiers: Array, now: float) -> Dictionary:
    var result: Dictionary = cooldowns.duplicate(true)
    for modifier in modifiers:
        if modifier is Dictionary and float(modifier.get("cooldown", 0.0)) > 0.0:
            result[String(modifier.get("cooldown_key", modifier.get("effect_id", "")))] = (
                now + float(modifier["cooldown"]))
    return result

## Applies stat modifiers in a fixed order: every add, then every multiply, then every
## set (the last set in list order wins). spawn_projectile_modifier counts as its
## `apply` operation (add by default). Records with a `status` key are ignored.
## Missing stats start at 0. Stats that were ints in `base_stats` are rounded back to int.
static func apply_stat_modifiers(base_stats: Dictionary, modifiers) -> Dictionary:
    var values: Dictionary = {}
    for key in base_stats.keys():
        values[key] = base_stats[key]
    for phase in STAT_OPERATIONS:
        for modifier in modifiers:
            if not modifier is Dictionary or _stat_operation(modifier) != phase:
                continue
            var stat: String = String(modifier.get("stat", ""))
            if stat.is_empty():
                continue
            var current: float = float(values.get(stat, 0.0))
            var magnitude: float = float(modifier.get("magnitude", 0.0))
            match phase:
                "add":
                    values[stat] = current + magnitude
                "multiply":
                    values[stat] = current * magnitude
                "set":
                    values[stat] = magnitude
    for key in values.keys():
        if base_stats.has(key) and base_stats[key] is int:
            values[key] = roundi(float(values[key]))
    return values

## Turns active statuses into stat modifiers (their definitions' stat_modifiers).
## `status_defs` is either id -> definition or the raw statuses array.
static func status_modifiers(statuses: Dictionary, status_defs) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var ids: Array = statuses.keys()
    ids.sort()
    for status_id in ids:
        var definition: Dictionary = _status_def(status_defs, String(status_id))
        for entry in definition.get("stat_modifiers", []):
            var modifier: Dictionary = entry.duplicate(true)
            modifier["source"] = "status:" + String(status_id)
            result.append(modifier)
    return result

## Applies an apply_status (or set-with-status) effect to a status map and returns a new map.
## Instance shape: {stacks, max_stacks, remaining, duration, magnitude, applied_at,
## refreshed_at, tick_timer, tick_interval, periodic, flags}.
## Stacking: ignore = no change if present; refresh = remaining becomes max(remaining,
## duration) and magnitude the larger value; stack_count:N = +1 stack up to N and refresh.
## operation "set" sets the stack count (0 removes the status: used by cleanses).
## Effect duration/magnitude <= 0 fall back to the status definition defaults.
static func apply_status(statuses: Dictionary, effect, now: float, status_defs = {}) -> Dictionary:
    var result: Dictionary = statuses.duplicate(true)
    if not effect is Dictionary:
        return result
    var status_id: String = String(effect.get("status", ""))
    if status_id.is_empty():
        return result
    var definition: Dictionary = _status_def(status_defs, status_id)
    if String(effect.get("operation", "apply_status")) == "set":
        var count: int = int(effect.get("magnitude", 0))
        if count <= 0:
            result.erase(status_id)
        elif result.has(status_id):
            result[status_id]["stacks"] = mini(count, maxi(1, int(result[status_id].get("max_stacks", count))))
        return result
    var stacking: Dictionary = parse_stacking(effect.get("stacking",
        definition.get("default_stacking", "refresh")))
    if String(stacking["mode"]).is_empty():
        stacking = {"mode": "refresh", "max": 1}
    var duration: float = float(effect.get("duration", 0.0))
    if duration <= 0.0:
        duration = float(definition.get("default_duration", 1.0))
    var magnitude: float = float(effect.get("magnitude", 0.0))
    if magnitude <= 0.0:
        magnitude = float(definition.get("default_magnitude", 0.0))
    if not result.has(status_id):
        result[status_id] = {
            "stacks": 1, "max_stacks": int(stacking["max"]),
            "remaining": duration, "duration": duration, "magnitude": magnitude,
            "applied_at": now, "refreshed_at": now, "tick_timer": 0.0,
            "tick_interval": float(definition.get("tick_interval", 0.0)),
            "periodic": String(definition.get("periodic", "none")),
            "flags": Array(definition.get("flags", [])).duplicate(),
            "stacking": String(stacking["mode"])
        }
        return result
    var instance: Dictionary = result[status_id]
    match String(stacking["mode"]):
        "ignore":
            pass
        "refresh":
            instance["remaining"] = maxf(float(instance["remaining"]), duration)
            instance["magnitude"] = maxf(float(instance["magnitude"]), magnitude)
            instance["refreshed_at"] = now
        "stack_count":
            instance["max_stacks"] = int(stacking["max"])
            instance["stacks"] = mini(int(instance["stacks"]) + 1, int(stacking["max"]))
            instance["remaining"] = maxf(float(instance["remaining"]), duration)
            instance["magnitude"] = maxf(float(instance["magnitude"]), magnitude)
            instance["refreshed_at"] = now
    return result

## Advances every status by `delta` seconds. Periodic statuses emit magnitude x stacks
## on each full tick_interval (ticks landing exactly at expiry still fire).
## Returns {"statuses": still-active map, "expired": [ids], "periodic": [{status,
## operation, amount}], "damage": int total, "heal": int total}.
static func tick_statuses(statuses: Dictionary, delta: float) -> Dictionary:
    var updated: Dictionary = {}
    var expired: Array[String] = []
    var events: Array[Dictionary] = []
    var damage := 0
    var heal := 0
    var ids: Array = statuses.keys()
    ids.sort()
    for status_id in ids:
        var instance: Dictionary = statuses[status_id].duplicate(true)
        var remaining: float = float(instance.get("remaining", 0.0))
        var elapsed: float = minf(maxf(delta, 0.0), maxf(remaining, 0.0))
        var interval: float = float(instance.get("tick_interval", 0.0))
        var periodic: String = String(instance.get("periodic", "none"))
        if interval > 0.0 and (periodic == "damage" or periodic == "heal"):
            var timer: float = float(instance.get("tick_timer", 0.0)) + elapsed
            while timer + EPSILON >= interval:
                timer -= interval
                var amount: int = roundi(float(instance.get("magnitude", 0.0)) * int(instance.get("stacks", 1)))
                events.append({"status": String(status_id), "operation": periodic, "amount": amount})
                if periodic == "damage":
                    damage += amount
                else:
                    heal += amount
            instance["tick_timer"] = maxf(timer, 0.0)
        instance["remaining"] = remaining - delta
        if float(instance["remaining"]) <= EPSILON:
            expired.append(String(status_id))
        else:
            updated[status_id] = instance
    return {"statuses": updated, "expired": expired, "periodic": events,
        "damage": damage, "heal": heal}

## Spends a shielded pool against incoming damage.
## Returns {"statuses", "absorbed", "remaining_damage"}; an emptied shield is removed.
static func absorb_damage(statuses: Dictionary, amount: int) -> Dictionary:
    var result: Dictionary = statuses.duplicate(true)
    var absorbed := 0
    for status_id in result.keys():
        var instance: Dictionary = result[status_id]
        if not Array(instance.get("flags", [])).has("absorbs_damage"):
            continue
        var pool: int = roundi(float(instance.get("magnitude", 0.0)))
        var used: int = mini(pool, amount - absorbed)
        absorbed += used
        instance["magnitude"] = float(pool - used)
        if pool - used <= 0:
            result.erase(status_id)
        if absorbed >= amount:
            break
    return {"statuses": result, "absorbed": absorbed, "remaining_damage": amount - absorbed}

## True when any active status carries `flag` (blocks_actions, invulnerable, ...).
static func has_flag(statuses: Dictionary, flag: String) -> bool:
    for instance in statuses.values():
        if Array(instance.get("flags", [])).has(flag):
            return true
    return false

## Integer amount for heal/damage effects: magnitude, plus 1d(die) through rpg_rules when
## the effect has a die. Without an RNG the die contributes its rounded-up average.
static func resolve_amount(effect: Dictionary, rng: RandomNumberGenerator = null) -> int:
    var flat: int = roundi(float(effect.get("magnitude", 0.0)))
    var die: int = int(effect.get("die", 0))
    if die <= 0:
        return flat
    if rng == null:
        return flat + ceili(float(die + 1) / 2.0)
    return RPG.roll_damage(rng, die, flat, false)

static func _stat_operation(modifier: Dictionary) -> String:
    if modifier.has("status"):
        return ""
    var operation: String = String(modifier.get("operation", ""))
    if operation == "spawn_projectile_modifier":
        return String(modifier.get("apply", "add"))
    return operation if STAT_OPERATIONS.has(operation) else ""

static func _effect_defs(context: Dictionary) -> Dictionary:
    if context.get("effect_defs") is Dictionary:
        return context["effect_defs"]
    if context.get("db") is Dictionary:
        return context["db"].get("index", {}).get("effects", {})
    return {}

static func _status_def(status_defs, status_id: String) -> Dictionary:
    if status_defs is Dictionary:
        if status_defs.has(status_id) and status_defs[status_id] is Dictionary:
            return status_defs[status_id]
        if status_defs.get("index") is Dictionary:
            return status_defs["index"].get("statuses", {}).get(status_id, {})
    elif status_defs is Array:
        for entry in status_defs:
            if entry is Dictionary and String(entry.get("id", "")) == status_id:
                return entry
    return {}

static func _hp_pct(context: Dictionary) -> float:
    var max_hp: float = float(context.get("max_hp", 0.0))
    if max_hp <= 0.0 or not context.has("hp"):
        return -1.0
    return float(context["hp"]) / max_hp * 100.0

static func _contains(collection, value: String) -> bool:
    if collection is Dictionary:
        return collection.has(value)
    if collection is Array or collection is PackedStringArray:
        return value in collection
    return false
