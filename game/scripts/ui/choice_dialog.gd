extends CanvasLayer
## Minimal modal choice prompt (shrine offers, later shops/NPCs).
##
## open(title, body, options) shows a centred panel with one button per option
## ({id, label}); number keys 1..9 pick an option, `pause` (Esc) cancels.
## Game freezes the world (State.DIALOG) while it is open; this node only
## reports the result through `chosen(id)` / `cancelled()`.
## No autoload references, so tests may load it directly.
## Wave 3C: B (ui_cancel) also cancels, A confirms the focused option, the
## cancel button names the device's back input, and text follows text_scale.
const Accessibility = preload("res://scripts/core/accessibility.gd")
const InputBindings = preload("res://scripts/core/input_bindings.gd")
signal chosen(option_id: String)
signal cancelled

var mode := "closed"
var title := ""
var body := ""
var options: Array = []
var overlay: Control
var box: VBoxContainer


func _ready() -> void:
    layer = 9
    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(overlay)
    var dim := ColorRect.new()
    dim.color = Color(0.02, 0.02, 0.04, 0.72)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(420, 0)
    center.add_child(panel)
    box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    panel.add_child(box)
    overlay.visible = false


func is_open() -> bool:
    return mode != "closed"


func open(new_title: String, new_body: String, new_options: Array) -> void:
    title = new_title
    body = new_body
    options = new_options.duplicate(true)
    mode = "open"
    if box == null:
        return
    for child in box.get_children():
        child.queue_free()
    var heading := Label.new()
    heading.text = title
    heading.add_theme_font_size_override("font_size", Accessibility.px(20))
    box.add_child(heading)
    var text := Label.new()
    text.text = body
    text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    text.add_theme_font_size_override("font_size", Accessibility.px(16))
    box.add_child(text)
    for index in range(options.size()):
        var button := Button.new()
        button.text = "[%d] %s" % [index + 1, String(options[index]["label"])] \
            if not InputBindings.is_gamepad() else String(options[index]["label"])
        button.add_theme_font_size_override("font_size", Accessibility.px(16))
        var option_id: String = String(options[index]["id"])
        button.pressed.connect(func(): choose(option_id))
        box.add_child(button)
        if index == 0:
            button.call_deferred("grab_focus")
    var leave := Button.new()
    leave.text = "[%s] Walk away" % ("B" if InputBindings.is_gamepad() else "Esc")
    leave.add_theme_font_size_override("font_size", Accessibility.px(16))
    leave.pressed.connect(cancel)
    box.add_child(leave)
    overlay.visible = true


func close() -> void:
    mode = "closed"
    if overlay != null:
        overlay.visible = false


func choose(option_id: String) -> void:
    if not is_open():
        return
    close()
    chosen.emit(option_id)


func cancel() -> void:
    if not is_open():
        return
    close()
    cancelled.emit()


func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
        cancel()
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo:
        var index: int = int(event.keycode) - int(KEY_1)
        if index >= 0 and index < options.size():
            choose(String(options[index]["id"]))
            get_viewport().set_input_as_handled()
