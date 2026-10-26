extends "res://scripts/ui/screen_base.gd"
## Controls page (Wave 3C), opened from the settings screen's "Controls…"
## button. Lists every gameplay action (InputBindings.ACTIONS) with its
## keyboard / mouse and gamepad bindings; choosing a binding starts a capture
## ("press a key / button"), and the next key, mouse button, gamepad button or
## stick / trigger push is bound through InputBindings.rebind() in swap mode
## (an input another action uses moves over to that action, taking this
## action's old binding; developer keys and pause's Esc / Start are refused).
## "Reset to defaults" restores project.godot's bindings.
##
## Emits `bindings_changed` after every accepted change (SettingsScreen relays
## it as setting_changed("input_bindings", ...) and Game saves the overrides
## under [input] in user://settings.cfg) and `closed` when Back / B / Esc
## closes it. While capturing, Esc or Start cancels and nothing else reaches
## the game; a capture also times out after CAPTURE_SECONDS.
## No autoload references, so tests may load it directly.

signal bindings_changed
signal closed

const CAPTURE_SECONDS := 6.0
## How rebind() treats a conflict: "swap" (default) or "refuse".
const CONFLICT_MODE := "swap"
const COLUMN_TITLES := {"kbm": "Keyboard / mouse", "pad": "Gamepad"}
const REASONS := {
    "locked": "That binding is fixed.",
    "invalid": "That input cannot be bound.",
    "wrong_column": "Wrong device for this column.",
    "reserved": "Reserved: Esc / Start (pause) and the developer keys stay put.",
    "conflict": "Already used by another action.",
}

## Action and column being captured ("" when idle).
var capture_action := ""
var capture_column := ""
var status_label: Label
var reset_button: Button
var back_button: Button
var _capture_left := 0.0
var _capture_frame := -1


func _ready() -> void:
    layer = 21
    super()


func open() -> void:
    _build_page("")


func is_capturing() -> bool:
    return capture_action != ""


func _build_page(focus_name: String) -> void:
    var status: String = status_label.text if status_label != null \
        and is_instance_valid(status_label) else ""
    var content := _begin(Vector2(620, 0), 0.6)
    content.add_child(_text("CONTROLS", 28, GOLD))
    content.add_child(_text("Choose a binding, then press the new key, mouse button or gamepad input."
        + " Esc or Start cancels. A taken input swaps places with the old one.", 12, SOFT))
    var scroll := ScrollContainer.new()
    var view_height: float = 540.0
    if is_inside_tree():
        view_height = get_viewport().get_visible_rect().size.y
    scroll.custom_minimum_size = Vector2(580, clampf(view_height - 250.0 * Accessibility.text_scale(),
        140.0, 330.0))
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    content.add_child(scroll)
    var grid := GridContainer.new()
    grid.name = "Bindings"
    grid.columns = 3
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 4)
    scroll.add_child(grid)
    grid.add_child(_text("Action", 13, MUTED))
    grid.add_child(_text(COLUMN_TITLES["kbm"], 13, MUTED))
    grid.add_child(_text(COLUMN_TITLES["pad"], 13, MUTED))
    var first: Button = null
    for entry in InputBindings.ACTIONS:
        var action: String = String(entry[0])
        var label := _text(String(entry[1]), 14, Color.WHITE)
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(label)
        for column in InputBindings.COLUMNS:
            var button := _button(binding_text(action, column),
                Callable(self, "begin_capture").bind(action, column))
            button.name = button_name(action, column)
            button.custom_minimum_size.x = 170.0 * Accessibility.text_scale()
            button.custom_minimum_size.y = roundf(28.0 * Accessibility.text_scale())
            button.clip_text = true
            if not InputBindings.is_remappable(action, column):
                button.disabled = true
                button.focus_mode = Control.FOCUS_NONE
            elif first == null:
                first = button
            grid.add_child(button)
    status_label = _text(status, 12, Color("#eccba6"))
    status_label.name = "Status"
    content.add_child(status_label)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    content.add_child(row)
    reset_button = _button("Reset to defaults", reset_defaults)
    reset_button.name = "ResetDefaults"
    row.add_child(reset_button)
    back_button = _button("Back", close)
    back_button.name = "Back"
    row.add_child(back_button)
    _add_hint(content)
    var target: Node = null
    if focus_name != "":
        target = center.find_child(focus_name, true, false)
    if target is Control:
        (target as Control).grab_focus()
    elif first != null:
        first.grab_focus()


static func button_name(action: String, column: String) -> String:
    return "%s_%s" % [column, action]


## Button caption for `action` / `column` ("press…" while capturing it).
func binding_text(action: String, column: String) -> String:
    if action == capture_action and column == capture_column:
        return "Press a %s…" % ("key / mouse button" if column == "kbm" else "gamepad input")
    return InputBindings.column_label(action, column)


