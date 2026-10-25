extends SceneTree
## Determinism regression for seed 424242: same inputs -> same outputs. Probes:
## floor signature, every room's obstacle map, every room's encounter list,
## and a scripted combat trace (d20 rolls, damage, XP, HUD messages).
## The floor signature is still the pre-refactor main.gd value (commit 9bb993d).
## Obstacle, encounter and trace constants were regenerated in Wave 2C, when
## threat-budget encounters and the boss-room obstacle cap replaced the count
## tables; a mismatch prints the new hash so intended changes are easy to adopt.
## Run: godot --headless --path game --script res://tests/determinism_test.gd
const Generator = preload("res://scripts/floor_generator.gd")
const SEED := 424242
const SIGNATURE_MD5 := "b4a17cba2d2d09d31d90f84d8f610610"
const OBSTACLES_MD5 := "8e23284dcf127de9d683a0f6d7bbfa03"
const ENCOUNTERS_MD5 := "8313ee681010df7e7a8c08332f5ab4b0"
const TRACE_MD5 := "3a5207df4159cc2358f737b5684bbcd2"
## First lines of the captured trace, kept readable for debugging diffs.
const TRACE_HEAD := ["10 24 (192.0, 363.0)", "3 7 0 Missed Rat Scavenger (d20: 2)",
    "2 17 25 Hit Rat Scavenger for 7 damage"]
var failures := 0
var last_message := ""


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL DETERMINISM: " + detail)


func _on_message(text: String, _category: String) -> void:
    last_message = text


func _run() -> void:
    var run_state: Node = get_root().get_node("RunState")
    get_root().get_node("Events").message.connect(_on_message)
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    game.start_run(SEED)
    var rooms: Array = run_state.floor["rooms"]
    var signature: String = Generator.signature(rooms)
    check(signature.md5_text() == SIGNATURE_MD5, "floor signature matches pre-refactor main")
    check(signature == Generator.signature(Generator.generate(SEED, 22)["rooms"]),
        "Game floor equals a direct Generator call")

    var obstacles: PackedStringArray = []
    var encounters: PackedStringArray = []
    for room in rooms:
        var id: int = int(room["id"])
        game._load_room(id)
        var state: Dictionary = run_state.room_states[id]
        var keys: Array = state["blocked"].keys()
        keys.sort()
        obstacles.append("%d:%s:%s" % [id, str(keys), str(state["props"])])
        var foes: PackedStringArray = []
        for foe in state["enemies"]:
            foes.append("%s@%s hp%d cd%.6f" % [foe["instance_id"] + "/" + foe["definition"],
                str(foe["pos"]), int(foe["hp"]), float(foe["attack_cooldown"])])
        encounters.append("%d:%s" % [id, ",".join(foes)])
    check("|".join(obstacles).md5_text() == OBSTACLES_MD5, "obstacle maps match fixture (got %s)"
        % "|".join(obstacles).md5_text())
    check("|".join(encounters).md5_text() == ENCOUNTERS_MD5, "encounter lists match fixture (got %s)"
        % "|".join(encounters).md5_text())

    var first: PackedStringArray = _combat_trace(game, run_state)
    for i in range(TRACE_HEAD.size()):
        check(i < first.size() and first[i] == TRACE_HEAD[i],
            "trace line %d: %s" % [i, first[i] if i < first.size() else "<missing>"])
    check("\n".join(first).md5_text() == TRACE_MD5, "combat trace matches fixture (got %s):\n"
        % "\n".join(first).md5_text() + "\n".join(first))
    var second: PackedStringArray = _combat_trace(game, run_state)
    check(first == second, "restarting the same seed replays the identical trace")

    game.queue_free()
    if failures == 0:
        print("PASS: seed 424242 floor, obstacles, encounters and combat trace match the fixtures")
    quit(1 if failures > 0 else 0)


## Same probe as the capture script run against main.gd: enter the first
## normal neighbour of the start room, kill everything with fixed attack
## numbers, then take enemy hits until death.
func _combat_trace(game, run_state: Node) -> PackedStringArray:
    game.start_run(SEED)
    var rooms: Array = run_state.floor["rooms"]
    var trace: PackedStringArray = []
    var start: Dictionary = rooms[0]
    for direction in ["N", "E", "S", "W"]:
        if start["neighbors"].has(direction) and \
                rooms[int(start["neighbors"][direction])]["kind"] == "normal":
            game._enter_neighbor(direction)
            break
    trace.append("%d %d %s" % [run_state.current_room_id, run_state.ticks,
        str(game.player.world_position)])
    var foes: Array = run_state.current_room()["enemies"]
    for _i in range(60):
        if foes.is_empty():
            break
        game.combat.hit_enemy(0, 5, 6, 2)
        trace.append("%d %d %d %s" % [foes.size(),
            int(foes[0]["hp"]) if not foes.is_empty() else -1, run_state.xp, last_message])
    for _i in range(12):
        if run_state.hp <= 0:
            break
        game.player.invulnerability = 0.0
        game.combat.hit_player(4, 6, 1)
        trace.append("%d %s %s" % [run_state.hp, run_state.outcome, last_message])
    return trace
