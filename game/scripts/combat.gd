extends Node
## Combat: projectiles, melee arcs, d20 hit resolution, enemy AI and attacks.
##
## Enemy turns: update_enemies() steps each enemy's state machine
## (enemy_system.gd step(): dormant -> idle -> winding_up -> resolve ->
## recovery, plus dashing/stunned) and resolves the actions it returns here:
## strikes roll d20 against the crawler, volleys spawn projectiles, puddles and
## death bursts become `hazards`, summons and support casts change the room.
##
## Room data (enemies, obstacles) is read from `RunState.current_room()`; the
## enemy dictionaries are the persisted room state, so HP survives revisits.
## Every point of damage goes through apply_damage(), which is the single place
## that changes HP and emits `Events.enemy_damaged` / `enemy_killed` /
## `player_damaged` / `player_died`. All d20 and damage rolls use `RunState.rng`
## in a fixed order, which keeps seeded runs reproducible.
const Contents = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const Player = preload("res://scripts/player.gd")

const PLAYER_SHOT_SPEED := 215.0
const PLAYER_SHOT_TTL := 2.0
const PLAYER_SHOT_DIE := 6
const PLAYER_SHOT_SPAWN := 9.0
const MELEE_REACH := 32.0
const MELEE_ARC_DOT := 0.45
const MELEE_DIE := 6
const ENEMY_SHOT_TTL := 2.8
const PROJECTILE_RADIUS := 2.0
const HIT_SLOP := 3.0

## Live projectiles: {pos, velocity, ttl, owner ("player"/"enemy"), die, bonus,
## attack_bonus, source, mult}. Cleared on every room transition.
var projectiles: Array[Dictionary] = []
## Live ground hazards: {pos, radius, telegraph_remaining, damage, duration,
## source} plus tick, tick_timer, status, damage_type, hits_enemies, hits_player,
## owner (see Enemies.make_hazard). Cleared on every room entry. Wave 2E's
## generic hazard module is expected to absorb this list.
var hazards: Array[Dictionary] = []
## Crawler velocity estimated from frame-to-frame movement (twin_shot lead).
var player_velocity := Vector2.ZERO
var _last_player_pos := Vector2.INF
var player: Player
var catalogue: Dictionary = {}


func _ready() -> void:
    Events.room_entered.connect(_on_room_entered)


func setup(player_node: Player, enemy_catalogue: Dictionary) -> void:
    player = player_node
    catalogue = enemy_catalogue


## Every room entry (first visit or revisit) clears hazards and puts the room's
## enemies back on their spawn points, dormant for `encounters.dormancy` s.
func _on_room_entered(_room_id: int, _kind: String, _entry: Dictionary, _first: bool) -> void:
    hazards.clear()
    _last_player_pos = Vector2.INF
    player_velocity = Vector2.ZERO
    var dormancy: float = float(catalogue.get("encounters", {}).get("dormancy", 0.6))
    for foe in enemies():
        Enemies.on_room_entered(foe, dormancy)


func enemies() -> Array:
    return RunState.current_room().get("enemies", [])


func blocked() -> Dictionary:
    return RunState.current_room().get("blocked", {})


func definition_of(foe: Dictionary) -> Dictionary:
    return catalogue["enemies"][foe["definition"]]


func clear_projectiles() -> void:
    projectiles.clear()


## Spawns a player bolt along the current aim (cooldown is the Player's job).
func player_fire() -> void:
    var scores: Dictionary = RunState.ability_scores
    var shot := {
        "pos": player.world_position + player.aim_direction * PLAYER_SHOT_SPAWN,
        "velocity": player.aim_direction * PLAYER_SHOT_SPEED, "ttl": PLAYER_SHOT_TTL,
        "owner": "player", "die": PLAYER_SHOT_DIE,
        "bonus": RPG.modifier(int(scores["DEX"])),
        "attack_bonus": RPG.attack_bonus(scores, "DEX", RunState.level),
        "source": "player"
    }
    projectiles.append(shot)
    Events.projectile_fired.emit("player", shot)


## Resolves a melee arc in front of the player against every enemy in reach.
func player_melee() -> void:
    Events.melee_swung.emit("player", player.world_position, player.aim_direction)
    var scores: Dictionary = RunState.ability_scores
    var foes: Array = enemies()
    for i in range(foes.size() - 1, -1, -1):
        if i >= foes.size():
            continue
        var foe: Dictionary = foes[i]
        var toward: Vector2 = Vector2(foe["pos"]) - player.world_position
        if toward.length() <= MELEE_REACH + float(foe["radius"]) and toward.length() > 0.01:
            if player.aim_direction.dot(toward.normalized()) > MELEE_ARC_DOT:
                hit_enemy(i, RPG.attack_bonus(scores, "STR", RunState.level),
                    MELEE_DIE, RPG.modifier(int(scores["STR"])),
                    {"slot": "melee", "direction": toward.normalized()})


