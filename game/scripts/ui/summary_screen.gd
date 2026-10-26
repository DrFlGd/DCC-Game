extends "res://scripts/ui/screen_base.gd"
## Run summary (Game state SUMMARY, GAME_DESIGN §6), shown after every
## Events.run_ended. Built from the RunState.summary() snapshot only. The seed
## sits in a read-only field (select + copy) with a Copy button.

signal retry_requested
signal new_run_requested
signal title_requested

const TITLES := {
    "victory": "VICTORY", "defeated": "YOU DIED", "collapsed": "FLOOR COLLAPSED",
    "abandoned": "RUN ABANDONED"
}

var seed_field: LineEdit
var retry_button: Button
## The summary dictionary last shown.
var summary: Dictionary = {}


func _ready() -> void:
    layer = 12
    super()


func open(run_summary: Dictionary) -> void:
    summary = run_summary.duplicate(true)
    var outcome: String = String(summary.get("outcome", ""))
    var content := _begin(Vector2(540, 0), 0.92)
    content.add_child(_text(String(TITLES.get(outcome, outcome.to_upper())), 32,
        GOLD if outcome == "victory" else Color("#ec9c9d"), HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(_text(cause_line(summary), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(_text(epitaph(outcome), 13, SOFT, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(HSeparator.new())
    _rows(content, [
        ["Depth reached", "Floor %d of %d  (%d cleared)" % [int(summary.get("depth", 1)),
            int(summary.get("target_depth", 6)), int(summary.get("floors_cleared", 0))]],
        ["Rooms explored", str(int(summary.get("rooms_entered", 0)))],
        ["Ticks spent / granted", "%d / %d" % [int(summary.get("ticks_spent", 0)),
            int(summary.get("ticks_granted", 0))]],
        ["Kills", str(int(summary.get("kills", 0)))],
        ["Damage dealt / taken", "%d / %d" % [int(summary.get("damage_dealt", 0)),
            int(summary.get("damage_taken", 0))]],
        ["Level / XP", "%d / %d" % [int(summary.get("level", 1)), int(summary.get("xp", 0))]],
        ["Run time", format_time(float(summary.get("run_time_seconds", 0.0)))],
    ])
    var seed_row := HBoxContainer.new()
    seed_row.add_theme_constant_override("separation", 8)
    content.add_child(seed_row)
    seed_row.add_child(_text("Seed", 15, MUTED))
    seed_field = LineEdit.new()
    seed_field.text = str(int(summary.get("seed", 0)))
    seed_field.editable = false
    seed_field.focus_mode = Control.FOCUS_CLICK
    seed_field.custom_minimum_size = Vector2(170, 32)
    seed_row.add_child(seed_field)
    seed_row.add_child(_button("Copy seed", copy_seed))
    content.add_child(HSeparator.new())
    var actions := HBoxContainer.new()
    actions.add_theme_constant_override("separation", 10)
    actions.alignment = BoxContainer.ALIGNMENT_CENTER
    content.add_child(actions)
    retry_button = _button("Retry seed", func(): retry_requested.emit())
    actions.add_child(retry_button)
    actions.add_child(_button("New run", func(): new_run_requested.emit()))
    actions.add_child(_button("Title", func(): title_requested.emit()))
    # Wave 3C: worded for the last-used device (R / N are keyboard shortcuts).
    _add_hint(content)
    retry_button.grab_focus()


func _hint_text() -> String:
    if InputBindings.is_gamepad():
        return nav_hint("", false)
    return "R: retry seed   N: new run   " + nav_hint("", false)


func copy_seed() -> void:
    DisplayServer.clipboard_set(str(int(summary.get("seed", 0))))


## "Killed by Rat Scavenger on floor 2", "Collapse on floor 3", ...
static func cause_line(run_summary: Dictionary) -> String:
    var cause: String = String(run_summary.get("cause", ""))
    var depth: int = int(run_summary.get("depth", 1))
    match String(run_summary.get("outcome", "")):
        "victory":
            return "Took the exit on floor %d. The dungeon will want that back." % depth
        "defeated":
            var killer: String = cause.replace("_", " ").capitalize() if cause != "" else "something"
            return "Killed by %s on floor %d" % [killer, depth]
        "collapsed":
            return cause.capitalize() if cause != "" else "Collapse on floor %d" % depth
        "abandoned":
            return "Abandoned on floor %d" % depth
    return cause


static func epitaph(outcome: String) -> String:
    match outcome:
        "victory":
            return "Congratulations. Your prize is the knowledge that there is more dungeon."
        "defeated":
            return "Your remains have been filed under 'learning experience'."
        "collapsed":
            return "The ceiling was load-bearing. You were not."
        "abandoned":
            return "Walking away is a valid strategy. It is just not a winning one."
    return ""
