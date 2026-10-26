extends Node2D
## Immediate-mode world renderer for the current 24x24 room.
## Wave 2D: hit feedback from `combat.fx` (shake offset, flashes, numbers,
## death bursts), the i-frame blink and dodge trail, and sealed doors from
## `door_lock`, each drawn by its own _draw_* function below.
##
## Draws floor and wall tiles, props, doors with net tick previews, enemy and
## player sprites, projectiles, ground hazards, enemy attack telegraphs, the
## melee arc and the i-frame ring. It only reads state (RunState, Player,
## Combat) and never mutates it.
## World pixels are mapped to the window with `layout` (room_layout.gd), so the
## room is always 24x24 tiles whatever the window size.
##
## Wave 3B: tiles are drawn by **slot name** from the room's biome
## (Biomes.art: atlas + tiles.json; art-less biomes draw the stone_crypt atlas
## multiplied by their fallback_tint). _piece(slot, ...) is the one entry
## point; the real south wall, outer corners, thresholds and door states
## replace the rotated wall-top stand-ins. Decals and small props are
## sprinkled per cell from Biomes.cell_hash (floor seed, room, cell): no RNG.
##
## Follow-up candidate: migrate tiles/props to a TileMapLayer and actors to
## Sprite2D/AnimatedSprite2D nodes under a transformed world root once
## animation work starts; keep this script as the debug-overlay layer.
const Contents = preload("res://scripts/room_contents.gd")
const Biomes = preload("res://scripts/biomes.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Accessibility = preload("res://scripts/core/accessibility.gd")
const Inventory = preload("res://scripts/inventory.gd")
const StatusSystem = preload("res://scripts/status_system.gd")

const TILE := 16.0
const SIZE := 24
const ROOM := Layout.ARENA
const MID := Vector2(192, 192)
const DIRECTIONS := ["N", "E", "S", "W"]
const BACKGROUND := Color("#101720")
## Last-resort atlas when a biome's tileset fails to load (rows 0-1 only).
const CRYPT = preload("res://assets/biomes/stone_crypt/tileset_16x16.png")
## Hazard patch animation: 4 frames at 6 fps (BIOMES_AND_TILESETS §8 Q4).
const HAZARD_FPS := 6.0
## Cells never dressed: the 4x4 spawn centre and the door lanes.
const DRESSING_DECAL_SLOTS := ["decal_a", "decal_b", "decal_c", "decal_d"]
const DRESSING_PROP_SLOTS := ["prop_small_a", "prop_small_b"]
const CRAWLER = preload("res://assets/characters/crawler/facing_8.png")
## Telegraph colours by attack type (sprite tint blends 50 % toward these).
const TELEGRAPH_COLORS := {"melee": Color("#ff5a4f"), "area": Color("#ffb347"),
    "dash": Color("#ff8c2a"), "ranged": Color("#d778dc"), "puddle": Color("#c6e05a"),
    "summon": Color("#f2a2c8"), "support": Color("#8fd3ff")}
## Legacy sampler regions (rows 0-1 of the standard atlas), kept for reference
## and for the CRYPT fallback; drawing goes through slot names now.
const FLOOR_TILE := Rect2(0, 0, 16, 16)
const FLOOR_ALT := Rect2(16, 0, 16, 16)
const WALL_TOP := Rect2(32, 0, 16, 16)
const WALL_EDGE_E := Rect2(48, 0, 16, 16)
const WALL_EDGE_W := Rect2(64, 0, 16, 16)
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
## DoorLock node (Wave 2D); null draws every door open.
var door_lock
## sprite id -> {texture: Texture2D, render: Vector2}, loaded on first use.
var _sheets: Dictionary = {}
## Biome atlas path -> Texture2D, loaded on first use (Wave 3B).
var _atlases: Dictionary = {}
## Biomes.art() of the room being drawn (set by _draw_room / use_biome).
var _art: Dictionary = {}


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
    layout["offset"] = base_offset + (grace_shake() + feel_shake()) * scale
    var offset: Vector2 = layout["offset"]
    draw_set_transform(offset, 0.0, Vector2.ONE * scale)
    _draw_room()
    _draw_actors()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    layout["offset"] = base_offset


func _draw_room() -> void:
    var room: Dictionary = RunState.floor["rooms"][RunState.current_room_id]
    var kind: String = String(room["kind"])
    var biome: String = String(room.get("biome", Biomes.default_id()))
    use_biome(biome)
    var state: Dictionary = RunState.current_room()
    var blocked: Dictionary = state.get("blocked", {})
    var floor_seed: int = RunState.floor_seed()
    var room_id: int = int(room["id"])
    var dressing: Dictionary = Biomes.dressing(biome)
    for y in range(SIZE):
        for x in range(SIZE):
            var cell := Vector2i(x, y)
            var tile_center := Vector2((float(x) + 0.5) * TILE, (float(y) + 0.5) * TILE)
            _piece(floor_slot(cell, floor_seed, room_id, dressing), tile_center, Vector2(TILE, TILE))
    var ambient: Color = Biomes.ambient(biome)
    if ambient.a > 0.0:
        draw_rect(ROOM, ambient)
    var tint := Color.TRANSPARENT
    if kind == "boss":
        tint = Color(0.3, 0.05, 0.09, 0.16)
    elif kind == "guild_hall":
        tint = Color(0.04, 0.30, 0.22, 0.14)
    elif kind == "exit":
        tint = Color(0.35, 0.24, 0.06, 0.14)
    if tint.a > 0.0:
        draw_rect(ROOM, tint)
    _draw_dressing(blocked, floor_seed, room_id, dressing, biome)
    _draw_patches(state.get("patches", []))

    for prop in state.get("props", []):
        _draw_obstacle(prop)
    _draw_room_features()
    _draw_pickups()

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
        _piece("stairs_down", MID, Vector2(32, 32))
        _text("EXIT", MID + Vector2(-16, -146), 17, Color("#ffdc91"))
    elif ROOM_LABELS.has(kind):
        _text(String(ROOM_LABELS[kind][0]), MID + Vector2(-28, -146), 17, ROOM_LABELS[kind][1])


# --- Wave 3B: biome slots, dressing and patches ----------------------------------

## Selects the biome whose atlas and slot map _piece() draws with.
func use_biome(biome: String) -> void:
    _art = Biomes.art(biome)


## The biome currently drawn (Biomes.art() shape), for tests and the HUD.
func current_art() -> Dictionary:
    return _art


## Atlas texture of the current biome (CRYPT when its tileset cannot load).
func atlas_texture() -> Texture2D:
    var path: String = String(_art.get("texture", ""))
    if path == "":
        return CRYPT
    if not _atlases.has(path):
        var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
        _atlases[path] = texture if texture != null else CRYPT
    return _atlases[path]


## Atlas region of `slot` in the current biome (standard layout when unnamed).
func slot_region(slot: String) -> Rect2:
    var slots: Dictionary = _art.get("slots", {})
    return slots.get(slot, Biomes.standard_region(slot))


## Floor slot of `cell`: the prototype's floor_b pattern, plus floor_c/d where
## the biome's floor_variant_chance allows (stone_crypt: 0, unchanged look).
static func floor_slot(cell: Vector2i, floor_seed: int, room_id: int, dressing: Dictionary) -> String:
    var chance: float = float(dressing.get("floor_variant_chance", 0.0))
    if chance > 0.0:
        var roll: int = Biomes.cell_hash(floor_seed, room_id, cell, 7)
        if float(roll % 1000) / 1000.0 < chance:
            return "floor_c" if roll % 2 == 0 else "floor_d"
    return "floor_b" if (cell.x * 17 + cell.y * 13) % 9 == 0 else "floor_a"


## Cosmetic decals and small props on free cells, chosen per cell from
## Biomes.cell_hash (no RNG): the same room always dresses the same way.
## Returns the slot drawn at each cell: {Vector2i: String}.
static func dressing_for(blocked: Dictionary, floor_seed: int, room_id: int,
        dressing: Dictionary) -> Dictionary:
    var picks: Dictionary = {}
    var decal_chance: float = float(dressing.get("decal_chance", 0.0))
    var prop_chance: float = float(dressing.get("prop_chance", 0.0))
    var feature_chance: float = float(dressing.get("feature_chance", 0.0))
    if decal_chance <= 0.0 and prop_chance <= 0.0 and feature_chance <= 0.0:
        return picks
    for y in range(1, SIZE - 1):
        for x in range(1, SIZE - 1):
            var cell := Vector2i(x, y)
            if blocked.has(cell) or not dressable(cell):
                continue
            var roll: int = Biomes.cell_hash(floor_seed, room_id, cell, 11)
            var unit: float = float(roll % 10000) / 10000.0
            var pick: int = Biomes.cell_hash(floor_seed, room_id, cell, 13)
            if unit < feature_chance:
                picks[cell] = "feature_b"
            elif unit < feature_chance + prop_chance:
                picks[cell] = DRESSING_PROP_SLOTS[pick % DRESSING_PROP_SLOTS.size()]
            elif unit < feature_chance + prop_chance + decal_chance:
                picks[cell] = DRESSING_DECAL_SLOTS[pick % DRESSING_DECAL_SLOTS.size()]
    return picks


## False for the 4x4 spawn centre and the door approach lanes.
static func dressable(cell: Vector2i) -> bool:
    if cell.x >= 10 and cell.x <= 13 and cell.y >= 10 and cell.y <= 13:
        return false
    if (cell.x == 11 or cell.x == 12) and (cell.y <= 3 or cell.y >= SIZE - 4):
        return false
    if (cell.y == 11 or cell.y == 12) and (cell.x <= 3 or cell.x >= SIZE - 4):
        return false
    return true


func _draw_dressing(blocked: Dictionary, floor_seed: int, room_id: int, dressing: Dictionary,
        biome: String) -> void:
    var picks: Dictionary = dressing_for(blocked, floor_seed, room_id, dressing)
    var light: Dictionary = Biomes.light(biome)
    for cell in picks.keys():
        var center: Vector2 = Contents.cell_center(cell)
        var slot: String = String(picks[cell])
        if slot == "feature_b" and float(light["alpha"]) > 0.0:
            _draw_light_pool(center, light)
        _piece(slot, center, Vector2(TILE, TILE))


## Soft light pool (two concentric discs) under glowing features.
func _draw_light_pool(center: Vector2, light: Dictionary) -> void:
    var color: Color = light["color"]
    var radius: float = float(light["radius"])
    var alpha: float = float(light["alpha"])
    draw_circle(center, radius, Color(color, alpha * 0.5))
    draw_circle(center, radius * 0.55, Color(color, alpha))


## Current animation frame of an armed patch (4 frames, HAZARD_FPS).
static func hazard_frame(time_seconds: float) -> int:
    return int(floorf(time_seconds * HAZARD_FPS)) % 4


## Biome floor patches: hazard frames (animated while armed, dimmed while
## re-arming) with edge/corner transitions on open sides, or a decal slot
## per cell (luminous puddles).
func _draw_patches(patches: Array) -> void:
    var t: float = float(Time.get_ticks_msec()) / 1000.0
    for patch in patches:
        var cells: Array = patch.get("cells", [])
        var armed: bool = bool(patch.get("armed", true))
        var tile: String = String(patch.get("tile", "hazard"))
        var modulation := Color.WHITE if armed else Color(1, 1, 1, 0.55)
        var lookup: Dictionary = {}
        for cell in cells:
            lookup[Vector2i(cell)] = true
        for cell in cells:
            var center: Vector2 = Contents.cell_center(Vector2i(cell))
            if tile == "hazard":
                var frame: int = hazard_frame(t + float(Vector2i(cell).x) * 0.07) if armed else 0
                _piece("hazard_f%d" % frame, center, Vector2(TILE, TILE), 0.0, modulation)
                for side in [["n", Vector2i(0, -1)], ["e", Vector2i(1, 0)], ["s", Vector2i(0, 1)],
                        ["w", Vector2i(-1, 0)]]:
                    if not lookup.has(Vector2i(cell) + side[1]):
                        _piece("haz_edge_" + String(side[0]), center, Vector2(TILE, TILE), 0.0,
                            modulation)
            else:
                _piece(tile, center, Vector2(TILE, TILE), 0.0, modulation)


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
    var amount: float = float(wave.get("shake", 0.0)) * Accessibility.shake_scale()
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
                _piece("chest", center, Vector2(TILE, TILE), 0.0, tint)
            "shrine":
                draw_circle(center, 7.0, Color("#8fb8ff", 0.35 if used else 0.9))
                draw_arc(center, 9.0, 0.0, TAU, 20, Color("#dfe9ff", tint.a), 1.0)
            "rest":
                draw_rect(Rect2(center - Vector2(7, 4), Vector2(14, 8)), Color("#6e9e8a", tint.a))
                draw_rect(Rect2(center - Vector2(7, 4), Vector2(4, 8)), Color("#e8f2ea", tint.a))
            "shop_sign", "shop":
                draw_rect(Rect2(center - Vector2(6, 7), Vector2(12, 8)), Color("#a77b4f"))
                draw_line(center + Vector2(0, 1), center + Vector2(0, 7), Color("#6b4a2b"), 2.0)
            _:
                draw_circle(center, 5.0, Color("#fff1a7", tint.a))


## The wall ring by slot: wall_top + wall_face(_lit) north, wall_south south,
## wall_edge_w / wall_edge_e on the sides (the floor-facing rim of each edge
## tile faces the room; see the asset README) and the four outer corners.
## Door gaps show a threshold tile under the leaves.
func _draw_walls(links: Dictionary) -> void:
    for x in range(SIZE):
        var px: float = (float(x) + 0.5) * TILE
        var gap: bool = x == 11 or x == 12
        if links.has("N") and gap:
            _piece("threshold", Vector2(px, -TILE * 0.5), Vector2(TILE, TILE))
        else:
            _piece("wall_top", Vector2(px, -TILE * 0.5), Vector2(TILE, TILE))
            _piece("wall_face_lit" if (x == 5 or x == 18) else "wall_face",
                Vector2(px, TILE * 0.5), Vector2(TILE, TILE))
        if links.has("S") and gap:
            _piece("threshold", Vector2(px, ROOM.end.y + TILE * 0.5), Vector2(TILE, TILE), PI)
        else:
            _piece("wall_south", Vector2(px, ROOM.end.y + TILE * 0.5), Vector2(TILE, TILE))
    for y in range(SIZE):
        var py: float = (float(y) + 0.5) * TILE
        var gap: bool = y == 11 or y == 12
        if links.has("W") and gap:
            _piece("threshold", Vector2(-TILE * 0.5, py), Vector2(TILE, TILE), -PI * 0.5)
        else:
            _piece("wall_edge_w", Vector2(-TILE * 0.5, py), Vector2(TILE, TILE))
        if links.has("E") and gap:
            _piece("threshold", Vector2(ROOM.end.x + TILE * 0.5, py), Vector2(TILE, TILE), PI * 0.5)
        else:
            _piece("wall_edge_e", Vector2(ROOM.end.x + TILE * 0.5, py), Vector2(TILE, TILE))
    _piece("corner_out_nw", Vector2(-8, -8), Vector2(TILE, TILE))
    _piece("corner_out_ne", Vector2(ROOM.end.x + 8, -8), Vector2(TILE, TILE))
    _piece("corner_out_se", ROOM.end + Vector2(8, 8), Vector2(TILE, TILE))
    _piece("corner_out_sw", Vector2(-8, ROOM.end.y + 8), Vector2(TILE, TILE))


## Door leaf slot: door_locked while DoorLock seals the room, door_open toward
## rooms already visited, door_closed otherwise.
func door_slot(next_id: int) -> String:
    if door_lock != null and float(door_lock.visual) > 0.5:
        return "door_locked"
    return "door_open" if RunState.visited.has(next_id) else "door_closed"


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
    var leaf: String = door_slot(next_id)
    _piece(leaf, door_center - door_offset, Vector2(TILE, TILE), rotation, color)
    _piece(leaf, door_center + door_offset, Vector2(TILE, TILE), rotation, color)
    _draw_door_lock(door_center, rotation)
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
    _piece("obstacle_pillar" if prop["kind"] == "pillar" else "obstacle_rubble", center,
        Vector2(TILE, TILE))


func _draw_actors() -> void:
    Hazards.draw_all(self, combat.hazards, ThemeDB.fallback_font)
    for projectile in combat.projectiles:
        var point: Vector2 = projectile["pos"]
        var color := Color("#ffe78b") if projectile["owner"] == "player" else Color("#d778dc")
        if projectile["owner"] != "player":
            draw_circle(point, 3.5, Color("#240a2a"))
        draw_circle(point, 2.5, color)
    for foe in RunState.current_room().get("enemies", []):
        _draw_enemy(foe)
    var at: Vector2 = player.world_position
    var aim: Vector2 = player.aim_direction
    _draw_dodge_trail(at)
    _draw_facing_sprite(CRAWLER, at, Vector2(24, 24), player.facing, _crawler_modulation())
    draw_line(at, at + aim * 13.0, Color("#f9dc92"), 1.0)
    # Wave 2B: the swing outline is the weapon's hit shape (arc / thrust / spin).
    if player.melee_flash > 0.0:
        _draw_swing(combat.last_swing)
    _draw_item_overlay()
    if player.invulnerability > 0.0:
        draw_arc(at, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.42), 1.0)
    _draw_fx()


