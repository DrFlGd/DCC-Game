extends RefCounted
## Deterministic grid-of-rooms graph. Room definitions are independent of rendering.
## IDs are stable within a seed. All adjacent occupied cells are joined by doors.
##
## Wave 2E adds special room kinds (treasure, elite, trap, shrine) and the
## feasibility pass of PROCEDURAL_GENERATION.md §6: a floor whose mandatory
## route is unaffordable (or breaks another check) is regenerated with
## `seed + attempt x feasibility.seed_stride`, deterministically, and the
## result is recorded under `floor["feasibility"]`.
## Pure module: no autoload references, safe to preload from tests.

const Collapse = preload("res://scripts/collapse_policy.gd")
const CONFIG_PATH := "res://data/prototype_rules.json"
const CARDINAL := [
    Vector2i(0, -1),
    Vector2i(1, 0),
    Vector2i(0, 1),
    Vector2i(-1, 0)
]
const LABELS := ["N", "E", "S", "W"]
## Assignment order of the special kinds (PROCEDURAL_GENERATION §4.2).
const SPECIAL_ORDER := ["treasure", "elite", "trap", "shrine"]
## Kinds with fixed roles; every other room is "normal" or a special kind.
const FIXED_KINDS := ["start", "boss", "exit", "guild_hall"]

static var _config_cache: Dictionary = {}


## prototype_rules.json, parsed once. Used when `options.config` is absent so
## `generate(seed, count)` matches what Game generates.
static func default_config() -> Dictionary:
    if _config_cache.is_empty():
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
        _config_cache = parsed if parsed is Dictionary else {}
    return _config_cache


## Generates floor `options.depth` (default 1) for `seed_value`.
## options: depth (int), config (prototype_rules dictionary; default: the file),
## budget (int > 0: test feasibility against this fixed budget instead of
## CollapsePolicy.budget_for).
## Returns {seed, generation_seed, depth, rooms, start_id, boss_id, exit_id,
## guild_id, specials {kind: [ids]}, relaxations [..], mandatory_route [ids],
## mandatory_route_cost, budget, feasibility {ok, attempt, attempts, checks}}.
static func generate(seed_value: int, requested_count: int, options: Dictionary = {}) -> Dictionary:
    var depth: int = maxi(1, int(options.get("depth", 1)))
    var config: Dictionary = options.get("config", {})
    if config.is_empty():
        config = default_config()
    var generation: Dictionary = config.get("generation", {})
    var policy = Collapse.new(config.get("collapse", {}))
    var feasibility_config: Dictionary = generation.get("feasibility", {})
    var max_attempts: int = maxi(1, int(feasibility_config.get("max_attempts", 20)))
    var stride: int = int(feasibility_config.get("seed_stride", 104729))
    var fixed_budget: int = int(options.get("budget", 0))
    var first: Dictionary = {}
    for attempt in range(max_attempts):
        var generation_seed: int = seed_value + attempt * stride
        var floor: Dictionary = _generate_layout(generation_seed, requested_count, depth,
            generation, policy)
        floor["seed"] = seed_value
        floor["generation_seed"] = generation_seed
        var checks: Dictionary = feasibility(floor, policy, fixed_budget)
        floor["feasibility"] = {"ok": bool(checks["ok"]), "attempt": attempt,
            "attempts": attempt + 1, "checks": checks}
        if attempt == 0:
            first = floor
        if bool(checks["ok"]):
            return floor
    # Exhausted: an error for CI; play falls back to attempt 0 (PROCEDURAL_GENERATION §6).
    push_error("Floor generation: no feasible layout for seed %d depth %d after %d attempts"
        % [seed_value, depth, max_attempts])
    first["feasibility"]["attempts"] = max_attempts
    return first


