extends CanvasLayer
## Shared look and plumbing for the full-screen menus built in code: title,
## intermission, run summary and settings. Subclasses call `_begin()` to get a
## fresh panel content box, add controls, then grab focus on their primary
## button so keyboard and gamepad (ui_up / ui_down / ui_accept) work at once.
## Reads no autoloads, so it compiles in --script tests.

const GOLD := Color("#f6d48d")
const SOFT := Color("#c5dee4")
const MUTED := Color("#9eb8c4")
const GOOD := Color("#a9e7c5")

var overlay: Control
var dim: ColorRect
var center: CenterContainer


func _ready() -> void:
    _build()


func is_open() -> bool:
    return overlay != null and overlay.visible


func close() -> void:
    if overlay != null:
        overlay.visible = false


func _build() -> void:
    if overlay != null:
        return
    overlay = Control.new()
    overlay.name = "Overlay"
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(overlay)
    dim = ColorRect.new()
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.add_child(dim)
    center = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(center)
    overlay.visible = false


## Clears the screen, shows it over a backdrop of `backdrop_alpha` and returns
## the VBoxContainer to fill.
func _begin(min_size: Vector2, backdrop_alpha: float) -> VBoxContainer:
    _build()
    dim.color = Color(0.015, 0.025, 0.045, backdrop_alpha)
    for node in center.get_children():
        center.remove_child(node)
        node.queue_free()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = min_size
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#172333")
    style.border_color = Color("#d5b978")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", style)
    center.add_child(panel)
    var padding := MarginContainer.new()
    for side in ["left", "right"]:
        padding.add_theme_constant_override("margin_" + side, 24)
    for side in ["top", "bottom"]:
        padding.add_theme_constant_override("margin_" + side, 16)
    panel.add_child(padding)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 7)
    padding.add_child(content)
    overlay.visible = true
    return content


func _button(label: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size.y = 34
    button.add_theme_font_size_override("font_size", 15)
    button.pressed.connect(callback)
    return button


func _text(value: String, font_size: int, color: Color,
        align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var label := Label.new()
    label.text = value
    label.horizontal_alignment = align
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


## Two-column label grid for "name  value" rows.
func _rows(content: VBoxContainer, rows: Array) -> GridContainer:
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 28)
    grid.add_theme_constant_override("v_separation", 4)
    for row in rows:
        grid.add_child(_text(String(row[0]), 15, MUTED))
        grid.add_child(_text(String(row[1]), 15, Color.WHITE))
    content.add_child(grid)
    return grid


## 125.4 -> "2:05"; an hour or more -> "1:02:05".
static func format_time(seconds: float) -> String:
    var total: int = maxi(0, int(seconds))
    if total >= 3600:
        return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
    return "%d:%02d" % [total / 60, total % 60]