func _sheet(sprite: String) -> Dictionary:
    if not _sheets.has(sprite):
        var info: Dictionary = Enemies.sheet_info(catalogue, sprite)
        _sheets[sprite] = {"texture": load(String(info["path"])) as Texture2D,
            "render": info["render"]}
    return _sheets[sprite]


func _draw_enemy(foe: Dictionary) -> void:
    var definition: Dictionary = catalogue["enemies"][foe["definition"]]
    var sheet: Dictionary = _sheet(String(definition["sprite"]))
    var sprite_size: Vector2 = sheet["render"]
    var point: Vector2 = foe["pos"]
    var state: String = String(foe.get("state", "idle"))
    var attack: Dictionary = Enemies.attack_by_id(definition, String(foe.get("attack", "")))
    var modulation := Color.WHITE
    if String(foe.get("tint", "")) != "":
        var tint := Color(String(foe["tint"]))
        draw_arc(point, sprite_size.x * 0.5 + 1.5, 0.0, TAU, 28, tint, 1.5)
        modulation = Color.WHITE.lerp(tint, 0.25)
    if state == "winding_up" or state == "dashing":
        # Wave 3C: high-contrast palette; no pulsing with reduced_flash.
        var cue: Color = Accessibility.telegraph_color(String(attack.get("type", "melee")),
            TELEGRAPH_COLORS)
        var pulse: float = Accessibility.steady(
            0.35 + 0.15 * sin(float(foe.get("state_time", 0.0)) * 18.0), 0.4)
        modulation = modulation.lerp(cue, pulse)
        _draw_telegraph(foe, attack, cue)
    if float(foe.get("dormant", 0.0)) > 0.0:
        modulation.a = 0.55
    modulation = _flash_modulation(String(foe.get("instance_id", "")), modulation)
    if float(foe.get("invulnerable", 0.0)) > 0.0:
        draw_arc(point, sprite_size.x * 0.5 + 3.0, 0.0, TAU, 28, Color(1, 1, 1, 0.6), 1.0)
    if sheet["texture"] != null:
        _draw_facing_sprite(sheet["texture"], point, sprite_size, int(foe["facing"]), modulation)
    else:
        draw_circle(point, float(foe["radius"]), modulation)
    if state == "stunned":
        _text("*", point + Vector2(-3, -sprite_size.y * 0.5 - 8), 12, Color("#ffe78b"))
    var bar_top: float = point.y - sprite_size.y * 0.5 - 6
    var hp_ratio: float = clampf(float(foe["hp"]) / float(foe["max_hp"]), 0.0, 1.0)
    draw_rect(Rect2(point.x - 12, bar_top, 24, 3), Color("#151b25"))
    draw_rect(Rect2(point.x - 12, bar_top, 24 * hp_ratio, 3), Color("#a5d49b"))
    var pool: int = int(foe.get("shield", 0)) + int(foe.get("ward", 0))
    if pool > 0:
        draw_rect(Rect2(point.x - 12, bar_top - 3, minf(24.0, 3.0 * float(pool)), 2),
            Color("#7fc4ff"))


