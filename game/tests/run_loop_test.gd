extends SceneTree
## Wave 2A run loop on the live Game scene: TITLE -> start_run, multi-floor
## descent (exit -> intermission -> next floor with a fresh budget), exit with
## the last tick, victory on target_depth, SUMMARY after death / abandon,
## run-time accounting, pause -> settings, and the settings file roundtrip.
## Run: godot --headless --path game --script res://tests/run_loop_test.gd
## Game scripts reference autoloads, so they are load()ed at runtime; the pure
## modules below are safe to preload (see tests/run_all.sh).
const RunRules = preload("res://scripts/core/run_rules.gd")
const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Settings = preload("res://scripts/core/settings.gd")
const SEED := 424242
const ROUNDTRIP_PATH := "user://settings_roundtrip_test.cfg"
var failures := 0
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL RUNLOOP: " + detail)


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event


func _record(name: String, args: Array) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(args)


## Marks the boss dead, stands in the boss room and walks into the exit.
func _take_exit(game, rs: Node, ticks: int = -1) -> void:
    var boss_id: int = int(rs.floor["boss_id"])
    var exit_id: int = int(rs.floor["exit_id"])
    rs.boss_defeated = true
    rs.current_room_id = boss_id
    rs.visited[boss_id] = true
    game._load_room(boss_id)
    if ticks >= 0:
        rs.ticks = ticks
    for side in rs.floor["rooms"][boss_id]["neighbors"]:
        if int(rs.floor["rooms"][boss_id]["neighbors"][side]) == exit_id:
            game._enter_neighbor(side)
            return
    check(false, "boss room has a door to the exit")


func _kill_player(game, rs: Node) -> void:
    for _i in range(200):
        if rs.hp <= 0:
            break
        game.player.invulnerability = 0.0
        game.combat.hit_player(30, 6, 1, "rat_scavenger")