## Player attack roll against enemy `index` of the current room. `extra` is
## merged into the apply_damage context (slot, direction, damage_type).
func hit_enemy(index: int, to_hit: int, die: int, damage_bonus: int,
        extra: Dictionary = {}) -> void:
    var foes: Array = enemies()
    if index < 0 or index >= foes.size():
        return
    var foe: Dictionary = foes[index]
    var definition: Dictionary = definition_of(foe)
    var attack: Dictionary = RPG.roll_to_hit(RunState.rng, to_hit,
        int(foe.get("ac", definition["ac"])))
    if not bool(attack["hit"]):
        Events.say("Missed %s (d20: %d)" % [foe.get("name", definition["name"]),
            int(attack["d20"])], "combat")
        return
    var damage: int = RPG.roll_damage(RunState.rng, die, damage_bonus, bool(attack["critical"]))
    var context := {"critical": bool(attack["critical"]), "source": "player", "index": index}
    context.merge(extra)
    apply_damage(foe, damage, context)


## Enemy attack roll against the player; ignored during invulnerability.
## `damage_mult` is the elite multiplier (rounded down, minimum 1). `source` is
## the attacker's definition id. Returns true when the attack landed.
func hit_player(to_hit: int, die: int, damage_bonus: int, source: String = "enemy",
        damage_mult: float = 1.0) -> bool:
    if player.invulnerability > 0.0:
        return false
    var attack: Dictionary = RPG.roll_to_hit(RunState.rng, to_hit, RunState.ac)
    if not bool(attack["hit"]):
        Events.say("Enemy missed you (d20: %d)." % int(attack["d20"]), "combat")
        return false
    var damage: int = RPG.roll_damage(RunState.rng, die, damage_bonus, bool(attack["critical"]))
    if damage_mult != 1.0:
        damage = maxi(1, int(floorf(float(damage) * damage_mult)))
    apply_damage(player, damage, {"critical": bool(attack["critical"]), "source": source})
    return true


## The damage pipeline. `target` is the Player node or an enemy dictionary from
## the current room. `context` keys: critical (bool), source (String), index
## (int, optional enemy index hint), damage_type ("physical" default), slot
## ("melee"/"ranged"), direction (Vector2 of travel). Returns the damage applied.
## Enemy side, in order: phase-roar invulnerability, Enemies.mitigate()
## (resistances, front guard, DR), then ward and shield pools absorb.
## Feature teams: resistances, shields, status effects and on-hit item
## triggers belong here, before HP changes.
func apply_damage(target, amount: int, context: Dictionary = {}) -> int:
    if amount <= 0:
        return 0
    if target is Dictionary:
        return _damage_enemy(target, amount, context)
    if target == player:
        return _damage_player(amount, context)
    push_warning("apply_damage: unsupported target %s" % [target])
    return 0


func _damage_enemy(foe: Dictionary, amount: int, context: Dictionary) -> int:
    var definition: Dictionary = definition_of(foe)
    var label: String = String(foe.get("name", definition["name"]))
    if int(foe["hp"]) <= 0:
        return 0
    if float(foe.get("invulnerable", 0.0)) > 0.0:
        Events.say("%s is busy roaring and ignores that." % label, "combat")
        return 0
    amount = Enemies.mitigate(foe, definition, amount, context)
    if amount <= 0:
        Events.say("%s is immune." % label, "combat")
        return 0
    foe["shield_regen"] = 0.0
    for pool in ["ward", "shield"]:
        var absorbed: int = mini(int(foe.get(pool, 0)), amount)
        foe[pool] = int(foe.get(pool, 0)) - absorbed
        amount -= absorbed
    if amount <= 0:
        Events.say("%s's shield soaks the hit." % label, "combat")
        return 0
    foe["hp"] = int(foe["hp"]) - amount
    Events.enemy_damaged.emit(String(foe["instance_id"]), amount,
        bool(context.get("critical", false)))
    Events.say("Hit %s for %d damage" % [label, amount], "combat")
    if int(foe["hp"]) > 0:
        _check_phase(foe, definition)
        return amount
    var foes: Array = enemies()
    var index: int = int(context.get("index", -1))
    if index < 0 or index >= foes.size() or not is_same(foes[index], foe):
        index = -1
        for i in range(foes.size()):
            if is_same(foes[i], foe):
                index = i
                break
    if index >= 0:
        foes.remove_at(index)
    Events.enemy_killed.emit(String(foe["definition"]), int(foe.get("xp", definition["xp"])),
        Vector2(foe["pos"]))
    _on_enemy_death(foe)
    if foes.is_empty():
        Events.room_cleared.emit(RunState.current_room_id)
    return amount


