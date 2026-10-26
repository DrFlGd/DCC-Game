extends SceneTree
## Wave 3E companion prototype (D-10): companions.json validation, the
## companion.enabled flag (off = nothing created, RunState.rng untouched),
## spawning, following, target selection, bites through apply_damage with
## source "companion" (XP and credits yes, on_kill no), enemy retargeting,
## strikes and bullets on the companion, downed / revive, room-entry and
## leash teleports, the stay command, the pickup buff, F8 and per-seed
## determinism. Frames are stepped by hand (1/60 s).
## Run: godot --headless --path game --script res://tests/companion_test.gd
## Autoloads are fetched at runtime and game scripts load()ed (see run_all.sh).
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var Enemies
var AI
var Companions
var Loadout
var seen: Dictionary = {}
var damaged: Array = []
var kills: Array = []


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL COMPANION: " + detail)


func _record(name: String, value = null) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(value)


func _on_announcement(trigger: String, context: Dictionary) -> void:
    if trigger.begins_with("companion_"):
        _record("announce", [trigger, String(context.get("text", ""))])


func _count(name: String) -> int:
    return seen.get(name, []).size()


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    Enemies = load("res://scripts/enemy_system.gd")
    AI = load("res://scripts/companion_ai.gd")
    Companions = load("res://scripts/companions.gd")
    Loadout = load("res://scripts/loadout.gd")
    events.companion_spawned.connect(func(id): _record("spawned", id))
    events.companion_downed.connect(func(): _record("downed"))
    events.companion_revived.connect(func(): _record("revived"))
    events.companion_killed_enemy.connect(func(id): _record("killed", id))
    events.announcement_requested.connect(_on_announcement)
    events.enemy_damaged.connect(func(id, amount, _crit): damaged.append([id, amount]))
    events.enemy_killed.connect(func(id, xp, _pos): kills.append([id, xp]))
    _test_data()
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    _test_flag_off()
    _enable(true)
    _test_spawn()
    _test_follow_and_leash()
    _test_target_selection()
    _test_bites()
    _test_kill_rewards()
    _test_retarget_rule()
    _test_enemy_attacks_on_companion()
    _test_downed_and_revive()
    _test_room_entry_teleport()
    _test_stay_command()
    _test_determinism()
    _enable(false)
    _test_f8_toggle()
    game.queue_free()
    if failures == 0:
        print("PASS: companions.json, flag off/on, spawn, follow, leash, targets, bites, kill rewards, " +
            "retarget, strikes and bullets, downed/revive, room teleport, stay, F8, determinism")
    quit(1 if failures > 0 else 0)


func _enable(on: bool) -> void:
    var block: Dictionary = rs.config.get("companion", {})
    block["enabled"] = on
    rs.config["companion"] = block


func _definition() -> Dictionary:
    return Companions.definition("cmp_scrap_hound")


func _bite() -> Dictionary:
    return _definition()["attacks"][0]


## Obstacle-free copy of the current room with `foes`; crawler at `at`.
func _arena(foes: Array, at: Vector2 = Vector2(192, 192)) -> Array:
    var room: Dictionary = rs.current_room()
    room["blocked"] = {}
    room["enemies"] = foes
    room["pickups"] = []
    game.combat.clear_projectiles()
    game.combat.clear_hazards()
    game.combat.last_player_target = ""
    game.player.world_position = at
    game.player.aim_direction = Vector2.RIGHT
    game.player.invulnerability = 0.0
    game.player.dodge_iframes = 0.0
    rs.statuses = {}
    rs.hp = 500
    damaged.clear()
    kills.clear()
    if game.companion != null and game.companion.is_spawned():
        var buddy: Dictionary = game.companion.state
        if AI.is_down(buddy):
            AI.stand_up(buddy, 1.0)
        buddy["hp"] = int(buddy["max_hp"])
        buddy["pos"] = at + Vector2(-20, 0)
        buddy["iframes"] = 0.0
        buddy["cooldowns"] = {}
        buddy["wind_up"] = 0.0
        buddy["recovery"] = 0.0
        buddy["target_id"] = ""
        buddy["mode"] = "follow"
        buddy["state"] = "follow"
        game.companion._sync_buff()
    return room["enemies"]


