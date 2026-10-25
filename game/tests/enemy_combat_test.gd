extends SceneTree
## Live enemy combat on Main.tscn: wind-up timing, room-entry dormancy, the
## twin_shot fix, boss phases, elite modifiers, summon caps, hazards and the
## data-driven boss_defeated signal. Frames are stepped by hand (1/60 s).
## Run: godot --headless --path game --script res://tests/enemy_combat_test.gd
## Autoloads are fetched at runtime and game scripts load()ed (see run_all.sh).
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var Enemies
var Hazards
var damage_log: Array = []
var messages: Array = []
var kills: Array = []
var bosses: Array = []


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ENEMY COMBAT: " + detail)


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    Enemies = load("res://scripts/enemy_system.gd")
    Hazards = load("res://scripts/hazards.gd")
    events.player_damaged.connect(func(amount, source): damage_log.append([amount, source]))
    events.message.connect(func(text, _category): messages.append(text))
    events.enemy_killed.connect(func(id, xp, _pos): kills.append([id, xp]))
    events.boss_defeated.connect(func(id): bosses.append(id))
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    game.start_run(SEED)
    _test_wind_up_timing()
    _test_dormancy()
    _test_twin_shot()
    _test_boss_phases()
    _test_elites()
    _test_summoner_cap()
    _test_hazards()
    _test_support_and_knockback()
    _test_boss_defeated()
    game.queue_free()
    if failures == 0:
        print("PASS: wind-ups, dormancy, twin_shot, phases, elites, summons, hazards, boss_defeated")
    quit(1 if failures > 0 else 0)


## Puts `foes` in an obstacle-free copy of the current room and resets the crawler.
func _arena(foes: Array, player_pos: Vector2) -> Array:
    var room: Dictionary = rs.current_room()
    room["blocked"] = {}
    room["enemies"] = foes
    game.combat.hazards.clear()
    game.combat.projectiles.clear()
    game.player.world_position = player_pos
    game.player.invulnerability = 0.0
    rs.hp = 500
    rs.ac = -100
    damage_log.clear()
    messages.clear()
    kills.clear()
    bosses.clear()
    return room["enemies"]


func _spawn(enemy_id: String, pos: Vector2, band: int = 1, elite: String = "", id: String = "") -> Dictionary:
    var foe: Dictionary = Enemies.make_instance(game.catalogue, enemy_id, pos, band, elite,
        id if id != "" else "%s_test" % enemy_id)
    foe["attack_cooldown"] = 0.0
    return foe


## Steps enemies and projectiles; returns the time of the first resolved enemy
## attack on the crawler (a hit or a logged miss), or -1.
func _simulate(seconds: float, keep_vulnerable: bool = true) -> float:
    var elapsed := 0.0
    var first := -1.0
    while elapsed < seconds - 0.0001:
        if keep_vulnerable:
            game.player.invulnerability = 0.0
        game.combat.update_projectiles(FRAME)
        game.combat.update_enemies(FRAME)
        elapsed += FRAME
        if first < 0.0 and (not damage_log.is_empty() or _missed()):
            first = elapsed
    return first


func _missed() -> bool:
    for text in messages:
        if String(text).begins_with("Enemy missed you"):
            return true
    return false


func _test_wind_up_timing() -> void:
    _arena([_spawn("rat_scavenger", Vector2(100, 100))], Vector2(112, 100))
    var foe: Dictionary = rs.current_room()["enemies"][0]
    var resolved: float = _simulate(0.34)
    check(resolved < 0.0 and damage_log.is_empty(), "no damage before the 0.35 s wind-up elapses")
    check(foe["state"] == "winding_up", "rat is winding up (state %s)" % foe["state"])
    resolved = _simulate(0.1)
    check(resolved >= 0.0, "bite resolves right after the wind-up")
    check(not damage_log.is_empty() and damage_log[0][1] == "rat_scavenger",
        "the bite lands and names its source: %s" % [damage_log])
    # Stepping out of reach during the wind-up makes the attack whiff.
    _arena([_spawn("rat_scavenger", Vector2(100, 100))], Vector2(112, 100))
    _simulate(0.2)
    game.player.world_position = Vector2(160, 100)
    _simulate(0.3)
    check(damage_log.is_empty() and not _missed(), "leaving the arc before resolution dodges the bite")


