extends RefCounted
## Data-defined achievements (`data/achievements.json`): tracking and rules.
## Pure logic: no nodes, no autoloads, so tests and CharacterMenu may preload it.
##
## A definition is {"id", "title", "description", "quip", "event", "requires",
## "secret"}. It is checked whenever an event of type `event` is observed;
## `requires` maps a snapshot key to one comparison, {"<op>": value}, with op
## one of OPERATORS, and every comparison must hold. Keys starting with
## "event." read the event's own fields instead of the snapshot.
##
## Flow (the Announcer does this for every Events signal):
##   observe(tracker, event)                       # per-run counters
##   snap := build_snapshot(tracker, live, lifetime, unlocked)
##   evaluate(snap, event) -> ids unlocked by this event (never already-unlocked)
##
## Event dictionaries: {"type": <signal name>, "time": run seconds, ...fields}.
## Fields used: enemy_killed.definition_id, player_damaged.amount/.source,
## player_died.cause, room_entered.kind/.first_visit/.door, floor_started.depth,
## floor_cleared.depth, level_up.level, run_ended.outcome.
const PATH := "res://data/achievements.json"
const SCHEMA_VERSION := 1
const OPERATORS := [">=", "<=", ">", "<", "==", "!=", "in", "contains"]
const EVENTS := ["run_started", "floor_started", "room_entered", "room_cleared",
    "enemy_killed", "player_damaged", "player_died", "level_up", "boss_defeated",
    "floor_cleared", "run_ended", "ticks_changed", "chest_opened", "shrine_used",
    "guild_rested", "grace_started", "grace_ended", "hazard_spawned", "item_picked_up"]
## Per-run counters kept by observe().
const TRACKER_KEYS := ["run.kills", "run.streak", "run.doors", "run.chests", "run.shrines",
    "run.guild_rests", "run.graces", "run.floors_cleared", "run.cause", "room.kills",
    "room.damage_taken", "floor.damage_taken", "floor.revisits", "floor.start_time"]
## Keys build_snapshot() adds from live RunState values and the profile.
const LIVE_KEYS := ["hp", "max_hp", "hp_fraction", "ticks", "depth", "level", "outcome",
    "seed", "run_time", "floor.seconds", "life.kills", "life.runs", "life.floors"]
const FIELDS := ["id", "title", "description", "quip", "event", "requires", "secret"]

static var _definitions: Array = []


## The shipped definitions, parsed once and cached.
static func default_definitions() -> Array:
    if _definitions.is_empty():
        _definitions = load_definitions()
    return _definitions


## Parses `path`; returns [] when missing or malformed.
static func load_definitions(path: String = PATH) -> Array:
    if not FileAccess.file_exists(path):
        return []
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary or not parsed.get("achievements") is Array:
        return []
    return parsed["achievements"]


## id -> definition.
static func by_id(definitions: Array = []) -> Dictionary:
    var result: Dictionary = {}
    for definition in (definitions if not definitions.is_empty() else default_definitions()):
        result[String(definition.get("id", ""))] = definition
    return result