func _run() -> void:
    var events: Node = get_root().get_node("Events")
    var rs: Node = get_root().get_node("RunState")
    events.floor_cleared.connect(func(d): _record("floor_cleared", [d]))
    events.floor_started.connect(func(d, _f): _record("floor_started", [d]))
    events.run_ended.connect(func(o, s): _record("run_ended", [o, s]))
    events.settings_changed.connect(func(s): _record("settings_changed", [s]))
    _rules_checks(rs)
    _settings_roundtrip()

    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    var S = game.State

    # --- TITLE ------------------------------------------------------------
    check(game.state == S.TITLE and game.title_screen.is_open(), "boot shows the title screen")
    check(not game.hud.visible, "HUD hidden on the title screen")
    check(game.settings == Settings.shared() and game.settings.path == Settings.TEST_PATH,
        "Game uses the shared settings (test file under --script)")
    var runs_before: int = seen.get("run_ended", []).size()
    game._unhandled_input(_key(KEY_R))
    check(game.state == S.TITLE, "R does nothing on the title screen")
    check(not game.title_screen.submit_seed("not a seed") and game.state == S.TITLE,
        "invalid seed text is rejected")
    check(game.title_screen.parse_seed("0") == -1 and game.title_screen.parse_seed("99999999999") == -1
        and game.title_screen.parse_seed(" 77 ") == 77, "seed parsing bounds")
    check(game.title_screen.submit_seed(str(SEED)), "seeded run accepted")
    check(game.state == S.RUNNING and rs.seed == SEED and not game.title_screen.is_open(),
        "TITLE -> seeded start_run -> RUNNING")
    check(game.hud.visible, "HUD visible while running")

    # --- Floor 1 budget ----------------------------------------------------
    check(rs.depth == 1 and rs.floor["rooms"].size() == 22, "floor 1 has 22 rooms")
    check(rs.ticks == 26 and rs.floor_budget == 26, "floor 1 budget is 26 for seed 424242")
    check(int(rs.telemetry["ticks_granted"]) == 26, "floor budget counted as ticks_granted")

    # --- Exit -> intermission -> floor 2 ------------------------------------
    var first_dir := ""
    for side in rs.floor["rooms"][0]["neighbors"]:
        if rs.floor["rooms"][int(rs.floor["rooms"][0]["neighbors"][side])]["kind"] == "normal":
            first_dir = side
            break
    game._enter_neighbor(first_dir)
    rs.award_xp(120)
    rs.apply_damage_to_player(6, "test")
    var xp_before: int = rs.xp
    var scores_before: Dictionary = rs.ability_scores.duplicate(true)
    var level_before: int = rs.level
    game._physics_process(0.5)
    var time_before: float = float(rs.telemetry["run_time_seconds"])
    check(time_before > 0.0, "run time advances while RUNNING")
    seen.erase("floor_cleared")
    _take_exit(game, rs)
    check(seen.get("floor_cleared", []) == [[1]], "exit emits floor_cleared(1)")
    check(game.state == S.INTERMISSION and game.intermission_screen.is_open(),
        "exit opens the intermission")
    check(rs.outcome == "running" and int(rs.telemetry["floors_cleared"]) == 1,
        "run continues; floors_cleared counted")
    var recap: Dictionary = game.intermission_screen.recap
    check(int(recap["depth"]) == 1 and int(recap["rooms_explored"]) == rs.visited.size()
        and int(recap["rooms_total"]) == 22 and int(recap["budget"]) == 26,
        "intermission recap: floor, rooms explored / total, budget")
    check(int(recap["healed"]) == 3 and rs.hp == rs.max_hp - 3,
        "intermission heals half the missing HP, rounded up")
    check(game.intermission_screen.descend_button.has_focus(), "Descend button has focus")
    game._physics_process(2.0)
    check(float(rs.telemetry["run_time_seconds"]) == time_before,
        "run time frozen during the intermission")
    game._unhandled_input(_key(KEY_R))
    check(game.state == S.INTERMISSION, "R does nothing on the intermission")
    var hp_carry: int = rs.hp
    game.intermission_screen.descend_requested.emit()
    check(game.state == S.RUNNING and rs.depth == 2, "Descend starts floor 2")
    check(seen.get("floor_started", []).back() == [2], "floor_started(2)")
    check(rs.floor["seed"] == rs.floor_seed(2) and rs.floor["rooms"].size() == 26,
        "floor 2 uses floor_seed(2) and 26 rooms")
    check(rs.visited.keys() == [int(rs.floor["start_id"])] and rs.room_states.size() == 1,
        "visited and room_states reset (start room only)")
    check(not rs.boss_defeated and rs.tick_ledger.is_empty(), "boss flag and ledger reset")
    var expected_budget: int = RunRules.floor_budget(rs.floor, game.rules, rs.config)
    check(rs.ticks == expected_budget and rs.floor_budget == expected_budget and expected_budget == 30,
        "fresh floor 2 budget (30 for seed 424242)")
    check(rs.xp == xp_before and rs.level == level_before and rs.ability_scores == scores_before
        and rs.hp == hp_carry, "XP, level, scores and HP carry over")
    check(game.player.world_position == game.ROOM.get_center(), "player placed at start centre")

    # --- Exit with exactly the last tick is a success -----------------------
    _take_exit(game, rs, 1)
    check(rs.ticks == 0 and game.state == S.INTERMISSION and rs.outcome == "running",
        "exit paid with the last tick clears the floor instead of collapsing")
    game.descend()

    # --- Victory on target_depth --------------------------------------------
    var target: int = RunRules.target_depth(rs.config)
    check(target == 6, "default target_depth is 6")
    while rs.depth < target:
        check(rs.floor["rooms"].size() == RunRules.room_count(rs.depth, rs.config),
            "floor %d room count" % rs.depth)
        _take_exit(game, rs)
        check(game.state == S.INTERMISSION, "floor %d -> intermission" % rs.depth)
        game.descend()
    check(rs.depth == 6 and rs.floor["rooms"].size() == 44, "floor 6 has 44 rooms")
    _take_exit(game, rs)
    check(game.state == S.SUMMARY and rs.outcome == "victory", "exit on floor 6 wins the run")
    var won: Dictionary = seen["run_ended"].back()[1]
    check(won["outcome"] == "victory" and int(won["floors_cleared"]) == 6
        and won["floors"].size() == 6 and int(won["depth"]) == 6, "victory summary")
    check(game.summary_screen.is_open() and game.summary_screen.seed_field.text == str(SEED),
        "summary shows the seed")

    # --- SUMMARY after death; R / Retry / Title ----------------------------
    game._unhandled_input(_key(KEY_R))
    check(game.state == S.RUNNING and rs.seed == SEED and rs.depth == 1,
        "R on the summary retries the seed")
    _kill_player(game, rs)
    check(game.state == S.SUMMARY and game.summary_screen.is_open(), "death opens SUMMARY")
    var died: Dictionary = game.summary_screen.summary
    check(died["outcome"] == "defeated" and died["cause"] == "rat_scavenger"
        and died["floors"].size() == 1 and died["floors"][0]["result"] == "defeated",
        "death summary: outcome, cause, floor record")
    for key in ["ticks_granted", "floors_cleared", "run_time_seconds", "ticks_spent",
            "damage_dealt", "damage_taken", "kills", "level", "xp", "seed"]:
        check(died.has(key), "summary has " + key)
    check(game.summary_screen.retry_button.has_focus(), "Retry seed has focus")
    game.summary_screen.retry_requested.emit()
    check(game.state == S.RUNNING and rs.seed == SEED and not game.summary_screen.is_open(),
        "Retry seed restarts")
    _kill_player(game, rs)
    game.summary_screen.new_run_requested.emit()
    check(game.state == S.RUNNING and rs.outcome == "running", "New run from summary")
    _kill_player(game, rs)
    game.summary_screen.title_requested.emit()
    check(game.state == S.TITLE and game.title_screen.is_open() and not game.summary_screen.is_open(),
        "Title from summary")
    game.title_screen.new_run_requested.emit()
    check(game.state == S.RUNNING and rs.seed >= 1, "New run from title uses a random seed")

    # --- Pause -> settings -> back; abandon ----------------------------------
    var escape := _key(KEY_ESCAPE)
    game._input(escape)
    check(game.state == S.PAUSED, "Esc pauses")
    game.character_menu.settings_requested.emit()
    check(game.settings_screen.is_open(), "settings reachable from the pause menu")
    seen.erase("settings_changed")
    check(game.settings_screen.change("screen_shake", 0.5), "settings screen change accepted")
    check(game.settings.screen_shake == 0.5 and seen.get("settings_changed", []).size() == 1
        and seen["settings_changed"][0][0]["screen_shake"] == 0.5, "settings_changed emitted")
    var reread = Settings.new(Settings.TEST_PATH)
    check(reread.load_settings() and reread.screen_shake == 0.5, "change saved to disk")
    game._input(escape)
    check(not game.settings_screen.is_open() and game.state == S.PAUSED
        and game.character_menu.mode == "pause", "Esc closes settings back to the pause menu")
    game.character_menu._open_abandon_page()
    game.character_menu._confirm_abandon()
    check(game.state == S.SUMMARY and rs.outcome == "abandoned" and rs.cause == "abandoned",
        "abandon ends the run as abandoned")
    game.show_title()
    game.title_screen.settings_requested.emit()
    check(game.settings_screen.is_open(), "settings reachable from the title screen")
    game.settings_screen.close()
    check(game.state == S.TITLE and game.title_screen.is_open(), "closing settings returns to title")

    # --- Legacy direct start_run from any state ------------------------------
    game.start_run(SEED)
    check(game.state == S.RUNNING and rs.ticks == 26, "start_run works directly from TITLE")
    check(seen.get("run_ended", []).size() > runs_before, "runs ended during the test")

    game.queue_free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.TEST_PATH))
    if failures == 0:
        print("PASS: title, multi-floor descent with fresh budgets, last-tick exit, victory, summary, settings")
    quit(1 if failures > 0 else 0)


