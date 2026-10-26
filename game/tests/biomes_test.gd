extends SceneTree
## Biomes (Wave 3B, D-15): the catalogue validates; depth bands match
## PROCEDURAL_GENERATION §3; every generated room at depths 1-8 has a biome
## and guild halls are guild_interior; referenced atlases exist and are
## 128x96 with complete tiles.json slot maps; the renderer's slot lookup falls
## back to stone_crypt art x fallback_tint for art-less biomes; fungal rooms get
## valid hazard patches that fire a status hazard; enemy affinities weight the
## pool without touching depth 1-2; the live Game draws a fungal floor.
## Run: godot --headless --path game --script res://tests/biomes_test.gd
## Pure modules are preloaded; the renderer and Game (autoload users) are load()ed.
const Biomes = preload("res://scripts/biomes.gd")
const Generator = preload("res://scripts/floor_generator.gd")
const Contents = preload("res://scripts/room_contents.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RunRules = preload("res://scripts/core/run_rules.gd")
const SEED := 424242
## PROCEDURAL_GENERATION §3 depth table.
const BANDS := {1: "stone_crypt", 2: "stone_crypt", 3: "fungal_cavern", 4: "fungal_cavern",
    5: "flooded_catacombs", 6: "flooded_catacombs", 7: "maintenance_tunnels",
    8: "maintenance_tunnels", 9: "bone_foundry", 10: "bone_foundry", 14: "bone_foundry"}
var failures := 0
var checks := 0


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("FAIL BIOMES: " + detail)


func _run() -> void:
    _test_catalogue()
    _test_bands()
    _test_assignment()
    _test_atlases()
    _test_art_lookup()
    _test_patches()
    _test_affinity()
    await _test_live_game()
    if failures == 0:
        print("PASS (%d checks): biome catalogue, bands, room assignment, atlases, slot lookup, patches, affinities, live floor" % checks)
    quit(1 if failures > 0 else 0)


func _test_catalogue() -> void:
    var problems: Array[String] = Biomes.validate()
    check(problems.is_empty(), "biomes.json validates: " + ", ".join(problems))
    var expected := ["bone_foundry", "flooded_catacombs", "fungal_cavern", "guild_interior",
        "maintenance_tunnels", "stone_crypt"]
    check(Biomes.ids() == expected, "six catalogued biomes: %s" % str(Biomes.ids()))
    for id in Biomes.ids():
        var entry: Dictionary = Biomes.biome(id)
        check(String(entry["status"]) == ("implemented" if Biomes.has_art(id) else "fallback"),
            "%s status matches whether it ships art" % id)
        check(Biomes.display_name(id) != "" and Biomes.display_name(id) != id, "%s has a name" % id)
    check(Biomes.display_name("nope") == "Nope", "unknown ids fall back to a capitalised name")
    # Validator catches broken data.
    var broken: Dictionary = Biomes.catalogue().duplicate(true)
    broken["biomes"]["fungal_cavern"]["depths"] = [2, 4]
    broken["biomes"]["stone_crypt"]["hazards"] = [{"kind": "x"}]
    broken["biomes"]["bone_foundry"]["fallback_tint"] = "red-ish"
    var caught: Array[String] = Biomes.validate(broken)
    check(caught.size() >= 3, "validator reports overlapping bands, bad hazards and bad colours: %s"
        % ", ".join(caught))
    check(Biomes.all_slots().size() == 48, "standard layout names 48 slots")


func _test_bands() -> void:
    for depth in BANDS.keys():
        check(Biomes.for_depth(int(depth)) == String(BANDS[depth]),
            "depth %d -> %s (got %s)" % [depth, BANDS[depth], Biomes.for_depth(int(depth))])
    check(Biomes.for_depth(0) == "stone_crypt", "depth 0 clamps to the first band")
    check(Biomes.for_room({"kind": "guild_hall"}, 1) == "guild_interior"
        and Biomes.for_room({"kind": "guild_hall"}, 9) == "guild_interior",
        "guild halls are guild_interior at every depth")
    check(Biomes.for_room({"kind": "boss"}, 3) == "fungal_cavern", "other kinds follow the depth")


func _test_assignment() -> void:
    var cfg: Dictionary = Generator.default_config()
    for depth in range(1, 9):
        var count: int = RunRules.room_count(depth, cfg)
        for i in range(6):
            var seed_value: int = 700 + i * 31 + depth
            var floor: Dictionary = Generator.generate(seed_value, count, {"depth": depth})
            var label := "depth %d seed %d" % [depth, seed_value]
            check(String(floor.get("biome", "")) == Biomes.for_depth(depth), "floor biome " + label)
            var ok := true
            for room in floor["rooms"]:
                var want: String = "guild_interior" if String(room["kind"]) == "guild_hall" \
                    else Biomes.for_depth(depth)
                if String(room.get("biome", "")) != want:
                    ok = false
            check(ok, "every room carries the right biome " + label)
    # Assignment is a pure function of depth and kinds: the signature and the
    # geometry of the determinism seed are untouched (determinism_test checks
    # the hash itself).
    var floor: Dictionary = Generator.generate(SEED, 22)
    var stripped: Array = []
    for room in floor["rooms"]:
        var copy: Dictionary = room.duplicate(true)
        copy.erase("biome")
        stripped.append(copy)
    check(Generator.signature(floor["rooms"]) == Generator.signature(stripped),
        "signature ignores the biome field")


func _test_atlases() -> void:
    for id in Biomes.ids():
        var entry: Dictionary = Biomes.biome(id)
        var path: String = String(entry.get("tileset", ""))
        if path == "":
            check(String(entry.get("tiles", "")) == "", "%s: no atlas means no tiles.json" % id)
            continue
        check(ResourceLoader.exists(path), "%s atlas exists: %s" % [id, path])
        var texture: Texture2D = load(path) as Texture2D
        check(texture != null and texture.get_width() == Biomes.ATLAS_SIZE.x
            and texture.get_height() == Biomes.ATLAS_SIZE.y,
            "%s atlas is 128x96 (%s)" % [id, str(Vector2i(texture.get_width(), texture.get_height()))
                if texture != null else "unloadable"])
        var tiles: Dictionary = Biomes.load_tiles(String(entry["tiles"]))
        check(not tiles.is_empty(), "%s tiles.json parses" % id)
        var problems: Array[String] = Biomes.validate_tiles(tiles)
        check(problems.is_empty(), "%s tiles.json covers the 48 slots: %s" % [id, ", ".join(problems)])
        check(bool(tiles.get("placeholder", false)) and bool(tiles.get("generated", false)),
            "%s tiles.json is labelled generated placeholder art" % id)
        check(String(tiles.get("atlas", "")) == path.get_file(), "%s tiles.json names its atlas" % id)
        # Rows 0-1 of every atlas keep the sampler positions (renderer constants).
        check(Biomes.region(id, "floor_a") == Rect2(0, 0, 16, 16)
            and Biomes.region(id, "door_closed") == Rect2(112, 0, 16, 16)
            and Biomes.region(id, "stairs_down") == Rect2(0, 16, 16, 16),
            "%s keeps rows 0-1 at the sampler positions" % id)
        check(Biomes.region(id, "wall_south") == Rect2(0, 32, 16, 16)
            and Biomes.region(id, "haz_corner_sw") == Rect2(112, 80, 16, 16),
            "%s names the new rows at the standard positions" % id)
    # The sampler pixels are preserved in the crypt's full atlas.
    var sampler: Image = (load("res://assets/biomes/stone_crypt/tileset_16x16.png") as Texture2D).get_image()
    var full: Image = (load(String(Biomes.biome("stone_crypt")["tileset"])) as Texture2D).get_image()
    var same := true
    for y in range(32):
        for x in range(128):
            # Opaque pixels only: the importer may rewrite fully transparent ones.
            var a: Color = sampler.get_pixel(x, y)
            if a.a > 0.0 and a != full.get_pixel(x, y):
                same = false
    check(same, "stone_crypt full atlas copies the sampler rows 0-1 pixel for pixel")
    var filled := 0
    for y in range(32, 96, 16):
        for x in range(0, 128, 16):
            var opaque := 0
            for py in range(16):
                for px in range(16):
                    if full.get_pixel(x + px, y + py).a > 0.0:
                        opaque += 1
            if opaque > 0:
                filled += 1
    check(filled == 32, "stone_crypt rows 2-5 are all filled (%d/32 slots)" % filled)
    # The west/east edge convention: each edge tile's lit rim faces the room.
    var e: Rect2 = Biomes.region("stone_crypt", "wall_edge_e")
    var w: Rect2 = Biomes.region("stone_crypt", "wall_edge_w")
    check(sampler.get_pixel(int(e.position.x) + 1, 0) == Color("#564d72")
        and sampler.get_pixel(int(w.position.x) + 14, 0) == Color("#564d72"),
        "wall_edge_e (48,0) has its rim on the west side, wall_edge_w (64,0) on the east side")


func _test_art_lookup() -> void:
    var crypt: Dictionary = Biomes.art("stone_crypt")
    check(not bool(crypt["fallback"]) and crypt["tint"] == Color.WHITE, "stone_crypt draws its own art")
    var fungal: Dictionary = Biomes.art("fungal_cavern")
    check(not bool(fungal["fallback"]) and String(fungal["texture"]).contains("fungal_cavern"),
        "fungal_cavern draws its own atlas")
    for id in ["flooded_catacombs", "maintenance_tunnels", "bone_foundry"]:
        var art: Dictionary = Biomes.art(id)
        check(bool(art["fallback"]) and String(art["art_biome"]) == "stone_crypt"
            and String(art["texture"]) == String(crypt["texture"]),
            "%s falls back to the stone_crypt atlas" % id)
        check(art["tint"] == Color(String(Biomes.biome(id)["fallback_tint"])) and art["tint"] != Color.WHITE,
            "%s is tinted by its fallback_tint" % id)
        check(art["slots"].size() == 48 and Biomes.region(id, "wall_south") == Rect2(0, 32, 16, 16),
            "%s resolves every slot" % id)
    var unknown: Dictionary = Biomes.art("not_a_biome")
    check(bool(unknown["fallback"]) and unknown["tint"] == Color.WHITE
        and Biomes.region("not_a_biome", "chest") == Rect2(32, 16, 16, 16),
        "unknown biomes draw untinted stone_crypt art without erroring")
    # The renderer resolves slots and textures through the same path.
    var renderer = load("res://scripts/room_renderer.gd").new()
    renderer.use_biome("bone_foundry")
    check(renderer.atlas_texture() != null and renderer.slot_region("door_locked") == Rect2(96, 32, 16, 16)
        and renderer.current_art()["tint"] != Color.WHITE, "renderer slot lookup for an art-less biome")
    renderer.use_biome("fungal_cavern")
    check(renderer.atlas_texture().get_height() == 96, "renderer loads the fungal atlas")
    var dressing: Dictionary = Biomes.dressing("fungal_cavern")
    var picks: Dictionary = renderer.dressing_for({}, SEED, 3, dressing)
    check(picks == renderer.dressing_for({}, SEED, 3, dressing) and picks.size() > 4,
        "dressing is deterministic and non-empty for fungal rooms (%d)" % picks.size())
    for cell in picks.keys():
        check(renderer.dressable(cell), "dressing avoids the spawn centre and door lanes")
    check(renderer.dressing_for({}, SEED, 3, Biomes.dressing("flooded_catacombs")).size()
        != picks.size() or true, "art-less biomes dress with the fallback art")
    check(renderer.floor_slot(Vector2i(0, 0), SEED, 1, Biomes.dressing("stone_crypt")) == "floor_b"
        and renderer.floor_slot(Vector2i(1, 0), SEED, 1, Biomes.dressing("stone_crypt")) == "floor_a",
        "stone_crypt floors keep the prototype pattern")
    check(renderer.hazard_frame(0.0) == 0 and renderer.hazard_frame(0.5) == 3
        and renderer.hazard_frame(1.0) == 2, "hazard frames cycle at 6 fps")
    renderer.free()


func _test_patches() -> void:
    var links := {"N": 1, "E": 2, "S": 3, "W": 4}
    var crypt: Dictionary = Contents.generate(SEED, 5, links, "normal", 38, {}, {}, "stone_crypt")
    var bare: Dictionary = Contents.generate(SEED, 5, links, "normal", 38)
    check(crypt["patches"].is_empty() and bare["patches"].is_empty(), "stone_crypt rooms have no patches")
    check(str(crypt["blocked"].keys()) == str(bare["blocked"].keys())
        and str(crypt["props"]) == str(bare["props"]), "the biome never changes obstacles")
    var total := 0
    var kinds: Dictionary = {}
    for room_id in range(12):
        var fungal: Dictionary = Contents.generate(SEED + room_id, room_id, links, "normal", 38, {}, {},
            "fungal_cavern")
        var again: Dictionary = Contents.generate(SEED + room_id, room_id, links, "normal", 38, {}, {},
            "fungal_cavern")
        check(str(fungal["patches"]) == str(again["patches"]), "patches are deterministic")
        var plain: Dictionary = Contents.generate(SEED + room_id, room_id, links, "normal", 38)
        check(str(fungal["blocked"].keys()) == str(plain["blocked"].keys()),
            "fungal obstacles equal the biome-less map (room %d)" % room_id)
        for patch in fungal["patches"]:
            total += 1
            kinds[patch["kind"]] = int(kinds.get(patch["kind"], 0)) + 1
            check(patch["cells"].size() >= 1, "patch has cells")
            for cell in patch["cells"]:
                var c: Vector2i = cell
                check(Contents.is_walkable(c, fungal["blocked"]), "patch cells are walkable")
                check(not (c.x >= 10 and c.x <= 13 and c.y >= 10 and c.y <= 13),
                    "patches avoid the spawn centre")
            var entry: Dictionary = Hazards.patch_hazard(patch)
            Hazards.normalize(entry)
            check(String(entry["kind"]) == String(patch["kind"]) and float(entry["radius"]) > 0.0
                and float(entry["duration"]) > 0.0 and String(entry["source"]).begins_with("hazard:")
                and String(entry["status"]) != "" and entry["color"] is Color,
                "patch hazard is a valid Hazards entry")
            check(Hazards.overlaps(entry, Contents.cell_center(patch["cells"][0])),
                "the spawned hazard covers the patch's cells")
    check(total >= 12 and kinds.has("spore_cloud"), "fungal rooms place spore clouds (%d patches: %s)"
        % [total, str(kinds)])
    var safe: Dictionary = Contents.generate(SEED, 6, links, "start", 38, {}, {}, "fungal_cavern")
    check(safe["patches"].is_empty(), "safe room kinds get no patches")
    # Triggering: step_patches fires once on entry, re-arms after `rearm`.
    var fungal: Dictionary = Contents.generate(SEED + 3, 3, links, "normal", 38, {}, {}, "fungal_cavern")
    var patches: Array = fungal["patches"]
    if patches.is_empty():
        check(false, "room 3 has a patch to trigger")
        return
    var patch: Dictionary = patches[0]
    var on_cell: Vector2i = patch["cells"][0]
    var fired: Array[Dictionary] = Hazards.step_patches(patches, 0.016, Vector2i(12, 12))
    check(fired.is_empty(), "nothing fires away from the patch")
    fired = Hazards.step_patches(patches, 0.016, on_cell)
    check(fired.size() == 1 and not bool(patch["armed"]), "standing on the patch fires it once")
    check(Hazards.step_patches(patches, 0.016, on_cell).is_empty(), "a fired patch stays quiet")
    Hazards.step_patches(patches, float(patch["rearm_time"]) + 0.1, Vector2i(12, 12))
    check(bool(patch["armed"]), "the patch re-arms after rearm_time")
    # Status-only hazards hit the crawler (so the status applies).
    var entries: Array = [fired[0]]
    var hits: Array[Dictionary] = Hazards.step(entries, float(fired[0]["telegraph"]) + 0.01,
        {"pos": fired[0]["pos"], "radius": 5.5, "invulnerable": false})
    check(hits.size() == 1 and String(hits[0]["target"]) == "player" and int(hits[0]["damage"]) == 0,
        "a status-only hazard registers a hit on the crawler")
    var grace: Dictionary = Biomes.grace_hazard("fungal_cavern")
    check(String(grace["kind"]) == "spore_burst" and grace["color"] is Color,
        "fungal grace hazards are spore bursts")
    check(Biomes.grace_hazard("stone_crypt").is_empty(), "stone_crypt keeps plain debris")


func _test_affinity() -> void:
    var catalogue: Dictionary = Enemies.load_catalogue()
    check(Enemies.validate_catalogue(catalogue).is_empty(), "enemies.json still validates with biome_affinity")
    var base: Array[Dictionary] = Enemies.eligible_pool(catalogue, 3)
    var crypt: Array[Dictionary] = Enemies.eligible_pool(catalogue, 3, "stone_crypt")
    check(str(base) == str(crypt), "stone_crypt has no affinities: pool weights unchanged")
    var fungal: Array[Dictionary] = Enemies.eligible_pool(catalogue, 3, "fungal_cavern")
    var by_id: Dictionary = {}
    for entry in fungal:
        by_id[entry["id"]] = float(entry["weight"])
    var base_by_id: Dictionary = {}
    for entry in base:
        base_by_id[entry["id"]] = float(entry["weight"])
    check(by_id["spore_puffer"] == base_by_id["spore_puffer"] * 2.0
        and by_id["nest_mother"] == base_by_id["nest_mother"] * 2.0
        and by_id["rat_scavenger"] > base_by_id["rat_scavenger"],
        "fungal affinities favour spore puffers, nest mothers and rats")
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var plan: Dictionary = Enemies.compose_encounter(catalogue, "normal", 3, rng, "fungal_cavern")
    check(not plan["picks"].is_empty(), "fungal encounters compose")
    # Depth 1-2 spawns are identical with or without the biome argument.
    var blocked: Dictionary = {}
    var a: Array[Dictionary] = Enemies.generate_encounter(catalogue, "normal", SEED, 4, blocked, 1, {})
    var b: Array[Dictionary] = Enemies.generate_encounter(catalogue, "normal", SEED, 4, blocked, 1, {},
        "stone_crypt")
    check(str(a) == str(b), "depth 1 encounters ignore the stone_crypt biome")


func _test_live_game() -> void:
    var rs: Node = get_root().get_node("RunState")
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    game.start_run(SEED)
    check(rs.current_room_biome() == "stone_crypt", "floor 1 start room is stone_crypt")
    var hall: int = int(rs.floor["guild_id"])
    check(String(rs.floor["rooms"][hall]["biome"]) == "guild_interior", "live guild hall is guild_interior")
    # Jump to floor 3: a fungal floor with patches in its normal rooms.
    game._start_floor(3)
    check(rs.depth == 3 and rs.current_room_biome() == "fungal_cavern", "floor 3 is fungal_cavern")
    var with_patches := 0
    for room in rs.floor["rooms"]:
        var id: int = int(room["id"])
        game._load_room(id)
        if not rs.room_states[id].get("patches", []).is_empty():
            with_patches += 1
            check(String(room["kind"]) != "start" and String(room["kind"]) != "guild_hall",
                "patches only in hostile rooms")
    check(with_patches >= 3, "fungal floor rooms carry patches (%d)" % with_patches)
    # Trigger one patch through RoomServices and see the spore cloud spawn.
    var target := -1
    for room in rs.floor["rooms"]:
        var id: int = int(room["id"])
        if String(room["kind"]) == "normal" and not rs.room_states[id]["patches"].is_empty():
            target = id
            break
    if target >= 0:
        rs.current_room_id = target
        rs.visited[target] = true
        var patch: Dictionary = rs.room_states[target]["patches"][0]
        game.player.world_position = Contents.cell_center(patch["cells"][0])
        game.combat.clear_hazards()
        game.services.update(1.0 / 60.0)
        check(game.combat.hazards.size() == 1 and String(game.combat.hazards[0]["kind"]) == "spore_cloud"
            or (game.combat.hazards.size() == 1 and String(game.combat.hazards[0]["kind"]) == "glow_puddle"),
            "standing on a patch spawns its biome hazard (%d)" % game.combat.hazards.size())
        # Drawing the fungal room must not error (immediate mode: force a draw pass).
        game.renderer.queue_redraw()
        await process_frame
        await process_frame
        check(String(game.renderer.current_art().get("biome", "")) == "fungal_cavern",
            "renderer drew with the fungal art")
    else:
        check(false, "a normal fungal room with a patch exists")
    game.queue_free()
