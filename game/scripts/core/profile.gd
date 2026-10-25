extends RefCounted
## The persistent player profile: `user://profile.json`.
## Pure file IO and bookkeeping; no nodes, no autoloads, so the title screen,
## CharacterMenu and tests may preload it:
##   const Profile = preload("res://scripts/core/profile.gd")
##   Profile.best_depth(); Profile.total_runs(); Profile.is_unlocked("first_blood")
##
## Shape (version 1):
##   {"version": 1,
##    "achievements": {"<id>": {"unlocked_at": <unix>, "seed": <int>}},
##    "stats": {"runs", "best_depth", "total_kills", "total_floors", "victories",
##              "collapses", "total_run_seconds", "deaths_by_cause": {"<cause>": n}},
##    "last_seed": <int>, "last_outcome": "<outcome>", "updated_at": <unix>}
## Presentation only (GAME_DESIGN.md §4): nothing here changes a run.
## A missing file loads as a blank profile; an unreadable one is renamed to
## `<path>.corrupt` and replaced by a blank profile on the next save.
const DEFAULT_PATH := "user://profile.json"
const VERSION := 1
const STAT_DEFAULTS := {
    "runs": 0, "best_depth": 0, "total_kills": 0, "total_floors": 0, "victories": 0,
    "collapses": 0, "total_run_seconds": 0.0, "deaths_by_cause": {}
}
const VICTORY_OUTCOMES := ["escaped", "victory"]

## File used by current()/save_current() and the accessors.
static var profile_path := DEFAULT_PATH
static var _cache: Dictionary = {}


## Points the shared profile at another file (tests) and drops the cache.
static func use_path(new_path: String) -> void:
    profile_path = new_path
    _cache = {}


static func blank() -> Dictionary:
    return {"version": VERSION, "achievements": {}, "stats": STAT_DEFAULTS.duplicate(true),
        "last_seed": 0, "last_outcome": "", "updated_at": 0}


## Reads a profile from `file_path`, never failing: see the class notes.
static func load_profile(file_path: String = "") -> Dictionary:
    var target: String = file_path if not file_path.is_empty() else profile_path
    if not FileAccess.file_exists(target):
        return blank()
    var text: String = FileAccess.get_file_as_string(target)
    var json := JSON.new()
    var ok: bool = json.parse(text) == OK and json.data is Dictionary
    if not ok:
        push_warning("Profile %s is unreadable; keeping it as .corrupt and starting fresh" % target)
        DirAccess.remove_absolute(target + ".corrupt")
        DirAccess.rename_absolute(target, target + ".corrupt")
        return blank()
    return normalise(json.data)


## Fills missing fields and coerces types so callers can index freely.
static func normalise(raw: Dictionary) -> Dictionary:
    var result: Dictionary = blank()
    if raw.get("achievements") is Dictionary:
        for id in raw["achievements"]:
            var record = raw["achievements"][id]
            if record is Dictionary:
                result["achievements"][String(id)] = {
                    "unlocked_at": int(record.get("unlocked_at", 0)),
                    "seed": int(record.get("seed", 0))}
    if raw.get("stats") is Dictionary:
        var stats: Dictionary = raw["stats"]
        for key in STAT_DEFAULTS:
            if key == "deaths_by_cause":
                if stats.get(key) is Dictionary:
                    for cause in stats[key]:
                        result["stats"][key][String(cause)] = int(stats[key][cause])
            elif key == "total_run_seconds":
                result["stats"][key] = float(stats.get(key, 0.0))
            elif stats.has(key):
                result["stats"][key] = int(stats[key])
    result["last_seed"] = int(raw.get("last_seed", 0))
    result["last_outcome"] = String(raw.get("last_outcome", ""))
    result["updated_at"] = int(raw.get("updated_at", 0))
    return result