func _rules_checks(rs: Node) -> void:
    check(rs.ensure_config(), "config loads")
    var counts: Array = []
    for depth in range(1, 8):
        counts.append(RunRules.room_count(depth, rs.config))
    check(counts == [22, 26, 30, 34, 40, 44, 50], "rooms_by_depth then +6: %s" % [counts])
    check(RunRules.room_count(12, rs.config) == 80 and RunRules.room_count(30, rs.config) == 80,
        "room count capped at 80")
    check(RunRules.slack(22, rs.config) == 10 and RunRules.slack(10, rs.config) == 8
        and RunRules.slack(20, rs.config) == 9, "slack = max(8, ceil(0.45 x rooms))")
    var policy = Collapse.new(rs.config["collapse"])
    var floor_one: Dictionary = Generator.generate(SEED, 22)
    check(RunRules.mandatory_route_cost(floor_one, policy) == 16
        and RunRules.floor_budget(floor_one, policy, rs.config) == 26,
        "seed 424242 floor 1: route 16 + slack 10 = 26")
    # COLLAPSE_SYSTEM §9: slack >= min_slack and budgets stay readable.
    for run_seed in [1, 7, 99, 424242, 1234567]:
        for depth in range(1, 7):
            var d_seed: int = run_seed if depth == 1 else int((run_seed + (depth - 1) * 1000003) % 2147483647)
            var generated: Dictionary = Generator.generate(d_seed, RunRules.room_count(depth, rs.config))
            var route: int = RunRules.mandatory_route_cost(generated, policy)
            var budget: int = RunRules.floor_budget(generated, policy, rs.config)
            check(route > 0 and budget - route >= 8 and budget <= 70,
                "seed %d depth %d budget %d route %d" % [run_seed, depth, budget, route])


