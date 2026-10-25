extends SceneTree
## Wave 2D combat feel on Main.tscn: dodge roll distance, timing and i-frames,
## stamina cost / delay / regen and the two-chain rule, dodge refusals,
## knockback (resistance, walls, interrupts, boss cap, the crawler), the D-07
## door lock (timing, kinds, unlock on clear and grace, the dodge and door
## refusal), the unreachable-enemy failsafe, hit-stop freezing the simulation,
## damage numbers and the settings gate, and attack movement penalties.
## Frames are stepped by hand (1/60 s).
## Run: godot --headless --path game --script res://tests/combat_feel_test.gd
## Autoloads are fetched at runtime and game scripts load()ed (see run_all.sh);
## fx.gd is pure and may be preloaded.
const Fx = preload("res://scripts/fx.gd")
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var Enemies
var DoorLock
var Settings
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL COMBAT FEEL: " + detail)


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    Enemies = load("res://scripts/enemy_system.gd")
    DoorLock = load("res://scripts/door_lock.gd")
    Settings = load("res://scripts/core/settings.gd")
    for name in ["dodged", "stamina_changed", "doors_locked", "doors_unlocked", "enemy_killed",
            "announcement_requested"]:
        seen[name] = []
    events.dodged.connect(func(direction): seen["dodged"].append(direction))
    events.stamina_changed.connect(func(current, maximum): seen["stamina_changed"].append([current, maximum]))
    events.doors_locked.connect(func(id): seen["doors_locked"].append(id))
    events.doors_unlocked.connect(func(id, reason): seen["doors_unlocked"].append([id, reason]))
    events.enemy_killed.connect(func(id, xp, _pos): seen["enemy_killed"].append([id, xp]))
    events.announcement_requested.connect(func(trigger, _context): seen["announcement_requested"].append(trigger))
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    game.start_run(SEED)
    _test_dodge_distance_and_iframes()
    _test_stamina()
    _test_dodge_refusals()
    _test_knockback()
    _test_hitstop()
    _test_numbers_and_feedback()
    _test_move_penalties()
    _test_door_lock_kinds()
    _test_door_lock_timing_and_clear()
    _test_locked_door_blocks_dodge()
    _test_failsafe()
    game.queue_free()
    if failures == 0:
        print("PASS: dodge, i-frames, stamina, knockback, hit-stop, numbers, move penalties, door lock, failsafe")
    quit(1 if failures > 0 else 0)


## An obstacle-free copy of the current room holding `foes`, crawler at `player_pos`.
func _arena(foes: Array, player_pos: Vector2) -> Array:
    var room: Dictionary = rs.current_room()
    room["blocked"] = {}
    room["enemies"] = foes
    game.combat.hazards.clear()
    game.combat.projectiles.clear()
    game.combat.hitstop = 0.0
    game.combat.fx.clear()
    game.player.reset(player_pos, 105.0)
    rs.xp = 0
    rs.hp = 500
    rs.max_hp = 500
    rs.refill_stamina()
    for name in seen:
        seen[name].clear()
    return room["enemies"]


func _spawn(enemy_id: String, pos: Vector2, id: String = "", band: int = 1) -> Dictionary:
    var foe: Dictionary = Enemies.make_instance(game.catalogue, enemy_id, pos, band, "",
        id if id != "" else "%s_feel" % enemy_id)
    foe["dormant"] = 999.0
    return foe


func _frames(count: int) -> void:
    for _i in range(count):
        game._physics_process(FRAME)


