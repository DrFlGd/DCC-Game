extends RefCounted
## Loader, validator and template resolver for `data/announcer.json`, the
## dungeon-system announcer's script. Pure logic: no nodes, no autoloads, so
## tests may preload it.
##
## File shape:
##   {"schema_version": 1, "settings": {...}, "lines": {"<trigger>": [<line>, ...]}}
## A line is {"text", "weight", "priority", "cooldown_seconds", "once_per_run",
## "category"}. `text` may contain `{placeholders}` (see placeholders_for()).
## Triggers are fixed keys (FIXED_TRIGGERS), `room_entered.<kind>` for every
## ROOM_KINDS entry, `kill_streak.<n>` for every settings threshold, and the
## optional `enemy_killed.<definition_id>`.
const PATH := "res://data/announcer.json"
const SCHEMA_VERSION := 1
const CATEGORIES := ["flavour", "warning", "celebration", "sponsor", "taunt", "obituary",
    "achievement", "system"]
## Room kinds the announcer knows. treasure/trap/shrine/elite arrive with 2E.
const ROOM_KINDS := ["start", "normal", "boss", "guild_hall", "exit", "treasure", "trap",
    "shrine", "elite"]
## Every trigger with a fixed name. Required unless listed in OPTIONAL_TRIGGERS.
const FIXED_TRIGGERS := ["run_started", "floor_started", "first_blood", "level_up", "low_hp",
    "player_damaged_big", "boss_room_entered", "boss_defeated", "floor_cleared", "ticks_low",
    "grace_started", "grace_stabilised", "run_ended.defeated", "run_ended.collapsed",
    "run_ended.victory", "run_ended.abandoned", "idle", "chest_opened", "shrine_used",
    "guild_rested", "achievement_unlocked", "hazard_spawned", "room_cleared"]
const OPTIONAL_TRIGGERS := ["run_ended.abandoned", "hazard_spawned"]
## Triggers that fire often enough to need at least COMMON_MINIMUM variants.
## Every other required trigger needs REQUIRED_MINIMUM.
const COMMON_TRIGGERS := ["run_started", "floor_started", "room_entered.normal", "first_blood",
    "level_up", "low_hp", "player_damaged_big", "boss_room_entered", "boss_defeated",
    "floor_cleared", "ticks_low", "grace_started", "grace_stabilised", "run_ended.defeated",
    "run_ended.collapsed", "run_ended.victory", "idle", "chest_opened", "shrine_used",
    "guild_rested", "achievement_unlocked"]
const COMMON_MINIMUM := 5
const REQUIRED_MINIMUM := 3
## Placeholders every trigger may use (filled from RunState by the Announcer).
const GLOBAL_PLACEHOLDERS := ["depth", "kills", "ticks", "seed", "level", "hp", "max_hp", "xp",
    "room"]
## Extra placeholders, by trigger or trigger prefix (the part before the dot).
const TRIGGER_PLACEHOLDERS := {
    "first_blood": ["enemy"], "enemy_killed": ["enemy"], "boss_defeated": ["enemy"],
    "player_damaged_big": ["enemy", "damage"], "run_ended.defeated": ["enemy"],
    "kill_streak": ["streak"], "achievement_unlocked": ["achievement", "quip"],
    "idle": ["idle"]
}
const LINE_KEYS := ["text", "weight", "priority", "cooldown_seconds", "once_per_run", "category"]
const MAX_SEGMENTS := 2
const MAX_SEGMENT_CHARS := 90
## Defaults for every scheduling and detection setting; data may override.
const DEFAULT_SETTINGS := {
    "rate_limit_seconds": 2.5, "bypass_priority": 4, "max_visible": 2,
    "min_on_screen_seconds": 1.0, "toast_seconds": 2.5, "toast_max_seconds": 5.0,
    "seconds_per_char": 0.04, "fade_seconds": 0.4, "queue_size": 8, "queue_ttl_seconds": 4.0,
    "log_size": 50, "idle_seconds": 25.0, "kill_streak_thresholds": [3, 5, 8, 12],
    "low_hp_fraction": 0.3, "low_hp_rearm_fraction": 0.5, "big_hit_fraction": 0.25,
    "ticks_low": 4
}
## Inclusive numeric range for each scalar setting.
const SETTING_RANGES := {
    "rate_limit_seconds": [0.0, 30.0], "bypass_priority": [1, 5], "max_visible": [1, 4],
    "min_on_screen_seconds": [0.0, 10.0], "toast_seconds": [0.5, 10.0],
    "toast_max_seconds": [0.5, 20.0], "seconds_per_char": [0.0, 0.5], "fade_seconds": [0.0, 2.0],
    "queue_size": [1, 64], "queue_ttl_seconds": [0.5, 60.0], "log_size": [1, 500],
    "idle_seconds": [5.0, 600.0], "low_hp_fraction": [0.01, 0.99],
    "low_hp_rearm_fraction": [0.01, 1.0], "big_hit_fraction": [0.01, 1.0], "ticks_low": [1, 50]
}