func _settings_roundtrip() -> void:
    var path_abs: String = ProjectSettings.globalize_path(ROUNDTRIP_PATH)
    DirAccess.remove_absolute(path_abs)
    var fresh = Settings.new(ROUNDTRIP_PATH)
    check(not fresh.load_settings() and fresh.resolution == Settings.DEFAULT_RESOLUTION
        and fresh.show_damage_numbers and fresh.screen_shake == 1.0, "missing file keeps defaults")
    check(fresh.set_value("resolution", Vector2i(1280, 720)), "preset resolution accepted")
    check(not fresh.set_value("resolution", Vector2i(123, 45)), "non-preset resolution rejected")
    check(not fresh.set_value("no_such_key", 1), "unknown key rejected")
    fresh.set_value("fullscreen", true)
    fresh.set_value("master_volume", 1.7)
    fresh.set_value("show_damage_numbers", false)
    fresh.set_value("screen_shake", 0.25)
    check(fresh.master_volume == 1.0, "volume clamped to 1.0")
    fresh.set_value("master_volume", 0.4)
    check(fresh.save_settings() and FileAccess.file_exists(ROUNDTRIP_PATH), "settings saved to user://")
    var loaded = Settings.new(ROUNDTRIP_PATH)
    check(loaded.load_settings(), "settings file loads")
    check(loaded.to_dict() == fresh.to_dict(), "roundtrip: %s vs %s" % [loaded.to_dict(), fresh.to_dict()])
    check(loaded.resolution == Vector2i(1280, 720) and loaded.fullscreen
        and is_equal_approx(loaded.master_volume, 0.4) and not loaded.show_damage_numbers
        and is_equal_approx(loaded.screen_shake, 0.25), "every value survives the roundtrip")
    DirAccess.remove_absolute(path_abs)
