extends RefCounted
## Build version for display: `config/version` from project.godot plus the
## commit stamped into res://version.json by tools/stamp_version.py (CI does
## this before exporting; the committed file says "dev"). Pure and static, no
## autoloads, so tests may preload it.

const PATH := "res://version.json"


## {version, commit, built_at}; falls back to the project version and "dev".
static func info() -> Dictionary:
    var result := {
        "version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
        "commit": "dev",
        "built_at": "",
    }
    if FileAccess.file_exists(PATH):
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        if parsed is Dictionary:
            for key in result.keys():
                if parsed.has(key) and str(parsed[key]) != "":
                    result[key] = str(parsed[key])
    return result


## "v0.1.0 · dev" or "v0.1.0 · 1a2b3c4".
static func label_text() -> String:
    var data := info()
    return "v%s · %s" % [data["version"], data["commit"]]
