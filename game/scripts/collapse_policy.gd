extends RefCounted
## Pure, configuration-driven collapse clock rules (COLLAPSE_SYSTEM.md, clock v1).
##
## Instances wrap the `collapse` block of prototype_rules.json and price door
## transitions (evaluate). Static functions cover the floor budget (D-04), the
## cheapest mandatory route, and the zero-clock grace period (D-05).
## No autoload references: tests may preload this script.
## No cost is a claim about the book canon. Costs are deliberate prototype defaults.

const RunRules = preload("res://scripts/core/run_rules.gd")
## Kinds that must never lie on the cheapest mandatory route (COLLAPSE_SYSTEM §9.3).
const OPTIONAL_KINDS := ["elite", "trap", "shrine"]
## OPTIONAL_KINDS plus the guild hall, which is kept off the cheapest route too
## (§9.4 "not on the spine"): a free guild on an equal-length detour would
## otherwise make the route, and so the budget, 2 ticks cheaper.
const OFF_ROUTE_KINDS := ["elite", "trap", "shrine", "guild_hall"]
## Tie-break weight so the route search prefers routes without optional kinds.
const _SPECIAL_PENALTY := 1
const _COST_SCALE := 1000

var settings: Dictionary


func _init(config: Dictionary = {}) -> void:
    settings = config


## Prices a door transition. v1 semantics (D-03): a transition is never refused
## for lack of ticks, so `allowed` is always true (a sealed exit is refused by
## Game before this is called). The result is clamped at 0. `charged` is the
## number of ticks actually removed (`cost` clamped by what was left), and
## `reaches_zero` is true when this entry takes a positive clock to 0, which
## starts the grace period unless the destination is the exit.
## `collapses` is kept for older callers and is always false in v1.
func evaluate(before: int, room_kind: String, first_visit: bool, room_id: int) -> Dictionary:
    var cost: int = kind_value(room_kind, "first_entry_cost" if first_visit else "revisit_cost")
    var grant: int = kind_value(room_kind, "first_entry_grant") if first_visit else 0
    cost = maxi(0, cost)
    grant = maxi(0, grant)
    var charged: int = mini(maxi(0, before), cost)
    var after: int = maxi(0, before - cost + grant)
    return {
        "room_id": room_id,
        "room_kind": room_kind,
        "first_visit": first_visit,
        "before": before,
        "cost": cost,
        "charged": charged,
        "grant": grant,
        "after": after,
        "allowed": true,
        "collapses": false,
        "reaches_zero": before > 0 and after == 0,
        "source": "transition",
        "modifiers": [],
        "reason": "%s %s (cost %d, grant %d)" % [
            room_kind, "first entry" if first_visit else "revisit", cost, grant
        ]
    }


## A room-type policy value with the `default` block as fallback (0 if absent).
func kind_value(room_kind: String, key: String) -> int:
    var default_policy: Dictionary = settings.get("default", {})
    var room_policy: Dictionary = settings.get("room_types", {}).get(room_kind, {})
    return int(room_policy.get(key, default_policy.get(key, 0)))


## Net first-entry cost of a kind, clamped to >= 0 (grants never make a room
## "pay" the player in route estimates, which keeps the estimate conservative).
func net_first_entry(room_kind: String) -> int:
    return maxi(0, maxi(0, kind_value(room_kind, "first_entry_cost"))
        - maxi(0, kind_value(room_kind, "first_entry_grant")))


## Ticks granted when a room of this kind is cleared: the kind's `clear_grant`
## (elite +1) plus `default.clear_refund` (0 by default).
func clear_grant(room_kind: String) -> int:
    var room_policy: Dictionary = settings.get("room_types", {}).get(room_kind, {})
    var refund: int = int(settings.get("default", {}).get("clear_refund", 0))
    return maxi(0, int(room_policy.get("clear_grant", 0)) + refund)


# --- Budget (D-04) -------------------------------------------------------------
# The route cost and slack formulas live in core/run_rules.gd (Wave 2A); the
# functions below delegate to it so there is exactly one implementation.

