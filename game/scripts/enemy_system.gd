extends RefCounted
## Enemy catalogue (res://data/enemies.json, schema v2), encounter budgets, spawn
## placement and the per-enemy AI state machine.
##
## Pure logic: no autoloads and no nodes, so tests may preload this script.
## step() advances one enemy dictionary and returns *actions* (strikes,
## projectiles, hazards, summons, support casts) that Combat resolves with
## `RunState.rng`; everything an enemy remembers lives in its dictionary.
## Spec: docs/design/ENEMY_TIERS.md and docs/design/ENCOUNTER_RULES.md.
##
## Enemy dictionary (one per live enemy, persisted in RunState.room_states):
##   identity   instance_id, definition, name, tags (target_tag), boss, elite,
##              modifiers, tint (html colour or ""), band, veteran, threat, xp
##   body       pos, spawn_pos, radius, facing (0..7), hp, max_hp, ac, dr, speed,
##              knockback_resist (0..1; 1 = immune)
##   scaling    attack_bonus_add, damage_bonus_add, damage_mult, wind_up_mult,
##              min_wind_up
##   defence    shield / shield_max / shield_regen (bulwark pool), ward / ward_time
##              (support pool), invulnerable (s, phase roar)
##   AI         state ("idle", "winding_up", "dashing", "recovery", "stunned"),
##              state_time, state_length, attack (id), queued (follow-up id), aim,
##              target_point, dash_left, dash_hit, attack_cooldown (global delay),
##              cooldowns {attack_id: s}, dormant (s), phase, volley, repath,
##              waypoints
##   summons    summoner (parent instance_id or ""), summon_serial, rng_seed
const Room = preload("res://scripts/room_contents.gd")
const RPG = preload("res://scripts/rpg_rules.gd")

const SCHEMA_VERSION := 2
const CATALOGUE_PATH := "res://data/enemies.json"
## True room midpoint (cell (12, 12)'s centre is (200, 200)).
const MID := Vector2(192, 192)
const PLAYER_SPEED := 105.0
const PLAYER_RADIUS := 5.5
const ROLES := ["chaser", "ranged", "charger", "zoner", "summoner", "tank", "support",
    "elite", "miniboss", "boss"]
const MODES := ["chase", "kite", "guard", "charge", "zone", "summon", "support"]
const NAVIGATION := ["grid_bfs", "direct", "stationary"]
const ATTACK_TYPES := ["melee", "ranged", "dash", "area", "puddle", "summon", "support"]
const TELEGRAPHS := ["arc", "line", "circle", "dash"]
const TELEGRAPH_FOR_TYPE := {"melee": ["arc", "circle"], "ranged": ["line"], "dash": ["dash"],
    "area": ["circle"], "puddle": ["circle"], "summon": ["circle"], "support": ["circle"]}
const ABILITY_IDS := ["lunge", "twin_shot", "summon", "dash", "puddle", "shield_allies",
    "heal_allies", "enrage"]
## Attack type -> ability id the enemy must list to use it.
const REQUIRED_ABILITY := {"dash": "dash", "puddle": "puddle", "summon": "summon"}
const SUPPORT_EFFECTS := {"shield": "shield_allies", "heal": "heal_allies"}
const DAMAGE_TYPES := ["physical", "fire", "toxic", "arcane"]
const STATUS_IDS := ["burning", "poisoned", "bleeding", "slowed", "stunned", "shielded",
    "hasted", "evasive", "concealed", "vulnerable", "weakened", "marked", "rooted"]
const NON_POOL_ROLES := ["elite", "miniboss", "boss"]
## Fraction of a wind-up during which the aim follows the crawler (then locks).
const TRACK_MELEE := 0.6
const TRACK_RANGED := 0.8
## twin_shot: the second shot leads the crawler's motion by this many radians.
const TWIN_LEAD := 0.25
const MIN_RECOVERY := 0.25
const AREA_MIN_WIND_UP := 0.5
const MAX_CHARGE_SPEED := 2.5 * PLAYER_SPEED
const ENRAGE_COOLDOWN := 0.8
const ENRAGE_SPEED := 1.2
const PHASE_ROAR := 1.0
const PORTAL_CENTERS := {"N": Vector2(192, 0), "S": Vector2(192, 384),
    "W": Vector2(0, 192), "E": Vector2(384, 192)}
## Cells two tiles inside each doorway; large actors path to these.
const PORTAL_APPROACH := {"N": [Vector2i(11, 2), Vector2i(12, 2)],
    "S": [Vector2i(11, 21), Vector2i(12, 21)], "W": [Vector2i(2, 11), Vector2i(2, 12)],
    "E": [Vector2i(21, 11), Vector2i(21, 12)]}
## Fixed summon points used by `at_edges` summons (the drains in the corners).
const EDGE_POINTS := [Vector2(40, 40), Vector2(344, 40), Vector2(344, 344), Vector2(40, 344)]


# --- Catalogue -----------------------------------------------------------------

static func load_catalogue(path: String = CATALOGUE_PATH) -> Dictionary:
    var config = JSON.parse_string(FileAccess.get_file_as_string(path))
    return config if config is Dictionary else {}


static func settings(catalogue: Dictionary) -> Dictionary:
    return catalogue.get("encounters", {})


static func is_boss(catalogue: Dictionary, enemy_id: String) -> bool:
    return bool(catalogue.get("enemies", {}).get(enemy_id, {}).get("boss", false))


## Design band (1..5) for a 1-based floor depth.
static func band_for_depth(catalogue: Dictionary, depth: int) -> int:
    for entry in settings(catalogue).get("depth_bands", []):
        if depth <= int(entry["max_depth"]):
            return int(entry["band"])
    return 5


static func band_rules(catalogue: Dictionary, band: int) -> Dictionary:
    return catalogue.get("bands", {}).get(str(clampi(band, 1, 5)), {})


## Resolves an enemy's `sprite` (a sprite_sheets id or a res:// path) to
## {path, frame: Vector2, render: Vector2}.
static func sheet_info(catalogue: Dictionary, sprite: String) -> Dictionary:
    var sheets: Dictionary = catalogue.get("sprite_sheets", {})
    if sheets.has(sprite):
        var entry: Dictionary = sheets[sprite]
        return {"path": String(entry["path"]),
            "frame": Vector2(float(entry["frame"][0]), float(entry["frame"][1])),
            "render": Vector2(float(entry["render"][0]), float(entry["render"][1]))}
    return {"path": sprite, "frame": Vector2(32, 32), "render": Vector2(24, 24)}


static func attack_by_id(definition: Dictionary, attack_id: String) -> Dictionary:
    for attack in definition.get("attacks", []):
        if String(attack.get("id", "")) == attack_id:
            return attack
    return {}


# --- Instances: veteran scaling and elite modifiers ------------------------------