## Shape cue for a wind-up, drawn where the attack will land: an arc at reach
## (melee), a 1 px aim line (ranged), a lane (dash) or a filling circle (area).
func _draw_telegraph(foe: Dictionary, attack: Dictionary, cue: Color) -> void:
    var point: Vector2 = foe["pos"]
    var aim: Vector2 = foe.get("aim", Vector2.RIGHT)
    var length: float = maxf(0.001, float(foe.get("state_length", 1.0)))
    var progress: float = clampf(float(foe.get("state_time", 0.0)) / length, 0.0, 1.0)
    var faint := Color(cue, Accessibility.telegraph_fill())
    if Accessibility.colorblind_telegraphs():
        _draw_telegraph_pattern(foe, attack, cue, progress)
    match String(attack.get("telegraph", "arc")):
        "arc":
            var reach: float = float(attack.get("range", 22.0)) + 5.5
            var half: float = deg_to_rad(float(attack.get("arc", 120.0))) * 0.5
            var fan := PackedVector2Array([point])
            for i in range(13):
                fan.append(point + aim.rotated(-half + 2.0 * half * float(i) / 12.0) * reach * progress)
            if progress > 0.05:
                draw_colored_polygon(fan, faint)
            draw_arc(point, reach, aim.angle() - half, aim.angle() + half, 14, cue, 1.5)
        "line":
            draw_line(point, point + aim * float(attack.get("range", 120.0)), Color(cue, 0.8), 1.0)
        "dash":
            var lane: float = float(attack.get("dash_distance", 64.0)) if String(foe["state"]) != "dashing" \
                else float(foe.get("dash_left", 0.0))
            var side: Vector2 = aim.orthogonal() * float(foe["radius"])
            var far: Vector2 = point + aim * lane
            draw_colored_polygon(PackedVector2Array([point + side, far + side, far - side,
                point - side]), faint)
            draw_polyline(PackedVector2Array([point + side, far + side, far - side, point - side,
                point + side]), cue, 1.0)
        "circle":
            var center: Vector2 = foe.get("target_point", point)
            var radius: float = float(attack.get("aoe_radius", 24.0))
            draw_circle(center, radius * progress, faint)
            draw_arc(center, radius, 0.0, TAU, 32, cue, 1.5)


