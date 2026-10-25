extends SceneTree
## Run: godot --headless --path game --script res://tests/content_test.gd
## Covers the Wave 1B content layer: schema validation, starter-pool counts, effect
## ordering/stacking/expiry/conditions, skill prerequisite cycles and loot determinism.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const Loot = preload("res://scripts/content/loot_rules.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
    run_tests()
    if failures == 0:
        print("PASS (%d checks): content schema, starter pool, effect ordering, stacking, statuses, conditions, skills and loot" % checks)
    quit(1 if failures > 0 else 0)

func check(condition: bool, detail: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("FAIL CONTENT: " + detail)

func has_problem(problems: Array[String], fragment: String) -> bool:
    for problem in problems:
        if fragment in problem:
            return true
    return false

func run_tests() -> void:
    var db: Dictionary = ContentDB.load_all()
    var problems: Array[String] = ContentDB.validate(db)
    for problem in problems:
        print("  content problem: ", problem)
    check(problems.is_empty(), "shipped content validates (%d problems)" % problems.size())
    test_counts(db)
    test_lookups(db)
    test_broken_records(db)
    test_attack_profiles(db)
    test_modifier_ordering(db)
    test_collect_modifiers(db)
    test_stacking(db)
    test_status_ticks(db)
    test_conditions()
    test_skill_graph(db)
    test_loot(db)

func test_counts(db: Dictionary) -> void:
    var melee := 0
    var ranged := 0
    for entry in db["weapons"]:
        if entry["slot"] == "melee":
            melee += 1
        else:
            ranged += 1
    var kinds: Dictionary = {"active": 0, "passive": 0, "consumable": 0}
    for entry in db["items"]:
        kinds[entry["kind"]] = int(kinds[entry["kind"]]) + 1
    var skill_kinds: Dictionary = {"active": 0, "passive": 0}
    for entry in db["skills"]:
        skill_kinds[entry["kind"]] = int(skill_kinds[entry["kind"]]) + 1
    check(melee >= 3 and ranged >= 3, "starter pool has >= 3 melee and >= 3 ranged weapons")
    check(int(kinds["active"]) >= 3, "at least 3 active items")
    check(int(kinds["passive"]) >= 6, "at least 6 passive items")
    check(int(kinds["consumable"]) >= 4, "at least 4 consumables")
    check(db["skills"].size() >= 6 and int(skill_kinds["active"]) >= 1 and int(skill_kinds["passive"]) >= 1,
        "at least 6 skills spanning active and passive")
    var required_statuses := ["burning", "poisoned", "slowed", "stunned", "bleeding", "shielded", "hasted"]
    for status_id in required_statuses:
        check(not ContentDB.status(status_id, db).is_empty(), "status defined: " + status_id)
    for kind in ["weapons", "items", "skills"]:
        for entry in db[kind]:
            check(String(entry.get("adaptation_type", "")) != "canon",
                "%s is original/adapted, not canon" % entry["id"])
    var patterns: Dictionary = {}
    for entry in db["weapons"]:
        patterns[entry["attack_pattern"]] = true
    for pattern in ["arc", "thrust", "spin", "single", "spread", "burst"]:
        check(patterns.has(pattern), "a starter weapon uses pattern " + pattern)
    print("  content counts: %d effects, %d statuses, %d weapons (%d melee / %d ranged), %d items (%d active / %d passive / %d consumable), %d skills, %d loot tables" % [
        db["effects"].size(), db["statuses"].size(), db["weapons"].size(), melee, ranged,
        db["items"].size(), kinds["active"], kinds["passive"], kinds["consumable"],
        db["skills"].size(), db["loot"]["tables"].size()])

func test_lookups(db: Dictionary) -> void:
    check(ContentDB.weapon("wpn_crowbar", db)["slot"] == "melee", "weapon lookup")
    check(ContentDB.item("itm_bandage_roll", db)["kind"] == "consumable", "item lookup")
    check(ContentDB.skill("skl_iron_gut", db)["max_rank"] == 3, "skill lookup")
    check(ContentDB.effect("fx_heal_6", db)["operation"] == "heal", "effect lookup")
    check(ContentDB.weapon("wpn_does_not_exist", db).is_empty(), "unknown id returns empty")
    check(ContentDB.weapon("wpn_nail_pistol")["slot"] == "ranged", "lookup without db uses cache")
    var entry: Dictionary = ContentDB.loadout_entry("skl_iron_gut", 3, 1, db)
    check(entry["effects"].has("fx_iron_gut_3") and entry["effects"].has("fx_level_up_heal_5"),
        "skill loadout entry uses the requested rank's effects")
    check(ContentDB.loadout(["itm_hazard_vest", "nope", {"id": "skl_brawler", "rank": 2}], db).size() == 2,
        "loadout skips unknown ids")

func test_broken_records(db: Dictionary) -> void:
    var broken: Dictionary = db.duplicate(true)
    broken["weapons"].append({
        "id": "wpn_broken_spoon", "name": "Broken Spoon", "slot": "melee", "attack_pattern": "spread",
        "damage_die": 0, "damage_bonus": 0, "ability": "CHA", "reach": 20, "arc_degrees": 90,
        "cooldown": 0.4, "knockback": 0, "pierce": 0, "tags": [], "rarity": "mythic",
        "min_depth": 1, "effects": ["fx_missing_effect"], "sprite": "x", "description": "Bent.",
        "adaptation_type": "original"})
    var found: Array[String] = ContentDB.validate(broken)
    check(not found.is_empty(), "broken weapon fails validation")
    check(has_problem(found, "wpn_broken_spoon: damage_die=0 outside"), "die must be > 0 message")
    check(has_problem(found, "wpn_broken_spoon: unknown effect 'fx_missing_effect'"), "missing effect message")
    check(has_problem(found, "wpn_broken_spoon: invalid rarity 'mythic'"), "unknown rarity message")
    check(has_problem(found, "wpn_broken_spoon: invalid ability 'CHA'"), "invalid ability message")
    check(has_problem(found, "invalid attack_pattern for melee 'spread'"), "pattern must suit slot")

    var duplicated: Dictionary = db.duplicate(true)
    duplicated["items"].append(duplicated["items"][0].duplicate(true))
    check(has_problem(ContentDB.validate(duplicated), "duplicate id in items"), "duplicate ids rejected")

    var bad_effect: Dictionary = db.duplicate(true)
    bad_effect["effects"].append({"id": "fx_bad", "trigger": "on_sneeze", "target": "self",
        "operation": "apply_status", "status": "frozen", "magnitude": 1, "duration": 0,
        "stacking": "stack_count:0", "condition": {"luck": 3}, "description": "Bad."})
    var effect_problems: Array[String] = ContentDB.validate(bad_effect)
    check(has_problem(effect_problems, "fx_bad: invalid trigger 'on_sneeze'"), "unknown trigger rejected")
    check(has_problem(effect_problems, "fx_bad: unknown status 'frozen'"), "unknown status rejected")
    check(has_problem(effect_problems, "fx_bad: invalid stacking"), "stack_count:0 rejected")
    check(has_problem(effect_problems, "fx_bad: unknown condition key 'luck'"), "unknown condition rejected")
    check(has_problem(effect_problems, "fx_bad: apply_status needs duration > 0"), "status duration required")

    var bad_prefix: Dictionary = db.duplicate(true)
    bad_prefix["skills"][0]["id"] = "IronGut"
    var prefix_problems: Array[String] = ContentDB.validate(bad_prefix)
    check(has_problem(prefix_problems, "IronGut: id must be snake_case"), "snake_case enforced")
    check(has_problem(prefix_problems, "must start with 'skl_'"), "id prefix enforced")

    var bad_item: Dictionary = db.duplicate(true)
    for entry in bad_item["items"]:
        if entry["id"] == "itm_hazard_vest":
            entry["effects"] = ["fx_heal_6"]
        if entry["id"] == "itm_floor_stomp":
            entry["cooldown"] = 0
    var item_problems: Array[String] = ContentDB.validate(bad_item)
    check(has_problem(item_problems, "itm_hazard_vest: passive items cannot have on_use"), "passive/on_use rule")
    check(has_problem(item_problems, "itm_floor_stomp: cooldown=0 outside"), "actives need a cooldown")

    var bad_loot: Dictionary = db.duplicate(true)
    bad_loot["loot"]["tables"].erase("boss_kill")
    bad_loot["loot"]["tables"]["treasure_room"]["exclude"].append("itm_ghost")
    var loot_problems: Array[String] = ContentDB.validate(bad_loot)
    check(has_problem(loot_problems, "missing table 'boss_kill'"), "required loot contexts")
    check(has_problem(loot_problems, "exclude names unknown id 'itm_ghost'"), "exclude ids must exist")

func test_attack_profiles(db: Dictionary) -> void:
    var scores: Dictionary = RPG.player_base_scores()
    var pistol: Dictionary = ContentDB.attack_profile(ContentDB.weapon("wpn_nail_pistol", db), scores, 1)
    check(pistol["die"] == 6 and is_equal_approx(float(pistol["cooldown"]), 0.28), "pistol matches prototype shot")
    check(is_equal_approx(float(pistol["projectile_speed"]), 215.0) and is_equal_approx(float(pistol["ttl"]), 2.0),
        "pistol speed/lifetime match prototype")
    check(pistol["attack_bonus"] == RPG.attack_bonus(scores, "DEX", 1)
        and pistol["damage_bonus"] == RPG.modifier(14), "ranged profile uses rpg_rules")
    var crowbar: Dictionary = ContentDB.attack_profile(ContentDB.weapon("wpn_crowbar", db), scores, 1)
    check(is_equal_approx(float(crowbar["reach"]), 32.0) and is_equal_approx(float(crowbar["cooldown"]), 0.5),
        "crowbar matches prototype swing")
    check(absf(float(crowbar["dot_threshold"]) - 0.45) < 0.01, "127 degree arc ~ 0.45 dot threshold")
    var maul: Dictionary = ContentDB.weapon("wpn_demolition_maul", db)
    var buffed: Dictionary = ContentDB.attack_profile(maul, scores, 1,
        [ContentDB.effect("fx_brawler_dmg_2", db), ContentDB.effect("fx_melee_cooldown_x090", db),
         ContentDB.effect("fx_damage_bonus_plus_1", db)])
    check(buffed["damage_bonus"] == RPG.modifier(14) + 1 + 2 + 1, "maul damage = STR mod + weapon + modifiers")
    check(is_equal_approx(float(buffed["cooldown"]), 0.85 * 0.9), "melee cooldown multiplier applies")
    check(ContentDB.arc_dot_threshold(360.0) < -1.0, "spin weapons hit every direction")
    for entry in db["weapons"]:
        check(float(entry["cooldown"]) >= 0.15 and float(entry["cooldown"]) <= 1.2,
            "%s cooldown near prototype band" % entry["id"])
        if entry["slot"] == "melee":
            check(float(entry["reach"]) >= 24.0 and float(entry["reach"]) <= 48.0,
                "%s reach near 32px baseline" % entry["id"])

func test_modifier_ordering(_db: Dictionary) -> void:
    var base := {"move_speed": 100.0, "max_hp": 12, "ac": 12}
    var modifiers: Array = [
        {"operation": "multiply", "stat": "move_speed", "magnitude": 2.0},
        {"operation": "add", "stat": "move_speed", "magnitude": 10.0},
        {"operation": "multiply", "stat": "max_hp", "magnitude": 1.5},
        {"operation": "add", "stat": "max_hp", "magnitude": 4.0},
        {"operation": "set", "stat": "ac", "magnitude": 18.0},
        {"operation": "add", "stat": "ac", "magnitude": 5.0},
        {"operation": "spawn_projectile_modifier", "stat": "pierce", "magnitude": 1.0},
        {"operation": "set", "status": "poisoned", "magnitude": 0.0},
    ]
    var out: Dictionary = Resolver.apply_stat_modifiers(base, modifiers)
    check(is_equal_approx(float(out["move_speed"]), 220.0), "add happens before multiply ((100+10)*2)")
    check(out["max_hp"] == 24 and out["max_hp"] is int, "int stats stay int ((12+4)*1.5)")
    check(out["ac"] == 18, "set happens last and overrides add")
    check(is_equal_approx(float(out["pierce"]), 1.0), "projectile modifier adds to missing stat from 0")
    check(base["move_speed"] == 100.0, "base stats are not mutated")
    var two_sets: Dictionary = Resolver.apply_stat_modifiers({"ac": 10}, [
        {"operation": "set", "stat": "ac", "magnitude": 14}, {"operation": "set", "stat": "ac", "magnitude": 16}])
    check(two_sets["ac"] == 16, "last set wins")

func test_collect_modifiers(db: Dictionary) -> void:
    var loadout: Array[Dictionary] = ContentDB.loadout([
        "itm_hazard_vest", {"id": "itm_hazard_vest"}, {"id": "itm_hazard_vest"},
        "itm_last_gasp_adrenaline", "itm_spite_battery", "wpn_box_cutter"], db)
    var context := {"db": db, "hp": 10, "max_hp": 12}
    var passive: Array[Dictionary] = Resolver.collect_modifiers(loadout, "passive", context)
    var ac_count := 0
    var hp_count := 0
    for modifier in passive:
        if modifier["effect_id"] == "fx_ac_plus_1":
            ac_count += 1
        if modifier["effect_id"] == "fx_max_hp_plus_4":
            hp_count += 1
        check(modifier["effect_id"] != "fx_low_hp_melee_haste", "low-HP passive inactive at 83% HP")
    check(ac_count == 2, "stack_count:2 caps three vests to two AC bonuses")
    check(hp_count == 3, "stack_count:3 allows three HP bonuses")
    var stats: Dictionary = Resolver.apply_stat_modifiers({"ac": 12, "max_hp": 12}, passive)
    check(stats["ac"] == 14 and stats["max_hp"] == 24, "collected passives apply to stats")
    var low: Array[Dictionary] = Resolver.collect_modifiers(loadout, "passive",
        {"db": db, "hp": 3, "max_hp": 12})
    var low_ids: Array = low.map(func(m): return m["effect_id"])
    check(low_ids.has("fx_low_hp_melee_haste") and low_ids.has("fx_low_hp_ranged_haste"),
        "hp_below_pct passives activate at 25% HP")

    var hurt: Array[Dictionary] = Resolver.collect_modifiers(loadout, "on_damage_taken", {"db": db, "now": 10.0})
    check(hurt.size() == 1 and hurt[0]["cooldown_key"] == "itm_spite_battery:fx_spite_discharge",
        "on_damage_taken trigger fires spite battery")
    var cooldowns: Dictionary = Resolver.start_cooldowns({}, hurt, 10.0)
    check(Resolver.collect_modifiers(loadout, "on_damage_taken",
        {"db": db, "now": 11.0, "cooldowns": cooldowns}).is_empty(), "internal cooldown blocks re-trigger")
    check(Resolver.collect_modifiers(loadout, "on_damage_taken",
        {"db": db, "now": 12.0, "cooldowns": cooldowns}).size() == 1, "cooldown expires")

    var rolls := []
    for attempt in range(2):
        var rng := RandomNumberGenerator.new()
        rng.seed = 777
        var hits := 0
        for _i in range(200):
            hits += Resolver.collect_modifiers(loadout, "on_hit", {"db": db, "rng": rng, "slot": "melee"}).size()
        rolls.append(hits)
    check(rolls[0] == rolls[1], "seeded chance rolls are deterministic")
    check(int(rolls[0]) > 25 and int(rolls[0]) < 80, "25%% bleed chance fires about a quarter of the time (%d/200)" % rolls[0])
    check(Resolver.collect_modifiers(loadout, "on_hit", {"db": db}).is_empty(),
        "chance effects never fire without an RNG")
    var inline: Array[Dictionary] = [{"id": "test", "effects": [
        {"id": "fx_inline", "trigger": "on_kill", "operation": "heal", "magnitude": 3, "stacking": "ignore"}]}]
    check(Resolver.collect_modifiers(inline, "on_kill", {}).size() == 1, "inline effect records are accepted")

func test_stacking(db: Dictionary) -> void:
    var defs: Array = db["statuses"]
    # refresh: re-applying keeps one stack, extends duration, never shortens.
    var slow: Dictionary = ContentDB.effect("fx_slow_on_hit_35", db)
    var statuses: Dictionary = Resolver.apply_status({}, slow, 0.0, defs)
    check(statuses["slowed"]["stacks"] == 1 and is_equal_approx(float(statuses["slowed"]["remaining"]), 1.5),
        "first application creates the status")
    var ticked: Dictionary = Resolver.tick_statuses(statuses, 1.0)["statuses"]
    var refreshed: Dictionary = Resolver.apply_status(ticked, slow, 1.0, defs)
    check(refreshed["slowed"]["stacks"] == 1 and is_equal_approx(float(refreshed["slowed"]["remaining"]), 1.5),
        "refresh resets remaining duration")
    check(is_equal_approx(float(refreshed["slowed"]["refreshed_at"]), 1.0), "refresh records time")
    var long_slow: Dictionary = slow.duplicate()
    long_slow["duration"] = 5.0
    var longer: Dictionary = Resolver.apply_status({}, long_slow, 0.0, defs)
    check(is_equal_approx(float(Resolver.apply_status(longer, slow, 0.0, defs)["slowed"]["remaining"]), 5.0),
        "refresh never shortens a longer status")
    # stack_count: stacks rise to the cap and then only refresh.
    var bleed: Dictionary = ContentDB.effect("fx_bleed_on_hit_25", db)
    var stacked: Dictionary = {}
    for i in range(7):
        stacked = Resolver.apply_status(stacked, bleed, float(i) * 0.1, defs)
    check(stacked["bleeding"]["stacks"] == 5, "stack_count:5 caps at five stacks")
    # ignore: re-application does nothing while active.
    var stun: Dictionary = ContentDB.effect("fx_stun_on_hit_10", db)
    var stunned: Dictionary = Resolver.apply_status({}, stun, 0.0, defs)
    var half: Dictionary = Resolver.tick_statuses(stunned, 0.4)["statuses"]
    var again: Dictionary = Resolver.apply_status(half, stun, 0.4, defs)
    check(is_equal_approx(float(again["stunned"]["remaining"]), 0.2) and again["stunned"]["stacks"] == 1,
        "ignore stacking leaves an active status untouched")
    check(Resolver.has_flag(again, "blocks_actions"), "stun blocks actions")
    # set-with-status removes stacks (cleanse).
    var cleansed: Dictionary = Resolver.apply_status(stacked, ContentDB.effect("fx_cleanse_bleeding", db), 1.0, defs)
    check(not cleansed.has("bleeding"), "set magnitude 0 cleanses a status")
    check(stacked.has("bleeding"), "apply_status does not mutate its input")
    # Shield absorbs, then disappears.
    var shield: Dictionary = Resolver.apply_status({}, ContentDB.effect("fx_emergency_shield", db), 0.0, defs)
    var absorbed: Dictionary = Resolver.absorb_damage(shield, 5)
    check(absorbed["absorbed"] == 5 and absorbed["remaining_damage"] == 0, "shield absorbs damage")
    var broken: Dictionary = Resolver.absorb_damage(absorbed["statuses"], 7)
    check(broken["absorbed"] == 3 and broken["remaining_damage"] == 4 and not broken["statuses"].has("shielded"),
        "emptied shield is removed and overflow passes through")
    # Status stat modifiers feed the same pipeline.
    var hasted: Dictionary = Resolver.apply_status({}, ContentDB.effect("fx_draught_haste", db), 0.0, defs)
    var speed: Dictionary = Resolver.apply_stat_modifiers({"move_speed": 105.0},
        Resolver.status_modifiers(hasted, defs))
    check(is_equal_approx(float(speed["move_speed"]), 105.0 * 1.3), "hasted multiplies move speed")

func test_status_ticks(db: Dictionary) -> void:
    var defs: Array = db["statuses"]
    var burning: Dictionary = Resolver.apply_status({}, ContentDB.effect("fx_ignite_on_hit_15", db), 0.0, defs)
    burning = Resolver.apply_status(burning, ContentDB.effect("fx_ignite_on_hit_15", db), 0.0, defs)
    var total := 0
    var expired_seen := false
    var state: Dictionary = burning
    for _frame in range(40):
        var step: Dictionary = Resolver.tick_statuses(state, 0.1)
        total += int(step["damage"])
        state = step["statuses"]
        if step["expired"].has("burning"):
            expired_seen = true
    check(total == 12, "2 stacks x 2 damage x 3 ticks over 3s of burning (got %d)" % total)
    check(expired_seen and not state.has("burning"), "burning expires after its duration")
    var big_step: Dictionary = Resolver.tick_statuses(burning, 10.0)
    check(int(big_step["damage"]) == 12 and big_step["periodic"].size() == 3,
        "a long frame still emits every tick up to expiry, never more")
    var bleed: Dictionary = Resolver.apply_status({}, ContentDB.effect("fx_bleed_on_hit_25", db), 0.0, defs)
    var bled: Dictionary = Resolver.tick_statuses(bleed, 1.0)
    check(int(bled["damage"]) == 2 and bled["statuses"].has("bleeding"), "bleeding ticks every 0.5s")
    var rng := RandomNumberGenerator.new()
    rng.seed = 5
    var heal: int = Resolver.resolve_amount(ContentDB.effect("fx_heal_1d6_plus_6", db), rng)
    check(heal >= 7 and heal <= 12, "1d6+6 heal resolves through rpg_rules")
    check(Resolver.resolve_amount(ContentDB.effect("fx_heal_6", db)) == 6, "flat heal")

func test_conditions() -> void:
    var context := {"hp": 3, "max_hp": 12, "slot": "melee", "target_tags": ["beast"],
        "target_statuses": {"bleeding": {}}, "ticks": 4, "depth": 2, "room_kind": "boss",
        "nearby_enemies": 3}
    check(Resolver.evaluate_condition({}, context), "empty condition passes")
    check(Resolver.evaluate_condition(null, context), "null condition passes")
    check(Resolver.evaluate_condition({"hp_below_pct": 35}, context), "hp below threshold")
    check(not Resolver.evaluate_condition({"hp_below_pct": 20}, context), "hp not below threshold")
    check(not Resolver.evaluate_condition({"hp_below_pct": 35}, {"hp": 1}), "hp condition needs max_hp")
    check(Resolver.evaluate_condition({"target_tag": "beast", "slot": "melee"}, context), "conditions AND together")
    check(not Resolver.evaluate_condition({"target_tag": "beast", "slot": "ranged"}, context), "any failure fails")
    check(Resolver.evaluate_condition({"status_present": "bleeding"}, context), "status present")
    check(Resolver.evaluate_condition({"status_absent": "burning"}, context), "status absent")
    check(Resolver.evaluate_condition({"ticks_below": 6, "depth_at_least": 2, "room_kind": "boss",
        "nearby_enemies_at_least": 3}, context), "clock/depth/room/crowd conditions")
    check(not Resolver.evaluate_condition({"ticks_below": 6}, {}), "ticks_below needs a clock")
    check(not Resolver.evaluate_condition({"mystery": 1}, context), "unknown keys fail closed")
    check(Resolver.evaluate_condition({"chance": 1.0}, context), "chance 1 always passes")
    check(not Resolver.evaluate_condition({"chance": 0.5}, context), "chance without RNG fails")
    var first: Array = []
    var second: Array = []
    for sequence in [first, second]:
        var rng := RandomNumberGenerator.new()
        rng.seed = 99
        for _i in range(20):
            sequence.append(Resolver.evaluate_condition({"chance": 0.5}, context, rng))
    check(first == second, "chance rolls repeat for the same seed")
    var gated := RandomNumberGenerator.new()
    gated.seed = 1
    var state_before: int = gated.state
    Resolver.evaluate_condition({"chance": 0.5, "slot": "ranged"}, context, gated)
    check(gated.state == state_before, "chance is not rolled when another condition already failed")

func test_skill_graph(db: Dictionary) -> void:
    check(ContentDB.find_prerequisite_cycle(db["skills"]).is_empty(), "shipped skills have no prerequisite cycle")
    var cyclic: Array = [
        {"id": "skl_a", "prerequisites": [{"skill": "skl_c", "rank": 1}]},
        {"id": "skl_b", "prerequisites": [{"skill": "skl_a", "rank": 1}]},
        {"id": "skl_c", "prerequisites": [{"skill": "skl_b", "rank": 1}]},
        {"id": "skl_d", "prerequisites": []}]
    var cycle: Array[String] = ContentDB.find_prerequisite_cycle(cyclic)
    check(cycle.size() == 4 and cycle[0] == cycle[-1], "three-skill cycle detected")
    var broken: Dictionary = db.duplicate(true)
    for entry in broken["skills"]:
        if entry["id"] == "skl_brawler":
            entry["prerequisites"] = [{"skill": "skl_open_wounds", "rank": 1}]
    check(has_problem(ContentDB.validate(broken), "skills: prerequisite cycle"), "validate reports cycles")
    for entry in db["skills"]:
        for prerequisite in entry["prerequisites"]:
            var needed: Dictionary = ContentDB.skill(String(prerequisite["skill"]), db)
            check(int(needed["unlock_level"]) <= int(entry["unlock_level"]),
                "%s unlocks no earlier than its prerequisite" % entry["id"])

func test_loot(db: Dictionary) -> void:
    for table_id in ContentDB.LOOT_CONTEXTS:
        var a: Array[String] = Loot.roll(db, table_id, 424242, 3, 7, 0)
        var b: Array[String] = Loot.roll(db, table_id, 424242, 3, 7, 0)
        check(a == b, "same inputs give same loot: " + table_id)
        for drop_id in a:
            check(not ContentDB.record(drop_id, db).is_empty(), "drop is a real record: " + drop_id)
    var treasure: Array[String] = Loot.roll(db, "treasure_room", 1, 1, 3, 0)
    check(treasure.size() == 2 and treasure[0] != treasure[1], "treasure room gives two distinct rewards")
    check(Loot.roll(db, "guild_hall_shop", 9, 4, 2, 0).size() == 4, "shop stocks four offers")
    var differs := false
    for salt in range(1, 30):
        if Loot.roll(db, "treasure_room", 1, 5, 3, salt) != Loot.roll(db, "treasure_room", 1, 5, 3, 0):
            differs = true
            break
    check(differs, "rng_salt changes the roll")
    # Depth gates rarity: nothing above rare and no min_depth>1 records at depth 1.
    var shallow: Dictionary = {}
    var deep: Dictionary = {}
    for seed_value in range(300):
        for drop_id in Loot.roll(db, "treasure_room", seed_value, 1, 0, 0):
            shallow[drop_id] = true
        for drop_id in Loot.roll(db, "treasure_room", seed_value, 8, 0, 0):
            deep[drop_id] = true
    var shallow_rarities: Dictionary = {}
    for drop_id in shallow.keys():
        var data: Dictionary = ContentDB.record(drop_id, db)
        shallow_rarities[data["rarity"]] = true
        check(int(data["min_depth"]) <= 1, "%s respects min_depth at depth 1" % drop_id)
    check(not shallow_rarities.has("epic") and not shallow_rarities.has("legendary"),
        "depth 1 never drops epic or legendary")
    check(deep.has("wpn_laser_pointer") or deep.has("itm_golden_trophy"), "deep floors unlock epic/legendary drops")
    check(not shallow.has("wpn_crowbar") and not deep.has("wpn_nail_pistol"), "exclude list removes starters")
    var boss_rarities: Dictionary = {}
    for seed_value in range(100):
        for drop_id in Loot.roll(db, "boss_kill", seed_value, 3, 21, 0):
            boss_rarities[ContentDB.record(drop_id, db)["rarity"]] = true
    check(not boss_rarities.has("common"), "boss loot respects min_rarity")
    var normal_drops := 0
    for seed_value in range(400):
        for drop_id in Loot.roll(db, "room_normal_clear", seed_value, 2, 5, 0):
            normal_drops += 1
            check(drop_id != "itm_tick_shard", "tick shards never drop from normal rooms")
    check(normal_drops > 100 and normal_drops < 260, "normal rooms drop loot ~45%% of the time (%d/400)" % normal_drops)
    var owned: Array = []
    for entry in Loot.eligible_candidates(db, "floor_start", 1):
        owned.append(entry["id"])
    check(Loot.roll(db, "floor_start", 3, 1, 0, 0, owned).is_empty(), "extra_exclude can empty a table")
    check(Loot.eligible_candidates(db, "treasure_room", 1).size() < Loot.eligible_candidates(db, "treasure_room", 8).size(),
        "deeper floors widen the candidate pool")
    var curve_shallow: Dictionary = Loot.rarity_weights(db, 1)
    var curve_deep: Dictionary = Loot.rarity_weights(db, 9)
    check(float(curve_shallow["legendary"]) == 0.0 and float(curve_deep["legendary"]) > 0.0, "rarity curve by depth")
