extends RefCounted
## Deterministic 24x24 obstacle/decoration map. Every linked exit is reachable
## from the center and from every other exit (flood fill on 4-neighbor cells).
const Interactables = preload("res://scripts/interactables.gd")
const SIZE := 24
const TILE := 16.0
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Obstacle caps per kind (PROCEDURAL_GENERATION §5); prototype_rules.json
## `room_obstacle_caps` overrides them. Kinds not listed use the full density.
## Boss rooms keep the prototype's full density until the clearance check lands.
const DEFAULT_CAPS := {"start": 13, "guild_hall": 13, "exit": 13, "treasure": 13,
    "shrine": 13, "trap": 20, "elite": 30}
## Safe kinds: no enemies, doors never lock (COMBAT_AND_RPG §9).
const SAFE_KINDS := ["start", "guild_hall", "exit", "treasure", "shrine"]
## Cells around the staging square where props (chest, shrine, rest station)
## may stand: inside the always-open 7x7 centre, off the central cross.
const FEATURE_RING := [Vector2i(9, 9), Vector2i(10, 9), Vector2i(9, 10), Vector2i(14, 9),
    Vector2i(13, 9), Vector2i(14, 10), Vector2i(9, 14), Vector2i(9, 13), Vector2i(10, 14),
    Vector2i(14, 14), Vector2i(13, 14), Vector2i(14, 13)]
## Default trap-plate settings (prototype_rules.json `hazards.trap_plates`).
const DEFAULT_PLATES := {"min": 2, "max": 4, "max_drain": 2}

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

## Obstacle count for `kind`: `density` capped by `caps` (DEFAULT_CAPS if empty).
static func density_for(kind: String, density: int, caps: Dictionary = {}) -> int:
    var table: Dictionary = caps if not caps.is_empty() else DEFAULT_CAPS
    return mini(density, int(table[kind])) if table.has(kind) else density


## Generates a room interior: {blocked, props, interactables, plates}.
## `props` are obstacles (rubble/pillar). `interactables` are
## Interactables.make() entries (chest, shrine, rest, shop) whose cells are
## also blocked. `plates` are trap pressure plates {id, cell, kind
## ("spike" | "drain"), armed, rearm}. Obstacle draws are unchanged from the
## prototype; features use their own RNG stream so obstacle maps of existing
## kinds keep their layout.
static func generate(seed_value: int, room_id: int, links: Dictionary, kind: String,
        density: int = 38, caps: Dictionary = {}, plate_rules: Dictionary = {}) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(seed_value) + int(room_id) * 7919 + 39317
    var blocked: Dictionary = {}
    var props: Array[Dictionary] = []
    density = density_for(kind, density, caps)
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
    var result := {"blocked": blocked, "props": props, "interactables": [], "plates": []}
    _add_features(result, seed_value, room_id, links, kind, plate_rules)
    return result


static func _add_features(result: Dictionary, seed_value: int, room_id: int, links: Dictionary,
        kind: String, plate_rules: Dictionary) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(seed_value) + int(room_id) * 7919 + 83492
    var blocked: Dictionary = result["blocked"]
    var features: Array = result["interactables"]
    var ring: Array = FEATURE_RING.duplicate()
    match kind:
        "treasure":
            features.append(Interactables.make("chest", ring[rng.randi_range(0, ring.size() - 1)],
                room_id))
        "shrine":
            features.append(Interactables.make("shrine", ring[rng.randi_range(0, ring.size() - 1)],
                room_id))
        "guild_hall":
            features.append(Interactables.make("rest", Vector2i(9, 9), room_id))
            # Wave 2B: the guild shop (ItemSystem registers the "shop" kind).
            features.append(Interactables.make("shop", Vector2i(14, 9), room_id,
                {"once": false}))
        "trap":
            result["plates"] = _trap_plates(rng, room_id, blocked, links, plate_rules)
    for feature in features:
        var cell: Vector2i = feature["cell"]
        blocked[cell] = true
        # Staging cells never disconnect a portal, but stay safe if that changes.
        if not exits_reachable(blocked, links):
            blocked.erase(cell)


static func _trap_plates(rng: RandomNumberGenerator, room_id: int, blocked: Dictionary,
        links: Dictionary, plate_rules: Dictionary) -> Array[Dictionary]:
    var rules: Dictionary = DEFAULT_PLATES.duplicate()
    rules.merge(plate_rules, true)
    var plates: Array[Dictionary] = []
    var wanted: int = rng.randi_range(int(rules["min"]), int(rules["max"]))
    # 1-2 drain plates (capped by max_drain), always leaving at least one spike.
    var drains: int = mini(mini(int(rules["max_drain"]), rng.randi_range(1, 2)), wanted - 1)
    var candidates: Array[Vector2i] = []
    for y in range(3, SIZE - 3):
        for x in range(3, SIZE - 3):
            var cell := Vector2i(x, y)
            # Not in the 4x4 centre (start spawn) or right inside a door.
            if x >= 10 and x <= 13 and y >= 10 and y <= 13:
                continue
            if (x == 11 or x == 12) and (y <= 3 or y >= 20):
                continue
            if (y == 11 or y == 12) and (x <= 3 or x >= 20):
                continue
            if not blocked.has(cell):
                candidates.append(cell)
    for i in range(candidates.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)
        var temp: Vector2i = candidates[i]
        candidates[i] = candidates[j]
        candidates[j] = temp
    for cell in candidates:
        if plates.size() >= wanted:
            break
        var crowded := false
        for plate in plates:
            var other: Vector2i = plate["cell"]
            if absi(other.x - cell.x) <= 1 and absi(other.y - cell.y) <= 1:
                crowded = true
                break
        if crowded:
            continue
        plates.append({"id": "plate_%d_%d" % [room_id, plates.size()], "cell": cell,
            "kind": "drain" if plates.size() < drains else "spike", "armed": true, "rearm": 0.0})
    return plates

static func can_occupy(point: Vector2, radius: float, blocked: Dictionary) -> bool:
    if point.x < radius or point.y < radius or point.x > SIZE * TILE - radius             or point.y > SIZE * TILE - radius:
        return false
    for delta in [Vector2(-radius, -radius), Vector2(radius, -radius),
            Vector2(-radius, radius), Vector2(radius, radius)]:
        if blocked.has(cell_of(point + delta)):
            return false
    return true
