extends "res://scripts/ui/screen_base.gd"
## Title screen (Game state TITLE): New run (random seed), Seeded run (integer
## seed field), Settings, Quit. Emits requests; Game acts on them. Shows the
## deepest floor reached when 2G's profile script exposes a static
## `best_depth() -> int`; otherwise that line is omitted.

signal new_run_requested
signal seeded_run_requested(seed: int)
signal settings_requested
signal quit_requested

const PROFILE_SCRIPT := "res://scripts/core/profile.gd"
const MAX_SEED := 2147483647

var seed_input: LineEdit
var feedback: Label
var new_run_button: Button


func _ready() -> void:
    layer = 12
    super()


func open() -> void:
    var content := _begin(Vector2(520, 0), 1.0)
    content.add_child(_text("DCC GAME", 44, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(_text("A fully licensed descent. Management accepts no liability.",
        14, SOFT, HORIZONTAL_ALIGNMENT_CENTER))
    var best: int = best_depth()
    if best > 0:
        content.add_child(_text("Deepest floor reached: %d" % best, 13, GOOD,
            HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(HSeparator.new())
    new_run_button = _button("New run", _on_new_run)
    content.add_child(new_run_button)
    var seed_row := HBoxContainer.new()
    seed_row.add_theme_constant_override("separation", 8)
    content.add_child(seed_row)
    seed_input = LineEdit.new()
    seed_input.placeholder_text = "Seed (whole number)"
    seed_input.custom_minimum_size = Vector2(250, 34)
    seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    seed_input.text_submitted.connect(submit_seed)
    seed_row.add_child(seed_input)
    seed_row.add_child(_button("Seeded run", func(): submit_seed(seed_input.text)))
    content.add_child(_button("Settings", func(): settings_requested.emit()))
    content.add_child(_button("Quit", func(): quit_requested.emit()))
    feedback = _text("", 12, Color("#eccba6"), HORIZONTAL_ALIGNMENT_CENTER)
    content.add_child(feedback)
    # Wave 3C: worded for the last-used device; updates when it changes.
    _add_hint(content)
    new_run_button.grab_focus()


func _hint_text() -> String:
    return nav_hint("", false)


## Starts a seeded run from `text`, or explains why it cannot. Returns whether
## a run was requested.
func submit_seed(text: String) -> bool:
    var value: int = parse_seed(text)
    if value < 1:
        if feedback != null:
            feedback.text = "The dungeon accepts whole numbers from 1 to %d. Try again." % MAX_SEED
        return false
    seeded_run_requested.emit(value)
    return true


## Returns the seed in `text`, or -1 unless it is a whole number in 1..MAX_SEED.
static func parse_seed(text: String) -> int:
    var trimmed: String = text.strip_edges()
    if trimmed.is_empty() or not trimmed.is_valid_int() or trimmed.length() > 10:
        return -1
    var value: int = trimmed.to_int()
    return value if value >= 1 and value <= MAX_SEED else -1


## Deepest floor from the profile (2G), or 0 when no profile script exists.
static func best_depth() -> int:
    if not ResourceLoader.exists(PROFILE_SCRIPT):
        return 0
    var script: Script = load(PROFILE_SCRIPT) as Script
    if script == null:
        return 0
    for method in script.get_script_method_list():
        if method["name"] == "best_depth" and int(method["flags"]) & METHOD_FLAG_STATIC:
            return int(script.call("best_depth"))
    return 0


func _on_new_run() -> void:
    new_run_requested.emit()
