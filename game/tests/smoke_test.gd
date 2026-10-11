extends SceneTree
## Run: godot --headless --path game --script res://tests/smoke_test.gd
const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Contents = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const Main = preload("res://scripts/main.gd")
const CharacterMenu = preload("res://scripts/character_menu.gd")
var failures := 0

func _initialize() -> void:
    run_tests()
    if failures == 0:
        print("PASS: fixed room, scaled viewport, seeded obstacles, exits, AI, encounters and d20 XP")
    quit(1 if failures > 0 else 0)

func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + detail)

func run_tests() -> void:
    var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_rules.json"))
    check(cfg is Dictionary, "config loads")
    if not cfg is Dictionary:
        return
    var collapse = Collapse.new(cfg.get("collapse", {}))
    check(collapse.evaluate(10, "normal", true, 1)["cost"] == 2, "normal tick cost")
    check(collapse.evaluate(10, "normal", false, 1)["cost"] == 0, "revisit free")
    check(collapse.evaluate(10, "boss", true, 1)["cost"] == 3, "boss override")
    check(collapse.evaluate(10, "guild_hall", true, 1)["grant"] == 3, "guild grant")
    check(not bool(collapse.evaluate(1, "boss", true, 1)["allowed"]), "cannot overspend")

    # The interior always contains exactly 24x24 logical 32px tiles.
    var last_scale := 0.0
    for dimensions in [Vector2(720, 480), Vector2(960, 540),
            Vector2(1280, 720), Vector2(1920, 1080)]:
        var l: Dictionary = Layout.compute(dimensions)
        var arena: Rect2 = l["arena"]
        check(int(l["columns"]) == 24 and int(l["rows"]) == 24, "fixed tile count")
        check(arena == Rect2(0, 0, 768, 768), "world bounds never change")
        check(float(l["scale"]) >= last_scale, "larger window yields same or larger scale")
        last_scale = float(l["scale"])
        var upper_left: Vector2 = Layout.world_to_screen(Vector2(-32, -32), l)
        var lower_right: Vector2 = Layout.world_to_screen(Vector2(800, 800), l)
        check(upper_left.x >= 0 and upper_left.y >= 98, "room ring inside upper margins")
        check(lower_right.x <= dimensions.x and lower_right.y <= dimensions.y - 55,
            "room ring fits under HUD")
        var sample := Vector2(216.0, 535.0)
        check(Layout.screen_to_world(Layout.world_to_screen(sample, l), l).distance_to(sample) < 0.01,
            "mouse screen/world mapping invertible")
    check(Layout.compute(Vector2(1920, 1080))["scale"] >
        Layout.compute(Vector2(720, 480))["scale"], "render scale changes with window")

    # Existing art uses separate files. Rat has 8 directional images.
    var crypt: Texture2D = load("res://assets/biomes/stone_crypt/tileset.png") as Texture2D
    check(crypt != null and crypt.get_size() == Vector2(128, 128), "crypt tileset")
    for entry in [
        {"path":"res://assets/characters/crawler/facing_8.png", "frame":48},
        {"path":"res://assets/enemies/rat/facing_8.png", "frame":32},
        {"path":"res://assets/enemies/brute_boss/facing_8.png", "frame":96}
    ]:
        var sheet: Texture2D = load(entry["path"]) as Texture2D
        check(sheet != null, "facing sheet loads: " + entry["path"])
        if sheet != null:
            check(sheet.get_size() == Vector2(int(entry["frame"])*8, int(entry["frame"])),
                "facing sheet regions valid")
    var scene = Main.new()
    for i in range(8):
        var angle: float = float(i) * PI / 4.0
        check(scene._facing_from_vector(Vector2.RIGHT.rotated(angle)) == i,
            "eight-way direction %d" % i)
    scene.free()

    # Six stats, ability modifiers (including negative odd scores), XP thresholds.
    check(RPG.modifier(8) == -1 and RPG.modifier(9) == -1, "negative modifiers floor")
    check(RPG.modifier(10) == 0 and RPG.modifier(15) == 2, "positive modifiers")
    check(RPG.ABILITIES.size() == 6, "six core abilities")
    check(RPG.level_for_xp(0) == 1 and RPG.level_for_xp(299) == 1, "level 1 XP")
    check(RPG.level_for_xp(300) == 2 and RPG.level_for_xp(900) == 3, "XP milestones")
    check(RPG.proficiency(1) == 2 and RPG.proficiency(5) == 3, "proficiency progression")
    var stats: Dictionary = RPG.player_base_scores()
    check(RPG.armor_class(stats) == 12, "DEX-based armor class")
    check(RPG.player_hp_at_level(2, stats) > RPG.player_hp_at_level(1, stats),
        "leveling increases max HP")
    var dice := RandomNumberGenerator.new()
    dice.seed = 123
    var attack: Dictionary = RPG.roll_to_hit(dice, 4, 12)
    check(int(attack["d20"]) >= 1 and int(attack["d20"]) <= 20, "d20 roll range")
    check(RPG.roll_damage(dice, 6, 2, false) >= 1, "weapon die and ability damage")

    # Allocation is exact, capped, nonnegative, and cannot invent new stat keys.
    var two_points: Dictionary = {"STR": 1, "CON": 1}
    var allocated: Dictionary = RPG.apply_allocation(stats, two_points, 2, 20)
    check(not allocated.is_empty(), "valid level-up allocation accepted")
    check(int(allocated["STR"]) == 15 and int(allocated["CON"]) == 15,
        "point allocation changes intended ability scores")
    check(RPG.apply_allocation(stats, {"STR": 3}, 2, 20).is_empty(),
        "overspending points is rejected")
    check(RPG.apply_allocation(stats, {"STR": -1, "DEX": 3}, 2, 20).is_empty(),
        "negative point allocations are rejected")
    check(RPG.apply_allocation(stats, {"LCK": 2}, 2, 20).is_empty(),
        "unknown abilities rejected")
    var capped: Dictionary = stats.duplicate(true)
    capped["STR"] = 20
    check(RPG.apply_allocation(capped, {"STR": 1, "DEX": 1}, 2, 20).is_empty(),
        "ability cap enforced")
    check(RPG.player_hp_at_level(3, {"CON": 16}) >
        RPG.player_hp_at_level(3, {"CON": 14}), "CON upgrades affect maximum HP")
    check(RPG.armor_class({"DEX": 16}) > RPG.armor_class({"DEX": 14}),
        "DEX upgrades affect armor class")
    check(RPG.level_for_xp(2700) - RPG.level_for_xp(0) == 3,
        "multi-level XP awards preserve all earned levels")

    # Modal view model refuses overspending and gates confirming until points spent.
    var menu = CharacterMenu.new()
    menu.show_level_up(stats, {"level": 2}, 2, 20)
    check(menu.mode == "level_up" and menu.remaining_points() == 2,
        "level-up menu starts with available points")
    check(menu.stage_point("STR", 1) and menu.stage_point("DEX", 1),
        "point buttons stage legitimate choices")
    check(menu.remaining_points() == 0, "staged points exhaust pool")
    check(not menu.stage_point("STR", 1), "no extra points after spending pool")
    check(menu.stage_point("STR", -1) and menu.remaining_points() == 1,
        "minus button refunds a staged point")
    menu.show_pause(stats, {"level": 2, "xp": 300})
    check(menu.mode == "pause", "pause page opens")
    menu.free()

    # Enemy templates and AI definitions are editable data, not hard-coded encounters.
    var catalog: Dictionary = Enemies.load_catalogue()
    check(Enemies.validate_catalogue(catalog).is_empty(), "enemy schema and behavior valid")
    check(catalog["enemies"].size() >= 4, "multiple enemy templates")
    check(catalog["enemies"]["spitting_rat"]["attacks"][0]["type"] == "ranged",
        "ranged enemy weapon defined")
    check(catalog["enemies"]["rat_scavenger"]["attacks"][0]["type"] == "melee",
        "melee enemy weapon defined")

    for offset_seed in range(8):
        var generated: Dictionary = Generator.generate(1100 + offset_seed, 22)
        var again: Dictionary = Generator.generate(1100 + offset_seed, 22)
        var rooms: Array = generated["rooms"]
        check(Generator.signature(rooms) == Generator.signature(again["rooms"]),
            "deterministic floor graph")
        check(not Generator.path_between(rooms, 0, int(generated["exit_id"])).is_empty(),
            "floor exit reachable")
        check(Collapse.mandatory_budget_floor(generated, collapse) > 0,
            "collapse budget diagnostic works")
        for room_id in [0, 1, 2, int(generated["boss_id"])]:
            var room: Dictionary = rooms[room_id]
            var obstacle_map: Dictionary = Contents.generate(1100+offset_seed,
                room_id, room["neighbors"], String(room["kind"]), 40)
            var repeats: Dictionary = Contents.generate(1100+offset_seed,
                room_id, room["neighbors"], String(room["kind"]), 40)
            check(obstacle_map["props"] == repeats["props"], "deterministic obstacles")
            check(Contents.exits_reachable(obstacle_map["blocked"], room["neighbors"]),
                "every generated doorway reachable")
            check(Contents.is_walkable(Vector2i(12, 12), obstacle_map["blocked"]),
                "player start unobstructed")
            var encounter: Array[Dictionary] = Enemies.generate_encounter(catalog,
                String(room["kind"]), 1100+offset_seed, room_id, obstacle_map["blocked"])
            if room["kind"] == "normal":
                check(encounter.size() >= 2 and encounter.size() <= 4,
                    "normal room has multiple enemies")
            if room["kind"] == "boss":
                check(encounter.size() >= 2, "boss room has mixed encounter")
            for foe in encounter:
                check(Contents.can_occupy(foe["pos"], float(foe["radius"]), obstacle_map["blocked"]),
                    "enemy spawns on a walkable tile")
                check(not Contents.find_path(obstacle_map["blocked"],
                    Contents.cell_of(foe["pos"]), Vector2i(12, 12)).is_empty(),
                    "enemy spawn reachable via navigation graph")
    check(Enemies.has_line_of_sight(Vector2(64, 64), Vector2(160, 64), {}),
        "line of sight over open tiles")
    check(not Enemies.has_line_of_sight(Vector2(64, 64), Vector2(160, 64),
        {Vector2i(3, 2): true}), "obstacle blocks projectile line of sight")
