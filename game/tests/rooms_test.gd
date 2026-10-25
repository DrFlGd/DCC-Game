extends SceneTree
## Special rooms (Wave 2E): placement rules across seeds and depths, room
## features and obstacle caps, chest / shrine / guild-rest / trap-plate
## interactions on the live Game, the interaction registry and the floor map.
## Run: godot --headless --path game --script res://tests/rooms_test.gd
const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Contents = preload("res://scripts/room_contents.gd")
const Interactables = preload("res://scripts/interactables.gd")
const LootRules = preload("res://scripts/content/loot_rules.gd")
const ContentDB = preload("res://scripts/content/content_db.gd")
const FloorMap = preload("res://scripts/ui/floor_map.gd")
const RunRules = preload("res://scripts/core/run_rules.gd")
const SEED := 424242
const STEP := 1.0 / 60.0
var failures := 0
var chests: Array = []
var shrines: Array = []
var rests := 0


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ROOMS: " + detail)


func _key(physical: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = physical
    event.physical_keycode = physical
    event.pressed = true
    return event


func _run() -> void:
    var events: Node = get_root().get_node("Events")
    var rs: Node = get_root().get_node("RunState")
    events.chest_opened.connect(func(room_id, ids): chests.append([room_id, ids]))
    events.shrine_used.connect(func(choice): shrines.append(choice))
    events.guild_rested.connect(func(): rests += 1)
    _test_placement()
    _test_contents()
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    _test_chest(game, rs)
    _test_shrine_and_registry(game, rs)
    _test_guild_rest(game, rs)
    _test_trap_plates(game, rs)
    _test_floor_map(game, rs)
    game.queue_free()
    if failures == 0:
        print("PASS: special-room placement, features, chest, shrine, guild rest, plates, map overlay")
    quit(1 if failures > 0 else 0)


func _relaxed(floor: Dictionary, kind: String, level: int) -> bool:
    for entry in floor["relaxations"]:
        if String(entry["kind"]) == kind and int(entry["level"]) >= level:
            return true
    return false


func _test_placement() -> void:
    var cfg: Dictionary = Generator.default_config()
    var policy = Collapse.new(cfg["collapse"])
    for depth in range(1, 7):
        var expected: Dictionary = Generator.special_counts(depth, cfg["generation"])
        check(int(expected["treasure"]) == 1, "one treasure room per floor")
        check(int(expected["elite"]) == (0 if depth < 2 else 1), "elite 0-1 from depth 2")
        check(int(expected["trap"]) == [0, 1, 1, 1, 2, 2][depth - 1], "trap count by depth")
        check(int(expected["shrine"]) == (1 if depth >= 3 else 0), "shrine from depth 3")
        var count: int = RunRules.room_count(depth, cfg)
        for i in range(20):
            var seed_value: int = 700 + i * 31
            var floor: Dictionary = Generator.generate(seed_value, count, {"depth": depth})
            var rooms: Array = floor["rooms"]
            var spine: int = int(floor["spine_length"])
            var label := "depth %d seed %d" % [depth, seed_value]
            check(Generator.signature(rooms) == Generator.signature(
                Generator.generate(seed_value, count, {"depth": depth})["rooms"]), "deterministic " + label)
            check(int(floor["boss_id"]) == spine - 1 and int(floor["exit_id"]) == spine
                and rooms[spine - 1]["kind"] == "boss" and rooms[spine]["kind"] == "exit"
                and rooms[0]["kind"] == "start", "boss/exit/start untouched " + label)
            var tally := {}
            for room in rooms:
                tally[room["kind"]] = int(tally.get(room["kind"], 0)) + 1
            check(int(tally.get("treasure", 0)) == 1, "exactly one treasure " + label)
            check(int(tally.get("guild_hall", 0)) == 1 and int(floor["guild_id"]) > spine,
                "one guild hall, off the spine " + label)
            var hops: Dictionary = Generator.hop_distances(rooms, 0)
            check(int(hops[int(floor["guild_id"])]) >= 2, "guild >= 2 hops from start " + label)
            for kind in Generator.SPECIAL_ORDER:
                var ids: Array = floor["specials"][kind]
                check(ids.size() == int(expected[kind]) or _relaxed(floor, kind, 3),
                    "%s count %d (or logged) %s" % [kind, ids.size(), label])
                check(int(tally.get(kind, 0)) == ids.size(), "%s ids recorded %s" % [kind, label])
                for id in ids:
                    var room: Dictionary = rooms[int(id)]
                    check(int(id) > spine, "%s on a side room %s" % [kind, label])
                    var near: Array = []
                    for n in room["neighbors"].values():
                        near.append(String(rooms[int(n)]["kind"]))
                    if not _relaxed(floor, kind, 2):
                        check(not near.has(kind), "no adjacent %s pair %s" % [kind, label])
                    if kind == "treasure":
                        check(not near.has("start"), "treasure not next to start " + label)
                    if kind == "elite":
                        check(int(hops[int(id)]) >= 3, "elite >= 3 hops " + label)
                    if kind == "trap" and not _relaxed(floor, kind, 2):
                        check(not near.has("guild_hall") and room["neighbors"].size() > 1,
                            "trap not by the guild, not a dead end " + label)
            var route: Dictionary = Collapse.mandatory_route(floor, policy)
            for id in route["rooms"]:
                check(not Collapse.OFF_ROUTE_KINDS.has(String(rooms[int(id)]["kind"])),
                    "no special or guild room on the cheapest route " + label)
            check(bool(floor["feasibility"]["ok"]), "feasible " + label)
    var sig: String = Generator.signature(Generator.generate(SEED, 22)["rooms"])
    check(sig.contains(":treasure:") and sig.contains(":guild_hall:"), "signature includes kinds")


func _test_contents() -> void:
    var links := {"N": 1, "E": 2, "S": 3, "W": 4}
    for kind in ["treasure", "shrine", "guild_hall", "start", "exit"]:
        var room: Dictionary = Contents.generate(SEED, 5, links, kind, 38)
        check(room["props"].size() <= 13, "%s keeps the safe-room density" % kind)
    check(Contents.generate(SEED, 5, links, "trap", 38)["props"].size() <= 20, "trap density 20")
    check(Contents.generate(SEED, 5, links, "elite", 38)["props"].size() <= 30, "elite density 30")
    check(Contents.generate(SEED, 5, links, "boss", 38)["props"].size() == 38, "boss unchanged")
    var normal_a: Dictionary = Contents.generate(SEED, 5, links, "normal", 38)
    check(normal_a["interactables"].is_empty() and normal_a["plates"].is_empty(),
        "normal rooms have no features")
    for room_id in range(10):
        var treasure: Dictionary = Contents.generate(SEED + room_id, room_id, links, "treasure", 38)
        check(treasure["interactables"].size() == 1 and treasure["interactables"][0]["kind"] == "chest",
            "treasure room has one chest")
        var chest_cell: Vector2i = treasure["interactables"][0]["cell"]
        var reachable := false
        for direction in Contents.DIRECTIONS:
            var next: Vector2i = chest_cell + direction
            if Contents.is_walkable(next, treasure["blocked"]) and not Contents.find_path(
                    treasure["blocked"], Vector2i(12, 12), next).is_empty():
                reachable = true
        check(reachable and Contents.exits_reachable(treasure["blocked"], links),
            "chest stands at a reachable cell and keeps every door reachable")
        var shrine: Dictionary = Contents.generate(SEED, room_id, links, "shrine", 38)
        check(shrine["interactables"].size() == 1 and shrine["interactables"][0]["kind"] == "shrine",
            "shrine room has a shrine")
        var trap: Dictionary = Contents.generate(SEED + room_id, room_id, links, "trap", 38)
        var plates: Array = trap["plates"]
        var drains := 0
        for plate in plates:
            check(Contents.is_walkable(plate["cell"], trap["blocked"]), "plates are walkable")
            drains += 1 if plate["kind"] == "drain" else 0
        check(plates.size() >= 2 and plates.size() <= 4 and drains <= 2 and drains >= 1,
            "2-4 plates, at most 2 drains (%d/%d)" % [plates.size(), drains])
    var guild: Dictionary = Contents.generate(SEED, 3, links, "guild_hall", 38)
    var kinds: Array = []
    for entry in guild["interactables"]:
        kinds.append(entry["kind"])
    check(kinds == ["rest", "shop"], "guild hall has a rest station and the shop")


func _enter_room(game, rs: Node, id: int) -> void:
    rs.current_room_id = id
    rs.visited[id] = true
    game._load_room(id)
    game.combat.clear_hazards()


func _feature(rs: Node, kind: String) -> Dictionary:
    for entry in rs.current_room().get("interactables", []):
        if entry["kind"] == kind:
            return entry
    return {}


func _test_chest(game, rs: Node) -> void:
    game.start_run(SEED)
    var treasure_id: int = int(rs.floor["specials"]["treasure"][0])
    check(treasure_id == 11, "seed 424242: room 11 is the treasure room")
    _enter_room(game, rs, treasure_id)
    check(rs.current_room()["enemies"].is_empty(), "treasure rooms have no enemies")
    var chest: Dictionary = _feature(rs, "chest")
    game.player.world_position = Vector2(chest["pos"]) + Vector2(0, 16)
    game.services.update(STEP)
    check(game.services.prompt == "[E] Open the chest", "chest prompt in reach")
    game._redraw()
    check(game.hud.prompt == "[E] Open the chest", "HUD shows the prompt")
    var interact := InputEventAction.new()
    interact.action = "interact"
    interact.pressed = true
    game._unhandled_input(interact)
    var expected: Array[String] = LootRules.roll(ContentDB.default_db(), "treasure_room", SEED, 1,
        treasure_id, 0)
    check(chests.size() == 1 and chests[0][0] == treasure_id and chests[0][1] == Array(expected)
        and expected.size() == 2, "chest_opened(room, ids) rolls treasure_room deterministically")
    check(bool(chest["used"]) and game.services.focus().is_empty(), "chest opens once")
    game.services.try_interact()
    check(chests.size() == 1, "a second interact does nothing")
    game.start_run(SEED)
    _enter_room(game, rs, treasure_id)
    game.player.world_position = Vector2(_feature(rs, "chest")["pos"]) + Vector2(0, 16)
    game.services.try_interact()
    check(chests.size() == 2 and chests[1][1] == chests[0][1], "same seed, same loot")


func _test_shrine_and_registry(game, rs: Node) -> void:
    game.start_run(SEED)
    var room: int = rs.current_room_id
    var shrine: Dictionary = Interactables.make("shrine", Vector2i(9, 9), room)
    game.services.add_interactable(room, shrine)
    game.player.world_position = Vector2(shrine["pos"]) + Vector2(16, 0)
    var ticks: int = rs.ticks
    check(game.services.try_interact() and game.state == game.State.DIALOG
        and game.services.dialog.is_open(), "shrine opens the choice modal and freezes the game")
    var position: Vector2 = game.player.world_position
    Input.action_press("move_right")
    game._physics_process(STEP)
    Input.action_release("move_right")
    check(game.player.world_position == position, "world frozen during the modal")
    game.services.dialog.cancel()
    check(game.state == game.State.RUNNING and not bool(shrine["used"]), "walking away keeps it")
    game.services.try_interact()
    game.services.dialog.choose("stabilise")
    check(rs.ticks == ticks + 2 and shrines == ["stabilise"] and bool(shrine["used"])
        and game.state == game.State.RUNNING, "stabilise: +2 ticks, shrine_used(stabilise)")
    check(rs.tick_ledger.back()["source"] == "shrine", "shrine ticks are ledgered")
    game.services.try_interact()
    check(not game.services.dialog.is_open() and shrines.size() == 1, "one use per shrine")
    var mend: Dictionary = Interactables.make("shrine", Vector2i(14, 14), room)
    game.services.add_interactable(room, mend)
    game.player.world_position = Vector2(mend["pos"])
    rs.hp = 1
    var expected_hp: int = mini(rs.max_hp, 1 + int(ceil(rs.max_hp * 0.5)))
    game.services.try_interact()
    game.services.dialog.choose("mend")
    check(rs.hp == expected_hp and shrines == ["stabilise", "mend"], "mend heals 50 % of max HP")

    # Registry: other teams add their own interactable kinds.
    var used: Array = []
    game.services.register_interaction("vending", func(_e): return "[E] Insert soul",
        func(e): used.append(e["id"]))
    var vending: Dictionary = Interactables.make("vending", Vector2i(9, 14), room, {"once": false})
    game.services.add_interactable(room, vending)
    game.player.world_position = Vector2(vending["pos"])
    game.services.update(STEP)
    check(game.services.prompt == "[E] Insert soul", "custom prompt registered")
    game.services.try_interact()
    game.services.try_interact()
    check(used == [vending["id"], vending["id"]], "repeatable custom action")


func _test_guild_rest(game, rs: Node) -> void:
    game.start_run(SEED)
    _enter_room(game, rs, int(rs.floor["guild_id"]))
    var rest: Dictionary = _feature(rs, "rest")
    check(not rest.is_empty(), "guild hall has a rest station")
    game.player.world_position = Vector2(rest["pos"]) + Vector2(0, 16)
    rs.hp = 2
    game.services.try_interact()
    check(rs.hp == rs.max_hp and rests == 1, "rest: full heal, guild_rested")
    rs.hp = 2
    game.services.try_interact()
    check(rs.hp == 2 and rests == 1, "rest only once per floor")
    # Wave 2B: the shop sign became the guild shop (a repeatable choice dialog).
    var shop: Dictionary = _feature(rs, "shop")
    game.player.world_position = Vector2(shop["pos"]) + Vector2(0, 16)
    check(game.services.try_interact() and game.services.is_modal_open(), "shop opens its dialog")
    game.services.dialog.cancel()
    check(game.services.try_interact(), "shop is repeatable")
    game.services.dialog.cancel()
    # A new floor brings a new guild hall and a fresh rest.
    game._start_floor(2)
    _enter_room(game, rs, int(rs.floor["guild_id"]))
    game.player.world_position = Vector2(_feature(rs, "rest")["pos"]) + Vector2(0, 16)
    game.services.try_interact()
    check(rests == 2, "rest available again on the next floor")


func _test_trap_plates(game, rs: Node) -> void:
    game.start_run(SEED)
    game._start_floor(2)
    var traps: Array = rs.floor["specials"]["trap"]
    check(traps.size() == 1, "depth 2 has a trap room")
    if traps.is_empty():
        return
    _enter_room(game, rs, int(traps[0]))
    var plates: Array = rs.current_room()["plates"]
    var spike: Dictionary = {}
    var drain: Dictionary = {}
    for plate in plates:
        if plate["kind"] == "spike" and spike.is_empty():
            spike = plate
        if plate["kind"] == "drain" and drain.is_empty():
            drain = plate
    check(not spike.is_empty() and not drain.is_empty(), "trap room has spike and drain plates")
    if spike.is_empty() or drain.is_empty():
        return
    var hp: int = rs.hp
    game.player.invulnerability = 0.0
    game.player.world_position = Contents.cell_center(spike["cell"])
    game._physics_process(STEP)
    check(not bool(spike["armed"]) and game.combat.hazards.size() == 1
        and game.combat.hazards[0]["kind"] == "spike", "stepping on a plate spawns a spike")
    for _i in range(40):
        game._physics_process(STEP)
    check(rs.hp == hp - 3, "spike lands once for 3 damage after its telegraph")
    # Step off (standing on an armed plate fires it again), then wait to rearm.
    game.player.world_position = Contents.cell_center(Vector2i(12, 12))
    for _i in range(130):
        game.player.invulnerability = 1.0
        game._physics_process(STEP)
    check(bool(spike["armed"]), "spike plate rearms")
    var ticks: int = rs.ticks
    game.player.world_position = Contents.cell_center(drain["cell"])
    for _i in range(60):
        game.player.invulnerability = 0.0
        game._physics_process(STEP)
    check(rs.ticks == ticks - 1 and rs.tick_ledger.back()["source"] == "hazard:drain_plate",
        "drain plate takes 1 tick after the telegraph")
    for _i in range(200):
        game._physics_process(STEP)
    check(rs.ticks == ticks - 1 and not bool(drain["armed"]), "drain plates are one-shot")


func _test_floor_map(game, rs: Node) -> void:
    game.start_run(SEED)
    var rooms: Array = rs.floor["rooms"]
    var model: Dictionary = FloorMap.build_model(rs.floor, rs.visited, 0, rs.ticks, game.rules,
        rs.room_states, false)
    var states := {}
    for room in model["rooms"]:
        states[int(room["id"])] = room
    check(states.has(0) and states[0]["state"] == "visited" and bool(states[0]["current"]),
        "current room visited and highlighted")
    for neighbor in rooms[0]["neighbors"].values():
        check(states.has(int(neighbor)) and states[int(neighbor)]["state"] == "scouted",
            "known neighbours are scouted")
    check(not states.has(int(rs.floor["exit_id"])), "exit hidden until discovered")
    check(model["edges"].size() == rooms[0]["neighbors"].size(), "links from visited rooms only")
    for edge in model["edges"]:
        check(edge["label"] == "-2", "door preview on edges of the current room")
    var boss_id: int = int(rs.floor["boss_id"])
    var seen_boss := {boss_id: true}
    var near_exit: Dictionary = FloorMap.build_model(rs.floor, seen_boss, boss_id, 5, game.rules,
        {}, false)
    var exit_known := false
    for room in near_exit["rooms"]:
        if int(room["id"]) == int(rs.floor["exit_id"]):
            exit_known = room["icon"] == "X"
    check(exit_known, "exit shown once discovered")
    for edge in near_exit["edges"]:
        if int(edge["a"]) == int(rs.floor["exit_id"]) or int(edge["b"]) == int(rs.floor["exit_id"]):
            check(edge["label"] == "sealed", "sealed exit edge")

    var position: Vector2 = game.player.world_position
    var time_before: float = float(rs.telemetry["run_time_seconds"])
    game._input(_key(KEY_M))
    check(game.state == game.State.MAP and game.floor_map.is_open(), "M opens the map")
    Input.action_press("move_right")
    for _i in range(10):
        game._physics_process(STEP)
    Input.action_release("move_right")
    check(game.player.world_position == position
        and float(rs.telemetry["run_time_seconds"]) == time_before, "map freezes simulation")
    var interact := InputEventAction.new()
    interact.action = "interact"
    interact.pressed = true
    game._unhandled_input(interact)
    check(game.state == game.State.MAP, "interact ignored under the map")
    game._input(_key(KEY_M))
    check(game.state == game.State.RUNNING and not game.floor_map.is_open(), "M closes the map")
    game._input(_key(KEY_M))
    game._input(_key(KEY_ESCAPE))
    check(game.state == game.State.RUNNING and game.character_menu.mode == "closed",
        "Esc closes the map without opening pause")
