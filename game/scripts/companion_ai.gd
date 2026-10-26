extends RefCounted
## Follower AI for the Wave 3E companion prototype (D-10, COMBAT_AND_RPG §13).
##
## Pure logic, like enemy_system.gd: no autoloads and no nodes, so tests may
## preload it. step() advances one companion dictionary and returns *actions*
## that the Companion node (companion.gd) resolves with its own RNG:
##   bite      {attack, target_id}   a bite whose wind-up finished in reach
##   teleport  {reason}              leash or stuck: moved beside the crawler
##   revive    {reason}              "channel" (crawler stood close) or "auto"
## Everything the companion remembers lives in its dictionary:
##   identity  id, name
##   body      pos, radius, facing (0..3 = E, S, W, N), hp, max_hp, ac, speed,
##             iframes (s)
##   AI        state ("follow", "engage", "return", "downed"), mode ("follow" or
##             "stay"), target_id, attack (id winding up or ""), wind_up (s left),
##             recovery (s left), aim, cooldowns {attack_id: s}, stuck_time,
##             waypoints, repath, downed_time, revive_progress
## `world` keys: crawler_pos (Vector2), blocked (Dictionary), foes (Array of
## live enemy dictionaries), preferred_id (the crawler's last target, or ""),
## crawler_aim (Vector2, optional).
const Room = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")

const STATES := ["follow", "engage", "return", "downed"]
## A follower farther than follow_distance × this starts "return" (hysteresis).
const RETURN_FACTOR := 1.8
## Extra reach slack when a finished wind-up checks its target again.
const REACH_SLACK := 2.0
## Engaged targets are kept until this far beyond engage_radius.
const DISENGAGE_SLACK := 32.0
const REPATH_SECONDS := 0.35


## Builds the live companion dictionary at `pos`. `level` is the crawler's
## level (hp_per_level scaling).
static func make_instance(definition: Dictionary, pos: Vector2, level: int = 1,
        companion_id: String = "") -> Dictionary:
    var hp: int = max_hp_for(definition, level)
    return {
        "id": companion_id, "name": String(definition.get("name", companion_id)),
        "pos": pos, "radius": float(definition.get("radius", 5.0)), "facing": 0,
        "hp": hp, "max_hp": hp, "ac": int(definition.get("ac", 12)),
        "speed": float(definition.get("speed", 110.0)), "iframes": 0.0,
        "state": "follow", "mode": "follow", "target_id": "", "attack": "", "wind_up": 0.0,
        "recovery": 0.0, "aim": Vector2.RIGHT, "cooldowns": {}, "stuck_time": 0.0,
        "waypoints": [], "repath": 0.0, "downed_time": 0.0, "revive_progress": 0.0
    }


static func max_hp_for(definition: Dictionary, level: int) -> int:
    return maxi(1, int(definition.get("hp", 10))
        + int(definition.get("hp_per_level", 0)) * (clampi(level, 1, 20) - 1))


## 0..3 = E, S, W, N (the four sheet columns before the downed frame).
static func facing_of(direction: Vector2) -> int:
    if direction.length_squared() < 0.0001:
        return 0
    return posmod(int(round(direction.angle() / (PI / 2.0))), 4)


static func is_down(companion: Dictionary) -> bool:
    return String(companion.get("state", "")) == "downed"


## {to_hit, die, bonus} for a companion attack at crawler level `level`
## (proficiency follows the crawler).
static func attack_numbers(definition: Dictionary, attack: Dictionary, level: int) -> Dictionary:
    var scores: Dictionary = definition.get("scores", {})
    var ability: String = String(attack.get("ability", "STR"))
    return {"to_hit": RPG.attack_bonus(scores, ability, level, bool(attack.get("proficient", true))),
        "die": int(attack.get("damage_die", 4)),
        "bonus": RPG.modifier(int(scores.get(ability, 10))) + int(attack.get("damage_bonus", 0))}


