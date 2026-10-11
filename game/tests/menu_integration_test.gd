extends SceneTree
## Integration test of the live Main node and real menu signals.
## Run after import: godot --headless --path game --script res://tests/menu_integration_test.gd
const Main = preload("res://scripts/main.gd")
var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL UI: " + description)

func _run() -> void:
    var main = Main.new()
    get_root().add_child(main)
    var ui = main.character_menu
    check(ui != null and not ui.is_open(), "game starts with no modal menu")

    # A kill granting enough XP should freeze gameplay and open the allocation UI.
    main._award_xp(300)
    check(main.player_level == 2, "XP gains level 2")
    check(main.pending_stat_points == 2, "two unspent ability points awarded")
    check(ui.mode == "level_up" and ui.remaining_points() == 2, "level-up menu opens")
    var old_max: int = main.player_max_hp
    var original_hp: int = main.player_hp
    check(ui.stage_point("CON", 2), "player can allocate both points into CON")
    check(ui.remaining_points() == 0, "all points staged")
    ui.confirm_allocation()
    check(ui.mode == "closed", "confirmation resumes game")
    check(main.pending_stat_points == 0, "unspent point bank cleared")
    check(int(main.ability_scores["CON"]) == 16, "confirmed CON score updates")
    check(main.player_max_hp == old_max + 2, "CON bonus updates level-based HP")
    check(main.player_hp == original_hp + 2, "CON bonus heals by gained max HP")

    # Escape opens pause, stops simulation, and supports a full character page.
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    main._input(escape)
    check(ui.mode == "pause" and ui.page == "overview", "Escape opens pause menu")
    main.fire_cooldown = 1.0
    var before_pos: Vector2 = main.player_position
    main._physics_process(0.6)
    check(main.fire_cooldown == 1.0 and main.player_position == before_pos,
        "combat timers and player position freeze while paused")
    ui._open_character_page()
    check(ui.page == "character", "stat page is accessible from pause")
    check(ui.context["max_hp"] == main.player_max_hp and
        ui.context["level"] == main.player_level,
        "character stats show actual RPG state")
    main._input(escape)
    check(ui.mode == "closed", "Escape resumes from stat page")

    # A multi-level XP award must queue all points, even when levels are skipped.
    main._start_run(424242)
    main._award_xp(2700)
    check(main.player_level == 4, "multi-level XP award reaches level four")
    check(main.pending_stat_points == 6 and ui.mode == "level_up",
        "three level-ups grant six points without loss")
    # Esc cannot bypass the mandatory allocation screen.
    main._input(escape)
    check(ui.mode == "level_up", "Escape does not bypass allocation")
    main._start_run(424242)
    check(ui.mode == "closed" and main.pending_stat_points == 0,
        "new run resets menu and points")

    # Debug shortcut allows reviewers to exercise the modal without grinding.
    var level_key := InputEventKey.new()
    level_key.keycode = KEY_F9
    level_key.pressed = true
    main._unhandled_input(level_key)
    check(main.player_level == 2 and ui.mode == "level_up" and
        main.pending_stat_points == 2,
        "F9 reaches the next XP threshold and opens allocation")
    main._start_run(424242)

    main.queue_free()
    if failures == 0:
        print("PASS: live menu opening, stat allocation, level jumps, pause/resume and time freeze")
    quit(1 if failures > 0 else 0)
