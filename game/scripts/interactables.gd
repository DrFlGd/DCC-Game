extends RefCounted
## Interactable room features: chests, shrines, the guild rest station, signs,
## and anything later teams add (shops, loot pickups, NPCs).
##
## Entries are plain dictionaries stored in the room state
## (`RunState.room_states[id]["interactables"]`):
##   {id: String, kind: String, cell: Vector2i, pos: Vector2, radius: float,
##    once: bool, used: bool}
## plus any kind-specific keys. Behaviour is registered per `kind` on the
## RoomServices node (`register_interaction(kind, prompt, action)`); this module
## only builds entries and finds the one the crawler can use.
## Pure module: no autoload references, safe to preload from tests.

const TILE := 16.0
const DEFAULT_RADIUS := 26.0


## A new entry centred on `cell`. `extra` keys are merged over the defaults.
static func make(kind: String, cell: Vector2i, room_id: int, extra: Dictionary = {}) -> Dictionary:
    var entry := {
        "id": "%s_%d_%d_%d" % [kind, room_id, cell.x, cell.y], "kind": kind, "cell": cell,
        "pos": Vector2(cell) * TILE + Vector2.ONE * (TILE * 0.5), "radius": DEFAULT_RADIUS,
        "once": true, "used": false, "room_id": room_id
    }
    entry.merge(extra, true)
    return entry


## True when the entry can still be used (repeatable, or one-shot and unused).
static func available(entry: Dictionary) -> bool:
    return not (bool(entry.get("once", true)) and bool(entry.get("used", false)))


## The closest available entry whose `radius` reaches `point`, or {}.
## Ties keep the earlier entry, so results are stable.
static func nearest(entries: Array, point: Vector2) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for entry in entries:
        if not available(entry):
            continue
        var distance: float = Vector2(entry["pos"]).distance_to(point)
        if distance <= float(entry.get("radius", DEFAULT_RADIUS)) and distance < best_distance:
            best = entry
            best_distance = distance
    return best
