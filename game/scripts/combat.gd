extends Node
## Combat: projectiles, melee arcs, d20 hit resolution, enemy AI and attacks.
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
## attack_bonus, source}. Cleared on every room transition.
var projectiles: Array[Dictionary] = []
var player: Player
var catalogue: Dictionary = {}


func setup(player_node: Player, enemy_catalogue: Dictionary) -> void:
    player = player_node
    catalogue = enemy_catalogue


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
                    MELEE_DIE, RPG.modifier(int(scores["STR"])))


## Player attack roll against enemy `index` of the current room.
func hit_enemy(index: int, to_hit: int, die: int, damage_bonus: int) -> void:
    var foes: Array = enemies()
    if index < 0 or index >= foes.size():
        return
    var foe: Dictionary = foes[index]
    var definition: Dictionary = definition_of(foe)
    var attack: Dictionary = RPG.roll_to_hit(RunState.rng, to_hit, int(definition["ac"]))
    if not bool(attack["hit"]):
        Events.say("Missed %s (d20: %d)" % [definition["name"], int(attack["d20"])], "combat")
        return
    var damage: int = RPG.roll_damage(RunState.rng, die, damage_bonus, bool(attack["critical"]))
    apply_damage(foe, damage, {"critical": bool(attack["critical"]), "source": "player",
        "index": index})


## Enemy attack roll against the player; ignored during invulnerability.
func hit_player(to_hit: int, die: int, damage_bonus: int, source: String = "enemy") -> void:
    if player.invulnerability > 0.0:
        return
    var attack: Dictionary = RPG.roll_to_hit(RunState.rng, to_hit, RunState.ac)
    if not bool(attack["hit"]):
        Events.say("Enemy missed you (d20: %d)." % int(attack["d20"]), "combat")
        return
    var damage: int = RPG.roll_damage(RunState.rng, die, damage_bonus, bool(attack["critical"]))
    apply_damage(player, damage, {"critical": bool(attack["critical"]), "source": source})


## The damage pipeline. `target` is the Player node or an enemy dictionary from
## the current room. `context` keys: critical (bool), source (String), index
## (int, optional enemy index hint). Returns the damage applied.
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
    foe["hp"] = int(foe["hp"]) - amount
    Events.enemy_damaged.emit(String(foe["instance_id"]), amount,
        bool(context.get("critical", false)))
    Events.say("Hit %s for %d damage" % [definition["name"], amount], "combat")
    if int(foe["hp"]) > 0:
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
    Events.enemy_killed.emit(String(foe["definition"]), int(definition["xp"]),
        Vector2(foe["pos"]))
    if foes.is_empty():
        Events.room_cleared.emit(RunState.current_room_id)
    return amount


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
                    hit_enemy(j, int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]))
                    collided = true
                    break
        elif position.distance_to(player.world_position) < Player.RADIUS + HIT_SLOP:
            hit_player(int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]),
                String(bullet.get("source", "enemy")))
            collided = true
        if collided and i < projectiles.size() and is_same(projectiles[i], bullet):
            projectiles.remove_at(i)


## Runs every enemy's AI step and fires its first attack when in range.
func update_enemies(delta: float) -> void:
    var foes: Array = enemies()
    var obstacles: Dictionary = blocked()
    var target: Vector2 = player.world_position
    for foe in foes:
        var definition: Dictionary = definition_of(foe)
        Enemies.advance(foe, definition, delta, target, obstacles)
        foe["attack_cooldown"] = maxf(0.0, float(foe["attack_cooldown"]) - delta)
        if float(foe["attack_cooldown"]) > 0.0:
            continue
        var attacks: Array = definition.get("attacks", [])
        if attacks.is_empty():
            continue
        var skill: Dictionary = attacks[0]
        if Vector2(foe["pos"]).distance_to(target) > float(skill.get("range", 22.5)):
            continue
        if not Enemies.has_line_of_sight(Vector2(foe["pos"]), target, obstacles):
            continue
        var ability: String = String(skill.get("ability", "STR"))
        var attack_bonus: int = RPG.attack_bonus(definition["scores"], ability,
            int(definition.get("level", 1)), bool(skill.get("proficient", true)))
        var damage_bonus: int = RPG.modifier(int(definition["scores"].get(ability, 10))) \
            + int(skill.get("damage_bonus", 0))
        foe["attack_cooldown"] = float(skill.get("cooldown", 1.0))
        if skill["type"] == "melee":
            hit_player(attack_bonus, int(skill["damage_die"]), damage_bonus,
                String(foe["definition"]))
        elif skill["type"] == "ranged":
            _enemy_volley(foe, definition, skill, attack_bonus, damage_bonus)


func _enemy_volley(foe: Dictionary, definition: Dictionary, skill: Dictionary,
        attack_bonus: int, damage_bonus: int) -> void:
    var direction: Vector2 = (player.world_position - Vector2(foe["pos"])).normalized()
    var angles: Array[float] = [0.0]
    if "twin_shot" in definition.get("abilities", []):
        angles = [-0.15, 0.15]
    for angle in angles:
        var shot: Vector2 = direction.rotated(angle)
        var bullet := {
            "pos": Vector2(foe["pos"]) + shot * (float(foe["radius"]) + 4.0),
            "velocity": shot * float(skill.get("projectile_speed", 125.0)),
            "ttl": ENEMY_SHOT_TTL, "owner": "enemy", "die": int(skill["damage_die"]),
            "bonus": damage_bonus, "attack_bonus": attack_bonus,
            "source": String(foe["definition"])
        }
        projectiles.append(bullet)
        Events.projectile_fired.emit("enemy", bullet)