func _rat(at: Vector2, id: String, hp: int = 500) -> Dictionary:
    var foe: Dictionary = Enemies.make_instance(game.catalogue, "rat_scavenger", at, 1, "", id)
    foe["hp"] = hp
    foe["max_hp"] = hp
    foe["dormant"] = 999.0
    return foe


func _step_companion(seconds: float) -> void:
    var elapsed := 0.0
    while elapsed < seconds - 0.0001:
        game.companion.update(FRAME, game.companion.build_world())
        elapsed += FRAME


# --- Data --------------------------------------------------------------------------

func _test_data() -> void:
    var catalogue: Dictionary = Companions.load_catalogue()
    var problems: Array = Companions.validate(catalogue)
    check(problems.is_empty(), "companions.json validates: %s" % [problems])
    var hound: Dictionary = _definition()
    check(String(hound.get("name", "")) == "Scrap Hound" and hound.get("adaptation_type") == "original",
        "cmp_scrap_hound is the original Scrap Hound")
    check(String(_bite().get("type", "")) == "melee" and float(_bite().get("cooldown", 0)) > 0.0,
        "the hound has a melee bite with a cooldown (enemies.json attack schema)")
    check(ResourceLoader.exists(String(hound["sprite"])), "the generated sprite is imported")
    var broken: Dictionary = catalogue.duplicate(true)
    broken["companions"]["cmp_scrap_hound"]["attacks"][0]["type"] = "laser"
    broken["companions"]["cmp_scrap_hound"]["leash_distance"] = 1
    broken["companions"]["bad_id"] = {"name": "x"}
    check(Companions.validate(broken).size() >= 3, "the validator rejects bad types, leash and ids")
    var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_rules.json"))
    check(rules.has("companion") and not bool(rules["companion"]["enabled"]),
        "prototype_rules.json ships companion.enabled = false")


# --- Flag off ----------------------------------------------------------------------

func _test_flag_off() -> void:
    game.start_run(SEED)
    check(not rs.companion_enabled and game.companion == null and game.get_node_or_null("Companion") == null,
        "flag off: no Companion node is created")
    check(game.combat.companion == null and game.hud.companion == null, "flag off: combat and HUD hold no companion")
    check(_count("spawned") == 0, "flag off: companion_spawned never fires")
    check(float(Loadout.player_stats()["pickup_radius"]) == 0.0, "flag off: no pickup buff")
    var foes: Array = _arena([_rat(Vector2(150, 192), "off_1")])
    foes[0]["dormant"] = 0.0
    for _i in range(60):
        game.combat.update_enemies(FRAME)
    check(not foes[0].has("target") and not foes[0].has("retarget_timer"),
        "flag off: enemies never gain companion targeting keys")
    # The companion never touches RunState.rng: run start leaves it where the flag-off run does.
    game.start_run(SEED)
    var off_state: int = rs.rng.state
    _enable(true)
    game.start_run(SEED)
    check(rs.rng.state == off_state, "flag on: run start consumes no RunState.rng rolls")
    _enable(false)
    game.start_run(SEED)
    check(game.companion == null, "turning the flag off removes the companion on the next run")


# --- Spawn, follow, leash -----------------------------------------------------------

func _test_spawn() -> void:
    seen.erase("spawned")
    game.start_run(SEED)
    check(rs.companion_enabled and game.companion != null and game.companion.is_up(),
        "flag on: the companion exists and is up after start_run")
    check(game.combat.companion == game.companion and game.hud.companion == game.companion,
        "Combat and HUD see the companion")
    check(_count("spawned") == 1 and seen["spawned"][0] == "cmp_scrap_hound",
        "companion_spawned(cmp_scrap_hound) fires once at run start (%d)" % _count("spawned"))
    var gap: float = game.companion.position().distance_to(game.player.world_position)
    check(gap <= float(_definition()["follow_distance"]) + 0.5,
        "spawns beside the crawler (%.1f px)" % gap)
    check(int(game.companion.state["max_hp"]) == AI.max_hp_for(_definition(), rs.level),
        "max HP follows the crawler's level")
    check(float(Loadout.player_stats()["pickup_radius"]) == 1.0,
        "while up, the crawler's pickup_radius gets +1 (Loadout.player_stats)")
    var info: Dictionary = game.companion.hud_info()
    check(info["state"] == "follow" and int(info["hp"]) == int(info["max_hp"]), "hud_info reports a healthy follower")


