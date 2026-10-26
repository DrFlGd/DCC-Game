extends "res://scripts/ui/screen_base.gd"
## Settings page, reachable from the title screen and the pause menu. Edits a
## Settings instance (scripts/core/settings.gd) in place and emits
## `setting_changed(key, value)` after each accepted change; Game saves,
## applies window changes and emits Events.settings_changed. `closed` fires
## when Back (or Esc, routed by Game) closes the page.
##
## Wave 3C: accessibility rows (text size, high contrast, reduced flash,
## colour-blind telegraphs, gamepad aim assist) and a "Controls…" button that
## opens the controls screen (ui/controls_screen.gd, a child of this node).
## Rebinding there is relayed as setting_changed("input_bindings", overrides)
## so Game saves it like any other setting. Changing text size or contrast
## rebuilds this page at once, keeping focus. The rows sit in a scroll box so
## the page fits a 480 px tall window at 150 % text.

signal setting_changed(key: String, value: Variant)
signal closed

const Settings = preload("res://scripts/core/settings.gd")
const ControlsScreen = preload("res://scripts/ui/controls_screen.gd")
## Settings that change how this page itself looks (rebuilt after a change).
const RESTYLE_KEYS := ["text_scale", "high_contrast"]

var settings
var back_button: Button
var controls_button: Button
var controls_screen: ControlsScreen
var volume_label: Label
var music_label: Label
var sfx_label: Label
var shake_label: Label


func _ready() -> void:
    layer = 20
    super()
    controls_screen = ControlsScreen.new()
    controls_screen.name = "ControlsScreen"
    add_child(controls_screen)
    controls_screen.bindings_changed.connect(func():
        setting_changed.emit("input_bindings", InputBindings.overrides()))
    controls_screen.closed.connect(_on_controls_closed)


func open(target_settings) -> void:
    settings = target_settings
    _build_page("")


func _build_page(focus_name: String) -> void:
    var content := _begin(Vector2(560, 0), 0.75)
    content.add_child(_text("SETTINGS", 28, GOLD))
    var scroll := ScrollContainer.new()
    var view_height: float = 540.0
    if is_inside_tree():
        view_height = get_viewport().get_visible_rect().size.y
    scroll.custom_minimum_size = Vector2(540, clampf(view_height - 200.0 * Accessibility.text_scale(),
        150.0, 420.0))
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    content.add_child(scroll)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 20)
    grid.add_theme_constant_override("v_separation", 8)
    scroll.add_child(grid)

    grid.add_child(_label("Window resolution"))
    var resolution := OptionButton.new()
    resolution.name = "resolution"
    for preset in Settings.RESOLUTION_PRESETS:
        resolution.add_item("%d × %d" % [preset.x, preset.y])
    resolution.select(Settings.RESOLUTION_PRESETS.find(settings.resolution))
    resolution.item_selected.connect(func(index: int):
        change("resolution", Settings.RESOLUTION_PRESETS[index]))
    _style_control(resolution)
    grid.add_child(resolution)

    grid.add_child(_label("Fullscreen"))
    grid.add_child(_toggle("fullscreen"))

    volume_label = _label("")
    grid.add_child(volume_label)
    grid.add_child(_slider(settings.master_volume, "master_volume"))
    music_label = _label("")
    grid.add_child(music_label)
    grid.add_child(_slider(settings.music_volume, "music_volume"))
    sfx_label = _label("")
    grid.add_child(sfx_label)
    grid.add_child(_slider(settings.sfx_volume, "sfx_volume"))

    grid.add_child(_label("Damage numbers"))
    grid.add_child(_toggle("show_damage_numbers"))

    shake_label = _label("")
    grid.add_child(shake_label)
    grid.add_child(_slider(settings.screen_shake, "screen_shake"))

    # Wave 3C accessibility.
    grid.add_child(_label("Text size"))
    var text_size := OptionButton.new()
    text_size.name = "text_scale"
    for option in Settings.TEXT_SCALES:
        text_size.add_item("%d %%" % roundi(float(option) * 100.0))
    text_size.select(maxi(0, Settings.TEXT_SCALES.find(settings.text_scale)))
    text_size.item_selected.connect(func(index: int):
        change("text_scale", Settings.TEXT_SCALES[index]))
    _style_control(text_size)
    grid.add_child(text_size)
    grid.add_child(_label("High contrast"))
    grid.add_child(_toggle("high_contrast"))
    grid.add_child(_label("Reduced flashing"))
    grid.add_child(_toggle("reduced_flash"))
    grid.add_child(_label("Patterned telegraphs"))
    grid.add_child(_toggle("colorblind_telegraphs"))
    grid.add_child(_label("Gamepad aim assist"))
    grid.add_child(_toggle("aim_assist"))
    _update_labels()

    var note := _text("Music also sets the ambience; effects also set menu sounds. Reduced flashing"
        + " also caps hit-stop and screen shake. Saved to user://settings.cfg.", 11, MUTED)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.custom_minimum_size.x = 540
    content.add_child(note)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    content.add_child(row)
    controls_button = _button("Controls…", open_controls)
    controls_button.name = "controls"
    row.add_child(controls_button)
    back_button = _button("Back", close)
    back_button.name = "back"
    row.add_child(back_button)
    _add_hint(content)
    var target: Node = center.find_child(focus_name, true, false) if focus_name != "" else null
    if target is Control:
        (target as Control).grab_focus()
    else:
        resolution.grab_focus()


