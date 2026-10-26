extends RefCounted
## Biome catalogue (D-15, BIOMES_AND_TILESETS.md; PROCEDURAL_GENERATION §8).
##
## Loads and validates `data/biomes.json` and answers:
## - which biome a depth or a room uses: for_depth(depth), for_room(room, depth)
##   (guild halls are always `guild_interior`), assign(floor) to stamp them;
## - how to draw it: art(id) -> {biome, art_biome, texture, tint, fallback,
##   slots {name: Rect2}}; region(id, slot) -> Rect2. A biome without art
##   (empty or missing `tileset`) draws the `fallback_art` biome's atlas
##   multiplied by its `fallback_tint`, and keeps its hazards and affinities;
## - what it does: hazard_specs(id, room_kind), grace_hazard(id), ambient(id),
##   light(id), dressing(id); cell_hash() seeds cosmetic dressing per cell.
## Slots follow the standard 128x96 atlas (8 x 6 slots of 16 px); a biome's
## tiles.json names them, falling back to STANDARD_LAYOUT positions.
## Pure module: no autoload references, safe to preload from tests.

const PATH := "res://data/biomes.json"
const SCHEMA_VERSION := 1
const TILE := 16
const ATLAS_SIZE := Vector2i(128, 96)
const GUILD_BIOME := "guild_interior"
const STATUSES := ["implemented", "fallback", "planned"]
## BIOMES_AND_TILESETS §2, row by row.
const STANDARD_LAYOUT := [
    ["floor_a", "floor_b", "wall_top", "wall_edge_e", "wall_edge_w", "wall_face",
        "wall_face_lit", "door_closed"],
    ["stairs_down", "obstacle_pillar", "chest", "obstacle_rubble", "floor_c", "floor_d",
        "decal_a", "decal_b"],
    ["wall_south", "corner_out_nw", "corner_out_ne", "corner_out_se", "corner_out_sw",
        "door_open", "door_locked", "threshold"],
    ["corner_in_nw", "corner_in_ne", "corner_in_se", "corner_in_sw", "decal_c", "decal_d",
        "prop_small_a", "prop_small_b"],
    ["hazard_f0", "hazard_f1", "hazard_f2", "hazard_f3", "destructible", "destructible_broken",
        "feature_a", "feature_b"],
    ["haz_edge_n", "haz_edge_e", "haz_edge_s", "haz_edge_w", "haz_corner_nw", "haz_corner_ne",
        "haz_corner_se", "haz_corner_sw"],
]
## Keys every hazards[] entry needs.
const HAZARD_KEYS := ["kind", "tile", "status", "damage", "telegraph", "duration", "rearm",
    "radius", "color", "cells", "per_room", "room_kinds"]
const STATUS_IDS := ["", "burning", "poisoned", "bleeding", "slowed", "stunned"]

static var _data: Dictionary = {}
static var _tiles: Dictionary = {}
static var _art: Dictionary = {}


## The parsed catalogue (cached). `{}` when the file is missing or invalid JSON.
static func catalogue() -> Dictionary:
    if _data.is_empty():
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        _data = parsed if parsed is Dictionary else {}
    return _data


## Drops the caches (tests that edit data, hot reload).
static func reload() -> void:
    _data = {}
    _tiles = {}
    _art = {}


static func ids() -> Array:
    var list: Array = catalogue().get("biomes", {}).keys()
    list.sort()
    return list


static func default_id() -> String:
    return String(catalogue().get("default_biome", "stone_crypt"))


## The biome definition, or {} for an unknown id.
static func biome(id: String) -> Dictionary:
    return catalogue().get("biomes", {}).get(id, {})


static func display_name(id: String) -> String:
    return String(biome(id).get("name", id.capitalize()))


## The biome whose `depths` band [min, max] (max -1 = open-ended) holds `depth`.
## Depths past every band reuse the deepest band (PROCEDURAL_GENERATION §3).
static func for_depth(depth: int) -> String:
    var deepest := ""
    var deepest_min := -1
    for id in ids():
        var band: Array = biome(id).get("depths", [])
        if band.size() != 2:
            continue
        var low: int = int(band[0])
        var high: int = int(band[1])
        if depth >= low and (high < 0 or depth <= high):
            return id
        if low > deepest_min:
            deepest_min = low
            deepest = id
    if deepest != "" and depth >= deepest_min:
        return deepest
    return default_id()


