extends SceneTree
## Wave 3C input and accessibility: aim source rules (stick beats mouse,
## deadzone, movement fallback), aim-assist geometry, event-string round
## trips, rebinding (apply, swap, refuse, reserved inputs, defaults), settings
## persistence of the new keys and of [input] overrides, the text-scale
## helper, reduced flash in fx, device names for hint lines, the controls
## screen (build, capture, cancel, reset), and gamepad aim on the live Game.
## Run: godot --headless --path game --script res://tests/input_test.gd
## The preloaded modules never name an autoload; Main.tscn is load()ed.
const InputBindings = preload("res://scripts/core/input_bindings.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Accessibility = preload("res://scripts/core/accessibility.gd")
const Fx = preload("res://scripts/fx.gd")
const Player = preload("res://scripts/player.gd")
const SCRATCH := "user://test/input_test_settings.cfg"
var failures := 0


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL INPUT: " + detail)


func _run() -> void:
    DirAccess.make_dir_recursive_absolute("user://test")
    InputBindings.reset_defaults()
    _test_aim_resolution()
    _test_aim_assist()
    _test_event_strings()
    _test_rebinding()
    _test_defaults()
    _test_settings_persistence()
    _test_text_scale()
    _test_reduced_flash()
    _test_device_names()
    await _test_controls_screen()
    await _test_menus_live()
    await _test_live_gamepad_aim()
    InputBindings.reset_defaults()
    InputBindings.device = InputBindings.KEYBOARD
    if failures == 0:
        print("PASS: aim source, deadzone, fallback, aim assist, event strings, rebind/swap/refuse, defaults, persistence, text scale, reduced flash, hints, controls screen, live gamepad aim")
    quit(1 if failures > 0 else 0)


func _test_aim_resolution() -> void:
    var origin := Vector2(100, 100)
    var mouse := Vector2(100, 40)
    var opts: Dictionary = Player.AIM_DEFAULTS
    # A deflected stick wins even when the mouse moved in the same frame.
    var r: Dictionary = Player.resolve_aim(Vector2(0.8, 0.0), mouse, true, "keyboard", Vector2.LEFT,
        Vector2.ZERO, origin, opts)
    check(r["source"] == "stick" and r["device"] == "gamepad" and Vector2(r["direction"]).is_equal_approx(Vector2.RIGHT),
        "stick beats mouse when deflected: %s" % [r])
    # Below the 0.25 deadzone the stick is ignored: mouse when it moved...
    r = Player.resolve_aim(Vector2(0.2, 0.0), mouse, true, "gamepad", Vector2.LEFT, Vector2.ZERO, origin, opts)
    check(r["source"] == "mouse" and Vector2(r["direction"]).is_equal_approx(Vector2.UP),
        "inside the deadzone a moved mouse aims: %s" % [r])
    # ...or when the keyboard/mouse was the last device.
    r = Player.resolve_aim(Vector2.ZERO, mouse, false, "keyboard", Vector2.LEFT, Vector2.ZERO, origin, opts)
    check(r["source"] == "mouse" and r["device"] == "keyboard", "last device keyboard aims at the mouse")
    # Gamepad, stick centred, mouse still: hold the last direction...
    r = Player.resolve_aim(Vector2(0.1, 0.1), mouse, false, "gamepad", Vector2.LEFT, Vector2.ZERO, origin, opts)
    check(r["source"] == "hold" and Vector2(r["direction"]).is_equal_approx(Vector2.LEFT),
        "released stick keeps the last aim: %s" % [r])
    # ...or follow the movement when the fallback is on (default)...
    r = Player.resolve_aim(Vector2.ZERO, mouse, false, "gamepad", Vector2.LEFT, Vector2(0, 1), origin, opts)
    check(r["source"] == "move" and Vector2(r["direction"]).is_equal_approx(Vector2.DOWN),
        "movement fallback aims along the move: %s" % [r])
    # ...and not when it is off.
    var no_fallback: Dictionary = opts.duplicate()
    no_fallback["aim_fallback_to_move"] = false
    r = Player.resolve_aim(Vector2.ZERO, mouse, false, "gamepad", Vector2.LEFT, Vector2(0, 1), origin, no_fallback)
    check(r["source"] == "hold" and Vector2(r["direction"]).is_equal_approx(Vector2.LEFT),
        "fallback off holds the aim")
    # A custom deadzone moves the threshold.
    var wide: Dictionary = opts.duplicate()
    wide["aim_deadzone"] = 0.5
    r = Player.resolve_aim(Vector2(0.4, 0.0), mouse, false, "gamepad", Vector2.LEFT, Vector2.ZERO, origin, wide)
    check(r["source"] == "hold", "stick 0.4 is inside a 0.5 deadzone")
    # Mouse on top of the crawler keeps the held direction.
    r = Player.resolve_aim(Vector2.ZERO, origin + Vector2(1, 1), true, "keyboard", Vector2.LEFT, Vector2.ZERO,
        origin, opts)
    check(Vector2(r["direction"]).is_equal_approx(Vector2.LEFT), "mouse on the crawler keeps the aim")


func _test_aim_assist() -> void:
    var origin := Vector2.ZERO
    var right := Vector2.RIGHT
    var near_cone := Vector2(100, 0).rotated(deg_to_rad(5.0))
    var snapped: Vector2 = Player.assist_direction(origin, right, [near_cone], 8.0, 200.0)
    check(snapped.is_equal_approx(near_cone.normalized()), "a target 5 deg off snaps the aim")
    var outside := Vector2(100, 0).rotated(deg_to_rad(12.0))
    check(Player.assist_direction(origin, right, [outside], 8.0, 200.0) == right,
        "a target 12 deg off is outside an 8 deg cone")
    check(Player.assist_direction(origin, right, [Vector2(300, 0)], 8.0, 200.0) == right,
        "a target beyond the range is ignored")
    check(Player.assist_direction(origin, right, [near_cone], 0.0, 200.0) == right, "0 deg disables assist")
    var closer_angle := Vector2(150, 0).rotated(deg_to_rad(-2.0))
    var pick: Vector2 = Player.assist_direction(origin, right, [near_cone, closer_angle], 8.0, 200.0)
    check(pick.is_equal_approx(closer_angle.normalized()), "the smallest angle wins")
    var far_same := Vector2(180, 0).rotated(deg_to_rad(3.0))
    var near_same := Vector2(60, 0).rotated(deg_to_rad(3.0))
    pick = Player.assist_direction(origin, right, [far_same, near_same], 8.0, 200.0)
    check(pick.is_equal_approx(near_same.normalized()), "equal angles go to the nearer target")
    # Deterministic: the same inputs give the same answer, in any call order.
    check(Player.assist_direction(origin, right, [far_same, near_same], 8.0, 200.0) == pick,
        "assist is deterministic")
    # update_aim: assist only for gamepad aim.
    var player = Player.new()
    player.world_position = origin
    player.update_aim(Vector2(1, 0), Vector2(0, -50), false, "gamepad", Vector2.ZERO, [near_cone], true)
    check(player.aim_assisted and player.aim_direction.is_equal_approx(near_cone.normalized())
        and player.aim_raw.is_equal_approx(right), "gamepad aim is assisted, raw aim kept")
    player.update_aim(Vector2.ZERO, Vector2(100, 0), true, "gamepad", Vector2.ZERO, [near_cone], true)
    check(not player.aim_assisted and player.aim_device == "keyboard"
        and player.aim_direction.is_equal_approx(right), "mouse aim is never assisted")
    player.update_aim(Vector2(1, 0), Vector2.ZERO, false, "gamepad", Vector2.ZERO, [near_cone], false)
    check(not player.aim_assisted, "assist setting off disables it")
    check(player.reticle_point().is_equal_approx(Vector2(34, 0)), "reticle sits at reticle_distance")
    player.free()


func _test_event_strings() -> void:
    for text in ["key:90", "key:4194320", "keycode:4194305", "mouse:1", "mouse:2", "joy_button:2",
            "joy_button:14", "joy_axis:4:+", "joy_axis:1:-", "joy_axis:2:+"]:
        var event: InputEvent = InputBindings.string_to_event(text)
        check(event != null and InputBindings.event_to_string(event) == text, "round trip " + text)
    for bad in ["", "key", "key:", "key:abc", "key:0", "mouse:0", "mouse:12", "joy_axis:4",
            "joy_axis:4:x", "joy_button:-1", "pad:1"]:
        check(InputBindings.string_to_event(bad) == null, "rejects malformed '%s'" % bad)
    var captured := InputEventKey.new()
    captured.keycode = KEY_Z
    captured.physical_keycode = KEY_Z
    captured.device = 3
    check(InputBindings.event_to_string(captured) == "key:90", "physical keycode preferred")
    check(InputBindings.identity("keycode:82") == "key:82", "label and physical keys share an identity")
    check(InputBindings.column_of("mouse:1") == "kbm" and InputBindings.column_of("joy_axis:5:+") == "pad",
        "columns by device")
    var every: Array = []
    for action in InputBindings.action_ids():
        for text in InputBindings.current_strings(action):
            every.append(text)
    check(every.has("joy_axis:4:+") and every.has("mouse:1") and every.has("key:32"),
        "project bindings serialise (LT, LMB, Space)")


func _test_rebinding() -> void:
    InputBindings.reset_defaults()
    var r: Dictionary = InputBindings.rebind("fire", "kbm", "mouse:2")
    check(r["ok"] and InputBindings.column_strings("fire", "kbm") == PackedStringArray(["mouse:2"]),
        "fire rebinds to RMB in the Input Map: %s" % [r])
    var action_events: Array = InputMap.action_get_events("fire")
    check(action_events.size() == 2 and action_events[0] is InputEventMouseButton
        and (action_events[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT,
        "InputMap holds the new event")
    # Swap: melee onto interact's E; interact takes Space.
    r = InputBindings.rebind("melee", "kbm", "key:69")
    check(r["ok"] and r["swapped_with"] == "interact"
        and InputBindings.column_strings("melee", "kbm") == PackedStringArray(["key:69"])
        and InputBindings.column_strings("interact", "kbm") == PackedStringArray(["key:32"]),
        "conflict swaps: %s" % [r])
    # Refuse mode leaves both actions alone.
    r = InputBindings.rebind("dodge", "pad", "joy_button:0", "refuse")
    check(not r["ok"] and r["reason"] == "conflict"
        and InputBindings.column_strings("dodge", "pad") == PackedStringArray(["joy_button:1"]),
        "refuse mode refuses a taken button")
    # Gamepad swap including an axis: skill 1 onto RT (fire's), fire takes LT.
    r = InputBindings.rebind("use_skill_1", "pad", "joy_axis:5:+")
    check(r["ok"] and InputBindings.column_strings("fire", "pad") == PackedStringArray(["joy_axis:4:+"]),
        "axis swap: %s" % [r])
    # Reserved inputs: developer keys and pause's Esc / Start.
    check(InputBindings.rebind("fire", "kbm", "key:82")["reason"] == "reserved", "R (restart) is reserved")
    check(InputBindings.rebind("fire", "kbm", "key:4194340")["reason"] == "reserved", "F9 is reserved")
    check(InputBindings.rebind("melee", "kbm", "key:4194305")["reason"] == "reserved", "Esc is reserved")
    check(InputBindings.rebind("melee", "pad", "joy_button:6")["reason"] == "reserved", "Start is reserved")
    check(InputBindings.rebind("fire", "kbm", "joy_button:3")["reason"] == "wrong_column", "device checked")
    check(InputBindings.rebind("aim_up", "kbm", "key:73")["reason"] == "locked", "mouse aim column is fixed")
    check(InputBindings.rebind("restart_seed", "kbm", "key:73")["reason"] == "locked",
        "developer actions are not remappable")
    # Movement keeps its secondary arrow key; rebinding to the arrow drops the duplicate.
    r = InputBindings.rebind("move_up", "kbm", "key:73")
    check(r["ok"] and InputBindings.column_strings("move_up", "kbm") == PackedStringArray(["key:73", "key:4194320"]),
        "move_up primary replaced, arrow kept: %s" % [InputBindings.column_strings("move_up", "kbm")])
    # Pause keeps Esc and Start; an extra binding is added beside them.
    r = InputBindings.rebind("pause", "kbm", "key:80")
    var pause: PackedStringArray = InputBindings.current_strings("pause")
    check(r["ok"] and pause.has("keycode:4194305") and pause.has("joy_button:6") and pause.has("key:80"),
        "pause keeps Esc / Start: %s" % [pause])
    check(InputBindings.conflicts().is_empty(), "no input bound twice after rebinding: %s" % [InputBindings.conflicts()])
    _check_collision_rule("after rebinding")


## The inventory_test rule: no key, mouse or gamepad button on two gameplay actions.
func _check_collision_rule(label: String) -> void:
    var owners: Dictionary = {}
    for action in InputMap.get_actions():
        if String(action).begins_with("ui_"):
            continue
        for event in InputMap.action_get_events(action):
            var key := ""
            if event is InputEventKey:
                key = "key:%d" % (event.physical_keycode if event.physical_keycode != 0 else event.keycode)
            elif event is InputEventJoypadButton:
                key = "pad:%d" % event.button_index
            elif event is InputEventMouseButton:
                key = "mouse:%d" % event.button_index
            if key == "":
                continue
            check(not owners.has(key), "%s: %s bound to %s and %s" % [label, key, owners.get(key, ""), action])
            owners[key] = action


func _test_defaults() -> void:
    check(not InputBindings.overrides().is_empty(), "rebinding produced overrides")
    InputBindings.reset_defaults()
    check(InputBindings.overrides().is_empty(), "reset restores every default")
    for action in InputBindings.action_ids():
        check(not InputBindings.default_strings(action).is_empty(), "default exists: " + action)
        for column in InputBindings.COLUMNS:
            if InputBindings.is_remappable(action, column):
                check(not InputBindings.column_strings(action, column).is_empty(),
                    "default binding present: %s %s" % [action, column])
    _check_collision_rule("defaults")


func _test_settings_persistence() -> void:
    InputBindings.reset_defaults()
    var settings = Settings.new(SCRATCH)
    check(settings.text_scale == 1.0 and not settings.high_contrast and not settings.reduced_flash
        and not settings.colorblind_telegraphs and settings.aim_assist, "accessibility defaults")
    check(settings.set_value("text_scale", 1.25), "text_scale 1.25 accepted")
    check(not settings.set_value("text_scale", 1.1) and settings.text_scale == 1.25, "text_scale 1.1 refused")
    check(not settings.set_value("text_scale", "big"), "text_scale must be a number")
    for key in ["high_contrast", "reduced_flash", "colorblind_telegraphs"]:
        check(settings.set_value(key, true), key + " accepted")
    settings.set_value("aim_assist", false)
    InputBindings.rebind("use_item", "kbm", "key:70")
    InputBindings.rebind("dodge", "pad", "joy_button:8")
    settings.capture_bindings()
    check(settings.bindings.size() == 2, "two overridden actions captured: %s" % [settings.bindings])
    check(settings.save_settings(), "settings saved")
    var file := ConfigFile.new()
    check(file.load(SCRATCH) == OK and file.has_section("input")
        and Array(file.get_value("input", "use_item", [])).has("key:70"), "[input] section written")
    InputBindings.reset_defaults()
    var again = Settings.new(SCRATCH)
    check(again.load_settings(), "settings reloaded")
    check(again.text_scale == 1.25 and again.high_contrast and again.reduced_flash
        and again.colorblind_telegraphs and not again.aim_assist, "accessibility keys persist")
    check(again.to_dict().has("text_scale") and again.to_dict().has("reduced_flash"),
        "settings_changed payload carries the new keys")
    check(again.apply_bindings(), "saved bindings apply")
    check(InputBindings.column_strings("use_item", "kbm") == PackedStringArray(["key:70"])
        and InputBindings.column_strings("dodge", "pad") == PackedStringArray(["joy_button:8"]),
        "overrides reach the Input Map")
    # A hand-edited file binding one key twice falls back to the defaults.
    again.bindings = {"fire": PackedStringArray(["key:32", "joy_axis:5:+"])}
    check(not again.apply_bindings() and again.bindings.is_empty() and InputBindings.overrides().is_empty(),
        "conflicting overrides restore the defaults")
    again.bindings = {"melee": PackedStringArray(["nonsense", "key:71", "joy_button:10"]),
        "no_such_action": PackedStringArray(["key:72"]), "aim_up": PackedStringArray(["key:73", "joy_axis:3:-"])}
    check(again.apply_bindings() and InputBindings.column_strings("melee", "kbm") == PackedStringArray(["key:71"])
        and InputBindings.column_strings("aim_up", "kbm").is_empty(), "malformed entries skipped")
    InputBindings.reset_defaults()
    DirAccess.remove_absolute(SCRATCH)


func _test_text_scale() -> void:
    check(Accessibility.px(15, 1.0) == 15 and Accessibility.px(15, 1.25) == 19 and Accessibility.px(15, 1.5) == 23,
        "px(15) at 1.0/1.25/1.5")
    check(Accessibility.px(12, 1.5) == 18 and Accessibility.px(11, 1.25) == 14, "px rounding")
    var shared = Settings.shared()
    var before: float = shared.text_scale
    shared.set_value("text_scale", 1.5)
    check(Accessibility.px(14) == 21, "px reads the shared setting")
    shared.set_value("text_scale", before)
    var contrast: bool = shared.high_contrast
    shared.set_value("high_contrast", true)
    check(Accessibility.panel(Color(0.1, 0.1, 0.1, 0.5)).a > 0.9 and Accessibility.outline() > 0,
        "high contrast panels are opaque and text is outlined")
    var palette := {"melee": Color("#ff5a4f")}
    check(Accessibility.telegraph_color("melee", palette) != palette["melee"], "high contrast telegraph colour")
    shared.set_value("high_contrast", false)
    check(Accessibility.telegraph_color("melee", palette) == palette["melee"], "normal telegraph colour")
    shared.set_value("high_contrast", contrast)


func _test_reduced_flash() -> void:
    var normal := Fx.new()
    normal.flash("foe", Color(4, 4, 4, 1))
    check(is_equal_approx(float(normal.flashes["foe"]["left"]), Fx.FLASH_SECONDS)
        and is_equal_approx(normal.flash_amount("foe"), 1.0), "normal flash is full strength")
    check(is_equal_approx(normal.request_hitstop(0.09), 0.09), "normal hit-stop granted")
    var calm := Fx.new()
    calm.reduced_flash = true
    calm.flash("foe", Color(4, 4, 4, 1))
    check(float(calm.flashes["foe"]["left"]) <= Fx.REDUCED_FLASH_SECONDS, "reduced flash is shorter")
    check(calm.flash_amount("foe") <= Fx.REDUCED_FLASH_STRENGTH, "reduced flash is a subtle tint")
    check(calm.flash_color("foe").r <= 1.0, "no overbright white with reduced flash")
    check(calm.request_hitstop(0.09) <= Fx.REDUCED_HITSTOP_MAX + 0.000001, "hit-stop capped")
    check(calm.request_hitstop(0.12, true) <= Fx.REDUCED_HITSTOP_MAX + 0.000001, "forced hit-stop capped")
    calm.shake(Fx.SHAKE_HEAVY)
    normal.shake(Fx.SHAKE_HEAVY)
    check(calm.current_shake() <= normal.current_shake() * Fx.REDUCED_SHAKE_CAP + 0.0001
        and calm.current_shake() > 0.0, "shake capped, not removed")
    var shared = Settings.shared()
    var before: bool = shared.reduced_flash
    shared.set_value("reduced_flash", true)
    check(is_equal_approx(Accessibility.shake_scale(1.0), Accessibility.REDUCED_SHAKE_CAP)
        and is_equal_approx(Accessibility.shake_scale(0.1), 0.1), "grace shake follows the slider under the cap")
    check(Accessibility.steady(0.9, 0.4) == 0.4, "pulses hold steady")
    shared.set_value("reduced_flash", before)


func _test_device_names() -> void:
    InputBindings.reset_defaults()
    check(InputBindings.hint("melee", "keyboard") == "Space" and InputBindings.hint("melee", "gamepad") == "RB",
        "melee: Space / RB")
    check(InputBindings.hint("fire", "keyboard") == "LMB" and InputBindings.hint("fire", "gamepad") == "RT",
        "fire: LMB / RT")
    check(InputBindings.hint("pause", "keyboard") == "Esc" and InputBindings.hint("pause", "gamepad") == "Start",
        "pause: Esc / Start")
    check(InputBindings.move_hint("keyboard") == "WASD" and InputBindings.move_hint("gamepad") == "L-stick",
        "move hint")
    check(InputBindings.aim_hint("keyboard") == "Mouse" and InputBindings.aim_hint("gamepad") == "R-stick",
        "aim hint")
    check(InputBindings.hint("use_consumable", "gamepad") == "D-pad down", "belt on the D-pad")
    var button := InputEventJoypadButton.new()
    button.pressed = true
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(0.5, 0)
    var stick := InputEventJoypadMotion.new()
    stick.axis = JOY_AXIS_RIGHT_X
    stick.axis_value = 0.1
    check(InputBindings.classify(button) == "gamepad" and InputBindings.classify(motion) == ""
        and InputBindings.classify(stick) == "", "device classification ignores jitter")
    InputBindings.rebind("melee", "kbm", "key:71")
    check(InputBindings.hint("melee", "keyboard") == "G", "hints follow rebinding")
    var hud_script: GDScript = load("res://scripts/ui/hud.gd")
    var pad_lines: Array = hud_script.hint_segments("gamepad")
    var key_lines: Array = hud_script.hint_segments("keyboard")
    check(" | ".join(pad_lines[0]).contains("RB: melee") and " | ".join(key_lines[0]).contains("G: melee"),
        "HUD hint line switches wording by device")
    check(not " | ".join(pad_lines[1]).contains("R: replay"), "developer keys hidden from the gamepad hints")
    var wrapped: PackedStringArray = hud_script.wrap_segments(PackedStringArray(key_lines[0]), 300.0, 13)
    check(wrapped.size() > 1, "hint line wraps in a narrow window")
    InputBindings.reset_defaults()


func _test_controls_screen() -> void:
    InputBindings.reset_defaults()
    var screen = load("res://scripts/ui/controls_screen.gd").new()
    get_root().add_child(screen)
    var changes: Array = []
    screen.bindings_changed.connect(func(): changes.append(true))
    screen.open()
    await process_frame
    check(screen.is_open(), "controls screen opens")
    for action in InputBindings.action_ids():
        for column in InputBindings.COLUMNS:
            var button: Button = screen.binding_button(action, column)
            check(button != null, "button for %s %s" % [action, column])
            if button != null and InputBindings.is_remappable(action, column):
                check(button.text != "—" and not button.disabled, "%s %s is bound" % [action, column])
    for hidden in InputBindings.HIDDEN_ACTIONS:
        check(screen.binding_button(hidden, "kbm") == null, "developer action hidden: " + hidden)
    var focused: Control = get_root().gui_get_focus_owner()
    check(focused == screen.binding_button("move_up", "kbm"), "first binding has focus")
    # Capture a key for melee.
    check(screen.begin_capture("melee", "kbm") and screen.is_capturing(), "capture starts")
    var pad := InputEventJoypadButton.new()
    pad.button_index = JOY_BUTTON_Y
    pad.pressed = true
    check(screen.capture_event(pad) and screen.is_capturing(), "wrong device keeps listening")
    var release := InputEventKey.new()
    release.keycode = KEY_K
    check(not screen.capture_event(release), "a release is not a press")
    var key := InputEventKey.new()
    key.keycode = KEY_K
    key.physical_keycode = KEY_K
    key.pressed = true
    check(screen.capture_event(key) and not screen.is_capturing(), "key captured")
    check(InputBindings.column_strings("melee", "kbm") == PackedStringArray(["key:75"])
        and changes.size() == 1, "melee rebound to K and change reported")
    check(screen.binding_button("melee", "kbm").text == "K", "button shows the new key")
    # Escape cancels a capture without changing anything.
    screen.begin_capture("fire", "kbm")
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    check(screen.capture_event(escape) and not screen.is_capturing()
        and InputBindings.column_strings("fire", "kbm") == PackedStringArray(["mouse:1"]), "Esc cancels")
    # Start cancels a gamepad capture; a stick push binds an axis.
    screen.begin_capture("dodge", "pad")
    var start := InputEventJoypadButton.new()
    start.button_index = JOY_BUTTON_START
    start.pressed = true
    check(screen.capture_event(start) and not screen.is_capturing()
        and InputBindings.column_strings("dodge", "pad") == PackedStringArray(["joy_button:1"]), "Start cancels")
    screen.begin_capture("dodge", "pad")
    var small := InputEventJoypadMotion.new()
    small.axis = JOY_AXIS_TRIGGER_LEFT
    small.axis_value = 0.3
    check(not screen.capture_event(small) and screen.is_capturing(), "a light trigger touch is ignored")
    small.axis_value = 0.9
    check(screen.capture_event(small) and InputBindings.column_strings("dodge", "pad")
        == PackedStringArray(["joy_axis:4:+"]) and InputBindings.column_strings("use_skill_1", "pad")
        == PackedStringArray(["joy_button:1"]), "trigger captured, skill 1 swapped to B")
    # Reserved input refused through the screen.
    screen.begin_capture("melee", "kbm")
    var f9 := InputEventKey.new()
    f9.physical_keycode = KEY_F9
    f9.pressed = true
    check(screen.capture_event(f9) and InputBindings.column_strings("melee", "kbm")
        == PackedStringArray(["key:75"]) and screen.status_label.text.begins_with("Reserved"), "F9 refused")
    _check_collision_rule("controls screen")
    screen.reset_defaults()
    check(InputBindings.overrides().is_empty() and screen.binding_button("melee", "kbm").text == "Space",
        "reset to defaults")
    var closed: Array = []
    screen.closed.connect(func(): closed.append(true))
    screen._on_cancel()
    check(not screen.is_open() and closed.size() == 1, "B closes the controls screen")
    screen.queue_free()
    await process_frame


## Choice dialog B, and the settings page rebuilding for text size / contrast.
func _test_menus_live() -> void:
    var dialog = load("res://scripts/ui/choice_dialog.gd").new()
    get_root().add_child(dialog)
    var cancelled: Array = []
    dialog.cancelled.connect(func(): cancelled.append(true))
    dialog.open("Shrine", "An offer.", [{"id": "a", "label": "Accept"}])
    var b := InputEventJoypadButton.new()
    b.button_index = JOY_BUTTON_B
    b.pressed = true
    dialog._input(b)
    check(not dialog.is_open() and cancelled.size() == 1, "B cancels the choice dialog")
    dialog.queue_free()
    var page = load("res://scripts/ui/settings_screen.gd").new()
    get_root().add_child(page)
    var scratch = Settings.new(SCRATCH)
    var seen: Array = []
    page.setting_changed.connect(func(key, _value): seen.append(key))
    page.open(scratch)
    await process_frame
    check(page.controls_button != null and page.center.find_child("text_scale", true, false) != null
        and page.center.find_child("reduced_flash", true, false) != null, "settings lists the 3C rows")
    var before_size: int = page.back_button.get_theme_font_size("font_size")
    var shared = Settings.shared()
    var shared_scale: float = shared.text_scale
    shared.set_value("text_scale", 1.5)
    check(page.change("text_scale", 1.5) and seen.has("text_scale"), "text size change emitted")
    await process_frame
    check(page.back_button.get_theme_font_size("font_size") > before_size, "page rebuilt at the new size")
    check(page.center.find_child("text_scale", true, false) == get_root().gui_get_focus_owner(),
        "focus kept on the text size row")
    shared.set_value("text_scale", shared_scale)
    page.open_controls()
    check(page.controls_screen.is_open(), "Remap controls opens the controls screen")
    page.back()
    check(not page.controls_screen.is_open() and page.is_open(), "back closes controls first")
    page.back()
    check(not page.is_open(), "then the settings page")
    page.queue_free()
    await process_frame


func _test_live_gamepad_aim() -> void:
    var events: Node = get_root().get_node("Events")
    var devices: Array = []
    events.input_device_changed.connect(func(device): devices.append(device))
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    var assist_before: bool = game.settings.aim_assist
    game.settings.aim_assist = false
    game.start_run(424242)
    InputBindings.device = InputBindings.KEYBOARD
    game._physics_process(1.0 / 60.0)
    check(game.hud.reticle == Vector2.INF, "no reticle for mouse aim")
    Input.action_press("aim_up", 1.0)
    game._physics_process(1.0 / 60.0)
    check(game.player.aim_device == "gamepad" and game.player.aim_direction.is_equal_approx(Vector2.UP),
        "right stick aims the crawler: %s" % [game.player.aim_direction])
    check(InputBindings.device == "gamepad" and devices.has("gamepad"), "device switch announced")
    check(game.hud.reticle != Vector2.INF and game.hud.reticle.is_equal_approx(game.player.reticle_point()),
        "reticle shown for gamepad aim")
    check(" | ".join(game.hud.hint_segments()[0]).contains("RT: shoot"), "HUD hints in gamepad wording")
    Input.action_release("aim_up")
    Input.action_press("move_left", 1.0)
    game._physics_process(1.0 / 60.0)
    Input.action_release("move_left")
    check(game.player.aim_source == "move" and game.player.aim_direction.is_equal_approx(Vector2.LEFT),
        "stick released: aim follows movement")
    game._physics_process(1.0 / 60.0)
    check(game.player.aim_source == "hold" and game.player.aim_direction.is_equal_approx(Vector2.LEFT),
        "standing still holds the aim")
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(12, 0)
    game._input(motion)
    check(InputBindings.device == "keyboard" and devices.back() == "keyboard", "mouse motion switches back")
    game._physics_process(1.0 / 60.0)
    check(game.player.aim_device == "keyboard" and game.hud.reticle == Vector2.INF, "reticle hidden for mouse")
    # B closes the floor map.
    check(game.open_map(), "map opens")
    var b := InputEventJoypadButton.new()
    b.button_index = JOY_BUTTON_B
    b.pressed = true
    game._input(b)
    check(game.state == game.State.RUNNING, "B closes the floor map")
    game.settings.aim_assist = assist_before
    game.queue_free()
    await process_frame