## The binding button for `action` / `column`, or null.
func binding_button(action: String, column: String) -> Button:
    if center == null:
        return null
    return center.find_child(button_name(action, column), true, false) as Button


## Starts listening for a new `column` binding of `action`.
func begin_capture(action: String, column: String) -> bool:
    if not InputBindings.is_remappable(action, column):
        return false
    capture_action = action
    capture_column = column
    _capture_left = CAPTURE_SECONDS
    _capture_frame = Engine.get_process_frames()
    _set_status("%s (%s): press the new %s." % [InputBindings.action_label(action),
        COLUMN_TITLES[column].to_lower(), "key or mouse button" if column == "kbm" else
        "button, stick or trigger"])
    var button: Button = binding_button(action, column)
    if button != null:
        button.text = binding_text(action, column)
    return true


func cancel_capture(message: String = "Cancelled.") -> void:
    if not is_capturing():
        return
    var action: String = capture_action
    var column: String = capture_column
    capture_action = ""
    capture_column = ""
    var button: Button = binding_button(action, column)
    if button != null:
        button.text = binding_text(action, column)
    _set_status(message)


## Offers `event` to the running capture. Returns true when the event was
## used (bound, refused or cancelled) and false when it is not a fresh press
## (releases, echoes, small stick movement, mouse motion and the wheel are
## ignored and the capture keeps waiting).
func capture_event(event: InputEvent) -> bool:
    if not is_capturing() or not _is_press(event):
        return false
    if _is_cancel(event):
        cancel_capture()
        return true
    var text: String = InputBindings.event_to_string(event)
    if text.begins_with("keycode:"):
        # Captured keys are stored by physical position when the platform gives one.
        text = "key:" + text.substr(8)
    if text == "" or InputBindings.column_of(text) != capture_column:
        _set_status("That is not a %s. Still listening…" % ("key or mouse button" if
            capture_column == "kbm" else "gamepad input"))
        return true
    var action: String = capture_action
    var column: String = capture_column
    capture_action = ""
    capture_column = ""
    var result: Dictionary = InputBindings.rebind(action, column, text, CONFLICT_MODE)
    var focus: String = button_name(action, column)
    if not bool(result["ok"]):
        _set_status("%s  (%s)" % [String(REASONS.get(String(result["reason"]), "Refused.")),
            InputBindings.label(text)])
        _rebuild(focus)
        return true
    if String(result["reason"]) == "unchanged":
        _set_status("%s already uses %s." % [InputBindings.action_label(action), InputBindings.label(text)])
    elif String(result["swapped_with"]) != "":
        _set_status("%s is now %s; %s took over its old binding." % [InputBindings.action_label(action),
            InputBindings.label(text), InputBindings.action_label(String(result["swapped_with"]))])
    else:
        _set_status("%s is now %s." % [InputBindings.action_label(action), InputBindings.label(text)])
    _rebuild(focus)
    if String(result["reason"]) != "unchanged":
        bindings_changed.emit()
    return true


## Restores project.godot's bindings for every listed action.
func reset_defaults() -> void:
    cancel_capture("")
    InputBindings.reset_defaults()
    _set_status("Controls reset to defaults.")
    _rebuild(String(reset_button.name) if reset_button != null else "")
    bindings_changed.emit()


func close() -> void:
    cancel_capture("")
    var was_open: bool = is_open()
    super()
    if was_open:
        closed.emit()


func _on_cancel() -> bool:
    close()
    return true


func _hint_text() -> String:
    return nav_hint()


func _process(delta: float) -> void:
    if not is_capturing():
        return
    _capture_left -= delta
    if _capture_left <= 0.0:
        cancel_capture("Timed out. Nothing changed.")


func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if is_capturing():
        # Swallow everything while listening so nothing else reacts.
        if Engine.get_process_frames() != _capture_frame or not _is_press(event):
            capture_event(event)
        if not event is InputEventMouseMotion:
            get_viewport().set_input_as_handled()
        return
    super(event)


func _rebuild(focus_name: String) -> void:
    if is_open():
        _build_page(focus_name)


func _set_status(text: String) -> void:
    if status_label != null and is_instance_valid(status_label):
        status_label.text = text


static func _is_press(event: InputEvent) -> bool:
    if event is InputEventKey:
        return (event as InputEventKey).pressed and not (event as InputEventKey).echo
    if event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        return button.pressed and button.button_index not in [MOUSE_BUTTON_WHEEL_UP,
            MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
    if event is InputEventJoypadButton:
        return (event as InputEventJoypadButton).pressed
    if event is InputEventJoypadMotion:
        return absf((event as InputEventJoypadMotion).axis_value) >= InputBindings.AXIS_CAPTURE
    return false


## Esc (by label or position) or Start cancels a capture.
static func _is_cancel(event: InputEvent) -> bool:
    if event is InputEventKey:
        var key := event as InputEventKey
        return key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
    if event is InputEventJoypadButton:
        return (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
    return false