## Biome of one room: a biome listing the room's kind in `room_kinds` wins
## (guild halls -> guild_interior at every depth), otherwise for_depth().
static func for_room(room: Dictionary, depth: int) -> String:
    var kind: String = String(room.get("kind", "normal"))
    for id in ids():
        if Array(biome(id).get("room_kinds", [])).has(kind):
            return id
    return for_depth(depth)


## Stamps `floor.biome` (the depth's biome) and `biome` on every room. Pure
## function of depth and kinds: draws no random numbers, so layouts, kinds and
## Generator.signature() are unchanged.
static func assign(floor: Dictionary) -> void:
    var depth: int = maxi(1, int(floor.get("depth", 1)))
    floor["biome"] = for_depth(depth)
    for room in floor.get("rooms", []):
        room["biome"] = for_room(room, depth)


## True when the biome ships its own atlas (the tileset resource exists).
static func has_art(id: String) -> bool:
    var path: String = String(biome(id).get("tileset", ""))
    return path != "" and ResourceLoader.exists(path)


static func standard_region(slot: String) -> Rect2:
    for row in range(STANDARD_LAYOUT.size()):
        var col: int = STANDARD_LAYOUT[row].find(slot)
        if col >= 0:
            return Rect2(col * TILE, row * TILE, TILE, TILE)
    return Rect2()


static func all_slots() -> Array:
    var names: Array = []
    for row in STANDARD_LAYOUT:
        names.append_array(row)
    return names


## A tiles.json file parsed (cached); {} when missing.
static func load_tiles(path: String) -> Dictionary:
    if path == "":
        return {}
    if not _tiles.has(path):
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) \
            if FileAccess.file_exists(path) else null
        _tiles[path] = parsed if parsed is Dictionary else {}
    return _tiles[path]


## Drawing info for biome `id`: {biome, art_biome, texture (res:// path),
## tint (Color), fallback (bool), slots {name: Rect2}}. Art-less or unknown
## biomes resolve to the fallback_art biome's atlas tinted by fallback_tint.
static func art(id: String) -> Dictionary:
    if _art.has(id):
        return _art[id]
    var art_id: String = id
    var fallback: bool = not has_art(id)
    if fallback:
        art_id = String(catalogue().get("fallback_art", "stone_crypt"))
    var source: Dictionary = biome(art_id)
    var tint := Color.WHITE
    if fallback and not biome(id).is_empty():
        tint = Color(String(biome(id).get("fallback_tint", "#ffffff")))
    var tiles: Dictionary = load_tiles(String(source.get("tiles", "")))
    var size: int = int(tiles.get("tile_size", TILE))
    var named: Dictionary = tiles.get("slots", {})
    var fallbacks: Dictionary = tiles.get("fallbacks", {})
    var slots: Dictionary = {}
    for slot in all_slots():
        var key: String = String(slot)
        if fallbacks.has(key) and not named.has(key):
            key = String(fallbacks[key])
        if named.has(key) and named[key] is Array and named[key].size() == 2:
            slots[slot] = Rect2(int(named[key][0]) * size, int(named[key][1]) * size, size, size)
        else:
            slots[slot] = standard_region(key)
    var info := {"biome": id, "art_biome": art_id, "texture": String(source.get("tileset", "")),
        "tint": tint, "fallback": fallback, "slots": slots}
    _art[id] = info
    return info


## Atlas region of `slot` for biome `id` (fallback rules of art()).
static func region(id: String, slot: String) -> Rect2:
    return art(id)["slots"].get(slot, standard_region(slot))


## hazards[] entries of biome `id` that apply to rooms of `room_kind` ("" = all).
static func hazard_specs(id: String, room_kind: String = "") -> Array:
    var specs: Array = []
    for spec in biome(id).get("hazards", []):
        if room_kind == "" or Array(spec.get("room_kinds", [])).has(room_kind):
            specs.append(spec)
    return specs


