extends RefCounted
## Player settings persisted to `user://settings.cfg` (ConfigFile, section
## [settings]). Plain RefCounted, not an autoload: a test can build its own
## instance with a scratch path, and no autoload identifier is involved.
##
## The game uses one shared instance: `Settings.shared()` (with
## `const Settings = preload("res://scripts/core/settings.gd")`). Game loads it
## in _ready, applies the window settings, saves on every change made from the
## settings screen or the pause menu, and then emits
## `Events.settings_changed(values)`. Feature code (damage numbers, screen
## shake, audio) reads `Settings.shared()` and listens to that signal.
##
## Under a `--script` test run the shared instance uses `user://settings_test.cfg`
## so tests never overwrite a player's settings.
## No autoload references here: tests and character_menu.gd preload this file.

const PATH := "user://settings.cfg"
const TEST_PATH := "user://settings_test.cfg"
const SECTION := "settings"
## Common windowed resolutions offered by the settings screen and pause menu.
const RESOLUTION_PRESETS := [
    Vector2i(800, 600), Vector2i(960, 540), Vector2i(1024, 768),
    Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768),
    Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080),
    Vector2i(2560, 1440), Vector2i(3840, 2160)
]
const DEFAULT_RESOLUTION := Vector2i(960, 540)
## Setting keys, in the order the settings screen shows them.
const KEYS := ["resolution", "fullscreen", "master_volume", "music_volume", "sfx_volume",
    "show_damage_numbers", "screen_shake"]

static var _shared

## Where load()/save() read and write.
var path := PATH
## Windowed size; always one of RESOLUTION_PRESETS.
var resolution := DEFAULT_RESOLUTION
var fullscreen := false
## 0.0-1.0 linear volumes; scripts/audio.gd maps them to the audio buses
## (Master; Music and Ambient; SFX and UI), 0 = muted (-80 dB).
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
## Floating damage numbers (combat-feel work reads this).
var show_damage_numbers := true
## 0.0 (off) - 1.0 (full) screen-shake multiplier.
var screen_shake := 1.0


func _init(file_path: String = PATH) -> void:
    path = file_path


## The game's shared instance, loaded from disk on first use.
static func shared():
    if _shared == null:
        var test_run: bool = OS.get_cmdline_args().has("--script")
        _shared = new(TEST_PATH if test_run else PATH)
        _shared.load_settings()
    return _shared


## Reads `path`. A missing file keeps the defaults and returns false; invalid
## values are clamped or replaced by defaults.
func load_settings() -> bool:
    var file := ConfigFile.new()
    if file.load(path) != OK:
        return false
    for key in KEYS:
        set_value(key, file.get_value(SECTION, key, get(key)))
    return true


## Writes every key to `path`. Returns true on success.
func save_settings() -> bool:
    var file := ConfigFile.new()
    for key in KEYS:
        file.set_value(SECTION, key, get(key))
    return file.save(path) == OK


## Sets one key with validation. Returns false for an unknown key or a value
## that cannot be used (the old value is kept).
func set_value(key: String, value) -> bool:
    match key:
        "resolution":
            if not (value is Vector2i and RESOLUTION_PRESETS.has(value)):
                return false
            resolution = value
        "fullscreen":
            fullscreen = bool(value)
        "master_volume", "music_volume", "sfx_volume":
            set(key, clampf(float(value), 0.0, 1.0))
        "show_damage_numbers":
            show_damage_numbers = bool(value)
        "screen_shake":
            screen_shake = clampf(float(value), 0.0, 1.0)
        _:
            return false
    return true


func to_dict() -> Dictionary:
    var result: Dictionary = {}
    for key in KEYS:
        result[key] = get(key)
    return result


## Applies fullscreen / windowed resolution to `window`. Headless runs only
## change the size (there is no real window to centre or make fullscreen).
func apply_window(window: Window) -> void:
    var headless: bool = DisplayServer.get_name() == "headless"
    if fullscreen and not headless:
        window.mode = Window.MODE_FULLSCREEN
        return
    window.mode = Window.MODE_WINDOWED
    window.size = resolution
    if not headless:
        window.move_to_center()