func _test_dodge_distance_and_iframes() -> void:
    _arena([], Vector2(100, 192))
    check(game.try_dodge(Vector2.RIGHT), "a dodge starts from full stamina")
    check(is_equal_approx(rs.stamina, 65.0), "a dodge costs 35 stamina (left %.1f)" % rs.stamina)
    check(seen["dodged"].size() == 1 and seen["dodged"][0] == Vector2.RIGHT,
        "Events.dodged fires with the roll direction: %s" % [seen["dodged"]])
    check(int(rs.telemetry["dodges"]) >= 1, "dodges telemetry counts the roll")
    _frames(11)
    check(game.player.is_dodging() and game.player.world_position.x < 148.0,
        "still rolling at 0.18 s (x=%.2f)" % game.player.world_position.x)
    check(game.combat.apply_damage(game.player, 3, {"source": "test"}) == 0,
        "i-frames block damage at 0.18 s")
    check(not game.combat.hit_player(100, 6, 0, "test"), "hit_player is refused during i-frames")
    _frames(2)
    check(game.player.dodge_iframes <= 0.0, "i-frames end after 0.20 s")
    check(game.combat.apply_damage(game.player, 3, {"source": "test"}) == 3,
        "damage lands after the i-frame window (0.22 s, still rolling)")
    game.player.invulnerability = 0.0
    game.combat.hitstop = 0.0
    _frames(3)
    check(not game.player.is_dodging(), "the roll ends at 0.25 s")
    check(absf(game.player.world_position.x - 148.0) < 0.05 and is_equal_approx(game.player.world_position.y, 192.0),
        "the roll covers 48 px (x=%.3f)" % game.player.world_position.x)
    check(game.player.attack_locked() and not game.player.can_dodge(), "0.10 s recovery: no attack, no dodge")
    _frames(7)
    check(not game.player.attack_locked() and game.player.can_dodge(), "recovery over after 0.10 s")
    # Standing still rolls along the aim; obstacles stop it and it slides along walls.
    _arena([], Vector2(100, 192))
    game.player.aim_direction = Vector2.UP
    game.player.aim_at(Vector2(100, 100))
    var start: Vector2 = game.player.world_position
    game.try_dodge(Vector2.ZERO)
    check(game.player.dodge_direction.is_equal_approx(Vector2.UP), "a still crawler rolls along its aim")
    _frames(20)
    check(game.player.world_position.y < start.y - 40.0, "the aim roll travels (y=%.1f)" % game.player.world_position.y)
    _arena([], Vector2(100, 192))
    rs.current_room()["blocked"] = {Vector2i(7, 12): true, Vector2i(7, 11): true, Vector2i(7, 13): true}
    game.try_dodge(Vector2(1, 1).normalized())
    _frames(20)
    check(game.player.world_position.x < 106.6 and game.player.world_position.y > 210.0,
        "a diagonal roll into an obstacle slides along it (%s)" % game.player.world_position)
    # Enemies do not stop a roll.
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(124, 192))
    _arena([rat], Vector2(100, 192))
    game.try_dodge(Vector2.RIGHT)
    _frames(20)
    check(game.player.world_position.x > 147.0, "the roll passes through enemies")


