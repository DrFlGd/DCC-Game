extends RefCounted
## Pure, data-driven rules for the multi-floor run loop (Wave 2A).
##
## Room count by depth (PROCEDURAL_GENERATION.md §3), the per-floor collapse
## budget (COLLAPSE_SYSTEM.md §4) and the victory depth. Static functions only;
## no nodes and no autoloads, so tests may preload this file.
##
## Config keys (game/data/prototype_rules.json):
##   run.target_depth            floor whose exit wins the run (default 6)
##   run.rooms_by_depth          room counts for depths 1..N (default 22..44)
##   run.rooms_per_extra_depth   rooms added per depth past the table (default 6)
##   run.max_rooms               room-count cap (default 80)
##   collapse.budget.min_slack   minimum slack ticks (default 8)
##   collapse.budget.slack_ratio slack per room (default 0.45)

const DEFAULT_TARGET_DEPTH := 6
const DEFAULT_ROOMS_BY_DEPTH := [22, 26, 30, 34, 40, 44]
const DEFAULT_ROOMS_PER_EXTRA_DEPTH := 6
const DEFAULT_MAX_ROOMS := 80
const DEFAULT_MIN_SLACK := 8
const DEFAULT_SLACK_RATIO := 0.45


static func target_depth(config: Dictionary) -> int:
    return maxi(1, int(config.get("run", {}).get("target_depth", DEFAULT_TARGET_DEPTH)))


## Rooms on floor `depth`: the table value, then +rooms_per_extra_depth per
## floor past the table, capped at max_rooms. Without a table, the legacy
## `room_count` key (or 22) is used for every depth.
static func room_count(depth: int, config: Dictionary) -> int:
    var run: Dictionary = config.get("run", {})
    var table: Array = run.get("rooms_by_depth", DEFAULT_ROOMS_BY_DEPTH)
    var cap: int = int(run.get("max_rooms", DEFAULT_MAX_ROOMS))
    if table.is_empty():
        return mini(cap, int(config.get("room_count", 22)))
    var d: int = maxi(1, depth)
    if d <= table.size():
        return mini(cap, int(table[d - 1]))
    var extra: int = int(run.get("rooms_per_extra_depth", DEFAULT_ROOMS_PER_EXTRA_DEPTH))
    return mini(cap, int(table.back()) + (d - table.size()) * extra)


## slack(rooms) = max(min_slack, ceil(slack_ratio * rooms)).
static func slack(rooms: int, config: Dictionary) -> int:
    var budget: Dictionary = config.get("collapse", {}).get("budget", {})
    var ratio: float = float(budget.get("slack_ratio", DEFAULT_SLACK_RATIO))
    var minimum: int = int(budget.get("min_slack", DEFAULT_MIN_SLACK))
    # Round before ceil so 0.45 * 20 = 9.000000000000002 stays 9.
    return maxi(minimum, int(ceil(snappedf(ratio * float(rooms), 0.0001))))


## Cheapest mandatory route start -> boss -> exit, paying first-entry costs.
## Dijkstra over room entries; each room's net cost (cost - grant) is clamped
## to >= 0 so grants never make the estimate optimistic. The start room is free,
## the exit is never used as a waypoint to the boss (it is sealed), rooms
## already paid for on the first leg are free on the second, and the exit's own
## cost is included. No "+1": the exit resolves before collapse.
## `policy` is a CollapsePolicy (anything with evaluate()).
static func mandatory_route_cost(floor_data: Dictionary, policy) -> int:
    var rooms: Array = floor_data["rooms"]
    var start_id: int = int(floor_data["start_id"])
    var boss_id: int = int(floor_data["boss_id"])
    var exit_id: int = int(floor_data["exit_id"])
    var entry_cost: Array[int] = []
    for room in rooms:
        var entry: Dictionary = policy.evaluate(100000, String(room["kind"]), true, int(room["id"]))
        entry_cost.append(maxi(0, int(entry["cost"]) - int(entry["grant"])))
    entry_cost[start_id] = 0
    var first: Dictionary = _cheapest_path(rooms, entry_cost, start_id, boss_id, {exit_id: true})
    if first.is_empty():
        return 0
    var paid: Array[int] = entry_cost.duplicate()
    for id in first["path"]:
        paid[int(id)] = 0
    var second: Dictionary = _cheapest_path(rooms, paid, boss_id, exit_id, {})
    return int(first["cost"]) + (int(second["cost"]) if not second.is_empty() else 0)


## Starting ticks for a generated floor:
## mandatory_route_cost + slack(room_count of that floor).
static func floor_budget(floor_data: Dictionary, policy, config: Dictionary) -> int:
    return mandatory_route_cost(floor_data, policy) + slack(floor_data["rooms"].size(), config)


## Public entry to the Dijkstra below (used by CollapsePolicy.mandatory_route
## for the generator's route checks, with tie-break weights folded into `cost`).
static func cheapest_path(rooms: Array, cost: Array[int], from_id: int, to_id: int,
        forbidden: Dictionary = {}) -> Dictionary:
    return _cheapest_path(rooms, cost, from_id, to_id, forbidden)


## Dijkstra from `from_id` to `to_id`, where stepping into room r costs
## cost[r]. Rooms in `forbidden` are never entered. Returns {cost, path} or {}.
static func _cheapest_path(rooms: Array, cost: Array[int], from_id: int, to_id: int,
        forbidden: Dictionary) -> Dictionary:
    var best: Dictionary = {from_id: 0}
    var parent: Dictionary = {from_id: -1}
    var done: Dictionary = {}
    while true:
        var current: int = -1
        for id in best:
            if done.has(id):
                continue
            # Ties break on the lower id so the result is deterministic.
            if current == -1 or int(best[id]) < int(best[current]) \
                    or (int(best[id]) == int(best[current]) and int(id) < current):
                current = int(id)
        if current == -1:
            return {}
        if current == to_id:
            break
        done[current] = true
        for neighbor in rooms[current]["neighbors"].values():
            var next_id: int = int(neighbor)
            if forbidden.has(next_id) or done.has(next_id):
                continue
            var total: int = int(best[current]) + cost[next_id]
            if not best.has(next_id) or total < int(best[next_id]):
                best[next_id] = total
                parent[next_id] = current
    var path: Array[int] = []
    var cursor: int = to_id
    while cursor != -1:
        path.push_front(cursor)
        cursor = int(parent[cursor])
    return {"cost": int(best[to_id]), "path": path}
