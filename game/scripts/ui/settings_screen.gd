extends "res://scripts/ui/screen_base.gd"
## Settings page, reachable from the title screen and the pause menu. Edits a
## Settings instance (scripts/core/settings.gd) in place and emits
## `setting_changed(key, value)` after each accepted change; Game saves,
## applies window changes and emits Events.settings_changed. `closed` fires
## when Back (or Esc, routed by Game) closes the page.

signal setting_changed(key: String, value: Variant)
signal closed

const Settings = preload("res://scripts/core/settings.gd")

var settings
var back_button: Button
var volume_label: Label
var music_label: Label
var sfx_label: Label
var shake_label: Label


func _ready() -> void:
    layer = 20
    super()


func open(target_settings) -> void:
    settings = target_settings
    var content := _begin(Vector2(520, 0), 0.75)
    content.add_child(_text("SETTINGS", 28, GOLD))
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 20)
    grid.add_theme_constant_override("v_separation", 8)
    content.add_child(grid)

    grid.add_child(_text("Window resolution", 15, MUTED))
    var resolution := OptionButton.new()
    for preset in Settings.RESOLUTION_PRESETS:
        resolution.add_item("%d × %d" % [preset.x, preset.y])
    resolution.select(Settings.RESOLUTION_PRESETS.find(settings.resolution))
    resolution.item_selected.connect(func(index: int):
        change("resolution", Settings.RESOLUTION_PRESETS[index]))
    grid.add_child(resolution)

    grid.add_child(_text("Fullscreen", 15, MUTED))
    var fullscreen := CheckButton.new()
    fullscreen.button_pressed = settings.fullscreen
    fullscreen.toggled.connect(func(on: bool): change("fullscreen", on))
    grid.add_child(fullscreen)

    volume_label = _text("", 15, MUTED)
    grid.add_child(volume_label)
    grid.add_child(_slider(settings.master_volume, "master_volume"))
    music_label = _text("", 15, MUTED)
    grid.add_child(music_label)
    grid.add_child(_slider(settings.music_volume, "music_volume"))
    sfx_label = _text("", 15, MUTED)
    grid.add_child(sfx_label)
    grid.add_child(_slider(settings.sfx_volume, "sfx_volume"))

    grid.add_child(_text("Damage numbers", 15, MUTED))
    var numbers := CheckButton.new()
    numbers.button_pressed = settings.show_damage_numbers
    numbers.toggled.connect(func(on: bool): change("show_damage_numbers", on))
    grid.add_child(numbers)

    shake_label = _text("", 15, MUTED)
    grid.add_child(shake_label)
    grid.add_child(_slider(settings.screen_shake, "screen_shake"))
    _update_labels()

    content.add_child(_text("Music also sets the ambience; effects also set menu sounds. Saved to user://settings.cfg.",
        11, MUTED))
    back_button = _button("Back  (Esc)", close)
    content.add_child(back_button)
    resolution.grab_focus()


## Applies one change through Settings validation; emits setting_changed when
## the value was accepted.
func change(key: String, value) -> bool:
    if settings == null or not settings.set_value(key, value):
        return false
    _update_labels()
    setting_changed.emit(key, settings.get(key))
    return true


func close() -> void:
    var was_open: bool = is_open()
    super()
    if was_open:
        closed.emit()


func _slider(value: float, key: String) -> HSlider:
    var slider := HSlider.new()
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 5
    slider.value = round(value * 100.0)
    slider.custom_minimum_size = Vector2(200, 28)
    slider.value_changed.connect(func(v: float): change(key, v / 100.0))
    return slider


func _update_labels() -> void:
    if volume_label != null:
        volume_label.text = "Master volume  %d%%" % roundi(settings.master_volume * 100.0)
    if music_label != null:
        music_label.text = "Music volume  %d%%" % roundi(settings.music_volume * 100.0)
    if sfx_label != null:
        sfx_label.text = "Effects volume  %d%%" % roundi(settings.sfx_volume * 100.0)
    if shake_label != null:
        shake_label.text = "Screen shake  %d%%" % roundi(settings.screen_shake * 100.0)
