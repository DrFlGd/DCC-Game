extends RefCounted
## Enemy definitions live in res://data/enemies.json, not in scene code.
const Room = preload("res://scripts/room_contents.gd")
const RPG = preload("res://scripts/rpg_rules.gd")

static func load_catalogue() -> Dictionary:
    var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
    return config if config is Dictionary else {}

static func generate_encounter(catalogue: Dictionary, kind: String, seed_value: int,
        room_id: int, blocked: Dictionary) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    var rng := RandomNumberGenerator.new()
    rng.seed = int(seed_value) * 73 + int(room_id) * 10211 + 41
    var table: Dictionary = catalogue.get("encounter_tables", {}).get(kind, {})
    var candidates: Array = []
    if table.has("fixed"):
        candidates = table["fixed"].duplicate()
    else:
        var pool: Array = table.get("pool", [])
        if not pool.is_empty():
            var count: int = rng.randi_range(int(table.get("min", 1)), int(table.get("max", 2)))
            for _i in range(count):
                candidates.append(pool[rng.randi_range(0, pool.size() - 1)])
    var defs: Dictionary = catalogue.get("enemies", {})
    for i in range(candidates.size()):
        var enemy_id: String = String(candidates[i])
        if not defs.has(enemy_id):
            push_warning("Unknown enemy definition: " + enemy_id)
            continue
        var template: Dictionary = defs[enemy_id]
        var position := Vector2.ZERO
        var placed := false
        for _attempt in range(150):
            var cell := Vector2i(rng.randi_range(2, 21), rng.randi_range(2, 21))
            var candidate_pos: Vector2 = Room.cell_center(cell)
            if not Room.is_walkable(cell, blocked) or not Room.can_occupy(candidate_pos,
                    float(template.get("collision_radius", 12)), blocked):
                continue
            if candidate_pos.distance_to(Room.cell_center(Vector2i(12, 12))) < 82.0:
                continue
            if Room.find_path(blocked, cell, Vector2i(12, 12)).is_empty():
                continue
            var collides := false
            for other in results:
                if candidate_pos.distance_to(Vector2(other["pos"])) < (
                        float(template.get("collision_radius", 12)) + float(other["radius"]) + 11.0):
                    collides = true
                    break
            if collides:
                continue
            position = candidate_pos
            placed = true
            break
        if not placed:
            push_warning("Could not place enemy " + enemy_id + " without blocking room")
            continue
        results.append({
            "instance_id": "%d_%d" % [room_id, i],
            "definition": enemy_id, "pos": position,
            "hp": int(template.get("hp", 5)), "max_hp": int(template.get("hp", 5)),
            "radius": float(template.get("collision_radius", 12)), "facing": 4,
            "attack_cooldown": rng.randf_range(0.2, 0.8),
            "repath": 0.0, "waypoints": []
        })
    return results

static func advance(enemy: Dictionary, definition: Dictionary, delta: float,
        player_pos: Vector2, blocked: Dictionary) -> void:
    var behavior: Dictionary = definition.get("behavior", {})
    var mode: String = String(behavior.get("mode", "chase"))
    var position: Vector2 = enemy["pos"]
    var to_player: Vector2 = player_pos - position
    var distance: float = to_player.length()
    if distance < 0.01 or distance > float(behavior.get("detection_range", 1000.0)):
        return
    var preferred: float = float(behavior.get("preferred_distance", 28.0))
    var navigation: String = String(behavior.get("pathfinding", "grid_bfs"))
    if navigation == "stationary" or (mode == "guard" and distance > preferred * 4.0):
        return
    var target: Vector2 = player_pos
    if mode == "kite":
        if distance >= preferred and distance <= preferred * 1.30:
            return
        if distance < preferred:
            var escape: Vector2 = -to_player.normalized()
            target = position + escape * 70.0
            target.x = clampf(target.x, 9.0, Room.SIZE * Room.TILE - 9.0)
            target.y = clampf(target.y, 9.0, Room.SIZE * Room.TILE - 9.0)
    elif distance < preferred:
        return
    if navigation == "direct":
        var straight: Vector2 = target - position
        if straight.length_squared() > 0.1:
            var trial: Vector2 = position + straight.normalized() * float(definition.get("speed", 55.0)) * delta
            if Room.can_occupy(trial, float(enemy["radius"]), blocked):
                enemy["pos"] = trial
                enemy["facing"] = posmod(int(round(straight.angle() / (PI / 4.0))), 8)
        return
    enemy["repath"] = float(enemy.get("repath", 0.0)) - delta
    var waypoints: Array = enemy.get("waypoints", [])
    if float(enemy["repath"]) <= 0.0 or waypoints.is_empty():
        enemy["repath"] = float(behavior.get("repath_seconds", 0.35))
        var start: Vector2i = Room.cell_of(position)
        var goal: Vector2i = Room.cell_of(target)
        var route: Array[Vector2i] = Room.find_path(blocked, start, goal)
        waypoints = []
        for cell in route:
            waypoints.append(Room.cell_center(cell))
        enemy["waypoints"] = waypoints
    if waypoints.is_empty():
        return
    if position.distance_to(Vector2(waypoints[0])) < 3.5:
        waypoints.remove_at(0)
    if waypoints.is_empty():
        return
    var movement: Vector2 = Vector2(waypoints[0]) - position
    if movement.length_squared() < 0.01:
        return
    var speed: float = float(definition.get("speed", 55.0))
    var abilities: Array = definition.get("abilities", [])
    if "lunge" in abilities and distance < 72.0:
        speed *= 1.35
    var next: Vector2 = position + movement.normalized() * minf(speed * delta, movement.length())
    if Room.can_occupy(next, float(enemy["radius"]), blocked):
        enemy["pos"] = next
        enemy["facing"] = posmod(int(round(movement.angle() / (PI / 4.0))), 8)

static func has_line_of_sight(from_pos: Vector2, to_pos: Vector2, blocked: Dictionary) -> bool:
    var displacement: Vector2 = to_pos - from_pos
    var steps: int = maxi(1, int(ceilf(displacement.length() / 4.0)))
    for i in range(1, steps):
        var point: Vector2 = from_pos + displacement * (float(i) / float(steps))
        if blocked.has(Room.cell_of(point)):
            return false
    return true

static func validate_catalogue(catalogue: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    var defs: Dictionary = catalogue.get("enemies", {})
    for enemy_id in defs.keys():
        var data: Dictionary = defs[enemy_id]
        for key in ["hp", "ac", "xp", "speed", "scores", "behavior", "attacks", "sprite"]:
            if not data.has(key):
                problems.append("%s: missing %s" % [enemy_id, key])
        for attack in data.get("attacks", []):
            if not ["melee", "ranged"].has(String(attack.get("type", ""))):
                problems.append("%s: invalid attack type" % enemy_id)
            if not RPG.ABILITIES.has(String(attack.get("ability", ""))):
                problems.append("%s: invalid attack ability" % enemy_id)
        var mode: String = String(data.get("behavior", {}).get("mode", ""))
        if not ["chase", "kite", "guard"].has(mode):
            problems.append("%s: unsupported AI mode" % enemy_id)
        var navigation: String = String(data.get("behavior", {}).get("pathfinding", "grid_bfs"))
        if not ["grid_bfs", "direct", "stationary"].has(navigation):
            problems.append("%s: unsupported pathfinding" % enemy_id)
    return problems
