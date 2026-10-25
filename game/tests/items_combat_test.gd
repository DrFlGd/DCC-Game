extends SceneTree
## Wave 2B weapons, statuses and triggers in live combat (Main.tscn):
## crowbar / nail-pistol equivalence with the prototype numbers, spread count,
## burst timing, pierce count, thrust / spin / arc geometry, beam ticks,
## on_hit status application and DoT damage through apply_damage, shielded
## absorb, stun / evasive / concealed, boss immunity, on_kill and
## on_damage_taken triggers, hazard statuses and status-scaled enemy speed.
## Run: godot --headless --path game --script res://tests/items_combat_test.gd
## Preloaded modules never name an autoload; Game and Combat are load()ed.
const Inventory = preload("res://scripts/inventory.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const ContentDB = preload("res://scripts/content/content_db.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var Combat
var Enemies
var Hazards
var damaged: Array = []
var fired: Array = []


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ITEMS COMBAT: " + detail)


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    Combat = load("res://scripts/combat.gd")
    Enemies = load("res://scripts/enemy_system.gd")
    Hazards = load("res://scripts/hazards.gd")
    events.enemy_damaged.connect(func(id, amount, _crit): damaged.append([id, amount]))
    events.projectile_fired.connect(func(owner, data): if owner == "player": fired.append(data))
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    game.start_run(SEED)
    _test_starter_equivalence()
    _test_spread()
    _test_burst()
    _test_pierce()
    _test_melee_geometry()
    _test_beam()
    _test_on_hit_and_dot()
    _test_shield_and_player_statuses()
    _test_boss_immunity_and_enemy_stun()
    _test_kill_and_damage_triggers()
    _test_hazard_status()
    _test_feel_integration()
    await _test_render()
    game.queue_free()
    if failures == 0:
        print("PASS: starter equivalence, spread, burst, pierce, thrust/spin/arc, beam, on_hit, DoT, shields, stun, decoy, triggers, hazards")
    quit(1 if failures > 0 else 0)


## Clean obstacle-free current room holding `foes`; the crawler at `at`.
func _arena(foes: Array, at: Vector2 = Vector2(100, 192)) -> Array:
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
    game.player.fire_cooldown = 0.0
    game.player.melee_cooldown = 0.0
    rs.statuses = {}
    damaged.clear()
    fired.clear()
    return room["enemies"]


func _foe(at: Vector2, id: String = "", hp: int = 500) -> Dictionary:
    var foe: Dictionary = Enemies.make_instance(game.catalogue, "rat_scavenger", at, 1, "",
        id if id != "" else "t_%d_%d" % [int(at.x), int(at.y)])
    foe["hp"] = hp
    foe["max_hp"] = hp
    foe["dormant"] = 999.0
    return foe


func _equip(id: String) -> void:
    var slot: String = String(ContentDB.weapon(id).get("slot", ""))
    if slot != "":
        rs.inventory[slot] = id
    events.inventory_changed.emit()
    game.items.recompute()


func _test_starter_equivalence() -> void:
    _arena([])
    var scores: Dictionary = rs.ability_scores
    var pistol: Dictionary = Loadout.attack_profile("ranged")
    check(pistol["weapon_id"] == "wpn_nail_pistol" and pistol["die"] == Combat.PLAYER_SHOT_DIE
        and is_equal_approx(float(pistol["projectile_speed"]), Combat.PLAYER_SHOT_SPEED)
        and is_equal_approx(float(pistol["ttl"]), Combat.PLAYER_SHOT_TTL), "pistol: d6, 215 px/s, 2.0 s")
    check(int(pistol["damage_bonus"]) == RPG.modifier(int(scores["DEX"]))
        and int(pistol["attack_bonus"]) == RPG.attack_bonus(scores, "DEX", rs.level),
        "pistol: DEX mod damage and DEX + proficiency to hit")
    check(is_equal_approx(game.items.cooldown("ranged"), 0.28), "pistol cooldown 0.28 s")
    var crowbar: Dictionary = Loadout.attack_profile("melee")
    check(crowbar["die"] == Combat.MELEE_DIE and is_equal_approx(float(crowbar["reach"]), Combat.MELEE_REACH)
        and is_equal_approx(game.items.cooldown("melee"), 0.5)
        and int(crowbar["damage_bonus"]) == RPG.modifier(int(scores["STR"]))
        and int(crowbar["attack_bonus"]) == RPG.attack_bonus(scores, "STR", rs.level),
        "crowbar: d6 STR, 32 px, 0.5 s")
    check(absf(float(crowbar["dot_threshold"]) - Combat.MELEE_ARC_DOT) < 0.005,
        "crowbar arc 127 degrees ~ the prototype's 0.45 dot test")
    game.combat.player_fire()
    check(game.combat.projectiles.size() == 1, "single pattern: one bolt")
    var shot: Dictionary = game.combat.projectiles[0]
    check(Vector2(shot["pos"]).is_equal_approx(Vector2(100, 192) + Vector2.RIGHT * Combat.PLAYER_SHOT_SPAWN)
        and Vector2(shot["velocity"]).is_equal_approx(Vector2.RIGHT * 215.0)
        and is_equal_approx(float(shot["ttl"]), 2.0) and shot["die"] == 6
        and shot["bonus"] == RPG.modifier(int(scores["DEX"])) and shot["owner"] == "player"
        and shot["source"] == "player", "the bolt matches the prototype dictionary")
    check(shot["pierce"] == 0 and shot["weapon_id"] == "wpn_nail_pistol" and shot.has("knockback")
        and shot["effects"] == [], "projectiles carry pierce, knockback, effects, weapon_id")


func _test_spread() -> void:
    _arena([])
    _equip("wpn_confetti_scattergun")
    game.combat.player_fire()
    var shots: Array = game.combat.projectiles
    check(shots.size() == 4 and fired.size() == 4, "scattergun: 4 pellets (%d)" % shots.size())
    var angles: Array = []
    for shot in shots:
        angles.append(rad_to_deg(Vector2(shot["velocity"]).angle()))
    angles.sort()
    check(absf(float(angles[0]) + 20.0) < 0.01 and absf(float(angles[3]) - 20.0) < 0.01,
        "pellets fan over 40 degrees: %s" % [angles])
    check(is_equal_approx(float(shots[0]["ttl"]), 170.0 / 200.0), "lifetime = range / speed")
    check(Combat.spread_angles(1, 40.0) == [0.0], "one projectile flies straight")


func _test_burst() -> void:
    _arena([])
    _equip("wpn_staple_rifle")
    game.combat.player_fire()
    check(game.combat.projectiles.size() == 1 and game.combat.pending_shots.size() == 2,
        "burst: first shot now, two queued")
    var times: Array = []
    var elapsed := 0.0
    var step := 0.005
    while elapsed < 0.3:
        var before: int = fired.size()
        game.combat.update_projectiles(step)
        elapsed += step
        if fired.size() > before:
            times.append(elapsed)
    check(fired.size() == 3 and times.size() == 2, "three shots in total")
    if times.size() == 2:
        check(absf(float(times[0]) - 0.07) <= step + 0.0001 and absf(float(times[1]) - 0.14) <= step + 0.0001,
            "burst_interval 0.07 s, the burst ends by 0.15 s: %s" % [times])
    for shot in fired:
        var angle: float = absf(rad_to_deg(Vector2(shot["velocity"]).angle()))
        check(angle <= 3.0001, "jitter within +-3 degrees (%.2f)" % angle)
    game.combat.player_fire()
    game.combat.clear_projectiles()
    check(game.combat.pending_shots.is_empty(), "room transitions drop queued burst shots")


func _test_pierce() -> void:
    var foes: Array = _arena([_foe(Vector2(140, 192), "p1"), _foe(Vector2(170, 192), "p2"),
        _foe(Vector2(200, 192), "p3"), _foe(Vector2(230, 192), "p4")])
    _equip("wpn_siege_crossbow")
    game.combat.player_fire()
    var bolt: Dictionary = game.combat.projectiles[0]
    check(int(bolt["pierce"]) == 2, "siege crossbow pierces 2")
    for _i in range(240):
        game.combat.update_projectiles(FRAME)
        if game.combat.projectiles.is_empty():
            break
    check(bolt["hit"].size() == 3 and bolt["hit"].has("p1") and bolt["hit"].has("p3")
        and not bolt["hit"].has("p4"), "a pierce-2 bolt hits 3 enemies in line: %s" % [bolt["hit"].keys()])
    check(game.combat.projectiles.is_empty(), "then it is spent")
    check(foes.size() == 4, "nobody died (500 HP)")


func _test_melee_geometry() -> void:
    _arena([])
    _equip("wpn_mop_pike")
    var pike: Dictionary = Loadout.attack_profile("melee")
    check(pike["pattern"] == "thrust" and is_equal_approx(float(pike["reach"]), 48.0)
        and is_equal_approx(game.items.cooldown("melee"), 0.62), "mop pike: thrust, 48 px, 0.62 s")
    var origin := Vector2(100, 192)
    var foes: Array = [_foe(origin + Vector2(20, 3)), _foe(origin + Vector2(30, 14)),
        _foe(origin + Vector2(40, -2)), _foe(origin + Vector2(10, 0)), _foe(origin + Vector2(50, 0)),
        _foe(origin + Vector2(-15, 0))]
    var radius: float = float(foes[0]["radius"])
    var hits: Array[int] = Combat.melee_hits(pike, origin, Vector2.RIGHT, foes)
    check(hits == [3, 0, 2], "thrust: 10 px lane, nearest first, 1 + pierce targets: %s (r %.1f)" %
        [hits, radius])
    var lane: Array[int] = Combat.melee_hits(pike, origin, Vector2.RIGHT,
        [_foe(origin + Vector2(48.0 + radius - 0.5, 0)), _foe(origin + Vector2(48.0 + radius + 1.0, 0))])
    check(lane == [0], "thrust length is reach + enemy radius")
    _equip("wpn_novelty_flail")
    var flail: Dictionary = Loadout.attack_profile("melee")
    var ring: Array = [_foe(origin + Vector2(-30, 0)), _foe(origin + Vector2(0, 33)),
        _foe(origin + Vector2(40, 0))]
    check(Combat.melee_hits(flail, origin, Vector2.RIGHT, ring) == [1, 0],
        "spin: every enemy within reach + radius, behind included")
    _equip("wpn_crowbar")
    var crowbar: Dictionary = Loadout.attack_profile("melee")
    var cone: Array = [_foe(origin + Vector2(20, 0)), _foe(origin + Vector2(-20, 0)),
        _foe(origin + Vector2(12, 22)), _foe(origin + Vector2(8, 24))]
    # (12, 22): 61.4 degrees off-axis, inside 63.5; (8, 24): 71.6 degrees, outside.
    check(Combat.melee_hits(crowbar, origin, Vector2.RIGHT, cone) == [2, 0],
        "arc: the 127 degree sector only, prototype order (highest index first)")
    var live: Array = _arena([_foe(origin + Vector2(20, 0), "m1")], origin)
    game.combat.player_melee()
    check(game.combat.last_swing["pattern"] == "arc" and is_equal_approx(float(game.combat.last_swing["reach"]), 32.0),
        "the swing records its shape for the renderer")
    check(live.size() == 1, "swing resolved without errors")


func _test_beam() -> void:
    var foes: Array = _arena([_foe(Vector2(140, 192), "b1"), _foe(Vector2(170, 192), "b2")])
    _equip("wpn_laser_pointer")
    var laser: Dictionary = Loadout.attack_profile("ranged")
    check(laser["pattern"] == "beam" and is_equal_approx(game.items.cooldown("ranged"), 0.2),
        "laser pointer: beam ticks every 0.2 s")
    var hits: Array = game.combat.fire_beam(laser, Vector2(100, 192), Vector2.RIGHT)
    check(hits.size() == 1 and String(hits[0]["instance_id"]) == "b1", "a pierce-0 beam hits the first enemy")
    check(game.combat.beams.size() == 1 and game.combat.projectiles.is_empty(), "hitscan: no projectile")
    rs.current_room()["blocked"] = {Vector2i(7, 12): true}
    hits = game.combat.fire_beam(laser, Vector2(100, 192), Vector2.RIGHT)
    check(hits.is_empty(), "obstacles stop the beam")
    check(foes.size() == 2, "beam left both alive")


func _test_on_hit_and_dot() -> void:
    var foes: Array = _arena([_foe(Vector2(140, 192), "h1", 60)])
    var foe: Dictionary = foes[0]
    _equip("wpn_siege_crossbow")
    var dealt: int = game.combat.apply_damage(foe, 3, {"source": "player", "slot": "ranged",
        "weapon_id": "wpn_siege_crossbow"})
    check(dealt == 3 and StatusSystem.has_status(foe, "slowed"), "crossbow on_hit (fx_hobble_on_hit) slows")
    check(is_equal_approx(StatusSystem.speed_multiplier(foe), 0.6), "slowed: speed x0.6")
    _equip("wpn_nail_pistol")
    StatusSystem.clear(foe)
    game.combat.apply_damage(foe, 3, {"source": "player", "slot": "ranged", "weapon_id": "wpn_nail_pistol"})
    check(not StatusSystem.has_status(foe, "slowed"), "the pistol's hits carry no crossbow effects")
    # The crossbow's on_hit belongs to its own projectiles even after a swap.
    game.combat.apply_damage(foe, 1, {"source": "player", "slot": "ranged", "weapon_id": "wpn_siege_crossbow"})
    check(StatusSystem.has_status(foe, "slowed"), "a projectile keeps the weapon that fired it")
    # Slowed enemies move slower for that step only.
    var mover: Dictionary = _foe(Vector2(300, 300), "mv")
    mover["dormant"] = 0.0
    var still: Dictionary = _foe(Vector2(300, 100), "mv2")
    still["dormant"] = 0.0
    _arena([mover, still], Vector2(60, 200))
    StatusSystem.apply(mover, {"status": "slowed"})
    var base: float = float(mover["speed"])
    var start_a: Vector2 = mover["pos"]
    var start_b: Vector2 = still["pos"]
    for _i in range(12):
        game.combat.update_enemies(FRAME)
    var moved_a: float = Vector2(mover["pos"]).distance_to(start_a)
    var moved_b: float = Vector2(still["pos"]).distance_to(start_b)
    check(moved_b > 0.0 and absf(moved_a - moved_b * 0.6) < 0.5 and float(mover["speed"]) == base,
        "slowed enemy covers 60 %% of the distance (%.2f vs %.2f); speed restored" % [moved_a, moved_b])
    # Burning: 2 x stacks every 1 s through apply_damage.
    foes = _arena([_foe(Vector2(140, 192), "d1", 60)])
    foe = foes[0]
    var resist: float = float(game.combat.definition_of(foe).get("resistances", {}).get("fire", 1.0))
    StatusSystem.apply(foe, {"status": "burning", "magnitude": 2, "duration": 3})
    for _i in range(int(3.0 / FRAME) + 2):
        game.items.update(FRAME)
    check(damaged.size() == 3, "3 s of burning ticks 3 times (%d)" % damaged.size())
    var expected_hp: int = 60 - 3 * maxi(1, int(floorf(2.0 * resist)))
    check(int(foe["hp"]) == expected_hp, "burn damage went through the pipeline (HP %d, expected %d)" %
        [int(foe["hp"]), expected_hp])
    check(not StatusSystem.has_status(foe, "burning"), "the burn expired")
    StatusSystem.apply(foe, {"status": "bleeding", "magnitude": 1, "duration": 3, "stacking": "stack_count:5"})
    StatusSystem.apply(foe, {"status": "bleeding", "magnitude": 1, "duration": 3, "stacking": "stack_count:5"})
    check(int(foe["statuses"]["bleeding"]["stacks"]) == 2, "bleeding stacks")


func _test_shield_and_player_statuses() -> void:
    _arena([])
    rs.hp = rs.max_hp
    StatusSystem.apply("player", {"status": "shielded", "magnitude": 8, "duration": 5})
    var hp: int = rs.hp
    game.combat.apply_damage(game.player, 5, {"source": "rat_scavenger"})
    check(rs.hp == hp and int(rs.statuses["shielded"]["magnitude"]) == 3, "shielded absorbs 5 of 8")
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    game.combat.apply_damage(game.player, 5, {"source": "rat_scavenger"})
    check(rs.hp == hp - 2 and not rs.statuses.has("shielded"), "the rest goes to HP; empty shield removed")
    # Enemy shielded status.
    var foe: Dictionary = _arena([_foe(Vector2(140, 192), "s1", 50)])[0]
    StatusSystem.apply(foe, {"status": "shielded", "magnitude": 4, "duration": 5})
    game.combat.apply_damage(foe, 6, {"source": "player"})
    check(int(foe["hp"]) == 48, "an enemy's shielded pool absorbs too")
    # Stunned blocks actions.
    _arena([])
    StatusSystem.apply("player", {"status": "stunned"})
    check(not game.items.player_can_act(), "stunned: the crawler cannot act")
    var ticks: float = 0.0
    while game.items.player_can_act() == false and ticks < 2.0:
        game.items.update(FRAME)
        ticks += FRAME
    var wis: int = RPG.modifier(int(rs.ability_scores["WIS"]))
    check(absf(ticks - 0.6 * maxf(0.5, 1.0 - 0.1 * float(wis))) < 0.05,
        "the stun lasts 0.6 s, shortened by WIS (%.2f s)" % ticks)
    # Evasive keeps i-frames up.
    StatusSystem.apply("player", {"status": "evasive", "duration": 0.3})
    game.items.update(FRAME)
    hp = rs.hp
    check(not game.combat.hit_player(100, 6, 0, "test") and rs.hp == hp, "evasive: hits are ignored")
    game.combat.apply_damage(game.player, 4, {"source": "hazard:debris"})
    check(rs.hp == hp, "evasive ignores hazards too")
    # Concealed: enemies target the decoy and strikes miss the crawler.
    _arena([])
    game.player.world_position = Vector2(120, 120)
    rs.inventory["active"] = ""
    Inventory.acquire("itm_fan_club_decoy")
    check(game.items.use_active() and rs.statuses.has("concealed"), "the fan club conceals the crawler")
    check(StatusSystem.decoy_position().is_equal_approx(Vector2(120, 120)), "the decoy stands where it was used")
    var rat: Dictionary = _foe(Vector2(140, 120), "c1")
    rat["dormant"] = 0.0
    _arena([rat], Vector2(156, 120))
    rs.statuses = {}
    rs.hp = rs.max_hp
    StatusSystem.apply("player", {"status": "concealed", "duration": 3}, "test", {"decoy_pos": Vector2(140, 160)})
    hp = rs.hp
    for _i in range(120):
        game.player.invulnerability = 0.0
        game.player.dodge_iframes = 0.0
        game.combat.update_enemies(FRAME)
    check(Vector2(rat["pos"]).distance_to(Vector2(140, 160)) < 39.0 and rs.hp == hp,
        "the rat goes for the decoy, not the crawler next to it (rat at %s, HP %d/%d)" % [rat["pos"], rs.hp, hp])
    rs.statuses = {}
    rs.hp = rs.max_hp
    rat["pos"] = Vector2(140, 120)
    var hurt := false
    for _i in range(180):
        game.player.invulnerability = 0.0
        game.player.dodge_iframes = 0.0
        game.combat.update_enemies(FRAME)
        hurt = hurt or rs.hp < rs.max_hp
    check(hurt, "without the decoy the same rat bites the crawler")


func _test_boss_immunity_and_enemy_stun() -> void:
    var boss: Dictionary = Enemies.make_instance(game.catalogue, "armored_brute", Vector2(200, 200), 1, "", "boss_t")
    var rat: Dictionary = _foe(Vector2(100, 100), "stun_t")
    _arena([boss, rat])
    check(bool(boss["boss"]) and not StatusSystem.apply(boss, {"status": "stunned"}),
        "bosses are immune to stunned")
    StatusSystem.apply(boss, {"status": "slowed", "duration": 2.0})
    check(absf(float(boss["statuses"]["slowed"]["remaining"]) - 1.0) < 0.001, "slows last half as long on bosses")
    rat["dormant"] = 0.0
    rat["state"] = "winding_up"
    check(StatusSystem.apply(rat, {"status": "stunned"}) and rat["state"] == "stunned"
        and is_equal_approx(float(rat["state_length"]), 0.6), "a stun interrupts the wind-up (AI state stunned)")
    for i in range(7):
        StatusSystem.apply(rat, {"status": ["burning", "poisoned", "bleeding", "slowed", "hasted", "shielded", "evasive"][i]})
    check(rat["statuses"].size() == 6, "at most 6 distinct statuses (%d)" % rat["statuses"].size())


func _test_kill_and_damage_triggers() -> void:
    var foes: Array = _arena([_foe(Vector2(140, 192), "k1", 3), _foe(Vector2(200, 192), "k2", 50)])
    rs.inventory["passives"] = [{"id": "itm_vampire_straw", "count": 1}, {"id": "itm_spite_battery", "count": 1}]
    events.inventory_changed.emit()
    game.items.update(FRAME)
    rs.hp = 5
    game.combat.apply_damage(foes[0], 10, {"source": "player", "slot": "melee"})
    check(foes.size() == 1 and rs.hp == 7, "vampire straw: on_kill heals 2 (HP %d)" % rs.hp)
    var near: Dictionary = foes[0]
    near["pos"] = Vector2(130, 192)
    var before: int = int(near["hp"])
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    game.combat.apply_damage(game.player, 2, {"source": "rat_scavenger"})
    check(int(near["hp"]) == before - 3, "spite battery: on_damage_taken hits enemies within 48 px")
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    game.combat.apply_damage(game.player, 2, {"source": "rat_scavenger"})
    check(int(near["hp"]) == before - 3, "its 2 s internal cooldown holds")
    # A burn tick on the crawler does not start hit i-frames.
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    game.combat.apply_damage(game.player, 1, {"source": "status:burning"})
    check(game.player.invulnerability == 0.0, "status ticks do not grant i-frames")
    rs.inventory["passives"] = []
    events.inventory_changed.emit()


## Wave 2D merge: a dodge applies `evasive` for its i-frame window and fires
## on_dodge; the equipped weapon's pattern drives the attack move penalty; the
## weapon's knockback is applied by the finalise step.
func _test_feel_integration() -> void:
    _arena([])
    _equip("wpn_crowbar")
    rs.inventory["passives"] = [{"id": "itm_knockoff_sneakers", "count": 1}]
    rs.inventory["effect_cooldowns"] = {}
    events.inventory_changed.emit()
    game.items.recompute()
    game.player.reset(Vector2(150, 150), 105.0)
    rs.refill_stamina()
    check(game.try_dodge(Vector2.RIGHT), "the crawler can dodge")
    check(rs.statuses.has("evasive") and absf(float(rs.statuses["evasive"]["remaining"])
        - float(game.player.dodge_settings["iframes"])) < 0.001, "a dodge applies evasive for its i-frames")
    check(rs.statuses.has("hasted"), "on_dodge fires loadout effects (knockoff sneakers haste)")
    rs.inventory["passives"] = []
    events.inventory_changed.emit()
    game.items.recompute()
    game.player.reset(Vector2(150, 150), 105.0)
    rs.statuses = {}
    _equip("wpn_mop_pike")
    game.player.begin_attack(String(game.items.profile("melee")["pattern"]), 0.0, 0.1, 0.18)
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.4), "the pike's thrust slows to 40 %")
    game.player.begin_attack("melee", 0.0, 0.1, 0.18)
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.4),
        "a generic melee attack resolves the equipped weapon id's pattern")
    game.player.reset(Vector2(100, 192), 105.0)
    _equip("wpn_demolition_maul")
    var rat: Dictionary = _foe(Vector2(120, 192), "kb")
    _arena([rat])
    var profile: Dictionary = game.items.profile("melee")
    var context: Dictionary = game.combat._attack_context(profile, "melee", Vector2.RIGHT)
    var str_mod: int = maxi(0, RPG.modifier(int(rs.ability_scores["STR"])))
    check(is_equal_approx(float(context["knockback"]), 60.0 * (1.0 + 0.05 * str_mod)),
        "melee weapon knockback is STR-scaled like the default shove")
    var before: float = float(rat["pos"].x)
    game.combat.apply_damage(rat, 1, context.merged({"source": "player"}))
    check(float(rat["pos"].x) > before + 10.0, "the maul's knockback is applied (moved %.1f)"
        % (float(rat["pos"].x) - before))
    _equip("wpn_crowbar")