func _test_stamina() -> void:
    _arena([], Vector2(192, 192))
    check(is_equal_approx(rs.max_stamina, 100.0) and is_equal_approx(rs.stamina, 100.0), "stamina pool 100")
    check(is_equal_approx(rs.stamina_regen_rate(), 33.0), "regen 30/s +10 %% for WIS 12 (+1): %.2f" % rs.stamina_regen_rate())
    check(rs.spend_stamina(35.0) and is_equal_approx(rs.stamina, 65.0), "spend_stamina spends")
    check(not rs.spend_stamina(70.0) and is_equal_approx(rs.stamina, 65.0), "spend_stamina refuses an overdraft")
    rs.stamina_idle = 0.0
    for _i in range(30):
        rs.regen_stamina(FRAME)
    check(is_equal_approx(rs.stamina, 65.0), "no regen during the 0.6 s delay")
    for _i in range(12):
        rs.regen_stamina(FRAME)
    check(rs.stamina > 65.0 and rs.stamina < 72.0, "regen after the delay (%.2f)" % rs.stamina)
    check(not seen["stamina_changed"].is_empty(), "stamina_changed fires")
    # Two-chain rule: from full, two rolls back to back, the third ~0.75 s later.
    _arena([], Vector2(60, 192))
    check(game.try_dodge(Vector2.RIGHT), "first chained dodge")
    var elapsed := 0.0
    while not game.try_dodge(Vector2.RIGHT) and elapsed < 1.0:
        _frames(1)
        elapsed += FRAME
    check(absf(elapsed - 0.35) < 0.02, "second dodge as soon as roll + recovery end (%.3f s)" % elapsed)
    check(is_equal_approx(rs.stamina, 30.0), "two dodges leave 30 stamina")
    game.player.world_position = Vector2(60, 192)
    elapsed = 0.0
    while not game.try_dodge(Vector2.RIGHT) and elapsed < 2.0:
        _frames(1)
        elapsed += FRAME
    check(absf(elapsed - 0.75) < 0.04, "third dodge ~0.75 s after the second (%.3f s)" % elapsed)
    # Stamina regen waits while the game is not RUNNING.
    _arena([], Vector2(192, 192))
    rs.stamina = 10.0
    rs.stamina_idle = 5.0
    game._change_state(game.State.PAUSED)
    game._physics_process(0.5)
    check(is_equal_approx(rs.stamina, 10.0), "no regen while paused")
    game._change_state(game.State.RUNNING)


func _test_dodge_refusals() -> void:
    _arena([], Vector2(192, 192))
    rs.stamina = 0.0
    check(not game.try_dodge(Vector2.RIGHT) and not game.player.is_dodging(), "no dodge at 0 stamina")
    rs.stamina = 34.0
    check(not game.try_dodge(Vector2.RIGHT), "no dodge below the 35 cost")
    rs.refill_stamina()
    game.player.begin_attack("thrust", 0.12, 0.08, 0.2)
    check(not game.try_dodge(Vector2.RIGHT), "no dodge during an attack wind-up")
    game.player.tick_timers(0.13)
    check(game.player.attack_phase() == "active" and not game.try_dodge(Vector2.RIGHT),
        "no dodge during active frames")
    game.player.tick_timers(0.08)
    check(game.player.attack_phase() == "recovery", "recovery after active")
    check(game.try_dodge(Vector2.RIGHT), "a dodge cancels attack recovery")
    check(game.player.attack_phase() == "" and game.player.attack_recovery == 0.0, "recovery cancelled")
    _arena([], Vector2(192, 192))
    game.player.dodge_gap = 0.5
    game.try_dodge(Vector2.RIGHT)
    _frames(22)
    check(not game.try_dodge(Vector2.RIGHT), "dodge_cooldown stat adds a minimum gap")
    _frames(10)
    check(game.try_dodge(Vector2.RIGHT), "dodge allowed after the dodge_cooldown gap")
    game.player.dodge_gap = 0.0