## Wave 3C colour-blind telegraphs: a dark-underlaid pattern inside the shape
## (radial spokes for arcs, rungs across dash lanes, chords across circles,
## ticks along aim lines) and a letter for the attack type over the attacker,
## so telegraphs differ by more than colour.
const TELEGRAPH_LETTERS := {"melee": "M", "area": "A", "dash": "D", "ranged": "R",
    "puddle": "P", "summon": "S", "support": "+"}


func _draw_telegraph_pattern(foe: Dictionary, attack: Dictionary, cue: Color, progress: float) -> void:
    var point: Vector2 = foe["pos"]
    var aim: Vector2 = foe.get("aim", Vector2.RIGHT)
    var dark := Color(0.02, 0.02, 0.04, 0.85)
    var lines: Array = []
    match String(attack.get("telegraph", "arc")):
        "arc":
            var reach: float = float(attack.get("range", 22.0)) + 5.5
            var half: float = deg_to_rad(float(attack.get("arc", 120.0))) * 0.5
            for i in range(5):
                var direction: Vector2 = aim.rotated(-half + 2.0 * half * float(i) / 4.0)
                lines.append([point + direction * reach * 0.35, point + direction * reach])
        "line":
            var reach: float = float(attack.get("range", 120.0))
            var side: Vector2 = aim.orthogonal() * 3.0
            var step := 12.0
            while step < reach:
                lines.append([point + aim * step - side, point + aim * step + side])
                step += 12.0
        "dash":
            var lane: float = float(attack.get("dash_distance", 64.0))
            var side: Vector2 = aim.orthogonal() * float(foe.get("radius", 6.0))
            var step := 8.0
            while step < lane:
                lines.append([point + aim * step - side, point + aim * step + side])
                step += 8.0
        "circle":
            var center: Vector2 = foe.get("target_point", point)
            var radius: float = float(attack.get("aoe_radius", 24.0))
            var offset: float = -radius + 6.0
            while offset < radius:
                var half_chord: float = sqrt(maxf(0.0, radius * radius - offset * offset))
                var a: Vector2 = center + Vector2(-half_chord, offset).rotated(PI * 0.25)
                var b: Vector2 = center + Vector2(half_chord, offset).rotated(PI * 0.25)
                lines.append([a, b])
                offset += 6.0
    for segment in lines:
        draw_line(segment[0], segment[1], dark, 2.5)
        draw_line(segment[0], segment[1], Color(cue, 0.55 + 0.4 * progress), 1.0)
    var letter: String = String(TELEGRAPH_LETTERS.get(String(attack.get("type", "melee")), "!"))
    var at: Vector2 = point + Vector2(-3.5, -16.0)
    draw_string_outline(ThemeDB.fallback_font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, 3, dark)
    draw_string(ThemeDB.fallback_font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, cue)


