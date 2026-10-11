extends RefCounted
## Deterministic grid-of-rooms graph. Room definitions are independent of rendering.
## IDs are stable within a seed. All adjacent occupied cells are joined by doors.

const CARDINAL := [
    Vector2i(0, -1),
    Vector2i(1, 0),
    Vector2i(0, 1),
    Vector2i(-1, 0)
]
const LABELS := ["N", "E", "S", "W"]


static func generate(seed_value: int, requested_count: int) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    var count: int = maxi(8, requested_count)
    var rooms: Array[Dictionary] = []
    var occupied: Dictionary = {}

    _append_room(rooms, occupied, Vector2i.ZERO)
    # A guaranteed main route: monotonically moves east/south, never self-intersects.
    var cursor := Vector2i.ZERO
    var spine_length: int = mini(maxi(int(round(float(count) * 0.35)), 5), count - 3)
    for _step in range(spine_length):
        cursor += CARDINAL[1] if rng.randi_range(0, 1) == 0 else CARDINAL[2]
        _append_room(rooms, occupied, cursor)

    var boss_id: int = spine_length - 1
    var exit_id: int = spine_length
    # Side branches and adjacency-created loops make the layout more interesting.
    while rooms.size() < count:
        var candidate_cells: Array[Vector2i] = []
        for room in rooms:
            var origin: Vector2i = room["grid"]
            for direction in CARDINAL:
                var candidate: Vector2i = origin + direction
                if not occupied.has(candidate) and not candidate_cells.has(candidate):
                    candidate_cells.append(candidate)
        if candidate_cells.is_empty():
            break
        var pick: int = rng.randi_range(0, candidate_cells.size() - 1)
        _append_room(rooms, occupied, candidate_cells[pick])

    # Index-based lookup and reciprocal links; adjacent rooms form optional loops.
    for room in rooms:
        var links: Dictionary = {}
        var grid: Vector2i = room["grid"]
        for index in range(CARDINAL.size()):
            if occupied.has(grid + CARDINAL[index]):
                links[LABELS[index]] = occupied[grid + CARDINAL[index]]
        room["neighbors"] = links

    rooms[0]["kind"] = "start"
    rooms[boss_id]["kind"] = "boss"
    rooms[exit_id]["kind"] = "exit"

    # Keep the guild hall off the guaranteed main spine to reward exploration.
    var side_ids: Array[int] = []
    for index in range(spine_length + 1, rooms.size()):
        side_ids.append(index)
    var guild_id: int = side_ids[rng.randi_range(0, side_ids.size() - 1)]
    rooms[guild_id]["kind"] = "guild_hall"

    return {
        "seed": seed_value,
        "rooms": rooms,
        "start_id": 0,
        "boss_id": boss_id,
        "exit_id": exit_id,
        "guild_id": guild_id
    }


static func _append_room(rooms: Array[Dictionary], occupied: Dictionary, grid: Vector2i) -> void:
    var room_id: int = rooms.size()
    rooms.append({"id": room_id, "grid": grid, "kind": "normal", "neighbors": {}})
    occupied[grid] = room_id


static func path_between(rooms: Array, from_id: int, to_id: int) -> Array[int]:
    var frontier: Array[int] = [from_id]
    var parent: Dictionary = {from_id: -1}
    var front_index := 0
    while front_index < frontier.size():
        var current: int = frontier[front_index]
        front_index += 1
        if current == to_id:
            break
        var neighbors: Dictionary = rooms[current]["neighbors"]
        for neighbor_id in neighbors.values():
            var next_id: int = int(neighbor_id)
            if not parent.has(next_id):
                parent[next_id] = current
                frontier.append(next_id)
    var result: Array[int] = []
    if not parent.has(to_id):
        return result
    var cursor: int = to_id
    while cursor != -1:
        result.push_front(cursor)
        cursor = int(parent[cursor])
    return result


static func signature(rooms: Array) -> String:
    var parts: PackedStringArray = []
    for room in rooms:
        var cell: Vector2i = room["grid"]
        var links: Dictionary = room["neighbors"]
        var directions: PackedStringArray = []
        for direction in LABELS:
            if links.has(direction):
                directions.append("%s%d" % [direction, int(links[direction])])
        parts.append("%d:%d,%d:%s:%s" % [
            int(room["id"]), cell.x, cell.y, String(room["kind"]), ",".join(directions)
        ])
    return "|".join(parts)
