extends SceneTree
## Enemy roster, encounter budgets and the pure enemy state machine.
## Run: godot --headless --path game --script res://tests/enemies_test.gd
## Pure logic only: enemy_system.gd never references the autoloads, so it is
## preloaded. Live combat resolution is covered by enemy_combat_test.gd.
const Enemies = preload("res://scripts/enemy_system.gd")
const Generator = preload("res://scripts/floor_generator.gd")
const Contents = preload("res://scripts/room_contents.gd")
const SEEDS := 20
var failures := 0
var catalogue: Dictionary = {}


func _initialize() -> void:
    catalogue = Enemies.load_catalogue()
    _test_shipped_catalogue()
    _test_broken_records()
    _test_budgets_and_composition()
    _test_boss_and_elite_rooms()
    _test_spawn_constraints()
    _test_scaling_and_elites()
    _test_phases()
    _test_geometry()
    _test_state_machine()
    if failures == 0:
        print("PASS: enemy schema v2, roster, budgets, composition, spawns, scaling, phases, AI timing")
    quit(1 if failures > 0 else 0)


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ENEMIES: " + detail)


func has_problem(problems: Array[String], fragment: String) -> bool:
    for problem in problems:
        if problem.contains(fragment):
            return true
    return false


func _test_shipped_catalogue() -> void:
    var problems: Array[String] = Enemies.validate_catalogue(catalogue)
    check(problems.is_empty(), "shipped catalogue validates: %s" % [problems])
    check(int(catalogue["schema_version"]) == 2, "schema_version 2")
    var defs: Dictionary = catalogue["enemies"]
    var normal_roles: Dictionary = {}
    var normals := 0
    var bosses: Array = []
    for enemy_id in defs:
        var data: Dictionary = defs[enemy_id]
        if bool(data["boss"]):
            bosses.append(enemy_id)
            check(data["phases"].size() >= 2, "%s has at least two phases" % enemy_id)
        elif not bool(data.get("summon_only", false)):
            normals += 1
            normal_roles[data["role"]] = true
        for attack in data["attacks"]:
            check(float(attack["wind_up"]) >= 0.35 or int(data["band"]) > 1,
                "%s.%s band I wind-up >= 0.35 s" % [enemy_id, attack["id"]])
        var sheet: Dictionary = Enemies.sheet_info(catalogue, String(data["sprite"]))
        var texture: Texture2D = load(String(sheet["path"])) as Texture2D
        check(texture != null, "%s sprite sheet loads" % enemy_id)
        if texture != null:
            check(texture.get_size() == Vector2(sheet["frame"].x * 8, sheet["frame"].y),
                "%s sheet is 8 frames of the declared size" % enemy_id)
    check(normals >= 8, "at least 8 normal archetypes (got %d)" % normals)
    check(normal_roles.size() >= 6, "normal archetypes span 6+ roles: %s" % [normal_roles.keys()])
    check(bosses.size() == 2 and "armored_brute" in bosses and "sump_warden" in bosses,
        "two bosses: %s" % [bosses])
    check(defs["sump_warden"]["phases"].size() == 3, "sump warden has three phases")
    check(catalogue["elites"]["modifiers"].size() >= 2, "two elite modifiers")
    for rat in ["rat_scavenger", "spitting_rat", "hulking_rat"]:
        check(int(defs[rat]["band"]) == 1, rat + " is band I")
    check(Enemies.max_hit(defs["hulking_rat"], Enemies.attack_by_id(defs["hulking_rat"], "claw")) == 7,
        "hulking claw retuned to max 7")
    check(Enemies.max_hit(defs["armored_brute"], Enemies.attack_by_id(defs["armored_brute"], "maul")) == 10,
        "brute maul retuned to max 10")
    check("beast" in defs["rat_scavenger"]["tags"] and "armored" in defs["rubble_golem"]["tags"],
        "target_tag tags present")


