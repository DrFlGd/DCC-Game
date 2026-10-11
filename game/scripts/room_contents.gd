extends RefCounted
## Deterministic 24x24 obstacle/decoration map. Every linked exit is reachable
## from the center and from every other exit (flood fill on 4-neighbor cells).
const SIZE := 24
const TILE := 16.0
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func portal_cells(direction: String) -> Array[Vector2i]:
    match direction:
        "N": return [Vector2i(11, 0), Vector2i(12, 0)]
        "S": return [Vector2i(11, 23), Vector2i(12, 23)]
        "W": return [Vector2i(0, 11), Vector2i(0, 12)]
        "E": return [Vector2i(23, 11), Vector2i(23, 12)]
    return []

static func cell_of(point: Vector2) -> Vector2i:
    return Vector2i(int(floorf(point.x / TILE)), int(floorf(point.y / TILE)))

static func cell_center(cell: Vector2i) -> Vector2:
    return Vector2(cell) * TILE + Vector2.ONE * (TILE * 0.5)

static func is_walkable(cell: Vector2i, blocked: Dictionary) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and not blocked.has(cell)

static func find_path(blocked: Dictionary, start: Vector2i, target: Vector2i) -> Array[Vector2i]:
    var empty: Array[Vector2i] = []
    if not is_walkable(start, blocked) or not is_walkable(target, blocked):
        return empty
    var queue: Array[Vector2i] = [start]
    var parents: Dictionary = {start: start}
    var index := 0
    while index < queue.size():
        var cell: Vector2i = queue[index]
        index += 1
        if cell == target:
            break
        for direction in DIRECTIONS:
            var neighbor: Vector2i = cell + direction
            if is_walkable(neighbor, blocked) and not parents.has(neighbor):
                parents[neighbor] = cell
                queue.append(neighbor)
    if not parents.has(target):
        return empty
    var path: Array[Vector2i] = []
    var current: Vector2i = target
    while current != start:
        path.push_front(current)
        current = parents[current]
    path.push_front(start)
    return path

static func exits_reachable(blocked: Dictionary, links: Dictionary) -> bool:
    var start := Vector2i(12, 12)
    if not is_walkable(start, blocked):
        return false
    for key in links.keys():
        var targets: Array[Vector2i] = portal_cells(String(key))
        var connected := false
        for target in targets:
            if not find_path(blocked, start, target).is_empty():
                connected = true
                break
        if not connected:
            return false
    return true

static func generate(seed_value: int, room_id: int, links: Dictionary, kind: String,
        density: int = 38) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(seed_value) + int(room_id) * 7919 + 39317
    var blocked: Dictionary = {}
    var props: Array[Dictionary] = []
    if kind == "start" or kind == "guild_hall" or kind == "exit":
        density = mini(density, 13)
    var candidates: Array[Vector2i] = []
    for y in range(2, SIZE - 2):
        for x in range(2, SIZE - 2):
            var cell := Vector2i(x, y)
            # Keep an open center staging area for player and several enemies.
            if abs(x - 12) <= 3 and abs(y - 12) <= 3:
                continue
            # Door approach lanes must remain clear for both halves of each portal.
            if (abs(x - 11) <= 2 or abs(x - 12) <= 2) and (y <= 3 or y >= 20):
                continue
            if (abs(y - 11) <= 2 or abs(y - 12) <= 2) and (x <= 3 or x >= 20):
                continue
            candidates.append(cell)
    # Deterministic Fisher–Yates shuffle.
    for i in range(candidates.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)
        var temp: Vector2i = candidates[i]
        candidates[i] = candidates[j]
        candidates[j] = temp
    for cell in candidates:
        if blocked.size() >= density:
            break
        blocked[cell] = true
        if not exits_reachable(blocked, links):
            blocked.erase(cell)
            continue
        var kind_name := "rubble" if rng.randf() < 0.63 else "pillar"
        props.append({"cell": cell, "kind": kind_name})
    return {"blocked": blocked, "props": props}

static func can_occupy(point: Vector2, radius: float, blocked: Dictionary) -> bool:
    if point.x < radius or point.y < radius or point.x > SIZE * TILE - radius             or point.y > SIZE * TILE - radius:
        return false
    for delta in [Vector2(-radius, -radius), Vector2(radius, -radius),
            Vector2(-radius, radius), Vector2(radius, radius)]:
        if blocked.has(cell_of(point + delta)):
            return false
    return true
