extends SceneTree
## Wave 2F skills on the live Main.tscn: skill points per level-up (and F9),
## can_learn() rules (unlock level, prerequisite, prerequisite rank, max
## rank, points), learn() ranks replacing each other in Loadout.current(),
## passive recompute, INT magnitude scaling, slot auto-assignment, active
## skills (stamina, cooldown, statuses, dash, refusals on cooldown / low
## stamina / stun), cooldown_reduction "skills" and "dodge", the Input Map
## actions, and the level-up overlay / pause Skills page picks.
## Run: godot --headless --path game --script res://tests/skills_test.gd
## The modules preloaded below never name an autoload (they look RunState and
## Events up at runtime), so they are safe here; Game is load()ed.
const SkillSystem = preload("res://scripts/skill_system.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const EffectRunner = preload("res://scripts/effect_runner.gd")
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const CharacterMenu = preload("res://scripts/character_menu.gd")
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var Enemies
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL SKILLS: " + detail)


func _record(name: String, args: Array) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(args)


func _count(name: String) -> int:
    return seen.get(name, []).size()


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    Enemies = load("res://scripts/enemy_system.gd")
    events.skill_learned.connect(func(id, rank): _record("skill_learned", [id, rank]))
    events.skill_used.connect(func(id, rank): _record("skill_used", [id, rank]))
    events.dodged.connect(func(direction): _record("dodged", [direction]))
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    _test_skill_points()
    _test_can_learn()
    _test_learn_and_ranks()
    _test_int_scaling()
    _test_slots()
    _test_sidestep()
    _test_refusals()
    _test_hype()
    _test_cooldown_reduction()
    _test_input_map()
    _test_input_use()
    await _test_level_up_overlay()
    await _test_skills_page()
    _test_menu_no_learnable()
    game.queue_free()
    if failures == 0:
        print("PASS: skill points, learning rules, ranks, INT scaling, slots, sidestep, hype, refusals, cooldown reduction, input, level-up and Skills page picks")
    quit(1 if failures > 0 else 0)


## A fresh run in RUNNING with no modal open.
func _fresh() -> void:
    game.start_run(SEED)
    seen.clear()


## Puts the crawler at `level` with `points` skill points, no modal.
func _at_level(level: int, points: int) -> void:
    rs.level = level
    rs.skill_points = points


func _arena(foes: Array, at: Vector2 = Vector2(100, 192)) -> void:
    var room: Dictionary = rs.current_room()
    room["blocked"] = {}
    room["enemies"] = foes
    room["pickups"] = []
    game.combat.clear_projectiles()
    game.combat.clear_hazards()
    game.player.world_position = at
    game.player.aim_direction = Vector2.RIGHT
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    game.player.cancel_dash()
    game.player.dodge_recovery = 0.0
    rs.statuses = {}


func _foe(at: Vector2, id: String) -> Dictionary:
    var foe: Dictionary = Enemies.make_instance(game.catalogue, "rat_scavenger", at, 1, "", id)
    foe["hp"] = 500
    foe["max_hp"] = 500
    foe["dormant"] = 999.0
    return foe


func _close_level_up() -> void:
    if game.character_menu.is_open():
        game.character_menu.close_menu()
    game._change_state(game.State.RUNNING)


func _test_skill_points() -> void:
    _fresh()
    check(rs.skill_points == 0 and rs.skill_points_earned == 0 and rs.skills.is_empty()
        and rs.skill_slots == ["", ""] and rs.skill_cooldowns.is_empty(), "a new run has no skill state")
    rs.award_xp(RPG.next_level_xp(1))
    check(rs.level == 2 and rs.skill_points == 1 and rs.skill_points_earned == 1
        and rs.pending_stat_points == 2, "a level-up grants 1 skill point and 2 stat points")
    check(game.state == game.State.LEVEL_UP, "the level-up overlay opens")
    _close_level_up()
    rs.award_xp(RPG.next_level_xp(4) - rs.xp)
    check(rs.level == 5 and rs.skill_points == 4 and rs.skill_points_earned == 4,
        "a multi-level award grants one point per level (%d)" % rs.skill_points)
    _close_level_up()
    rs.skills.append({"id": "skl_brawler", "rank": 1})
    rs.skill_cooldowns["skl_sidestep"] = 2.0
    rs.reset_for_floor(2, 30)
    check(rs.skill_points == 4 and rs.skills.size() == 1 and rs.skill_cooldowns.is_empty(),
        "skills and points persist across floors; cooldowns clear")
    var summary: Dictionary = rs.summary()
    check(summary["skill_points"] == 4 and summary["skill_points_earned"] == 4
        and summary["skills"].size() == 1 and summary.has("skill_slots")
        and summary.has("skills_learned") and summary.has("skills_used"), "summary carries skill state")
    game.start_run(SEED)
    check(rs.skill_points == 0 and rs.skill_points_earned == 0 and rs.skills.is_empty(),
        "skills reset on a new run")


func _test_can_learn() -> void:
    _fresh()
    _at_level(1, 5)
    var result: Dictionary = SkillSystem.can_learn("skl_sidestep")
    check(not result["ok"] and result["reason"] == "level" and result["detail"] == "Needs level 2.",
        "below unlock_level: %s" % [result])
    check(SkillSystem.can_learn("skl_brawler")["ok"], "a level-1 skill is learnable at level 1")
    check(SkillSystem.can_learn("skl_nope")["reason"] == "unknown", "unknown ids are rejected")
    _at_level(3, 5)
    result = SkillSystem.can_learn("skl_open_wounds")
    check(not result["ok"] and result["reason"] == "prerequisite", "missing prerequisite: %s" % [result])
    rs.skills.append({"id": "skl_steady_aim", "rank": 1})
    _at_level(4, 5)
    result = SkillSystem.can_learn("skl_arson_enthusiast")
    check(not result["ok"] and result["reason"] == "prerequisite_rank"
        and result["detail"] == "Needs Steady Aim rank 2.", "prerequisite below its rank: %s" % [result])
    rs.skills[0]["rank"] = 2
    check(SkillSystem.can_learn("skl_arson_enthusiast")["ok"], "prerequisite rank met")
    _at_level(5, 5)
    rs.skills.append({"id": "skl_panic_mode", "rank": 1})
    result = SkillSystem.can_learn("skl_panic_mode")
    check(not result["ok"] and result["reason"] == "max_rank", "at max_rank: %s" % [result])
    rs.skills.append({"id": "skl_iron_gut", "rank": 1})
    _at_level(5, 1)
    result = SkillSystem.can_learn("skl_mandatory_hype")
    check(not result["ok"] and result["reason"] == "points" and result["cost"] == 2,
        "cost above the banked points: %s" % [result])
    _at_level(5, 0)
    check(SkillSystem.can_learn("skl_brawler")["reason"] == "points", "no points, nothing learnable")
    check(not SkillSystem.learn("skl_brawler")["ok"] and SkillSystem.rank_of("skl_brawler") == 0
        and _count("skill_learned") == 0, "a refused learn changes nothing")
    # Plain-id entries (Loadout's legacy shape) read as rank 1.
    rs.skills.append("skl_brawler")
    check(SkillSystem.rank_of("skl_brawler") == 1 and rs.skills.back() is Dictionary,
        "a plain id is normalised to {id, rank 1}")


func _effects_of(loadout: Array, id: String) -> Array:
    var found: Array = []
    for entry in loadout:
        if String(entry["id"]) == id:
            found.append(entry["effects"])
    return found


func _test_learn_and_ranks() -> void:
    _fresh()
    _at_level(3, 3)
    var hp_before: int = rs.max_hp
    var result: Dictionary = SkillSystem.learn("skl_brawler")
    check(result["ok"] and result["rank"] == 1 and rs.skill_points == 2
        and rs.skills == [{"id": "skl_brawler", "rank": 1}], "learn stores {id, rank} and spends the cost")
    check(seen.get("skill_learned", []) == [["skl_brawler", 1]], "skill_learned(id, rank)")
    check(int(rs.telemetry["skills_learned"]) == 1, "telemetry skills_learned")
    check(_effects_of(Loadout.current(), "skl_brawler") == [["fx_brawler_dmg_1"]], "rank 1 effects")
    SkillSystem.learn("skl_brawler")
    check(_effects_of(Loadout.current(), "skl_brawler") == [["fx_brawler_dmg_1", "fx_melee_cooldown_x090"]],
        "rank 2 replaces rank 1")
    SkillSystem.learn("skl_brawler")
    var rank3: Array = _effects_of(Loadout.current(), "skl_brawler")
    check(rank3 == [["fx_brawler_dmg_2", "fx_melee_cooldown_x090"]] and SkillSystem.rank_of("skl_brawler") == 3
        and rs.skills.size() == 1, "rank 3: only the current rank's effects, one entry")
    check(SkillSystem.can_learn("skl_brawler")["reason"] == "max_rank", "brawler maxed at 3")
    game.items.recompute()
    var melee: Dictionary = game.items.profile("melee")
    check(int(melee["damage_bonus"]) == RPG.modifier(int(rs.ability_scores["STR"])) + 2
        and is_equal_approx(float(melee["cooldown"]), 0.45), "brawler 3 changes the melee profile: %s" % [melee])
    # Passive recompute happens through ItemSystem's skill_learned hook.
    rs.skill_points = 1
    SkillSystem.learn("skl_iron_gut")
    check(game.items._dirty, "skill_learned marks ItemSystem dirty")
    game.items.update(FRAME)
    check(rs.max_hp == hp_before + 3, "Iron Gut 1: +3 max HP after the recompute (%d -> %d)" % [hp_before, rs.max_hp])


func _test_int_scaling() -> void:
    _fresh()
    check(is_equal_approx(Loadout.skill_magnitude_mult(), 1.0), "INT 10: no scaling")
    rs.skills.append({"id": "skl_iron_gut", "rank": 3})
    rs.skills.append({"id": "skl_brawler", "rank": 2})
    rs.ability_scores["INT"] = 14
    check(is_equal_approx(Loadout.skill_magnitude_mult(), 1.2), "INT 14 (+2): x1.2")
    var mods: Array[Dictionary] = Loadout.passive_modifiers()
    var hp_mod := 0.0
    var cooldown_mod := 0.0
    for modifier in mods:
        if String(modifier["effect_id"]) == "fx_iron_gut_3":
            hp_mod = float(modifier["magnitude"])
        if String(modifier["effect_id"]) == "fx_melee_cooldown_x090":
            cooldown_mod = float(modifier["magnitude"])
    check(is_equal_approx(hp_mod, 10.8), "add effects scale: +9 -> +10.8 (%f)" % hp_mod)
    check(is_equal_approx(cooldown_mod, 0.88), "multiply effects scale from 1: x0.9 -> x0.88 (%f)" % cooldown_mod)
    var shield: Array[Dictionary] = Resolver.collect_modifiers(ContentDB.loadout([{"id": "skl_mandatory_hype",
        "rank": 2, "magnitude_mult": Loadout.skill_magnitude_mult()}]), "on_use", {"db": ContentDB.default_db()})
    var pool := 0.0
    var slow := -1.0
    for modifier in shield:
        if String(modifier.get("status", "")) == "shielded":
            pool = float(modifier["magnitude"])
        if String(modifier.get("status", "")) == "slowed":
            slow = float(modifier["magnitude"])
    check(is_equal_approx(pool, 6.0) and is_equal_approx(slow, 0.0),
        "status magnitudes scale (shield 5 -> 6), a 0 magnitude stays 0")
    var item_mods: Array[Dictionary] = Resolver.collect_modifiers(ContentDB.loadout(["itm_hazard_vest"]),
        "passive", {"db": ContentDB.default_db()})
    check(not item_mods.is_empty() and not item_mods[0].has("magnitude_mult"), "items are not INT-scaled")
    rs.ability_scores["INT"] = 10
    rs.skills.clear()


func _test_slots() -> void:
    _fresh()
    _at_level(3, 10)
    rs.skills.append({"id": "skl_iron_gut", "rank": 1})
    SkillSystem.learn("skl_brawler")
    check(rs.skill_slots == ["", ""], "passives take no slot")
    SkillSystem.learn("skl_sidestep")
    check(rs.skill_slots == ["skl_sidestep", ""], "the first active fills slot 1")
    SkillSystem.learn("skl_mandatory_hype")
    check(rs.skill_slots == ["skl_sidestep", "skl_mandatory_hype"], "the second fills slot 2")
    SkillSystem.learn("skl_sidestep")
    check(rs.skill_slots == ["skl_sidestep", "skl_mandatory_hype"], "a rank-up keeps the binding")
    check(SkillSystem.assign_slot("skl_sidestep", 1)
        and rs.skill_slots == ["skl_mandatory_hype", "skl_sidestep"], "reassigning swaps the slots")
    check(not SkillSystem.assign_slot("skl_brawler", 0) and not SkillSystem.assign_slot("skl_sidestep", 2)
        and not SkillSystem.assign_slot("skl_open_wounds", 0), "passives, bad slots and unlearned skills refused")
    var view: Array = SkillSystem.describe_slots()
    check(view.size() == 2 and view[0]["key"] == "Z" and view[1]["name"] == "Sidestep Protocol"
        and is_equal_approx(float(view[1]["cooldown"]), 2.4), "describe_slots: keys, names, rank cooldown")


func _learn_now(id: String, rank: int = 1) -> void:
    for i in range(rank):
        rs.skill_points = 9
        rs.level = 10
        var result: Dictionary = SkillSystem.learn(id)
        if not result["ok"]:
            push_error("learn %s failed: %s" % [id, result])
    rs.skill_points = 0


func _test_sidestep() -> void:
    _fresh()
    _arena([])
    _learn_now("skl_sidestep")
    seen.clear()
    var start: Vector2 = game.player.world_position
    var result: Dictionary = game.skills.use_slot(0, Vector2.UP)
    check(result["ok"], "sidestep used: %s" % [result])
    check(is_equal_approx(rs.stamina, 80.0), "costs 20 stamina (%f)" % rs.stamina)
    check(is_equal_approx(SkillSystem.cooldown_left("skl_sidestep"), 3.0), "starts its 3 s cooldown")
    check(rs.statuses.has("evasive") and is_equal_approx(float(rs.statuses["evasive"]["remaining"]), 0.3)
        and game.player.dodge_iframes >= 0.299, "applies evasive 0.3 s as i-frames")
    check(game.player.is_dodging() and game.player.dodge_direction == Vector2.UP, "dashes in the move direction")
    check(seen.get("skill_used", []) == [["skl_sidestep", 1]] and _count("dodged") == 1,
        "skill_used(id, rank) and the on_dodge path (dodged)")
    check(int(rs.telemetry["skills_used"]) == 1, "telemetry skills_used")
    check(not game.combat.hit_player(100, 6, 0, "test"), "hits are ignored while evasive")
    for _i in range(20):
        game.player.tick_timers(FRAME)
        game.player.move(game.player.step_dash(FRAME), game.combat.blocked())
    check(is_equal_approx(start.y - game.player.world_position.y, 40.0), "the dash covers 40 px (%f)"
        % (start.y - game.player.world_position.y))
    game.skills.update(3.0)
    check(SkillSystem.cooldown_left("skl_sidestep") == 0.0, "the cooldown ticks down in update()")
    _arena([])
    _learn_now("skl_sidestep")
    check(game.skills.use_skill("skl_sidestep")["ok"] and is_equal_approx(
        SkillSystem.cooldown_left("skl_sidestep"), 2.4) and is_equal_approx(
        float(rs.statuses["evasive"]["remaining"]), 0.45), "rank 2: 2.4 s cooldown, 0.45 s evasive")


func _test_refusals() -> void:
    _fresh()
    _arena([])
    _learn_now("skl_sidestep")
    check(game.skills.use_slot(0)["ok"], "first use")
    var stamina: float = rs.stamina
    game.player.cancel_dash()
    game.player.dodge_recovery = 0.0
    var again: Dictionary = game.skills.use_slot(0)
    check(not again["ok"] and again["reason"] == "cooldown" and is_equal_approx(rs.stamina, stamina),
        "refused on cooldown, no stamina spent")
    game.skills.update(5.0)
    rs.stamina = 10.0
    var tired: Dictionary = game.skills.use_slot(0)
    check(not tired["ok"] and tired["reason"] == "stamina" and is_equal_approx(rs.stamina, 10.0)
        and SkillSystem.cooldown_left("skl_sidestep") == 0.0, "refused without enough stamina")
    rs.stamina = 100.0
    StatusSystem.apply("player", {"status": "stunned"})
    var stunned: Dictionary = game.skills.use_slot(0)
    check(not stunned["ok"] and stunned["reason"] == "stunned" and is_equal_approx(rs.stamina, 100.0),
        "refused while stunned (blocks_actions)")
    rs.statuses = {}
    game.player.start_dash(Vector2.RIGHT, 10.0, 0.2)
    check(game.skills.use_slot(0)["reason"] == "busy", "a dash skill waits for the current dash")
    game.player.cancel_dash()
    check(game.skills.use_slot(1)["reason"] == "empty", "an empty slot does nothing")
    check(game.skills.use_skill("skl_mandatory_hype")["reason"] == "not_learned", "unlearned skills refused")
    rs.skills.append({"id": "skl_brawler", "rank": 1})
    check(game.skills.use_skill("skl_brawler")["reason"] == "passive", "passives cannot be used")
    check(int(rs.telemetry["skills_used"]) == 1, "only the successful use counted")


func _test_hype() -> void:
    _fresh()
    var near: Dictionary = _foe(Vector2(150, 192), "near")
    var far: Dictionary = _foe(Vector2(300, 192), "far")
    _arena([near, far])
    rs.skills.append({"id": "skl_iron_gut", "rank": 1})
    _learn_now("skl_mandatory_hype")
    check(rs.skill_slots[0] == "skl_mandatory_hype", "hype auto-binds to slot 1")
    var result: Dictionary = game.skills.use_slot(0)
    check(result["ok"] and is_equal_approx(rs.stamina, 70.0)
        and is_equal_approx(SkillSystem.cooldown_left("skl_mandatory_hype"), 14.0), "30 stamina, 14 s cooldown")
    check(StatusSystem.has_status(near, "slowed") and not StatusSystem.has_status(far, "slowed"),
        "slows enemies within 80 px only")
    check(rs.statuses.has("hasted") and not rs.statuses.has("shielded"), "rank 1: hasted, no shield")
    check(not game.player.is_dodging(), "hype does not dash")
    _arena([_foe(Vector2(150, 192), "near2")])
    rs.skill_cooldowns.clear()
    _learn_now("skl_mandatory_hype")
    game.skills.use_slot(0)
    check(rs.statuses.has("shielded") and int(rs.statuses["shielded"]["magnitude"]) == 5
        and is_equal_approx(SkillSystem.cooldown_left("skl_mandatory_hype"), 11.0),
        "rank 2 adds a 5-point shield; 11 s cooldown")


func _test_cooldown_reduction() -> void:
    _fresh()
    _arena([])
    _learn_now("skl_sidestep")
    _learn_now("skl_panic_mode")
    rs.skill_cooldowns["skl_sidestep"] = 2.0
    var fired: Array[Dictionary] = EffectRunner.fire(game.combat, "on_kill", {})
    var refunded := false
    for modifier in fired:
        refunded = refunded or String(modifier["effect_id"]) == "fx_skill_cooldown_refund"
    check(refunded and is_equal_approx(SkillSystem.cooldown_left("skl_sidestep"), 1.5),
        "Panic Mode: a kill takes 0.5 s off skill cooldowns (cooldown_reduction skills)")
    EffectRunner.execute(game.combat, [{"operation": "cooldown_reduction", "stat": "skills", "magnitude": 5.0}])
    check(not rs.skill_cooldowns.has("skl_sidestep"), "a cooldown reduced to 0 is cleared")
    game.player.dodge_cooldown = 1.0
    EffectRunner.execute(game.combat, [{"operation": "cooldown_reduction", "stat": "dodge", "magnitude": 0.4}])
    check(is_equal_approx(game.player.dodge_cooldown, 0.6), "cooldown_reduction dodge shortens the dodge gap")
    rs.skill_cooldowns["skl_sidestep"] = 2.0
    game.player.dodge_cooldown = 1.0
    EffectRunner.execute(game.combat, [{"operation": "cooldown_reduction", "stat": "all", "magnitude": 1.0}])
    check(is_equal_approx(SkillSystem.cooldown_left("skl_sidestep"), 1.0) and game.player.dodge_cooldown == 0.0,
        "cooldown_reduction all covers skills and dodge")


func _test_input_map() -> void:
    var expected := {"use_skill_1": [90, "axis:4:1"], "use_skill_2": [88, "pad:2"]}
    for action in expected.keys():
        check(InputMap.has_action(action), "input action defined: " + action)
        var has_key := false
        var has_pad := false
        for event in InputMap.action_get_events(action):
            if event is InputEventKey and event.physical_keycode == expected[action][0]:
                has_key = true
            if event is InputEventJoypadButton and "pad:%d" % event.button_index == expected[action][1]:
                has_pad = true
            if event is InputEventJoypadMotion and "axis:%d:%d" % [event.axis, int(signf(event.axis_value))] \
                    == expected[action][1]:
                has_pad = true
        check(has_key and has_pad, "%s bound to its key and pad input" % action)
    # No key, button or axis direction is shared by two gameplay actions.
    var owners: Dictionary = {}
    for action in InputMap.get_actions():
        if String(action).begins_with("ui_"):
            continue
        for event in InputMap.action_get_events(action):
            var key := ""
            if event is InputEventKey:
                key = "key:%d" % (event.physical_keycode if event.physical_keycode != 0 else event.keycode)
            elif event is InputEventJoypadButton:
                key = "pad:%d" % event.button_index
            elif event is InputEventJoypadMotion:
                key = "axis:%d:%d" % [event.axis, int(signf(event.axis_value))]
            elif event is InputEventMouseButton:
                key = "mouse:%d" % event.button_index
            if key == "":
                continue
            check(not owners.has(key), "%s is bound to both %s and %s" % [key, owners.get(key, ""), action])
            owners[key] = action


func _test_input_use() -> void:
    _fresh()
    _arena([])
    _learn_now("skl_sidestep")
    Input.action_press("use_skill_1")
    game._physics_process(FRAME)
    Input.action_release("use_skill_1")
    check(SkillSystem.cooldown_left("skl_sidestep") > 2.9 and rs.statuses.has("evasive"),
        "use_skill_1 in the physics loop uses slot 1")
    game._physics_process(FRAME)
    check(int(rs.telemetry["skills_used"]) == 1, "one press, one use")


func _find(root: Node, node_name: String) -> Node:
    return root.find_child(node_name, true, false)


func _test_level_up_overlay() -> void:
    _fresh()
    var ui = game.character_menu
    rs.award_xp(RPG.next_level_xp(1))
    check(ui.mode == "level_up" and ui.skill_points() == 1, "the overlay shows the skill point")
    var listed: Array = []
    for entry in ui.skill_view().get("skills", []):
        listed.append(String(entry["id"]))
    check(listed.size() == 8 and listed.has("skl_panic_mode"), "every skill is listed: %s" % [listed])
    var learnable: Array = ui.learnable_skills()
    check(learnable.has("skl_sidestep") and learnable.has("skl_iron_gut") and not learnable.has("skl_open_wounds")
        and not learnable.has("skl_mandatory_hype"), "learnable at level 2: %s" % [learnable])
    await process_frame
    var pick: Node = _find(ui.center, "learn_skl_sidestep")
    var locked: Node = _find(ui.center, "learn_skl_open_wounds")
    var confirm: Node = _find(ui.center, "confirm")
    var bank: Node = _find(ui.center, "bank")
    check(pick is Button and not pick.disabled and pick.text == "Learn", "Sidestep has an enabled Learn button")
    check(locked is Button and locked.disabled and locked.text == "Locked", "Open Wounds is greyed out (level 3)")
    check(confirm is Button and confirm.disabled and bank is Button and bank.disabled,
        "confirm and save wait for the ability points")
    ui.stage_point("DEX", 2)
    await process_frame
    confirm = _find(ui.center, "confirm")
    bank = _find(ui.center, "bank")
    check(confirm.disabled and not bank.disabled, "with stats staged: save enabled, confirm still waits")
    pick = _find(ui.center, "learn_skl_sidestep")
    pick.emit_signal("pressed")
    check(SkillSystem.rank_of("skl_sidestep") == 1 and rs.skill_points == 0 and ui.skill_points() == 0,
        "pressing Learn learns the skill")
    check(int(ui.staged.get("DEX", 0)) == 2, "staged ability points survive the pick")
    await process_frame
    confirm = _find(ui.center, "confirm")
    check(confirm is Button and not confirm.disabled and _find(ui.center, "bank") == null,
        "confirm is enabled once both pools are spent")
    check(rs.skill_slots[0] == "skl_sidestep", "the new active is bound to Z")
    confirm.emit_signal("pressed")
    check(ui.mode == "closed" and game.state == game.State.RUNNING and int(rs.ability_scores["DEX"]) == 16,
        "confirm applies the stats and resumes")
    # Banking: the next level saves the point for later.
    rs.award_xp(RPG.next_level_xp(2) - rs.xp)
    check(ui.mode == "level_up" and ui.skill_points() == 1, "level 3 overlay")
    ui.stage_point("CON", 2)
    ui.confirm_allocation()
    check(ui.mode == "level_up", "confirm refused while the point is unspent")
    ui.bank_and_confirm()
    check(ui.mode == "closed" and rs.skill_points == 1 and game.state == game.State.RUNNING,
        "Save for later banks the point and resumes")


func _test_skills_page() -> void:
    var ui = game.character_menu
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    game._input(escape)
    check(ui.mode == "pause", "pause opens")
    ui._open_skills_page()
    await process_frame
    check(ui.page == "skills" and ui.skill_points() == 1, "the Skills page shows the banked point")
    var bind: Node = _find(ui.center, "slot_1_skl_sidestep")
    check(bind is Button and not bind.disabled, "a learned active can be moved to slot 2")
    bind.emit_signal("pressed")
    check(rs.skill_slots == ["", "skl_sidestep"], "the slot button rebinds it")
    check(ui.pick_skill("skl_brawler") and SkillSystem.rank_of("skl_brawler") == 1 and rs.skill_points == 0,
        "banked points are spent on the Skills page")
    check(not ui.pick_skill("skl_iron_gut"), "nothing more to spend")
    await process_frame
    check(ui.page == "skills" and _find(ui.center, "learn_skl_brawler").text == "Rank up",
        "the page refreshes in place")
    game._input(escape)
    check(ui.mode == "closed" and game.state == game.State.RUNNING, "Esc resumes")


## With nothing learnable, confirm needs only the ability points.
func _test_menu_no_learnable() -> void:
    var menu = CharacterMenu.new()
    menu.show_level_up({"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
        {"level": 2, "skills": {"points": 1, "skills": [{"id": "skl_x", "learnable": false}]}}, 2, 20)
    check(not menu.can_confirm(), "ability points first")
    menu.stage_point("STR", 2)
    check(menu.can_confirm(), "a skill point with nothing learnable does not block confirm")
    menu.free()