func _test_broken_records() -> void:
    var broken: Dictionary = catalogue.duplicate(true)
    var rat: Dictionary = broken["enemies"]["rat_scavenger"]
    rat["behavior"]["mode"] = "teleport"
    rat["abilities"] = ["laser_eyes"]
    rat["attacks"][0]["wind_up"] = 0.1
    rat["attacks"][0]["telegraph"] = "line"
    rat["role"] = "sniper"
    rat["phases"] = [{"below": 1.0, "attacks": ["bite"]}]
    rat["resistances"] = {"cold": 0.5}
    rat["attacks"][0]["damage_bonus"] = 9
    broken["enemies"]["spitting_rat"]["attacks"][0]["projectile_speed"] = 400
    broken["enemies"]["spitting_rat"]["attacks"][0]["type"] = "beam"
    broken["enemies"]["nest_mother"]["attacks"][0]["summon"]["id"] = "rat_scavenger"
    broken["enemies"]["sump_warden"]["phases"][1]["attacks"].append("tsunami")
    broken["enemies"]["spore_puffer"].erase("threat")
    broken["enemies"]["lobber"]["abilities"] = []
    var problems: Array[String] = Enemies.validate_catalogue(broken)
    check(has_problem(problems, "rat_scavenger: unknown behavior mode 'teleport'"),
        "unknown behaviour id fails with a clear message: %s" % [problems])
    check(has_problem(problems, "unknown ability 'laser_eyes'"), "unknown ability rejected")
    check(has_problem(problems, "rat_scavenger.bite: wind_up 0.10 s is below the band minimum"),
        "wind-up below band minimum rejected")
    check(has_problem(problems, "telegraph 'line' is not valid for a melee attack"), "telegraph/type mismatch")
    check(has_problem(problems, "unknown role 'sniper'"), "unknown role rejected")
    check(has_problem(problems, "only bosses have phases[]"), "phases on a non-boss rejected")
    check(has_problem(problems, "unknown resistance tag 'cold'"), "unknown resistance tag rejected")
    check(has_problem(problems, "max non-crit hit 13 exceeds the band cap 7"), "damage guardrail")
    check(has_problem(problems, "unknown attack type 'beam'"), "unknown attack type rejected")
    check(has_problem(problems, "must be a summon_only enemy"), "summon id must be a summon")
    check(has_problem(problems, "uses unknown attack 'tsunami'"), "phase attack ids checked")
    check(has_problem(problems, "spore_puffer: missing threat"), "missing field reported")
    check(has_problem(problems, "lobber.firebomb: puddle attacks need the 'puddle' ability"),
        "attack type requires its ability")
    var old: Dictionary = catalogue.duplicate(true)
    old["schema_version"] = 1
    check(has_problem(Enemies.validate_catalogue(old), "schema_version must be 2"), "schema version checked")


func _plan_for(seed_value: int, room_id: int, kind: String, depth: int) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value * 73 + room_id * 10211 + 41
    return Enemies.compose_encounter(catalogue, kind, depth, rng)


