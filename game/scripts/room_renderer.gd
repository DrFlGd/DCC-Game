extends Node2D
## Immediate-mode world renderer for the current 24x24 room.
##
## Draws floor and wall tiles, props, doors with net tick previews, enemy and
## player sprites, projectiles, the melee arc and the i-frame ring. It only
## reads state (RunState, Player, Combat) and never mutates it.
## World pixels are mapped to the window with `layout` (room_layout.gd), so the
## room is always 24x24 tiles whatever the window size.
##
## Follow-up candidate: migrate tiles/props to a TileMapLayer and actors to
## Sprite2D/AnimatedSprite2D nodes under a transformed world root once
## animation work starts; keep this script as the debug-overlay layer.
const Contents = preload("res://scripts/room_contents.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Settings = preload("res://scripts/core/settings.gd")

const TILE := 16.0
const SIZE := 24
const ROOM := Layout.ARENA
const MID := Vector2(192, 192)
const DIRECTIONS := ["N", "E", "S", "W"]
const BACKGROUND := Color("#101720")
const CRYPT = preload("res://assets/biomes/stone_crypt/tileset_16x16.png")
const CRAWLER = preload("res://assets/characters/crawler/facing_8.png")
const RAT = preload("res://assets/enemies/rat/facing_8.png")
const BOSS = preload("res://assets/enemies/brute_boss/facing_8.png")
const FLOOR_TILE := Rect2(0, 0, 16, 16)
const FLOOR_ALT := Rect2(16, 0, 16, 16)
const WALL_TOP := Rect2(32, 0, 16, 16)
const WALL_LEFT_EDGE := Rect2(64, 0, 16, 16)
const WALL_RIGHT_EDGE := Rect2(48, 0, 16, 16)
const WALL_FACE := Rect2(80, 0, 16, 16)
const WALL_TORCH := Rect2(96, 0, 16, 16)
const DOOR_TILE := Rect2(112, 0, 16, 16)
const STAIRS := Rect2(0, 16, 16, 16)
const PROP_BARREL := Rect2(16, 16, 16, 16)
const PROP_CHEST := Rect2(32, 16, 16, 16)
const PROP_BONES := Rect2(48, 16, 16, 16)

## Room-to-window mapping from Layout.compute(); Game keeps it current.
var layout: Dictionary = Layout.compute(Vector2(960, 540))
var player
var combat
## CollapsePolicy instance used for the door previews.
var rules
var catalogue: Dictionary = {}


func setup(player_node, combat_node, collapse_rules, enemy_catalogue: Dictionary) -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    player = player_node
    combat = combat_node
    rules = collapse_rules
    catalogue = enemy_catalogue


## Net tick change (grant - cost) for walking into neighbour `next_id` now.
static func door_net_ticks(policy, ticks: int, kind: String, first_visit: bool, next_id: int) -> int:
    var preview: Dictionary = policy.evaluate(ticks, kind, first_visit, next_id)
    return int(preview["grant"]) - int(preview["cost"])


func _draw() -> void:
    var viewport: Vector2 = Vector2(layout.get("viewport", Vector2(960, 540)))
    draw_rect(Rect2(Vector2.ZERO, viewport), BACKGROUND)
    if RunState.floor.is_empty() or player == null:
        return
    var base_offset: Vector2 = layout.get("offset", Vector2.ZERO)
    var scale: float = float(layout.get("scale", 1.0))
    # Wave 2E: grace-period screen shake (presentation only; restored below).
    layout["offset"] = base_offset + grace_shake() * scale
    var offset: Vector2 = layout["offset"]
    draw_set_transform(offset, 0.0, Vector2.ONE * scale)
    _draw_room()
    _draw_actors()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    layout["offset"] = base_offset


func _draw_room() -> void:
    # Supplied 8x2 native-16px atlas; the sampler has no explicit corner/south
    # pieces, so rotated top-stone is a temporary joining fallback.
    for y in range(SIZE):
        for x in range(SIZE):
            var tile_center := Vector2((float(x) + 0.5) * TILE, (float(y) + 0.5) * TILE)
            var tile_region := FLOOR_ALT if (x * 17 + y * 13) % 9 == 0 else FLOOR_TILE
            _crypt_piece(tile_region, tile_center, Vector2(TILE, TILE))
    var room: Dictionary = RunState.floor["rooms"][RunState.current_room_id]
    var kind: String = String(room["kind"])
    var tint := Color.TRANSPARENT
    if kind == "boss":
        tint = Color(0.3, 0.05, 0.09, 0.16)
    elif kind == "guild_hall":
        tint = Color(0.04, 0.30, 0.22, 0.14)
    elif kind == "exit":
        tint = Color(0.35, 0.24, 0.06, 0.14)
    if tint.a > 0.0:
        draw_rect(ROOM, tint)

    for prop in RunState.current_room().get("props", []):
        _draw_obstacle(prop)
    _draw_room_features()

    var links: Dictionary = room["neighbors"]
    _draw_walls(links)
    for direction in DIRECTIONS:
        if links.has(direction):
            _draw_door(direction, int(links[direction]))

    if kind == "boss":
        _text("BOSS", MID + Vector2(-20, -146), 17, Color("#ffb4b7"))
    elif kind == "guild_hall":
        _text("GUILD", MID + Vector2(-22, -146), 17, Color("#b4f9d8"))
    elif kind == "exit":
        _crypt_piece(STAIRS, MID, Vector2(32, 32))
        _text("EXIT", MID + Vector2(-16, -146), 17, Color("#ffdc91"))
    elif ROOM_LABELS.has(kind):
        _text(String(ROOM_LABELS[kind][0]), MID + Vector2(-28, -146), 17, ROOM_LABELS[kind][1])


# --- Wave 2E: special rooms, interactables, plates, hazards ---------------------

## Banner text and colour for the Wave 2E room kinds.
const ROOM_LABELS := {
    "treasure": ["TREASURE", Color("#ffe08a")], "elite": ["ELITE", Color("#e9a3f0")],
    "trap": ["TRAPS", Color("#ffb08a")], "shrine": ["SHRINE", Color("#b9d2ff")]
}


## Screen-shake offset in world pixels for the current grace wave, scaled by
## the screen-shake setting. Zero outside grace.
static func grace_shake() -> Vector2:
    if not RunState.grace_active():
        return Vector2.ZERO
    var config: Dictionary = Collapse.grace_config(RunState.config.get("collapse", {}))
    var wave: Dictionary = Collapse.grace_wave(float(RunState.grace["remaining"]), config)
    var amount: float = float(wave.get("shake", 0.0)) * float(Settings.shared().screen_shake)
    var t: float = float(Time.get_ticks_msec()) / 1000.0
    return Vector2(sin(t * 53.0), cos(t * 47.0)) * amount


## Chests, shrines, the guild rest station and sign, and trap plates.
func _draw_room_features() -> void:
    var state: Dictionary = RunState.current_room()
    for plate in state.get("plates", []):
        var center: Vector2 = Contents.cell_center(plate["cell"])
        var drain: bool = String(plate["kind"]) == "drain"
        var color := Color("#c46bff") if drain else Color("#bfbfbf")
        if not bool(plate["armed"]):
            color = Color(color, 0.35)
        draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), Color(color, 0.25))
        draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), color, false, 1.0)
        if drain and bool(plate["armed"]):
            _text("-1", center + Vector2(-5, -8), 9, Color("#e7b6ff"))
    for feature in state.get("interactables", []):
        var center: Vector2 = feature["pos"]
        var used: bool = bool(feature.get("used", false))
        var tint := Color(1, 1, 1, 0.45) if used else Color.WHITE
        match String(feature["kind"]):
            "chest":
                _crypt_piece(PROP_CHEST, center, Vector2(TILE, TILE), 0.0, tint)
            "shrine":
                draw_circle(center, 7.0, Color("#8fb8ff", 0.35 if used else 0.9))
                draw_arc(center, 9.0, 0.0, TAU, 20, Color("#dfe9ff", tint.a), 1.0)
            "rest":
                draw_rect(Rect2(center - Vector2(7, 4), Vector2(14, 8)), Color("#6e9e8a", tint.a))
                draw_rect(Rect2(center - Vector2(7, 4), Vector2(4, 8)), Color("#e8f2ea", tint.a))
            "shop_sign":
                draw_rect(Rect2(center - Vector2(6, 7), Vector2(12, 8)), Color("#a77b4f"))
                draw_line(center + Vector2(0, 1), center + Vector2(0, 7), Color("#6b4a2b"), 2.0)
            _:
                draw_circle(center, 5.0, Color("#fff1a7", tint.a))