## Draws one atlas slot of the current biome at `center` (world px), tinted by
## the biome's fallback tint when it borrows another biome's art.
func _piece(slot: String, center: Vector2, size: Vector2, rotation: float = 0.0,
        modulation: Color = Color.WHITE) -> void:
    if _art.is_empty():
        use_biome(Biomes.default_id())
    var tint: Color = _art.get("tint", Color.WHITE)
    _atlas_piece(atlas_texture(), slot_region(slot), center, size, rotation,
        modulation if tint == Color.WHITE else modulation * tint)


func _atlas_piece(atlas: Texture2D, region: Rect2, center: Vector2, size: Vector2,
        rotation: float = 0.0, modulation: Color = Color.WHITE) -> void:
    var offset: Vector2 = layout["offset"]
    var scale: float = float(layout["scale"])
    draw_set_transform(offset + center * scale, rotation, Vector2.ONE * scale)
    draw_texture_rect_region(atlas, Rect2(-size * 0.5, size), region, modulation)
    draw_set_transform(offset, 0.0, Vector2.ONE * scale)


func _draw_facing_sprite(sheet: Texture2D, center: Vector2, size: Vector2, facing: int,
        modulation: Color = Color.WHITE) -> void:
    var index: int = posmod(facing, 8)
    var frame_size := Vector2(sheet.get_width() / 8.0, sheet.get_height())
    draw_texture_rect_region(sheet, Rect2(center - size * 0.5, size),
        Rect2(float(index) * frame_size.x, 0.0, frame_size.x, frame_size.y), modulation)


