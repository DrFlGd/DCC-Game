extends RefCounted
## Data-driven content catalogue: effects, statuses, weapons, items, skills and loot
## tables, loaded from res://data/content/*.json. Pure logic, not yet wired into
## main.gd (integration is Wave 2B/2F). Schema reference: docs/design/CONTENT_RULES.md.
## Records returned by lookups are shared: treat them as read-only (duplicate to edit).
const RPG = preload("res://scripts/rpg_rules.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")

const CONTENT_DIR := "res://data/content/"
const SCHEMA_VERSION := 1
const FILES := ["effects.json", "weapons.json", "items.json", "skills.json", "loot_tables.json"]
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const TRIGGERS := ["passive", "on_hit", "on_kill", "on_damage_taken", "on_room_enter",
    "on_room_clear", "on_use", "on_dodge", "on_level_up", "periodic"]
const TARGETS := ["self", "target", "enemies_in_radius", "projectile"]
const OPERATIONS := ["add", "multiply", "set", "heal", "damage", "apply_status",
    "grant_ticks", "spawn_projectile_modifier", "cooldown_reduction"]
const CONDITION_KEYS := ["hp_below_pct", "hp_above_pct", "chance", "target_tag", "weapon_tag",
    "status_present", "status_absent", "slot", "ticks_below", "depth_at_least", "room_kind",
    "nearby_enemies_at_least"]
const SLOTS := ["melee", "ranged"]
const PATTERNS := {"melee": ["arc", "thrust", "spin"], "ranged": ["single", "spread", "burst", "beam"]}
const WEAPON_ABILITIES := ["STR", "DEX"]
const WEAPON_TRIGGERS := ["passive", "on_hit", "on_kill", "periodic"]
const ITEM_KINDS := ["active", "passive", "consumable"]
const SKILL_KINDS := ["active", "passive"]
const COOLDOWN_UNITS := {"seconds": 600.0, "rooms_cleared": 20.0, "floors": 5.0}
const ADAPTATION_TYPES := ["canon", "adapted", "original"]
const LOOT_CONTEXTS := ["room_normal_clear", "treasure_room", "boss_kill", "guild_hall_shop", "floor_start"]
const STATUS_KINDS := ["buff", "debuff"]
const STATUS_PERIODIC := ["none", "damage", "heal"]
const STATUS_FLAGS := ["blocks_actions", "absorbs_damage", "invulnerable", "untargetable"]
const PREFIXES := {"effects": "fx_", "weapons": "wpn_", "items": "itm_", "skills": "skl_"}
const WEAPON_KEYS := ["id", "name", "slot", "attack_pattern", "damage_die", "damage_bonus",
    "ability", "cooldown", "knockback", "pierce", "tags", "rarity", "min_depth", "effects",
    "sprite", "description", "adaptation_type"]
const ITEM_KEYS := ["id", "name", "kind", "rarity", "min_depth", "effects", "cooldown",
    "cooldown_unit", "charges", "stack_max", "tags", "sprite", "description", "adaptation_type"]
const SKILL_KEYS := ["id", "name", "kind", "max_rank", "cost", "unlock_level", "prerequisites",
    "ranks", "tags", "description", "adaptation_type"]
const EFFECT_KEYS := ["id", "trigger", "target", "operation", "magnitude", "duration",
    "stacking", "description"]

static var _cache: Dictionary = {}

## Loads every content file and returns the database dictionary:
## {schema_versions, stats, projectile_stats, cooldown_keys, statuses, effects, weapons,
##  items, skills (raw record arrays), loot (loot_tables.json), index (kind -> id -> record),
##  load_problems}.
static func load_all() -> Dictionary:
    var problems: Array[String] = []
    var docs: Dictionary = {}
    for file_name in FILES:
        docs[file_name] = _read_json(CONTENT_DIR + file_name, problems)
    var effects_doc: Dictionary = docs["effects.json"]
    var db: Dictionary = {
        "schema_versions": {},
        "stats": effects_doc.get("stats", []),
        "projectile_stats": effects_doc.get("projectile_stats", []),
        "cooldown_keys": effects_doc.get("cooldown_keys", []),
        "statuses": effects_doc.get("statuses", []),
        "effects": effects_doc.get("effects", []),
        "weapons": docs["weapons.json"].get("weapons", []),
        "items": docs["items.json"].get("items", []),
        "skills": docs["skills.json"].get("skills", []),
        "loot": docs["loot_tables.json"],
        "load_problems": problems
    }
    for file_name in FILES:
        db["schema_versions"][file_name] = int(docs[file_name].get("schema_version", 0))
    db["index"] = build_index(db)
    return db

## Cached load_all() used by the lookup helpers when no db is passed.
static func default_db() -> Dictionary:
    if _cache.is_empty():
        _cache = load_all()
    return _cache