func _test_budgets_and_composition() -> void:
    var defs: Dictionary = catalogue["enemies"]
    var cfg: Dictionary = Enemies.settings(catalogue)
    check(Enemies.threat_budget(catalogue, "normal", 1, "standard") == 8, "depth 1 standard budget 8")
    check(Enemies.threat_budget(catalogue, "normal", 6, "heavy") == 30, "depth 6 heavy budget 30")
    check(Enemies.threat_budget(catalogue, "boss", 1) == 4, "depth 1 boss escort budget 4")
    check(Enemies.threat_budget(catalogue, "start", 3) == 0, "start rooms get no budget")
    var previous_mean := -1.0
    for depth in range(1, 7):
        var band: int = Enemies.band_for_depth(catalogue, depth)
        var caps: Dictionary = cfg["role_caps"][str(band)]
        var max_count: int = int(cfg["max_enemies"][str(band)])
        var total := 0
        var rooms := 0
        for seed_index in range(SEEDS):
            for room_id in range(1, 9):
                var plan: Dictionary = _plan_for(9000 + seed_index * 31, room_id, "normal", depth)
                var label := "depth %d seed %d room %d" % [depth, seed_index, room_id]
                var budget: int = int(plan["budget"])
                var spent: int = int(plan["spent"])
                total += spent
                rooms += 1
                check(absf(float(spent - budget)) <= float(budget) * 0.1 + 0.001,
                    "%s: spent %d within 10%% of budget %d" % [label, spent, budget])
                var picks: Array = plan["picks"]
                var sum := 0
                var roles: Dictionary = {}
                var ids: Dictionary = {}
                for pick in picks:
                    var data: Dictionary = defs[pick["id"]]
                    sum += int(pick["threat"])
                    roles[pick["role"]] = int(roles.get(pick["role"], 0)) + 1
                    ids[pick["id"]] = int(ids.get(pick["id"], 0)) + 1
                    check(depth >= int(data["min_depth"]) and depth <= int(data["max_depth"]),
                        "%s: %s eligible at this depth" % [label, pick["id"]])
                    check(not bool(data["boss"]) and not bool(data.get("summon_only", false)),
                        "%s: no bosses or summons in the pool" % label)
                check(sum == spent, "%s: spent equals the picks' threat" % label)
                check(picks.size() >= 2 and picks.size() <= max_count,
                    "%s: count %d within 2..%d" % [label, picks.size(), max_count])
                for role in caps:
                    check(int(roles.get(role, 0)) <= int(caps[role]), "%s: %s cap" % [label, role])
                for enemy_id in ids:
                    check(int(ids[enemy_id]) <= 3, "%s: repetition cap" % label)
                if band == 1:
                    check(roles.has("chaser"), "%s: band I room has a chaser" % label)
                elif picks.size() >= 3:
                    check(roles.has("chaser") or roles.has("charger"), "%s: pressure role" % label)
                if band <= 2:
                    check(int(roles.get("ranged", 0)) < picks.size(), "%s: not all ranged" % label)
                if roles.has("support"):
                    check(picks.size() - int(roles["support"]) >= 2, "%s: support has company" % label)
                if depth < 3:
                    check(not roles.has("summoner") and not roles.has("charger"),
                        "%s: no band II roles before depth 3" % label)
        var mean: float = float(total) / float(rooms)
        check(mean > previous_mean, "mean threat rises with depth (%d: %.2f)" % [depth, mean])
        previous_mean = mean
    var first: Dictionary = _plan_for(424242, 5, "normal", 4)
    var second: Dictionary = _plan_for(424242, 5, "normal", 4)
    check(str(first) == str(second), "composition is deterministic")