## Keys merged over the collapse grace debris entry (kind, status, color as a
## Color). {} keeps plain debris.
static func grace_hazard(id: String) -> Dictionary:
    var spec: Dictionary = biome(id).get("grace_hazard", {}).duplicate()
    if spec.has("color"):
        spec["color"] = Color(String(spec["color"]))
    return spec


## Translucent overlay drawn over the floor (alpha 0 = none).
static func ambient(id: String) -> Color:
    return Color(String(biome(id).get("ambient", "#00000000")))


## {color: Color, alpha: float, radius: float} light pools around lit features.
static func light(id: String) -> Dictionary:
    var spec: Dictionary = biome(id).get("light", {})
    return {"color": Color(String(spec.get("color", "#ffffff"))),
        "alpha": float(spec.get("alpha", 0.0)), "radius": float(spec.get("radius", 0.0))}


## {decal_chance, prop_chance, feature_chance} per free floor cell.
static func dressing(id: String) -> Dictionary:
    var spec: Dictionary = biome(id).get("dressing", {})
    return {"decal_chance": float(spec.get("decal_chance", 0.0)),
        "prop_chance": float(spec.get("prop_chance", 0.0)),
        "feature_chance": float(spec.get("feature_chance", 0.0))}


## Deterministic non-negative hash of (seed, room, cell, salt): cosmetic
## dressing draws no RNG state from RunState or the generators.
static func cell_hash(seed_value: int, room_id: int, cell: Vector2i, salt: int = 0) -> int:
    var h: int = (seed_value * 374761393 + room_id * 668265263 + cell.x * 2246822519
        + cell.y * 3266489917 + salt * 2654435761) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return (h ^ (h >> 16)) & 0x7fffffff


## Problems in `data` (default: the loaded catalogue); [] when valid.
static func validate(data: Dictionary = {}) -> Array[String]:
    if data.is_empty():
        data = catalogue()
    var problems: Array[String] = []
    if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    var biomes: Dictionary = data.get("biomes", {})
    if biomes.is_empty():
        problems.append("biomes: catalogue is empty")
    for key in ["default_biome", "fallback_art"]:
        if not biomes.has(String(data.get(key, ""))):
            problems.append("%s must name a biome" % key)
    var fallback_id: String = String(data.get("fallback_art", ""))
    if biomes.has(fallback_id) and String(biomes[fallback_id].get("tileset", "")) == "":
        problems.append("fallback_art biome '%s' needs a tileset" % fallback_id)
    var bands: Array = []
    for id in biomes.keys():
        var entry: Dictionary = biomes[id]
        var label: String = "biomes.%s" % id
        for key in ["name", "status", "depths", "tileset", "tiles", "fallback_tint", "palette",
                "hazards", "grace_hazard"]:
            if not entry.has(key):
                problems.append("%s: missing %s" % [label, key])
        if not STATUSES.has(String(entry.get("status", ""))):
            problems.append("%s: status must be one of %s" % [label, ", ".join(STATUSES)])
        for key in ["fallback_tint", "ambient"]:
            if entry.has(key) and not Color.html_is_valid(String(entry[key])):
                problems.append("%s: %s is not a colour" % [label, key])
        var depths = entry.get("depths", [])
        if not depths is Array or not (depths.size() == 0 or depths.size() == 2):
            problems.append("%s: depths must be [] or [min, max]" % label)
        elif depths.size() == 2:
            if int(depths[0]) < 1 or (int(depths[1]) >= 0 and int(depths[1]) < int(depths[0])):
                problems.append("%s: invalid depth band %s" % [label, str(depths)])
            bands.append([int(depths[0]), int(depths[1]) if int(depths[1]) >= 0 else 1 << 30, id])
        elif Array(entry.get("room_kinds", [])).is_empty():
            problems.append("%s: needs a depth band or room_kinds" % label)
        _validate_palette(label, entry.get("palette", {}), problems)
        var has_tileset: bool = String(entry.get("tileset", "")) != ""
        if has_tileset != (String(entry.get("tiles", "")) != ""):
            problems.append("%s: tileset and tiles must both be set or both empty" % label)
        if has_tileset and String(entry.get("status", "")) == "fallback":
            problems.append("%s: a biome with art is not 'fallback'" % label)
        for spec in entry.get("hazards", []):
            _validate_hazard(label, spec, problems)
        var grace = entry.get("grace_hazard", {})
        if not grace is Dictionary:
            problems.append("%s: grace_hazard must be an object" % label)
        elif grace.has("color") and not Color.html_is_valid(String(grace["color"])):
            problems.append("%s: grace_hazard.color is not a colour" % label)
        elif not STATUS_IDS.has(String(grace.get("status", ""))):
            problems.append("%s: grace_hazard.status '%s' is unknown" % [label, grace.get("status")])
    bands.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
    for i in range(1, bands.size()):
        if int(bands[i][0]) <= int(bands[i - 1][1]):
            problems.append("depth bands of %s and %s overlap" % [bands[i - 1][2], bands[i][2]])
        elif int(bands[i][0]) != int(bands[i - 1][1]) + 1:
            problems.append("depth gap between %s and %s" % [bands[i - 1][2], bands[i][2]])
    if not bands.is_empty() and int(bands[0][0]) != 1:
        problems.append("depth bands must start at depth 1")
    return problems