func _test_dormancy() -> void:
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(100, 100))
    _arena([rat], Vector2(112, 100))
    rat["pos"] = Vector2(150, 150)  # wandered off; entry resets it to its spawn point
    events.room_entered.emit(rs.current_room_id, "normal", {}, false)
    check(rat["pos"] == Vector2(100, 100) and is_equal_approx(float(rat["dormant"]), 0.6),
        "room entry resets the spawn point and starts 0.6 s of dormancy")
    var resolved: float = _simulate(0.58)
    check(resolved < 0.0 and rat["state"] == "idle", "dormant enemies neither move nor attack")
    resolved = _simulate(0.6)
    check(resolved >= 0.0, "attacks resume after dormancy and the wind-up")
    check(0.58 + resolved >= 0.6 + 0.35 - 0.02, "earliest hit is dormancy + wind-up after entry")


func _test_twin_shot() -> void:
    var spitter: Dictionary = _spawn("spitting_rat", Vector2(100, 200))
    _arena([spitter], Vector2(205, 200))
    var fired := [0]
    var counter := func(owner, _data): fired[0] += 1 if owner == "enemy" else 0
    events.projectile_fired.connect(counter)
    var resolved: float = _simulate(2.0)
    events.projectile_fired.disconnect(counter)
    check(fired[0] == 2, "twin_shot fires two projectiles (fired %d)" % fired[0])
    check(resolved >= 0.45, "a stationary crawler at the 105 px preferred range is reached (t=%.2f)" % resolved)
    var spit_hits := 0
    for entry in damage_log:
        if entry[1] == "spitting_rat":
            spit_hits += 1
    check(spit_hits >= 1 or _missed(), "the aimed shot rolls against the stationary crawler")


func _test_boss_phases() -> void:
    var brute: Dictionary = _spawn("armored_brute", Enemies.MID, 1, "", "boss_test")
    _arena([brute], Vector2(40, 40))
    game.combat.projectiles.append({"pos": Vector2(50, 50), "velocity": Vector2.ZERO, "ttl": 5.0,
        "owner": "enemy", "die": 4, "bonus": 0, "attack_bonus": 0, "source": "test"})
    check(game.combat.apply_damage(brute, 21) == 21 and int(brute["phase"]) == 0,
        "brute stays in phase 1 at exactly 50 %")
    game.combat.apply_damage(brute, 1)
    check(int(brute["phase"]) == 1, "brute enters phase 2 below 50 %")
    check(float(brute["invulnerable"]) > 0.0 and game.combat.projectiles.is_empty(),
        "phase change roars and clears hostile projectiles")
    check(messages.back().contains("charging"), "phase announcement: %s" % messages.back())
    check(game.combat.apply_damage(brute, 5) == 0 and int(brute["hp"]) == 20, "roar is invulnerable")
    check(Enemies.active_attack_ids(brute, game.catalogue["enemies"]["armored_brute"])[0]
        == "shoulder_charge", "phase 2 adds the shoulder charge")
    var warden: Dictionary = _spawn("sump_warden", Enemies.MID, 2, "", "warden_test")
    _arena([warden], Vector2(40, 40))
    game.combat.apply_damage(warden, 36)
    check(int(warden["phase"]) == 0, "warden phase 1 at 60 %")
    game.combat.apply_damage(warden, 1)
    check(int(warden["phase"]) == 1, "warden phase 2 below 60 %")
    warden["invulnerable"] = 0.0
    game.combat.apply_damage(warden, 31)
    check(int(warden["phase"]) == 2 and int(warden["hp"]) == 22, "warden phase 3 below 25 %")


