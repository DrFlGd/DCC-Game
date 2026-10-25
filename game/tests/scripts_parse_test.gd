extends SceneTree
## Compiles every GDScript under res://scripts and res://tests at runtime.
## The editor import step (--editor --quit) does not report parse errors in
## scripts that no scene loads, so this is the parse gate for run_all.sh.
## Loading happens after autoloads are registered, so Events/RunState resolve.
## Run: godot --headless --path game --script res://tests/scripts_parse_test.gd
const ROOTS := ["res://scripts", "res://tests"]
var failures := 0
var checked := 0


func _initialize() -> void:
    for root in ROOTS:
        _scan(root)
    if checked < 10:
        failures += 1
        push_error("FAIL PARSE: expected at least 10 scripts, found %d" % checked)
    if failures == 0:
        print("PASS: %d scripts compile" % checked)
    quit(1 if failures > 0 else 0)


func _scan(directory: String) -> void:
    for sub in DirAccess.get_directories_at(directory):
        _scan(directory.path_join(sub))
    for file in DirAccess.get_files_at(directory):
        if file.get_extension() == "gd":
            _check_script(directory.path_join(file))


func _check_script(path: String) -> void:
    # Reloading the running test script itself crashes the engine; skip it.
    if path == get_script().resource_path:
        return
    checked += 1
    var script: GDScript = load(path) as GDScript
    if script == null or not script.can_instantiate():
        failures += 1
        push_error("FAIL PARSE: " + path)