func _test_follow_and_leash() -> void:
    _arena([], Vector2(192, 192))
    var follow: float = float(_definition()["follow_distance"])
    game.companion.state["pos"] = Vector2(192 + 100, 192)
    var before: float = game.companion.position().distance_to(game.player.world_position)
    _step_companion(0.3)
    var mid: float = game.companion.position().distance_to(game.player.world_position)
    _step_companion(2.0)
    var after: float = game.companion.position().distance_to(game.player.world_position)
    check(mid < before and after <= follow + 1.0,
        "the companion closes in and settles within follow_distance (%.1f -> %.1f -> %.1f)" % [before, mid, after])
    check(String(game.companion.state["state"]) == "follow", "back to follow once close")
    # Moving the crawler drags the companion along.
    game.player.world_position = Vector2(80, 192)
    _step_companion(2.0)
    after = game.companion.position().distance_to(game.player.world_position)
    check(after <= follow + 1.0, "it keeps up when the crawler walks off (%.1f)" % after)
    # Leash: beyond leash_distance it teleports beside the crawler.
    game.companion.state["pos"] = Vector2(370, 370)
    game.player.world_position = Vector2(30, 30)
    var actions: Array = AI.step(game.companion.state, _definition(), FRAME, game.companion.build_world())
    check(actions.size() == 1 and actions[0]["type"] == "teleport" and actions[0]["reason"] == "leash",
        "past leash_distance it teleports (%s)" % [actions])
    check(game.companion.position().distance_to(game.player.world_position) <= follow + 0.5,
        "the leash teleport lands beside the crawler")
    # Stuck: walled in, it gives up after stuck_seconds and teleports.
    var room: Dictionary = rs.current_room()
    _arena([], Vector2(100, 100))
    var cell: Vector2i = Vector2i(15, 6)
    var walls: Dictionary = {}
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            if dx != 0 or dy != 0:
                walls[cell + Vector2i(dx, dy)] = true
    room["blocked"] = walls
    game.companion.state["pos"] = Vector2(cell) * 16.0 + Vector2(8, 8)
    var teleported := false
    for _i in range(150):
        for action in AI.step(game.companion.state, _definition(), FRAME, game.companion.build_world()):
            if action["type"] == "teleport" and action["reason"] == "stuck":
                teleported = true
    check(teleported and game.companion.position().distance_to(game.player.world_position) <= follow + 0.5,
        "a boxed-in companion teleports out after stuck_seconds")
    room["blocked"] = {}


# --- Targets and bites ---------------------------------------------------------------

func _test_target_selection() -> void:
    var hound: Dictionary = _definition()
    var buddy: Dictionary = AI.make_instance(hound, Vector2(100, 100), 1, "cmp_scrap_hound")
    var near_dog: Dictionary = _rat(Vector2(110, 100), "near_dog")
    var near_crawler: Dictionary = _rat(Vector2(170, 100), "near_crawler")
    var far: Dictionary = _rat(Vector2(370, 370), "far")
    var world := {"crawler_pos": Vector2(160, 100), "foes": [far, near_crawler, near_dog], "preferred_id": ""}
    check(AI.choose_target(buddy, hound, world)["instance_id"] == "near_dog",
        "no preference: the enemy nearest the companion within engage_radius of the crawler")
    world["preferred_id"] = "near_crawler"
    check(AI.choose_target(buddy, hound, world)["instance_id"] == "near_crawler",
        "the crawler's last target is preferred")
    world["preferred_id"] = "far"
    check(AI.choose_target(buddy, hound, world)["instance_id"] == "near_dog",
        "a preferred target beyond engage_radius is ignored")
    buddy["target_id"] = "near_crawler"
    world["preferred_id"] = ""
    check(AI.choose_target(buddy, hound, world)["instance_id"] == "near_crawler",
        "the current target is kept while valid")
    near_crawler["hp"] = 0
    check(AI.choose_target(buddy, hound, world)["instance_id"] == "near_dog", "dead targets are dropped")
    world["foes"] = [far]
    check(AI.choose_target(buddy, hound, world).is_empty(), "nothing within engage_radius: no target")
    # Combat records the crawler's last target (source "player" only).
    var foes: Array = _arena([_rat(Vector2(250, 192), "marked"), _rat(Vector2(150, 192), "other")])
    game.combat.apply_damage(foes[0], 1, {"source": "player", "slot": "melee", "knockback": 0.0})
    check(game.combat.last_player_target == "marked", "Combat.last_player_target follows the crawler's hits")
    game.combat.apply_damage(foes[1], 1, {"source": "companion", "knockback": 0.0})
    check(game.combat.last_player_target == "marked", "companion hits do not change it")
    check(AI.choose_target(game.companion.state, hound, game.companion.build_world())["instance_id"] == "marked",
        "the live companion goes for the crawler's mark")