func _draw_walls(links: Dictionary) -> void:
    for x in range(SIZE):
        var px: float = (float(x) + 0.5) * TILE
        var north_gap: bool = links.has("N") and (x == 11 or x == 12)
        var south_gap: bool = links.has("S") and (x == 11 or x == 12)
        if not north_gap:
            _crypt_piece(WALL_TOP, Vector2(px, -TILE * 0.5), Vector2(TILE, TILE))
            var face: Rect2 = WALL_TORCH if (x == 5 or x == 18) else WALL_FACE
            _crypt_piece(face, Vector2(px, TILE * 0.5), Vector2(TILE, TILE))
        if not south_gap:
            _crypt_piece(WALL_TOP, Vector2(px, ROOM.end.y + TILE * 0.5),
                Vector2(TILE, TILE), PI)
    for y in range(SIZE):
        var py: float = (float(y) + 0.5) * TILE
        if not (links.has("W") and (y == 11 or y == 12)):
            _crypt_piece(WALL_RIGHT_EDGE, Vector2(-TILE * 0.5, py), Vector2(TILE, TILE))
        if not (links.has("E") and (y == 11 or y == 12)):
            _crypt_piece(WALL_LEFT_EDGE, Vector2(ROOM.end.x + TILE * 0.5, py),
                Vector2(TILE, TILE))
    # Corner fallback uses wall-top stone because the free sampler omits corner tiles.
    _crypt_piece(WALL_TOP, Vector2(-8, -8), Vector2(TILE, TILE))
    _crypt_piece(WALL_TOP, Vector2(ROOM.end.x + 8, -8), Vector2(TILE, TILE), PI * 0.5)
    _crypt_piece(WALL_TOP, ROOM.end + Vector2(8, 8), Vector2(TILE, TILE), PI)
    _crypt_piece(WALL_TOP, Vector2(-8, ROOM.end.y + 8), Vector2(TILE, TILE), -PI * 0.5)


