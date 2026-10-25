extends CanvasLayer
## Reward-moment item card (Wave 2B, GAME_DESIGN §3.3): when an item enters the
## inventory (Events.item_picked_up), a card with its name in the rarity
## colour, its rarity and kind, and its description slides in on the right
## for CARD_SECONDS. Several pickups queue. Presentation only; it never
## changes state. Owned by ItemSystem (created in its setup()).
const Inventory = preload("res://scripts/inventory.gd")

const CARD_SECONDS := 2.8
const WIDTH := 290.0
const MAX_QUEUE := 4

var queue: Array[Dictionary] = []
var current: Dictionary = {}
var remaining := 0.0
var canvas: Control


func _ready() -> void:
    layer = 6
    canvas = Control.new()
    canvas.name = "Canvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.draw.connect(_draw_card)
    add_child(canvas)
    Events.item_picked_up.connect(show_item)
    Events.run_started.connect(func(_seed): clear())


## Queues a card for content id `id`.
func show_item(id: String) -> void:
    if queue.size() >= MAX_QUEUE:
        queue.pop_front()
    queue.append(Inventory.label(id))
    if current.is_empty():
        _next()


func clear() -> void:
    queue.clear()
    current = {}
    remaining = 0.0
    if canvas != null:
        canvas.queue_redraw()


func _next() -> void:
    current = queue.pop_front() if not queue.is_empty() else {}
    remaining = CARD_SECONDS if not current.is_empty() else 0.0
    if canvas != null:
        canvas.queue_redraw()


func _process(delta: float) -> void:
    if current.is_empty():
        return
    remaining -= delta
    if remaining <= 0.0:
        _next()
    elif canvas != null:
        canvas.queue_redraw()


func _draw_card() -> void:
    if current.is_empty():
        return
    var view: Vector2 = canvas.get_viewport_rect().size
    var font: Font = ThemeDB.fallback_font
    var color: Color = current.get("color", Color.WHITE)
    var slide: float = clampf((CARD_SECONDS - remaining) / 0.18, 0.0, 1.0)
    var fade: float = clampf(remaining / 0.3, 0.0, 1.0)
    var origin := Vector2(view.x - (WIDTH + 14.0) * slide, 112.0)
    var description: String = String(current.get("description", ""))
    var text_height: float = font.get_multiline_string_size(description,
        HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 20.0, 12).y
    var height: float = 54.0 + text_height
    canvas.draw_rect(Rect2(origin, Vector2(WIDTH, height)), Color(0.06, 0.08, 0.12, 0.93 * fade))
    canvas.draw_rect(Rect2(origin, Vector2(4, height)), Color(color, fade))
    canvas.draw_rect(Rect2(origin, Vector2(WIDTH, height)), Color(color, 0.8 * fade), false, 1.5)
    canvas.draw_string(font, origin + Vector2(12, 14), "NEW ITEM", HORIZONTAL_ALIGNMENT_LEFT,
        -1.0, 10, Color(0.75, 0.8, 0.9, fade))
    canvas.draw_string(font, origin + Vector2(12, 32), String(current.get("name", "")),
        HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 20.0, 16, Color(color, fade))
    canvas.draw_string(font, origin + Vector2(12, 47), "%s %s" % [
        String(current.get("rarity", "")).to_upper(), String(current.get("kind", ""))],
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(color.lightened(0.3), fade))
    canvas.draw_multiline_string(font, origin + Vector2(12, 62), description,
        HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 20.0, 12, -1, Color(0.9, 0.92, 0.95, fade))