## Applies one change through Settings validation; emits setting_changed when
## the value was accepted. Text size and contrast rebuild the page.
func change(key: String, value) -> bool:
    if settings == null or not settings.set_value(key, value):
        return false
    _update_labels()
    setting_changed.emit(key, settings.get(key))
    if RESTYLE_KEYS.has(key) and is_open():
        call_deferred("_build_page", key)
    return true


## Opens the controls screen above this page.
func open_controls() -> void:
    if is_open():
        controls_screen.open()


## Esc / Start (through Game) and B: closes the controls screen when it is
## open (cancelling a capture first), otherwise this page.
func back() -> void:
    if controls_screen != null and controls_screen.is_open():
        if controls_screen.is_capturing():
            controls_screen.cancel_capture()
        else:
            controls_screen.close()
        return
    close()


func close() -> void:
    if controls_screen != null and controls_screen.is_open():
        controls_screen.close()
    var was_open: bool = is_open()
    super()
    if was_open:
        closed.emit()


func _on_cancel() -> bool:
    back()
    return true


func _on_controls_closed() -> void:
    if is_open() and controls_button != null and is_instance_valid(controls_button):
        controls_button.grab_focus()


func _label(value: String) -> Label:
    return _text(value, 15, MUTED)


func _toggle(key: String) -> CheckButton:
    var toggle := CheckButton.new()
    toggle.name = key
    toggle.button_pressed = bool(settings.get(key))
    toggle.toggled.connect(func(on: bool): change(key, on))
    _style_control(toggle)
    return toggle


func _style_control(control: Control) -> void:
    control.add_theme_font_size_override("font_size", Accessibility.px(15))


func _slider(value: float, key: String) -> HSlider:
    var slider := HSlider.new()
    slider.name = key
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 5
    slider.value = round(value * 100.0)
    slider.custom_minimum_size = Vector2(200, 28)
    slider.value_changed.connect(func(v: float): change(key, v / 100.0))
    return slider


func _update_labels() -> void:
    if volume_label != null and is_instance_valid(volume_label):
        volume_label.text = "Master volume  %d%%" % roundi(settings.master_volume * 100.0)
    if music_label != null and is_instance_valid(music_label):
        music_label.text = "Music volume  %d%%" % roundi(settings.music_volume * 100.0)
    if sfx_label != null and is_instance_valid(sfx_label):
        sfx_label.text = "Effects volume  %d%%" % roundi(settings.sfx_volume * 100.0)
    if shake_label != null and is_instance_valid(shake_label):
        shake_label.text = "Screen shake  %d%%" % roundi(settings.screen_shake * 100.0)
