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
##
## Wave 2B: the crawler's attacks read the equipped weapon through
## Loadout.attack_profile() (ContentDB.attack_profile + passives + statuses):
## melee arc / thrust / spin, ranged single / spread / burst / beam, with
## pierce. Statuses (status_system.gd) and item triggers (effect_runner.gd)
## run inside apply_damage(); weapon knockback rides in the damage context
## (`knockback`, `knockback_direction`) and is not applied yet (combat-feel PR).
const Contents = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const Player = preload("res://scripts/player.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const EffectRunner = preload("res://scripts/effect_runner.gd")

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
## Half-width of a thrust's hit capsule (COMBAT_AND_RPG §4.1: 10 px wide).
const THRUST_HALF_WIDTH := 5.0
## Seconds a beam tick stays drawn.
const BEAM_FLASH := 0.08
## Damage sources that credit the crawler with a kill (on_kill triggers).
const PLAYER_SOURCES := ["player", "status:", "effect:"]
## Enemy puddle colours by status tag (drawn by hazards.gd).
const PUDDLE_COLORS := {"poisoned": Color("#9bd34a"), "burning": Color("#ff7a2e"),
    "slowed": Color("#4fa3ff")}

## Live projectiles: {pos, velocity, ttl, owner ("player"/"enemy"), die, bonus,
## attack_bonus, source, mult}. Cleared on every room transition.
var projectiles: Array[Dictionary] = []
## Live ground hazards of the current room (hazards.gd entry shape: pos, radius,
## telegraph_remaining, damage, duration, source, kind, ...). Shared by grace
## debris, trap plates and enemy puddles. Cleared on every room transition.
var hazards: Array[Dictionary] = []
## Crawler velocity estimated from frame-to-frame movement (twin_shot lead).
var player_velocity := Vector2.ZERO
var _last_player_pos := Vector2.INF
var player: Player
var catalogue: Dictionary = {}
## Wave 2B: queued burst shots {delay, weapon_id} (fired from update_projectiles).
var pending_shots: Array[Dictionary] = []
## Wave 2B: beam ticks for the renderer {from, to, ttl}.
var beams: Array[Dictionary] = []
## Wave 2B: the last player swing for the renderer {pattern, origin, direction,
## reach, arc_degrees, width}; drawn while player.melee_flash > 0.
var last_swing: Dictionary = {}


func _ready() -> void:
    Events.room_entered.connect(_on_room_entered)


func setup(player_node: Player, enemy_catalogue: Dictionary) -> void:
    player = player_node
    catalogue = enemy_catalogue


## Every room entry (first visit or revisit) puts the room's enemies back on
## their spawn points, dormant for `encounters.dormancy` s. (Game clears
## hazards before the room swap.)
func _on_room_entered(_room_id: int, _kind: String, _entry: Dictionary, _first: bool) -> void:
    _last_player_pos = Vector2.INF
    player_velocity = Vector2.ZERO
    var dormancy: float = float(catalogue.get("encounters", {}).get("dormancy", 0.6))
    for foe in enemies():
        Enemies.on_room_entered(foe, dormancy)
        if String(foe.get("elite", "")) != "" and not bool(foe.get("boss", false)):
            Events.announcement_requested.emit("elite_spotted", {"enemy": String(foe["name"]),
                "text": "Elite detected: %s. Its loot is nicer than yours." % foe["name"],
                "priority": 3, "category": "warning"})


func enemies() -> Array:
    return RunState.current_room().get("enemies", [])


func blocked() -> Dictionary:
    return RunState.current_room().get("blocked", {})


func definition_of(foe: Dictionary) -> Dictionary:
    return catalogue["enemies"][foe["definition"]]


func clear_projectiles() -> void:
    projectiles.clear()
    pending_shots.clear()
    beams.clear()


# --- Ground hazards (Wave 2E) -------------------------------------------------

## Adds a hazard entry (normalised by hazards.gd) and emits `hazard_spawned`.
func spawn_hazard(entry: Dictionary) -> Dictionary:
    Hazards.normalize(entry)
    hazards.append(entry)
    Events.hazard_spawned.emit(entry)
    return entry


func clear_hazards() -> void:
    hazards.clear()


## Steps every hazard and applies its hits: flat damage through apply_damage()
## (i-frames skip the crawler inside hazards.gd) and tick drains through
## RunState.add_ticks(-n, source).
func update_hazards(delta: float) -> void:
    if hazards.is_empty():
        return
    var hits: Array[Dictionary] = Hazards.step(hazards, delta, {
        "pos": player.world_position, "radius": Player.RADIUS,
        "invulnerable": player.invulnerability > 0.0}, enemies())
    for hit in hits:
        var source: String = String(hit["entry"]["source"])
        # Wave 2B: a hazard's `status` (spore puddles, firebombs, floods) is applied.
        var status: String = String(hit["entry"].get("status", ""))
        if hit["target"] is String:
            if int(hit["damage"]) > 0 and RunState.hp > 0:
                apply_damage(player, int(hit["damage"]), {"source": source, "status": status,
                    "damage_type": String(hit["entry"].get("damage_type", "physical"))})
            elif status != "" and RunState.hp > 0:
                StatusSystem.apply_default("player", status, source)
            if int(hit["ticks"]) > 0:
                RunState.add_ticks(-int(hit["ticks"]), source)
        elif int(hit["target"]["hp"]) > 0:
            apply_damage(hit["target"], int(hit["damage"]), {"source": source,
                "damage_type": String(hit["entry"].get("damage_type", "physical"))})
            if status != "" and int(hit["target"]["hp"]) > 0:
                StatusSystem.apply_default(hit["target"], status, source)


## Fires the equipped ranged weapon along the current aim (the cooldown is the
## Player's job; Game passes the profile's cooldown to try_fire). Patterns:
## single, spread (projectile_count over spread_degrees), burst (burst_count
## shots burst_interval apart, jittered by spread_degrees), beam (one hitscan
## tick per trigger, i.e. every `cooldown` seconds while held).
## wpn_nail_pistol reproduces the prototype shot exactly.
func player_fire() -> void:
    var profile: Dictionary = Loadout.attack_profile("ranged")
    var aim: Vector2 = player.aim_direction
    match String(profile.get("pattern", "single")):
        "spread":
            for angle in spread_angles(int(profile["projectile_count"]),
                    float(profile["spread_degrees"])):
                _spawn_player_shot(profile, aim.rotated(deg_to_rad(angle)))
        "burst":
            _spawn_player_shot(profile, _jittered(aim, profile))
            for i in range(1, maxi(1, int(profile.get("burst_count", 1)))):
                pending_shots.append({"delay": float(profile["burst_interval"]) * float(i),
                    "weapon_id": String(profile["weapon_id"])})
        "beam":
            fire_beam(profile, player.world_position, aim)
        _:
            for angle in spread_angles(int(profile["projectile_count"]),
                    float(profile["spread_degrees"])):
                _spawn_player_shot(profile, aim.rotated(deg_to_rad(angle)))


## Fan angles in degrees for `count` projectiles over `spread` degrees total
## (centred on 0; one projectile flies straight).
static func spread_angles(count: int, spread: float) -> Array[float]:
    var angles: Array[float] = []
    if count <= 1:
        angles.append(0.0)
        return angles
    for i in range(count):
        angles.append(-spread * 0.5 + spread * float(i) / float(count - 1))
    return angles


func _jittered(aim: Vector2, profile: Dictionary) -> Vector2:
    var jitter: float = float(profile.get("spread_degrees", 0.0))
    if jitter <= 0.0:
        return aim
    return aim.rotated(deg_to_rad(RunState.rng.randf_range(-jitter * 0.5, jitter * 0.5)))


## One player projectile: the prototype keys (pos, velocity, ttl, owner, die,
## bonus, attack_bonus, source) plus pierce, knockback, effects (the weapon's
## effect ids), weapon_id, slot and hit (instance ids already hit).
func _spawn_player_shot(profile: Dictionary, direction: Vector2) -> Dictionary:
    var shot := {
        "pos": player.world_position + direction * PLAYER_SHOT_SPAWN,
        "velocity": direction * float(profile["projectile_speed"]), "ttl": float(profile["ttl"]),
        "owner": "player", "die": int(profile["die"]), "bonus": int(profile["damage_bonus"]),
        "attack_bonus": int(profile["attack_bonus"]), "source": "player",
        "pierce": int(profile["pierce"]), "knockback": float(profile["knockback"]),
        "effects": Array(profile.get("effects", [])).duplicate(),
        "weapon_id": String(profile["weapon_id"]), "slot": "ranged", "hit": {}
    }
    projectiles.append(shot)
    Events.projectile_fired.emit("player", shot)
    return shot


## Hitscan beam tick from `origin` along `aim` up to profile.range, stopped by
## obstacles; hits up to 1 + pierce enemies in order along the beam. Returns
## the enemy dictionaries hit (before the rolls).
func fire_beam(profile: Dictionary, origin: Vector2, aim: Vector2) -> Array:
    var obstacles: Dictionary = blocked()
    var reach: float = float(profile.get("range", 200.0))
    var travelled := PLAYER_SHOT_SPAWN
    while travelled < reach:
        if not Contents.can_occupy(origin + aim * (travelled + 2.0), PROJECTILE_RADIUS, obstacles):
            break
        travelled += 2.0
    var end: Vector2 = origin + aim * travelled
    var candidates: Array = []
    for foe in enemies():
        var along: float = (Vector2(foe["pos"]) - origin).dot(aim)
        if along <= 0.0 or along > travelled + float(foe["radius"]):
            continue
        var side: float = absf((Vector2(foe["pos"]) - origin).cross(aim))
        if side <= float(foe["radius"]) + HIT_SLOP:
            candidates.append([along, foe])
    candidates.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
    var hits: Array = []
    for pair in candidates.slice(0, 1 + int(profile.get("pierce", 0))):
        hits.append(pair[1])
    beams.append({"from": origin + aim * PLAYER_SHOT_SPAWN, "to": end, "ttl": BEAM_FLASH})
    Events.projectile_fired.emit("player", {"pos": origin, "velocity": Vector2.ZERO, "ttl": 0.0,
        "owner": "player", "die": int(profile["die"]), "bonus": int(profile["damage_bonus"]),
        "attack_bonus": int(profile["attack_bonus"]), "source": "player", "beam": true,
        "weapon_id": String(profile["weapon_id"])})
    for foe in hits:
        var index: int = _index_of(foe)
        if index >= 0:
            hit_enemy(index, int(profile["attack_bonus"]), int(profile["die"]),
                int(profile["damage_bonus"]), _attack_context(profile, "ranged", aim))
    return hits


## Swings the equipped melee weapon (COMBAT_AND_RPG §4.1): arc (sector of
## reach + enemy radius, width arc_degrees), thrust (a 10 px capsule of length
## reach along the aim, 1 + pierce targets nearest first) or spin (circle).
## Resolves instantly as in the prototype; wind-up/active/recovery frames and
## LOS belong to the combat-feel PR. wpn_crowbar reproduces the prototype
## swing (32 px, 0.5 s, d6 STR; 127 degrees = dot 0.446 vs the old 0.45).
func player_melee() -> void:
    Events.melee_swung.emit("player", player.world_position, player.aim_direction)
    var profile: Dictionary = Loadout.attack_profile("melee")
    var origin: Vector2 = player.world_position
    var aim: Vector2 = player.aim_direction
    last_swing = {"pattern": String(profile["pattern"]), "origin": origin, "direction": aim,
        "reach": float(profile["reach"]), "arc_degrees": float(profile["arc_degrees"]),
        "width": THRUST_HALF_WIDTH * 2.0}
    var targets: Array = []
    for i in melee_hits(profile, origin, aim, enemies()):
        targets.append(enemies()[i])
    for foe in targets:
        var index: int = _index_of(foe)
        if index < 0:
            continue
        var toward: Vector2 = Vector2(foe["pos"]) - origin
        var push: Vector2 = aim if String(profile["pattern"]) == "thrust" else toward.normalized()
        hit_enemy(index, int(profile["attack_bonus"]), int(profile["die"]),
            int(profile["damage_bonus"]), _attack_context(profile, "melee", push))


## Indices of `foes` a swing hits, in resolution order (pure, for tests).
## Arc and spin keep the prototype's order (highest index first); thrust is
## nearest first and capped at 1 + pierce.
static func melee_hits(profile: Dictionary, origin: Vector2, aim: Vector2, foes: Array) -> Array[int]:
    var result: Array[int] = []
    var reach: float = float(profile.get("reach", MELEE_REACH))
    match String(profile.get("pattern", "arc")):
        "thrust":
            var line: Array = []
            for i in range(foes.size()):
                var toward: Vector2 = Vector2(foes[i]["pos"]) - origin
                var radius: float = float(foes[i]["radius"])
                var along: float = toward.dot(aim)
                if along > 0.0 and along <= reach + radius \
                        and absf(toward.cross(aim)) <= THRUST_HALF_WIDTH + radius:
                    line.append([along, i])
            line.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
            for pair in line.slice(0, 1 + int(profile.get("pierce", 0))):
                result.append(int(pair[1]))
        "spin":
            for i in range(foes.size() - 1, -1, -1):
                var distance: float = (Vector2(foes[i]["pos"]) - origin).length()
                if distance <= reach + float(foes[i]["radius"]):
                    result.append(i)
        _:
            var threshold: float = float(profile.get("dot_threshold", MELEE_ARC_DOT))
            for i in range(foes.size() - 1, -1, -1):
                var toward: Vector2 = Vector2(foes[i]["pos"]) - origin
                if toward.length() <= reach + float(foes[i]["radius"]) and toward.length() > 0.01:
                    if aim.dot(toward.normalized()) > threshold:
                        result.append(i)
    return result


## Damage-context keys for a player weapon hit (merged by hit_enemy).
func _attack_context(profile: Dictionary, slot: String, direction: Vector2) -> Dictionary:
    return {"slot": slot, "direction": direction, "weapon_id": String(profile["weapon_id"]),
        "knockback": float(profile.get("knockback", 0.0)), "knockback_direction": direction,
        "effects": Array(profile.get("effects", [])).duplicate()}


func _index_of(foe: Dictionary) -> int:
    var foes: Array = enemies()
    for i in range(foes.size()):
        if is_same(foes[i], foe):
            return i
    return -1


## Player attack roll against enemy `index` of the current room. `extra` is
## merged into the apply_damage context (slot, direction, damage_type, and from
## Wave 2B weapon_id, knockback, knockback_direction, effects).
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
## the attacker's definition id. `status` (Wave 2B) is applied on a hit.
## Returns true when the attack landed.
func hit_player(to_hit: int, die: int, damage_bonus: int, source: String = "enemy",
        damage_mult: float = 1.0, status: String = "") -> bool:
    if player.invulnerability > 0.0 or StatusSystem.has_flag("player", "invulnerable"):
        return false
    var attack: Dictionary = RPG.roll_to_hit(RunState.rng, to_hit, RunState.ac)
    if not bool(attack["hit"]):
        Events.say("Enemy missed you (d20: %d)." % int(attack["d20"]), "combat")
        return false
    var damage: int = RPG.roll_damage(RunState.rng, die, damage_bonus, bool(attack["critical"]))
    if damage_mult != 1.0:
        damage = maxi(1, int(floorf(float(damage) * damage_mult)))
    apply_damage(player, damage, {"critical": bool(attack["critical"]), "source": source,
        "status": status})
    return true


## The damage pipeline. `target` is the Player node or an enemy dictionary from
## the current room. `context` keys: critical (bool), source (String), index
## (int, optional enemy index hint), damage_type ("physical" default), slot
## ("melee"/"ranged"), direction (Vector2 of travel). Returns the damage applied.
## Enemy side, in order: phase-roar invulnerability, Enemies.mitigate()
## (resistances, front guard, DR), then ward and shield pools absorb, then the
## `shielded` status (2B); after the HP change: on_hit (player attacks, i.e.
## source "player"), death, room_cleared, then on_kill (player, status: and
## effect: sources). Player side (2B): `evasive` ignores the hit, then
## damage_taken_mult, then `shielded` absorbs; after the HP change the
## context `status` is applied and on_damage_taken fires. Status ticks
## (source "status:<id>") do not start hit i-frames.
## Wave 2B context keys: weapon_id, knockback (px), knockback_direction
## (Vector2), effects (weapon effect ids), status (to apply on the player),
## triggers (false suppresses item triggers). Knockback is carried, not applied.
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
    amount = StatusSystem.absorb(foe, amount)
    if amount <= 0:
        Events.say("%s's shield soaks the hit." % label, "combat")
        return 0
    foe["hp"] = int(foe["hp"]) - amount
    Events.enemy_damaged.emit(String(foe["instance_id"]), amount,
        bool(context.get("critical", false)))
    Events.say("Hit %s for %d damage" % [label, amount], "combat")
    var triggers: bool = bool(context.get("triggers", true))
    if triggers and String(context.get("source", "")) == "player":
        EffectRunner.fire(self, "on_hit", {"target": foe, "slot": String(context.get("slot", "")),
            "weapon_id": String(context.get("weapon_id", "")), "damage": amount,
            "origin": Vector2(foe["pos"])}, String(context.get("slot", "")),
            String(context.get("weapon_id", "")))
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
    if triggers and _credits_player(context):
        EffectRunner.fire(self, "on_kill", {"target": foe, "slot": String(context.get("slot", "")),
            "weapon_id": String(context.get("weapon_id", "")), "origin": Vector2(foe["pos"])},
            String(context.get("slot", "")), String(context.get("weapon_id", "")))
    return amount


static func _credits_player(context: Dictionary) -> bool:
    var source: String = String(context.get("source", ""))
    for prefix in PLAYER_SOURCES:
        if source == prefix or (prefix.ends_with(":") and source.begins_with(prefix)):
            return true
    return false


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
        spawn_hazard(Hazards.make("volatile_burst", Vector2(foe["pos"]),
            float(burst.get("radius", 32)), float(burst.get("telegraph", 0.8)), damage, 0.0,
            String(foe["definition"]), {"hits_enemies": bool(burst.get("hits_enemies", true)),
                "damage_type": String(burst.get("damage_type", "fire")),
                "color": Color(String(foe.get("tint", "#ff8a3d")))}))


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
    var line: String = String(phases[index].get("announce", "%s changes tactics." % foe["name"]))
    Events.say(line, "combat")
    Events.announcement_requested.emit("boss_phase_changed", {"text": line, "priority": 4,
        "category": "warning", "enemy": String(foe["name"]), "phase": index + 1})


func _damage_player(amount: int, context: Dictionary) -> int:
    var source: String = String(context.get("source", "enemy"))
    var from_status: bool = source.begins_with("status:")
    if StatusSystem.has_flag("player", "invulnerable"):
        return 0
    var mult: float = float(Loadout.player_stats().get("damage_taken_mult", 1.0))
    if mult != 1.0:
        amount = maxi(0 if mult <= 0.0 else 1, int(floorf(float(amount) * mult)))
    amount = StatusSystem.absorb("player", amount)
    if amount <= 0:
        Events.say("Your shield absorbs the hit.", "combat")
        return 0
    var remaining: int = maxi(0, RunState.hp - amount)
    Events.say("You take %d damage. %d/%d HP." % [amount, remaining, RunState.max_hp], "combat")
    if not from_status:
        player.start_invulnerability()
    var applied: int = RunState.apply_damage_to_player(amount, source)
    if applied <= 0 or RunState.hp <= 0:
        return applied
    var status: String = String(context.get("status", ""))
    if status != "":
        StatusSystem.apply_default("player", status, source)
    if bool(context.get("triggers", true)):
        EffectRunner.fire(self, "on_damage_taken", {"damage": applied, "source": source})
    return applied


func update_projectiles(delta: float) -> void:
    _update_pending_shots(delta)
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
            # Wave 2B: a projectile hits each enemy once and passes through
            # `pierce` of them (prototype bolts have no "hit" registry: pierce 0).
            var foes: Array = enemies()
            var struck: Dictionary = bullet.get("hit", {})
            for j in range(foes.size() - 1, -1, -1):
                if struck.has(String(foes[j]["instance_id"])):
                    continue
                if position.distance_to(Vector2(foes[j]["pos"])) < float(foes[j]["radius"]) + HIT_SLOP:
                    struck[String(foes[j]["instance_id"])] = true
                    bullet["hit"] = struck
                    var direction: Vector2 = Vector2(bullet["velocity"]).normalized()
                    hit_enemy(j, int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]),
                        {"slot": "ranged", "direction": direction,
                            "weapon_id": String(bullet.get("weapon_id", "")),
                            "knockback": float(bullet.get("knockback", 0.0)),
                            "knockback_direction": direction,
                            "effects": bullet.get("effects", [])})
                    collided = struck.size() > int(bullet.get("pierce", 0))
                    break
        elif position.distance_to(player.world_position) < Player.RADIUS + HIT_SLOP:
            hit_player(int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]),
                String(bullet.get("source", "enemy")), float(bullet.get("mult", 1.0)))
            collided = true
        if collided and i < projectiles.size() and is_same(projectiles[i], bullet):
            projectiles.remove_at(i)


