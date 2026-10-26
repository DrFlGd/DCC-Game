extends SceneTree
## Integration test of the live Game scene (Main.tscn) and real menu signals.
## Run after import: godot --headless --path game --script res://tests/menu_integration_test.gd
## Game scripts reference the Events/RunState autoloads, so they are load()ed at
## runtime instead of preloaded (see tests/run_all.sh).
## Wave 3C: a gamepad-only traversal (title -> Settings -> Controls -> back)
## with synthesized InputEventJoypadButtons through Input.parse_input_event,
## so D-pad focus moves, A confirms and B backs out on the real screens.
var failures := 0


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL UI: " + description)


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event


## Presses and releases gamepad `button`, letting the engine dispatch both.
func _pad(button: JoyButton) -> void:
    for pressed in [true, false]:
        var event := InputEventJoypadButton.new()
        event.device = 0
        event.button_index = button
        event.pressed = pressed
        Input.parse_input_event(event)
        await process_frame


func _focus() -> Control:
    return get_root().gui_get_focus_owner()


## D-pad down until `target` has focus (at most `limit` presses).
func _pad_down_to(target: Control, limit: int) -> bool:
    for _i in range(limit):
        if _focus() == target:
            return true
        await _pad(JOY_BUTTON_DPAD_DOWN)
    return _focus() == target


## Wave 3C: title -> Settings -> Controls -> B -> B with the gamepad alone.
func _gamepad_traversal(game) -> void:
    await process_frame
    var title = game.title_screen
    check(game.state == game.State.TITLE and _focus() == title.new_run_button,
        "gamepad: title focuses New run")
    var settings_button: Button = null
    for node in title.center.find_children("*", "Button", true, false):
        if (node as Button).text == "Settings":
            settings_button = node
    check(await _pad_down_to(settings_button, 6), "gamepad: D-pad reaches Settings (focus %s)" % [_focus()])
    await _pad(JOY_BUTTON_A)
    var settings = game.settings_screen
    check(settings.is_open(), "gamepad: A opens settings")
    check(_focus() != null and _focus().name == "resolution", "gamepad: settings focuses its first row")
    check(await _pad_down_to(settings.controls_button, 24), "gamepad: D-pad reaches Remap controls (focus %s)"
        % [_focus()])
    await _pad(JOY_BUTTON_A)
    var controls = settings.controls_screen
    check(controls.is_open() and _focus() == controls.binding_button("move_up", "kbm"),
        "gamepad: A opens the controls screen with the first binding focused")
    await _pad(JOY_BUTTON_DPAD_DOWN)
    check(_focus() == controls.binding_button("move_down", "kbm"), "gamepad: D-pad moves down the bindings")
    await _pad(JOY_BUTTON_B)
    check(not controls.is_open() and settings.is_open() and _focus() == settings.controls_button,
        "gamepad: B closes controls back to Settings")
    await _pad(JOY_BUTTON_B)
    check(not settings.is_open() and game.state == game.State.TITLE and title.is_open()
        and _focus() == title.new_run_button, "gamepad: B closes settings back to the title")


## Wave 3C: Start pauses, D-pad up / left reach Inventory, A opens it with its list
## focused, B returns to the overview, B resumes; Back opens the map and B
## closes it.
func _gamepad_pause(game) -> void:
    game.start_run(424242)
    await process_frame
    var ui = game.character_menu
    await _pad(JOY_BUTTON_START)
    check(ui.mode == "pause" and game.state == game.State.PAUSED, "gamepad: Start pauses")
    var inventory: Button = null
    for node in ui.center.find_children("*", "Button", true, false):
        if (node as Button).text == "Inventory":
            inventory = node
    var reached := false
    await _pad(JOY_BUTTON_DPAD_UP)
    for _i in range(6):
        if _focus() == inventory:
            reached = true
            break
        await _pad(JOY_BUTTON_DPAD_LEFT)
    check(reached, "gamepad: D-pad reaches Inventory (focus %s)" % [_focus()])
    await _pad(JOY_BUTTON_A)
    check(ui.page == "inventory" and _focus() is ScrollContainer, "gamepad: inventory list focused")
    await _pad(JOY_BUTTON_B)
    check(ui.mode == "pause" and ui.page == "overview" and _focus() != null,
        "gamepad: B returns to the pause overview")
    await _pad(JOY_BUTTON_B)
    check(ui.mode == "closed" and game.state == game.State.RUNNING, "gamepad: B on the overview resumes")
    await _pad(JOY_BUTTON_BACK)
    check(game.state == game.State.MAP, "gamepad: Back opens the map from the HUD")
    await _pad(JOY_BUTTON_B)
    check(game.state == game.State.RUNNING, "gamepad: B closes the map")