func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


# --- Wave 2B: pickups, swings, beams, decoy and status markers -----------------

## Floor loot: a rarity-coloured diamond (weapons get a blade line, the loot
## box is a gold crate) with a slow pulse ring. The tooltip is the HUD's job.
func _draw_pickups() -> void:
    var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 260.0)
    for entry in RunState.current_room().get("pickups", []):
        var center: Vector2 = entry["pos"]
        var id: String = String(entry["id"])
        if id == "loot_box":
            draw_rect(Rect2(center - Vector2(7, 6), Vector2(14, 12)), Color("#b8862f"))
            draw_rect(Rect2(center - Vector2(7, 6), Vector2(14, 12)), Color("#ffe08a"), false, 1.0)
            draw_line(center + Vector2(-7, -1), center + Vector2(7, -1), Color("#ffe08a"), 1.0)
            draw_arc(center, 11.0 + pulse * 2.0, 0.0, TAU, 24, Color("#ffd24a", 0.6), 1.0)
            continue
        var info: Dictionary = Inventory.label(id)
        var color: Color = info["color"]
        var diamond := PackedVector2Array([center + Vector2(0, -6), center + Vector2(5, 0),
            center + Vector2(0, 6), center + Vector2(-5, 0)])
        draw_colored_polygon(diamond, Color(color, 0.85))
        draw_polyline(diamond + PackedVector2Array([center + Vector2(0, -6)]), Color.WHITE, 1.0)
        if String(info["kind"]) == "weapon":
            draw_line(center + Vector2(-4, 4), center + Vector2(4, -4), Color("#20262e"), 1.5)
        draw_arc(center, 8.0 + pulse * 1.5, 0.0, TAU, 20, Color(color, 0.45), 1.0)
        if int(entry.get("count", 1)) > 1:
            _text(str(int(entry["count"])), center + Vector2(4, -4), 8, Color.WHITE)