func _test_knockback() -> void:
    var cases := [["rat_scavenger", 20.0], ["hulking_rat", 15.0], ["rubble_golem", 5.0]]
    for entry in cases:
        var foe: Dictionary = _spawn(String(entry[0]), Vector2(200, 192))
        _arena([foe], Vector2(160, 192))
        game.combat.apply_damage(foe, 1, {"source": "player", "knockback": 20.0, "direction": Vector2.RIGHT})
        var moved: float = float(foe["pos"].x) - 200.0
        check(absf(moved - float(entry[1])) < 0.6, "%s knocked back %.1f px (want %.1f)" % [entry[0], moved, entry[1]])
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(200, 192))
    _arena([rat], Vector2(160, 192))
    game.combat.apply_damage(rat, 1, {"source": "player", "slot": "melee", "direction": Vector2.RIGHT})
    check(absf(float(rat["pos"].x) - 222.0) < 0.6,
        "melee default knockback 20 px +5 %% per STR mod (x=%.1f)" % float(rat["pos"].x))
    rat = _spawn("rat_scavenger", Vector2(200, 192))
    _arena([rat], Vector2(160, 192))
    game.combat.apply_damage(rat, 1, {"source": "player", "slot": "ranged", "direction": Vector2.RIGHT})
    check(rat["pos"] == Vector2(200, 192), "ranged hits without a knockback value do not push")
    # Walls and obstacles stop it; no wall-slam damage.
    rat = _spawn("rat_scavenger", Vector2(370, 192))
    _arena([rat], Vector2(330, 192))
    var hp: int = int(rat["hp"])
    game.combat.apply_damage(rat, 1, {"source": "player", "knockback": 40.0, "direction": Vector2.RIGHT})
    check(float(rat["pos"].x) <= 384.0 - float(rat["radius"]) + 0.01 and float(rat["pos"].x) > 370.0,
        "the room wall stops knockback (x=%.1f)" % float(rat["pos"].x))
    check(int(rat["hp"]) == hp - 1, "wall slam deals no damage")
    rat = _spawn("rat_scavenger", Vector2(200, 200))
    _arena([rat], Vector2(160, 200))
    rs.current_room()["blocked"] = {Vector2i(13, 12): true}
    game.combat.apply_damage(rat, 1, {"source": "player", "knockback": 40.0, "direction": Vector2.RIGHT})
    check(float(rat["pos"].x) < 208.0 - float(rat["radius"]) + 0.01, "an obstacle stops knockback (x=%.1f)" % float(rat["pos"].x))
    # Interruptible wind-ups break; others keep going.
    var acolyte: Dictionary = _spawn("bell_acolyte", Vector2(200, 192))
    var biter: Dictionary = _spawn("rat_scavenger", Vector2(100, 100), "biter")
    _arena([acolyte, biter], Vector2(160, 192))
    acolyte["state"] = "winding_up"
    acolyte["attack"] = "ward_peal"
    biter["state"] = "winding_up"
    biter["attack"] = "bite"
    game.combat.apply_damage(acolyte, 1, {"source": "player", "knockback": 10.0, "direction": Vector2.RIGHT})
    game.combat.apply_damage(biter, 1, {"source": "player", "knockback": 10.0, "direction": Vector2.RIGHT})
    check(acolyte["state"] == "recovery", "knockback interrupts an interruptible wind-up")
    check(biter["state"] == "winding_up", "a non-interruptible wind-up continues")
    # Bosses: at most x0.25 (definition boss_knockback_mult overrides).
    var brute: Dictionary = _spawn("armored_brute", Vector2(192, 192), "brute")
    _arena([brute], Vector2(120, 192))
    game.combat.apply_damage(brute, 1, {"source": "player", "knockback": 40.0, "direction": Vector2.RIGHT})
    check(absf(float(brute["pos"].x) - 202.0) < 0.6, "boss knockback x0.25 (moved %.1f)" % (float(brute["pos"].x) - 192.0))
    var warden: Dictionary = _spawn("sump_warden", Vector2(192, 192), "warden", 2)
    _arena([warden], Vector2(120, 192))
    game.combat.apply_damage(warden, 1, {"source": "player", "knockback": 40.0, "direction": Vector2.RIGHT})
    check(warden["pos"] == Vector2(192, 192), "an immune boss stays put")
    # The crawler: pushed along the direction, stopped by obstacles.
    _arena([], Vector2(192, 192))
    game.combat.apply_damage(game.player, 1, {"source": "test", "knockback": 30.0, "direction": Vector2.LEFT})
    check(absf(game.player.world_position.x - 162.0) < 0.6, "crawler knockback (x=%.1f)" % game.player.world_position.x)
    _arena([], Vector2(192, 192))
    rs.current_room()["blocked"] = {Vector2i(10, 12): true}
    game.combat.apply_damage(game.player, 1, {"source": "test", "knockback": 30.0, "origin": Vector2(220, 192)})
    check(game.player.world_position.x >= 176.0 + 5.5 - 0.01 and game.player.world_position.x < 192.0,
        "an obstacle stops the crawler's knockback (x=%.1f)" % game.player.world_position.x)


