extends CanvasLayer
## Screen-space HUD: status lines, last message, minimap and control hints.
## Reads RunState only; the message line is fed by `Events.message`. The
## end-of-run banner was replaced by the run summary screen (Wave 2A); Game
## hides the HUD on the title screen.
## Drawn in immediate mode on a full-rect Control that ignores the mouse, so
## clicks still reach gameplay. Layer 5 keeps it under CharacterMenu (layer 10).
const RPG = preload("res://scripts/rpg_rules.gd")
const Layout = preload("res://scripts/room_layout.gd")

## Room-to-window mapping from Layout.compute(); Game keeps it current.
var layout: Dictionary = Layout.compute(Vector2(960, 540))
## Newest Events.message text and category.
var message := ""
var message_category := "info"
var canvas: Control


func _ready() -> void:
    layer = 5
    canvas = Control.new()
    canvas.name = "Canvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.draw.connect(_draw_hud)
    add_child(canvas)
    Events.message.connect(_on_message)


func _process(_delta: float) -> void:
    refresh()


func refresh() -> void:
    if canvas != null:
        canvas.queue_redraw()


func _on_message(text: String, category: String) -> void:
    message = text
    message_category = category
    refresh()


func _draw_hud() -> void:
    if RunState.floor.is_empty():
        return
    var view: Vector2 = layout["viewport"]
    var room: Dictionary = RunState.floor["rooms"][RunState.current_room_id]
    var foes: Array = RunState.current_room().get("enemies", [])
    var level: int = RunState.level
    _text("DCC | FLOOR %d/%d | ROOM %d %s | TICKS %d | FOES %d" % [
        RunState.depth, int(RunState.config.get("run", {}).get("target_depth", 6)),
        RunState.current_room_id, String(room["kind"]).to_upper(),
        RunState.ticks, foes.size()], Vector2(14, 22), 17, Color("#f2da99"))
    _text("HP %d/%d  AC %d  LV %d  XP %d/%s  PROF +%d" % [
        maxi(0, RunState.hp), RunState.max_hp, RunState.ac, level, RunState.xp,
        str(RPG.next_level_xp(level)) if level < 20 else "MAX",
        RunState.proficiency], Vector2(14, 43), 15, Color("#e5eafa"))
    var stat_parts: PackedStringArray = []
    for ability in RPG.ABILITIES:
        var score: int = int(RunState.ability_scores[ability])
        stat_parts.append("%s%d(%+d)" % [ability, score, RPG.modifier(score)])
    _text("  ".join(stat_parts), Vector2(14, 62), 12, Color("#afd4ce"))
    _text(message, Vector2(14, 83), 12, Color("#eccba6"))
    _draw_minimap(view)
    _draw_boss_bar(view)
    _text("WASD / arrows: move  |  Mouse: aim  |  LMB: shoot  |  Space: melee",
        Vector2(14, view.y - 46), 14, Color("#dce9f2"))
    _text("Esc: pause / stats | R: replay | N: new seed | 24x24 room, 16px tiles",
        Vector2(14, view.y - 21), 12, Color("#a7cfcb"))


## Small top-centre HP bar for a live boss in the current room (any enemy with
## "boss": true), with its phase as pips. Self-contained: reads RunState only.
func _draw_boss_bar(view: Vector2) -> void:
    var boss: Dictionary = {}
    for foe in RunState.current_room().get("enemies", []):
        if bool(foe.get("boss", false)) and int(foe["hp"]) > 0:
            boss = foe
            break
    if boss.is_empty():
        return
    var width := 240.0
    var origin := Vector2(floorf(view.x * 0.5 - width * 0.5), 86.0)
    var ratio: float = clampf(float(boss["hp"]) / float(maxi(1, int(boss["max_hp"]))), 0.0, 1.0)
    canvas.draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 13)), Color("#0b0f16"))
    canvas.draw_rect(Rect2(origin, Vector2(width * ratio, 11)), Color("#b8323c"))
    if int(boss.get("shield", 0)) + int(boss.get("ward", 0)) > 0:
        canvas.draw_rect(Rect2(origin + Vector2(0, 9), Vector2(width, 2)), Color("#7fc4ff"))
    var phase: int = int(boss.get("phase", 0))
    var label: String = "%s  %s" % [String(boss.get("name", "Boss")).to_upper(),
        "I".repeat(phase + 1) if phase < 3 else str(phase + 1)]
    canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(0, 9), label,
        HORIZONTAL_ALIGNMENT_CENTER, width, 10, Color.WHITE)


func _draw_minimap(view: Vector2) -> void:
    var floor_data: Dictionary = RunState.floor
    var map_origin := Vector2(view.x - 185.0, 9.0)
    canvas.draw_rect(Rect2(map_origin, Vector2(174, 82)), Color("#222c39"))
    _text("MAP", map_origin + Vector2(8, 13), 11, Color.WHITE)
    var min_cell := Vector2i(999, 999)
    var max_cell := Vector2i(-999, -999)
    for room in floor_data["rooms"]:
        var cell: Vector2i = room["grid"]
        min_cell.x = mini(min_cell.x, cell.x)
        min_cell.y = mini(min_cell.y, cell.y)
        max_cell.x = maxi(max_cell.x, cell.x)
        max_cell.y = maxi(max_cell.y, cell.y)
    var span_x: int = maxi(1, max_cell.x - min_cell.x + 1)
    var span_y: int = maxi(1, max_cell.y - min_cell.y + 1)
    var unit: float = minf(9.0, minf(156.0 / float(span_x), 60.0 / float(span_y)))
    for room in floor_data["rooms"]:
        var id: int = int(room["id"])
        if not RunState.visited.has(id) and id != int(floor_data["exit_id"]):
            continue
        var cell: Vector2i = room["grid"]
        var p: Vector2 = map_origin + Vector2(
            8.0 + float(cell.x - min_cell.x) * unit,
            20.0 + float(cell.y - min_cell.y) * unit)
        var color := Color("#788b9d")
        if id == RunState.current_room_id: color = Color.WHITE
        elif room["kind"] == "boss": color = Color("#ec9c9d")
        elif room["kind"] == "exit": color = Color("#eacb7b")
        elif room["kind"] == "guild_hall": color = Color("#a4efd6")
        canvas.draw_rect(Rect2(p, Vector2(maxf(3.0, unit - 1.0), maxf(3.0, unit - 1.0))), color)


func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    canvas.draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