## The last swing's hit shape: a sector at reach (arc), a 10 px lane (thrust)
## or a circle (spin).
func _draw_swing(swing: Dictionary) -> void:
    if swing.is_empty():
        return
    var origin: Vector2 = player.world_position
    var aim: Vector2 = swing.get("direction", player.aim_direction)
    var reach: float = float(swing.get("reach", 32.0))
    var color := Color("#fff1a7")
    match String(swing.get("pattern", "arc")):
        "thrust":
            var side: Vector2 = aim.orthogonal() * float(swing.get("width", 10.0)) * 0.5
            var far: Vector2 = origin + aim * reach
            draw_colored_polygon(PackedVector2Array([origin + side, far + side, far - side,
                origin - side]), Color(color, 0.25))
            draw_polyline(PackedVector2Array([origin + side, far + side, far - side,
                origin - side]), color, 1.5)
        "spin":
            draw_circle(origin, reach, Color(color, 0.12))
            draw_arc(origin, reach, 0.0, TAU, 32, color, 2.0)
        _:
            var half: float = deg_to_rad(float(swing.get("arc_degrees", 127.0))) * 0.5
            var fan := PackedVector2Array([origin])
            for i in range(15):
                fan.append(origin + aim.rotated(-half + 2.0 * half * float(i) / 14.0) * reach)
            draw_colored_polygon(fan, Color(color, 0.18))
            draw_arc(origin, reach, aim.angle() - half, aim.angle() + half, 16, color, 2.5)


## Beam ticks, the concealment decoy and status markers on every actor.
func _draw_item_overlay() -> void:
    for beam in combat.beams:
        var fade: float = clampf(float(beam["ttl"]) / 0.08, 0.0, 1.0)
        draw_line(beam["from"], beam["to"], Color(1.0, 0.3, 0.25, 0.9 * fade), 2.0)
        draw_line(beam["from"], beam["to"], Color(1, 1, 1, 0.7 * fade), 0.7)
    var decoy: Vector2 = StatusSystem.decoy_position()
    if decoy != Vector2.INF:
        _draw_facing_sprite(CRAWLER, decoy, Vector2(24, 24), 2, Color(1, 1, 1, 0.55))
        _text("FAN CLUB", decoy + Vector2(-20, -16), 8, Color("#ffd2f0"))
    draw_status_markers()


## Status pips above each enemy's HP bar and above the crawler: one coloured
## square per status (StatusSystem.COLORS), with the stack count when > 1.
## Self-contained: reads RunState and the enemy catalogue only.
func draw_status_markers() -> void:
    for foe in RunState.current_room().get("enemies", []):
        var statuses: Dictionary = foe.get("statuses", {})
        if statuses.is_empty() or int(foe.get("hp", 0)) <= 0:
            continue
        var definition: Dictionary = catalogue.get("enemies", {}).get(foe["definition"], {})
        var sprite_size: Vector2 = _sheet(String(definition.get("sprite", "rat")))["render"]
        var top: float = Vector2(foe["pos"]).y - sprite_size.y * 0.5 - 13.0
        _draw_status_row(statuses, Vector2(Vector2(foe["pos"]).x, top))
    if not RunState.statuses.is_empty():
        _draw_status_row(RunState.statuses, player.world_position + Vector2(0, -19))


