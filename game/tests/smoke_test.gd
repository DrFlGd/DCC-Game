extends SceneTree
## Run: godot --headless --path game --script res://tests/smoke_test.gd

const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
var failures := 0


func _initialize() -> void:
    run_tests()
    if failures == 0:
        print("PASS: seed, connectivity, room types, collapse policy, budget diagnostics")
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

    # The visual prototype must have a valid 192x160 atlas that covers all regions.
    var atlas: Texture2D = load("res://assets/crypt_atlas.png") as Texture2D
    check(atlas != null, "crypt atlas imports successfully")
    if atlas != null:
        check(atlas.get_size() == Vector2(192, 160), "crypt atlas is 192x160")
        var regions: Array[Rect2] = [
            Rect2(0, 0, 32, 32), Rect2(32, 0, 32, 32),
            Rect2(64, 0, 64, 64), Rect2(0, 64, 48, 48),
            Rect2(48, 64, 48, 48), Rect2(96, 64, 96, 96)
        ]
        for region in regions:
            check(region.position.x >= 0 and region.position.y >= 0
                and region.end.x <= atlas.get_width()
                and region.end.y <= atlas.get_height(),
                "art region fits within atlas: %s" % region)


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
