extends SceneTree
## Proves the live Game emits the Events bus signals during scripted play:
## door transitions, a revisit, kills, player shots/swings, boss gate, death,
## grace-then-collapse and floor clear (exit -> intermission).
## Run: godot --headless --path game --script res://tests/events_test.gd
const SEED := 424242
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
const RECORDED := ["run_started", "floor_started", "room_entered", "ticks_changed",
    "enemy_damaged", "enemy_killed", "xp_gained", "room_cleared", "projectile_fired",
    "melee_swung", "player_damaged", "player_died", "boss_defeated", "floor_cleared",
    "run_ended", "message", "game_state_changed"]
var failures := 0
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL EVENTS: " + detail)


func _count(name: String) -> int:
    return seen.get(name, []).size()


func _last(name: String) -> Array:
    return seen[name].back() if _count(name) > 0 else []


func _connect_all(events: Node) -> void:
    for name in RECORDED:
        var signal_ref: Signal = events.get(name)
        var arity: int = 0
        for info in events.get_signal_list():
            if info["name"] == name:
                arity = info["args"].size()
        match arity:
            1: signal_ref.connect(func(a): _record(name, [a]))
            2: signal_ref.connect(func(a, b): _record(name, [a, b]))
            3: signal_ref.connect(func(a, b, c): _record(name, [a, b, c]))
            4: signal_ref.connect(func(a, b, c, d): _record(name, [a, b, c, d]))


func _record(name: String, args: Array) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(args)


func _first_normal_direction(rs: Node) -> String:
    var rooms: Array = rs.floor["rooms"]
    var here: Dictionary = rooms[rs.current_room_id]
    for direction in ["N", "E", "S", "W"]:
        if here["neighbors"].has(direction) and \
                rooms[int(here["neighbors"][direction])]["kind"] == "normal":
            return direction
    return ""