func _test_elites() -> void:
    var guard: Dictionary = _spawn("rat_scavenger", Vector2(300, 300), 3, "bulwark")
    _arena([guard], Vector2(40, 40))
    var hp: int = int(guard["hp"])
    check(game.combat.apply_damage(guard, 5) == 0 and int(guard["hp"]) == hp and int(guard["shield"]) == 3,
        "bulwark shield absorbs damage first")
    game.combat.apply_damage(guard, 5)
    check(int(guard["hp"]) == hp - 2 and int(guard["shield"]) == 0, "overflow reaches HP")
    _simulate(4.2)
    check(int(guard["shield"]) == 8, "bulwark shield regenerates after 4 s without damage")
    var bomb: Dictionary = _spawn("rat_scavenger", Vector2(300, 300), 3, "volatile")
    _arena([bomb], Vector2(40, 40))
    game.combat.apply_damage(bomb, 999)
    check(game.combat.hazards.size() == 1, "volatile elites leave a death burst")
    if game.combat.hazards.size() == 1:
        var burst: Dictionary = game.combat.hazards[0]
        check(is_equal_approx(float(burst["telegraph_remaining"]), 0.8) and bool(burst["hits_enemies"])
            and int(burst["damage"]) >= 2 and int(burst["damage"]) <= 12, "burst: 0.8 s telegraph, 2d6, hits enemies")
    check(kills == [["rat_scavenger", int(bomb["xp"])]] and int(bomb["xp"]) > 56,
        "elite XP awarded on kill")


func _summon_positions() -> Array:
    var mother: Dictionary = _spawn("nest_mother", Vector2(200, 200), 2, "", "9_0")
    mother["rng_seed"] = 4242
    var foes: Array = _arena([mother], Vector2(40, 40))
    var squeal: Dictionary = Enemies.attack_by_id(game.catalogue["enemies"]["nest_mother"], "squeal")
    for _i in range(4):
        game.combat._summon(mother, squeal)
    var spots: Array = []
    for foe in foes:
        if foe["summoner"] == "9_0":
            spots.append(foe["pos"])
            check(int(foe["xp"]) == 0, "summons are worth 0 XP")
    return spots


func _test_summoner_cap() -> void:
    var spots: Array = _summon_positions()
    check(spots.size() == 4, "summoner cap of 4 alive pups (got %d)" % spots.size())
    check(spots == _summon_positions(), "summon positions are deterministic")
    var foes: Array = rs.current_room()["enemies"]
    var mother: Dictionary = foes[0]
    var cleared := [false]
    var on_clear := func(_id): cleared[0] = true
    events.room_cleared.connect(on_clear)
    game.combat.apply_damage(mother, 999)
    events.room_cleared.disconnect(on_clear)
    check(foes.is_empty() and cleared[0], "pups die with the summoner and the room clears")
    var pup_kills := 0
    for kill in kills:
        if kill[0] == "rat_pup":
            pup_kills += 1
            check(int(kill[1]) == 0, "pup deaths give no XP")
    check(pup_kills == 4, "every pup death is announced")
    # Room-wide cap: two summoners share at most 6 summons.
    var a: Dictionary = _spawn("nest_mother", Vector2(200, 200), 2, "", "9_1")
    var b: Dictionary = _spawn("nest_mother", Vector2(100, 300), 2, "", "9_2")
    foes = _arena([a, b], Vector2(40, 40))
    var squeal: Dictionary = Enemies.attack_by_id(game.catalogue["enemies"]["nest_mother"], "squeal")
    for _i in range(4):
        game.combat._summon(a, squeal)
        game.combat._summon(b, squeal)
    check(foes.size() == 2 + 6, "room summon cap of 6 (got %d)" % (foes.size() - 2))