## Builds the live enemy dictionary for `enemy_id` spawned at band `band`.
## Veteran scaling applies once per band above the archetype's `band`; an elite
## modifier id (see `elites.modifiers`) adds the elite base rules on non-bosses.
static func make_instance(catalogue: Dictionary, enemy_id: String, pos: Vector2, band: int,
        elite_id: String = "", instance_id: String = "") -> Dictionary:
    var template: Dictionary = catalogue["enemies"][enemy_id]
    var boss: bool = bool(template.get("boss", false))
    var vet: int = maxi(0, band - int(template.get("band", 1)))
    var hp: float = float(template.get("hp", 5)) * pow(1.25, vet)
    var by_band: Dictionary = template.get("hp_by_band", {})
    if by_band.has(str(band)):
        hp = float(by_band[str(band)])
    var xp: float = float(template.get("xp", 0)) * pow(1.5, vet)
    var threat: int = int(template.get("threat", 0)) + (vet if int(template.get("threat", 0)) > 0 else 0)
    var damage_mult := 1.0
    var speed: float = float(template.get("speed", 0))
    var ac: int = int(template.get("ac", 10))
    var knockback: float = float(template.get("knockback_resist", 0.0))
    var display_name: String = String(template.get("name", enemy_id))
    var tint := ""
    var shield := 0
    var shield_delay := 4.0
    var tags: Array = template.get("tags", []).duplicate()
    var modifiers: Array = []
    if elite_id != "":
        var elites: Dictionary = catalogue.get("elites", {})
        var mod: Dictionary = elites.get("modifiers", {}).get(elite_id, {})
        if not boss:
            var base: Dictionary = elites.get("base", {})
            hp *= float(base.get("hp_mult", 1.0))
            damage_mult *= float(base.get("damage_mult", 1.0))
            xp *= float(base.get("xp_mult", 1.0))
            threat *= int(base.get("threat_mult", 1))
            tags.append("elite")
        if not boss:
            hp *= float(mod.get("hp_mult", 1.0))
        speed *= float(mod.get("speed_mult", 1.0))
        damage_mult *= float(mod.get("damage_mult", 1.0))
        xp *= float(mod.get("xp_mult", 1.0))
        ac += int(mod.get("ac_add", 0))
        knockback += float(mod.get("knockback_resist_add", 0.0))
        shield = int(mod.get("shield", 0))
        shield_delay = float(mod.get("shield_regen_delay", 4.0))
        tint = String(mod.get("tint", ""))
        display_name = "%s %s" % [String(mod.get("name_prefix", elite_id.capitalize())), display_name]
        tags.append_array(mod.get("tags", []))
        modifiers.append(elite_id)
    var hp_total: int = maxi(1, int(round(hp)))
    return {
        "instance_id": instance_id, "definition": enemy_id, "name": display_name,
        "pos": pos, "spawn_pos": pos, "hp": hp_total, "max_hp": hp_total,
        "radius": float(template.get("collision_radius", 12)), "facing": 4,
        "ac": ac, "dr": int(template.get("dr", 0)), "speed": speed,
        "xp": int(round(xp)), "threat": threat, "band": band, "veteran": vet,
        "attack_bonus_add": vet, "damage_bonus_add": vet, "damage_mult": damage_mult,
        "wind_up_mult": pow(0.9, vet),
        "min_wind_up": float(band_rules(catalogue, band).get("min_wind_up", 0.35)),
        "knockback_resist": clampf(knockback, 0.0, 1.0), "tags": tags, "boss": boss,
        "elite": elite_id, "modifiers": modifiers, "tint": tint,
        "shield": shield, "shield_max": shield, "shield_regen": 0.0,
        "shield_delay": shield_delay, "ward": 0, "ward_time": 0.0, "invulnerable": 0.0,
        "state": "idle", "state_time": 0.0, "state_length": 0.0, "attack": "",
        "queued": "", "aim": Vector2.LEFT, "target_point": pos, "dash_left": 0.0,
        "dash_hit": false, "attack_cooldown": 0.0, "cooldowns": {}, "dormant": 0.0,
        "phase": 0, "volley": 0, "summoner": "", "summon_serial": 0, "rng_seed": 0,
        "repath": 0.0, "waypoints": []
    }


# --- Encounter composition (threat budgets) --------------------------------------

## round((base + per_depth × depth) × intensity × kind multiplier); boss escorts
## always use standard intensity. 0 for kinds without a multiplier.
static func threat_budget(catalogue: Dictionary, kind: String, depth: int,
        intensity: String = "standard") -> int:
    var cfg: Dictionary = settings(catalogue)
    var kinds: Dictionary = cfg.get("kind_multiplier", {})
    if not kinds.has(kind):
        return 0
    var budget: Dictionary = cfg.get("budget", {})
    var multiplier: float = 1.0
    if kind != "boss":
        multiplier = float(cfg.get("intensity", {}).get(intensity, {}).get("multiplier", 1.0))
    return int(round((float(budget.get("base", 5)) + float(budget.get("per_depth", 3)) * depth)
        * multiplier * float(kinds[kind])))


static func roll_intensity(catalogue: Dictionary, rng: RandomNumberGenerator) -> String:
    var table: Dictionary = settings(catalogue).get("intensity", {})
    var names: Array = table.keys()
    names.sort()
    var total := 0.0
    for name in names:
        total += float(table[name].get("weight", 0))
    var roll: float = rng.randf() * total
    for name in names:
        roll -= float(table[name].get("weight", 0))
        if roll < 0.0:
            return String(name)
    return "standard"


## Normal archetypes that may be drawn at `depth`: {id, role, threat, weight}.
static func eligible_pool(catalogue: Dictionary, depth: int) -> Array[Dictionary]:
    var band: int = band_for_depth(catalogue, depth)
    var pool: Array[Dictionary] = []
    var defs: Dictionary = catalogue.get("enemies", {})
    var ids: Array = defs.keys()
    ids.sort()
    for enemy_id in ids:
        var data: Dictionary = defs[enemy_id]
        if bool(data.get("boss", false)) or bool(data.get("summon_only", false)):
            continue
        if NON_POOL_ROLES.has(String(data.get("role", ""))) or float(data.get("weight", 1.0)) <= 0.0:
            continue
        if depth < int(data.get("min_depth", 1)) or depth > int(data.get("max_depth", 99)):
            continue
        pool.append({"id": String(enemy_id), "role": String(data["role"]),
            "threat": int(data["threat"]) + maxi(0, band - int(data.get("band", 1))),
            "weight": float(data.get("weight", 1.0)), "elite": ""})
    return pool


## Picks the boss for a boss room from `encounters.boss_pool`: {id, elite}.
static func pick_boss(catalogue: Dictionary, depth: int, rng: RandomNumberGenerator) -> Dictionary:
    var pool: Array = settings(catalogue).get("boss_pool", [])
    var chosen: Dictionary = pool.back() if not pool.is_empty() else {}
    for entry in pool:
        if depth >= int(entry["min_depth"]) and depth <= int(entry["max_depth"]):
            chosen = entry
            break
    var options: Array = chosen.get("options", [])
    if options.is_empty():
        return {}
    var option: Dictionary = options[rng.randi_range(0, options.size() - 1)]
    return {"id": String(option["id"]), "elite": String(option.get("elite", "")),
        "role": "boss", "threat": 0, "boss": true}


## Chooses the enemies for a room (ENCOUNTER_RULES §4.1) and returns
## {kind, depth, band, intensity, budget, spent, elite_room, picks: [{id, role,
## threat, elite, boss}]}. The boss (if any) is picks[0] and is not budgeted.
static func compose_encounter(catalogue: Dictionary, kind: String, depth: int,
        rng: RandomNumberGenerator) -> Dictionary:
    var cfg: Dictionary = settings(catalogue)
    var band: int = band_for_depth(catalogue, depth)
    var plan := {"kind": kind, "depth": depth, "band": band, "intensity": "standard",
        "budget": 0, "spent": 0, "picks": []}
    if not cfg.get("kind_multiplier", {}).has(kind):
        return plan
    var picks: Array[Dictionary] = []
    if kind == "boss":
        var boss: Dictionary = pick_boss(catalogue, depth, rng)
        if not boss.is_empty():
            picks.append(boss)
    else:
        plan["intensity"] = roll_intensity(catalogue, rng)
    var budget: int = threat_budget(catalogue, kind, depth, String(plan["intensity"]))
    plan["budget"] = budget
    var tolerance: float = float(cfg.get("budget", {}).get("tolerance", 0.1))
    var low: int = int(ceilf(float(budget) * (1.0 - tolerance) - 0.0001))
    var high: int = int(floorf(float(budget) * (1.0 + tolerance) + 0.0001))
    var max_count: int = int(cfg.get("max_enemies", {}).get(str(band), 4))
    var min_count: int = int(cfg.get("min_enemies", {}).get(kind, 2))
    var pool: Array[Dictionary] = eligible_pool(catalogue, depth)
    var wants_elite: bool = kind == "elite"
    if kind == "normal":
        var chance: float = float(cfg.get("elite_chance", {}).get(str(band), 0.0))
        wants_elite = chance > 0.0 and rng.randf() < chance
    var pressure: Array = cfg.get("pressure_roles", {}).get(str(band), ["chaser"])
    # Draw complete fills until one lands inside the tolerance window; keep the
    # closest. Every draw consumes the same rng, so the result is deterministic.
    var best: Array[Dictionary] = []
    var best_spent := -1
    for _attempt in range(int(cfg.get("budget", {}).get("attempts", 12))):
        var trial: Array[Dictionary] = picks.duplicate()
        var got: int = _fill(catalogue, pool, trial, band, kind, budget, low, high, max_count,
            wants_elite, pressure, rng)
        if best_spent < 0 or absi(got - budget) < absi(best_spent - budget):
            best = trial
            best_spent = got
        if got >= low and got <= high:
            break
    picks = best
    var spent: int = maxi(0, best_spent)
    var count := 0
    for pick in picks:
        if not bool(pick.get("boss", false)):
            count += 1
    # Rule 5: never fewer than the minimum; the cheapest chaser may overspend by 2.
    while count < min_count:
        var cheapest: Dictionary = {}
        for entry in pool:
            if String(entry["role"]) == "chaser" and _rule_allows(catalogue, entry, picks, band, kind) \
                    and (cheapest.is_empty() or int(entry["threat"]) < int(cheapest["threat"])):
                cheapest = entry
        if cheapest.is_empty() or spent + int(cheapest["threat"]) > budget + 2:
            break
        picks.append(cheapest)
        spent += int(cheapest["threat"])
        count += 1
    plan["picks"] = picks
    plan["spent"] = spent
    return plan