static func reload() -> Dictionary:
    _cache = load_all()
    return _cache

## Builds kind -> id -> record. The first record wins when an id is duplicated
## (validate() reports duplicates).
static func build_index(db: Dictionary) -> Dictionary:
    var index: Dictionary = {}
    for kind in ["statuses", "effects", "weapons", "items", "skills"]:
        var by_id: Dictionary = {}
        for record in db.get(kind, []):
            if record is Dictionary and record.has("id") and not by_id.has(String(record["id"])):
                by_id[String(record["id"])] = record
        index[kind] = by_id
    return index

static func weapon(id: String, db: Dictionary = {}) -> Dictionary:
    return _lookup("weapons", id, db)

static func item(id: String, db: Dictionary = {}) -> Dictionary:
    return _lookup("items", id, db)

static func skill(id: String, db: Dictionary = {}) -> Dictionary:
    return _lookup("skills", id, db)

static func effect(id: String, db: Dictionary = {}) -> Dictionary:
    return _lookup("effects", id, db)

static func status(id: String, db: Dictionary = {}) -> Dictionary:
    return _lookup("statuses", id, db)

static func loot_table(id: String, db: Dictionary = {}) -> Dictionary:
    var source: Dictionary = db if not db.is_empty() else default_db()
    return source.get("loot", {}).get("tables", {}).get(id, {})

## Looks up a weapon, item or skill by its id prefix.
static func record(id: String, db: Dictionary = {}) -> Dictionary:
    for kind in ["weapons", "items", "skills", "effects"]:
        if id.begins_with(String(PREFIXES[kind])):
            return _lookup(kind, id, db)
    return {}

## Normalises an owned weapon/item/skill into the entry shape that
## EffectResolver.collect_modifiers() expects: {id, kind, rank, stacks, effects}.
## Skills use the effects of the given rank. Unknown ids return {}.
static func loadout_entry(id: String, rank: int = 1, stacks: int = 1, db: Dictionary = {}) -> Dictionary:
    var data: Dictionary = record(id, db)
    if data.is_empty():
        return {}
    var effects: Array = data.get("effects", [])
    var kind: String = "weapon" if id.begins_with("wpn_") else ("item" if id.begins_with("itm_") else "skill")
    if kind == "skill":
        var ranks: Array = data.get("ranks", [])
        var chosen: int = clampi(rank, 1, maxi(1, ranks.size()))
        effects = ranks[chosen - 1].get("effects", []) if not ranks.is_empty() else []
        rank = chosen
    return {"id": id, "kind": kind, "rank": rank, "stacks": maxi(1, stacks), "effects": effects.duplicate()}

## Builds a typed loadout from ids or {"id", "rank", "stacks"} dictionaries.
static func loadout(owned: Array, db: Dictionary = {}) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for owned_entry in owned:
        var entry: Dictionary = {}
        if owned_entry is Dictionary:
            entry = loadout_entry(String(owned_entry.get("id", "")), int(owned_entry.get("rank", 1)),
                int(owned_entry.get("stacks", 1)), db)
        else:
            entry = loadout_entry(String(owned_entry), 1, 1, db)
        if not entry.is_empty():
            result.append(entry)
    return result

## Weapon numbers expressed in stat-vocabulary keys, ready for apply_stat_modifiers().
static func weapon_base_stats(weapon_record: Dictionary) -> Dictionary:
    var slot: String = String(weapon_record.get("slot", "melee"))
    var stats: Dictionary = {
        slot + "_cooldown": float(weapon_record.get("cooldown", 0.5)),
        "damage_bonus": int(weapon_record.get("damage_bonus", 0)),
        "melee_damage_bonus": 0, "ranged_damage_bonus": 0, "attack_bonus": 0,
        "knockback": float(weapon_record.get("knockback", 0)),
        "pierce": int(weapon_record.get("pierce", 0)), "crit_threshold": 20
    }
    if slot == "melee":
        stats["melee_reach"] = float(weapon_record.get("reach", 32))
        stats["arc_degrees"] = float(weapon_record.get("arc_degrees", 127))
    else:
        stats["range"] = float(weapon_record.get("range", 430))
        stats["projectile_speed"] = float(weapon_record.get("projectile_speed", 215))
        stats["projectile_count"] = int(weapon_record.get("projectile_count", 1))
        stats["spread_degrees"] = float(weapon_record.get("spread_degrees", 0))
    return stats