func _test_hazards() -> void:
    _arena([], Vector2(100, 100))
    game.combat.spawn_hazard(Hazards.make("puddle", Vector2(100, 100), 32.0, 0.0, 2, 3.0,
        "spore_puffer", {"interval": 1.0, "status": "poisoned"}))
    for _i in range(190):
        game.player.invulnerability = 0.0
        game.combat.update_hazards(FRAME)
    check(damage_log.size() == 3 and damage_log[0] == [2, "spore_puffer"],
        "puddle pulses once per second for 3 s: %s" % [damage_log])
    check(game.combat.hazards.is_empty(), "expired hazards are removed")
    _arena([], Vector2(100, 100))
    game.combat.spawn_hazard(Hazards.make("puddle", Vector2(100, 100), 22.0, 0.9, 6, 0.0, "lobber"))
    for _i in range(53):
        game.combat.update_hazards(FRAME)
    check(damage_log.is_empty(), "no damage while the ground circle is telegraphing")
    for _i in range(3):
        game.combat.update_hazards(FRAME)
    check(damage_log == [[6, "lobber"]] and game.combat.hazards.is_empty(), "bomb bursts once on landing")
    # A zoner drops its puddle into combat.hazards through its own attack.
    var puffer: Dictionary = _spawn("spore_puffer", Vector2(100, 100), 2)
    _arena([puffer], Vector2(120, 100))
    _simulate(0.7, false)
    check(game.combat.hazards.size() == 1 and game.combat.hazards[0]["source"] == "spore_puffer"
        and float(game.combat.hazards[0]["radius"]) == 32.0
        and float(game.combat.hazards[0]["interval"]) == 1.0, "spore puffer drops a 32 px puddle (hazards.gd entry)")


func _test_support_and_knockback() -> void:
    var acolyte: Dictionary = _spawn("bell_acolyte", Vector2(200, 200), 3)
    var ally: Dictionary = _spawn("rat_scavenger", Vector2(220, 200), 3, "", "ally")
    _arena([acolyte, ally], Vector2(360, 360))
    game.combat._support(acolyte, Enemies.attack_by_id(game.catalogue["enemies"]["bell_acolyte"], "ward_peal"))
    check(int(ally["ward"]) == 6 and int(acolyte.get("ward", 0)) == 0, "ward peal shields allies, not itself")
    var hp: int = int(ally["hp"])
    game.combat.apply_damage(ally, 4)
    check(int(ally["hp"]) == hp and int(ally["ward"]) == 2, "ward absorbs damage")
    # A natural 1 always misses, so retry until one slam lands (bounded).
    var landed := false
    for _attempt in range(6):
        var golem: Dictionary = _spawn("rubble_golem", Vector2(100, 100), 3)
        _arena([golem], Vector2(118, 100))
        var resolved: float = _simulate(0.8)
        check(resolved >= 0.7 - 0.02, "golem slam resolves after its 0.7 s wind-up")
        if not damage_log.is_empty():
            landed = true
            break
    check(landed, "a golem slam lands")
    check(game.player.world_position.x > 140.0, "slam knocks the crawler back (x=%.1f)" % game.player.world_position.x)


func _test_boss_defeated() -> void:
    for boss_id in ["armored_brute", "sump_warden"]:
        var boss: Dictionary = _spawn(boss_id, Enemies.MID, 2 if boss_id == "sump_warden" else 1)
        _arena([boss], Vector2(40, 40))
        rs.boss_defeated = false
        game.combat.apply_damage(boss, 9999)
        check(bosses == [boss_id] and rs.boss_defeated, "boss_defeated fires for %s" % boss_id)
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(200, 200))
    _arena([rat], Vector2(40, 40))
    rs.boss_defeated = false
    game.combat.apply_damage(rat, 999)
    check(bosses.is_empty() and not rs.boss_defeated, "normal kills do not unlock the exit")