func _test_bites() -> void:
    var foes: Array = _arena([_rat(Vector2(192, 160), "chew_toy")])
    foes[0]["ac"] = -100
    game.companion.state["pos"] = Vector2(192, 175)
    var rng_before: int = rs.rng.state
    var cooldown: float = float(_bite()["cooldown"])
    var bites := 0
    var last := 0.0
    var elapsed := 0.0
    while elapsed < 3.0 - 0.0001:
        game.companion.update(FRAME, game.companion.build_world())
        var now: float = float(game.companion.state["cooldowns"].get("bite", 0.0))
        if now > last + 0.5:
            bites += 1
        last = now
        elapsed += FRAME
    check(bites == 3, "3 s of biting at a %.2f s cooldown + %.2f s wind-up = 3 bites (%d)" % [
        cooldown, float(_bite()["wind_up"]), bites])
    check(damaged.size() >= 2 and int(foes[0]["hp"]) < 500,
        "bites damage the target through apply_damage (Events.enemy_damaged x%d)" % damaged.size())
    check(damaged.is_empty() or damaged[0][0] == "chew_toy", "damage lands on the engaged enemy")
    check(String(game.companion.state["state"]) == "engage" and game.companion.state["target_id"] == "chew_toy",
        "the companion is engaged with its target")
    check(rs.rng.state == rng_before, "companion bites never consume RunState.rng")
    check(game.combat.last_player_target == "", "companion damage is not credited as a crawler hit")
    # Out of reach when the wind-up ends: the bite whiffs.
    _arena([_rat(Vector2(192, 160), "dodger")])
    game.companion.state["pos"] = Vector2(192, 175)
    game.companion.update(FRAME, game.companion.build_world())
    check(float(game.companion.state["wind_up"]) > 0.0, "a bite winds up when in reach")
    rs.current_room()["enemies"][0]["pos"] = Vector2(192, 60)
    _step_companion(0.2)
    check(damaged.is_empty(), "the target stepping away during the wind-up makes the bite miss")


func _test_kill_rewards() -> void:
    var foes: Array = _arena([_rat(Vector2(192, 160), "doomed", 1)])
    foes[0]["ac"] = -100
    rs.inventory["passives"] = [{"id": "itm_vampire_straw", "count": 1}]
    events.inventory_changed.emit()
    game.items.update(FRAME)
    rs.hp = 5
    var xp_before: int = rs.xp
    var credits_before: int = int(rs.inventory.get("credits", 0))
    var telemetry_before: int = int(rs.telemetry.get("companion_kills", 0))
    seen.erase("killed")
    game.companion.state["pos"] = Vector2(192, 175)
    for _i in range(240):
        if foes.is_empty():
            break
        game.companion.update(FRAME, game.companion.build_world())
    check(foes.is_empty() and kills.size() == 1 and kills[0][0] == "rat_scavenger",
        "the companion kills the rat (enemy_killed)")
    check(rs.xp == xp_before + int(kills[0][1]) if not kills.is_empty() else false,
        "the kill's XP goes to the crawler (%d -> %d)" % [xp_before, rs.xp])
    check(int(rs.inventory.get("credits", 0)) > credits_before, "per-kill credits go to the crawler")
    check(rs.hp == 5, "on_kill item triggers do not fire for companion kills (vampire straw HP %d)" % rs.hp)
    check(_count("killed") == 1 and seen["killed"][0] == "rat_scavenger", "companion_killed_enemy fires")
    check(int(rs.telemetry["companion_kills"]) == telemetry_before + 1 and game.companion.kills >= 1,
        "telemetry companion_kills counts it")
    rs.inventory["passives"] = []
    events.inventory_changed.emit()
    game.items.update(FRAME)


