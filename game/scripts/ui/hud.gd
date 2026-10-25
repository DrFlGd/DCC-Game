extends CanvasLayer
## Screen-space HUD: status lines, last message, minimap and control hints.
## Reads RunState only; the message line is fed by `Events.message`. The
## end-of-run banner was replaced by the run summary screen (Wave 2A); Game
## hides the HUD on the title screen.
## Drawn in immediate mode on a full-rect Control that ignores the mouse, so
## clicks still reach gameplay. Layer 5 keeps it under CharacterMenu (layer 10).
const RPG = preload("res://scripts/rpg_rules.gd")
const Layout = preload("res://scripts/room_layout.gd")
const FloorMap = preload("res://scripts/ui/floor_map.gd")
## Tick counter colour thresholds (COLLAPSE_SYSTEM §8).
const TICKS_AMBER := 6
const TICKS_RED := 3

## Room-to-window mapping from Layout.compute(); Game keeps it current.
var layout: Dictionary = Layout.compute(Vector2(960, 540))
## Newest Events.message text and category.
var message := ""
var message_category := "info"
## Interaction prompt for the feature in reach (set by Game from RoomServices).
var prompt := ""
var canvas: Control
## Seconds left on the "ROOM CLEAR" flourish (show_room_clear, Wave 2D).
var room_clear_left := 0.0
const ROOM_CLEAR_SECONDS := 1.1


func _ready() -> void:
    layer = 5
    canvas = Control.new()
    canvas.name = "Canvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.draw.connect(_draw_hud)
    add_child(canvas)
    Events.message.connect(_on_message)


func _process(delta: float) -> void:
    room_clear_left = maxf(0.0, room_clear_left - delta)
    refresh()


## Starts the ~1 s "ROOM CLEAR" flourish (DoorLock calls it on a locking room's clear).
func show_room_clear() -> void:
    room_clear_left = ROOM_CLEAR_SECONDS
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
    # Ticks moved to the clock widget (_draw_clock, Wave 2E).
    _text("DCC | FLOOR %d/%d | ROOM %d %s | FOES %d" % [
        RunState.depth, int(RunState.config.get("run", {}).get("target_depth", 6)),
        RunState.current_room_id, String(room["kind"]).to_upper(),
        foes.size()], Vector2(14, 22), 17, Color("#f2da99"))
    _text("HP %d/%d  AC %d  LV %d  XP %d/%s  PROF +%d" % [
        maxi(0, RunState.hp), RunState.max_hp, RunState.ac, level, RunState.xp,
        str(RPG.next_level_xp(level)) if level < 20 else "MAX",
        RunState.proficiency], Vector2(14, 43), 15, Color("#e5eafa"))
    _draw_stamina_bar(Vector2(14, 47))
    var stat_parts: PackedStringArray = []
    for ability in RPG.ABILITIES:
        var score: int = int(RunState.ability_scores[ability])
        stat_parts.append("%s%d(%+d)" % [ability, score, RPG.modifier(score)])
    _text("  ".join(stat_parts), Vector2(14, 62), 12, Color("#afd4ce"))
    _text(message, Vector2(14, 83), 12, Color("#eccba6"))
    _draw_minimap(view)
    _draw_boss_bar(view)
    _draw_clock(view)
    _draw_grace_vignette(view)
    _draw_prompt(view)
    _draw_room_clear(view)
    _text("WASD / arrows: move  |  Mouse: aim  |  LMB: shoot  |  Space: melee  |  Shift: dodge  |  E: interact",
        Vector2(14, view.y - 46), 14, Color("#dce9f2"))
    _text("Esc: pause / stats | M: map | R: replay | N: new seed | 24x24 room, 16px tiles",
        Vector2(14, view.y - 21), 12, Color("#a7cfcb"))


## Stamina pool (Wave 2D): a thin bar under the HP line; amber when a dodge
## (35) is not affordable. Self-contained: reads RunState only.
func _draw_stamina_bar(origin: Vector2) -> void:
    var width := 120.0
    var maximum: float = maxf(1.0, RunState.max_stamina)
    var ratio: float = clampf(RunState.stamina / maximum, 0.0, 1.0)
    var cost: float = float(RunState.config.get("feel", {}).get("dodge", {}).get("cost", 35.0))
    var fill := Color("#6fd3a0") if RunState.stamina >= cost else Color("#d9a441")
    canvas.draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 6)), Color("#0b0f16"))
    canvas.draw_rect(Rect2(origin, Vector2(width * ratio, 4)), fill)
    var tick: float = width * clampf(cost / maximum, 0.0, 1.0)
    for i in range(1, int(maximum / maxf(1.0, cost)) + 1):
        canvas.draw_line(origin + Vector2(tick * i, 0), origin + Vector2(tick * i, 4),
            Color(0, 0, 0, 0.5), 1.0)
    _text("STA", origin + Vector2(width + 6, 5), 9, Color("#a7cfcb"))