## Ticks needed to walk the cheapest mandatory route start -> boss -> exit
## (RunRules.mandatory_route_cost: Dijkstra over clamped net first-entry
## costs, start free, exit sealed on the first leg, exit cost included).
## No "+1 for exit ordering": Game resolves the exit before any zero-clock
## handling (2A's ordering fix, kept by 2E's _enter_neighbor), so arriving at
## the exit with exactly its cost succeeds. If that ordering is ever undone,
## the +1 is needed again.
static func mandatory_route_cost(floor: Dictionary, policy) -> int:
    return RunRules.mandatory_route_cost(floor, policy)


## Starting ticks for a floor (COLLAPSE_SYSTEM §4):
## `mandatory_route_cost + max(budget.min_slack, ceil(budget.slack_ratio x room_count))`.
## `room_count` <= 0 uses the floor's generated room count. Same value as
## RunRules.floor_budget, which Game uses at floor start. Not capped; the
## generator's feasibility check enforces `budget.max_start_ticks`.
## Floor 1 / seed 424242 / 22 rooms -> 16 + 10 = 26. Typical depths 2-6
## (26/30/34/40/44 rooms) -> 30/36/40/46/50.
static func budget_for(floor: Dictionary, room_count: int, policy) -> int:
    var count: int = room_count if room_count > 0 else Array(floor.get("rooms", [])).size()
    return mandatory_route_cost(floor, policy) + slack_for(count, policy)


## `max(min_slack, ceil(slack_ratio x room_count))` (RunRules.slack).
static func slack_for(room_count: int, policy) -> int:
    return RunRules.slack(room_count, {"collapse": policy.settings})


## Legacy prototype diagnostic name, kept for older callers. Fixed for v1: it
## is now the cheapest route cost itself (no "+1"; see mandatory_route_cost).
static func mandatory_budget_floor(floor: Dictionary, policy) -> int:
    return maxi(1, mandatory_route_cost(floor, policy))


static func floor_generator_path(rooms: Array, start_id: int, end_id: int) -> Array[int]:
    # Loaded at call time: floor_generator.gd preloads this script.
    return load("res://scripts/floor_generator.gd").path_between(rooms, start_id, end_id)


## The rooms of the cheapest mandatory route, for the generator's checks:
## {cost, rooms (ids, start first)}. Same cost as mandatory_route_cost; among
## equally cheap routes it prefers ones without elite/trap/shrine/guild rooms.
## Empty `rooms` means no route exists.
static func mandatory_route(floor: Dictionary, policy) -> Dictionary:
    var rooms: Array = floor.get("rooms", [])
    var start_id: int = int(floor.get("start_id", 0))
    var boss_id: int = int(floor.get("boss_id", -1))
    var exit_id: int = int(floor.get("exit_id", -1))
    if rooms.is_empty() or boss_id < 0 or exit_id < 0:
        return {"cost": 0, "rooms": []}
    var weights: Array[int] = _route_weights(rooms, policy)
    weights[start_id] = 0
    var first: Dictionary = RunRules.cheapest_path(rooms, weights, start_id, boss_id,
        {exit_id: true})
    if first.is_empty():
        return {"cost": 0, "rooms": []}
    var paid: Array[int] = weights.duplicate()
    for id in first["path"]:
        paid[int(id)] = 0
    var second: Dictionary = RunRules.cheapest_path(rooms, paid, boss_id, exit_id)
    if second.is_empty():
        return {"cost": 0, "rooms": []}
    var route: Array[int] = []
    for id in first["path"]:
        route.append(int(id))
    for id in second["path"]:
        if not route.has(int(id)):
            route.append(int(id))
    return {"cost": _route_cost(rooms, route, start_id, policy), "rooms": route}


## Cheapest first-entry cost from `from_id` to `to_id` as {cost, rooms}
## (`from_id` is free, `to_id` is paid). `blocked` ids are never entered.
## Empty `rooms` means unreachable.
static func cheapest_path(rooms: Array, from_id: int, to_id: int, policy,
        blocked: Dictionary = {}) -> Dictionary:
    var found: Dictionary = RunRules.cheapest_path(rooms, _route_weights(rooms, policy),
        from_id, to_id, blocked)
    if found.is_empty():
        return {"cost": 0, "rooms": []}
    return {"cost": _route_cost(rooms, found["path"], from_id, policy), "rooms": found["path"]}