## One weighted fill (§4.1 step 4): an optional elite first, then a pressure
## role (chaser in band I, chaser or charger later), then any allowed archetype
## whose threat still fits under `high`, until the budget or count cap is met.
## Appends to `picks` and returns the threat spent.
static func _fill(catalogue: Dictionary, pool: Array[Dictionary], picks: Array[Dictionary],
        band: int, kind: String, budget: int, low: int, high: int, max_count: int, wants_elite: bool,
        pressure: Array, rng: RandomNumberGenerator) -> int:
    var elite_mult: int = int(catalogue.get("elites", {}).get("base", {}).get("threat_mult", 2))
    var elite_pending: bool = wants_elite
    var need_pressure: bool = kind != "boss"
    var spent := 0
    var count := 0
    for _guard in range(32):
        if count >= max_count or spent >= budget:
            break
        var candidates: Array[Dictionary] = []
        var top := 0
        for entry in pool:
            if _rule_allows(catalogue, entry, picks, band, kind):
                top = maxi(top, int(entry["threat"]))
        for entry in pool:
            if not _rule_allows(catalogue, entry, picks, band, kind):
                continue
            var option: Dictionary = entry
            if elite_pending:
                option = entry.duplicate()
                option["elite"] = "pending"
                option["threat"] = int(entry["threat"]) * elite_mult
            elif need_pressure and not pressure.has(String(entry["role"])):
                continue
            if spent + int(option["threat"]) <= high:
                candidates.append(option)
        # Upper-bound lookahead: prefer picks after which the remaining slots
        # can still reach the low end of the window.
        var reachable: Array[Dictionary] = []
        for option in candidates:
            if spent + int(option["threat"]) + (max_count - count - 1) * top >= low:
                reachable.append(option)
        if not reachable.is_empty():
            candidates = reachable
        if candidates.is_empty():
            if elite_pending:
                elite_pending = false
                continue
            if need_pressure:
                need_pressure = false
                continue
            break
        var choice: Dictionary = _weighted(candidates, rng).duplicate()
        if String(choice["elite"]) == "pending":
            choice["elite"] = _pick_modifier(catalogue, rng)
        picks.append(choice)
        spent += int(choice["threat"])
        count += 1
        if pressure.has(String(choice["role"])):
            need_pressure = false
        elite_pending = false
    return spent


static func _pick_modifier(catalogue: Dictionary, rng: RandomNumberGenerator) -> String:
    var names: Array = catalogue.get("elites", {}).get("modifiers", {}).keys()
    names.sort()
    if names.is_empty():
        return ""
    return String(names[rng.randi_range(0, names.size() - 1)])


## R3 role caps, R6 support company, R10 repetition, R12 escort exclusions.
static func _rule_allows(catalogue: Dictionary, entry: Dictionary, picks: Array, band: int,
        kind: String) -> bool:
    var cfg: Dictionary = settings(catalogue)
    var role: String = String(entry["role"])
    var same_id := 0
    var same_role := 0
    var others := 0
    for pick in picks:
        if bool(pick.get("boss", false)):
            continue
        if String(pick["id"]) == String(entry["id"]):
            same_id += 1
        if String(pick["role"]) == role:
            same_role += 1
        if String(pick["role"]) != "support":
            others += 1
    if same_id >= int(cfg.get("repeat_cap", 3)):
        return false
    var caps: Dictionary = cfg.get("role_caps", {}).get(str(band), {})
    if caps.has(role) and same_role >= int(caps[role]):
        return false
    if role == "support" and others < int(cfg.get("support_min_company", 2)):
        return false
    if kind == "boss" and cfg.get("escort_excluded_roles", {}).get(str(band), []).has(role):
        return false
    return true