## Death side effects: summons die with their summoner (0 XP), volatile elites
## leave a telegraphed blast that also hits enemies.
func _on_enemy_death(foe: Dictionary) -> void:
    var foes: Array = enemies()
    for i in range(foes.size() - 1, -1, -1):
        var minion: Dictionary = foes[i]
        if String(minion.get("summoner", "")) == String(foe["instance_id"]):
            minion["hp"] = 0
            foes.remove_at(i)
            Events.enemy_killed.emit(String(minion["definition"]), 0, Vector2(minion["pos"]))
    var mods: Dictionary = catalogue.get("elites", {}).get("modifiers", {})
    for mod_id in foe.get("modifiers", []):
        var burst: Dictionary = mods.get(String(mod_id), {}).get("death_burst", {})
        if burst.is_empty():
            continue
        var damage := 0
        for _i in range(int(burst.get("dice", 1))):
            damage += RunState.rng.randi_range(1, maxi(1, int(burst.get("die", 6))))
        hazards.append(Enemies.make_hazard(Vector2(foe["pos"]), float(burst.get("radius", 32)),
            float(burst.get("telegraph", 0.8)), damage, 0.0, String(foe["definition"]),
            {"hits_enemies": bool(burst.get("hits_enemies", true)),
                "damage_type": String(burst.get("damage_type", "fire"))}))


## Boss phase thresholds: entering a phase roars (1 s invulnerable), clears
## hostile projectiles and announces the phase line.
func _check_phase(foe: Dictionary, definition: Dictionary) -> void:
    var phases: Array = definition.get("phases", [])
    if phases.is_empty():
        return
    var index: int = Enemies.phase_index(definition, int(foe["hp"]), int(foe["max_hp"]))
    if index <= int(foe.get("phase", 0)):
        return
    Enemies.enter_phase(foe, index)
    for i in range(projectiles.size() - 1, -1, -1):
        if String(projectiles[i]["owner"]) == "enemy":
            projectiles.remove_at(i)
    Events.say(String(phases[index].get("announce", "%s changes tactics." % foe["name"])), "combat")


func _damage_player(amount: int, context: Dictionary) -> int:
    var remaining: int = maxi(0, RunState.hp - amount)
    Events.say("You take %d damage. %d/%d HP." % [amount, remaining, RunState.max_hp], "combat")
    player.start_invulnerability()
    return RunState.apply_damage_to_player(amount, String(context.get("source", "enemy")))


func update_projectiles(delta: float) -> void:
    var obstacles: Dictionary = blocked()
    for i in range(projectiles.size() - 1, -1, -1):
        if i >= projectiles.size():
            continue
        var bullet: Dictionary = projectiles[i]
        bullet["pos"] = Vector2(bullet["pos"]) + Vector2(bullet["velocity"]) * delta
        bullet["ttl"] = float(bullet["ttl"]) - delta
        var position: Vector2 = bullet["pos"]
        if float(bullet["ttl"]) <= 0.0 or not Contents.can_occupy(position,
                PROJECTILE_RADIUS, obstacles):
            projectiles.remove_at(i)
            continue
        var collided := false
        if String(bullet["owner"]) == "player":
            var foes: Array = enemies()
            for j in range(foes.size() - 1, -1, -1):
                if position.distance_to(Vector2(foes[j]["pos"])) < float(foes[j]["radius"]) + HIT_SLOP:
                    hit_enemy(j, int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]),
                        {"slot": "ranged", "direction": Vector2(bullet["velocity"]).normalized()})
                    collided = true
                    break
        elif position.distance_to(player.world_position) < Player.RADIUS + HIT_SLOP:
            hit_player(int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]),
                String(bullet.get("source", "enemy")), float(bullet.get("mult", 1.0)))
            collided = true
        if collided and i < projectiles.size() and is_same(projectiles[i], bullet):
            projectiles.remove_at(i)