func _draw_door(direction: String, next_id: int) -> void:
    var destination: Dictionary = RunState.floor["rooms"][next_id]
    var kind: String = String(destination["kind"])
    var color := Color.WHITE
    if kind == "guild_hall":
        color = Color("#a4efe1")
    elif kind == "boss":
        color = Color("#f5b0b0")
    elif kind == "exit":
        color = Color("#f9d57e") if RunState.boss_defeated else Color("#c77179")
    var door_center := MID
    var rotation := 0.0
    var label_pos := MID
    match direction:
        "N":
            door_center = Vector2(MID.x, 0)
            label_pos = Vector2(MID.x - 16, 30)
        "S":
            door_center = Vector2(MID.x, ROOM.end.y)
            rotation = PI
            label_pos = Vector2(MID.x - 16, ROOM.end.y - 19)
        "W":
            door_center = Vector2(0, MID.y)
            rotation = -PI * 0.5
            label_pos = Vector2(16, MID.y + 6)
        "E":
            door_center = Vector2(ROOM.end.x, MID.y)
            rotation = PI * 0.5
            label_pos = Vector2(ROOM.end.x - 40, MID.y + 6)
    # Two 16px leaf sprites visually fill each 32px linked-door opening.
    var door_offset := Vector2(TILE * 0.5, 0).rotated(rotation)
    _crypt_piece(DOOR_TILE, door_center - door_offset, Vector2(TILE, TILE), rotation, color)
    _crypt_piece(DOOR_TILE, door_center + door_offset, Vector2(TILE, TILE), rotation, color)
    var net_ticks: int = door_net_ticks(rules, RunState.ticks, kind,
        not RunState.visited.has(next_id), next_id)
    # Wave 2E: red "!" when the door would leave the clock at 0; during grace
    # entries are free, so the label shows the true change (grants only).
    var label_color := Color.WHITE
    var suffix := ""
    if RunState.ticks <= 0:
        net_ticks = maxi(0, net_ticks)
        label_color = Color("#ffb3b3")
    elif RunState.ticks + net_ticks <= 0:
        label_color = Color("#ff5a5a")
        suffix = "!"
    _text("%s%+d%s" % [direction, net_ticks, suffix], label_pos, 13, label_color)