func _test_hitstop() -> void:
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(170, 192))
    rat["dormant"] = 0.0
    rat["attack_cooldown"] = 50.0
    _arena([rat], Vector2(100, 192))
    var before_time: float = float(rs.telemetry["run_time_seconds"])
    _frames(2)
    var moving: Vector2 = rat["pos"]
    check(moving != Vector2(170, 192), "the rat chases before the stop")
    game.combat.hitstop = 0.09
    var clock: float = float(rs.telemetry["run_time_seconds"])
    _frames(5)
    check(rat["pos"] == moving and is_equal_approx(float(rs.telemetry["run_time_seconds"]), clock),
        "hit-stop freezes enemies and the run clock")
    _frames(1)
    var used: float = float(rs.telemetry["run_time_seconds"]) - clock
    check(used > 0.0 and used < FRAME, "the frame that ends the stop simulates only its remainder (%.4f)" % used)
    check(float(rs.telemetry["run_time_seconds"]) > before_time, "time advances again")
    # Cues and the 120 ms per 0.5 s budget.
    var fx = Fx.new()
    check(is_equal_approx(fx.hitstop_for("hit"), 0.04), "hit 40 ms")
    fx.hitstop = 0.0
    check(is_equal_approx(fx.hitstop_for("kill"), 0.08), "kill tops up to the 120 ms budget only")
    fx.hitstop = 0.0
    check(fx.hitstop_for("crit") == 0.0, "budget spent inside the window")
    fx.update(0.6)
    check(is_equal_approx(fx.hitstop_for("crit"), 0.07), "budget refills after 0.5 s: crit 70 ms")
    check(is_equal_approx(fx.hitstop_for("room_clear"), 0.05), "room clear is forced past the budget (to 120 ms)")
    # A kill by the crawler stops time for 90 ms.
    rat = _spawn("rat_scavenger", Vector2(300, 192))
    _arena([rat], Vector2(100, 192))
    game.combat.fx = Fx.new()
    game.combat.apply_damage(rat, 99, {"source": "player"})
    check(is_equal_approx(game.combat.hitstop, 0.09), "kill hit-stop 90 ms (%.3f)" % game.combat.hitstop)
    var phase_boss: Dictionary = _spawn("armored_brute", Vector2(192, 192), "phase_boss")
    _arena([phase_boss], Vector2(100, 192))
    game.combat.fx = Fx.new()
    game.combat.apply_damage(phase_boss, 22, {"source": "test"})
    check(int(phase_boss["phase"]) == 1 and is_equal_approx(game.combat.hitstop, 0.09),
        "boss phase change: 90 ms hit-stop")
    check(game.combat.fx.current_shake() >= 3.9 * game.combat.fx.shake_scale, "boss phase change: heavy shake")
    game.combat.fx = Fx.new()
    game.combat._sync_settings()