## Writes `data` as JSON via a temporary file. Returns false on failure.
static func save_profile(data: Dictionary, file_path: String = "") -> bool:
    var target: String = file_path if not file_path.is_empty() else profile_path
    DirAccess.make_dir_recursive_absolute(target.get_base_dir())
    var temp: String = target + ".tmp"
    var file := FileAccess.open(temp, FileAccess.WRITE)
    if file == null:
        push_warning("Cannot write profile %s (%s)" % [temp, FileAccess.get_open_error()])
        return false
    file.store_string(JSON.stringify(data, "  ", true))
    file.close()
    if FileAccess.file_exists(target):
        DirAccess.remove_absolute(target)
    if DirAccess.rename_absolute(temp, target) != OK:
        push_warning("Cannot move profile into place at " + target)
        return false
    return true


## Records a finished run (mutates `data`). `cause` is the killer id for a
## defeat; collapses count under "collapse". Call once per run_ended.
static func record_run(data: Dictionary, summary: Dictionary, outcome: String,
        cause: String = "", floors_cleared: int = 0, unix: int = -1) -> void:
    var stats: Dictionary = data["stats"]
    stats["runs"] = int(stats["runs"]) + 1
    stats["best_depth"] = maxi(int(stats["best_depth"]), int(summary.get("depth", 0)))
    stats["total_kills"] = int(stats["total_kills"]) + int(summary.get("kills", 0))
    stats["total_floors"] = int(stats["total_floors"]) + maxi(0, floors_cleared)
    stats["total_run_seconds"] = float(stats["total_run_seconds"]) + \
        float(summary.get("run_time_seconds", 0.0))
    if VICTORY_OUTCOMES.has(outcome):
        stats["victories"] = int(stats["victories"]) + 1
    elif outcome == "collapsed":
        stats["collapses"] = int(stats["collapses"]) + 1
        _count_death(stats, "collapse")
    elif outcome == "defeated":
        _count_death(stats, cause if not cause.is_empty() else "unknown")
    data["last_seed"] = int(summary.get("seed", 0))
    data["last_outcome"] = outcome
    data["updated_at"] = unix if unix >= 0 else int(Time.get_unix_time_from_system())


## Marks `id` unlocked (mutates `data`). Returns false if it already was.
static func unlock(data: Dictionary, id: String, seed_value: int = 0, unix: int = -1) -> bool:
    if data["achievements"].has(id):
        return false
    var at: int = unix if unix >= 0 else int(Time.get_unix_time_from_system())
    data["achievements"][id] = {"unlocked_at": at, "seed": seed_value}
    data["updated_at"] = at
    return true


# --- Shared, cached profile (what the game and menus use) -------------------

## The profile at `path`, loaded on first use and shared by every caller.
static func current() -> Dictionary:
    if _cache.is_empty():
        _cache = load_profile(profile_path)
    return _cache


static func save_current() -> bool:
    return save_profile(current(), profile_path)


## Re-reads the file on the next current() call. (Not `reload`: that name is
## GDScript.reload(), which would recompile this script and reset its statics.)
static func refresh() -> void:
    _cache = {}


static func best_depth() -> int:
    return int(current()["stats"]["best_depth"])


static func total_runs() -> int:
    return int(current()["stats"]["runs"])


static func total_kills() -> int:
    return int(current()["stats"]["total_kills"])


static func total_floors() -> int:
    return int(current()["stats"]["total_floors"])


static func victories() -> int:
    return int(current()["stats"]["victories"])


static func deaths_by_cause() -> Dictionary:
    return (current()["stats"]["deaths_by_cause"] as Dictionary).duplicate()


static func last_seed() -> int:
    return int(current()["last_seed"])


## id -> {"unlocked_at", "seed"}.
static func unlocked() -> Dictionary:
    return (current()["achievements"] as Dictionary).duplicate(true)


static func is_unlocked(id: String) -> bool:
    return current()["achievements"].has(id)


static func stats() -> Dictionary:
    return (current()["stats"] as Dictionary).duplicate(true)


static func _count_death(stats: Dictionary, cause: String) -> void:
    var deaths: Dictionary = stats["deaths_by_cause"]
    deaths[cause] = int(deaths.get(cause, 0)) + 1