# --- Enemies vs the companion -------------------------------------------------------------

func _test_retarget_rule() -> void:
    var rat_def: Dictionary = game.catalogue["enemies"]["rat_scavenger"]
    check(Enemies.can_target_companion(rat_def), "non-boss melee enemies may retarget")
    check(not Enemies.can_target_companion(game.catalogue["enemies"]["spitting_rat"]),
        "ranged-only enemies keep the crawler")
    check(not Enemies.can_target_companion(game.catalogue["enemies"]["armored_brute"]), "bosses keep the crawler")
    var rules := {"retarget_chance": 0.3, "retarget_radius": 64.0, "retarget_interval": 1.0}
    var world := {"player_pos": Vector2(200, 100), "companion_pos": Vector2(120, 100),
        "companion_alive": true, "companion_rules": rules, "retarget_seed": 7}
    var picked := 0
    for i in range(400):
        var foe := {"instance_id": "r_%d" % i, "pos": Vector2(100, 100), "state": "idle"}
        Enemies.update_companion_target(foe, rat_def, FRAME, world)
        if foe["target"] == "companion":
            picked += 1
    check(picked > 80 and picked < 160, "about 30 %% of eligible enemies retarget (%d / 400)" % picked)
    var again := 0
    for i in range(400):
        var foe := {"instance_id": "r_%d" % i, "pos": Vector2(100, 100), "state": "idle"}
        Enemies.update_companion_target(foe, rat_def, FRAME, world)
        if foe["target"] == "companion":
            again += 1
    check(again == picked, "the roll is deterministic (no RNG stream consumed)")
    var foe := {"instance_id": "r_far", "pos": Vector2(100, 100), "state": "idle"}
    world["companion_pos"] = Vector2(100, 200)
    for _i in range(20):
        foe["retarget_timer"] = 0.0
        Enemies.update_companion_target(foe, rat_def, FRAME, world)
        check(foe["target"] == "player", "no retarget when the companion is beyond retarget_radius")
    world["companion_pos"] = Vector2(130, 100)
    world["player_pos"] = Vector2(110, 100)
    foe["retarget_timer"] = 0.0
    Enemies.update_companion_target(foe, rat_def, FRAME, world)
    check(foe["target"] == "player", "no retarget when the crawler is nearer")
    foe["target"] = "companion"
    world["companion_alive"] = false
    Enemies.update_companion_target(foe, rat_def, FRAME, world)
    check(foe["target"] == "player", "a downed companion sends enemies back to the crawler")


func _test_enemy_attacks_on_companion() -> void:
    var foes: Array = _arena([_rat(Vector2(150, 192), "biter")], Vector2(300, 192))
    var rat: Dictionary = foes[0]
    rat["dormant"] = 0.0
    rat["attack_cooldown"] = 0.0
    rat["target"] = "companion"
    rat["retarget_timer"] = 999.0
    game.companion.state["pos"] = Vector2(165, 192)
    game.companion.state["ac"] = -100
    var hp_before: int = int(game.companion.state["hp"])
    var crawler_before: int = rs.hp
    var rng_before: int = rs.rng.state
    for _i in range(150):
        game.combat.update_enemies(FRAME)
    check(int(game.companion.state["hp"]) < hp_before, "a retargeted rat's bite hits the companion (%d -> %d)" % [
        hp_before, int(game.companion.state["hp"])])
    check(rs.hp == crawler_before, "the crawler is not hit by a strike aimed at the companion")
    check(rs.rng.state == rng_before, "hit_companion rolls with the companion's RNG, not RunState.rng")
    # Bullets hit the companion too.
    _arena([], Vector2(300, 300))
    game.companion.state["pos"] = Vector2(100, 100)
    game.companion.state["ac"] = -100
    hp_before = int(game.companion.state["hp"])
    game.combat.projectiles.append({"pos": Vector2(60, 100), "velocity": Vector2(120, 0), "ttl": 2.0,
        "owner": "enemy", "die": 4, "bonus": 0, "attack_bonus": 3, "source": "spitting_rat", "mult": 1.0,
        "status": ""})
    for _i in range(40):
        game.combat.update_projectiles(FRAME)
    check(int(game.companion.state["hp"]) < hp_before and game.combat.projectiles.is_empty(),
        "an enemy bullet hits the companion and is consumed")
    game.companion.state["ac"] = int(_definition()["ac"])


