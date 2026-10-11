extends RefCounted
## Pure window-to-room layout. Reusable for tests and future biome renderers.
const TILE_SIZE := 32.0
const MIN_WINDOW := Vector2(720.0, 480.0)

static func compute(window_size: Vector2) -> Dictionary:
    var view := Vector2(
        maxf(MIN_WINDOW.x, window_size.x),
        maxf(MIN_WINDOW.y, window_size.y)
    )
    # Even tile counts provide a symmetric 2-tile-wide portal on every side.
    var columns: int = maxi(12, 2 * int(floorf((view.x - 96.0) / (2.0 * TILE_SIZE))))
    var rows: int = maxi(6, 2 * int(floorf((view.y - 212.0) / (2.0 * TILE_SIZE))))
    var content_size := Vector2(float(columns), float(rows)) * TILE_SIZE
    var top: float = floorf(110.0 + maxf(0.0,
        view.y - 212.0 - content_size.y) * 0.5)
    var arena := Rect2(
        Vector2(floorf((view.x - content_size.x) * 0.5), top),
        content_size
    )
    return {"viewport": view, "columns": columns, "rows": rows,
        "arena": arena, "center": arena.get_center()}