static func _validate_palette(label: String, palette, problems: Array[String]) -> void:
    if not palette is Dictionary or not palette.has("outline"):
        problems.append("%s: palette needs an outline colour" % label)
        return
    for role in palette.keys():
        var values: Array = palette[role] if palette[role] is Array else [palette[role]]
        for value in values:
            if not Color.html_is_valid(String(value)):
                problems.append("%s: palette.%s has a bad colour '%s'" % [label, role, value])


static func _validate_hazard(label: String, spec, problems: Array[String]) -> void:
    if not spec is Dictionary:
        problems.append("%s: hazards entries must be objects" % label)
        return
    for key in HAZARD_KEYS:
        if not spec.has(key):
            problems.append("%s: hazard missing %s" % [label, key])
            return
    var name: String = "%s: hazard %s" % [label, spec["kind"]]
    if not STATUS_IDS.has(String(spec["status"])):
        problems.append("%s: unknown status '%s'" % [name, spec["status"]])
    if int(spec["damage"]) <= 0 and String(spec["status"]) == "":
        problems.append("%s: needs damage or a status" % name)
    if String(spec["tile"]) != "hazard" and not all_slots().has(String(spec["tile"])):
        problems.append("%s: tile must be 'hazard' or a slot name" % name)
    if not Color.html_is_valid(String(spec["color"])):
        problems.append("%s: color is not a colour" % name)
    for key in ["telegraph", "duration", "rearm", "radius"]:
        if float(spec[key]) < 0.0:
            problems.append("%s: %s must be >= 0" % [name, key])
    for key in ["cells", "per_room"]:
        var pair = spec[key]
        if not pair is Array or pair.size() != 2 or int(pair[0]) < 0 or int(pair[1]) < int(pair[0]):
            problems.append("%s: %s must be [min, max]" % [name, key])
    if int(spec["cells"][0]) < 1:
        problems.append("%s: patches need at least one cell" % name)


## Problems in a tiles.json dictionary; [] when every standard slot is named
## (directly or through `fallbacks`) inside the atlas.
static func validate_tiles(tiles: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    var named: Dictionary = tiles.get("slots", {})
    var fallbacks: Dictionary = tiles.get("fallbacks", {})
    var columns: int = int(tiles.get("columns", 8))
    var rows: int = int(tiles.get("rows", 6))
    for slot in all_slots():
        var key: String = String(slot)
        if not named.has(key) and fallbacks.has(key):
            key = String(fallbacks[key])
        if not named.has(key):
            problems.append("tiles: slot %s is not named" % slot)
            continue
        var pos = named[key]
        if not pos is Array or pos.size() != 2 or int(pos[0]) < 0 or int(pos[0]) >= columns \
                or int(pos[1]) < 0 or int(pos[1]) >= rows:
            problems.append("tiles: slot %s is outside the %dx%d grid" % [slot, columns, rows])
    return problems