## "ROOM CLEAR" banner across the top third with a gold border pulse.
func _draw_room_clear(view: Vector2) -> void:
    if room_clear_left <= 0.0:
        return
    var t: float = 1.0 - room_clear_left / ROOM_CLEAR_SECONDS
    var alpha: float = clampf(minf(t * 6.0, room_clear_left * 3.0), 0.0, 1.0)
    var scale: float = 1.0 + 0.25 * maxf(0.0, 1.0 - t * 5.0)
    var size: int = int(34.0 * scale)
    var text := "ROOM CLEAR"
    var font: Font = ThemeDB.fallback_font
    var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
    var at := Vector2((view.x - width) * 0.5, view.y * 0.32)
    canvas.draw_rect(Rect2(Vector2(0, at.y - size - 8), Vector2(view.x, size + 22)),
        Color(0.05, 0.04, 0.02, 0.55 * alpha))
    var border := Color(1.0, 0.84, 0.35, 0.8 * alpha * (0.6 + 0.4 * sin(t * 18.0)))
    canvas.draw_rect(Rect2(Vector2(3, 3), view - Vector2(6, 6)), border, false, 3.0)
    canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 5,
        Color(0.1, 0.06, 0.0, alpha))
    canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
        Color(1.0, 0.86, 0.4, alpha))


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


# --- Collapse clock widget (Wave 2E) -------------------------------------------

## Colour of the tick counter: amber at <= 6, red at <= 3.
static func ticks_color(ticks: int) -> Color:
    if ticks <= TICKS_RED:
        return Color("#ff6b6b")
    if ticks <= TICKS_AMBER:
        return Color("#ffc15e")
    return Color("#f2da99")


## Tick counter left of the minimap; during grace a large red countdown and a
## remaining-grace bar replace it.
func _draw_clock(view: Vector2) -> void:
    var origin := Vector2(view.x - 330.0, 9.0)
    var grace: Dictionary = RunState.grace
    if bool(grace.get("active", false)):
        var remaining: float = float(grace.get("remaining", 0.0))
        var duration: float = maxf(0.01, float(grace.get("duration", 1.0)))
        canvas.draw_rect(Rect2(origin, Vector2(138, 82)), Color(0.25, 0.02, 0.03, 0.92))
        _text("COLLAPSE IN", origin + Vector2(8, 15), 12, Color("#ffb3b3"))
        _text("%.1f" % remaining, origin + Vector2(8, 58), 40, Color("#ff3b3b"))
        canvas.draw_rect(Rect2(origin + Vector2(8, 66), Vector2(122, 8)), Color("#3a0a0d"))
        canvas.draw_rect(Rect2(origin + Vector2(8, 66), Vector2(122.0 * remaining / duration, 8)),
            Color("#ff3b3b"))
        return
    canvas.draw_rect(Rect2(origin, Vector2(138, 82)), Color("#222c39"))
    _text("COLLAPSE TICKS", origin + Vector2(8, 15), 11, Color.WHITE)
    _text(str(RunState.ticks), origin + Vector2(8, 60), 40, ticks_color(RunState.ticks))
    var budget: int = int(RunState.floor.get("budget", 0))
    if budget > 0:
        _text("/ %d" % budget, origin + Vector2(80, 60), 13, Color("#a7b4c2"))


## Red dust vignette while grace runs; it thickens as time runs out.
func _draw_grace_vignette(view: Vector2) -> void:
    var grace: Dictionary = RunState.grace
    if not bool(grace.get("active", false)):
        return
    var urgency: float = 1.0 - float(grace.get("remaining", 0.0)) \
        / maxf(0.01, float(grace.get("duration", 1.0)))
    var edge: float = 10.0 + 26.0 * urgency
    var tint := Color(0.55, 0.05, 0.05, 0.22 + 0.25 * urgency)
    canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(view.x, edge)), tint)
    canvas.draw_rect(Rect2(Vector2(0, view.y - edge), Vector2(view.x, edge)), tint)
    canvas.draw_rect(Rect2(Vector2(0, edge), Vector2(edge, view.y - edge * 2.0)), tint)
    canvas.draw_rect(Rect2(Vector2(view.x - edge, edge), Vector2(edge, view.y - edge * 2.0)), tint)


func _draw_prompt(view: Vector2) -> void:
    if prompt == "":
        return
    var font: Font = ThemeDB.fallback_font
    var width: float = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
    var at := Vector2((view.x - width) * 0.5, view.y - 72.0)
    canvas.draw_rect(Rect2(at + Vector2(-10, -18), Vector2(width + 20, 26)), Color(0.05, 0.07, 0.1, 0.85))
    _text(prompt, at, 15, Color("#fff1a7"))


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
        var color: Color = FloorMap.KIND_COLORS.get(String(room["kind"]), Color("#788b9d"))
        if id == RunState.current_room_id: color = Color.WHITE
        canvas.draw_rect(Rect2(p, Vector2(maxf(3.0, unit - 1.0), maxf(3.0, unit - 1.0))), color)


func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    canvas.draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