func _test_numbers_and_feedback() -> void:
    var settings = Settings.shared()
    var rat: Dictionary = _spawn("rat_scavenger", Vector2(200, 192), "num_rat")
    _arena([rat], Vector2(160, 192))
    settings.show_damage_numbers = false
    events.settings_changed.emit(settings.to_dict())
    game.combat.apply_damage(rat, 1, {"source": "player"})
    check(game.combat.fx.numbers.is_empty(), "no damage numbers when the setting is off")
    check(game.combat.fx.flash_amount("num_rat") > 0.0, "the hit flashes the enemy anyway")
    settings.show_damage_numbers = true
    events.settings_changed.emit(settings.to_dict())
    game.combat.apply_damage(rat, 2, {"source": "player"})
    check(game.combat.fx.numbers.size() == 1 and game.combat.fx.numbers[0]["text"] == "2",
        "a damage number when the setting is on")
    game.combat.apply_damage(rat, 1, {"source": "player"})
    check(game.combat.fx.numbers.size() == 1 and game.combat.fx.numbers[0]["text"] == "3",
        "numbers on one target within 0.1 s merge")
    game.combat.fx.clear()
    game.combat.apply_damage(rat, 1, {"source": "status:poisoned"})
    check(game.combat.fx.numbers.size() == 1 and game.combat.fx.numbers[0]["style"] == "dot"
        and int(game.combat.fx.numbers[0]["size"]) < int(Fx.STYLES["normal"]["size"]), "DoT numbers are small")
    check(Fx.STYLES["crit"]["size"] > Fx.STYLES["normal"]["size"], "crit numbers are bigger")
    game.combat.fx.clear()
    rat["hp"] = 500
    var missed := false
    for _i in range(8):
        game.combat.hit_enemy(0, -100, 6, 0)
        for entry in game.combat.fx.numbers:
            if entry["text"] == "MISS":
                missed = true
                check(entry["style"] == "miss" and entry["color"] == Fx.STYLES["miss"]["color"], "MISS is grey")
        if missed:
            break
    check(missed, "a miss shows MISS")
    # Kills burst, the crawler flashes, shakes respect the setting.
    game.combat.apply_damage(rat, 9999, {"source": "player"})
    check(game.combat.fx.bursts.size() == 1 and game.combat.fx.bursts[0]["particles"].size() >= 6,
        "a kill leaves a death burst")
    settings.screen_shake = 0.0
    events.settings_changed.emit(settings.to_dict())
    game.combat.apply_damage(game.player, 1, {"source": "test"})
    check(game.combat.fx.flash_amount("player") > 0.0, "the crawler flashes when hit")
    check(game.combat.fx.shake_offset() == Vector2.ZERO, "screen shake 0 turns shake off")
    settings.screen_shake = 1.0
    events.settings_changed.emit(settings.to_dict())
    check(game.combat.fx.current_shake() > 1.0, "medium shake on crawler damage at full setting")


func _test_move_penalties() -> void:
    _arena([], Vector2(192, 192))
    var player = game.player
    check(is_equal_approx(game.combat.player_move_multiplier(), 1.0), "full speed when not attacking")
    player.begin_attack("melee", 0.0, 0.1, 0.18)
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.6), "melee without a weapon record = arc 60 %")
    rs.inventory = {"melee": {"id": "wpn_mop_pike", "attack_pattern": "thrust"}}
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.4), "thrust 40 % from the inventory weapon")
    rs.inventory = {"weapons": {"melee": {"attack_pattern": "spin"}}}
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.5), "spin 50 %")
    rs.inventory = {}
    player.begin_attack("ranged", 0.0, 0.0, 0.28)
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.85), "ranged 85 %")
    player.begin_attack("spread", 0.0, 0.0, 0.28)
    check(is_equal_approx(game.combat.player_move_multiplier(), 0.85), "every ranged pattern 85 %")
    player.tick_timers(0.3)
    check(is_equal_approx(game.combat.player_move_multiplier(), 1.0), "full speed after recovery")
    # Live frame: the penalty slows real movement.
    player.begin_attack("melee", 0.0, 0.1, 0.18)
    Input.action_press("move_right")
    _frames(1)
    Input.action_release("move_right")
    var moved: float = player.world_position.x - 192.0
    check(absf(moved - 105.0 * 0.6 * FRAME) < 0.01, "attacking crawler moves at 60 %% (%.3f px)" % moved)


func _test_door_lock_kinds() -> void:
    var kinds: Array = DoorLock.DEFAULTS["locking_kinds"]
    var hostile := [{"hp": 5}]
    for kind in ["normal", "elite", "boss", "trap"]:
        check(DoorLock.kind_locks(kind, hostile, kinds), "%s locks with hostiles" % kind)
        check(not DoorLock.kind_locks(kind, [], kinds), "%s without hostiles never locks" % kind)
    for kind in ["start", "guild_hall", "exit", "treasure", "shrine"]:
        check(not DoorLock.kind_locks(kind, hostile, kinds), "%s never locks" % kind)
    var links := {"N": 1, "W": 2}
    check(not DoorLock.is_inside(Vector2(192, 21), links, 24.0), "21 px from the N door is not inside")
    check(DoorLock.is_inside(Vector2(192, 25), links, 24.0), "25 px from the N door is inside")
    check(DoorLock.is_inside(Vector2(192, 380), links, 24.0), "unlinked walls do not count")