## Steps every enemy's state machine (dormancy, wind-up, resolution, recovery)
## and resolves the actions it returns. Also ticks hazards.
func update_enemies(delta: float) -> void:
    _track_player(delta)
    update_hazards(delta)
    var foes: Array = enemies()
    var world := {"player_pos": player.world_position, "player_velocity": player_velocity,
        "blocked": blocked(), "allies": foes}
    for foe in foes.duplicate():
        if int(foe["hp"]) <= 0:
            continue
        var definition: Dictionary = definition_of(foe)
        for action in Enemies.step(foe, definition, delta, world):
            _resolve_enemy_action(foe, definition, action)


func _track_player(delta: float) -> void:
    var here: Vector2 = player.world_position
    if _last_player_pos != Vector2.INF and delta > 0.0:
        player_velocity = (here - _last_player_pos) / delta
    _last_player_pos = here


func _resolve_enemy_action(foe: Dictionary, definition: Dictionary, action: Dictionary) -> void:
    var attack: Dictionary = action.get("attack", {})
    var source: String = String(foe["definition"])
    match String(action["type"]):
        "strike":
            if not bool(action["hit"]):
                return
            var landed := true
            if attack.has("damage_die"):
                var numbers: Dictionary = Enemies.attack_numbers(foe, definition, attack)
                landed = hit_player(int(numbers["to_hit"]), int(numbers["die"]),
                    int(numbers["bonus"]), source, float(numbers["mult"]))
            if not landed:
                return
            var obstacles: Dictionary = blocked()
            if float(attack.get("pull", 0.0)) > 0.0:
                var inward: Vector2 = Vector2(foe["pos"]) - player.world_position
                var room_left: float = maxf(0.0, inward.length() - float(foe["radius"]) - Player.RADIUS)
                player.world_position = Enemies.push(player.world_position, inward,
                    minf(float(attack["pull"]), room_left), Player.RADIUS, obstacles)
            if float(attack.get("knockback", 0.0)) > 0.0:
                player.world_position = Enemies.push(player.world_position, action["direction"],
                    float(attack["knockback"]), Player.RADIUS, obstacles)
        "projectiles":
            var numbers: Dictionary = Enemies.attack_numbers(foe, definition, attack)
            for direction in action["directions"]:
                var shot: Vector2 = direction
                var bullet := {
                    "pos": Vector2(action["origin"]) + shot * (float(foe["radius"]) + 4.0),
                    "velocity": shot * float(attack.get("projectile_speed", 125.0)),
                    "ttl": ENEMY_SHOT_TTL, "owner": "enemy", "die": int(numbers["die"]),
                    "bonus": int(numbers["bonus"]), "attack_bonus": int(numbers["to_hit"]),
                    "source": source, "mult": float(numbers["mult"])
                }
                projectiles.append(bullet)
                Events.projectile_fired.emit("enemy", bullet)
        "hazard":
            var spec: Dictionary = attack.get("hazard", {})
            var damage: int = int(spec.get("damage", 0))
            if attack.has("damage_die"):
                var numbers: Dictionary = Enemies.attack_numbers(foe, definition, attack)
                damage = maxi(1, int(floorf(float(RPG.roll_damage(RunState.rng,
                    int(numbers["die"]), int(numbers["bonus"]), false)) * float(numbers["mult"]))))
            hazards.append(Enemies.make_hazard(action["pos"], float(action["radius"]),
                float(spec.get("telegraph", 0.0)), damage, float(spec.get("duration", 0.0)), source,
                {"tick": float(spec.get("tick", 0.0)), "status": String(spec.get("status", "")),
                    "damage_type": String(attack.get("damage_type", "physical"))}))
        "summon":
            _summon(foe, attack)
        "support":
            _support(foe, attack)
        "wall_stun":
            Events.say("%s meets a wall. The wall wins." % foe["name"], "combat")