## Parses `path`; returns {} when the file is missing or not a JSON object.
static func load_data(path: String = PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


static func settings_with_defaults(raw: Dictionary) -> Dictionary:
    var result: Dictionary = DEFAULT_SETTINGS.duplicate(true)
    for key in raw:
        result[key] = raw[key]
    return result


## True if `trigger` is a key the Announcer can fire.
static func is_known_trigger(trigger: String, settings: Dictionary) -> bool:
    if FIXED_TRIGGERS.has(trigger):
        return true
    var parts: PackedStringArray = trigger.split(".", false, 1)
    if parts.size() != 2:
        return false
    match parts[0]:
        "room_entered":
            return ROOM_KINDS.has(parts[1])
        "kill_streak":
            return parts[1].is_valid_int() and _thresholds(settings).has(int(parts[1]))
        "enemy_killed":
            return _is_identifier(parts[1])
    return false


## Placeholders that `trigger` may reference.
static func placeholders_for(trigger: String) -> Array:
    var allowed: Array = GLOBAL_PLACEHOLDERS.duplicate()
    allowed.append_array(TRIGGER_PLACEHOLDERS.get(trigger, []))
    var prefix: String = trigger.get_slice(".", 0)
    if prefix != trigger:
        allowed.append_array(TRIGGER_PLACEHOLDERS.get(prefix, []))
    return allowed


## Names inside `{...}` in `text`, in order of appearance.
static func placeholders(text: String) -> Array[String]:
    var found: Array[String] = []
    var regex := RegEx.create_from_string("\\{([a-z_]+)\\}")
    for match in regex.search_all(text):
        found.append(match.get_string(1))
    return found


## Replaces each `{name}` with str(context[name]); unknown names become "?".
static func resolve(text: String, context: Dictionary) -> String:
    var regex := RegEx.create_from_string("\\{([a-z_]+)\\}")
    var result := ""
    var cursor := 0
    for match in regex.search_all(text):
        result += text.substr(cursor, match.get_start() - cursor)
        var key: String = match.get_string(1)
        result += str(context[key]) if context.has(key) else "?"
        cursor = match.get_end()
    return result + text.substr(cursor)


## Every problem in `data`, as human-readable strings. Empty means valid.
static func validate(data: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    var raw_settings = data.get("settings", {})
    if not raw_settings is Dictionary:
        problems.append("settings must be an object")
        raw_settings = {}
    problems.append_array(_validate_settings(raw_settings))
    var settings: Dictionary = settings_with_defaults(raw_settings)
    var lines = data.get("lines", null)
    if not lines is Dictionary:
        problems.append("lines must be an object of trigger -> array")
        return problems
    var seen_texts: Dictionary = {}
    for trigger in lines:
        var key := String(trigger)
        if not is_known_trigger(key, settings):
            problems.append("unknown trigger '%s'" % key)
            continue
        if not lines[trigger] is Array:
            problems.append("%s: lines must be an array" % key)
            continue
        var index := 0
        for line in lines[trigger]:
            problems.append_array(_validate_line(key, index, line, seen_texts))
            index += 1
    for trigger in required_triggers(settings):
        var count: int = lines[trigger].size() if lines.get(trigger) is Array else 0
        var minimum: int = COMMON_MINIMUM if COMMON_TRIGGERS.has(trigger) else REQUIRED_MINIMUM
        if count < minimum:
            problems.append("%s needs at least %d lines (has %d)" % [trigger, minimum, count])
    return problems


## Triggers that must have lines for `settings` (thresholds decide kill_streak keys).
static func required_triggers(settings: Dictionary) -> Array[String]:
    var result: Array[String] = []
    for trigger in FIXED_TRIGGERS:
        if not OPTIONAL_TRIGGERS.has(trigger):
            result.append(trigger)
    for kind in ROOM_KINDS:
        result.append("room_entered." + kind)
    for threshold in _thresholds(settings):
        result.append("kill_streak.%d" % threshold)
    return result


## trigger -> number of lines.
static func count_lines(data: Dictionary) -> Dictionary:
    var counts: Dictionary = {}
    var lines: Dictionary = data.get("lines", {})
    for trigger in lines:
        counts[trigger] = (lines[trigger] as Array).size()
    return counts


static func _validate_settings(raw: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    for key in raw:
        if not DEFAULT_SETTINGS.has(key):
            problems.append("settings: unknown key '%s'" % key)
    for key in SETTING_RANGES:
        if not raw.has(key):
            continue
        var value = raw[key]
        var bounds: Array = SETTING_RANGES[key]
        if not (value is int or value is float):
            problems.append("settings.%s must be a number" % key)
        elif float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
            problems.append("settings.%s must be in [%s, %s]" % [key, bounds[0], bounds[1]])
    if raw.has("kill_streak_thresholds"):
        var thresholds = raw["kill_streak_thresholds"]
        var ok: bool = thresholds is Array and not thresholds.is_empty()
        var previous := 1
        if ok:
            for value in thresholds:
                if not (value is int or value is float) or int(value) != float(value) \
                        or int(value) <= previous:
                    ok = false
                    break
                previous = int(value)
        if not ok:
            problems.append("settings.kill_streak_thresholds must be ascending integers >= 2")
    return problems


static func _validate_line(trigger: String, index: int, line, seen_texts: Dictionary) -> Array[String]:
    var where := "%s[%d]" % [trigger, index]
    if not line is Dictionary:
        return [where + " must be an object"]
    var problems: Array[String] = []
    for key in line:
        if not LINE_KEYS.has(key):
            problems.append("%s: unknown key '%s'" % [where, key])
    var text = line.get("text")
    if not text is String or String(text).strip_edges().is_empty():
        problems.append(where + ": text must be a non-empty string")
    else:
        var segments: PackedStringArray = String(text).split("\n")
        if segments.size() > MAX_SEGMENTS:
            problems.append("%s: at most %d lines of text" % [where, MAX_SEGMENTS])
        for segment in segments:
            if segment.length() > MAX_SEGMENT_CHARS:
                problems.append("%s: text line longer than %d characters" % [where, MAX_SEGMENT_CHARS])
        var normal: String = String(text).strip_edges().to_lower()
        if seen_texts.has(normal):
            problems.append("%s: duplicate text (also %s)" % [where, seen_texts[normal]])
        else:
            seen_texts[normal] = where
        var opens: int = String(text).count("{")
        if opens != String(text).count("}") or opens != placeholders(text).size():
            problems.append(where + ": malformed {placeholder}")
        var allowed: Array = placeholders_for(trigger)
        for name in placeholders(text):
            if not allowed.has(name):
                problems.append("%s: placeholder {%s} not available for this trigger" % [where, name])
    problems.append_array(_check_number(line, "weight", where, 0.01, 100.0, false))
    problems.append_array(_check_number(line, "priority", where, 1, 5, true))
    problems.append_array(_check_number(line, "cooldown_seconds", where, 0.0, 600.0, false))
    if not line.get("once_per_run") is bool:
        problems.append(where + ": once_per_run must be true or false")
    if not CATEGORIES.has(line.get("category")):
        problems.append("%s: category must be one of %s" % [where, CATEGORIES])
    return problems


static func _check_number(line: Dictionary, key: String, where: String, low: float, high: float,
        integer: bool) -> Array[String]:
    var value = line.get(key)
    if not (value is int or value is float):
        return ["%s: %s must be a number" % [where, key]]
    if integer and float(value) != float(int(value)):
        return ["%s: %s must be a whole number" % [where, key]]
    if float(value) < low or float(value) > high:
        return ["%s: %s must be in [%s, %s]" % [where, key, low, high]]
    return []


static func _thresholds(settings: Dictionary) -> Array:
    var result: Array = []
    for value in settings.get("kill_streak_thresholds", DEFAULT_SETTINGS["kill_streak_thresholds"]):
        result.append(int(value))
    return result


static func _is_identifier(value: String) -> bool:
    return RegEx.create_from_string("^[a-z0-9_]+$").search(value) != null