func _draw_obstacle(prop: Dictionary) -> void:
    var cell: Vector2i = prop["cell"]
    var center: Vector2 = Contents.cell_center(cell)
    var region: Rect2 = PROP_BARREL if prop["kind"] == "pillar" else PROP_BONES
    _crypt_piece(region, center, Vector2(TILE, TILE))


func _draw_actors() -> void:
    Hazards.draw_all(self, combat.hazards, ThemeDB.fallback_font)
    for projectile in combat.projectiles:
        var point: Vector2 = projectile["pos"]
        var color := Color("#ffe78b") if projectile["owner"] == "player" else Color("#d778dc")
        draw_circle(point, 2.5, color)
    for foe in RunState.current_room().get("enemies", []):
        var definition: Dictionary = catalogue["enemies"][foe["definition"]]
        var boss_sprite: bool = definition["sprite"] == "boss"
        var sheet: Texture2D = BOSS if boss_sprite else RAT
        var sprite_size := Vector2(48, 48) if boss_sprite else Vector2(24, 24)
        var point: Vector2 = foe["pos"]
        _draw_facing_sprite(sheet, point, sprite_size, int(foe["facing"]))
        var hp_ratio: float = float(foe["hp"]) / float(foe["max_hp"])
        draw_rect(Rect2(point.x - 12, point.y - sprite_size.y * 0.5 - 6, 24, 3),
            Color("#151b25"))
        draw_rect(Rect2(point.x - 12, point.y - sprite_size.y * 0.5 - 6, 24 * hp_ratio, 3),
            Color("#a5d49b"))
        if foe["definition"] == "spitting_rat":
            draw_circle(point + Vector2(0, 11), 2.5, Color("#c978d4"))
    var at: Vector2 = player.world_position
    var aim: Vector2 = player.aim_direction
    _draw_facing_sprite(CRAWLER, at, Vector2(24, 24), player.facing)
    draw_line(at, at + aim * 13.0, Color("#f9dc92"), 1.0)
    if player.melee_flash > 0.0:
        draw_arc(at, 30.0, aim.angle() - 0.7, aim.angle() + 0.7, 14, Color("#fff1a7"), 3.0)
    if player.invulnerability > 0.0:
        draw_arc(at, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.42), 1.0)


func _crypt_piece(region: Rect2, center: Vector2, size: Vector2,
        rotation: float = 0.0, modulation: Color = Color.WHITE) -> void:
    var offset: Vector2 = layout["offset"]
    var scale: float = float(layout["scale"])
    draw_set_transform(offset + center * scale, rotation, Vector2.ONE * scale)
    draw_texture_rect_region(CRYPT, Rect2(-size * 0.5, size), region, modulation)
    draw_set_transform(offset, 0.0, Vector2.ONE * scale)


func _draw_facing_sprite(sheet: Texture2D, center: Vector2, size: Vector2, facing: int) -> void:
    var index: int = posmod(facing, 8)
    var frame_size := Vector2(sheet.get_width() / 8.0, sheet.get_height())
    draw_texture_rect_region(sheet, Rect2(center - size * 0.5, size),
        Rect2(float(index) * frame_size.x, 0.0, frame_size.x, frame_size.y))


func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
