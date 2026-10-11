extends SceneTree
## Run: godot --headless --path game --script res://tests/smoke_test.gd

const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Main = preload("res://scripts/main.gd")
var failures := 0


func _initialize() -> void:
    run_tests()
    if failures == 0:
        print("PASS: generation, collapse policies, facing sheets, 32px tile regions, resizable layouts")
    quit(1 if failures > 0 else 0)


func check(condition: bool, explanation: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + explanation)


func run_tests() -> void:
    var raw: String = FileAccess.get_file_as_string("res://data/prototype_rules.json")
    var config = JSON.parse_string(raw)
    check(config is Dictionary, "JSON config parses as an object")
    if not config is Dictionary:
        return
    var policy = Collapse.new(config.get("collapse", {}))

    # Independent artwork by category, with all 8 compass facings.
    var crypt: Texture2D = load("res://assets/biomes/stone_crypt/tileset.png") as Texture2D
    check(crypt != null, "biome tileset imports")
    if crypt != null:
        check(crypt.get_size() == Vector2(128, 128), "crypt tileset is 128x128")
        for tile in [Rect2(0, 0, 32, 32), Rect2(32, 0, 32, 32),
                Rect2(64, 0, 32, 32), Rect2(96, 0, 32, 32), Rect2(64, 64, 64, 64)]:
            check(tile.end.x <= 128 and tile.end.y <= 128, "environment tile is within atlas")
    for sprite in [
            {"path": "res://assets/characters/crawler/facing_8.png", "frame": 48},
            {"path": "res://assets/enemies/rat/facing_8.png", "frame": 48},
            {"path": "res://assets/enemies/brute_boss/facing_8.png", "frame": 96}
        ]:
        var sheet: Texture2D = load(sprite["path"]) as Texture2D
        check(sheet != null, "facing sheet imports: %s" % sprite["path"])
        if sheet != null:
            var cell: int = int(sprite["frame"])
            check(sheet.get_size() == Vector2(cell * 8, cell),
                "sheet has exactly 8 frames: %s" % sprite["path"])

    var main = Main.new()
    var facing_vectors: Array[Vector2] = [
        Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
        Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)
    ]
    for i in range(8):
        check(main._facing_from_vector(facing_vectors[i]) == i,
            "eight-way facing quadrant %d" % i)
    main.free()

    for dimensions in [Vector2(720, 480), Vector2(960, 540),
            Vector2(1280, 720), Vector2(1920, 1080)]:
        var layout: Dictionary = Layout.compute(dimensions)
        var bounds: Rect2 = layout["arena"]
        check(int(layout["columns"]) % 2 == 0 and int(layout["rows"]) % 2 == 0,
            "even tile counts allow 2-cell door openings")
        check(int(bounds.size.x) % 32 == 0 and int(bounds.size.y) % 32 == 0,
            "room dimensions are 32px multiples")
        check(bounds.position.x >= 32 and bounds.position.y >= 108,
            "room top and sides leave room for HUD and walls")
        check(bounds.end.x <= dimensions.x - 32 and bounds.end.y <= dimensions.y - 80,
            "room stays inside the resizeable window")
    check(
        Layout.compute(Vector2(1920, 1080))["columns"] >
            Layout.compute(Vector2(960, 540))["columns"],
        "larger window exposes more tiles rather than stretching a fixed room"
    )

    for seed_value in range(25):
        var floor: Dictionary = Generator.generate(seed_value + 1100, 22)
        var rooms: Array = floor["rooms"]
        check(rooms.size() == 22, "room count seed %d" % seed_value)
        check(
            Generator.signature(rooms) == Generator.signature(
                Generator.generate(seed_value + 1100, 22)["rooms"]
            ),
            "deterministic graph seed %d" % seed_value
        )
        check(rooms[int(floor["boss_id"])]["kind"] == "boss", "boss exists")
        check(rooms[int(floor["guild_id"])]["kind"] == "guild_hall", "guild hall exists")
        check(rooms[int(floor["exit_id"])]["kind"] == "exit", "exit exists")

        var seen_positions: Dictionary = {}
        for room in rooms:
            var grid: Vector2i = room["grid"]
            check(not seen_positions.has(grid), "unique room coordinate")
            seen_positions[grid] = true
            check(
                not Generator.path_between(rooms, 0, int(room["id"])).is_empty(),
                "every room reachable from start"
            )
            for direction in room["neighbors"].keys():
                var neighbor_id: int = int(room["neighbors"][direction])
                var reverse: String = {"N": "S", "S": "N", "W": "E", "E": "W"}[direction]
                check(
                    int(rooms[neighbor_id]["neighbors"].get(reverse, -1)) == int(room["id"]),
                    "bidirectional door"
                )

        check(
            Collapse.mandatory_budget_floor(floor, policy) > 0,
            "mandatory budget diagnostic works"
        )
    var default_first: Dictionary = policy.evaluate(10, "normal", true, 9)
    var revisit: Dictionary = policy.evaluate(10, "normal", false, 9)
    var boss: Dictionary = policy.evaluate(10, "boss", true, 9)
    var guild: Dictionary = policy.evaluate(10, "guild_hall", true, 9)
    check(default_first["cost"] == 2, "normal first entry charge")
    check(revisit["cost"] == 0, "revisit can be free")
    check(boss["cost"] == 3, "boss room override")
    check(guild["cost"] == 0 and guild["grant"] == 3, "guild hall grants ticks")
    check(policy.evaluate(1, "boss", true, 7)["allowed"] == false, "cannot overspend")
    check(policy.evaluate(2, "normal", true, 7)["collapses"], "zero triggers collapse")