## Spawns up to `summon.count` minions next to the summoner (or at the corner
## drains with `at_edges`), respecting the per-summoner cap and the room cap.
## Positions come from an RNG seeded by the summoner's rng_seed and serial, so
## a seeded run replays identically.
func _summon(foe: Dictionary, attack: Dictionary) -> void:
    var spec: Dictionary = attack.get("summon", {})
    var minion_id: String = String(spec.get("id", ""))
    if not catalogue["enemies"].has(minion_id):
        return
    var foes: Array = enemies()
    var room_cap: int = int(catalogue.get("encounters", {}).get("summon_room_cap", 6))
    var room_total := 0
    for other in foes:
        if String(other.get("summoner", "")) != "":
            room_total += 1
    var alive: int = Enemies.count_summons(foes, String(foe["instance_id"]))
    var count: int = mini(int(spec.get("count", 1)),
        mini(int(spec.get("cap", 4)) - alive, room_cap - room_total))
    var rng := RandomNumberGenerator.new()
    var obstacles: Dictionary = blocked()
    var radius: float = float(catalogue["enemies"][minion_id].get("collision_radius", 4))
    for _i in range(maxi(0, count)):
        var serial: int = int(foe.get("summon_serial", 0))
        foe["summon_serial"] = serial + 1
        rng.seed = int(foe.get("rng_seed", 0)) + serial * 7919
        var spot := Vector2.INF
        for _attempt in range(12):
            var candidate: Vector2
            if bool(spec.get("at_edges", false)):
                candidate = Enemies.EDGE_POINTS[rng.randi_range(0, Enemies.EDGE_POINTS.size() - 1)]
            else:
                candidate = Vector2(foe["pos"]) + Vector2.RIGHT.rotated(rng.randf() * TAU) \
                    * (float(foe["radius"]) + radius + 6.0)
            if Contents.can_occupy(candidate, radius, obstacles):
                spot = candidate
                break
        if spot == Vector2.INF:
            continue
        var minion: Dictionary = Enemies.make_instance(catalogue, minion_id, spot,
            int(foe.get("band", 1)), "", "%s_s%d" % [foe["instance_id"], serial])
        minion["summoner"] = String(foe["instance_id"])
        minion["xp"] = 0
        minion["attack_cooldown"] = 0.4
        minion["dormant"] = 0.3
        minion["rng_seed"] = rng.randi()
        foes.append(minion)


## Support casts: shield (temporary ward pool) or heal every other enemy in range.
func _support(foe: Dictionary, attack: Dictionary) -> void:
    var radius: float = float(attack.get("aoe_radius", 80))
    var amount: int = int(attack.get("amount", 0))
    for ally in enemies():
        if is_same(ally, foe) or int(ally["hp"]) <= 0:
            continue
        if Vector2(ally["pos"]).distance_to(foe["pos"]) > radius:
            continue
        if String(attack.get("effect", "")) == "heal":
            ally["hp"] = mini(int(ally["max_hp"]), int(ally["hp"]) + amount)
        else:
            ally["ward"] = maxi(int(ally.get("ward", 0)), amount)
            ally["ward_time"] = float(attack.get("duration", 6.0))


## Ticks hazards: the telegraph counts down (no damage), then the hazard pulses
## once on activation and every `tick` seconds until `duration` runs out.
func update_hazards(delta: float) -> void:
    for i in range(hazards.size() - 1, -1, -1):
        if i >= hazards.size():
            continue
        var hazard: Dictionary = hazards[i]
        if float(hazard["telegraph_remaining"]) > 0.0:
            hazard["telegraph_remaining"] = float(hazard["telegraph_remaining"]) - delta
            if float(hazard["telegraph_remaining"]) > 0.0:
                continue
            hazard["tick_timer"] = 0.0
        hazard["tick_timer"] = float(hazard.get("tick_timer", 0.0)) - delta
        if float(hazard["tick_timer"]) <= 0.0:
            var tick: float = float(hazard.get("tick", 0.0))
            hazard["tick_timer"] = tick if tick > 0.0 else INF
            _hazard_pulse(hazard)
        hazard["duration"] = float(hazard["duration"]) - delta
        if float(hazard["duration"]) <= 0.0 and i < hazards.size() and is_same(hazards[i], hazard):
            hazards.remove_at(i)


func _hazard_pulse(hazard: Dictionary) -> void:
    var center: Vector2 = hazard["pos"]
    var radius: float = float(hazard["radius"])
    var damage: int = int(hazard["damage"])
    if damage <= 0:
        return
    if bool(hazard.get("hits_player", true)) and player.invulnerability <= 0.0 \
            and center.distance_to(player.world_position) <= radius + Player.RADIUS:
        apply_damage(player, damage, {"source": String(hazard["source"])})
    if bool(hazard.get("hits_enemies", false)):
        for foe in enemies().duplicate():
            if int(foe["hp"]) > 0 and center.distance_to(Vector2(foe["pos"])) <= radius + float(foe["radius"]):
                apply_damage(foe, damage, {"source": "hazard:" + String(hazard["source"]),
                    "damage_type": String(hazard.get("damage_type", "physical"))})