func _test_hazard_status() -> void:
    _arena([], Vector2(150, 150))
    rs.hp = rs.max_hp
    game.combat.spawn_hazard(Hazards.make("puddle", Vector2(150, 150), 20.0, 0.0, 2, 3.0, "spore_puffer",
        {"interval": 1.0, "status": "poisoned"}))
    game.combat.update_hazards(FRAME)
    check(rs.statuses.has("poisoned"), "a spore puddle poisons the crawler")
    _arena([], Vector2(150, 150))
    game.combat.hit_player(100, 4, 0, "lobber", 1.0, {"status": "burning"})
    check(rs.statuses.has("burning") or rs.hp == rs.max_hp, "an attack's status lands with the hit")


## Draws real frames with every Wave 2B visual on screen (draw errors would be
## SCRIPT ERRORs, which fail run_all.sh): HUD loadout panel and tooltip, item
## card, pickups and the loot box, swing shapes, beams, decoy and markers.
func _test_render() -> void:
    game.start_run(SEED)
    var foe: Dictionary = _foe(Vector2(150, 192), "r1")
    _arena([foe], Vector2(120, 192))
    Inventory.acquire("itm_safety_button")
    game.items.use_active()
    Inventory.acquire("itm_bandage_roll", Vector2.INF, 3)
    Inventory.acquire("itm_party_popper")
    StatusSystem.apply(foe, {"status": "burning"})
    StatusSystem.apply(foe, {"status": "slowed"})
    StatusSystem.apply("player", {"status": "hasted"})
    StatusSystem.apply("player", {"status": "concealed"}, "test", {"decoy_pos": Vector2(100, 100)})
    var Pickups = load("res://scripts/pickups.gd")
    Pickups.spawn("wpn_mop_pike", Vector2(120, 192), rs.current_room_id)
    Pickups.spawn(Pickups.LOOT_BOX, Vector2(200, 250), rs.current_room_id)
    Pickups.spawn("itm_bandage_roll", Vector2(250, 250), rs.current_room_id, {"count": 3})
    events.item_picked_up.emit("itm_golden_trophy")
    for pattern in ["arc", "thrust", "spin"]:
        game.combat.last_swing = {"pattern": pattern, "origin": Vector2(120, 192),
            "direction": Vector2.RIGHT, "reach": 40.0, "arc_degrees": 127.0, "width": 10.0}
        game.player.melee_flash = 0.17
        game.combat.beams.append({"from": Vector2(120, 192), "to": Vector2(300, 192), "ttl": 0.08})
        game.items.refresh_prompt()
        game._redraw()
        await process_frame
        await process_frame
    check(not game.hud.hover.is_empty() and game.items.card.current.get("id", "") != "",
        "tooltip and item card were on screen")
    var dialog_open: bool = game.services.is_modal_open()
    game.character_menu.show_pause(rs.ability_scores, game._character_context())
    game.character_menu._open_inventory_page()
    await process_frame
    check(game.character_menu.page == "inventory" and not dialog_open, "the pause menu's inventory page renders")
    game.character_menu.close_menu()