## Fires queued burst shots whose delay elapsed and ages beam flashes.
func _update_pending_shots(delta: float) -> void:
    for i in range(beams.size() - 1, -1, -1):
        beams[i]["ttl"] = float(beams[i]["ttl"]) - delta
        if float(beams[i]["ttl"]) <= 0.0:
            beams.remove_at(i)
    if pending_shots.is_empty():
        return
    var due: Array[Dictionary] = []
    for i in range(pending_shots.size() - 1, -1, -1):
        pending_shots[i]["delay"] = float(pending_shots[i]["delay"]) - delta
        if float(pending_shots[i]["delay"]) <= 0.0:
            due.push_front(pending_shots[i])
            pending_shots.remove_at(i)
    for entry in due:
        var profile: Dictionary = Loadout.attack_profile("ranged", String(entry["weapon_id"]))
        _spawn_player_shot(profile, _jittered(player.aim_direction, profile))


## Steps every enemy's state machine (dormancy, wind-up, resolution, recovery)
## and resolves the actions it returns. Hazards tick in update_hazards().
func update_enemies(delta: float) -> void:
    _track_player(delta)
    var foes: Array = enemies()
    # Wave 2B: a concealed crawler is replaced by its decoy as the AI target;
    # slowed/hasted scale each enemy's speed for this step only.
    var decoy: Vector2 = StatusSystem.decoy_position()
    var world := {"player_pos": player.world_position if decoy == Vector2.INF else decoy,
        "player_velocity": player_velocity if decoy == Vector2.INF else Vector2.ZERO,
        "blocked": blocked(), "allies": foes}
    for foe in foes.duplicate():
        if int(foe["hp"]) <= 0:
            continue
        var definition: Dictionary = definition_of(foe)
        var speed_mult: float = StatusSystem.speed_multiplier(foe)
        var base_speed = foe.get("speed")
        if speed_mult != 1.0 and base_speed != null:
            foe["speed"] = float(base_speed) * speed_mult
        var actions: Array[Dictionary] = Enemies.step(foe, definition, delta, world)
        if speed_mult != 1.0 and base_speed != null:
            foe["speed"] = base_speed
        for action in actions:
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
            # Wave 2B: while concealed, strikes land on the decoy.
            if not bool(action["hit"]) or StatusSystem.has_flag("player", "untargetable"):
                return
            var landed := true
            if attack.has("damage_die"):
                var numbers: Dictionary = Enemies.attack_numbers(foe, definition, attack)
                landed = hit_player(int(numbers["to_hit"]), int(numbers["die"]),
                    int(numbers["bonus"]), source, float(numbers["mult"]),
                    String(attack.get("status", "")))
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
            var status: String = String(spec.get("status", ""))
            spawn_hazard(Hazards.make("puddle", action["pos"], float(action["radius"]),
                float(spec.get("telegraph", 0.0)), damage, float(spec.get("duration", 0.0)), source,
                {"interval": float(spec.get("tick", 0.0)), "status": status,
                    "damage_type": String(attack.get("damage_type", "physical")),
                    "color": PUDDLE_COLORS.get(status, Hazards.DEFAULT_COLOR)}))
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
