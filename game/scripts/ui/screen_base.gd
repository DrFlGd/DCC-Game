extends CanvasLayer
## Shared look and plumbing for the full-screen menus built in code: title,
## intermission, run summary and settings. Subclasses call `_begin()` to get a
## fresh panel content box, add controls, then grab focus on their primary
## button so keyboard and gamepad (ui_up / ui_down / ui_accept) work at once.
## Reads no autoloads, so it compiles in --script tests.
##
## Wave 3C: text and button sizes follow the text_scale setting
## (Accessibility.px), panels and labels switch to high contrast, `_add_hint()`
## adds a navigation hint line worded for the last-used device that updates on
## Events.input_device_changed (looked up at runtime), and B (`ui_cancel`
## without `pause`) calls `_on_cancel()` while the screen is open; Esc and
## Start reach screens through Game's `pause` handling instead.
const Accessibility = preload("res://scripts/core/accessibility.gd")
const InputBindings = preload("res://scripts/core/input_bindings.gd")

const GOLD := Color("#f6d48d")
const SOFT := Color("#c5dee4")
const MUTED := Color("#9eb8c4")
const GOOD := Color("#a9e7c5")

var overlay: Control
var dim: ColorRect
var center: CenterContainer
## Device-dependent hint line from _add_hint() (null when the screen has none).
var hint_label: Label


func _ready() -> void:
    _build()
    var events: Node = get_node_or_null("/root/Events")
    if events != null and events.has_signal("input_device_changed"):
        events.connect("input_device_changed", _on_input_device_changed)


func _input(event: InputEvent) -> void:
    if not is_open() or not event.is_action_pressed("ui_cancel"):
        return
    if InputMap.has_action("pause") and event.is_action_pressed("pause"):
        return
    if _on_cancel():
        get_viewport().set_input_as_handled()


## B on a gamepad (ui_cancel that is not `pause`). Return true when handled.
func _on_cancel() -> bool:
    return false


## Menu navigation hint for `device` ("" = the last-used one).
static func nav_hint(device: String = "", can_go_back: bool = true) -> String:
    var pad: bool = (InputBindings.device if device == "" else device) == InputBindings.GAMEPAD
    var parts: PackedStringArray = ["D-pad / left stick: move", "A: choose"] if pad \
        else ["Arrows / Tab: move", "Enter: choose"]
    if can_go_back:
        parts.append("B: back" if pad else "Esc: back")
    return "   ".join(parts)


## The text of this screen's hint line; screens override it.
func _hint_text() -> String:
    return nav_hint()


## Adds the device-dependent hint line to `content`.
func _add_hint(content: VBoxContainer) -> Label:
    hint_label = _text(_hint_text(), 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
    content.add_child(hint_label)
    return hint_label


func _on_input_device_changed(_device: String) -> void:
    if hint_label != null and is_instance_valid(hint_label):
        hint_label.text = _hint_text()


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
    var contrast: bool = Accessibility.high_contrast()
    style.bg_color = Color("#000000") if contrast else Color("#172333")
    style.border_color = Color.WHITE if contrast else Color("#d5b978")
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
    button.custom_minimum_size.y = roundf(34.0 * Accessibility.text_scale())
    button.add_theme_font_size_override("font_size", Accessibility.px(15))
    button.pressed.connect(callback)
    return button


func _text(value: String, font_size: int, color: Color,
        align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var label := Label.new()
    label.text = value
    label.horizontal_alignment = align
    label.add_theme_font_size_override("font_size", Accessibility.px(font_size))
    label.add_theme_color_override("font_color", color)
    if Accessibility.high_contrast():
        label.add_theme_constant_override("outline_size", Accessibility.OUTLINE)
        label.add_theme_color_override("font_outline_color", Accessibility.OUTLINE_COLOR)
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
