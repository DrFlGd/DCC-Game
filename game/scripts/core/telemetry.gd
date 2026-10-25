extends Node
## Run telemetry recorder: counts every signal on the bus, times each room, and
## writes one JSON report per finished run to
## `user://telemetry/run-<unix>-<seed>.json`, keeping the newest MAX_FILES.
##
## Never references the Events/RunState identifiers, so tests may preload it.
## The Announcer creates it, calls attach(Events) and, on run_ended, calls
## build_report() + write_report(). Reports are for tuning (GAME_DESIGN.md §10).
const DEFAULT_DIR := "user://telemetry"
const MAX_FILES := 50
const SCHEMA_VERSION := 1

## signal name -> times emitted this run.
var event_counts: Dictionary = {}
## "<depth>:<room_id>" -> seconds spent (run clock, so pauses do not count).
var room_seconds: Dictionary = {}
## [{"id", "at"}] unlocked this run.
var unlocks: Array[Dictionary] = []
## Returns the current run clock in seconds; set by the owner.
var clock: Callable = func() -> float: return 0.0
var _depth := 1
var _room_key := ""
var _room_since := 0.0


## Subscribes to every signal `bus` declares, whatever its arity (0-6 args),
## including signals other teams add later.
func attach(bus: Object) -> void:
    var script: Script = bus.get_script()
    var signals: Array = script.get_script_signal_list() if script != null else bus.get_signal_list()
    for info in signals:
        var name: String = info["name"]
        var handler: Callable
        match (info["args"] as Array).size():
            0: handler = func(): _on_signal(name, [])
            1: handler = func(a): _on_signal(name, [a])
            2: handler = func(a, b): _on_signal(name, [a, b])
            3: handler = func(a, b, c): _on_signal(name, [a, b, c])
            4: handler = func(a, b, c, d): _on_signal(name, [a, b, c, d])
            5: handler = func(a, b, c, d, e): _on_signal(name, [a, b, c, d, e])
            6: handler = func(a, b, c, d, e, f): _on_signal(name, [a, b, c, d, e, f])
            _: continue
        bus.connect(name, handler)


func reset() -> void:
    event_counts.clear()
    room_seconds.clear()
    unlocks.clear()
    _depth = 1
    _room_key = ""
    _room_since = clock.call()


## Closes the open room timer (call before building a report).
func close_room() -> void:
    if _room_key.is_empty():
        return
    var now: float = clock.call()
    room_seconds[_room_key] = float(room_seconds.get(_room_key, 0.0)) + maxf(0.0, now - _room_since)
    _room_since = now


func note_unlock(id: String, unix: int) -> void:
    unlocks.append({"id": id, "at": unix})


## The report written for one run. `announcer_lines` is the brain's history.
func build_report(summary: Dictionary, tick_ledger: Array, announcer_lines: Array,
        unix: int) -> Dictionary:
    close_room()
    var lines: Array = []
    for entry in announcer_lines:
        lines.append({"trigger": entry.get("trigger", ""), "text": entry.get("text", ""),
            "priority": entry.get("priority", 0), "category": entry.get("category", ""),
            "status": entry.get("status", ""), "at": snappedf(float(entry.get("created_at", 0.0)), 0.01)})
    var rounded: Dictionary = {}
    for key in room_seconds:
        rounded[key] = snappedf(float(room_seconds[key]), 0.01)
    return {
        "schema_version": SCHEMA_VERSION, "written_at_unix": unix,
        "seed": int(summary.get("seed", 0)), "outcome": String(summary.get("outcome", "")),
        "summary": summary.duplicate(true), "tick_ledger": tick_ledger.duplicate(true),
        "room_seconds": rounded, "event_counts": event_counts.duplicate(),
        "achievements": unlocks.duplicate(true), "announcer_lines": lines
    }


## Writes `report` to `<dir>/run-<unix>-<seed>.json` (a -2, -3 ... suffix
## avoids clobbering a same-second file), then prunes to `keep` files.
## Returns the path written, or "" on failure.
static func write_report(report: Dictionary, dir: String = DEFAULT_DIR,
        keep: int = MAX_FILES) -> String:
    if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
        push_warning("Cannot create telemetry directory " + dir)
        return ""
    var stem := "run-%d-%d" % [int(report.get("written_at_unix", 0)), int(report.get("seed", 0))]
    var target: String = dir.path_join(stem + ".json")
    var suffix := 2
    while FileAccess.file_exists(target):
        target = dir.path_join("%s-%d.json" % [stem, suffix])
        suffix += 1
    var file := FileAccess.open(target, FileAccess.WRITE)
    if file == null:
        push_warning("Cannot write telemetry %s (%s)" % [target, FileAccess.get_open_error()])
        return ""
    file.store_string(JSON.stringify(report, "  ", false))
    file.close()
    prune(dir, keep)
    return target


## Report files in `dir`, oldest first (by the unix time in the name, then name).
static func list_reports(dir: String = DEFAULT_DIR) -> Array[String]:
    var names: Array[String] = []
    if not DirAccess.dir_exists_absolute(dir):
        return names
    for file in DirAccess.get_files_at(dir):
        if file.begins_with("run-") and file.ends_with(".json"):
            names.append(file)
    names.sort_custom(func(a: String, b: String) -> bool:
        var ta: int = int(a.get_slice("-", 1))
        var tb: int = int(b.get_slice("-", 1))
        return ta < tb if ta != tb else a.naturalnocasecmp_to(b) < 0)
    return names


## Deletes the oldest reports beyond `keep`. Returns how many were removed.
static func prune(dir: String = DEFAULT_DIR, keep: int = MAX_FILES) -> int:
    var names: Array[String] = list_reports(dir)
    var removed := 0
    while names.size() > maxi(0, keep):
        DirAccess.remove_absolute(dir.path_join(names.pop_front()))
        removed += 1
    return removed


func _on_signal(name: String, args: Array) -> void:
    event_counts[name] = int(event_counts.get(name, 0)) + 1
    match name:
        "run_started":
            reset()
            event_counts[name] = 1
        "floor_started":
            close_room()
            _room_key = ""
            _depth = int(args[0]) if not args.is_empty() else _depth
        "room_entered":
            close_room()
            _room_key = "%d:%d" % [_depth, int(args[0]) if not args.is_empty() else 0]
            _room_since = clock.call()
