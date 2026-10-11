extends RefCounted
## Fixed 24x24 room in world pixels; window resize changes scale, never tile count.
const TILE_SIZE := 16
const COLUMNS := 24
const ROWS := 24
const ARENA := Rect2(0.0, 0.0, 384.0, 384.0)
const MIN_WINDOW := Vector2(720.0, 480.0)
const BORDER := 16.0

static func compute(window_size: Vector2) -> Dictionary:
    var view := Vector2(maxf(MIN_WINDOW.x, window_size.x), maxf(MIN_WINDOW.y, window_size.y))
    var full_size := ARENA.size + Vector2(BORDER * 2.0, BORDER * 2.0)
    var available := Vector2(maxf(10.0, view.x - 40.0), maxf(10.0, view.y - 193.0))
    var scale: float = minf(available.x / full_size.x, available.y / full_size.y)
    var offset := Vector2(
        floorf((view.x - ARENA.size.x * scale) * 0.5),
        floorf(106.0 + (available.y - full_size.y * scale) * 0.5 + BORDER * scale)
    )
    return {
        "viewport": view, "columns": COLUMNS, "rows": ROWS, "arena": ARENA,
        "center": ARENA.get_center(), "scale": scale, "offset": offset
    }

static func world_to_screen(point: Vector2, layout: Dictionary) -> Vector2:
    return Vector2(layout["offset"]) + point * float(layout["scale"])

static func screen_to_world(point: Vector2, layout: Dictionary) -> Vector2:
    return (point - Vector2(layout["offset"])) / float(layout["scale"])