## Runs the generation checks on `floor` and records route/budget fields on it.
## Returns {ok, route (F1/F2), slack (F3), optional_off_route (F5, guild included),
## guild_reachable (§9.4), budget_cap, failed [names]}.
static func feasibility(floor: Dictionary, policy, fixed_budget: int = 0) -> Dictionary:
    var budget_settings: Dictionary = policy.settings.get("budget", {})
    var min_slack: int = int(budget_settings.get("min_slack", 8))
    var cap: int = int(budget_settings.get("max_start_ticks", 70))
    var guild_ratio: float = float(budget_settings.get("guild_max_ratio", 0.5))
    var route: Dictionary = Collapse.mandatory_route(floor, policy)
    var rooms: Array = floor["rooms"]
    var route_cost: int = int(route["cost"])
    var budget: int = fixed_budget if fixed_budget > 0 \
        else Collapse.budget_for(floor, rooms.size(), policy)
    floor["mandatory_route"] = route["rooms"]
    floor["mandatory_route_cost"] = route_cost
    floor["budget"] = budget
    var checks := {
        "route": not Array(route["rooms"]).is_empty(),
        "slack": budget - route_cost >= min_slack,
        "budget_cap": budget <= cap,
        "optional_off_route": true,
        "guild_reachable": true
    }
    for id in route["rooms"]:
        if Collapse.OFF_ROUTE_KINDS.has(String(rooms[int(id)]["kind"])):
            checks["optional_off_route"] = false
    var guild_id: int = int(floor.get("guild_id", -1))
    if guild_id >= 0:
        var to_guild: Dictionary = Collapse.cheapest_path(rooms, int(floor["start_id"]),
            guild_id, policy, {int(floor["exit_id"]): true})
        checks["guild_reachable"] = not Array(to_guild["rooms"]).is_empty() \
            and float(to_guild["cost"]) <= guild_ratio * float(budget)
    var failed: Array[String] = []
    for key in checks.keys():
        if not bool(checks[key]):
            failed.append(String(key))
    checks["failed"] = failed
    checks["ok"] = failed.is_empty()
    return checks


## Special-room counts for `depth` from `generation.special_rooms.counts_by_depth`
## (the last row whose min_depth <= depth wins; missing kinds are 0).
static func special_counts(depth: int, generation: Dictionary) -> Dictionary:
    var counts: Dictionary = {}
    for kind in SPECIAL_ORDER:
        counts[kind] = 0
    var rows: Array = generation.get("special_rooms", {}).get("counts_by_depth", [
        {"min_depth": 1, "treasure": 1}])
    for row in rows:
        if int(row.get("min_depth", 1)) <= depth:
            for kind in SPECIAL_ORDER:
                if row.has(kind):
                    counts[kind] = int(row[kind])
    return counts


static func _generate_layout(seed_value: int, requested_count: int, depth: int,
        generation: Dictionary, policy) -> Dictionary:
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
    var floor: Dictionary = {
        "depth": depth,
        "rooms": rooms,
        "start_id": 0,
        "boss_id": boss_id,
        "exit_id": exit_id,
        "guild_id": guild_id,
        "spine_length": spine_length,
        "specials": {},
        "relaxations": []
    }
    # Every draw below is appended after the prototype's draws, so existing
    # seeds keep their geometry (PROCEDURAL_GENERATION §2).
    var hops: Dictionary = hop_distances(rooms, 0)
    var special_rules: Dictionary = generation.get("special_rooms", {})
    var guild_min_hops: int = int(special_rules.get("guild_min_hops", 2))
    var guild_limit: float = float(policy.settings.get("budget", {}).get("guild_max_ratio", 0.5)) \
        * float(Collapse.budget_for(floor, rooms.size(), policy))
    if not _guild_ok(floor, guild_id, hops, guild_min_hops, guild_limit, policy):
        var eligible: Array[int] = []
        for id in side_ids:
            if _guild_ok(floor, id, hops, guild_min_hops, guild_limit, policy):
                eligible.append(id)
        if not eligible.is_empty():
            guild_id = eligible[rng.randi_range(0, eligible.size() - 1)]
            floor["relaxations"].append({"kind": "guild_hall", "level": 0,
                "note": "re-picked: within %d hops of start, on the cheapest route or too costly to reach" % guild_min_hops})
    floor["guild_id"] = guild_id
    rooms[guild_id]["kind"] = "guild_hall"
    _assign_specials(floor, rng, special_counts(depth, generation), special_rules, hops, policy)
    return floor


static func _guild_ok(floor: Dictionary, id: int, hops: Dictionary, min_hops: int,
        cost_limit: float, policy) -> bool:
    if int(hops.get(id, 0)) < min_hops:
        return false
    var rooms: Array = floor["rooms"]
    var previous: String = String(rooms[id]["kind"])
    rooms[id]["kind"] = "guild_hall"
    var path: Dictionary = Collapse.cheapest_path(rooms, 0, id, policy,
        {int(floor["exit_id"]): true})
    var on_route: bool = Collapse.mandatory_route(floor, policy)["rooms"].has(id)
    rooms[id]["kind"] = previous
    return not on_route and not Array(path["rooms"]).is_empty() \
        and float(path["cost"]) <= cost_limit