func _draw_status_row(statuses: Dictionary, center: Vector2) -> void:
    var ids: Array = statuses.keys()
    ids.sort()
    var start: float = center.x - float(ids.size()) * 3.5
    for i in range(ids.size()):
        var at := Vector2(start + float(i) * 7.0, center.y)
        var color: Color = StatusSystem.COLORS.get(String(ids[i]), Color.WHITE)
        draw_rect(Rect2(at, Vector2(5, 5)), color)
        draw_rect(Rect2(at, Vector2(5, 5)), Color("#0b0f16"), false, 1.0)
        var stacks: int = int(statuses[ids[i]].get("stacks", 1))
        if stacks > 1:
            _text(str(stacks), at + Vector2(0, -1), 6, Color.WHITE)


# --- Combat feel (Wave 2D) -------------------------------------------------------

## Hit-feedback shake in world pixels (already scaled by the screen-shake setting).
func feel_shake() -> Vector2:
    if combat == null or combat.fx == null:
        return Vector2.ZERO
    return combat.fx.shake_offset()


## `modulation` pushed toward the fx flash colour of `key` (HDR white for enemies).
func _flash_modulation(key: String, modulation: Color) -> Color:
    if combat == null or key == "":
        return modulation
    var amount: float = combat.fx.flash_amount(key)
    if amount <= 0.0:
        return modulation
    var flashed: Color = combat.fx.flash_color(key)
    flashed.a = modulation.a
    return modulation.lerp(flashed, amount)


## Crawler tint: red hit flash, and a blink while any i-frames run.
func _crawler_modulation() -> Color:
    var modulation: Color = _flash_modulation("player", Color.WHITE)
    if player.is_invulnerable():
        var t: float = float(Time.get_ticks_msec()) / 1000.0
        # Wave 3C: reduced_flash replaces the 8 Hz blink with a steady fade.
        modulation.a = 0.6 if Accessibility.reduced_flash() \
            else (0.35 if int(t * 16.0) % 2 == 0 else 0.9)
    return modulation


## Fading afterimages behind the crawler while it dashes.
func _draw_dodge_trail(at: Vector2) -> void:
    if not player.is_dodging():
        return
    var back: Vector2 = -player.dodge_direction
    for i in range(3):
        var ghost := Color(0.75, 0.9, 1.0, 0.32 - 0.09 * float(i))
        _draw_facing_sprite(CRAWLER, at + back * (5.0 + 6.0 * float(i)), Vector2(24, 24),
            player.facing, ghost)


## Floating damage numbers and death-burst particles.
func _draw_fx() -> void:
    if combat == null:
        return
    for burst in combat.fx.bursts:
        var t: float = clampf(float(burst["age"]) / float(burst["life"]), 0.0, 1.0)
        var color: Color = burst["color"]
        color.a = 1.0 - t
        for particle in burst["particles"]:
            var size: float = float(particle["size"]) * (1.0 - 0.5 * t)
            var point: Vector2 = Vector2(burst["pos"]) + Vector2(particle["dir"]) \
                * float(particle["speed"]) * float(burst["life"]) * (1.0 - (1.0 - t) * (1.0 - t))
            draw_rect(Rect2(point - Vector2(size, size) * 0.5, Vector2(size, size)), color)
    var font: Font = ThemeDB.fallback_font
    for entry in combat.fx.numbers:
        var pose: Dictionary = combat.fx.number_pose(entry)
        var text: String = String(entry["text"])
        var size: int = int(entry["size"])
        var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
        var at: Vector2 = Vector2(pose["pos"]) + Vector2(-width * 0.5, -12.0)
        var color: Color = entry["color"]
        color.a = float(pose["alpha"])
        draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 3,
            Color(0.05, 0.05, 0.08, color.a))
        draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## Sealed-door overlay (D-07): a red lock tint over both leaves and an iron
## bar across the opening, faded by door_lock.visual (doors animate open).
func _draw_door_lock(door_center: Vector2, rotation: float) -> void:
    if door_lock == null or float(door_lock.visual) <= 0.0:
        return
    var amount: float = float(door_lock.visual)
    var across: Vector2 = Vector2(TILE, 0).rotated(rotation)
    var inward: Vector2 = Vector2(0, TILE * 0.5).rotated(rotation)
    var half: Vector2 = Vector2(TILE, TILE * 0.5).rotated(rotation).abs()
    draw_rect(Rect2(door_center + inward * 0.5 - half, half * 2.0), Color(0.75, 0.08, 0.1, 0.38 * amount))
    draw_line(door_center + inward * 0.5 - across, door_center + inward * 0.5 + across,
        Color(0.2, 0.2, 0.24, amount), 3.0)
    draw_circle(door_center + inward * 0.5, 2.5, Color(1.0, 0.82, 0.35, amount))
