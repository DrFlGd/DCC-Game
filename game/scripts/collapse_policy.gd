extends RefCounted
## Pure, configuration-driven room transition costing.
## No cost is a claim about the book canon. Costs are deliberate prototype defaults.

var settings: Dictionary


func _init(config: Dictionary = {}) -> void:
    settings = config


func evaluate(before: int, room_kind: String, first_visit: bool, room_id: int) -> Dictionary:
    var default_policy: Dictionary = settings.get("default", {})
    var overrides: Dictionary = settings.get("room_types", {})
    var room_policy: Dictionary = overrides.get(room_kind, {})
    var key: String = "first_entry_cost" if first_visit else "revisit_cost"
    var cost: int = maxi(0, int(room_policy.get(key, default_policy.get(key, 0))))
    var grant: int = 0
    if first_visit:
        grant = maxi(0, int(room_policy.get(
            "first_entry_grant", default_policy.get("first_entry_grant", 0)
        )))
    var after: int = maxi(0, before - cost + grant)
    return {
        "room_id": room_id,
        "room_kind": room_kind,
        "first_visit": first_visit,
        "before": before,
        "cost": cost,
        "grant": grant,
        "after": after,
        "allowed": before > 0 and before >= cost,
        "collapses": before > 0 and before >= cost and after == 0,
        "reason": "%s %s (cost %d, grant %d)" % [
            room_kind, "first entry" if first_visit else "revisit", cost, grant
        ]
    }


static func mandatory_budget_floor(floor: Dictionary, policy: RefCounted) -> int:
    # Conservative route estimate: start -> boss -> exit, paying for first visits.
    # It is a diagnostic, not a proof of optimal cost under all item mechanics.
    var rooms: Array = floor["rooms"]
    var to_boss: Array[int] = floor_generator_path(rooms, int(floor["start_id"]), int(floor["boss_id"]))
    var to_exit: Array[int] = floor_generator_path(rooms, int(floor["boss_id"]), int(floor["exit_id"]))
    var counted: Dictionary = {int(floor["start_id"]): true}
    var required: int = 1
    for route in [to_boss, to_exit]:
        for id in route:
            if counted.has(id):
                continue
            counted[id] = true
            var room: Dictionary = rooms[id]
            var entry: Dictionary = policy.evaluate(100000, String(room["kind"]), true, id)
            required += int(entry["cost"]) - int(entry["grant"])
    return maxi(1, required)


static func floor_generator_path(rooms: Array, start_id: int, end_id: int) -> Array[int]:
    # Uses the same graph traversal as the generator without dependency cycles.
    const GENERATOR = preload("res://scripts/floor_generator.gd")
    return GENERATOR.path_between(rooms, start_id, end_id)