## Per-room Dijkstra weights: net cost x 1000, +1 for OFF_ROUTE_KINDS so ties
## avoid them without ever changing which cost is cheapest.
static func _route_weights(rooms: Array, policy) -> Array[int]:
    var weights: Array[int] = []
    for room in rooms:
        var kind: String = String(room["kind"])
        weights.append(policy.net_first_entry(kind) * _COST_SCALE
            + (_SPECIAL_PENALTY if OFF_ROUTE_KINDS.has(kind) else 0))
    return weights


static func _route_cost(rooms: Array, route: Array, free_id: int, policy) -> int:
    var cost: int = 0
    for id in route:
        if int(id) != free_id:
            cost += policy.net_first_entry(String(rooms[int(id)]["kind"]))
    return cost


# --- Grace period (D-05) -------------------------------------------------------

## Fresh per-floor grace record (stored in RunState.grace).
## active: grace running. remaining / duration: seconds. count: graces started
## on this floor. wave_timer: seconds until the next debris wave. elapsed:
## seconds of grace used in total. outcome: "", "stabilised", "exit",
## "collapse" or "death" (the last grace's resolution, for telemetry).
static func grace_initial() -> Dictionary:
    return {"active": false, "remaining": 0.0, "duration": 0.0, "count": 0,
        "wave_timer": 0.0, "elapsed": 0.0, "outcome": "", "waves_spawned": 0}


## `collapse.grace` with defaults filled in.
static func grace_config(settings: Dictionary) -> Dictionary:
    var grace: Dictionary = settings.get("grace", {})
    var waves: Array = grace.get("waves", [
        {"above": 7.0, "interval": 1.5, "markers": 1, "shake": 1},
        {"above": 3.5, "interval": 1.0, "markers": 2, "shake": 2},
        {"above": 0.0, "interval": 0.6, "markers": 3, "shake": 3}])
    return {
        "seconds": float(grace.get("seconds", 10.0)),
        "repeat_seconds": float(grace.get("repeat_seconds", 5.0)),
        "max_per_floor": int(grace.get("max_per_floor", 2)),
        "waves": waves,
        "debris": grace.get("debris", {})
    }


## What a zero-clock event does to `state`: "grace" (a grace starts, `state` is
## updated) or "collapse" (the per-floor limit is used up).
static func grace_on_zero(state: Dictionary, config: Dictionary) -> String:
    if int(state.get("count", 0)) >= int(config["max_per_floor"]):
        state["active"] = false
        state["outcome"] = "collapse"
        return "collapse"
    var seconds: float = float(config["seconds"]) if int(state.get("count", 0)) == 0 \
        else float(config["repeat_seconds"])
    state["active"] = true
    state["count"] = int(state.get("count", 0)) + 1
    state["duration"] = seconds
    state["remaining"] = seconds
    state["wave_timer"] = 0.0
    state["outcome"] = ""
    return "grace"


## Ends an active grace with `outcome` ("stabilised", "exit", "collapse", "death").
static func grace_finish(state: Dictionary, outcome: String) -> void:
    state["active"] = false
    state["outcome"] = outcome
    state["remaining"] = 0.0


## The wave row for `remaining` seconds: the first row whose `above` is below it.
static func grace_wave(remaining: float, config: Dictionary) -> Dictionary:
    var waves: Array = config["waves"]
    for wave in waves:
        if remaining > float(wave.get("above", 0.0)):
            return wave
    return waves.back() if not waves.is_empty() else {}


## Advances an active grace by `delta`. Returns {markers, wave, expired}:
## `markers` debris markers to spawn this step (0 if no wave fired), and
## `expired` true when the timer reached 0 (hard collapse).
static func grace_advance(state: Dictionary, delta: float, config: Dictionary) -> Dictionary:
    var result := {"markers": 0, "wave": {}, "expired": false}
    if not bool(state.get("active", false)):
        return result
    var remaining: float = float(state["remaining"])
    var wave: Dictionary = grace_wave(remaining, config)
    var timer: float = float(state["wave_timer"]) - delta
    if timer <= 0.0:
        result["markers"] = int(wave.get("markers", 1))
        result["wave"] = wave
        timer += float(wave.get("interval", 1.0))
        state["waves_spawned"] = int(state.get("waves_spawned", 0)) + 1
    state["wave_timer"] = maxf(0.0, timer)
    remaining -= delta
    state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
    state["remaining"] = maxf(0.0, remaining)
    if remaining <= 0.0:
        result["expired"] = true
        grace_finish(state, "collapse")
    return result
