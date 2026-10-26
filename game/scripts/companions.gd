extends RefCounted
## Companion catalogue (res://data/companions.json, schema v1) for the Wave 3E
## follower prototype (D-10, COMBAT_AND_RPG §13). Static loader and validator
## in the style of content/content_db.gd.
##
## Pure logic: no autoloads and no nodes, so tests may preload this script.
## A companion record (keyed by a `cmp_` id):
##   name, description, adaptation_type ("original"), sprite (res:// sheet of
##   5 frames E, S, W, N, downed), frame [w, h], render [w, h], radius (px),
##   hp, hp_per_level (added per crawler level above 1), ac, speed (px/s),
##   return_speed_mult, follow_distance, leash_distance, engage_radius (px from
##   the crawler), stuck_seconds, hit_iframes, scores (six abilities),
##   attacks (enemies.json schema v2 attack records; the prototype supports
##   type "melee": id, telegraph, arc, ability, proficient, range, cooldown,
##   wind_up, recovery, damage_die, damage_bonus, damage_type, knockback),
##   revive {radius, channel_seconds, hp_ratio, auto_seconds (0 = never),
##   on_floor_start}, crawler_buffs {pickup_radius}, lines {spawned, downed,
##   revived, stay, follow} (original announcer text).
const RPG = preload("res://scripts/rpg_rules.gd")

const SCHEMA_VERSION := 1
const CATALOGUE_PATH := "res://data/companions.json"
const DEFAULT_ID := "cmp_scrap_hound"
const REQUIRED_NUMBERS := ["hp", "ac", "speed", "follow_distance", "leash_distance",
    "engage_radius", "radius"]
const ATTACK_TYPES := ["melee"]
const DAMAGE_TYPES := ["physical", "fire", "toxic", "arcane"]
const LINE_KEYS := ["downed", "revived"]

static var _cache: Dictionary = {}


static func load_catalogue(path: String = CATALOGUE_PATH) -> Dictionary:
    if path == CATALOGUE_PATH and not _cache.is_empty():
        return _cache
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    var result: Dictionary = parsed if parsed is Dictionary else {}
    if path == CATALOGUE_PATH:
        _cache = result
    return result


## The record for `companion_id` (read-only; duplicate to edit), or {}.
static func definition(companion_id: String = DEFAULT_ID) -> Dictionary:
    return load_catalogue().get("companions", {}).get(companion_id, {})


## First attack record (the prototype companion has one bite).
static func primary_attack(record: Dictionary) -> Dictionary:
    var attacks: Array = record.get("attacks", [])
    return attacks[0] if not attacks.is_empty() else {}


## Human-readable problems; empty means valid.
static func validate(catalogue: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    if int(catalogue.get("schema_version", 0)) != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    var records = catalogue.get("companions", {})
    if not records is Dictionary or records.is_empty():
        problems.append("companions must be a non-empty dictionary")
        return problems
    for id in records.keys():
        _validate_record(String(id), records[id], problems)
    return problems


static func _validate_record(id: String, data, problems: Array[String]) -> void:
    if not id.begins_with("cmp_"):
        problems.append("%s: ids start with cmp_" % id)
    if not data is Dictionary:
        problems.append("%s: record must be a dictionary" % id)
        return
    for key in ["name", "description", "sprite"]:
        if String(data.get(key, "")).strip_edges() == "":
            problems.append("%s: %s is required" % [id, key])
    if String(data.get("adaptation_type", "original")) != "original":
        problems.append("%s: companions must be original content" % id)
    var sprite: String = String(data.get("sprite", ""))
    if sprite != "" and not FileAccess.file_exists(sprite):
        problems.append("%s: sprite %s does not exist" % [id, sprite])
    for key in REQUIRED_NUMBERS:
        if not (data.get(key) is float or data.get(key) is int) or float(data[key]) <= 0.0:
            problems.append("%s: %s must be a positive number" % [id, key])
    if float(data.get("leash_distance", 0)) <= float(data.get("follow_distance", 0)):
        problems.append("%s: leash_distance must exceed follow_distance" % id)
    var scores = data.get("scores", {})
    if not scores is Dictionary:
        problems.append("%s: scores must be a dictionary" % id)
    else:
        for ability in RPG.ABILITIES:
            if not scores.has(ability):
                problems.append("%s: scores.%s is missing" % [id, ability])
    var attacks = data.get("attacks", [])
    if not attacks is Array or attacks.is_empty():
        problems.append("%s: needs at least one attack" % id)
    else:
        for attack in attacks:
            _validate_attack(id, attack, problems)
    var revive = data.get("revive", {})
    if not revive is Dictionary:
        problems.append("%s: revive must be a dictionary" % id)
    else:
        if float(revive.get("radius", 0)) <= 0.0 or float(revive.get("channel_seconds", 0)) <= 0.0:
            problems.append("%s: revive.radius and revive.channel_seconds must be positive" % id)
        var ratio: float = float(revive.get("hp_ratio", 0))
        if ratio <= 0.0 or ratio > 1.0:
            problems.append("%s: revive.hp_ratio must be in (0, 1]" % id)
        if float(revive.get("auto_seconds", 0)) < 0.0:
            problems.append("%s: revive.auto_seconds must be >= 0" % id)
    var lines = data.get("lines", {})
    for key in LINE_KEYS:
        var entries = lines.get(key, []) if lines is Dictionary else []
        if not entries is Array or entries.is_empty():
            problems.append("%s: lines.%s needs at least one line" % [id, key])
            continue
        for line in entries:
            if not line is String or String(line).strip_edges() == "":
                problems.append("%s: lines.%s holds an empty line" % [id, key])


static func _validate_attack(id: String, attack, problems: Array[String]) -> void:
    if not attack is Dictionary:
        problems.append("%s: attacks hold dictionaries" % id)
        return
    var label: String = "%s.%s" % [id, String(attack.get("id", "?"))]
    if String(attack.get("id", "")) == "":
        problems.append("%s: attack id is required" % label)
    if not ATTACK_TYPES.has(String(attack.get("type", ""))):
        problems.append("%s: type must be one of %s" % [label, ATTACK_TYPES])
    if not RPG.ABILITIES.has(String(attack.get("ability", "STR"))):
        problems.append("%s: unknown ability" % label)
    if not DAMAGE_TYPES.has(String(attack.get("damage_type", "physical"))):
        problems.append("%s: unknown damage_type" % label)
    for key in ["range", "cooldown", "damage_die"]:
        if float(attack.get(key, 0)) <= 0.0:
            problems.append("%s: %s must be positive" % [label, key])
    for key in ["wind_up", "recovery", "knockback"]:
        if float(attack.get(key, 0)) < 0.0:
            problems.append("%s: %s must be >= 0" % [label, key])
