extends SceneTree
## Release pipeline (Wave 3D): version.json parses with version/commit/built_at
## and agrees with config/version; the project name and icon are set; the
## title screen shows "v<version> · <commit>" bottom-right; export_presets.cfg
## parses as a ConfigFile with the Linux and Windows presets (embedded PCK, no
## console wrapper, paths under ../builds/) and an unsigned macOS preset.
## Run: godot --headless --path game --script res://tests/release_test.gd
## VersionInfo is pure (preloaded); Main.tscn uses autoloads, so it is load()ed.
const VersionInfo = preload("res://scripts/core/version_info.gd")
const LABEL_PATTERN := "^v\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.]+)? · (dev|[0-9a-f]{7,40})$"
var failures := 0
var checks := 0


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("FAIL RELEASE: " + detail)


func _run() -> void:
    _test_version_json()
    _test_project_settings()
    _test_presets()
    await _test_title_label()
    if failures == 0:
        print("PASS (%d checks): version.json, project name/icon/version, export presets, title version label" % checks)
    quit(1 if failures > 0 else 0)


func _test_version_json() -> void:
    check(FileAccess.file_exists("res://version.json"), "res://version.json exists")
    var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://version.json"))
    check(parsed is Dictionary, "version.json parses as an object")
    if not parsed is Dictionary:
        return
    for key in ["version", "commit", "built_at"]:
        check(parsed.has(key) and parsed[key] is String, "version.json has string key " + key)
    var project_version := str(ProjectSettings.get_setting("application/config/version", ""))
    check(str(parsed.get("version", "")) == project_version,
        "version.json version (%s) matches config/version (%s)" % [parsed.get("version", ""), project_version])
    check(str(parsed.get("commit", "")) != "", "commit is never empty ('dev' when unstamped)")
    var info: Dictionary = VersionInfo.info()
    check(info["version"] == project_version and info["commit"] == str(parsed["commit"]),
        "VersionInfo.info() reflects version.json")


func _test_project_settings() -> void:
    check(str(ProjectSettings.get_setting("application/config/name", "")) == "DCC Game",
        "project name is 'DCC Game'")
    var version := str(ProjectSettings.get_setting("application/config/version", ""))
    var semver := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.]+)?$")
    check(semver.search(version) != null, "config/version '%s' is semver" % version)
    var icon_path := str(ProjectSettings.get_setting("application/config/icon", ""))
    check(icon_path != "" and ResourceLoader.exists(icon_path), "config/icon exists (%s)" % icon_path)
    if ResourceLoader.exists(icon_path):
        var texture := load(icon_path) as Texture2D
        check(texture != null and texture.get_width() == 128 and texture.get_height() == 128,
            "icon is a 128x128 texture")


func _preset_section(cfg: ConfigFile, preset_name: String) -> String:
    for section in cfg.get_sections():
        if section.begins_with("preset.") and not section.ends_with(".options") \
                and str(cfg.get_value(section, "name", "")) == preset_name:
            return section
    return ""


func _test_presets() -> void:
    var cfg := ConfigFile.new()
    var err := cfg.load("res://export_presets.cfg")
    check(err == OK, "export_presets.cfg parses as a ConfigFile (error %d)" % err)
    if err != OK:
        return
    var expected := {
        "Linux x86_64": {"platform": "Linux", "path": "../builds/linux/dcc-game"},
        "Windows x86_64": {"platform": "Windows Desktop", "path": "../builds/windows/dcc-game.exe"},
    }
    for preset_name in expected.keys():
        var section := _preset_section(cfg, preset_name)
        check(section != "", "preset '%s' exists" % preset_name)
        if section == "":
            continue
        var want: Dictionary = expected[preset_name]
        check(str(cfg.get_value(section, "platform", "")) == want["platform"],
            "%s targets %s" % [preset_name, want["platform"]])
        check(str(cfg.get_value(section, "export_path", "")) == want["path"],
            "%s exports to %s" % [preset_name, want["path"]])
        check(str(cfg.get_value(section, "exclude_filter", "")).contains("tests/*"),
            "%s leaves the tests out" % preset_name)
        var options := section + ".options"
        check(bool(cfg.get_value(options, "binary_format/embed_pck", false)),
            "%s embeds the PCK" % preset_name)
        check(str(cfg.get_value(options, "binary_format/architecture", "")) == "x86_64",
            "%s is x86_64" % preset_name)
        check(int(cfg.get_value(options, "debug/export_console_wrapper", -1)) == 0,
            "%s has no console wrapper" % preset_name)
    var mac := _preset_section(cfg, "macOS")
    check(mac != "", "macOS preset exists")
    if mac != "":
        check(str(cfg.get_value(mac, "export_path", "")) == "../builds/macos/dcc-game.zip",
            "macOS exports a zip under ../builds/macos/")
        check(int(cfg.get_value(mac + ".options", "codesign/codesign", -1)) == 0,
            "macOS preset is unsigned")
        check(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)),
            "ETC2/ASTC import is on (required for the universal macOS export)")
    # Every export path stays inside the git-ignored builds/ folder.
    for section in cfg.get_sections():
        if section.begins_with("preset.") and not section.ends_with(".options"):
            check(str(cfg.get_value(section, "export_path", "")).begins_with("../builds/"),
                "%s exports under ../builds/" % section)


func _test_title_label() -> void:
    var pattern := RegEx.create_from_string(LABEL_PATTERN)
    check(pattern.search(VersionInfo.label_text()) != null,
        "VersionInfo.label_text() '%s' matches the pattern" % VersionInfo.label_text())
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    await process_frame
    await process_frame
    var title = game.title_screen
    check(title != null and title.is_open(), "the game boots to an open title screen")
    var label: Label = title.version_label if title != null else null
    check(label != null and label.is_visible_in_tree(), "the title screen has a visible version label")
    if label != null:
        check(pattern.search(label.text) != null, "version label '%s' matches the pattern" % label.text)
        check(label.text == VersionInfo.label_text(), "version label shows VersionInfo.label_text()")
        var view: Vector2 = Vector2(title.overlay.size)
        var rect: Rect2 = label.get_global_rect()
        check(rect.size.x > 0.0 and rect.end.x <= view.x + 0.5 and rect.end.x >= view.x - 40.0
            and rect.end.y <= view.y + 0.5 and rect.end.y >= view.y - 40.0,
            "version label sits in the bottom-right corner (%s in %s)" % [rect, view])
        # Reopening the title (e.g. after a run) must not add a second label.
        title.open()
        var count := 0
        for child in title.overlay.get_children():
            if child is Label and child.name.begins_with("VersionLabel"):
                count += 1
        check(count == 1, "reopening the title keeps a single version label (%d)" % count)
    game.queue_free()
    await process_frame
