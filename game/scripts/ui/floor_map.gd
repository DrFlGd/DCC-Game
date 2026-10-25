extends CanvasLayer
## Full-screen floor map overlay (PROCEDURAL_GENERATION §7, `map` action).
##
## Shows visited rooms filled in their kind colour, scouted rooms (adjacent to
## a visited room) as outlines, links touching a visited room, the current
## room highlighted, and the net tick change of every door of the current
## room. The exit appears once discovered (visited or scouted). Game freezes
## the world (State.MAP) while it is open.
## build_model() is pure and the node never reads autoloads, so tests may
## preload this script; Game passes the model in with open().

## Fill colours by room kind (shared with the HUD minimap).
const KIND_COLORS := {
    "start": Color("#9fb3c8"), "normal": Color("#788b9d"), "boss": Color("#ec9c9d"),
    "exit": Color("#eacb7b"), "guild_hall": Color("#a4efd6"), "treasure": Color("#f2d16b"),
    "elite": Color("#d77be0"), "trap": Color("#e48a5a"), "shrine": Color("#8fb8ff")
}
## Map icons by kind. Scouted rooms only reveal boss, exit and guild hall
## (door tints already do); other specials show "?".
const KIND_ICONS := {"start": "S", "boss": "B", "exit": "X", "guild_hall": "G",
    "treasure": "$", "elite": "E", "trap": "!", "shrine": "+", "normal": ""}
const REVEALED_WHEN_SCOUTED := ["boss", "exit", "guild_hall"]

var model: Dictionary = {}
var canvas: Control


func _ready() -> void:
    layer = 8
    canvas = Control.new()
    canvas.name = "MapCanvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.draw.connect(_draw_map)
    canvas.visible = false
    add_child(canvas)


func is_open() -> bool:
    return not model.is_empty()


func open(new_model: Dictionary) -> void:
    model = new_model
    if canvas != null:
        canvas.visible = true
        canvas.queue_redraw()


func close() -> void:
    model = {}
    if canvas != null:
        canvas.visible = false


## Pure map model. `policy` is a CollapsePolicy (door previews), `room_states`
## RunState.room_states (cleared markers). Returns
## {rooms: [{id, grid, kind, state ("visited"|"scouted"), icon, current,
##   cleared}], edges: [{a, b, label}], current_id, ticks, bounds: Rect2i}.
## Edge `label` is the net tick change for entering the far room through a
## door of the current room ("" for other edges).
static func build_model(floor: Dictionary, visited: Dictionary, current_id: int, ticks: int,
        policy, room_states: Dictionary = {}, boss_defeated: bool = false) -> Dictionary:
    var rooms: Array = floor.get("rooms", [])
    var known: Dictionary = {}
    for room in rooms:
        var id: int = int(room["id"])
        if visited.has(id):
            known[id] = "visited"
    for id in known.keys():
        for neighbor in rooms[int(id)]["neighbors"].values():
            if not known.has(int(neighbor)):
                known[int(neighbor)] = "scouted"
    var entries: Array[Dictionary] = []
    var bounds := Rect2i()
    var first := true
    for room in rooms:
        var id: int = int(room["id"])
        if not known.has(id):
            continue
        var kind: String = String(room["kind"])
        var state: String = String(known[id])
        var icon: String = String(KIND_ICONS.get(kind, "?"))
        if state == "scouted" and not REVEALED_WHEN_SCOUTED.has(kind):
            icon = "?" if kind != "normal" else ""
        var grid: Vector2i = room["grid"]
        bounds = Rect2i(grid, Vector2i.ONE) if first else bounds.merge(Rect2i(grid, Vector2i.ONE))
        first = false
        entries.append({"id": id, "grid": grid, "kind": kind if state == "visited" or
                REVEALED_WHEN_SCOUTED.has(kind) else "unknown", "state": state, "icon": icon,
            "current": id == current_id,
            "cleared": state == "visited" and Array(room_states.get(id, {}).get("enemies", [])).is_empty()})
    var edges: Array[Dictionary] = []
    for room in rooms:
        var a: int = int(room["id"])
        for neighbor in room["neighbors"].values():
            var b: int = int(neighbor)
            if b <= a or not (visited.has(a) or visited.has(b)):
                continue
            var label := ""
            if a == current_id or b == current_id:
                var far: int = b if a == current_id else a
                var kind: String = String(rooms[far]["kind"])
                if kind == "exit" and not boss_defeated:
                    label = "sealed"
                elif policy != null:
                    var preview: Dictionary = policy.evaluate(ticks, kind, not visited.has(far), far)
                    var net: int = int(preview["after"]) - ticks if ticks <= 0 \
                        else int(preview["grant"]) - int(preview["cost"])
                    label = "%+d" % net
            edges.append({"a": a, "b": b, "label": label})
    return {"rooms": entries, "edges": edges, "current_id": current_id, "ticks": ticks,
        "bounds": bounds}


func _draw_map() -> void:
    if model.is_empty():
        return
    var view: Vector2 = canvas.get_viewport_rect().size
    canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.03, 0.06, 0.93))
    var font: Font = ThemeDB.fallback_font
    canvas.draw_string(font, Vector2(24, 34), "FLOOR MAP  |  TICKS %d  |  M / Esc: close"
        % int(model["ticks"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("#f2da99"))
    var bounds: Rect2i = model["bounds"]
    var span := Vector2(maxi(1, bounds.size.x), maxi(1, bounds.size.y))
    var area := Rect2(Vector2(40, 60), view - Vector2(80, 110))
    var unit: float = minf(64.0, minf(area.size.x / span.x, area.size.y / span.y))
    var origin: Vector2 = area.position + (area.size - span * unit) * 0.5
    var centers: Dictionary = {}
    for room in model["rooms"]:
        var grid: Vector2i = room["grid"]
        centers[int(room["id"])] = origin + (Vector2(grid - bounds.position) + Vector2(0.5, 0.5)) * unit
    for edge in model["edges"]:
        if not centers.has(int(edge["a"])) or not centers.has(int(edge["b"])):
            continue
        var a: Vector2 = centers[int(edge["a"])]
        var b: Vector2 = centers[int(edge["b"])]
        canvas.draw_line(a, b, Color("#56657a"), 2.0)
        if String(edge["label"]) != "":
            canvas.draw_string(font, (a + b) * 0.5 + Vector2(-10, -4), String(edge["label"]),
                HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color.WHITE)
    var size: float = unit * 0.62
    for room in model["rooms"]:
        var center: Vector2 = centers[int(room["id"])]
        var rect := Rect2(center - Vector2.ONE * size * 0.5, Vector2.ONE * size)
        var color: Color = KIND_COLORS.get(String(room["kind"]), Color("#788b9d"))
        if String(room["state"]) == "visited":
            canvas.draw_rect(rect, color)
        else:
            canvas.draw_rect(rect, Color(color, 0.18))
            canvas.draw_rect(rect, color, false, 1.5)
        if bool(room["current"]):
            canvas.draw_rect(rect.grow(4.0), Color.WHITE, false, 2.5)
        if String(room["icon"]) != "":
            canvas.draw_string(font, center + Vector2(-5, 5), String(room["icon"]),
                HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("#101720"))
        if bool(room["cleared"]):
            canvas.draw_circle(rect.end - Vector2(4, 4), 2.5, Color("#a5d49b"))