func _test_boss_and_elite_rooms() -> void:
    var defs: Dictionary = catalogue["enemies"]
    var seen_options: Dictionary = {}
    for depth in range(1, 7):
        for seed_index in range(SEEDS):
            var plan: Dictionary = _plan_for(700 + seed_index, 3, "boss", depth)
            var picks: Array = plan["picks"]
            var bosses := 0
            for pick in picks:
                if bool(pick.get("boss", false)):
                    bosses += 1
                elif Enemies.band_for_depth(catalogue, depth) == 1:
                    check(not ["summoner", "support"].has(String(pick["role"])), "band I escort roles")
            check(bosses == 1 and bool(picks[0].get("boss", false)), "exactly one boss, placed first")
            check(int(plan["spent"]) <= int(plan["budget"]) + 2, "escort within budget + 2")
            var boss_id: String = String(picks[0]["id"])
            seen_options["%s%s" % [boss_id, picks[0]["elite"]]] = true
            if depth <= 2:
                check(boss_id == "armored_brute", "depths 1-2 boss is the brute")
            elif depth <= 4:
                check(boss_id == "sump_warden", "depths 3-4 boss is the sump warden")
            check(bool(defs[boss_id]["boss"]), "boss pool entries are boss-flagged")
    check(seen_options.has("sump_warden") and seen_options.has("armored_brutebulwark"),
        "depth 5-6 pool yields both the warden and the bulwark brute: %s" % [seen_options.keys()])
    var elites := 0
    for seed_index in range(SEEDS):
        var plan: Dictionary = _plan_for(300 + seed_index, 7, "elite", 3)
        var count := 0
        for pick in plan["picks"]:
            if String(pick["elite"]) != "":
                count += 1
                check(catalogue["elites"]["modifiers"].has(String(pick["elite"])), "known modifier")
        check(count == 1, "elite room has exactly one elite")
        elites += count
        var normal: Dictionary = _plan_for(300 + seed_index, 7, "normal", 2)
        for pick in normal["picks"]:
            check(String(pick["elite"]) == "", "no elites in band I normal rooms")
    check(elites == SEEDS, "elite rooms always field an elite")


func _test_spawn_constraints() -> void:
    var spawn: Dictionary = Enemies.settings(catalogue)["spawn"]
    for seed_index in range(4):
        var seed_value: int = 1300 + seed_index
        var generated: Dictionary = Generator.generate(seed_value, 22)
        for room in generated["rooms"]:
            var kind: String = String(room["kind"])
            if kind != "normal" and kind != "boss":
                continue
            for depth in [1, 3, 5]:
                var id: int = int(room["id"])
                var blocked: Dictionary = Contents.generate(seed_value, id, room["neighbors"], kind,
                    Enemies.obstacle_density(catalogue, kind, 38))["blocked"]
                var foes: Array[Dictionary] = Enemies.generate_encounter(catalogue, kind, seed_value,
                    id, blocked, depth, room["neighbors"])
                var again: Array[Dictionary] = Enemies.generate_encounter(catalogue, kind, seed_value,
                    id, blocked, depth, room["neighbors"])
                check(str(foes) == str(again), "same seed/depth/room -> same encounter")
                var plan: Dictionary = _plan_for(seed_value, id, kind, depth)
                check(foes.size() == plan["picks"].size(), "every planned enemy is placed")
                var boss_pos := Vector2.INF
                for foe in foes:
                    if bool(foe["boss"]):
                        boss_pos = foe["pos"]
                        check(Vector2(foe["pos"]) == Enemies.MID, "boss spawns at the room midpoint")
                for i in range(foes.size()):
                    var foe: Dictionary = foes[i]
                    var point: Vector2 = foe["pos"]
                    var radius: float = float(foe["radius"])
                    check(Contents.can_occupy(point, radius, blocked), "spawn fits its radius")
                    check(int(foe["dormant"]) == 0 and float(foe["attack_cooldown"]) >= 0.4
                        and float(foe["attack_cooldown"]) <= 1.0, "first cooldown 0.4-1.0 s")
                    if bool(foe["boss"]):
                        continue
                    var keep_out: float = Enemies.portal_distance(catalogue,
                        catalogue["enemies"][foe["definition"]])
                    for direction in room["neighbors"]:
                        check(point.distance_to(Enemies.PORTAL_CENTERS[direction]) >= keep_out,
                            "%s spawns >= %d px from portal %s" % [foe["definition"], keep_out, direction])
                        var reach: Dictionary = Enemies.flood(blocked, Contents.portal_cells(direction), 0.0)
                        check(reach.has(Contents.cell_of(point)), "spawn reachable from portal " + direction)
                    if boss_pos != Vector2.INF:
                        check(point.distance_to(boss_pos) >= float(spawn["escort_boss_gap"]),
                            "escort keeps its distance from the boss")
                    for j in range(i):
                        check(point.distance_to(foes[j]["pos"]) >= radius + float(foes[j]["radius"])
                            + float(spawn["gap"]) - 0.01, "spawns keep the S2 gap")