## Resolves a weapon into numbers main.gd already understands, via rpg_rules.gd:
## attack bonus = ability modifier + proficiency (+ attack_bonus modifiers);
## damage = 1d(die) + ability modifier + weapon bonus (+ damage modifiers).
## `modifiers` are passive stat/projectile modifiers from collect_modifiers().
static func attack_profile(weapon_record: Dictionary, scores: Dictionary, level: int,
        modifiers: Array = []) -> Dictionary:
    var slot: String = String(weapon_record.get("slot", "melee"))
    var ability: String = String(weapon_record.get("ability", "STR"))
    var effective_scores: Dictionary = Resolver.apply_stat_modifiers(scores, modifiers)
    var stats: Dictionary = Resolver.apply_stat_modifiers(weapon_base_stats(weapon_record), modifiers)
    var profile: Dictionary = {
        "weapon_id": String(weapon_record.get("id", "")), "slot": slot, "ability": ability,
        "pattern": String(weapon_record.get("attack_pattern", "")),
        "die": int(weapon_record.get("damage_die", 6)),
        "attack_bonus": RPG.attack_bonus(effective_scores, ability, level,
            bool(weapon_record.get("proficient", true))) + int(stats.get("attack_bonus", 0)),
        "damage_bonus": RPG.modifier(int(effective_scores.get(ability, 10)))
            + int(stats.get("damage_bonus", 0)) + int(stats.get(slot + "_damage_bonus", 0)),
        "cooldown": maxf(0.05, float(stats.get(slot + "_cooldown", 0.5))),
        "knockback": float(stats.get("knockback", 0.0)), "pierce": int(stats.get("pierce", 0)),
        "crit_threshold": int(stats.get("crit_threshold", 20))
    }
    if slot == "melee":
        profile["reach"] = float(stats["melee_reach"])
        profile["arc_degrees"] = float(stats["arc_degrees"])
        profile["dot_threshold"] = arc_dot_threshold(float(stats["arc_degrees"]))
    else:
        var speed: float = float(stats["projectile_speed"])
        profile["range"] = float(stats["range"])
        profile["projectile_speed"] = speed
        profile["projectile_count"] = maxi(1, int(stats["projectile_count"]))
        profile["spread_degrees"] = float(stats["spread_degrees"])
        profile["ttl"] = float(stats["range"]) / speed if speed > 0.0 else 0.0
        profile["burst_count"] = int(weapon_record.get("burst_count", 1))
        profile["burst_interval"] = float(weapon_record.get("burst_interval", 0.0))
    return profile

## Converts a full arc width in degrees to the dot-product test main.gd uses
## (aim.dot(toward_enemy) > threshold). 127 degrees is about the current 0.45.
static func arc_dot_threshold(arc_degrees: float) -> float:
    if arc_degrees >= 360.0:
        return -1.01
    return cos(deg_to_rad(arc_degrees / 2.0))

## Returns [] when the skill graph is acyclic, otherwise the ids along one cycle
## (first id repeated at the end).
static func find_prerequisite_cycle(skills: Array) -> Array[String]:
    var edges: Dictionary = {}
    var order: Array = []
    for entry in skills:
        if not entry is Dictionary:
            continue
        var skill_id: String = String(entry.get("id", ""))
        var needs: Array = []
        for prerequisite in entry.get("prerequisites", []):
            needs.append(_prerequisite_id(prerequisite))
        edges[skill_id] = needs
        order.append(skill_id)
    var colour: Dictionary = {}
    for start in order:
        if int(colour.get(start, 0)) != 0:
            continue
        var path: Array[String] = []
        var found: Array[String] = _cycle_from(start, edges, colour, path)
        if not found.is_empty():
            return found
    return []

static func _cycle_from(node: String, edges: Dictionary, colour: Dictionary,
        path: Array[String]) -> Array[String]:
    colour[node] = 1
    path.append(node)
    for next in edges.get(node, []):
        var state: int = int(colour.get(next, 0))
        if state == 1:
            var cycle: Array[String] = []
            for i in range(path.find(next), path.size()):
                cycle.append(path[i])
            cycle.append(String(next))
            return cycle
        if state == 0 and edges.has(next):
            var found: Array[String] = _cycle_from(String(next), edges, colour, path)
            if not found.is_empty():
                return found
    path.pop_back()
    colour[node] = 2
    var none: Array[String] = []
    return none

# ---------------------------------------------------------------- validation