func _test_downed_and_revive() -> void:
    _arena([], Vector2(300, 300))
    var buddy: Dictionary = game.companion.state
    buddy["pos"] = Vector2(100, 100)
    seen.erase("downed")
    seen.erase("revived")
    seen.erase("announce")
    game.companion.take_damage(999, {"source": "rat_scavenger"})
    check(AI.is_down(buddy) and int(buddy["hp"]) == 0 and _count("downed") == 1,
        "0 HP: downed and companion_downed fires")
    check(not game.companion.is_hittable() and not game.combat.hit_companion(30, 6, 0),
        "a downed companion cannot be hit")
    check(float(Loadout.player_stats()["pickup_radius"]) == 0.0, "no pickup buff while downed")
    check(_count("announce") == 1 and seen["announce"][0][0] == "companion_downed"
        and seen["announce"][0][1] in _definition()["lines"]["downed"],
        "the announcer gets one of the downed lines")
    _step_companion(1.0)
    check(AI.is_down(buddy) and float(buddy["revive_progress"]) == 0.0,
        "no revive progress while the crawler is away")
    check(buddy["pos"] == Vector2(100, 100), "a downed companion stays put")
    game.player.world_position = Vector2(110, 100)
    _step_companion(1.9)
    check(AI.is_down(buddy), "still down before revive.channel_seconds (2 s)")
    _step_companion(0.2)
    var half: int = int(ceilf(float(buddy["max_hp"]) * 0.5))
    check(not AI.is_down(buddy) and int(buddy["hp"]) == half and _count("revived") == 1,
        "standing within 24 px for 2 s revives at 50 %% HP (%d/%d)" % [int(buddy["hp"]), int(buddy["max_hp"])])
    check(float(Loadout.player_stats()["pickup_radius"]) == 1.0, "the buff returns on revive")
    # Auto revive after revive.auto_seconds.
    game.player.world_position = Vector2(300, 300)
    buddy["iframes"] = 0.0
    game.companion.take_damage(999, {"source": "test"})
    _step_companion(float(_definition()["revive"]["auto_seconds"]) - 0.5)
    check(AI.is_down(buddy), "no auto revive before auto_seconds")
    _step_companion(0.6)
    check(not AI.is_down(buddy) and _count("revived") == 2, "auto revive after auto_seconds")
    # Floor start revives at full HP.
    buddy["iframes"] = 0.0
    game.companion.take_damage(999, {"source": "test"})
    game._start_floor(2)
    check(not AI.is_down(game.companion.state) and int(game.companion.state["hp"]) ==
        int(game.companion.state["max_hp"]), "a new floor revives the companion at full HP")
    check(game.companion.position().distance_to(game.player.world_position) <=
        float(_definition()["follow_distance"]) + 0.5, "and places it beside the crawler")


func _test_room_entry_teleport() -> void:
    game.start_run(SEED)
    var rooms: Array = rs.floor["rooms"]
    var here: Dictionary = rooms[rs.current_room_id]
    var direction := ""
    for side in ["N", "E", "S", "W"]:
        if here["neighbors"].has(side) and rooms[int(here["neighbors"][side])]["kind"] != "exit":
            direction = side
            break
    game.companion.state["pos"] = Vector2(20, 20)
    game.companion.state["mode"] = "stay"
    var before: int = rs.current_room_id
    game._enter_neighbor(direction)
    check(rs.current_room_id != before, "entered a neighbour room")
    check(game.companion.position().distance_to(game.player.world_position) <=
        float(_definition()["follow_distance"]) + 0.5,
        "room entry teleports the companion beside the crawler (%.1f px)" %
        game.companion.position().distance_to(game.player.world_position))
    check(game.companion.state["mode"] == "follow", "room entry resets the stay command")