func _run() -> void:
    var run_state: Node = get_root().get_node("RunState")
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    await _gamepad_traversal(game)
    await _gamepad_pause(game)
    game.show_title()
    var ui = game.character_menu
    check(game.name == "Game", "scene root is the Game node")
    for child in ["Player", "Combat", "RoomRenderer", "Hud", "CharacterMenu"]:
        check(game.has_node(child), "Game composes " + child)
    check(ui != null and not ui.is_open(), "game starts with no modal menu")
    check(game.state == game.State.TITLE, "game boots to the TITLE state")
    game.start_run(424242)
    check(game.state == game.State.RUNNING, "start_run enters RUNNING state")

    # A kill granting enough XP should freeze gameplay and open the allocation UI.
    run_state.award_xp(300)
    check(run_state.level == 2, "XP gains level 2")
    check(run_state.pending_stat_points == 2, "two unspent ability points awarded")
    check(ui.mode == "level_up" and ui.remaining_points() == 2, "level-up menu opens")
    check(game.state == game.State.LEVEL_UP, "state machine enters LEVEL_UP")
    var old_max: int = run_state.max_hp
    var original_hp: int = run_state.hp
    check(ui.stage_point("CON", 2), "player can allocate both points into CON")
    check(ui.remaining_points() == 0, "all points staged")
    # Wave 2F: the level also granted a skill point; confirm waits for it.
    check(run_state.skill_points == 1 and ui.skill_points() == 1, "one skill point awarded")
    check(not ui.can_confirm(), "confirm waits while a skill is learnable")
    ui.confirm_allocation()
    check(ui.mode == "level_up", "confirm refused with an unspent skill point")
    check(ui.pick_skill("skl_brawler") and run_state.skill_points == 0
        and ui.skill_points() == 0 and ui.can_confirm(), "a skill pick spends the point")
    ui.confirm_allocation()
    check(ui.mode == "closed", "confirmation resumes game")
    check(game.state == game.State.RUNNING, "state machine returns to RUNNING")
    check(run_state.pending_stat_points == 0, "unspent point bank cleared")
    check(int(run_state.ability_scores["CON"]) == 16, "confirmed CON score updates")
    check(run_state.max_hp == old_max + 2, "CON bonus updates level-based HP")
    check(run_state.hp == original_hp + 2, "CON bonus heals by gained max HP")

    # Escape (the `pause` action) opens pause, stops simulation, and shows stats.
    var escape := _key(KEY_ESCAPE)
    game._input(escape)
    check(ui.mode == "pause" and ui.page == "overview", "Escape opens pause menu")
    check(game.state == game.State.PAUSED, "state machine enters PAUSED")
    game.player.fire_cooldown = 1.0
    var before_pos: Vector2 = game.player.world_position
    var before_time: float = float(run_state.telemetry["run_time_seconds"])
    game._physics_process(0.6)
    check(game.player.fire_cooldown == 1.0 and game.player.world_position == before_pos,
        "combat timers and player position freeze while paused")
    check(float(run_state.telemetry["run_time_seconds"]) == before_time,
        "run clock freezes while paused")
    ui._open_character_page()
    check(ui.page == "character", "stat page is accessible from pause")
    check(ui.context["max_hp"] == run_state.max_hp and
        ui.context["level"] == run_state.level,
        "character stats show actual RPG state")
    game._input(escape)
    check(ui.mode == "closed", "Escape resumes from stat page")
    check(game.state == game.State.RUNNING, "Escape returns to RUNNING")

    # Resolution selection is available directly in pause; it changes only
    # screen dimensions, never the fixed 24x24 tile world.
    game._input(escape)
    check(ui.mode == "pause", "pause reopens for display settings")
    check(ui.RESOLUTION_PRESETS.has(Vector2i(1280, 720)) and
        ui.RESOLUTION_PRESETS.has(Vector2i(1920, 1080)),
        "standard resolution presets included")
    var choice: int = ui.RESOLUTION_PRESETS.find(Vector2i(1280, 720))
    ui._select_resolution(choice)
    check(ui.selected_resolution == Vector2i(1280, 720),
        "resolution dropdown stages the selected dimensions")
    ui._apply_resolution()
    check(game.get_window().size == Vector2i(1280, 720),
        "Apply changes Godot's actual window size")
    check(game.ROOM.size == Vector2(384, 384) and game.layout["arena"].size == Vector2(384, 384),
        "resolution cannot change gameplay room dimensions")
    check(game.renderer.layout == game.layout and game.hud.layout == game.layout,
        "renderer and HUD share the recomputed layout")
    game._input(escape)
    check(ui.mode == "closed", "pause closes after resolution apply")

    # A multi-level XP award must queue all points, even when levels are skipped.
    game.start_run(424242)
    run_state.award_xp(2700)
    check(run_state.level == 4, "multi-level XP award reaches level four")
    check(run_state.pending_stat_points == 6 and ui.mode == "level_up",
        "three level-ups grant six points without loss")
    check(run_state.skill_points == 3, "and three skill points")
    # Esc cannot bypass the mandatory allocation screen.
    game._input(escape)
    check(ui.mode == "level_up", "Escape does not bypass allocation")
    game.start_run(424242)
    check(ui.mode == "closed" and run_state.pending_stat_points == 0,
        "new run resets menu and points")
    check(game.state == game.State.RUNNING, "restart returns to RUNNING")

    # Debug shortcut allows reviewers to exercise the modal without grinding.
    game._unhandled_input(_key(KEY_F9))
    check(run_state.level == 2 and ui.mode == "level_up" and
        run_state.pending_stat_points == 2 and run_state.skill_points == 1,
        "F9 reaches the next XP threshold, grants the skill point and opens allocation")
    game.start_run(424242)

    # R restarts on the same seed via the restart_seed action.
    var seed_before: int = run_state.seed
    run_state.ticks = 1
    game._unhandled_input(_key(KEY_R))
    check(run_state.seed == seed_before and run_state.ticks == int(run_state.config["start_ticks"]),
        "R restarts the same seed with a full clock")

    # The physics loop reads Input Map actions (not raw keys).
    game.start_run(424242)
    var start_pos: Vector2 = game.player.world_position
    Input.action_press("move_right")
    for _i in range(10):
        game._physics_process(1.0 / 60.0)
    Input.action_release("move_right")
    check(game.player.world_position.x > start_pos.x and
        is_equal_approx(game.player.world_position.x - start_pos.x, 105.0 * 10.0 / 60.0),
        "move_right action moves the player at player_speed")
    Input.action_press("fire")
    game._physics_process(1.0 / 60.0)
    Input.action_release("fire")
    check(game.combat.projectiles.size() == 1 and int(run_state.telemetry["shots_fired"]) == 1,
        "fire action spawns one projectile per cooldown")
    check(is_equal_approx(game.player.fire_cooldown, game.player.FIRE_COOLDOWN),
        "fire cooldown unchanged (0.28s)")

    game.queue_free()
    if failures == 0:
        print("PASS: live menu opening, stat allocation, level jumps, pause/resume and time freeze")
    quit(1 if failures > 0 else 0)