## Enters the first normal neighbour of the start room on a fresh run.
func _enter_normal_room() -> String:
    game.start_run(SEED)
    var rooms: Array = rs.floor["rooms"]
    for direction in ["N", "E", "S", "W"]:
        var here: Dictionary = rooms[rs.current_room_id]
        if here["neighbors"].has(direction) and rooms[int(here["neighbors"][direction])]["kind"] == "normal":
            game._enter_neighbor(direction)
            for foe in rs.current_room()["enemies"]:
                foe["dormant"] = 999.0
            rs.hp = 500
            rs.max_hp = 500
            for name in seen:
                seen[name].clear()
            return direction
    check(false, "no normal room next to the start room")
    return ""


func _test_door_lock_timing_and_clear() -> void:
    _enter_normal_room()
    var lock = game.door_lock
    check(lock.lockable and not lock.locked, "a normal room with hostiles is lockable, open on entry")
    for _i in range(60):
        lock.update(FRAME)
    check(not lock.locked, "no lock while the crawler stands in the doorway (21 px)")
    game.player.world_position = Vector2(192, 192)
    lock.update(FRAME)
    check(lock.locked and lock.is_locked(), "locks once the crawler is 24 px inside after 0.5 s")
    check(seen["doors_locked"] == [rs.current_room_id], "doors_locked(room_id) fires once")
    # Fresh entry with the crawler already inside: exactly 0.5 s.
    events.room_entered.emit(rs.current_room_id, "normal", {}, false)
    for foe in rs.current_room()["enemies"]:
        foe["dormant"] = 999.0
    game.player.world_position = Vector2(192, 192)
    for _i in range(29):
        lock.update(FRAME)
    check(not lock.locked, "still open at 0.48 s")
    lock.update(FRAME)
    lock.update(FRAME)
    check(lock.locked, "sealed by 0.5 s after entry")
    # Grace opens the doors and wins over the lock.
    rs.grace["active"] = true
    check(not lock.is_locked(), "collapse grace unlocks the doors")
    lock.update(FRAME)
    check(not lock.locked and seen["doors_unlocked"].back()[1] == "grace", "grace emits doors_unlocked(grace)")
    rs.grace["active"] = false
    lock.update(FRAME)
    check(lock.locked, "doors seal again once grace is over and the fight goes on")
    for _i in range(20):
        lock.update(FRAME)
    check(is_equal_approx(lock.visual, 1.0), "sealed doors are fully tinted")
    # Summons count until summoner and summons are dead; then the room-clear moment.
    var mother: Dictionary = _spawn("nest_mother", Vector2(250, 250), "mother")
    var foes: Array = rs.current_room()["enemies"]
    foes.clear()
    foes.append(mother)
    var squeal: Dictionary = Enemies.attack_by_id(game.catalogue["enemies"]["nest_mother"], "squeal")
    game.combat._summon(mother, squeal)
    check(foes.size() >= 2, "the mother summoned pups")
    game.combat.apply_damage(foes[1], 999, {"source": "player"})
    check(lock.is_locked(), "killing a summon alone keeps the doors sealed")
    seen["announcement_requested"].clear()
    game.combat.fx = Fx.new()
    game.combat.apply_damage(mother, 999, {"source": "player"})
    check(foes.is_empty() and not lock.is_locked(), "summoner and summons dead: doors open")
    check(seen["doors_unlocked"].back() == [rs.current_room_id, "cleared"], "doors_unlocked(cleared)")
    check(game.hud.room_clear_left > 0.0, "the HUD shows the ROOM CLEAR flourish")
    check(game.combat.hitstop >= 0.119, "room clear forces a brief hit-stop (%.3f)" % game.combat.hitstop)
    check(seen["announcement_requested"].has("room_cleared"), "the announcer is asked for a room_cleared line")
    for _i in range(10):
        lock.update(FRAME)
    check(lock.visual > 0.0 and lock.visual < 1.0, "doors fade open (visual %.2f)" % lock.visual)
    for _i in range(30):
        lock.update(FRAME)
    check(lock.visual == 0.0, "doors fully open after the fade")
    game.combat.fx = Fx.new()
    game.combat._sync_settings()