static func _weighted(options: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
    var total := 0.0
    for option in options:
        total += float(option.get("weight", 1.0))
    var roll: float = rng.randf() * total
    for option in options:
        roll -= float(option.get("weight", 1.0))
        if roll < 0.0:
            return option
    return options.back()


# --- Spawn placement ---------------------------------------------------------------

## Generates the persisted enemy list for a room. Same (seed, room_id, depth,
## blocked, links) -> same enemies. `links` is the room's neighbour map (portal
## distances and reachability use it); without links the room midpoint is used.
static func generate_encounter(catalogue: Dictionary, kind: String, seed_value: int,
        room_id: int, blocked: Dictionary, depth: int = 1, links: Dictionary = {}) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    var rng := RandomNumberGenerator.new()
    rng.seed = int(seed_value) * 73 + int(room_id) * 10211 + 41
    var plan: Dictionary = compose_encounter(catalogue, kind, depth, rng)
    var cfg: Dictionary = settings(catalogue)
    var first: Array = cfg.get("first_cooldown", [0.4, 1.0])
    var floods: Dictionary = {}
    var boss_pos := Vector2.INF
    for pick in plan["picks"]:
        var enemy_id: String = String(pick["id"])
        if not catalogue.get("enemies", {}).has(enemy_id):
            push_warning("Unknown enemy definition: " + enemy_id)
            continue
        var template: Dictionary = catalogue["enemies"][enemy_id]
        var radius: float = float(template.get("collision_radius", 12))
        var position := Vector2.INF
        if bool(pick.get("boss", false)):
            position = _boss_spot(radius, blocked)
            boss_pos = position
        else:
            position = _find_spawn(catalogue, rng, template, radius, blocked, links, results,
                boss_pos, floods)
        if position == Vector2.INF:
            push_warning("Could not place enemy " + enemy_id + " without blocking room")
            continue
        var foe: Dictionary = make_instance(catalogue, enemy_id, position, int(plan["band"]),
            String(pick.get("elite", "")), "%d_%d" % [room_id, results.size()])
        foe["attack_cooldown"] = rng.randf_range(float(first[0]), float(first[1]))
        foe["rng_seed"] = rng.randi()
        results.append(foe)
    return results


## Minimum portal distance for a template (ranged roles keep further back).
static func portal_distance(catalogue: Dictionary, template: Dictionary) -> float:
    var spawn: Dictionary = settings(catalogue).get("spawn", {})
    if String(template.get("role", "")) == "ranged":
        return float(spawn.get("ranged_portal_distance", 120))
    return float(spawn.get("portal_distance", 96))


## True when an actor of `radius` standing in `cell` fits (clearance for large radii).
static func passable(cell: Vector2i, radius: float, blocked: Dictionary) -> bool:
    if not Room.is_walkable(cell, blocked):
        return false
    return radius < 8.0 or Room.can_occupy(Room.cell_center(cell), radius, blocked)


## Cells reachable from `sources` by an actor of `radius` (4-neighbour flood).
static func flood(blocked: Dictionary, sources: Array, radius: float) -> Dictionary:
    var seen: Dictionary = {}
    var queue: Array[Vector2i] = []
    for source in sources:
        if passable(source, radius, blocked) and not seen.has(source):
            seen[source] = true
            queue.append(source)
    var index := 0
    while index < queue.size():
        var cell: Vector2i = queue[index]
        index += 1
        for direction in Room.DIRECTIONS:
            var next: Vector2i = cell + direction
            if not seen.has(next) and passable(next, radius, blocked):
                seen[next] = true
                queue.append(next)
    return seen


## Portal cells a radius class paths to: the doorway cells, or for large actors
## the cells two tiles inside (their bodies cannot touch the wall).
static func portal_targets(direction: String, radius: float) -> Array:
    if radius < 8.0:
        return Room.portal_cells(direction)
    return PORTAL_APPROACH.get(direction, [])


static func _find_spawn(catalogue: Dictionary, rng: RandomNumberGenerator, template: Dictionary,
        radius: float, blocked: Dictionary, links: Dictionary, placed: Array,
        boss_pos: Vector2, floods: Dictionary) -> Vector2:
    var spawn: Dictionary = settings(catalogue).get("spawn", {})
    var keep_out: float = portal_distance(catalogue, template)
    var gap: float = float(spawn.get("gap", 11))
    var boss_gap: float = float(spawn.get("escort_boss_gap", 48))
    var attempts: int = int(spawn.get("attempts", 150))
    for attempt in range(attempts * 2):
        # Second pass: large actors may spawn where only the plain grid reaches
        # the portals (they path with clearance where possible, else slide).
        var strict: bool = attempt < attempts
        var cell := Vector2i(rng.randi_range(2, 21), rng.randi_range(2, 21))
        var point: Vector2 = Room.cell_center(cell)
        if not Room.is_walkable(cell, blocked) or not Room.can_occupy(point, radius, blocked):
            continue
        if links.is_empty():
            if point.distance_to(MID) < float(spawn.get("fallback_center_distance", 82)):
                continue
        elif not _clear_of_portals(point, links, keep_out):
            continue
        if boss_pos != Vector2.INF and point.distance_to(boss_pos) < boss_gap:
            continue
        var collides := false
        for other in placed:
            if point.distance_to(Vector2(other["pos"])) < radius + float(other["radius"]) + gap:
                collides = true
                break
        if collides or not _reachable_everywhere(cell, radius if strict else 0.0, blocked,
                links, floods):
            continue
        return point
    return Vector2.INF


static func _clear_of_portals(point: Vector2, links: Dictionary, distance: float) -> bool:
    for direction in links.keys():
        if PORTAL_CENTERS.has(String(direction)) and \
                point.distance_to(PORTAL_CENTERS[String(direction)]) < distance:
            return false
    return true


static func _reachable_everywhere(cell: Vector2i, radius: float, blocked: Dictionary,
        links: Dictionary, floods: Dictionary) -> bool:
    var directions: Array = links.keys() if not links.is_empty() else ["_mid"]
    for direction in directions:
        var key := "%s:%d" % [String(direction), 1 if radius >= 8.0 else 0]
        if not floods.has(key):
            var sources: Array = [Vector2i(12, 12)] if String(direction) == "_mid" \
                else portal_targets(String(direction), radius)
            floods[key] = flood(blocked, sources, radius)
        if not floods[key].has(cell):
            return false
    return true


static func _boss_spot(radius: float, blocked: Dictionary) -> Vector2:
    if Room.can_occupy(MID, radius, blocked):
        return MID
    for ring in range(1, 8):
        for y in range(12 - ring, 12 + ring + 1):
            for x in range(12 - ring, 12 + ring + 1):
                var point: Vector2 = Room.cell_center(Vector2i(x, y))
                if Room.can_occupy(point, radius, blocked):
                    return point
    return MID


# --- AI state machine ----------------------------------------------------------------

## Resets an enemy for a room entry: back to its spawn point, idle, dormant.
static func on_room_entered(foe: Dictionary, dormancy: float) -> void:
    foe["pos"] = foe.get("spawn_pos", foe["pos"])
    foe["state"] = "idle"
    foe["state_time"] = 0.0
    foe["attack"] = ""
    foe["queued"] = ""
    foe["dash_left"] = 0.0
    foe["waypoints"] = []
    foe["repath"] = 0.0
    foe["dormant"] = dormancy


## Advances `foe` by `delta` seconds and returns the actions Combat resolves.
## `world`: player_pos (Vector2), player_velocity (Vector2), blocked (Dictionary),
## allies (Array of live enemy dictionaries, including `foe`).
## Action shapes (every action has "type"):
##   strike      {attack, hit: bool, direction: Vector2} melee/area/dash contact
##   projectiles {attack, directions: Array[Vector2], origin: Vector2}
##   hazard      {attack, pos: Vector2, radius: float}
##   summon      {attack}
##   support     {attack}
##   wall_stun   {} (a dash ended in an obstacle)
static func step(foe: Dictionary, definition: Dictionary, delta: float,
        world: Dictionary) -> Array[Dictionary]:
    var actions: Array[Dictionary] = []
    _tick_timers(foe, delta)
    if float(foe.get("dormant", 0.0)) > 0.0:
        foe["dormant"] = maxf(0.0, float(foe["dormant"]) - delta)
        return actions
    var player_pos: Vector2 = world["player_pos"]
    var blocked: Dictionary = world.get("blocked", {})
    match String(foe.get("state", "idle")):
        "stunned", "recovery":
            foe["state_time"] = float(foe["state_time"]) + delta
            if float(foe["state_time"]) >= float(foe["state_length"]):
                var queued: String = String(foe.get("queued", ""))
                foe["queued"] = ""
                _set_state(foe, "idle", 0.0)
                var follow: Dictionary = attack_by_id(definition, queued)
                if not follow.is_empty():
                    begin_wind_up(foe, definition, follow, player_pos)
        "winding_up":
            _update_wind_up(foe, definition, delta, world, actions)
        "dashing":
            _update_dash(foe, definition, delta, world, actions)
        _:
            advance(foe, definition, delta, player_pos, blocked, world)
            foe["attack_cooldown"] = maxf(0.0, float(foe.get("attack_cooldown", 0.0)) - delta)
            if float(foe["attack_cooldown"]) <= 0.0:
                var attack: Dictionary = choose_attack(foe, definition, world)
                if not attack.is_empty():
                    begin_wind_up(foe, definition, attack, player_pos)
    return actions


static func _tick_timers(foe: Dictionary, delta: float) -> void:
    var cooldowns: Dictionary = foe.get("cooldowns", {})
    for key in cooldowns.keys():
        cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
    foe["invulnerable"] = maxf(0.0, float(foe.get("invulnerable", 0.0)) - delta)
    if float(foe.get("ward_time", 0.0)) > 0.0:
        foe["ward_time"] = maxf(0.0, float(foe["ward_time"]) - delta)
        if float(foe["ward_time"]) <= 0.0:
            foe["ward"] = 0
    if int(foe.get("shield_max", 0)) > 0:
        foe["shield_regen"] = float(foe.get("shield_regen", 0.0)) + delta
        if float(foe["shield_regen"]) >= float(foe.get("shield_delay", 4.0)) and \
                int(foe.get("shield", 0)) < int(foe["shield_max"]):
            foe["shield"] = int(foe["shield_max"])


static func _set_state(foe: Dictionary, state: String, length: float) -> void:
    foe["state"] = state
    foe["state_time"] = 0.0
    foe["state_length"] = length


## Attack ids usable now: the current phase's list for bosses, else every attack.
static func active_attack_ids(foe: Dictionary, definition: Dictionary) -> Array:
    var phases: Array = definition.get("phases", [])
    if not phases.is_empty():
        return phases[clampi(int(foe.get("phase", 0)), 0, phases.size() - 1)].get("attacks", [])
    var ids: Array = []
    for attack in definition.get("attacks", []):
        ids.append(String(attack["id"]))
    return ids


## The first ready attack whose range, line-of-sight and target conditions hold.
static func choose_attack(foe: Dictionary, definition: Dictionary, world: Dictionary) -> Dictionary:
    var cooldowns: Dictionary = foe.get("cooldowns", {})
    for attack_id in active_attack_ids(foe, definition):
        var attack: Dictionary = attack_by_id(definition, String(attack_id))
        if attack.is_empty() or bool(attack.get("follow_up_only", false)):
            continue
        if float(cooldowns.get(String(attack_id), 0.0)) > 0.0:
            continue
        if attack_ready(foe, definition, attack, world):
            return attack
    return {}


static func attack_ready(foe: Dictionary, definition: Dictionary, attack: Dictionary,
        world: Dictionary) -> bool:
    var position: Vector2 = foe["pos"]
    var player_pos: Vector2 = world["player_pos"]
    var distance: float = position.distance_to(player_pos)
    if distance > float(definition.get("behavior", {}).get("detection_range", 1000.0)):
        return false
    if distance > float(attack.get("range", 22.5)) or distance < float(attack.get("min_range", 0.0)):
        return false
    var kind: String = String(attack.get("type", "melee"))
    var needs_los: bool = bool(attack.get("requires_los", true))
    if needs_los and not has_line_of_sight(position, player_pos, world.get("blocked", {})):
        return false
    var allies: Array = world.get("allies", [])
    if kind == "summon":
        var summon: Dictionary = attack.get("summon", {})
        return count_summons(allies, String(foe["instance_id"])) < int(summon.get("cap", 4))
    if kind == "support":
        var effect: String = String(attack.get("effect", "shield"))
        for ally in allies:
            if is_same(ally, foe) or int(ally["hp"]) <= 0:
                continue
            if position.distance_to(Vector2(ally["pos"])) > float(attack.get("aoe_radius", 80)):
                continue
            if effect == "heal" and int(ally["hp"]) < int(ally["max_hp"]):
                return true
            if effect == "shield" and int(ally.get("ward", 0)) <= 0:
                return true
        return false
    return true


static func count_summons(allies: Array, summoner_id: String) -> int:
    var total := 0
    for ally in allies:
        if String(ally.get("summoner", "")) == summoner_id and int(ally["hp"]) > 0:
            total += 1
    return total


## Effective wind-up: veteran-scaled, never below the band minimum, and at least
## 0.5 s for area (circle) telegraphs and boss attacks.
static func wind_up_of(foe: Dictionary, attack: Dictionary) -> float:
    var value: float = maxf(float(attack.get("wind_up", 0.35)) * float(foe.get("wind_up_mult", 1.0)),
        float(foe.get("min_wind_up", 0.0)))
    if bool(foe.get("boss", false)) or String(attack.get("telegraph", "")) == "circle":
        value = maxf(value, AREA_MIN_WIND_UP)
    return value


static func begin_wind_up(foe: Dictionary, _definition: Dictionary, attack: Dictionary,
        player_pos: Vector2) -> void:
    _set_state(foe, "winding_up", wind_up_of(foe, attack))
    foe["attack"] = String(attack["id"])
    _track(foe, attack, player_pos)


static func _track(foe: Dictionary, attack: Dictionary, player_pos: Vector2) -> void:
    var position: Vector2 = foe["pos"]
    var toward: Vector2 = player_pos - position
    if toward.length_squared() > 0.0001:
        foe["aim"] = toward.normalized()
        foe["facing"] = facing_of(foe["aim"])
    foe["target_point"] = player_pos if String(attack.get("target", "player")) == "player" \
        else position


static func _update_wind_up(foe: Dictionary, definition: Dictionary, delta: float,
        world: Dictionary, actions: Array[Dictionary]) -> void:
    var attack: Dictionary = attack_by_id(definition, String(foe["attack"]))
    if attack.is_empty():
        _set_state(foe, "idle", 0.0)
        return
    foe["state_time"] = float(foe["state_time"]) + delta
    var lock: float = TRACK_RANGED if String(attack["type"]) == "ranged" else TRACK_MELEE
    if float(foe["state_time"]) <= float(foe["state_length"]) * lock:
        _track(foe, attack, world["player_pos"])
    if float(foe["state_time"]) >= float(foe["state_length"]):
        _resolve(foe, definition, attack, world, actions)


static func _resolve(foe: Dictionary, definition: Dictionary, attack: Dictionary,
        world: Dictionary, actions: Array[Dictionary]) -> void:
    var player_pos: Vector2 = world["player_pos"]
    var position: Vector2 = foe["pos"]
    var kind: String = String(attack["type"])
    foe["cooldowns"][String(attack["id"])] = float(attack.get("cooldown", 1.0)) \
        * cooldown_mult(foe, definition)
    match kind:
        "melee":
            actions.append({"type": "strike", "attack": attack, "direction": foe["aim"],
                "hit": melee_hits(foe, attack, player_pos, PLAYER_RADIUS)})
        "area":
            var center: Vector2 = foe["target_point"]
            actions.append({"type": "strike", "attack": attack,
                "direction": (player_pos - center).normalized(),
                "hit": center.distance_to(player_pos) <= float(attack.get("aoe_radius", 24)) + PLAYER_RADIUS})
        "ranged":
            actions.append({"type": "projectiles", "attack": attack,
                "directions": volley_directions(foe, definition, attack,
                    world.get("player_velocity", Vector2.ZERO)),
                "origin": position})
            foe["volley"] = int(foe.get("volley", 0)) + 1
        "dash":
            _set_state(foe, "dashing", 0.0)
            foe["dash_left"] = float(attack.get("dash_distance", 64))
            foe["dash_hit"] = false
            return
        "puddle":
            actions.append({"type": "hazard", "attack": attack, "pos": foe["target_point"],
                "radius": float(attack.get("aoe_radius", 24))})
        "summon":
            actions.append({"type": "summon", "attack": attack})
        "support":
            actions.append({"type": "support", "attack": attack})
    _finish_attack(foe, attack)


static func _finish_attack(foe: Dictionary, attack: Dictionary) -> void:
    foe["queued"] = String(attack.get("then", ""))
    var recovery: float = float(attack.get("recovery", MIN_RECOVERY))
    _set_state(foe, "recovery", recovery)


static func _update_dash(foe: Dictionary, definition: Dictionary, delta: float,
        world: Dictionary, actions: Array[Dictionary]) -> void:
    var attack: Dictionary = attack_by_id(definition, String(foe["attack"]))
    var blocked: Dictionary = world.get("blocked", {})
    var direction: Vector2 = foe["aim"]
    var travel: float = minf(float(attack.get("dash_speed", 150)) * delta, float(foe["dash_left"]))
    var next: Vector2 = Vector2(foe["pos"]) + direction * travel
    if not Room.can_occupy(next, float(foe["radius"]), blocked):
        foe["dash_left"] = 0.0
        var stun: float = float(attack.get("stun_on_wall", 0.0))
        if stun > 0.0:
            _set_state(foe, "stunned", stun)
            actions.append({"type": "wall_stun", "attack": attack})
        else:
            _finish_attack(foe, attack)
        return
    foe["pos"] = next
    foe["dash_left"] = float(foe["dash_left"]) - travel
    var player_pos: Vector2 = world["player_pos"]
    if not bool(foe["dash_hit"]) and next.distance_to(player_pos) <= \
            float(foe["radius"]) + PLAYER_RADIUS + 2.0:
        foe["dash_hit"] = true
        actions.append({"type": "strike", "attack": attack, "direction": direction, "hit": true})
    if float(foe["dash_left"]) <= 0.0:
        _finish_attack(foe, attack)


static func cooldown_mult(foe: Dictionary, definition: Dictionary) -> float:
    return ENRAGE_COOLDOWN if is_enraged(foe, definition) else 1.0


static func is_enraged(foe: Dictionary, definition: Dictionary) -> bool:
    return "enrage" in definition.get("abilities", []) and float(foe["hp"]) <= \
        float(foe["max_hp"]) * float(definition.get("enrage_below", 0.3))


## True if `target` (radius `target_radius`) is inside a melee attack's reach and
## arc around the enemy's locked aim at this moment.
static func melee_hits(foe: Dictionary, attack: Dictionary, target: Vector2,
        target_radius: float) -> bool:
    var toward: Vector2 = target - Vector2(foe["pos"])
    var distance: float = toward.length()
    if distance > float(attack.get("range", 22.5)) + target_radius:
        return false
    if String(attack.get("telegraph", "arc")) == "circle" or distance < 0.01:
        return true
    var half: float = deg_to_rad(float(attack.get("arc", 120.0))) * 0.5
    var slack: float = atan2(target_radius, distance)
    return absf(Vector2(foe["aim"]).angle_to(toward)) <= half + slack


## Shot directions for a ranged attack, fanned over `spread` degrees. With
## twin_shot a single shot becomes two: one along the locked aim and one leading
## the crawler's sideways motion by TWIN_LEAD (alternating sides when still).
static func volley_directions(foe: Dictionary, definition: Dictionary, attack: Dictionary,
        player_velocity: Vector2) -> Array[Vector2]:
    var aim: Vector2 = foe["aim"]
    var directions: Array[Vector2] = []
    var count: int = maxi(1, int(attack.get("count", 1)))
    if count == 1 and "twin_shot" in definition.get("abilities", []):
        var lateral: float = player_velocity.dot(aim.rotated(PI * 0.5))
        var side: float = signf(lateral)
        if absf(lateral) < 5.0:
            side = 1.0 if int(foe.get("volley", 0)) % 2 == 0 else -1.0
        directions.append(aim)
        directions.append(aim.rotated(TWIN_LEAD * side))
        return directions
    var spread: float = deg_to_rad(float(attack.get("spread", 0.0)))
    for i in range(count):
        var t: float = 0.0 if count == 1 else float(i) / float(count - 1) - 0.5
        directions.append(aim.rotated(spread * t))
    return directions


## {to_hit, die, bonus, mult} for an attack, including veteran and elite scaling.
static func attack_numbers(foe: Dictionary, definition: Dictionary, attack: Dictionary) -> Dictionary:
    var ability: String = String(attack.get("ability", "STR"))
    var scores: Dictionary = definition.get("scores", {})
    return {
        "to_hit": RPG.attack_bonus(scores, ability, int(definition.get("level", 1)),
            bool(attack.get("proficient", true))) + int(foe.get("attack_bonus_add", 0)),
        "die": int(attack.get("damage_die", 0)),
        "bonus": RPG.modifier(int(scores.get(ability, 10))) + int(attack.get("damage_bonus", 0))
            + int(foe.get("damage_bonus_add", 0)),
        "mult": float(foe.get("damage_mult", 1.0))
    }


## Highest non-critical damage of one hit at the archetype's base band.
static func max_hit(definition: Dictionary, attack: Dictionary) -> int:
    var ability: String = String(attack.get("ability", "STR"))
    var modifier: int = RPG.modifier(int(definition.get("scores", {}).get(ability, 10)))
    if attack.has("damage_die"):
        return int(attack["damage_die"]) + modifier + int(attack.get("damage_bonus", 0))
    return int(attack.get("hazard", {}).get("damage", 0))


# --- Phases ---------------------------------------------------------------------------

## Index of the phase for this HP: the last phase whose `below` the HP fraction
## is under (phase 0 has below 1.0 and always applies).
static func phase_index(definition: Dictionary, hp: int, max_hp: int) -> int:
    var phases: Array = definition.get("phases", [])
    var fraction: float = float(hp) / float(maxi(1, max_hp))
    var index := 0
    for i in range(1, phases.size()):
        if fraction < float(phases[i].get("below", 0.0)):
            index = i
    return index


## Switches to phase `index`: PHASE_ROAR seconds of invulnerability, the current
## attack is cancelled and the next attack waits for the roar to end.
static func enter_phase(foe: Dictionary, index: int) -> void:
    foe["phase"] = index
    foe["invulnerable"] = PHASE_ROAR
    foe["attack"] = ""
    foe["queued"] = ""
    foe["dash_left"] = 0.0
    _set_state(foe, "idle", 0.0)
    foe["attack_cooldown"] = PHASE_ROAR


# --- Defence -------------------------------------------------------------------------

## Damage after resistances (by context.damage_type), the front guard (by
## context.slot and context.direction) and flat DR (never below 1). Returns 0 when
## a resistance is 0 (immune). Shields are absorbed by Combat afterwards.
static func mitigate(foe: Dictionary, definition: Dictionary, amount: int,
        context: Dictionary) -> int:
    var value: float = float(amount)
    var resist: Dictionary = definition.get("resistances", {})
    var damage_type: String = String(context.get("damage_type", "physical"))
    if resist.has(damage_type):
        value *= float(resist[damage_type])
        if value <= 0.0:
            return 0
    var guard: Dictionary = definition.get("front_guard", {})
    if not guard.is_empty() and String(context.get("slot", "")) == String(guard.get("slot", "ranged")):
        var incoming: Vector2 = context.get("direction", Vector2.ZERO)
        if incoming.length_squared() > 0.0001:
            var facing: Vector2 = Vector2.RIGHT.rotated(float(int(foe.get("facing", 0))) * PI / 4.0)
            if absf(facing.angle_to(-incoming)) <= deg_to_rad(float(guard.get("arc", 120))) * 0.5:
                value *= float(guard.get("multiplier", 0.5))
    var reduced: int = int(floorf(value)) - int(foe.get("dr", 0))
    return maxi(1, reduced)


## Moves `point` (an actor of `radius`) along `direction` up to `distance`,
## stopping before obstacles and walls. Returns the new position.
static func push(point: Vector2, direction: Vector2, distance: float, radius: float,
        blocked: Dictionary) -> Vector2:
    if distance <= 0.0 or direction.length_squared() < 0.0001:
        return point
    var unit: Vector2 = direction.normalized()
    var steps: int = maxi(1, int(ceilf(distance / 2.0)))
    var moved: Vector2 = point
    for i in range(steps):
        var trial: Vector2 = moved + unit * (distance / float(steps))
        if not Room.can_occupy(trial, radius, blocked):
            break
        moved = trial
    return moved


## Knocks an enemy back by `distance` × (1 − knockback_resist) and interrupts an
## interruptible wind-up. Returns the distance actually moved. For batch-2 weapon
## and skill knockback.
static func apply_knockback(foe: Dictionary, direction: Vector2, distance: float,
        blocked: Dictionary, definition: Dictionary = {}) -> float:
    var effective: float = distance * (1.0 - clampf(float(foe.get("knockback_resist", 0.0)), 0.0, 1.0))
    if effective <= 0.0:
        return 0.0
    var start: Vector2 = foe["pos"]
    foe["pos"] = push(start, direction, effective, float(foe["radius"]), blocked)
    foe["waypoints"] = []
    if String(foe.get("state", "")) == "winding_up" and not definition.is_empty():
        if bool(attack_by_id(definition, String(foe["attack"])).get("interruptible", false)):
            _set_state(foe, "recovery", MIN_RECOVERY)
    return start.distance_to(foe["pos"])


# --- Movement --------------------------------------------------------------------------

static func facing_of(direction: Vector2) -> int:
    return posmod(int(round(direction.angle() / (PI / 4.0))), 8)


static func move_speed(foe: Dictionary, definition: Dictionary) -> float:
    var speed: float = float(foe.get("speed", definition.get("speed", 55.0)))
    return speed * (ENRAGE_SPEED if is_enraged(foe, definition) else 1.0)


## Movement for the idle state, by behaviour mode. Pure: only `enemy` changes.
static func advance(enemy: Dictionary, definition: Dictionary, delta: float,
        player_pos: Vector2, blocked: Dictionary, world: Dictionary = {}) -> void:
    var behavior: Dictionary = definition.get("behavior", {})
    var mode: String = String(behavior.get("mode", "chase"))
    var position: Vector2 = enemy["pos"]
    var to_player: Vector2 = player_pos - position
    var distance: float = to_player.length()
    if distance < 0.01 or distance > float(behavior.get("detection_range", 1000.0)):
        return
    var preferred: float = float(behavior.get("preferred_distance", 28.0))
    var navigation: String = String(behavior.get("pathfinding", "grid_bfs"))
    var speed: float = move_speed(enemy, definition)
    if navigation == "stationary" or mode == "zone" or speed <= 0.0:
        enemy["facing"] = facing_of(to_player)
        return
    if mode == "guard" and distance > preferred * 4.0:
        return
    var target: Vector2 = player_pos
    match mode:
        "kite", "summon", "charge":
            if distance >= preferred and distance <= preferred * 1.30:
                enemy["facing"] = facing_of(to_player)
                return
            if distance < preferred:
                target = _flee_point(position, to_player)
        "support":
            if distance < preferred:
                target = _flee_point(position, to_player)
            else:
                var center: Vector2 = _ally_center(enemy, world.get("allies", []),
                    float(behavior.get("ally_radius", 80)) * 2.5)
                if center == Vector2.INF or position.distance_to(center) < 36.0:
                    enemy["facing"] = facing_of(to_player)
                    return
                target = center
        _:
            if distance < preferred:
                enemy["facing"] = facing_of(to_player)
                return
    if "lunge" in definition.get("abilities", []) and distance < 72.0:
        speed *= 1.35
    if navigation == "direct":
        _step_toward(enemy, target, speed * delta, blocked)
        return
    var radius: float = float(enemy["radius"])
    enemy["repath"] = float(enemy.get("repath", 0.0)) - delta
    var waypoints: Array = enemy.get("waypoints", [])
    if float(enemy["repath"]) <= 0.0 or waypoints.is_empty():
        enemy["repath"] = float(behavior.get("repath_seconds", 0.35))
        waypoints = []
        for cell in find_path_for(blocked, Room.cell_of(position), Room.cell_of(target), radius):
            waypoints.append(Room.cell_center(cell))
        enemy["waypoints"] = waypoints
    if waypoints.is_empty():
        _step_toward(enemy, target, speed * delta, blocked)
        return
    if position.distance_to(Vector2(waypoints[0])) < 3.5:
        waypoints.remove_at(0)
    if waypoints.is_empty():
        return
    _step_toward(enemy, Vector2(waypoints[0]), speed * delta, blocked)


static func _flee_point(position: Vector2, to_player: Vector2) -> Vector2:
    var target: Vector2 = position - to_player.normalized() * 70.0
    target.x = clampf(target.x, 9.0, Room.SIZE * Room.TILE - 9.0)
    target.y = clampf(target.y, 9.0, Room.SIZE * Room.TILE - 9.0)
    return target


static func _ally_center(enemy: Dictionary, allies: Array, radius: float) -> Vector2:
    var total := Vector2.ZERO
    var count := 0
    for ally in allies:
        if is_same(ally, enemy) or int(ally["hp"]) <= 0:
            continue
        if Vector2(ally["pos"]).distance_to(enemy["pos"]) <= radius:
            total += Vector2(ally["pos"])
            count += 1
    return total / float(count) if count > 0 else Vector2.INF


## Moves toward `target` by up to `travel`, sliding along an axis when blocked.
static func _step_toward(enemy: Dictionary, target: Vector2, travel: float,
        blocked: Dictionary) -> void:
    var position: Vector2 = enemy["pos"]
    var movement: Vector2 = target - position
    if movement.length_squared() < 0.01:
        return
    var radius: float = float(enemy["radius"])
    var change: Vector2 = movement.normalized() * minf(travel, movement.length())
    for trial in [position + change, position + Vector2(change.x, 0.0),
            position + Vector2(0.0, change.y)]:
        if Vector2(trial) != position and Room.can_occupy(trial, radius, blocked):
            enemy["pos"] = trial
            enemy["facing"] = facing_of(movement)
            return


## BFS over cells an actor of `radius` fits in; falls back to the plain grid.
static func find_path_for(blocked: Dictionary, start: Vector2i, goal: Vector2i,
        radius: float) -> Array[Vector2i]:
    if radius >= 8.0 and passable(start, radius, blocked) and passable(goal, radius, blocked):
        var parents: Dictionary = {start: start}
        var queue: Array[Vector2i] = [start]
        var index := 0
        while index < queue.size():
            var cell: Vector2i = queue[index]
            index += 1
            if cell == goal:
                var path: Array[Vector2i] = []
                var current: Vector2i = goal
                while current != start:
                    path.push_front(current)
                    current = parents[current]
                path.push_front(start)
                return path
            for direction in Room.DIRECTIONS:
                var next: Vector2i = cell + direction
                if not parents.has(next) and passable(next, radius, blocked):
                    parents[next] = cell
                    queue.append(next)
    return Room.find_path(blocked, start, goal)


static func has_line_of_sight(from_pos: Vector2, to_pos: Vector2, blocked: Dictionary) -> bool:
    var displacement: Vector2 = to_pos - from_pos
    var steps: int = maxi(1, int(ceilf(displacement.length() / 4.0)))
    for i in range(1, steps):
        var point: Vector2 = from_pos + displacement * (float(i) / float(steps))
        if blocked.has(Room.cell_of(point)):
            return false
    return true


# --- Validation ---------------------------------------------------------------------

## Checks the whole catalogue against schema v2 and the ENEMY_TIERS guardrails.
## Returns human-readable problems; empty means valid.
static func validate_catalogue(catalogue: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    if int(catalogue.get("schema_version", 0)) != SCHEMA_VERSION:
        problems.append("schema_version must be %d" % SCHEMA_VERSION)
    var sheets: Dictionary = catalogue.get("sprite_sheets", {})
    for sheet_id in sheets.keys():
        var sheet: Dictionary = sheets[sheet_id]
        if not String(sheet.get("path", "")).begins_with("res://"):
            problems.append("sprite_sheets.%s: path must be a res:// path" % sheet_id)
        for key in ["frame", "render"]:
            var size = sheet.get(key, [])
            if not size is Array or size.size() != 2 or float(size[0]) <= 0 or float(size[1]) <= 0:
                problems.append("sprite_sheets.%s: %s must be [width, height]" % [sheet_id, key])
    for band in range(1, 6):
        var rules: Dictionary = band_rules(catalogue, band)
        for key in ["ref_hp", "hp", "ac", "attack_bonus", "max_hit", "min_wind_up", "speed",
                "projectile_max", "xp_per_threat", "threat", "boss_hp"]:
            if not rules.has(key):
                problems.append("bands.%d: missing %s" % [band, key])
    _validate_settings(catalogue, problems)
    var defs: Dictionary = catalogue.get("enemies", {})
    if defs.is_empty():
        problems.append("enemies: catalogue is empty")
    for enemy_id in defs.keys():
        _validate_enemy(catalogue, String(enemy_id), defs[enemy_id], problems)
    return problems


static func _validate_settings(catalogue: Dictionary, problems: Array[String]) -> void:
    var cfg: Dictionary = settings(catalogue)
    for key in ["depth_bands", "budget", "intensity", "kind_multiplier", "max_enemies",
            "role_caps", "elite_chance", "boss_pool", "spawn", "dormancy", "first_cooldown"]:
        if not cfg.has(key):
            problems.append("encounters: missing %s" % key)
    var defs: Dictionary = catalogue.get("enemies", {})
    var modifiers: Dictionary = catalogue.get("elites", {}).get("modifiers", {})
    if modifiers.size() < 2:
        problems.append("elites: at least two modifiers are required")
    for mod_id in modifiers.keys():
        var mod: Dictionary = modifiers[mod_id]
        if not mod.has("name_prefix") or not Color.html_is_valid(String(mod.get("tint", ""))):
            problems.append("elites.%s: needs name_prefix and a valid tint" % mod_id)
    for entry in cfg.get("boss_pool", []):
        for option in entry.get("options", []):
            var boss_id: String = String(option.get("id", ""))
            if not defs.has(boss_id) or not bool(defs[boss_id].get("boss", false)):
                problems.append("encounters.boss_pool: '%s' is not a boss" % boss_id)
            var elite: String = String(option.get("elite", ""))
            if elite != "" and not modifiers.has(elite):
                problems.append("encounters.boss_pool: unknown elite modifier '%s'" % elite)


static func _validate_enemy(catalogue: Dictionary, enemy_id: String, data: Dictionary,
        problems: Array[String]) -> void:
    var missing := false
    for key in ["name", "role", "band", "min_depth", "max_depth", "threat", "tags", "boss",
            "resistances", "sprite", "level", "hp", "ac", "xp", "speed", "scores", "behavior",
            "attacks", "abilities", "collision_radius"]:
        if not data.has(key):
            problems.append("%s: missing %s" % [enemy_id, key])
            missing = true
    if missing:
        return
    var role: String = String(data["role"])
    if not ROLES.has(role):
        problems.append("%s: unknown role '%s' (expected one of %s)" % [enemy_id, role, ", ".join(ROLES)])
    var band: int = int(data["band"])
    if band < 1 or band > 5:
        problems.append("%s: band must be 1..5" % enemy_id)
    if int(data["min_depth"]) < 1 or int(data["max_depth"]) < int(data["min_depth"]):
        problems.append("%s: invalid depth range" % enemy_id)
    var boss: bool = bool(data["boss"])
    var summon_only: bool = bool(data.get("summon_only", false))
    if boss != (role == "boss"):
        problems.append("%s: boss flag and role 'boss' must agree" % enemy_id)
    if not data["tags"] is Array:
        problems.append("%s: tags must be an array of strings" % enemy_id)
    var resist = data["resistances"]
    if not resist is Dictionary:
        problems.append("%s: resistances must be an object" % enemy_id)
    else:
        for key in resist.keys():
            if not DAMAGE_TYPES.has(String(key)) and not STATUS_IDS.has(String(key)):
                problems.append("%s: unknown resistance tag '%s'" % [enemy_id, key])
            elif float(resist[key]) < 0.0:
                problems.append("%s: resistance '%s' must be >= 0" % [enemy_id, key])
    var sprite: String = String(data["sprite"])
    if not catalogue.get("sprite_sheets", {}).has(sprite) and not sprite.begins_with("res://"):
        problems.append("%s: sprite '%s' is neither a sprite_sheets id nor a res:// path" % [enemy_id, sprite])
    for ability in RPG.ABILITIES:
        if not data["scores"].has(ability):
            problems.append("%s: scores missing %s" % [enemy_id, ability])
    var abilities: Array = data["abilities"]
    for ability_id in abilities:
        if not ABILITY_IDS.has(String(ability_id)):
            problems.append("%s: unknown ability '%s' (expected one of %s)" % [enemy_id,
                ability_id, ", ".join(ABILITY_IDS)])
    var behavior: Dictionary = data["behavior"]
    var mode: String = String(behavior.get("mode", ""))
    if not MODES.has(mode):
        problems.append("%s: unknown behavior mode '%s' (expected one of %s)" % [enemy_id,
            mode, ", ".join(MODES)])
    var navigation: String = String(behavior.get("pathfinding", "grid_bfs"))
    if not NAVIGATION.has(navigation):
        problems.append("%s: unknown pathfinding '%s' (expected one of %s)" % [enemy_id,
            navigation, ", ".join(NAVIGATION)])
    var knockback: float = float(data.get("knockback_resist", 0.0))
    if knockback < 0.0 or knockback > 1.0:
        problems.append("%s: knockback_resist must be 0..1" % enemy_id)
    var rules: Dictionary = band_rules(catalogue, band)
    var attack_ids: Array = []
    var attacks: Array = data["attacks"]
    if attacks.is_empty():
        problems.append("%s: needs at least one attack" % enemy_id)
    for attack in attacks:
        var attack_id: String = String(attack.get("id", ""))
        if attack_id == "" or attack_ids.has(attack_id):
            problems.append("%s: attack ids must be unique and non-empty" % enemy_id)
        attack_ids.append(attack_id)
    for attack in attacks:
        _validate_attack(catalogue, enemy_id, data, attack, attack_ids, rules, problems)
    var phases: Array = data.get("phases", [])
    if boss and phases.is_empty():
        problems.append("%s: bosses need phases[]" % enemy_id)
    if not boss and not phases.is_empty():
        problems.append("%s: only bosses have phases[]" % enemy_id)
    var previous := 2.0
    for i in range(phases.size()):
        var phase: Dictionary = phases[i]
        var below: float = float(phase.get("below", -1.0))
        if (i == 0 and below != 1.0) or below <= 0.0 or below >= previous:
            problems.append("%s: phase %d 'below' must start at 1.0 and decrease" % [enemy_id, i])
        previous = below
        if phase.get("attacks", []).is_empty():
            problems.append("%s: phase %d has no attacks" % [enemy_id, i])
        for attack_id in phase.get("attacks", []):
            if not attack_ids.has(String(attack_id)):
                problems.append("%s: phase %d uses unknown attack '%s'" % [enemy_id, i, attack_id])
    if summon_only:
        return
    var threat: int = int(data["threat"])
    var hp: int = int(data["hp"])
    if boss:
        if not _within(rules.get("boss_hp", []), hp):
            problems.append("%s: boss HP %d outside band %d range %s" % [enemy_id, hp, band, rules.get("boss_hp")])
        var by_band: Dictionary = data.get("hp_by_band", {})
        for key in by_band.keys():
            if not _within(band_rules(catalogue, int(key)).get("boss_hp", []), int(by_band[key])):
                problems.append("%s: hp_by_band.%s outside the boss HP range" % [enemy_id, key])
        return
    if not _within(rules.get("hp", []), hp):
        problems.append("%s: HP %d outside band %d range %s" % [enemy_id, hp, band, rules.get("hp")])
    if not _within(rules.get("ac", []), int(data["ac"])):
        problems.append("%s: AC %d outside band %d range %s" % [enemy_id, int(data["ac"]), band, rules.get("ac")])
    if navigation != "stationary" and not _within(rules.get("speed", []), float(data["speed"])):
        problems.append("%s: speed %s outside band %d range %s" % [enemy_id, data["speed"], band, rules.get("speed")])
    if not _within(rules.get("threat", []), threat):
        problems.append("%s: threat %d outside band %d range %s" % [enemy_id, threat, band, rules.get("threat")])
    elif not _within(rules.get("xp_per_threat", []), float(data["xp"]) / float(threat)):
        problems.append("%s: XP per threat point %.1f outside band %d range %s" % [enemy_id,
            float(data["xp"]) / float(threat), band, rules.get("xp_per_threat")])


static func _validate_attack(catalogue: Dictionary, enemy_id: String, data: Dictionary,
        attack: Dictionary, attack_ids: Array, rules: Dictionary, problems: Array[String]) -> void:
    var label: String = "%s.%s" % [enemy_id, String(attack.get("id", "?"))]
    var kind: String = String(attack.get("type", ""))
    if not ATTACK_TYPES.has(kind):
        problems.append("%s: unknown attack type '%s' (expected one of %s)" % [label, kind,
            ", ".join(ATTACK_TYPES)])
        return
    var telegraph: String = String(attack.get("telegraph", ""))
    if not TELEGRAPHS.has(telegraph) or not TELEGRAPH_FOR_TYPE[kind].has(telegraph):
        problems.append("%s: telegraph '%s' is not valid for a %s attack (use %s)" % [label,
            telegraph, kind, "/".join(TELEGRAPH_FOR_TYPE[kind])])
    for key in ["wind_up", "recovery", "cooldown", "range"]:
        if not attack.has(key) or float(attack[key]) < 0.0:
            problems.append("%s: missing or negative %s" % [label, key])
    var boss: bool = bool(data.get("boss", false))
    var summon_only: bool = bool(data.get("summon_only", false))
    var wind_up: float = float(attack.get("wind_up", 0.0))
    if wind_up < float(rules.get("min_wind_up", 0.35)) - 0.0001:
        problems.append("%s: wind_up %.2f s is below the band minimum %.2f s" % [label, wind_up,
            float(rules.get("min_wind_up", 0.35))])
    if (boss or telegraph == "circle") and wind_up < AREA_MIN_WIND_UP - 0.0001:
        problems.append("%s: boss and area attacks need a wind_up of at least 0.5 s" % label)
    if float(attack.get("recovery", 0.0)) < MIN_RECOVERY and not attack.has("then"):
        problems.append("%s: recovery must be at least %.2f s" % [label, MIN_RECOVERY])
    if attack.has("then") and not attack_ids.has(String(attack["then"])):
        problems.append("%s: follow-up '%s' is not an attack of %s" % [label, attack["then"], enemy_id])
    if attack.has("damage_die") and not RPG.ABILITIES.has(String(attack.get("ability", ""))):
        problems.append("%s: invalid attack ability" % label)
    if attack.has("damage_type") and not DAMAGE_TYPES.has(String(attack["damage_type"])):
        problems.append("%s: unknown damage_type '%s'" % [label, attack["damage_type"]])
    if REQUIRED_ABILITY.has(kind) and not data.get("abilities", []).has(REQUIRED_ABILITY[kind]):
        problems.append("%s: %s attacks need the '%s' ability" % [label, kind, REQUIRED_ABILITY[kind]])
    match kind:
        "ranged":
            if float(attack.get("projectile_speed", 0.0)) <= 0.0 or \
                    float(attack.get("projectile_speed", 0.0)) > float(rules.get("projectile_max", 140)):
                problems.append("%s: projectile_speed must be within 0..%s" % [label, rules.get("projectile_max")])
        "dash":
            if float(attack.get("dash_speed", 0.0)) <= 0.0 or float(attack.get("dash_speed", 0.0)) > MAX_CHARGE_SPEED:
                problems.append("%s: dash_speed must be within 0..%.1f" % [label, MAX_CHARGE_SPEED])
            if float(attack.get("dash_distance", 0.0)) <= 0.0:
                problems.append("%s: dash_distance must be positive" % label)
        "area", "puddle":
            if float(attack.get("aoe_radius", 0.0)) <= 0.0:
                problems.append("%s: aoe_radius must be positive" % label)
            if kind == "puddle":
                var hazard = attack.get("hazard", null)
                if not hazard is Dictionary or float(hazard.get("duration", -1.0)) < 0.0:
                    problems.append("%s: puddle attacks need hazard {duration, tick, ...}" % label)
        "summon":
            var summon: Dictionary = attack.get("summon", {})
            var minion: Dictionary = catalogue.get("enemies", {}).get(String(summon.get("id", "")), {})
            if minion.is_empty() or not bool(minion.get("summon_only", false)):
                problems.append("%s: summon id '%s' must be a summon_only enemy" % [label, summon.get("id", "")])
            if int(summon.get("count", 0)) < 1 or int(summon.get("cap", 0)) < 1:
                problems.append("%s: summon count and cap must be at least 1" % label)
        "support":
            var effect: String = String(attack.get("effect", ""))
            if not SUPPORT_EFFECTS.has(effect):
                problems.append("%s: unknown support effect '%s'" % [label, effect])
            elif not data.get("abilities", []).has(SUPPORT_EFFECTS[effect]):
                problems.append("%s: %s support needs the '%s' ability" % [label, effect, SUPPORT_EFFECTS[effect]])
            if int(attack.get("amount", 0)) <= 0:
                problems.append("%s: support amount must be positive" % label)
    if summon_only:
        return
    var hit: int = max_hit(data, attack)
    var cap: int = int(floorf(float(rules.get("ref_hp", 20)) * 0.5)) if boss else int(rules.get("max_hit", 7))
    if hit > cap:
        problems.append("%s: max non-crit hit %d exceeds the band cap %d" % [label, hit, cap])
    if not boss and attack.has("damage_die") and ["melee", "ranged", "dash", "area"].has(kind):
        var to_hit: int = RPG.attack_bonus(data["scores"], String(attack.get("ability", "STR")),
            int(data.get("level", 1)), bool(attack.get("proficient", true)))
        if not _within(rules.get("attack_bonus", []), to_hit):
            problems.append("%s: attack bonus %+d outside band range %s" % [label, to_hit, rules.get("attack_bonus")])


static func _within(bounds, value: float) -> bool:
    if not bounds is Array or bounds.size() != 2:
        return true
    return value >= float(bounds[0]) - 0.0001 and value <= float(bounds[1]) + 0.0001
