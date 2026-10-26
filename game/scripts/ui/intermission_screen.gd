extends "res://scripts/ui/screen_base.gd"
## Between-floor screen (Game state INTERMISSION, GAME_DESIGN §5): floor recap
## from RunState.floor_stats() and a single Descend button. Simulation and the
## run clock are frozen while it is open.

const Biomes = preload("res://scripts/biomes.gd")

signal descend_requested

var descend_button: Button
## The recap dictionary last shown (for tests and the announcer).
var recap: Dictionary = {}


func _ready() -> void:
    layer = 12
    super()


## `floor_recap` is RunState.close_floor() plus "healed" (HP restored here).
func open(floor_recap: Dictionary, next_depth: int, target_depth: int, hp: int,
        max_hp: int) -> void:
    recap = floor_recap.duplicate(true)
    var depth: int = int(recap.get("depth", next_depth - 1))
    var content := _begin(Vector2(500, 0), 0.9)
    content.add_child(_text("FLOOR %d CLEARED" % depth, 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(_text(quip(recap), 13, SOFT, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(HSeparator.new())
    _rows(content, [
        ["Rooms explored", "%d / %d" % [int(recap.get("rooms_explored", 0)),
            int(recap.get("rooms_total", 0))]],
        ["Ticks left", "%d of %d" % [int(recap.get("ticks_left", 0)),
            int(recap.get("budget", 0))]],
        ["Kills", str(int(recap.get("kills", 0)))],
        ["Damage taken", str(int(recap.get("damage_taken", 0)))],
        ["Floor time", format_time(float(recap.get("run_time_seconds", 0.0)))],
        ["Patched up", "+%d HP  (now %d/%d)" % [int(recap.get("healed", 0)), hp, max_hp]],
    ])
    content.add_child(HSeparator.new())
    descend_button = _button("Descend to floor %d of %d" % [next_depth, target_depth],
        func(): descend_requested.emit())
    content.add_child(descend_button)
    # Wave 3B: where the next floor leads (biome by depth).
    content.add_child(_text("Next: %s" % Biomes.display_name(Biomes.for_depth(next_depth)),
        12, SOFT, HORIZONTAL_ALIGNMENT_CENTER))
    content.add_child(_text("Leftover ticks do not carry over. The next floor sets its own clock.",
        11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
    descend_button.grab_focus()


## One original "dungeon system" line keyed to how the floor went.
static func quip(floor_recap: Dictionary) -> String:
    var left: int = int(floor_recap.get("ticks_left", 0))
    if left == 0:
        return "Exact change. Accounting is impressed and slightly annoyed."
    if left <= 3:
        return "That was close. The ceiling sends its regards."
    if int(floor_recap.get("damage_taken", 0)) == 0:
        return "Not a scratch. The insurance department has opened an inquiry."
    if int(floor_recap.get("rooms_explored", 0)) * 2 < int(floor_recap.get("rooms_total", 0)):
        return "Efficient. Unsightly, but efficient. Please mind the stairwell."
    return "Floor processed. Please do not linger in the stairwell."
