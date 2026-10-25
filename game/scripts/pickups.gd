extends RefCounted
## World pickups (Wave 2B): loot on the floor, persisted per room in
## `RunState.room_states[room_id]["pickups"]` so dropped loot survives
## revisits (COMBAT_AND_RPG §9).
##
## Entry shape:
##   {uid: String, id: String (content id, or LOOT_BOX), pos: Vector2,
##    room_id: int, count: int (consumable copies), state: Dictionary
##    (a dropped active's active_state), table: String (loot box table)}
## Weapons, actives and loot boxes are taken with `interact` (they may swap);
## passives and consumables are taken on contact (ItemSystem.update). Every
## spawn emits Events.item_dropped(id, pos).
## Autoloads are looked up at runtime, so tests may preload this module.
const Contents = preload("res://scripts/room_contents.gd")

const LOOT_BOX := "loot_box"


static func _autoload(node_name: String) -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root.get_node_or_null(node_name) if tree != null else null


## The pickup array of `room_id` (created on first use); [] for unloaded rooms.
static func list(room_id: int) -> Array:
    var rs: Node = _autoload("RunState")
    if rs == null or not rs.room_states.has(room_id):
        return []
    var state: Dictionary = rs.room_states[room_id]
    if not state.has("pickups"):
        state["pickups"] = []
    return state["pickups"]


static func current() -> Array:
    var rs: Node = _autoload("RunState")
    return list(int(rs.current_room_id)) if rs != null else []


## Places `id` at `pos` (nudged to the nearest walkable cell) in `room_id`.
## Returns the entry, or {} when the room is not loaded.
static func spawn(id: String, pos: Vector2, room_id: int, extra: Dictionary = {}) -> Dictionary:
    var rs: Node = _autoload("RunState")
    if rs == null or not rs.room_states.has(room_id) or id == "":
        return {}
    var state: Dictionary = rs.room_states[room_id]
    var serial: int = int(state.get("pickup_serial", 0))
    state["pickup_serial"] = serial + 1
    var spot: Vector2 = walkable_spot(pos, state.get("blocked", {}))
    var entry := {"uid": "pk_%d_%d" % [room_id, serial], "id": id, "pos": spot,
        "room_id": room_id, "count": 1, "state": {}, "table": ""}
    entry.merge(extra, true)
    entry["count"] = maxi(1, int(entry["count"]))
    list(room_id).append(entry)
    var events: Node = _autoload("Events")
    if events != null:
        events.emit_signal("item_dropped", id, spot)
    return entry


## Spawns each id on a small ring around `center` (loot fountains).
static func spawn_ring(ids: Array, center: Vector2, room_id: int, spread: float = 18.0) -> Array:
    var placed: Array = []
    for i in range(ids.size()):
        var angle: float = -PI * 0.5 + TAU * float(i) / float(maxi(1, ids.size()))
        var offset: Vector2 = Vector2.ZERO if ids.size() == 1 and spread <= 0.0 \
            else Vector2.RIGHT.rotated(angle) * spread
        placed.append(spawn(String(ids[i]), center + offset, room_id))
    return placed


static func remove(entry: Dictionary) -> void:
    var entries: Array = list(int(entry.get("room_id", -1)))
    for i in range(entries.size()):
        if is_same(entries[i], entry):
            entries.remove_at(i)
            return


## The closest pickup of the current room within `radius` of `point`, or {}.
static func nearest(point: Vector2, radius: float) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for entry in current():
        var distance: float = Vector2(entry["pos"]).distance_to(point)
        if distance <= radius and distance < best_distance:
            best = entry
            best_distance = distance
    return best


## `pos` if its cell is walkable, else the centre of the nearest walkable cell
## (rings of radius 1..4 cells), clamped inside the room.
static func walkable_spot(pos: Vector2, blocked: Dictionary) -> Vector2:
    var clamped := Vector2(clampf(pos.x, 12.0, Contents.SIZE * Contents.TILE - 12.0),
        clampf(pos.y, 12.0, Contents.SIZE * Contents.TILE - 12.0))
    var cell: Vector2i = Contents.cell_of(clamped)
    if Contents.is_walkable(cell, blocked):
        return clamped
    for ring in range(1, 5):
        for dy in range(-ring, ring + 1):
            for dx in range(-ring, ring + 1):
                if maxi(absi(dx), absi(dy)) != ring:
                    continue
                var candidate: Vector2i = cell + Vector2i(dx, dy)
                if candidate.x >= 1 and candidate.y >= 1 and candidate.x < Contents.SIZE - 1 \
                        and candidate.y < Contents.SIZE - 1 and Contents.is_walkable(candidate, blocked):
                    return Contents.cell_center(candidate)
    return clamped