## Returns every problem found as "<file or id>: <message>" strings; empty means valid.
## Works on the raw record arrays, so in-memory edits are validated without re-indexing.
static func validate(db: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    for problem in db.get("load_problems", []):
        problems.append(String(problem))
    for file_name in db.get("schema_versions", {}).keys():
        if int(db["schema_versions"][file_name]) != SCHEMA_VERSION:
            problems.append("%s: schema_version must be %d" % [file_name, SCHEMA_VERSION])
    var stats: Array = db.get("stats", [])
    if stats.is_empty():
        problems.append("effects.json: stats vocabulary is empty")
    var ids: Dictionary = {}
    for kind in ["statuses", "effects", "weapons", "items", "skills"]:
        ids[kind] = _collect_ids(db.get(kind, []), kind, problems)
    for status_record in db.get("statuses", []):
        _validate_status(status_record, stats, problems)
    var effect_by_id: Dictionary = {}
    for effect_record in db.get("effects", []):
        if effect_record is Dictionary:
            effect_by_id[String(effect_record.get("id", ""))] = effect_record
            _validate_effect(effect_record, db, ids["statuses"], problems)
    for weapon_record in db.get("weapons", []):
        _validate_weapon(weapon_record, effect_by_id, problems)
    for item_record in db.get("items", []):
        _validate_item(item_record, effect_by_id, problems)
    var skill_by_id: Dictionary = {}
    for skill_record in db.get("skills", []):
        if skill_record is Dictionary:
            skill_by_id[String(skill_record.get("id", ""))] = skill_record
    for skill_record in db.get("skills", []):
        _validate_skill(skill_record, effect_by_id, skill_by_id, problems)
    var cycle: Array[String] = find_prerequisite_cycle(db.get("skills", []))
    if not cycle.is_empty():
        problems.append("skills: prerequisite cycle %s" % " -> ".join(cycle))
    _validate_loot(db, ids, problems)
    return problems

static func _collect_ids(records: Array, kind: String, problems: Array[String]) -> Dictionary:
    var seen: Dictionary = {}
    var snake := RegEx.create_from_string("^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
    for i in range(records.size()):
        var entry = records[i]
        if not entry is Dictionary:
            problems.append("%s[%d]: record is not an object" % [kind, i])
            continue
        var record_id: String = String(entry.get("id", ""))
        if record_id.is_empty():
            problems.append("%s[%d]: missing id" % [kind, i])
            continue
        if snake.search(record_id) == null:
            problems.append("%s: id must be snake_case" % record_id)
        if PREFIXES.has(kind) and not record_id.begins_with(String(PREFIXES[kind])):
            problems.append("%s: %s ids must start with '%s'" % [record_id, kind, PREFIXES[kind]])
        if seen.has(record_id):
            problems.append("%s: duplicate id in %s" % [record_id, kind])
        seen[record_id] = true
    return seen

static func _validate_status(entry, stats: Array, problems: Array[String]) -> void:
    if not entry is Dictionary:
        return
    var label: String = "status " + String(entry.get("id", "?"))
    _require_string(entry, "name", label, problems)
    _require_string(entry, "description", label, problems)
    _check_enum(entry.get("kind"), STATUS_KINDS, label, "kind", problems)
    _check_enum(entry.get("periodic", "none"), STATUS_PERIODIC, label, "periodic", problems)
    if String(entry.get("periodic", "none")) != "none":
        _check_range(entry, "tick_interval", 0.05, 60.0, label, problems)
        _check_range(entry, "default_magnitude", 0.0, 999.0, label, problems)
    _check_range(entry, "default_duration", 0.05, 600.0, label, problems)
    if String(Resolver.parse_stacking(entry.get("default_stacking", ""))["mode"]).is_empty():
        problems.append("%s: invalid default_stacking '%s'" % [label, entry.get("default_stacking", "")])
    for flag in entry.get("flags", []):
        _check_enum(flag, STATUS_FLAGS, label, "flags", problems)
    for modifier in entry.get("stat_modifiers", []):
        if not modifier is Dictionary or not stats.has(String(modifier.get("stat", ""))):
            problems.append("%s: stat_modifiers entry has unknown stat" % label)
            continue
        _check_enum(modifier.get("operation"), Resolver.STAT_OPERATIONS, label, "stat_modifiers.operation", problems)
        if String(modifier.get("operation", "")) == "multiply":
            _check_range(modifier, "magnitude", 0.01, 10.0, label, problems)

static func _validate_effect(entry: Dictionary, db: Dictionary, status_ids: Dictionary,
        problems: Array[String]) -> void:
    var label: String = String(entry.get("id", "?"))
    for key in EFFECT_KEYS:
        if not entry.has(key):
            problems.append("%s: missing %s" % [label, key])
    _require_string(entry, "description", label, problems)
    var trigger: String = String(entry.get("trigger", ""))
    var target: String = String(entry.get("target", ""))
    var operation: String = String(entry.get("operation", ""))
    _check_enum(trigger, TRIGGERS, label, "trigger", problems)
    _check_enum(target, TARGETS, label, "target", problems)
    _check_enum(operation, OPERATIONS, label, "operation", problems)
    _check_range(entry, "duration", 0.0, 600.0, label, problems)
    if entry.has("cooldown"):
        _check_range(entry, "cooldown", 0.0, 600.0, label, problems)
    if String(Resolver.parse_stacking(entry.get("stacking", ""))["mode"]).is_empty():
        problems.append("%s: invalid stacking '%s' (refresh | ignore | stack_count:N)" % [
            label, entry.get("stacking", "")])
    if trigger == "periodic":
        _check_range(entry, "interval", 0.1, 600.0, label, problems)
    if target == "enemies_in_radius":
        _check_range(entry, "radius", 8.0, 384.0, label, problems)
    if entry.has("die"):
        if not ["heal", "damage"].has(operation):
            problems.append("%s: die is only allowed on heal/damage" % label)
        _check_range(entry, "die", 1.0, 20.0, label, problems)
    if entry.has("condition"):
        _validate_condition(entry["condition"], label, status_ids, problems)
    if not _is_number(entry.get("magnitude")):
        problems.append("%s: magnitude must be a number" % label)
        return
    var magnitude: float = float(entry["magnitude"])
    var status_key: String = String(entry.get("status", ""))
    match operation:
        "add", "multiply", "set":
            if not status_key.is_empty():
                if operation != "set":
                    problems.append("%s: only 'set' may target a status (to change stack count)" % label)
                if not status_ids.has(status_key):
                    problems.append("%s: unknown status '%s'" % [label, status_key])
                if magnitude < 0.0 or magnitude > 20.0:
                    problems.append("%s: status stack count must be 0..20" % label)
            else:
                if not Array(db.get("stats", [])).has(String(entry.get("stat", ""))):
                    problems.append("%s: unknown stat '%s'" % [label, entry.get("stat", "")])
                if operation == "multiply" and (magnitude <= 0.0 or magnitude > 10.0):
                    problems.append("%s: multiply magnitude must be in (0, 10]" % label)
                elif absf(magnitude) > 1000.0:
                    problems.append("%s: magnitude out of range (|m| <= 1000)" % label)
        "heal", "damage":
            if magnitude < 0.0 or magnitude > 999.0:
                problems.append("%s: %s magnitude must be 0..999" % [label, operation])
            if target == "projectile":
                problems.append("%s: %s cannot target a projectile" % [label, operation])
        "apply_status":
            if not status_ids.has(status_key):
                problems.append("%s: unknown status '%s'" % [label, status_key])
            if float(entry.get("duration", 0)) <= 0.0:
                problems.append("%s: apply_status needs duration > 0" % label)
            if magnitude < 0.0 or magnitude > 999.0:
                problems.append("%s: status magnitude must be 0..999" % label)
        "grant_ticks":
            if target != "self":
                problems.append("%s: grant_ticks must target self" % label)
            if magnitude < 1.0 or magnitude > 5.0 or magnitude != floorf(magnitude):
                problems.append("%s: grant_ticks magnitude must be a whole number 1..5" % label)
        "spawn_projectile_modifier":
            if target != "projectile":
                problems.append("%s: spawn_projectile_modifier must target projectile" % label)
            if not Array(db.get("projectile_stats", [])).has(String(entry.get("stat", ""))):
                problems.append("%s: unknown projectile stat '%s'" % [label, entry.get("stat", "")])
            var apply: String = String(entry.get("apply", "add"))
            _check_enum(apply, ["add", "multiply"], label, "apply", problems)
            if apply == "multiply" and (magnitude <= 0.0 or magnitude > 10.0):
                problems.append("%s: multiply magnitude must be in (0, 10]" % label)
        "cooldown_reduction":
            if not Array(db.get("cooldown_keys", [])).has(String(entry.get("stat", ""))):
                problems.append("%s: unknown cooldown key '%s'" % [label, entry.get("stat", "")])
            if magnitude <= 0.0 or magnitude > 60.0:
                problems.append("%s: cooldown_reduction magnitude must be in (0, 60] seconds" % label)

static func _validate_condition(condition, label: String, status_ids: Dictionary,
        problems: Array[String]) -> void:
    if not condition is Dictionary:
        problems.append("%s: condition must be an object" % label)
        return
    for key in condition.keys():
        var value = condition[key]
        match String(key):
            "chance":
                if not _is_number(value) or float(value) <= 0.0 or float(value) > 1.0:
                    problems.append("%s: condition.chance must be in (0, 1]" % label)
            "hp_below_pct", "hp_above_pct":
                if not _is_number(value) or float(value) <= 0.0 or float(value) >= 100.0:
                    problems.append("%s: condition.%s must be in (0, 100)" % [label, key])
            "status_present", "status_absent":
                if not status_ids.has(String(value)):
                    problems.append("%s: condition.%s names unknown status '%s'" % [label, key, value])
            "slot":
                _check_enum(value, SLOTS, label, "condition.slot", problems)
            "ticks_below", "depth_at_least", "nearby_enemies_at_least":
                if not _is_number(value) or float(value) < 1.0 or float(value) > 99.0:
                    problems.append("%s: condition.%s must be 1..99" % [label, key])
            "target_tag", "weapon_tag", "room_kind":
                if not value is String or String(value).is_empty():
                    problems.append("%s: condition.%s must be a non-empty string" % [label, key])
            _:
                problems.append("%s: unknown condition key '%s'" % [label, key])

static func _validate_common(entry: Dictionary, label: String, keys: Array,
        effect_by_id: Dictionary, problems: Array[String]) -> void:
    for key in keys:
        if not entry.has(key):
            problems.append("%s: missing %s" % [label, key])
    _require_string(entry, "name", label, problems)
    _require_string(entry, "description", label, problems)
    if entry.has("sprite"):
        _require_string(entry, "sprite", label, problems)
    if entry.has("rarity"):
        _check_enum(entry.get("rarity"), RARITIES, label, "rarity", problems)
    if entry.has("min_depth"):
        _check_range(entry, "min_depth", 1.0, 99.0, label, problems, true)
    _check_enum(entry.get("adaptation_type"), ADAPTATION_TYPES, label, "adaptation_type", problems)
    if String(entry.get("adaptation_type", "")) == "canon" and String(entry.get("source_reference", "")).is_empty():
        problems.append("%s: canon content needs a source_reference" % label)
    if not entry.get("tags", []) is Array:
        problems.append("%s: tags must be an array" % label)
    if entry.has("value"):
        _check_range(entry, "value", 0.0, 100000.0, label, problems)
    if entry.has("effects"):
        _check_effect_refs(entry.get("effects"), label, effect_by_id, problems)

static func _check_effect_refs(refs, label: String, effect_by_id: Dictionary,
        problems: Array[String]) -> void:
    if not refs is Array:
        problems.append("%s: effects must be an array of effect ids" % label)
        return
    for ref in refs:
        if not effect_by_id.has(String(ref)):
            problems.append("%s: unknown effect '%s'" % [label, ref])

static func _validate_weapon(entry, effect_by_id: Dictionary, problems: Array[String]) -> void:
    if not entry is Dictionary:
        return
    var label: String = String(entry.get("id", "?"))
    _validate_common(entry, label, WEAPON_KEYS, effect_by_id, problems)
    var slot: String = String(entry.get("slot", ""))
    _check_enum(slot, SLOTS, label, "slot", problems)
    if PATTERNS.has(slot):
        _check_enum(entry.get("attack_pattern"), PATTERNS[slot], label, "attack_pattern for " + slot, problems)
    _check_enum(entry.get("ability"), WEAPON_ABILITIES, label, "ability", problems)
    _check_range(entry, "damage_die", 1.0, 20.0, label, problems, true)
    _check_range(entry, "damage_bonus", -5.0, 10.0, label, problems)
    _check_range(entry, "cooldown", 0.05, 5.0, label, problems)
    _check_range(entry, "knockback", 0.0, 200.0, label, problems)
    _check_range(entry, "pierce", 0.0, 10.0, label, problems, true)
    if slot == "melee":
        _check_range(entry, "reach", 8.0, 96.0, label, problems)
        _check_range(entry, "arc_degrees", 1.0, 360.0, label, problems)
    elif slot == "ranged":
        _check_range(entry, "range", 32.0, 800.0, label, problems)
        _check_range(entry, "projectile_count", 1.0, 12.0, label, problems, true)
        _check_range(entry, "spread_degrees", 0.0, 180.0, label, problems)
        if String(entry.get("attack_pattern", "")) == "beam":
            _check_range(entry, "projectile_speed", 0.0, 600.0, label, problems)
        else:
            _check_range(entry, "projectile_speed", 40.0, 600.0, label, problems)
        if String(entry.get("attack_pattern", "")) == "burst":
            _check_range(entry, "burst_count", 2.0, 8.0, label, problems, true)
            _check_range(entry, "burst_interval", 0.01, 0.5, label, problems)
    for ref in entry.get("effects", []):
        var fx: Dictionary = effect_by_id.get(String(ref), {})
        if not fx.is_empty() and not WEAPON_TRIGGERS.has(String(fx.get("trigger", ""))):
            problems.append("%s: weapon effect '%s' uses trigger '%s' (allowed: %s)" % [
                label, ref, fx.get("trigger", ""), ", ".join(WEAPON_TRIGGERS)])

static func _validate_item(entry, effect_by_id: Dictionary, problems: Array[String]) -> void:
    if not entry is Dictionary:
        return
    var label: String = String(entry.get("id", "?"))
    _validate_common(entry, label, ITEM_KEYS, effect_by_id, problems)
    var kind: String = String(entry.get("kind", ""))
    _check_enum(kind, ITEM_KINDS, label, "kind", problems)
    var unit: String = String(entry.get("cooldown_unit", "seconds"))
    _check_enum(unit, COOLDOWN_UNITS.keys(), label, "cooldown_unit", problems)
    _check_range(entry, "stack_max", 1.0, 99.0, label, problems, true)
    _check_range(entry, "charges", 0.0, 99.0, label, problems, true)
    var effects: Array = entry.get("effects", []) if entry.get("effects", []) is Array else []
    if effects.is_empty():
        problems.append("%s: items need at least one effect" % label)
    var uses := 0
    for ref in effects:
        if String(effect_by_id.get(String(ref), {}).get("trigger", "")) == "on_use":
            uses += 1
    match kind:
        "active":
            _check_range(entry, "cooldown", 0.1, float(COOLDOWN_UNITS.get(unit, 600.0)), label, problems)
            _check_range(entry, "charges", 1.0, 99.0, label, problems, true)
            if uses == 0:
                problems.append("%s: active items need an on_use effect" % label)
        "consumable":
            _check_range(entry, "charges", 1.0, 99.0, label, problems, true)
            if uses != effects.size():
                problems.append("%s: consumable effects must all be on_use" % label)
        "passive":
            if uses > 0:
                problems.append("%s: passive items cannot have on_use effects" % label)
    for flag in entry.get("balance_flags", []):
        if not flag is String:
            problems.append("%s: balance_flags must be strings" % label)

static func _validate_skill(entry, effect_by_id: Dictionary, skill_by_id: Dictionary,
        problems: Array[String]) -> void:
    if not entry is Dictionary:
        return
    var label: String = String(entry.get("id", "?"))
    _validate_common(entry, label, SKILL_KEYS, effect_by_id, problems)
    var kind: String = String(entry.get("kind", ""))
    _check_enum(kind, SKILL_KINDS, label, "kind", problems)
    _check_range(entry, "max_rank", 1.0, 5.0, label, problems, true)
    _check_range(entry, "cost", 1.0, 5.0, label, problems, true)
    _check_range(entry, "unlock_level", 1.0, 20.0, label, problems, true)
    if kind == "active":
        _check_range(entry, "cooldown", 0.1, 120.0, label, problems)
        _check_range(entry, "stamina_cost", 0.0, 100.0, label, problems)
    var ranks = entry.get("ranks", [])
    if not ranks is Array or ranks.size() != int(entry.get("max_rank", 0)):
        problems.append("%s: ranks must list exactly max_rank entries" % label)
        ranks = ranks if ranks is Array else []
    for i in range(ranks.size()):
        var rank_label: String = "%s rank %d" % [label, i + 1]
        var rank_entry = ranks[i]
        if not rank_entry is Dictionary or not rank_entry.get("effects") is Array \
                or rank_entry.get("effects", []).is_empty():
            problems.append("%s: needs a non-empty effects array" % rank_label)
            continue
        _check_effect_refs(rank_entry["effects"], rank_label, effect_by_id, problems)
        if rank_entry.has("cooldown"):
            _check_range(rank_entry, "cooldown", 0.1, 120.0, rank_label, problems)
        var uses := 0
        for ref in rank_entry["effects"]:
            if String(effect_by_id.get(String(ref), {}).get("trigger", "")) == "on_use":
                uses += 1
        if kind == "active" and uses == 0:
            problems.append("%s: active skills need an on_use effect" % rank_label)
        if kind == "passive" and uses > 0:
            problems.append("%s: passive skills cannot have on_use effects" % rank_label)
    if not entry.get("prerequisites", []) is Array:
        problems.append("%s: prerequisites must be an array" % label)
        return
    for prerequisite in entry.get("prerequisites", []):
        var needed: String = _prerequisite_id(prerequisite)
        if needed == label:
            problems.append("%s: lists itself as a prerequisite" % label)
        elif not skill_by_id.has(needed):
            problems.append("%s: unknown prerequisite skill '%s'" % [label, needed])
        else:
            var needed_rank: int = int(prerequisite.get("rank", 1)) if prerequisite is Dictionary else 1
            if needed_rank < 1 or needed_rank > int(skill_by_id[needed].get("max_rank", 1)):
                problems.append("%s: prerequisite rank %d exceeds %s max_rank" % [label, needed_rank, needed])

static func _validate_loot(db: Dictionary, ids: Dictionary, problems: Array[String]) -> void:
    var loot: Dictionary = db.get("loot", {})
    if Array(loot.get("rarity_order", [])) != RARITIES:
        problems.append("loot_tables: rarity_order must be %s" % ", ".join(RARITIES))
    var curve = loot.get("rarity_weights_by_depth", [])
    if not curve is Array or curve.is_empty():
        problems.append("loot_tables: rarity_weights_by_depth must be a non-empty array")
        curve = []
    var previous := 0
    for i in range(curve.size()):
        var band = curve[i]
        var label: String = "loot_tables: depth band %d" % i
        if not band is Dictionary:
            problems.append(label + " is not an object")
            continue
        var depth: int = int(band.get("min_depth", 0))
        if i == 0 and depth != 1:
            problems.append(label + " must start at min_depth 1")
        if depth <= previous:
            problems.append(label + " min_depth must be strictly increasing")
        previous = depth
        var total := 0.0
        for rarity in band.get("weights", {}).keys():
            _check_enum(rarity, RARITIES, label, "weights", problems)
            if float(band["weights"][rarity]) < 0.0:
                problems.append("%s: negative weight for %s" % [label, rarity])
            total += float(band["weights"][rarity])
        if total <= 0.0:
            problems.append(label + " weights must sum above 0")
    var tables: Dictionary = loot.get("tables", {})
    for context_id in LOOT_CONTEXTS:
        if not tables.has(context_id):
            problems.append("loot_tables: missing table '%s'" % context_id)
    for table_id in tables.keys():
        var table: Dictionary = tables[table_id]
        var label: String = "loot table " + String(table_id)
        var rolls = table.get("rolls", 1)
        if rolls is Dictionary:
            if int(rolls.get("min", -1)) < 0 or int(rolls.get("max", -1)) < int(rolls.get("min", 0)) \
                    or int(rolls.get("max", 0)) > 10:
                problems.append(label + ": rolls {min,max} must satisfy 0 <= min <= max <= 10")
        elif not _is_number(rolls) or int(rolls) < 0 or int(rolls) > 10:
            problems.append(label + ": rolls must be 0..10")
        _check_range(table, "empty_chance", 0.0, 1.0, label, problems)
        var low: int = RARITIES.find(String(table.get("min_rarity", "common")))
        var high: int = RARITIES.find(String(table.get("max_rarity", "legendary")))
        if low < 0 or high < 0 or low > high:
            problems.append(label + ": min_rarity/max_rarity unknown or inverted")
        for rarity in table.get("rarity_multipliers", {}).keys():
            _check_enum(rarity, RARITIES, label, "rarity_multipliers", problems)
            if float(table["rarity_multipliers"][rarity]) < 0.0:
                problems.append("%s: negative multiplier for %s" % [label, rarity])
        var sources: Array = table.get("sources", [])
        if sources.is_empty():
            problems.append(label + ": needs at least one source")
        for source in sources:
            var from: String = String(source.get("from", ""))
            _check_enum(from, ["weapons", "items"], label, "sources.from", problems)
            if source.has("kind"):
                _check_enum(source["kind"], ITEM_KINDS, label, "sources.kind", problems)
            if source.has("slot"):
                _check_enum(source["slot"], SLOTS, label, "sources.slot", problems)
            if float(source.get("weight", 0)) <= 0.0:
                problems.append(label + ": source weight must be > 0")
        for excluded in table.get("exclude", []):
            if not ids["weapons"].has(String(excluded)) and not ids["items"].has(String(excluded)):
                problems.append("%s: exclude names unknown id '%s'" % [label, excluded])

static func _check_enum(value, allowed: Array, label: String, field: String,
        problems: Array[String]) -> void:
    if value == null or not allowed.has(String(value)):
        problems.append("%s: invalid %s '%s' (allowed: %s)" % [
            label, field, "" if value == null else String(value), ", ".join(allowed)])

static func _check_range(entry: Dictionary, key: String, low: float, high: float,
        label: String, problems: Array[String], whole: bool = false) -> void:
    var value = entry.get(key)
    if not _is_number(value):
        problems.append("%s: %s must be a number" % [label, key])
    elif float(value) < low or float(value) > high:
        problems.append("%s: %s=%s outside %s..%s" % [label, key, _fmt(float(value)),
            _fmt(low), _fmt(high)])
    elif whole and float(value) != floorf(float(value)):
        problems.append("%s: %s must be a whole number" % [label, key])

static func _require_string(entry: Dictionary, key: String, label: String,
        problems: Array[String]) -> void:
    if not entry.get(key) is String or String(entry.get(key)).strip_edges().is_empty():
        problems.append("%s: %s must be a non-empty string" % [label, key])

static func _fmt(value: float) -> String:
    return str(int(value)) if value == floorf(value) and absf(value) < 1e15 else String.num(value)

static func _is_number(value) -> bool:
    return value is int or value is float

static func _prerequisite_id(prerequisite) -> String:
    if prerequisite is Dictionary:
        return String(prerequisite.get("skill", ""))
    return String(prerequisite)

static func _lookup(kind: String, id: String, db: Dictionary) -> Dictionary:
    var source: Dictionary = db if not db.is_empty() else default_db()
    var index: Dictionary = source.get("index", {})
    if index.is_empty():
        index = build_index(source)
    return index.get(kind, {}).get(id, {})

static func _read_json(path: String, problems: Array[String]) -> Dictionary:
    if not FileAccess.file_exists(path):
        problems.append("%s: file missing" % path)
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        problems.append("%s: not a JSON object" % path)
        return {}
    return parsed