## Every problem in the parsed file `data`; empty means valid.
static func validate(data: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    var list = data.get("achievements")
    if not list is Array:
        problems.append("achievements must be an array")
        return problems
    var ids: Dictionary = {}
    var titles: Dictionary = {}
    var index := 0
    for definition in list:
        var where := "achievements[%d]" % index
        index += 1
        if not definition is Dictionary:
            problems.append(where + " must be an object")
            continue
        for key in definition:
            if not FIELDS.has(key):
                problems.append("%s: unknown key '%s'" % [where, key])
        var id = definition.get("id")
        if not id is String or not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
            problems.append(where + ": id must be lower_snake_case")
        elif ids.has(id):
            problems.append("%s: duplicate id '%s'" % [where, id])
        else:
            ids[id] = true
            where = "achievement '%s'" % id
        for key in ["title", "description", "quip"]:
            var value = definition.get(key)
            if not value is String or String(value).strip_edges().is_empty():
                problems.append("%s: %s must be a non-empty string" % [where, key])
            elif String(value).length() > 90:
                problems.append("%s: %s longer than 90 characters" % [where, key])
        var title = definition.get("title", "")
        if title is String and titles.has(title):
            problems.append("%s: duplicate title '%s'" % [where, title])
        titles[title] = true
        if not EVENTS.has(definition.get("event")):
            problems.append("%s: event must be one of %s" % [where, EVENTS])
        if not definition.get("secret", false) is bool:
            problems.append(where + ": secret must be true or false")
        var requires = definition.get("requires", {})
        if not requires is Dictionary:
            problems.append(where + ": requires must be an object")
            continue
        for key in requires:
            if not _known_key(String(key)):
                problems.append("%s: unknown requirement key '%s'" % [where, key])
            var test = requires[key]
            if not test is Dictionary or test.size() != 1 or not OPERATORS.has(test.keys()[0]):
                problems.append("%s: requirement '%s' must be {\"<op>\": value}" % [where, key])
            elif test.keys()[0] in ["in"] and not test.values()[0] is Array:
                problems.append("%s: 'in' needs an array" % where)
    return problems


## Fresh per-run counters.
static func new_tracker() -> Dictionary:
    var tracker: Dictionary = {}
    for key in TRACKER_KEYS:
        tracker[key] = 0
    tracker["run.cause"] = ""
    tracker["floor.start_time"] = 0.0
    return tracker


## Folds `event` into `tracker` (mutates it). run_started resets everything,
## floor_started the floor counters, room_entered the room counters.
static func observe(tracker: Dictionary, event: Dictionary) -> void:
    var time: float = float(event.get("time", 0.0))
    match String(event.get("type", "")):
        "run_started":
            tracker.merge(new_tracker(), true)
        "floor_started":
            tracker["floor.damage_taken"] = 0
            tracker["floor.revisits"] = 0
            tracker["floor.start_time"] = time
            _reset_room(tracker)
        "room_entered":
            if bool(event.get("door", true)):
                _bump(tracker, "run.doors")
            if not bool(event.get("first_visit", true)):
                _bump(tracker, "floor.revisits")
            _reset_room(tracker)
        "enemy_killed":
            _bump(tracker, "run.kills")
            _bump(tracker, "run.streak")
            _bump(tracker, "room.kills")
        "player_damaged":
            var amount: int = maxi(0, int(event.get("amount", 0)))
            _bump(tracker, "room.damage_taken", amount)
            _bump(tracker, "floor.damage_taken", amount)
            tracker["run.streak"] = 0
        "player_died":
            tracker["run.cause"] = String(event.get("cause", ""))
        "floor_cleared":
            _bump(tracker, "run.floors_cleared")
        "chest_opened":
            _bump(tracker, "run.chests")
        "shrine_used":
            _bump(tracker, "run.shrines")
        "guild_rested":
            _bump(tracker, "run.guild_rests")
        "grace_ended":
            _bump(tracker, "run.graces")


## The dictionary evaluate() reads. `live` holds hp, max_hp, ticks, depth,
## level, outcome, seed and run_time; `lifetime` is Profile stats from before
## this run; `unlocked` is id -> anything for achievements already earned.
static func build_snapshot(tracker: Dictionary, live: Dictionary, lifetime: Dictionary,
        unlocked: Dictionary) -> Dictionary:
    var snap: Dictionary = tracker.duplicate(true)
    snap.merge(live, true)
    var max_hp: int = maxi(1, int(live.get("max_hp", 1)))
    snap["hp_fraction"] = float(live.get("hp", 0)) / float(max_hp)
    snap["floor.seconds"] = float(live.get("run_time", 0.0)) - float(tracker.get("floor.start_time", 0.0))
    snap["life.kills"] = int(lifetime.get("total_kills", 0)) + int(tracker.get("run.kills", 0))
    var finished: int = 0 if String(live.get("outcome", "running")) == "running" else 1
    snap["life.runs"] = int(lifetime.get("runs", 0)) + finished
    snap["life.floors"] = int(lifetime.get("total_floors", 0)) + int(tracker.get("run.floors_cleared", 0))
    snap["unlocked"] = unlocked
    return snap


## Ids whose `event` matches event.type, whose requirements hold, and which are
## not in state_snapshot.unlocked. Each id appears at most once.
static func evaluate(state_snapshot: Dictionary, event: Dictionary,
        definitions: Array = []) -> Array[String]:
    var unlocked: Dictionary = state_snapshot.get("unlocked", {})
    var result: Array[String] = []
    var type: String = String(event.get("type", ""))
    for definition in (definitions if not definitions.is_empty() else default_definitions()):
        var id: String = String(definition.get("id", ""))
        if id.is_empty() or unlocked.has(id) or result.has(id):
            continue
        if String(definition.get("event", "")) != type:
            continue
        if requirements_met(definition.get("requires", {}), state_snapshot, event):
            result.append(id)
    return result


static func requirements_met(requires: Dictionary, snap: Dictionary, event: Dictionary) -> bool:
    for key in requires:
        var name := String(key)
        var have = event.get(name.substr(6)) if name.begins_with("event.") else snap.get(name)
        var test: Dictionary = requires[key]
        if not compare(have, String(test.keys()[0]), test.values()[0]):
            return false
    return true


static func compare(have, op: String, want) -> bool:
    if have == null:
        return false
    match op:
        "contains":
            return String(want) in String(have)
        "in":
            return want is Array and (want.has(have) or want.has(str(have)))
        "==", "!=":
            var same: bool
            if (have is int or have is float) and (want is int or want is float):
                same = is_equal_approx(float(have), float(want))
            else:
                same = str(have) == str(want)
            return same if op == "==" else not same
    if not (have is int or have is float or have is bool) or not (want is int or want is float):
        return false
    var a: float = float(have)
    var b: float = float(want)
    match op:
        ">=": return a >= b
        "<=": return a <= b
        ">": return a > b
        "<": return a < b
    return false


static func _known_key(key: String) -> bool:
    return key.begins_with("event.") or TRACKER_KEYS.has(key) or LIVE_KEYS.has(key)


static func _reset_room(tracker: Dictionary) -> void:
    tracker["room.kills"] = 0
    tracker["room.damage_taken"] = 0


static func _bump(tracker: Dictionary, key: String, amount: int = 1) -> void:
    tracker[key] = int(tracker.get(key, 0)) + amount