static func find(foes: Array, instance_id: String) -> Dictionary:
    if instance_id == "":
        return {}
    for foe in foes:
        if String(foe.get("instance_id", "")) == instance_id and int(foe.get("hp", 0)) > 0:
            return foe
    return {}


## Target selection (§13 as built): among living enemies within
## `engage_radius` of the crawler, the crawler's last target (`preferred_id`)
## wins; else the current target is kept while it stays within engage_radius +
## DISENGAGE_SLACK; else the enemy nearest the companion (ties: room order).
## In "stay" mode only enemies already in bite reach of the companion count.
static func choose_target(companion: Dictionary, definition: Dictionary, world: Dictionary) -> Dictionary:
    var crawler: Vector2 = world.get("crawler_pos", companion["pos"])
    var foes: Array = world.get("foes", [])
    var radius: float = float(definition.get("engage_radius", 160.0))
    var here: Vector2 = companion["pos"]
    var stay: bool = String(companion.get("mode", "follow")) == "stay"
    var attack: Dictionary = definition.get("attacks", [{}])[0]
    var preferred: Dictionary = find(foes, String(world.get("preferred_id", "")))
    if _eligible(preferred, crawler, radius, here, stay, attack):
        return preferred
    var current: Dictionary = find(foes, String(companion.get("target_id", "")))
    if _eligible(current, crawler, radius + DISENGAGE_SLACK, here, stay, attack):
        return current
    var best: Dictionary = {}
    var best_distance := INF
    for foe in foes:
        if not _eligible(foe, crawler, radius, here, stay, attack):
            continue
        var distance: float = here.distance_to(Vector2(foe["pos"]))
        if distance < best_distance:
            best_distance = distance
            best = foe
    return best


static func _eligible(foe: Dictionary, crawler: Vector2, radius: float, here: Vector2,
        stay: bool, attack: Dictionary) -> bool:
    if foe.is_empty() or int(foe.get("hp", 0)) <= 0:
        return false
    if stay:
        return in_reach(here, foe, attack)
    return crawler.distance_to(Vector2(foe["pos"])) <= radius


static func in_reach(here: Vector2, foe: Dictionary, attack: Dictionary, slack: float = 0.0) -> bool:
    return here.distance_to(Vector2(foe["pos"])) <= float(attack.get("range", 14.0)) \
        + float(foe.get("radius", 6.0)) + slack


## A free spot `distance` px from the crawler, behind its aim first, then
## rotating in 45-degree steps; falls back to the crawler's own position.
static func spot_beside(crawler: Vector2, aim: Vector2, distance: float, radius: float,
        blocked: Dictionary) -> Vector2:
    var back: Vector2 = -aim.normalized() if aim.length_squared() > 0.0001 else Vector2.LEFT
    for ring in [distance, distance * 0.6, 12.0]:
        for i in range(8):
            var turn: float = (PI / 4.0) * float((i + 1) >> 1) * (1.0 if i % 2 == 1 else -1.0)
            var candidate: Vector2 = crawler + back.rotated(turn) * float(ring)
            if Room.can_occupy(candidate, radius, blocked) \
                    and Enemies.has_line_of_sight(crawler, candidate, blocked):
                return candidate
    return crawler


