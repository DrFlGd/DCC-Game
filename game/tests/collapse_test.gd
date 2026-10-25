extends SceneTree
## Collapse clock v1 (Wave 2E): never-refused transitions, the zero-clock grace
## lifecycle on the live Game, debris waves, the hazards module, budgets and
## the generator's feasibility re-roll.
## Run: godot --headless --path game --script res://tests/collapse_test.gd
## Pure modules (no autoload references) are preloaded; Game is load()ed.
const Collapse = preload("res://scripts/collapse_policy.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Generator = preload("res://scripts/floor_generator.gd")
const RunRules = preload("res://scripts/core/run_rules.gd")
const SEED := 424242
const STEP := 1.0 / 60.0
## COLLAPSE_SYSTEM §4: start ticks for depths 1-6 (22/26/30/34/40/44 rooms).
const DOCUMENTED_BUDGETS := [26, 30, 36, 40, 46, 50]
var failures := 0
var grace_started: Array = []
var grace_ended: Array = []
var spawned: Array = []
var run_ended: Array = []
var ticks_changed: Array = []


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL COLLAPSE: " + detail)


func _key(physical: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = physical
    event.physical_keycode = physical
    event.pressed = true
    return event


func _direction_to(rs: Node, wanted_kind: String, unvisited: bool = true) -> String:
    var rooms: Array = rs.floor["rooms"]
    var here: Dictionary = rooms[rs.current_room_id]
    for direction in ["N", "E", "S", "W"]:
        if not here["neighbors"].has(direction):
            continue
        var id: int = int(here["neighbors"][direction])
        if String(rooms[id]["kind"]) == wanted_kind and (not unvisited or not rs.visited.has(id)):
            return direction
    return ""


## Physics steps with i-frames held, so enemies and debris never kill the
## crawler while the clock is under test. Stops early when the state changes.
func _steps(game, count: int) -> void:
    for _i in range(count):
        if game.state != game.State.RUNNING:
            return
        game.player.invulnerability = 1.0
        game._physics_process(STEP)


func _run() -> void:
    var events: Node = get_root().get_node("Events")
    var rs: Node = get_root().get_node("RunState")
    events.grace_started.connect(func(s): grace_started.append(s))
    events.grace_ended.connect(func(s): grace_ended.append(s))
    events.hazard_spawned.connect(func(d): spawned.append(d))
    events.run_ended.connect(func(o, s): run_ended.append([o, s]))
    events.ticks_changed.connect(func(b, a, r): ticks_changed.append([b, a, r]))
    _test_policy_and_hazards()
    _test_budgets()
    _test_feasibility()
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    _test_never_refuse_and_grace(game, rs)
    _test_full_grace_waves(game, rs)
    _test_exit_during_grace(game, rs)
    _test_freeze_and_elite(game, rs, events)
    game.queue_free()
    if failures == 0:
        print("PASS: never-refused doors, grace lifecycle and waves, hazards, budgets, feasibility")
    quit(1 if failures > 0 else 0)


func _test_policy_and_hazards() -> void:
    var cfg: Dictionary = Generator.default_config()
    var policy = Collapse.new(cfg["collapse"])
    var entry: Dictionary = policy.evaluate(1, "normal", true, 4)
    check(bool(entry["allowed"]) and int(entry["after"]) == 0 and int(entry["charged"]) == 1
        and bool(entry["reaches_zero"]) and not bool(entry["collapses"]),
        "short of ticks: allowed, clamped, charged what was left, reaches zero")
    var at_zero: Dictionary = policy.evaluate(0, "normal", true, 4)
    check(bool(at_zero["allowed"]) and int(at_zero["charged"]) == 0 and int(at_zero["after"]) == 0
        and not bool(at_zero["reaches_zero"]), "at zero (grace) entries are free and allowed")
    var guild: Dictionary = policy.evaluate(0, "guild_hall", true, 4)
    check(int(guild["after"]) == 3, "first-entry grants still apply at zero")
    check(entry["source"] == "transition" and entry["modifiers"] == [], "ledger v1 fields")
    check(policy.clear_grant("elite") == 1 and policy.clear_grant("normal") == 0,
        "elite clear grant +1, default clear_refund 0")
    for kind in ["treasure", "elite", "trap", "shrine"]:
        check(cfg["collapse"]["room_types"].has(kind), "policy entry for " + kind)
    check(policy.evaluate(10, "elite", true, 1)["cost"] == 3
        and policy.evaluate(10, "trap", true, 1)["cost"] == 1
        and policy.evaluate(10, "shrine", true, 1)["cost"] == 1
        and policy.evaluate(10, "treasure", true, 1)["cost"] == 2, "new kinds' entry costs")

    # Grace rules (pure).
    var grace_cfg: Dictionary = Collapse.grace_config(cfg["collapse"])
    var state: Dictionary = Collapse.grace_initial()
    check(Collapse.grace_on_zero(state, grace_cfg) == "grace" and float(state["duration"]) == 10.0,
        "first zero: 10 s grace")
    Collapse.grace_finish(state, "stabilised")
    check(Collapse.grace_on_zero(state, grace_cfg) == "grace" and float(state["duration"]) == 5.0,
        "second zero: 5 s grace")
    Collapse.grace_finish(state, "stabilised")
    check(Collapse.grace_on_zero(state, grace_cfg) == "collapse", "third zero collapses")
    check(int(Collapse.grace_wave(9.0, grace_cfg)["markers"]) == 1
        and int(Collapse.grace_wave(5.0, grace_cfg)["markers"]) == 2
        and int(Collapse.grace_wave(1.0, grace_cfg)["markers"]) == 3, "wave table bands")

    # Hazards: telegraph -> one hit per activation -> expire.
    var list: Array[Dictionary] = [Hazards.make("test", Vector2(100, 100), 10.0, 0.5, 2, 0.3,
        "hazard:test")]
    var player := {"pos": Vector2(104, 100), "radius": 5.5, "invulnerable": false}
    var hits: Array = []
    for _i in range(29):
        hits.append_array(Hazards.step(list, STEP, player))
    check(hits.is_empty() and not Hazards.is_active(list[0]), "no damage during the telegraph")
    var total := 0
    for _i in range(40):
        for hit in Hazards.step(list, STEP, player):
            total += int(hit["damage"])
    check(total == 2, "exactly one hit per activation (got %d damage)" % total)
    check(list.is_empty(), "hazard expires after its duration")
    var dodge: Array[Dictionary] = [Hazards.make("test", Vector2(100, 100), 10.0, 0.1, 2, 0.2,
        "hazard:test")]
    var dodged := 0
    for _i in range(30):
        dodged += Hazards.step(dodge, STEP, {"pos": Vector2(100, 100), "radius": 5.5,
            "invulnerable": true}).size()
    check(dodged == 0 and dodge.is_empty(), "i-frames avoid the hit")
    var outside: Array[Dictionary] = [Hazards.make("test", Vector2(10, 10), 8.0, 0.0, 2, 0.2, "x")]
    check(Hazards.step(outside, STEP, player).is_empty(), "no hit outside the circle")
    var puddle: Array[Dictionary] = [Hazards.make("puddle", Vector2(100, 100), 10.0, 0.0, 1, 1.0,
        "enemy:zoner", {"interval": 0.5})]
    var ticks_hits := 0
    for _i in range(70):
        ticks_hits += Hazards.step(puddle, STEP, player).size()
    check(ticks_hits == 2, "interval hazards re-activate (got %d hits)" % ticks_hits)
    var shared: Dictionary = Hazards.normalize({"pos": Vector2(1, 1), "radius": 4.0,
        "telegraph_remaining": 0.3, "damage": 1, "duration": 0.5, "source": "enemy:zoner"})
    check(shared["kind"] == "generic" and float(shared["telegraph"]) == 0.3,
        "2C-shaped entries without kind normalise")
    var foe := {"instance_id": "1_0", "pos": Vector2(100, 100), "radius": 6.0, "hp": 5}
    var both: Array[Dictionary] = [Hazards.make("debris", Vector2(100, 100), 14.0, 0.0, 2, 0.1,
        "hazard:debris", {"hits_enemies": true})]
    var targets: Array = []
    for hit in Hazards.step(both, STEP, player, [foe]):
        targets.append(hit["target"] is String)
    check(targets == [true, false], "debris hits the crawler and enemies once each")


func _test_budgets() -> void:
    var cfg: Dictionary = Generator.default_config()
    var policy = Collapse.new(cfg["collapse"])
    var floor_one: Dictionary = Generator.generate(SEED, 22)
    check(Collapse.budget_for(floor_one, 22, policy) == 26, "budget_for floor 1 seed 424242 = 26")
    check(Collapse.mandatory_route_cost(floor_one, policy) == 16
        and Collapse.mandatory_budget_floor(floor_one, policy) == 16,
        "route cost 16; the legacy diagnostic lost its +1")
    check(int(floor_one["budget"]) == 26 and int(floor_one["mandatory_route_cost"]) == 16,
        "floor dict records route and budget")
    for depth in range(1, 7):
        var count: int = RunRules.room_count(depth, cfg)
        var seed_value: int = SEED if depth == 1 else int((SEED + (depth - 1) * 1000003) % 2147483647)
        var floor: Dictionary = Generator.generate(seed_value, count, {"depth": depth})
        var budget: int = Collapse.budget_for(floor, count, policy)
        check(budget == DOCUMENTED_BUDGETS[depth - 1], "depth %d budget %d == %d" % [
            depth, budget, DOCUMENTED_BUDGETS[depth - 1]])
        check(budget == RunRules.floor_budget(floor, policy, cfg), "agrees with RunRules depth %d" % depth)
    # §9.6 sweep: budgets readable, route costs stable around the depth median.
    for depth in range(1, 7):
        var count: int = RunRules.room_count(depth, cfg)
        var routes: Array[int] = []
        for i in range(60):
            var floor: Dictionary = Generator.generate(9000 + i * 13, count, {"depth": depth})
            routes.append(int(floor["mandatory_route_cost"]))
            check(int(floor["budget"]) <= 70, "budget <= 70")
            check(int(floor["budget"]) - int(floor["mandatory_route_cost"]) >= 8, "slack >= 8")
            check(Collapse.mandatory_route_cost(floor, policy)
                == int(Collapse.mandatory_route(floor, policy)["cost"]),
                "route rooms query agrees with RunRules")
        routes.sort()
        var median: float = float(routes[routes.size() / 2])
        check(float(routes[0]) >= median * 0.6 and float(routes[-1]) <= median * 1.4,
            "depth %d route cost within +/-40%% of median %d" % [depth, int(median)])


func _test_feasibility() -> void:
    var cfg: Dictionary = Generator.default_config()
    var floor: Dictionary = Generator.generate(SEED, 22)
    check(bool(floor["feasibility"]["ok"]) and int(floor["feasibility"]["attempt"]) == 0
        and int(floor["generation_seed"]) == SEED, "seed 424242 is feasible on attempt 0")
    # A fixed budget that cannot cover the route: every attempt fails, the
    # result falls back to attempt 0 and says so (push_error in the log).
    var starved: Dictionary = Generator.generate(SEED, 22, {"budget": 12})
    check(not bool(starved["feasibility"]["ok"]) and int(starved["feasibility"]["attempts"]) == 20
        and int(starved["generation_seed"]) == SEED
        and Array(starved["feasibility"]["checks"]["failed"]).has("slack"),
        "unaffordable route: 20 attempts, fallback to attempt 0, failure recorded")
    check(Generator.signature(starved["rooms"]) == Generator.signature(floor["rooms"]),
        "fallback is the attempt-0 layout")
    # A tight guild rule makes some seeds re-roll; the re-roll is deterministic.
    var tight: Dictionary = cfg.duplicate(true)
    tight["collapse"]["budget"]["guild_max_ratio"] = 0.2
    var found := false
    for i in range(200):
        var seed_value: int = 3000 + i
        var rolled: Dictionary = Generator.generate(seed_value, 22, {"config": tight})
        var attempt: int = int(rolled["feasibility"]["attempt"])
        if attempt == 0 or not bool(rolled["feasibility"]["ok"]):
            continue
        found = true
        check(int(rolled["generation_seed"]) == seed_value + attempt * 104729
            and int(rolled["seed"]) == seed_value, "re-roll uses seed + k x 104729")
        var again: Dictionary = Generator.generate(seed_value, 22, {"config": tight})
        check(Generator.signature(again["rooms"]) == Generator.signature(rolled["rooms"]),
            "re-rolled floor is deterministic")
        break
    check(found, "a seed that needs a feasibility re-roll exists")


func _test_never_refuse_and_grace(game, rs: Node) -> void:
    game.start_run(SEED)
    grace_started.clear()
    grace_ended.clear()
    spawned.clear()
    run_ended.clear()
    rs.ticks = 1
    # Seed 424242: start -S-> 1 -E-> 19 -S-> 3 are all unvisited normal rooms.
    var direction := "S"
    check(rs.floor["rooms"][int(rs.floor["rooms"][0]["neighbors"]["S"])]["kind"] == "normal",
        "fixture route starts with a normal room")
    var target: int = int(rs.floor["rooms"][0]["neighbors"][direction])
    game._enter_neighbor(direction)
    check(rs.current_room_id == target and rs.ticks == 0, "door with too few ticks still opens")
    check(rs.tick_ledger.back()["charged"] == 1, "only the remaining tick was charged")
    check(grace_started == [10.0] and rs.grace_active() and int(rs.grace["count"]) == 1,
        "grace_started(10) on the first zero")
    check(game.clock.doors_unlocked(), "doors unlocked during grace")
    check(game.state == game.State.RUNNING and run_ended.is_empty(), "the run goes on")

    # Entering an unvisited room during grace is free.
    var free_dir: String = _direction_to(rs, "normal")
    var before_changes: int = ticks_changed.size()
    game._enter_neighbor(free_dir)
    check(rs.ticks == 0 and ticks_changed.size() == before_changes
        and int(rs.tick_ledger.back()["charged"]) == 0, "grace entries cost nothing")

    # Waves: the first lands at once on the crawler; each batch matches the table.
    _steps(game, 120)
    var config: Dictionary = Collapse.grace_config(rs.config["collapse"])
    check(spawned.size() >= 2, "debris spawned during grace (%d)" % spawned.size())
    if not spawned.is_empty():
        check(spawned[0]["kind"] == "debris" and Vector2(spawned[0]["pos"]).distance_to(
            game.player.world_position) < 0.01, "first marker targets the crawler")
        check(int(spawned[0]["damage"]) == 2 and float(spawned[0]["radius"]) == 14.0
            and is_equal_approx(float(spawned[0]["telegraph"]), 0.8), "debris shape from config")
    for data in spawned:
        check(int(data["wave_markers"]) == int(Collapse.grace_wave(
            float(data["grace_remaining"]), config)["markers"]), "batch size matches the wave table")
    check(float(rs.grace["remaining"]) < 8.1 and float(rs.grace["remaining"]) > 7.9,
        "grace timer advanced 2 s")

    # Regaining ticks stabilises.
    rs.add_ticks(2, "item:itm_tick_shard")
    check(grace_ended == [true] and not rs.grace_active() and rs.grace["outcome"] == "stabilised",
        "ticks regained: grace_ended(true)")
    # Second zero on the floor: 5 s, starting in the 2-marker band.
    spawned.clear()
    var next_dir: String = _direction_to(rs, "normal")
    game._enter_neighbor(next_dir)
    check(rs.ticks == 0 and grace_started == [10.0, 5.0], "second grace lasts 5 s")
    _steps(game, 5)
    check(not spawned.is_empty() and int(spawned[0]["wave_markers"]) == 2,
        "a 5 s grace starts in the 2-marker band")
    rs.add_ticks(1, "skill:skl_test")
    check(grace_ended == [true, true], "second grace stabilised")
    # Third zero: immediate collapse.
    rs.add_ticks(-1, "hazard:drain_plate")
    check(run_ended.size() == 1 and run_ended[0][0] == "collapsed"
        and game.state == game.State.SUMMARY, "third zero on a floor collapses at once")
    check(run_ended[0][1]["cause"] == "collapse on floor 1" and int(run_ended[0][1]["grace_triggered"]) == 2,
        "summary records the cause and two graces")


func _test_full_grace_waves(game, rs: Node) -> void:
    game.start_run(SEED)
    spawned.clear()
    run_ended.clear()
    grace_ended.clear()
    rs.ticks = 1
    rs.add_ticks(-1, "hazard:test")
    check(rs.grace_active(), "add_ticks to zero starts grace too")
    var frames := 0
    while game.state == game.State.RUNNING and frames < 1000:
        _steps(game, 1)
        frames += 1
    var bands := {1: 0, 2: 0, 3: 0}
    var batches := {}
    for data in spawned:
        batches[float(data["grace_remaining"])] = int(data["wave_markers"])
    for remaining in batches.keys():
        bands[batches[remaining]] = int(bands.get(batches[remaining], 0)) + 1
    check(bands[1] >= 2 and bands[1] <= 3 and bands[2] >= 3 and bands[2] <= 4
        and bands[3] >= 5 and bands[3] <= 7, "wave counts per band: %s" % [bands])
    check(absi(frames - 600) <= 3, "grace lasts 10 s (%d frames)" % frames)
    check(run_ended.size() == 1 and run_ended[0][0] == "collapsed" and grace_ended == [false],
        "timer at zero: hard collapse, grace_ended(false)")
    check(rs.grace["outcome"] == "collapse", "outcome recorded")


func _test_exit_during_grace(game, rs: Node) -> void:
    game.start_run(SEED)
    grace_ended.clear()
    run_ended.clear()
    var boss_id: int = int(rs.floor["boss_id"])
    rs.boss_defeated = true
    rs.current_room_id = boss_id
    rs.visited[boss_id] = true
    game._load_room(boss_id)
    rs.ticks = 1
    rs.add_ticks(-1, "hazard:test")
    check(rs.grace_active(), "grace before the exit")
    game._enter_neighbor(_direction_to(rs, "exit"))
    check(game.state == game.State.INTERMISSION and run_ended.is_empty(),
        "exit during grace clears the floor")
    check(grace_ended == [false] and rs.floor_history.back()["grace_outcome"] == "exit",
        "grace resolved as exit")

    # Last-tick exit (no grace): the exit resolves before any zero handling.
    game.start_run(SEED)
    grace_started.clear()
    rs.boss_defeated = true
    rs.current_room_id = boss_id
    rs.visited[boss_id] = true
    game._load_room(boss_id)
    rs.ticks = 1
    game._enter_neighbor(_direction_to(rs, "exit"))
    check(rs.ticks == 0 and grace_started.is_empty() and game.state == game.State.INTERMISSION,
        "exit with exactly its cost succeeds without grace")


func _test_freeze_and_elite(game, rs: Node, events: Node) -> void:
    game.start_run(SEED)
    rs.ticks = 1
    rs.add_ticks(-1, "hazard:test")
    _steps(game, 10)
    var remaining: float = float(rs.grace["remaining"])
    var telegraphs: Array = []
    for hazard in game.combat.hazards:
        telegraphs.append(float(hazard["telegraph_remaining"]))
    game._input(_key(KEY_ESCAPE))
    check(game.state == game.State.PAUSED, "pause opens during grace")
    for _i in range(60):
        game._physics_process(STEP)
    var frozen: Array = []
    for hazard in game.combat.hazards:
        frozen.append(float(hazard["telegraph_remaining"]))
    check(float(rs.grace["remaining"]) == remaining and frozen == telegraphs,
        "pause freezes the grace timer and hazards")
    game._input(_key(KEY_ESCAPE))
    check(game.state == game.State.RUNNING, "resume")
    game._input(_key(KEY_M))
    check(game.state == game.State.MAP, "map opens during grace")
    for _i in range(60):
        game._physics_process(STEP)
    check(float(rs.grace["remaining"]) == remaining, "map freezes the grace timer")
    game._input(_key(KEY_M))
    _steps(game, 1)
    check(float(rs.grace["remaining"]) < remaining, "timer resumes after the map closes")

    # Elite clear grant: +1 tick on room_cleared, which also stabilises grace.
    var elite_id: int = int(rs.floor["rooms"].size() - 1)
    rs.floor["rooms"][elite_id]["kind"] = "elite"
    var before_ended: int = grace_ended.size()
    events.room_cleared.emit(elite_id)
    check(rs.ticks == 1 and not rs.grace_active() and grace_ended.size() == before_ended + 1,
        "elite clear grants +1 and stabilises")
    rs.floor["rooms"][elite_id]["kind"] = "normal"