func _test_locked_door_blocks_dodge() -> void:
    var entered: String = _enter_normal_room()
    var lock = game.door_lock
    game.player.world_position = Vector2(192, 192)
    for _i in range(40):
        lock.update(FRAME)
    check(lock.is_locked(), "sealed for the door test")
    var room_id: int = rs.current_room_id
    var back: String = {"N": "S", "S": "N", "E": "W", "W": "E"}[entered]
    var portal: Vector2 = Enemies.PORTAL_CENTERS[back]
    var inward: Vector2 = (Vector2(192, 192) - portal).normalized()
    game.player.world_position = portal + inward * 30.0
    game.combat.hitstop = 0.0
    rs.refill_stamina()
    check(game.try_dodge(-inward), "dodge toward the sealed door")
    _frames(25)
    check(rs.current_room_id == room_id, "a dodge cannot pass a locked door")
    check(lock.prompt() == "Sealed until clear" and game.hud.prompt == "Sealed until clear",
        "bumping a sealed door prompts 'Sealed until clear'")
    game._enter_neighbor(back)
    check(rs.current_room_id == room_id, "_enter_neighbor refuses while sealed")
    rs.grace["active"] = true
    game._enter_neighbor(back)
    check(rs.current_room_id != room_id, "grace unlock wins: the door opens")
    rs.grace["active"] = false


func _test_failsafe() -> void:
    _enter_normal_room()
    var lock = game.door_lock
    var stuck: Dictionary = _spawn("rat_scavenger", Vector2(88, 88), "stuck")
    var foes: Array = rs.current_room()["enemies"]
    foes.clear()
    foes.append(stuck)
    var walls: Dictionary = {}
    for x in range(4, 7):
        for y in range(4, 7):
            if Vector2i(x, y) != Vector2i(5, 5):
                walls[Vector2i(x, y)] = true
    rs.current_room()["blocked"] = walls
    game.player.world_position = Vector2(192, 192)
    for _i in range(40):
        lock.update(FRAME)
    check(lock.is_locked(), "sealed with the walled-in rat")
    check(DoorLock.hostiles_unreachable(foes, walls, Vector2(192, 192)), "the rat has no path to the crawler")
    check(not DoorLock.hostiles_unreachable(foes, {}, Vector2(192, 192)), "an open room has a path")
    var xp: int = rs.xp
    var before: int = int(rs.telemetry["failsafe_despawns"])
    _lock_seconds(10.0)
    events.enemy_damaged.emit("stuck", 1, false)
    _lock_seconds(10.0)
    check(foes.size() == 1, "damage dealt resets the failsafe timer")
    _lock_seconds(4.8)
    check(foes.size() == 1 and lock.is_locked(), "no despawn before 15 s")
    _lock_seconds(0.4)
    check(foes.is_empty(), "unreachable hostiles despawn after 15 s without damage")
    check(not lock.is_locked() and seen["doors_unlocked"].back()[1] == "failsafe", "failsafe opens the doors")
    check(rs.xp == xp and seen["enemy_killed"].is_empty(), "no XP and no kill for a failsafe despawn")
    check(int(rs.telemetry["failsafe_despawns"]) == before + 1, "failsafe_despawns telemetry counter")


func _lock_seconds(seconds: float) -> void:
    var steps: int = int(round(seconds / FRAME))
    for _i in range(steps):
        game.door_lock.update(FRAME)