func _test_stay_command() -> void:
    _arena([], Vector2(192, 192))
    game.companion.state["pos"] = Vector2(170, 192)
    seen.erase("announce")
    check(game.companion.toggle_command() == "stay", "toggle_command -> stay")
    game.player.world_position = Vector2(80, 192)
    _step_companion(1.0)
    check(game.companion.position() == Vector2(170, 192), "a staying companion holds its spot")
    # Hold interact (no interactable prompt) for 0.4 s -> follow again.
    Input.action_press("interact")
    var world: Dictionary = game.companion.build_world()
    world["can_command"] = true
    for _i in range(18):
        game.companion.update(FRAME, world)
    check(game.companion.state["mode"] == "stay", "a short press does not toggle (0.3 s)")
    for _i in range(12):
        game.companion.update(FRAME, world)
    check(game.companion.state["mode"] == "follow", "holding interact 0.4 s toggles back to follow")
    for _i in range(60):
        game.companion.update(FRAME, world)
    check(game.companion.state["mode"] == "follow", "one hold toggles once")
    world["can_command"] = false
    Input.action_release("interact")
    Input.action_press("interact")
    for _i in range(60):
        game.companion.update(FRAME, world)
    check(game.companion.state["mode"] == "follow", "no toggle while an interactable prompt shows")
    Input.action_release("interact")
    check(_count("announce") >= 2, "commands get announcer lines")


## Same seed, flag on, same inputs -> identical companion and enemy trace.
func _test_determinism() -> void:
    var first: PackedStringArray = _companion_trace()
    var second: PackedStringArray = _companion_trace()
    check(first.size() > 10 and first == second, "two runs of the same seed replay the same companion trace")
    var bit_count := 0
    for line in first:
        if line.contains("engage"):
            bit_count += 1
    check(bit_count > 0, "the trace includes combat (engaged frames: %d)" % bit_count)


func _companion_trace() -> PackedStringArray:
    game.start_run(SEED)
    var rooms: Array = rs.floor["rooms"]
    var start: Dictionary = rooms[rs.current_room_id]
    for direction in ["N", "E", "S", "W"]:
        if start["neighbors"].has(direction) and rooms[int(start["neighbors"][direction])]["kind"] == "normal":
            game._enter_neighbor(direction)
            break
    var trace: PackedStringArray = []
    for frame in range(600):
        game.player.invulnerability = 0.0
        game.combat.update_projectiles(FRAME)
        game.combat.update_enemies(FRAME)
        game.companion.update(FRAME, game.companion.build_world())
        if frame % 20 == 0:
            var hps: PackedStringArray = []
            for foe in game.combat.enemies():
                hps.append("%s:%d:%s" % [foe["instance_id"], int(foe["hp"]), String(foe.get("target", "-"))])
            trace.append("%s %d %s %s | %d | %s" % [str(game.companion.position()),
                int(game.companion.state["hp"]), game.companion.state["state"],
                game.companion.state["target_id"], rs.hp, ",".join(hps)])
    return trace


func _test_f8_toggle() -> void:
    game.start_run(SEED)
    check(game.companion == null, "flag off again: no companion")
    seen.erase("spawned")
    var press := InputEventAction.new()
    press.action = "debug_toggle_companion"
    press.pressed = true
    check(InputMap.has_action("debug_toggle_companion"), "debug_toggle_companion is in the Input Map")
    var keys: Array = []
    for event in InputMap.action_get_events("debug_toggle_companion"):
        check(event is InputEventKey, "debug_toggle_companion is keyboard only (no gamepad binding)")
        if event is InputEventKey:
            keys.append(event.physical_keycode)
    check(keys == [KEY_F8], "debug_toggle_companion is physical F8 (%s)" % [keys])
    game._unhandled_input(press)
    check(rs.companion_enabled and game.companion != null and game.companion.is_up() and _count("spawned") == 1,
        "F8 spawns the companion mid-run")
    game._unhandled_input(press)
    check(not rs.companion_enabled and game.companion == null and game.combat.companion == null,
        "F8 again removes it")
    check(float(Loadout.player_stats()["pickup_radius"]) == 0.0, "removing it clears the buff")
    game._unhandled_input(press)
    game.start_run(SEED)
    check(game.companion != null, "the F8 choice persists into the next run of the session")
    game._unhandled_input(press)