func _test_scaling_and_elites() -> void:
    var scavenger: Dictionary = Enemies.make_instance(catalogue, "rat_scavenger", Vector2.ZERO, 3)
    check(int(scavenger["veteran"]) == 2 and int(scavenger["max_hp"]) == 11, "veteran HP x1.25^2")
    check(int(scavenger["xp"]) == 56 and int(scavenger["threat"]) == 4, "veteran XP x1.5^2, threat +2")
    check(int(scavenger["attack_bonus_add"]) == 2 and int(scavenger["damage_bonus_add"]) == 2,
        "veteran attack and damage bonus")
    var bite: Dictionary = Enemies.attack_by_id(catalogue["enemies"]["rat_scavenger"], "bite")
    check(is_equal_approx(Enemies.wind_up_of(scavenger, bite), 0.2835), "veteran wind-up x0.9^2")
    var golem: Dictionary = Enemies.make_instance(catalogue, "rubble_golem", Vector2.ZERO, 3, "bulwark")
    check(int(golem["max_hp"]) == 105, "bulwark elite HP 40 x1.75 x1.5")
    check(int(golem["xp"]) == 375 and int(golem["threat"]) == 12, "elite XP x2.5 and threat x2")
    check(int(golem["shield"]) == 8 and is_equal_approx(float(golem["knockback_resist"]), 1.0),
        "bulwark shield 8 and knockback resist +0.25 (capped at 1)")
    check(String(golem["name"]) == "Bulwark Rubble Golem" and Color.html_is_valid(String(golem["tint"])),
        "elite name prefix and tint")
    check(int(golem["ac"]) == 15 and is_equal_approx(float(golem["damage_mult"]), 1.15),
        "bulwark AC +1, elite damage x1.15")
    var volatile: Dictionary = Enemies.make_instance(catalogue, "shellback_charger", Vector2.ZERO, 3, "volatile")
    check("volatile" in volatile["modifiers"] and "elite" in volatile["tags"], "volatile modifier tagged")
    check(volatile["name"] == "Volatile Shellback Charger" and float(volatile["speed"]) > 32.0,
        "volatile prefix and speed")
    var brute: Dictionary = Enemies.make_instance(catalogue, "armored_brute", Enemies.MID, 3, "bulwark")
    check(int(brute["max_hp"]) == 120 and int(brute["shield"]) == 8 and bool(brute["boss"]),
        "boss elites keep their band HP and gain the modifier's shield")
    check(int(Enemies.make_instance(catalogue, "sump_warden", Enemies.MID, 2)["max_hp"]) == 90
        and int(Enemies.make_instance(catalogue, "sump_warden", Enemies.MID, 3)["max_hp"]) == 140,
        "sump warden HP 90 / 140 by band")
    var golem_plain: Dictionary = Enemies.make_instance(catalogue, "rubble_golem", Vector2(100, 100), 3)
    check(is_equal_approx(Enemies.apply_knockback(golem_plain, Vector2.RIGHT, 40.0, {}), 10.0),
        "knockback scaled by knockback_resist 0.75")
    var warden: Dictionary = Enemies.make_instance(catalogue, "sump_warden", Enemies.MID, 2)
    check(Enemies.apply_knockback(warden, Vector2.RIGHT, 40.0, {}) == 0.0, "warden is knockback-immune")