## Moves toward `goal` by up to `travel` px: straight (sliding along an axis)
## with line of sight, else along a grid BFS path. Returns the distance moved.
static func walk_toward(companion: Dictionary, goal: Vector2, travel: float, blocked: Dictionary,
        delta: float) -> float:
    var start: Vector2 = companion["pos"]
    if travel <= 0.0 or start.distance_to(goal) < 0.5:
        return 0.0
    var radius: float = float(companion["radius"])
    var waypoint: Vector2 = goal
    if not Enemies.has_line_of_sight(start, goal, blocked):
        companion["repath"] = float(companion.get("repath", 0.0)) - delta
        var waypoints: Array = companion.get("waypoints", [])
        if float(companion["repath"]) <= 0.0 or waypoints.is_empty():
            companion["repath"] = REPATH_SECONDS
            waypoints = []
            for cell in Enemies.find_path_for(blocked, Room.cell_of(start), Room.cell_of(goal), radius):
                waypoints.append(Room.cell_center(cell))
            companion["waypoints"] = waypoints
        while not waypoints.is_empty() and start.distance_to(Vector2(waypoints[0])) < 3.5:
            waypoints.remove_at(0)
        if not waypoints.is_empty():
            waypoint = waypoints[0]
    else:
        companion["waypoints"] = []
    var movement: Vector2 = waypoint - start
    if movement.length_squared() < 0.0001:
        return 0.0
    var change: Vector2 = movement.normalized() * minf(travel, movement.length())
    var moved: Vector2 = start
    var horizontal: Vector2 = moved + Vector2(change.x, 0.0)
    if Room.can_occupy(horizontal, radius, blocked):
        moved = horizontal
    var vertical: Vector2 = moved + Vector2(0.0, change.y)
    if Room.can_occupy(vertical, radius, blocked):
        moved = vertical
    companion["pos"] = moved
    companion["facing"] = facing_of(movement)
    return start.distance_to(moved)


## Puts the companion beside the crawler, clears its path and target, and
## (unless downed) returns it to "follow".
static func teleport(companion: Dictionary, definition: Dictionary, world: Dictionary) -> void:
    companion["pos"] = spot_beside(world.get("crawler_pos", companion["pos"]),
        world.get("crawler_aim", Vector2.RIGHT), float(definition.get("follow_distance", 28.0)),
        float(companion["radius"]), world.get("blocked", {}))
    companion["waypoints"] = []
    companion["repath"] = 0.0
    companion["stuck_time"] = 0.0
    companion["target_id"] = ""
    companion["attack"] = ""
    companion["wind_up"] = 0.0
    if not is_down(companion):
        companion["state"] = "follow"


