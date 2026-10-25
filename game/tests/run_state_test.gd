extends SceneTree
## Unit tests for the RunState autoload (no Game scene involved).
## Run: godot --headless --path game --script res://tests/run_state_test.gd
## Autoload nodes already exist under /root when _initialize() runs, but the
## RunState/Events identifiers cannot be used in this file (it is compiled
## before autoloads are registered), so they are fetched with get_node().
var failures := 0
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL RUNSTATE: " + detail)


func _record(name: String, args: Array) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(args)


func _count(name: String) -> int:
    return seen.get(name, []).size()


func _run() -> void:
    var events: Node = get_root().get_node("Events")
    var rs: Node = get_root().get_node("RunState")
    events.run_started.connect(func(s): _record("run_started", [s]))
    events.xp_gained.connect(func(a, t): _record("xp_gained", [a, t]))
    events.level_up.connect(func(l, p): _record("level_up", [l, p]))
    events.player_damaged.connect(func(a, s): _record("player_damaged", [a, s]))
    events.player_healed.connect(func(a): _record("player_healed", [a]))
    events.player_died.connect(func(c): _record("player_died", [c]))
    events.ticks_changed.connect(func(b, a, r): _record("ticks_changed", [b, a, r]))
    events.stats_changed.connect(func(s): _record("stats_changed", [s]))
    events.run_ended.connect(func(o, s): _record("run_ended", [o, s]))

    # start_run resets everything from prototype_rules.json.
    check(rs.ensure_config(), "config loads")
    rs.inventory["torch"] = 1
    rs.skills.append("dodge_roll")
    rs.start_run(777)
    check(seen["run_started"] == [[777]], "run_started emitted with seed")
    check(rs.seed == 777 and rs.rng.seed == 777, "seed and combat RNG set")
    check(rs.depth == 1 and rs.outcome == "running" and not rs.boss_defeated, "fresh run flags")
    check(rs.ticks == int(rs.config["start_ticks"]), "ticks from config")
    check(rs.xp == 0 and rs.level == 1 and rs.pending_stat_points == 0, "fresh progression")
    check(rs.ability_scores == rs.config["player_ability_scores"], "scores from config")
    check(rs.hp == rs.max_hp and rs.max_hp == 12 and rs.ac == 12 and rs.proficiency == 2,
        "derived stats for 14/14/14 start (HP 12, AC 12, prof +2)")
    check(rs.inventory.is_empty() and rs.skills.is_empty(), "inventory and skills reset")
    for key in rs.TELEMETRY_KEYS:
        check(float(rs.telemetry[key]) == 0.0, "telemetry reset: " + key)
    check(rs.visited.is_empty() and rs.room_states.is_empty(), "floor state cleared")
    var first_rolls := [rs.rng.randi(), rs.rng.randi()]
    rs.start_run(777)
    check([rs.rng.randi(), rs.rng.randi()] == first_rolls, "same seed reproduces combat dice")

    # award_xp: multi-level jump banks every level's points, heals by max-HP gain.
    seen.clear()
    var hp_before: int = rs.hp
    rs.award_xp(2700)
    check(rs.xp == 2700 and rs.level == 4, "2700 XP reaches level 4")
    check(rs.pending_stat_points == 6, "three levels bank six points")
    check(seen["xp_gained"] == [[2700, 2700]], "xp_gained(amount, total)")
    check(seen["level_up"] == [[4, 6]], "one level_up for a multi-level award")
    check(rs.proficiency == 2 and rs.max_hp > hp_before and rs.hp == rs.max_hp,
        "max HP grows and current HP follows")
    rs.award_xp(-50)
    check(rs.xp == 2700 and _count("level_up") == 1, "negative XP ignored")
    rs.award_xp(3800)
    check(rs.level == 5 and rs.proficiency == 3 and rs.pending_stat_points == 8,
        "level 5 adds points to the unspent bank and raises proficiency")

    # Stat allocation goes through RPG validation.
    check(not rs.apply_stat_allocation({"STR": 9}), "overspend rejected")
    check(rs.pending_stat_points == 8, "rejected allocation changes nothing")
    var max_before: int = rs.max_hp
    check(rs.apply_stat_allocation({"CON": 2, "STR": 2, "DEX": 4}), "valid allocation accepted")
    check(rs.pending_stat_points == 0 and int(rs.ability_scores["CON"]) == 16, "scores applied")
    check(rs.max_hp > max_before and rs.hp == rs.max_hp, "CON raises max HP and heals the gain")
    check(rs.ac == 10 + 4, "DEX 18 gives AC 14")
    check(_count("stats_changed") == 1, "stats_changed emitted once")

    # Damage and healing clamp to [0, max_hp].
    rs.start_run(5)
    seen.clear()
    check(rs.apply_damage_to_player(5, "rat") == 5 and rs.hp == rs.max_hp - 5, "damage applied")
    check(rs.heal_player(3) == 3 and rs.hp == rs.max_hp - 2, "heal applied")
    check(rs.heal_player(999) == 2 and rs.hp == rs.max_hp, "heal clamps to max HP")
    check(rs.heal_player(0) == 0 and rs.heal_player(-4) == 0, "non-positive heal ignored")
    check(seen["player_healed"] == [[3], [2]], "player_healed reports HP actually restored")
    check(rs.apply_damage_to_player(0, "none") == 0 and rs.apply_damage_to_player(-3, "x") == 0,
        "non-positive damage ignored")
    rs.apply_damage_to_player(999, "boss")
    check(rs.hp == 0, "damage clamps at 0 HP")
    check(seen["player_died"] == [["boss"]], "player_died once with cause")
    check(rs.apply_damage_to_player(4, "rat") == 0 and _count("player_died") == 1,
        "dead player takes no further damage")
    check(rs.heal_player(5) == 0 and rs.hp == 0, "dead player cannot be healed")
    check(seen["player_damaged"] == [[5, "rat"], [999, "boss"]], "player_damaged payloads")
    check(int(rs.telemetry["damage_taken"]) == 1004, "damage_taken telemetry")

    # Ticks: ledger entries and free-form changes.
    rs.start_run(5)
    seen.clear()
    rs.apply_tick_entry({"after": 24, "cost": 2, "grant": 0, "reason": "normal first entry"})
    rs.apply_tick_entry({"after": 24, "cost": 0, "grant": 0, "reason": "normal revisit"})
    check(rs.ticks == 24 and rs.tick_ledger.size() == 2, "ledger applied")
    check(seen["ticks_changed"] == [[26, 24, "normal first entry"]],
        "ticks_changed only when the value changes")
    rs.add_ticks(3, "shrine")
    rs.add_ticks(-100, "curse")
    check(rs.ticks == 0, "add_ticks clamps at zero")
    check(int(rs.telemetry["ticks_spent"]) == 2 + 27, "ticks_spent counts costs and actual drains")

    # Telemetry listens to the bus.
    events.enemy_killed.emit("rat_scavenger", 25, Vector2.ZERO)
    events.enemy_damaged.emit("1_0", 7, false)
    events.projectile_fired.emit("player", {})
    events.projectile_fired.emit("enemy", {})
    events.melee_swung.emit("player", Vector2.ZERO, Vector2.RIGHT)
    events.room_entered.emit(3, "normal", {}, true)
    events.room_entered.emit(3, "normal", {}, false)
    check(int(rs.telemetry["kills"]) == 1 and int(rs.telemetry["damage_dealt"]) == 7,
        "kills and damage_dealt from signals")
    check(int(rs.telemetry["shots_fired"]) == 1 and int(rs.telemetry["melee_swings"]) == 1,
        "only player shots and swings counted")
    check(int(rs.telemetry["rooms_entered"]) == 1, "rooms_entered counts first visits only")
    check(rs.xp == 0, "RunState alone does not award XP for kills (Game does)")
    rs.advance_clock(1.5)

    # Floors and summary.
    rs.visited[4] = true
    rs.boss_defeated = true
    rs.reset_for_floor(2)
    check(rs.depth == 2 and rs.visited.is_empty() and not rs.boss_defeated, "floor reset")
    check(rs.floor_seed(1) == 5 and rs.floor_seed(2) != 5, "depth 1 keeps run seed")
    var summary: Dictionary = rs.end_run("victory")
    check(rs.outcome == "victory" and summary["outcome"] == "victory", "end_run sets outcome")
    for key in ["seed", "depth", "outcome", "level", "xp", "hp", "max_hp", "ticks",
            "rooms_visited", "boss_defeated", "inventory", "skills", "cause", "floors",
            "target_depth", "floor_budget"] + rs.TELEMETRY_KEYS:
        check(summary.has(key), "summary has " + key)
    check(summary["seed"] == 5 and summary["depth"] == 2 and summary["kills"] == 1,
        "summary values")
    check(is_equal_approx(float(summary["run_time_seconds"]), 1.5), "run time tracked")
    check(_count("run_ended") == 1 and seen["run_ended"][0][0] == "victory", "run_ended emitted")

    if failures == 0:
        print("PASS: RunState start_run, XP/level-up, allocation, damage/heal clamps, ticks, telemetry, summary")
    quit(1 if failures > 0 else 0)