func _test_phases() -> void:
    var brute: Dictionary = catalogue["enemies"]["armored_brute"]
    check(Enemies.phase_index(brute, 42, 42) == 0 and Enemies.phase_index(brute, 21, 42) == 0,
        "brute phase 1 down to 50 %")
    check(Enemies.phase_index(brute, 20, 42) == 1, "brute phase 2 below 50 %")
    var warden: Dictionary = catalogue["enemies"]["sump_warden"]
    check(Enemies.phase_index(warden, 54, 90) == 0 and Enemies.phase_index(warden, 53, 90) == 1,
        "warden phase 2 below 60 %")
    check(Enemies.phase_index(warden, 22, 90) == 2 and Enemies.phase_index(warden, 23, 90) == 1,
        "warden phase 3 below 25 %")
    var foe: Dictionary = Enemies.make_instance(catalogue, "sump_warden", Enemies.MID, 2)
    check(Enemies.active_attack_ids(foe, warden) == ["tide_spray", "flood_pulse"], "phase 1 attack set")
    Enemies.enter_phase(foe, 2)
    check(Enemies.active_attack_ids(foe, warden).has("tide_spray_wide"), "phase 3 attack set")
    check(float(foe["invulnerable"]) == 1.0 and foe["state"] == "idle", "phase roar")
    foe["hp"] = 20
    check(Enemies.is_enraged(foe, warden) and Enemies.cooldown_mult(foe, warden) == 0.8,
        "warden enrage below 25 %: cooldowns x0.8")


func _test_geometry() -> void:
    var defs: Dictionary = catalogue["enemies"]
    # twin_shot: a stationary crawler at the preferred range is in the path of
    # the aimed shot; a moving one is led by 0.25 rad.
    var spitter: Dictionary = Enemies.make_instance(catalogue, "spitting_rat", Vector2(100, 200), 1)
    spitter["aim"] = Vector2.RIGHT
    var spit: Dictionary = Enemies.attack_by_id(defs["spitting_rat"], "spit")
    var still: Array[Vector2] = Enemies.volley_directions(spitter, defs["spitting_rat"], spit, Vector2.ZERO)
    check(still.size() == 2 and still[0] == Vector2.RIGHT, "twin_shot: one shot straight at the crawler")
    var target := Vector2(205, 200)
    var hit := false
    for direction in still:
        var shot: Vector2 = Vector2(100, 200) + direction * 10.0
        for _i in range(200):
            shot += direction * 117.5 / 60.0
            hit = hit or shot.distance_to(target) < 5.5 + 3.0
    check(hit, "a stationary crawler at 105 px is hit")
    var moving: Array[Vector2] = Enemies.volley_directions(spitter, defs["spitting_rat"], spit,
        Vector2(0, 105))
    check(is_equal_approx(moving[1].angle(), 0.25), "lead shot leans 0.25 rad toward the motion")
    var spray: Array[Vector2] = Enemies.volley_directions(spitter, defs["sump_warden"],
        Enemies.attack_by_id(defs["sump_warden"], "tide_spray"), Vector2.ZERO)
    check(spray.size() == 5 and is_equal_approx(spray[0].angle_to(spray[4]), deg_to_rad(60.0)),
        "tide spray fans 5 shots over 60 degrees")
    var gap: float = 100.0 * deg_to_rad(15.0) - 2.0 * 2.0
    check(gap >= 14.0, "tide spray gaps are dodgeable at 100 px")
    var rat: Dictionary = Enemies.make_instance(catalogue, "rat_scavenger", Vector2(100, 100), 1)
    rat["aim"] = Vector2.RIGHT
    var bite: Dictionary = Enemies.attack_by_id(defs["rat_scavenger"], "bite")
    check(Enemies.melee_hits(rat, bite, Vector2(118, 100), 5.5), "bite hits in front at reach")
    check(not Enemies.melee_hits(rat, bite, Vector2(130, 100), 5.5), "bite whiffs past reach")
    check(not Enemies.melee_hits(rat, bite, Vector2(85, 100), 5.5), "bite whiffs behind")


func _world(player_pos: Vector2, allies: Array) -> Dictionary:
    return {"player_pos": player_pos, "player_velocity": Vector2.ZERO, "blocked": {}, "allies": allies}