## Advances `companion` by `delta` seconds; returns the actions to resolve.
static func step(companion: Dictionary, definition: Dictionary, delta: float,
        world: Dictionary) -> Array[Dictionary]:
    var actions: Array[Dictionary] = []
    var cooldowns: Dictionary = companion["cooldowns"]
    for key in cooldowns.keys():
        cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
    companion["iframes"] = maxf(0.0, float(companion.get("iframes", 0.0)) - delta)
    var crawler: Vector2 = world.get("crawler_pos", companion["pos"])
    var blocked: Dictionary = world.get("blocked", {})
    var here: Vector2 = companion["pos"]
    if is_down(companion):
        _step_downed(companion, definition, delta, crawler, actions)
        return actions
    var attack: Dictionary = definition.get("attacks", [{}])[0]
    # Wind-up: rooted, aim locked; resolves against the target if still in reach.
    if float(companion.get("wind_up", 0.0)) > 0.0:
        companion["wind_up"] = float(companion["wind_up"]) - delta
        if float(companion["wind_up"]) <= 0.0:
            companion["wind_up"] = 0.0
            var target: Dictionary = find(world.get("foes", []), String(companion["target_id"]))
            cooldowns[String(attack["id"])] = float(attack.get("cooldown", 1.0))
            companion["recovery"] = float(attack.get("recovery", 0.2))
            companion["attack"] = ""
            if not target.is_empty() and in_reach(here, target, attack, REACH_SLACK):
                actions.append({"type": "bite", "attack": attack,
                    "target_id": String(target["instance_id"])})
        return actions
    if float(companion.get("recovery", 0.0)) > 0.0:
        companion["recovery"] = maxf(0.0, float(companion["recovery"]) - delta)
        return actions
    # Leash: too far from the crawler (a dash, a knockback, a long chase).
    if here.distance_to(crawler) > float(definition.get("leash_distance", 170.0)):
        teleport(companion, definition, world)
        actions.append({"type": "teleport", "reason": "leash"})
        return actions
    var speed: float = float(companion["speed"])
    var follow: float = float(definition.get("follow_distance", 28.0))
    var stay: bool = String(companion.get("mode", "follow")) == "stay"
    var goal := Vector2.INF
    var travel := 0.0
    var target: Dictionary = choose_target(companion, definition, world)
    if not target.is_empty():
        companion["state"] = "engage"
        companion["target_id"] = String(target["instance_id"])
        var toward: Vector2 = Vector2(target["pos"]) - here
        if in_reach(here, target, attack):
            if toward.length_squared() > 0.0001:
                companion["aim"] = toward.normalized()
                companion["facing"] = facing_of(toward)
            if float(cooldowns.get(String(attack["id"]), 0.0)) <= 0.0:
                companion["attack"] = String(attack["id"])
                companion["wind_up"] = maxf(0.001, float(attack.get("wind_up", 0.15)))
        elif not stay:
            goal = Vector2(target["pos"]) - toward.normalized() \
                * (float(attack.get("range", 14.0)) * 0.6 + float(target.get("radius", 6.0)))
            travel = speed * delta
    else:
        var was_engaged: bool = String(companion["state"]) == "engage"
        companion["target_id"] = ""
        var distance: float = here.distance_to(crawler)
        if stay:
            companion["state"] = "follow"
        elif String(companion["state"]) == "return" or was_engaged \
                or distance > follow * RETURN_FACTOR:
            companion["state"] = "return" if distance > follow else "follow"
            if distance > follow:
                goal = crawler
                travel = speed * float(definition.get("return_speed_mult", 1.3)) * delta
        else:
            companion["state"] = "follow"
            if distance > follow:
                goal = crawler
                travel = minf(speed * delta, distance - follow)
    if goal == Vector2.INF or travel <= 0.0:
        companion["stuck_time"] = 0.0
        return actions
    var moved: float = walk_toward(companion, goal, travel, blocked, delta)
    if moved < travel * 0.2:
        companion["stuck_time"] = float(companion.get("stuck_time", 0.0)) + delta
    else:
        companion["stuck_time"] = 0.0
    if float(companion["stuck_time"]) >= float(definition.get("stuck_seconds", 1.5)):
        teleport(companion, definition, world)
        actions.append({"type": "teleport", "reason": "stuck"})
    return actions


static func _step_downed(companion: Dictionary, definition: Dictionary, delta: float,
        crawler: Vector2, actions: Array[Dictionary]) -> void:
    var revive: Dictionary = definition.get("revive", {})
    companion["downed_time"] = float(companion.get("downed_time", 0.0)) + delta
    if Vector2(companion["pos"]).distance_to(crawler) <= float(revive.get("radius", 24.0)):
        companion["revive_progress"] = float(companion.get("revive_progress", 0.0)) + delta
    else:
        companion["revive_progress"] = 0.0
    var auto: float = float(revive.get("auto_seconds", 0.0))
    if float(companion["revive_progress"]) >= float(revive.get("channel_seconds", 2.0)):
        actions.append({"type": "revive", "reason": "channel"})
    elif auto > 0.0 and float(companion["downed_time"]) >= auto:
        actions.append({"type": "revive", "reason": "auto"})


## Knocks the companion down: clears its attack and target.
static func knock_down(companion: Dictionary) -> void:
    companion["hp"] = 0
    companion["state"] = "downed"
    companion["target_id"] = ""
    companion["attack"] = ""
    companion["wind_up"] = 0.0
    companion["recovery"] = 0.0
    companion["waypoints"] = []
    companion["downed_time"] = 0.0
    companion["revive_progress"] = 0.0


## Stands the companion back up with `ratio` of its max HP (at least 1).
static func stand_up(companion: Dictionary, ratio: float) -> void:
    companion["hp"] = clampi(int(ceilf(float(companion["max_hp"]) * ratio)), 1, int(companion["max_hp"]))
    companion["state"] = "follow"
    companion["downed_time"] = 0.0
    companion["revive_progress"] = 0.0
    companion["iframes"] = 1.0