func _run() -> void:
    var events: Node = get_root().get_node("Events")
    var rs: Node = get_root().get_node("RunState")
    _connect_all(events)
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)

    # Booting shows the title screen; start_run begins floor 1 in the start room.
    check(_count("run_started") == 0 and game.state == game.State.TITLE, "boot shows TITLE")
    game.start_run(SEED)
    check(_last("game_state_changed") == ["TITLE", "RUNNING"], "game_state_changed(names)")
    check(_count("run_started") == 1 and _last("run_started")[0] == SEED, "run_started(seed)")
    check(_count("floor_started") == 1 and _last("floor_started")[0] == 1, "floor_started(1, floor)")
    check(_last("room_entered") == [0, "start", {}, true], "start room entered on boot")

    # Door transition: first visit costs ticks and is announced.
    seen.clear()
    var direction: String = _first_normal_direction(rs)
    var target: int = int(rs.floor["rooms"][0]["neighbors"][direction])
    game._enter_neighbor(direction)
    check(_count("room_entered") == 1, "room_entered on door transition")
    var entered: Array = _last("room_entered")
    check(entered[0] == target and entered[1] == "normal" and entered[3] == true,
        "room_entered(room_id, kind, ledger, first_visit)")
    check(int(entered[2]["cost"]) == 2 and int(entered[2]["after"]) == rs.ticks,
        "ledger entry carried by room_entered")
    check(_last("ticks_changed") == [26, 24, "normal first entry (cost 2, grant 0)"],
        "ticks_changed(before, after, reason)")
    check(String(_last("message")[0]).begins_with("Room %d [normal]" % target), "HUD message")

    # Revisit is free: room_entered fires with first_visit false, ticks do not change.
    game._enter_neighbor(OPPOSITE[direction])
    game._enter_neighbor(direction)
    check(_count("room_entered") == 3 and _last("room_entered")[3] == false, "revisit flagged")
    check(_count("ticks_changed") == 1, "no ticks_changed for free revisits")
    check(int(rs.telemetry["rooms_entered"]) == 2, "telemetry counts first visits")

    # Player shot and swing go through Combat and the bus.
    game.player.aim_direction = Vector2.UP
    game.combat.player_fire()
    game.combat.player_melee()
    check(_count("projectile_fired") == 1 and _last("projectile_fired")[0] == "player",
        "projectile_fired(owner, data)")
    check(_count("melee_swung") == 1 and _last("melee_swung")[2] == Vector2.UP,
        "melee_swung(owner, position, direction)")
    check(int(rs.telemetry["shots_fired"]) == 1 and int(rs.telemetry["melee_swings"]) == 1,
        "shot and swing telemetry")
    game.combat.clear_projectiles()

    # Scripted kill of every enemy in the room.
    seen.clear()
    var foes: Array = rs.current_room()["enemies"]
    var expected: int = foes.size()
    var xp_value: int = 0
    for foe in foes:
        xp_value += int(game.catalogue["enemies"][foe["definition"]]["xp"])
    for _i in range(200):
        if foes.is_empty():
            break
        game.combat.hit_enemy(0, 30, 6, 2)
    check(expected > 0 and foes.is_empty(), "scripted attacks clear the room")
    check(_count("enemy_killed") == expected, "enemy_killed once per enemy")
    check(_last("enemy_killed")[1] > 0 and _last("enemy_killed")[2] is Vector2,
        "enemy_killed(definition_id, xp, position)")
    var dealt := 0
    for args in seen.get("enemy_damaged", []):
        dealt += int(args[1])
    check(_count("enemy_damaged") >= expected and int(rs.telemetry["damage_dealt"]) == dealt,
        "enemy_damaged feeds damage_dealt")
    check(rs.xp == xp_value and _last("xp_gained")[1] == xp_value, "kills award XP via Game")
    check(seen.get("room_cleared", []) == [[target]], "room_cleared once for the room")
    check(int(rs.telemetry["kills"]) == expected, "kill telemetry")

    # Boss kill unlocks the exit; walking into it clears the floor.
    seen.clear()
    var boss_id: int = int(rs.floor["boss_id"])
    var exit_id: int = int(rs.floor["exit_id"])
    events.enemy_killed.emit("armored_brute", 250, Vector2(100, 100))
    check(rs.boss_defeated and seen.get("boss_defeated", []) == [["armored_brute"]],
        "boss_defeated emitted and recorded")
    rs.current_room_id = boss_id
    rs.visited[boss_id] = true
    game._load_room(boss_id)
    var to_exit := ""
    for side in rs.floor["rooms"][boss_id]["neighbors"]:
        if int(rs.floor["rooms"][boss_id]["neighbors"][side]) == exit_id:
            to_exit = side
    if game.state == game.State.LEVEL_UP:
        game.character_menu.close_menu()
        game._change_state(game.State.RUNNING)
    game._enter_neighbor(to_exit)
    check(seen.get("floor_cleared", []) == [[1]], "floor_cleared(depth)")
    check(_count("run_ended") == 0 and rs.outcome == "running", "floor 1 exit does not end the run")
    check(game.state == game.State.INTERMISSION, "Game enters INTERMISSION")

    # Death: enemy hits until HP is gone.
    game.start_run(SEED)
    seen.clear()
    for _i in range(100):
        if rs.hp <= 0:
            break
        game.player.invulnerability = 0.0
        game.combat.hit_player(30, 6, 1, "rat_scavenger")
    check(_count("player_damaged") > 0 and _last("player_damaged")[1] == "rat_scavenger",
        "player_damaged(amount, source)")
    check(seen.get("player_died", []) == [["rat_scavenger"]], "player_died(cause) once")
    check(_last("run_ended")[0] == "defeated" and rs.outcome == "defeated", "defeat ends the run")
    check(_last("run_ended")[1]["cause"] == "rat_scavenger", "summary carries the cause")
    check(_last("message")[0] == "YOU DIED! R = retry, N = new seed.", "death message kept")

    # Collapse (v1, D-05): a first entry that drains the last ticks starts the
    # grace period; the run collapses when the grace timer runs out.
    game.start_run(SEED)
    seen.clear()
    rs.ticks = 2
    var grace_seconds: Array = []
    events.grace_started.connect(func(seconds): grace_seconds.append(seconds))
    game._enter_neighbor(_first_normal_direction(rs))
    check(_last("ticks_changed") == [2, 0, "normal first entry (cost 2, grant 0)"],
        "ticks_changed to zero")
    check(grace_seconds == [10.0] and rs.grace_active() and _count("run_ended") == 0,
        "reaching zero starts a 10 s grace instead of ending the run")
    for _i in range(700):
        if game.state != game.State.RUNNING:
            break
        game.player.invulnerability = 1.0
        game._physics_process(1.0 / 60.0)
    check(_count("run_ended") == 1 and _last("run_ended")[0] == "collapsed"
        and game.state == game.State.SUMMARY, "grace running out collapses the run")
    check(_last("run_ended")[1]["cause"] == "collapse on floor 1", "collapse cause recorded")

    game.queue_free()
    if failures == 0:
        print("PASS: Events bus fires for doors, ticks, kills, XP, shots, boss gate, death, collapse, floor clear")
    quit(1 if failures > 0 else 0)