## Assigns treasure, elite, trap and shrine rooms (PROCEDURAL_GENERATION §4.2).
## Relaxation levels: 0 = every rule and preference, 1 = no preferences
## (dead end, 2x weight), 2 = no adjacency rules 5-7; when level 2 has no
## candidate, the kind's count drops by one. Every relaxation is logged in
## floor.relaxations as {kind, level, note}.
static func _assign_specials(floor: Dictionary, rng: RandomNumberGenerator, counts: Dictionary,
        rules: Dictionary, hops: Dictionary, policy) -> void:
    var rooms: Array = floor["rooms"]
    var spine_length: int = int(floor["spine_length"])
    var elite_min_hops: int = int(rules.get("elite_min_hops", 3))
    var specials: Dictionary = floor["specials"]
    for kind in SPECIAL_ORDER:
        specials[kind] = []
        for _n in range(int(counts.get(kind, 0))):
            var excluded: Dictionary = {}
            var placed := false
            while not placed:
                var choice: Dictionary = _pick_special(rooms, rng, kind, spine_length, hops,
                    elite_min_hops, excluded)
                var id: int = int(choice["id"])
                if id < 0:
                    floor["relaxations"].append({"kind": kind, "level": 3,
                        "note": "count reduced by 1: no eligible side room"})
                    break
                rooms[id]["kind"] = kind
                # F5: optional kinds must stay off the cheapest mandatory route.
                if Collapse.OPTIONAL_KINDS.has(kind) and \
                        Collapse.mandatory_route(floor, policy)["rooms"].has(id):
                    rooms[id]["kind"] = "normal"
                    excluded[id] = true
                    continue
                if int(choice["level"]) > 0:
                    floor["relaxations"].append({"kind": kind, "level": int(choice["level"]),
                        "note": "dropped preferences" if int(choice["level"]) == 1
                            else "dropped adjacency rules"})
                specials[kind].append(id)
                placed = true


static func _pick_special(rooms: Array, rng: RandomNumberGenerator, kind: String,
        spine_length: int, hops: Dictionary, elite_min_hops: int,
        excluded: Dictionary) -> Dictionary:
    for level in range(3):
        var ids: Array[int] = []
        var weights: Array[float] = []
        for room in rooms:
            var id: int = int(room["id"])
            if id <= spine_length or String(room["kind"]) != "normal" or excluded.has(id):
                continue
            var near: Array[String] = _neighbor_kinds(rooms, room)
            var degree: int = room["neighbors"].size()
            # Hard rules (never relaxed).
            if kind == "treasure" and near.has("start"):
                continue
            if kind == "elite" and int(hops.get(id, 0)) < elite_min_hops:
                continue
            # Adjacency rules 5-7 (dropped at level 2).
            if level < 2:
                if near.has(kind):
                    continue
                if kind == "trap" and (near.has("guild_hall") or degree <= 1):
                    continue
                if kind == "shrine" and _has_special_neighbor(near):
                    continue
            var weight := 1.0
            # Preferences (dropped at level 1).
            if level == 0:
                if kind == "treasure" and degree != 1:
                    continue
                if kind == "elite" and near.has("treasure"):
                    weight = 2.0
            ids.append(id)
            weights.append(weight)
        if ids.is_empty():
            continue
        var total := 0.0
        for weight in weights:
            total += weight
        var point: float = rng.randf() * total
        for i in range(ids.size()):
            point -= weights[i]
            if point < 0.0 or i == ids.size() - 1:
                return {"id": ids[i], "level": level}
    return {"id": -1, "level": 3}


static func _neighbor_kinds(rooms: Array, room: Dictionary) -> Array[String]:
    var kinds: Array[String] = []
    for neighbor in room["neighbors"].values():
        kinds.append(String(rooms[int(neighbor)]["kind"]))
    return kinds


static func _has_special_neighbor(kinds: Array[String]) -> bool:
    for kind in kinds:
        if SPECIAL_ORDER.has(kind) or kind == "guild_hall":
            return true
    return false


static func _append_room(rooms: Array[Dictionary], occupied: Dictionary, grid: Vector2i) -> void:
    var room_id: int = rooms.size()
    rooms.append({"id": room_id, "grid": grid, "kind": "normal", "neighbors": {}})
    occupied[grid] = room_id


## Hop distance (BFS over doors) from `from_id` to every reachable room.
static func hop_distances(rooms: Array, from_id: int) -> Dictionary:
    var distances: Dictionary = {from_id: 0}
    var frontier: Array[int] = [from_id]
    var index := 0
    while index < frontier.size():
        var current: int = frontier[index]
        index += 1
        for neighbor in rooms[current]["neighbors"].values():
            if not distances.has(int(neighbor)):
                distances[int(neighbor)] = int(distances[current]) + 1
                frontier.append(int(neighbor))
    return distances


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


## Determinism fingerprint: id, grid cell, kind and links of every room.
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