func _test_state_machine() -> void:
    var defs: Dictionary = catalogue["enemies"]
    var rat: Dictionary = Enemies.make_instance(catalogue, "rat_scavenger", Vector2(100, 100), 1, "", "t_0")
    Enemies.on_room_entered(rat, 0.6)
    var player := Vector2(112, 100)
    var allies: Array = [rat]
    var elapsed := 0.0
    var first_strike := -1.0
    var wind_up_start := -1.0
    for _frame in range(120):
        var actions: Array[Dictionary] = Enemies.step(rat, defs["rat_scavenger"], 1.0 / 60.0,
            _world(player, allies))
        elapsed += 1.0 / 60.0
        if elapsed < 0.6 - 0.001:
            check(rat["state"] == "idle" and rat["pos"] == Vector2(100, 100) and actions.is_empty(),
                "dormant for 0.6 s after room entry")
        if wind_up_start < 0.0 and rat["state"] == "winding_up":
            wind_up_start = elapsed
        for action in actions:
            if action["type"] == "strike" and first_strike < 0.0:
                first_strike = elapsed
                check(bool(action["hit"]), "bite connects with a crawler that stays in reach")
    check(wind_up_start >= 0.6 - 0.001, "no wind-up during dormancy (started %.3f)" % wind_up_start)
    check(first_strike > 0.0 and first_strike - wind_up_start >= 0.35 - 0.02,
        "strike resolves only after the 0.35 s wind-up (%.3f -> %.3f)" % [wind_up_start, first_strike])
    # Ranged enemies check line of sight before winding up.
    var spitter: Dictionary = Enemies.make_instance(catalogue, "spitting_rat", Vector2(40, 200), 1, "", "t_1")
    var wall: Dictionary = {Vector2i(5, 12): true, Vector2i(5, 11): true, Vector2i(5, 13): true}
    var world: Dictionary = _world(Vector2(150, 200), [spitter])
    world["blocked"] = wall
    check(Enemies.choose_attack(spitter, defs["spitting_rat"], world).is_empty(),
        "no ranged wind-up without line of sight")
    world["blocked"] = {}
    check(not Enemies.choose_attack(spitter, defs["spitting_rat"], world).is_empty(),
        "ranged wind-up with a clear line")
    # Charger: a dash into a wall stuns.
    var charger: Dictionary = Enemies.make_instance(catalogue, "shellback_charger", Vector2(360, 192), 3, "", "t_2")
    charger["state"] = "dashing"
    charger["attack"] = "ram"
    charger["aim"] = Vector2.RIGHT
    charger["dash_left"] = 120.0
    var stunned := false
    for _frame in range(30):
        for action in Enemies.step(charger, defs["shellback_charger"], 1.0 / 60.0, _world(Vector2(100, 100), [charger])):
            stunned = stunned or action["type"] == "wall_stun"
    check(stunned and charger["state"] == "stunned", "charger stuns itself on a wall")
    # Support flees a close crawler and only casts with allies in range.
    var acolyte: Dictionary = Enemies.make_instance(catalogue, "bell_acolyte", Vector2(200, 200), 3, "", "t_3")
    var start: Vector2 = acolyte["pos"]
    Enemies.advance(acolyte, defs["bell_acolyte"], 0.5, Vector2(230, 200), {}, _world(Vector2(230, 200), [acolyte]))
    check(Vector2(acolyte["pos"]).x < start.x, "support flees the crawler")
    check(Enemies.choose_attack(acolyte, defs["bell_acolyte"], _world(Vector2(330, 200), [acolyte])).is_empty(),
        "support does not cast alone")
    var buddy: Dictionary = Enemies.make_instance(catalogue, "rat_scavenger", Vector2(190, 210), 3, "", "t_4")
    check(Enemies.choose_attack(acolyte, defs["bell_acolyte"], _world(Vector2(330, 200), [acolyte, buddy]))["id"]
        == "ward_peal", "support wards a nearby ally")
