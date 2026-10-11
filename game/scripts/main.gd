extends Node2D
## Fixed 24x24 world room; window scale and HUD layout remain independent.
const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Contents = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const CharacterMenu = preload("res://scripts/character_menu.gd")

const TILE := 32.0
const SIZE := 24
const ROOM := Rect2(Vector2.ZERO, Vector2(768, 768))
const MID := Vector2(384, 384)
const DOOR_HALF := 32.0
const PLAYER_RADIUS := 11.0
const DIRECTIONS := ["N", "E", "S", "W"]
const CRYPT = preload("res://assets/biomes/stone_crypt/tileset.png")
const CRAWLER = preload("res://assets/characters/crawler/facing_8.png")
const RAT = preload("res://assets/enemies/rat/facing_8.png")
const BOSS = preload("res://assets/enemies/brute_boss/facing_8.png")
const FLOOR_TILE := Rect2(0, 0, 32, 32)
const FLOOR_ALT := Rect2(32, 0, 32, 32)
const WALL_TILE := Rect2(64, 0, 32, 32)
const CORNER_TILE := Rect2(96, 0, 32, 32)
const DOOR_TILE := Rect2(64, 64, 64, 64)

var config: Dictionary = {}
var catalogue: Dictionary = {}
var floor: Dictionary = {}
var layout: Dictionary = {}
var rules
var rng := RandomNumberGenerator.new()
var seed_value := 0
var current_room_id := 0
var ticks := 0
var visited: Dictionary = {}
var room_states: Dictionary = {}
var room_obstacles: Dictionary = {}
var props: Array = []
var enemies: Array = []
var projectiles: Array[Dictionary] = []
var tick_ledger: Array[Dictionary] = []
var boss_defeated := false
var outcome := "running"
var message := ""
var rooms_entered := 1

var player_position := MID
var aim_direction := Vector2.RIGHT
var player_facing := 0
var ability_scores: Dictionary = {}
var player_xp := 0
var player_level := 1
var player_max_hp := 12
var player_hp := 12
var player_ac := 12
var player_proficiency := 2
var fire_cooldown := 0.0
var melee_cooldown := 0.0
var melee_flash := 0.0
var invulnerability := 0.0
var shots_fired := 0
var melee_swings := 0
var pending_stat_points := 0
var character_menu


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_rules.json"))
    if not parsed is Dictionary:
        push_error("Invalid prototype_rules.json")
        get_tree().quit(1)
        return
    config = parsed
    catalogue = Enemies.load_catalogue()
    if not Enemies.validate_catalogue(catalogue).is_empty():
        push_error("Invalid enemy definitions: %s" % [Enemies.validate_catalogue(catalogue)])
        get_tree().quit(1)
        return
    layout = Layout.compute(get_viewport_rect().size)
    character_menu = CharacterMenu.new()
    add_child(character_menu)
    character_menu.allocation_confirmed.connect(_confirm_stat_allocation)
    character_menu.resume_requested.connect(_on_resume_game)
    _start_run(int(config.get("seed", 424242)))


func _start_run(new_seed: int) -> void:
    seed_value = new_seed
    rng.seed = seed_value
    floor = Generator.generate(seed_value, int(config.get("room_count", 22)))
    rules = Collapse.new(config.get("collapse", {}))
    ticks = int(config.get("start_ticks", 26))
    current_room_id = int(floor["start_id"])
    visited = {current_room_id: true}
    room_states.clear()
    projectiles.clear()
    tick_ledger.clear()
    boss_defeated = false
    outcome = "running"
    player_position = MID
    aim_direction = Vector2.RIGHT
    player_facing = 0
    player_xp = 0
    pending_stat_points = 0
    if character_menu != null:
        character_menu.close_menu()
    ability_scores = config.get("player_ability_scores", RPG.player_base_scores()).duplicate(true)
    _sync_progression()
    player_hp = player_max_hp
    invulnerability = 0.0
    fire_cooldown = 0.0
    melee_cooldown = 0.0
    melee_flash = 0.0
    rooms_entered = 1
    shots_fired = 0
    melee_swings = 0
    _load_room(current_room_id)
    var budget: int = Collapse.mandatory_budget_floor(floor, rules)
    message = "24x24 fixed room | Seed %d | budget diagnostic %d ticks" % [seed_value, budget]
    print(message)
    queue_redraw()


func _sync_progression() -> void:
    var progression: Dictionary = RPG.player_progression(player_xp, ability_scores)
    player_level = int(progression["level"])
    player_max_hp = int(progression["max_hp"])
    player_ac = int(progression["ac"])
    player_proficiency = int(progression["proficiency"])


func _load_room(id: int) -> void:
    if not room_states.has(id):
        var room: Dictionary = floor["rooms"][id]
        var contents: Dictionary = Contents.generate(seed_value, id, room["neighbors"],
            String(room["kind"]), int(config.get("obstacle_count", 38)))
        var encounter: Array[Dictionary] = Enemies.generate_encounter(catalogue,
            String(room["kind"]), seed_value, id, contents["blocked"])
        room_states[id] = {"blocked": contents["blocked"], "props": contents["props"],
            "enemies": encounter}
    var state: Dictionary = room_states[id]
    room_obstacles = state["blocked"]
    props = state["props"]
    enemies = state["enemies"]


func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event: InputEventKey = event
        if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
            if character_menu.mode == "pause":
                character_menu.close_menu()
            elif character_menu.mode == "closed" and outcome == "running":
                character_menu.show_pause(ability_scores, _character_context())
            get_viewport().set_input_as_handled()


func _character_context() -> Dictionary:
    return {
        "room_id": current_room_id,
        "ticks": ticks, "level": player_level, "xp": player_xp,
        "next_xp": RPG.next_level_xp(player_level) if player_level < 20 else "MAX",
        "hp": player_hp, "max_hp": player_max_hp, "ac": player_ac,
        "proficiency": player_proficiency,
        "melee_bonus": RPG.attack_bonus(ability_scores, "STR", player_level),
        "ranged_bonus": RPG.attack_bonus(ability_scores, "DEX", player_level)
    }


func _on_resume_game() -> void:
    queue_redraw()


func _confirm_stat_allocation(changes: Dictionary) -> void:
    if character_menu.mode != "level_up":
        return
    var cap: int = int(config.get("stat_score_cap", 20))
    var next_scores: Dictionary = RPG.apply_allocation(
        ability_scores, changes, pending_stat_points, cap
    )
    if next_scores.is_empty():
        push_warning("Invalid level-up stat point allocation")
        return
    var old_hp_max: int = player_max_hp
    ability_scores = next_scores
    pending_stat_points = 0
    _sync_progression()
    # Increasing CON raises current HP by the same amount as max HP.
    player_hp = mini(player_max_hp, player_hp + maxi(0, player_max_hp - old_hp_max))
    character_menu.close_menu()
    message = "Level %d stats confirmed. HP %d/%d  AC %d" % [
        player_level, player_hp, player_max_hp, player_ac
    ]
    queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if character_menu != null and character_menu.is_open():
        return
    if event is InputEventKey:
        var key_event: InputEventKey = event
        if key_event.pressed and not key_event.echo:
            if key_event.keycode == KEY_R:
                _start_run(seed_value)
            elif key_event.keycode == KEY_N:
                _start_run(int(Time.get_ticks_usec() % 2147483647))


func _physics_process(delta: float) -> void:
    if get_viewport_rect().size != Vector2(layout["viewport"]):
        layout = Layout.compute(get_viewport_rect().size)
    if outcome != "running" or character_menu.is_open():
        queue_redraw()
        return
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    melee_cooldown = maxf(0.0, melee_cooldown - delta)
    melee_flash = maxf(0.0, melee_flash - delta)
    invulnerability = maxf(0.0, invulnerability - delta)
    var move_axis := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        move_axis.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        move_axis.x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        move_axis.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        move_axis.y += 1.0
    var change: Vector2 = move_axis.normalized() * float(config.get("player_speed", 210.0)) * delta
    _move_player(change)
    if outcome != "running":
        queue_redraw()
        return
    var mouse_world: Vector2 = Layout.screen_to_world(get_global_mouse_position(), layout)
    var to_mouse: Vector2 = mouse_world - player_position
    if to_mouse.length_squared() > 9.0:
        aim_direction = to_mouse.normalized()
        player_facing = _facing_from_vector(aim_direction)
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0.0:
        _fire()
    if Input.is_key_pressed(KEY_SPACE) and melee_cooldown <= 0.0:
        _melee()
    _update_projectiles(delta)
    if not character_menu.is_open():
        _update_enemies(delta)
    queue_redraw()


func _move_player(change: Vector2) -> void:
    var proposed: Vector2 = player_position + change
    var direction := ""
    if proposed.x < PLAYER_RADIUS and absf(proposed.y - MID.y) <= DOOR_HALF:
        direction = "W"
    elif proposed.x > ROOM.end.x - PLAYER_RADIUS and absf(proposed.y - MID.y) <= DOOR_HALF:
        direction = "E"
    elif proposed.y < PLAYER_RADIUS and absf(proposed.x - MID.x) <= DOOR_HALF:
        direction = "N"
    elif proposed.y > ROOM.end.y - PLAYER_RADIUS and absf(proposed.x - MID.x) <= DOOR_HALF:
        direction = "S"
    if direction != "":
        _enter_neighbor(direction)
        return
    var horizontal := player_position + Vector2(change.x, 0.0)
    if Contents.can_occupy(horizontal, PLAYER_RADIUS, room_obstacles):
        player_position.x = horizontal.x
    var vertical := player_position + Vector2(0.0, change.y)
    if Contents.can_occupy(vertical, PLAYER_RADIUS, room_obstacles):
        player_position.y = vertical.y


func _enter_neighbor(direction: String) -> void:
    var room: Dictionary = floor["rooms"][current_room_id]
    if not room["neighbors"].has(direction):
        return
    var next_id: int = int(room["neighbors"][direction])
    var next_room: Dictionary = floor["rooms"][next_id]
    if next_room["kind"] == "exit" and not boss_defeated:
        message = "EXIT SEALED: defeat the boss before descending."
        return
    var first_visit: bool = not visited.has(next_id)
    var entry: Dictionary = rules.evaluate(ticks, String(next_room["kind"]), first_visit, next_id)
    if not bool(entry["allowed"]):
        message = "Not enough collapse ticks for that doorway."
        return
    tick_ledger.append(entry)
    ticks = int(entry["after"])
    current_room_id = next_id
    if first_visit:
        rooms_entered += 1
    visited[next_id] = true
    projectiles.clear()
    match direction:
        "N": player_position = Vector2(MID.x, ROOM.end.y - 42)
        "S": player_position = Vector2(MID.x, 42)
        "W": player_position = Vector2(ROOM.end.x - 42, MID.y)
        "E": player_position = Vector2(42, MID.y)
    _load_room(next_id)
    message = "Room %d [%s] | %s | %d ticks left" % [
        next_id, String(next_room["kind"]), String(entry["reason"]), ticks]
    print("COLLAPSE LEDGER ", entry)
    if bool(entry["collapses"]):
        outcome = "collapsed"
        message = "THE FLOOR COLLAPSED! R = repeat, N = new seed"
    elif next_room["kind"] == "exit":
        outcome = "escaped"
        message = "FLOOR CLEARED! R = repeat, N = new seed"


func _fire() -> void:
    fire_cooldown = 0.28
    shots_fired += 1
    projectiles.append({
        "pos": player_position + aim_direction * 18.0,
        "velocity": aim_direction * 430.0, "ttl": 2.0, "owner": "player",
        "die": 6, "bonus": RPG.modifier(int(ability_scores["DEX"])),
        "attack_bonus": RPG.attack_bonus(ability_scores, "DEX", player_level)
    })


func _melee() -> void:
    melee_cooldown = 0.50
    melee_flash = 0.17
    melee_swings += 1
    for i in range(enemies.size() - 1, -1, -1):
        var foe: Dictionary = enemies[i]
        var toward: Vector2 = Vector2(foe["pos"]) - player_position
        if toward.length() <= 64.0 + float(foe["radius"]) and toward.length() > 0.01:
            if aim_direction.dot(toward.normalized()) > 0.45:
                _hit_enemy(i, RPG.attack_bonus(ability_scores, "STR", player_level),
                    6, RPG.modifier(int(ability_scores["STR"])))


func _hit_enemy(index: int, to_hit: int, die: int, damage_bonus: int) -> void:
    if index < 0 or index >= enemies.size():
        return
    var foe: Dictionary = enemies[index]
    var definition: Dictionary = catalogue["enemies"][foe["definition"]]
    var attack: Dictionary = RPG.roll_to_hit(rng, to_hit, int(definition["ac"]))
    if not bool(attack["hit"]):
        message = "Missed %s (d20: %d)" % [definition["name"], int(attack["d20"])]
        return
    var damage: int = RPG.roll_damage(rng, die, damage_bonus, bool(attack["critical"]))
    foe["hp"] = int(foe["hp"]) - damage
    message = "Hit %s for %d damage" % [definition["name"], damage]
    if int(foe["hp"]) <= 0:
        var defeated_id: String = String(foe["definition"])
        enemies.remove_at(index)
        _award_xp(int(definition["xp"]))
        if defeated_id == "armored_brute":
            boss_defeated = true
            message = "Boss defeated! +%d XP | Exit unlocked." % int(definition["xp"])


func _award_xp(amount: int) -> void:
    var prior_level: int = player_level
    var old_max: int = player_max_hp
    player_xp += maxi(0, amount)
    _sync_progression()
    if player_level > prior_level:
        player_hp = mini(player_max_hp, player_hp + (player_max_hp - old_max))
        var earned_levels: int = player_level - prior_level
        pending_stat_points += earned_levels * maxi(0, int(config.get("stat_points_per_level", 2)))
        message = "LEVEL UP! Level %d — %d ability points available." % [
            player_level, pending_stat_points
        ]
        if pending_stat_points > 0 and character_menu != null:
            character_menu.show_level_up(ability_scores, _character_context(),
                pending_stat_points, int(config.get("stat_score_cap", 20)))


func _update_projectiles(delta: float) -> void:
    for i in range(projectiles.size() - 1, -1, -1):
        var bullet: Dictionary = projectiles[i]
        bullet["pos"] = Vector2(bullet["pos"]) + Vector2(bullet["velocity"]) * delta
        bullet["ttl"] = float(bullet["ttl"]) - delta
        var position: Vector2 = bullet["pos"]
        if float(bullet["ttl"]) <= 0.0 or not Contents.can_occupy(position, 4.0, room_obstacles):
            projectiles.remove_at(i)
            continue
        var collided := false
        if String(bullet["owner"]) == "player":
            for j in range(enemies.size() - 1, -1, -1):
                if position.distance_to(Vector2(enemies[j]["pos"])) < float(enemies[j]["radius"]) + 6.0:
                    _hit_enemy(j, int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]))
                    collided = true
                    break
        elif position.distance_to(player_position) < PLAYER_RADIUS + 6.0:
            _hit_player(int(bullet["attack_bonus"]), int(bullet["die"]), int(bullet["bonus"]))
            collided = true
        if collided:
            projectiles.remove_at(i)


func _hit_player(to_hit: int, die: int, damage_bonus: int) -> void:
    if invulnerability > 0.0:
        return
    var attack: Dictionary = RPG.roll_to_hit(rng, to_hit, player_ac)
    if not bool(attack["hit"]):
        message = "Enemy missed you (d20: %d)." % int(attack["d20"])
        return
    var damage: int = RPG.roll_damage(rng, die, damage_bonus, bool(attack["critical"]))
    player_hp -= damage
    invulnerability = 0.8
    message = "You take %d damage. %d/%d HP." % [damage, maxi(0, player_hp), player_max_hp]
    if player_hp <= 0:
        outcome = "defeated"
        message = "YOU DIED! R = retry, N = new seed."


func _update_enemies(delta: float) -> void:
    for i in range(enemies.size()):
        var foe: Dictionary = enemies[i]
        var definition: Dictionary = catalogue["enemies"][foe["definition"]]
        Enemies.advance(foe, definition, delta, player_position, room_obstacles)
        foe["attack_cooldown"] = maxf(0.0, float(foe["attack_cooldown"]) - delta)
        if float(foe["attack_cooldown"]) > 0.0:
            continue
        var attacks: Array = definition.get("attacks", [])
        if attacks.is_empty():
            continue
        var skill: Dictionary = attacks[0]
        var distance: float = Vector2(foe["pos"]).distance_to(player_position)
        if distance > float(skill.get("range", 45.0)):
            continue
        if not Enemies.has_line_of_sight(Vector2(foe["pos"]), player_position, room_obstacles):
            continue
        var ability: String = String(skill.get("ability", "STR"))
        var attack_bonus: int = RPG.attack_bonus(definition["scores"], ability,
            int(definition.get("level", 1)), bool(skill.get("proficient", true)))
        var damage_bonus: int = RPG.modifier(int(definition["scores"].get(ability, 10))) + int(skill.get("damage_bonus", 0))
        foe["attack_cooldown"] = float(skill.get("cooldown", 1.0))
        if skill["type"] == "melee":
            _hit_player(attack_bonus, int(skill["damage_die"]), damage_bonus)
        elif skill["type"] == "ranged":
            var direction: Vector2 = (player_position - Vector2(foe["pos"])).normalized()
            var angles: Array[float] = [0.0]
            if "twin_shot" in definition.get("abilities", []):
                angles = [-0.15, 0.15]
            for angle in angles:
                var shot: Vector2 = direction.rotated(angle)
                projectiles.append({
                    "pos": Vector2(foe["pos"]) + shot * (float(foe["radius"]) + 8.0),
                    "velocity": shot * float(skill.get("projectile_speed", 250.0)),
                    "ttl": 2.8, "owner": "enemy", "die": int(skill["damage_die"]),
                    "bonus": damage_bonus, "attack_bonus": attack_bonus
                })


func _facing_from_vector(vector: Vector2) -> int:
    if vector.length_squared() < 0.0001:
        return 0
    return posmod(int(round(vector.angle() / (PI / 4.0))), 8)


func _draw() -> void:
    var viewport: Vector2 = Vector2(layout.get("viewport", Vector2(960, 540)))
    draw_rect(Rect2(Vector2.ZERO, viewport), Color("#101720"))
    var offset: Vector2 = layout.get("offset", Vector2.ZERO)
    var scale: float = float(layout.get("scale", 1.0))
    draw_set_transform(offset, 0.0, Vector2.ONE * scale)
    _draw_room()
    _draw_combat()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    _draw_hud()
    if outcome != "running":
        draw_rect(Rect2(Vector2(40, viewport.y * 0.48 - 58), Vector2(viewport.x - 80, 116)),
            Color(0.02, 0.03, 0.07, 0.94))
        _text("FLOOR CLEARED!" if outcome == "escaped" else "RUN ENDED: " + outcome.to_upper(),
            Vector2(65, viewport.y * 0.48 - 12), 23, Color("#f7d98b"))
        _text("Rooms %d | Kills yield XP | Level %d | XP %d | R: repeat  N: new seed" % [
            rooms_entered, player_level, player_xp],
            Vector2(65, viewport.y * 0.48 + 22), 14, Color.WHITE)


func _draw_room() -> void:
    for y in range(SIZE):
        for x in range(SIZE):
            var center: Vector2 = Vector2((float(x) + 0.5) * TILE, (float(y) + 0.5) * TILE)
            var tile: Rect2 = FLOOR_ALT if (x * 17 + y * 13) % 9 == 0 else FLOOR_TILE
            _crypt_piece(tile, center, Vector2(32, 32), float((x + y * 3) % 4) * PI * 0.5)
    var kind: String = String(floor["rooms"][current_room_id]["kind"])
    var tint := Color.TRANSPARENT
    if kind == "boss": tint = Color(0.3, 0.05, 0.09, 0.16)
    elif kind == "guild_hall": tint = Color(0.04, 0.30, 0.22, 0.14)
    elif kind == "exit": tint = Color(0.35, 0.24, 0.06, 0.14)
    if tint.a > 0.0:
        draw_rect(ROOM, tint)

    for prop in props:
        _draw_obstacle(prop)

    var links: Dictionary = floor["rooms"][current_room_id]["neighbors"]
    for x in range(SIZE):
        var px: float = (float(x) + 0.5) * TILE
        if not (links.has("N") and (x == 11 or x == 12)):
            _crypt_piece(WALL_TILE, Vector2(px, -16), Vector2(32, 32))
        if not (links.has("S") and (x == 11 or x == 12)):
            _crypt_piece(WALL_TILE, Vector2(px, 784), Vector2(32, 32), PI)
    for y in range(SIZE):
        var py: float = (float(y) + 0.5) * TILE
        if not (links.has("W") and (y == 11 or y == 12)):
            _crypt_piece(WALL_TILE, Vector2(-16, py), Vector2(32, 32), -PI * 0.5)
        if not (links.has("E") and (y == 11 or y == 12)):
            _crypt_piece(WALL_TILE, Vector2(784, py), Vector2(32, 32), PI * 0.5)
    _crypt_piece(CORNER_TILE, Vector2(-16, -16), Vector2(32, 32))
    _crypt_piece(CORNER_TILE, Vector2(784, -16), Vector2(32, 32), PI * 0.5)
    _crypt_piece(CORNER_TILE, Vector2(784, 784), Vector2(32, 32), PI)
    _crypt_piece(CORNER_TILE, Vector2(-16, 784), Vector2(32, 32), -PI * 0.5)
    for direction in DIRECTIONS:
        if not links.has(direction):
            continue
        var next_id: int = int(links[direction])
        var destination: Dictionary = floor["rooms"][next_id]
        var preview: Dictionary = rules.evaluate(ticks, String(destination["kind"]),
            not visited.has(next_id), next_id)
        var color := Color.WHITE
        if destination["kind"] == "guild_hall": color = Color("#a4efe1")
        elif destination["kind"] == "boss": color = Color("#f5b0b0")
        elif destination["kind"] == "exit":
            color = Color("#f9d57e") if boss_defeated else Color("#c77179")
        var center := MID
        var rotation := 0.0
        var label := MID
        match direction:
            "N":
                center = Vector2(384, 0)
                label = Vector2(361, 42)
            "S":
                center = Vector2(384, 768)
                rotation = PI
                label = Vector2(361, 738)
            "W":
                center = Vector2(0, 384)
                rotation = -PI * 0.5
                label = Vector2(25, 392)
            "E":
                center = Vector2(768, 384)
                rotation = PI * 0.5
                label = Vector2(690, 392)
        _crypt_piece(DOOR_TILE, center, Vector2(64, 64), rotation, color)
        var net: int = int(preview["grant"]) - int(preview["cost"])
        _text("%s%+d" % [direction, net], label, 23, Color.WHITE)
    if kind == "boss":
        _text("BOSS ROOM", Vector2(306, 60), 26, Color("#ffb4b7"))
    elif kind == "guild_hall":
        _text("GUILD HALL", Vector2(300, 60), 26, Color("#b4f9d8"))
    elif kind == "exit":
        _text("EXIT", Vector2(344, 60), 26, Color("#ffdc91"))


func _draw_obstacle(prop: Dictionary) -> void:
    var cell: Vector2i = prop["cell"]
    var center: Vector2 = Contents.cell_center(cell)
    draw_circle(center + Vector2(2, 5), 15.5, Color("#11151c"))
    if prop["kind"] == "pillar":
        _crypt_piece(WALL_TILE, center, Vector2(32, 32))
        draw_rect(Rect2(center - Vector2(10, 12), Vector2(20, 5)), Color("#a39c92"))
    else:
        draw_colored_polygon(PackedVector2Array([
            center + Vector2(-13, 9), center + Vector2(-11, -5),
            center + Vector2(-2, -13), center + Vector2(10, -7),
            center + Vector2(13, 11)]), Color("#736b66"))
        draw_rect(Rect2(center + Vector2(-5, -7), Vector2(9, 7)), Color("#a4a09b"))


func _draw_combat() -> void:
    for projectile in projectiles:
        var point: Vector2 = projectile["pos"]
        var color := Color("#ffe78b") if projectile["owner"] == "player" else Color("#d778dc")
        draw_circle(point, 5.0, color)
    for foe in enemies:
        var definition: Dictionary = catalogue["enemies"][foe["definition"]]
        var boss_sprite: bool = definition["sprite"] == "boss"
        var sheet: Texture2D = BOSS if boss_sprite else RAT
        var size := Vector2(96, 96) if boss_sprite else Vector2(48, 48)
        var point: Vector2 = foe["pos"]
        _draw_facing_sprite(sheet, point, size, int(foe["facing"]))
        var hp_ratio: float = float(foe["hp"]) / float(foe["max_hp"])
        draw_rect(Rect2(point.x - 24, point.y - size.y * 0.5 - 12, 48, 6), Color("#151b25"))
        draw_rect(Rect2(point.x - 24, point.y - size.y * 0.5 - 12,
            48 * hp_ratio, 6), Color("#a5d49b"))
        if foe["definition"] == "spitting_rat":
            draw_circle(point + Vector2(0, 22), 4.0, Color("#c978d4"))
    _draw_facing_sprite(CRAWLER, player_position, Vector2(48, 48), player_facing)
    draw_line(player_position, player_position + aim_direction * 26.0, Color("#f9dc92"), 2.0)
    if melee_flash > 0.0:
        draw_arc(player_position, 60.0, aim_direction.angle() - 0.7,
            aim_direction.angle() + 0.7, 14, Color("#fff1a7"), 5.0)
    if invulnerability > 0.0:
        draw_arc(player_position, 24.0, 0.0, TAU, 24, Color(1, 1, 1, 0.42), 2.0)


func _crypt_piece(region: Rect2, center: Vector2, size: Vector2,
        rotation: float = 0.0, modulation: Color = Color.WHITE) -> void:
    # Draw transforms are absolute; compose the room's screen transform here.
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


func _draw_hud() -> void:
    var view: Vector2 = layout["viewport"]
    var room: Dictionary = floor["rooms"][current_room_id]
    _text("DCC | FLOOR 1 | ROOM %d %s | TICKS %d | FOES %d" % [
        current_room_id, String(room["kind"]).to_upper(), ticks, enemies.size()],
        Vector2(14, 22), 17, Color("#f2da99"))
    _text("HP %d/%d  AC %d  LV %d  XP %d/%s  PROF +%d" % [
        maxi(0, player_hp), player_max_hp, player_ac, player_level, player_xp,
        str(RPG.next_level_xp(player_level)) if player_level < 20 else "MAX",
        player_proficiency], Vector2(14, 43), 15, Color("#e5eafa"))
    var stat_parts: PackedStringArray = []
    for ability in RPG.ABILITIES:
        var score: int = int(ability_scores[ability])
        stat_parts.append("%s%d(%+d)" % [ability, score, RPG.modifier(score)])
    _text("  ".join(stat_parts), Vector2(14, 62), 12, Color("#afd4ce"))
    _text(message, Vector2(14, 83), 12, Color("#eccba6"))
    _draw_minimap()
    _text("WASD / arrows: move  |  Mouse: aim  |  LMB: shoot  |  Space: melee",
        Vector2(14, view.y - 46), 14, Color("#dce9f2"))
    _text("Esc: pause / stats | R: replay | N: new seed | Fixed 24x24 room",
        Vector2(14, view.y - 21), 12, Color("#a7cfcb"))


func _draw_minimap() -> void:
    var view: Vector2 = layout["viewport"]
    var map_origin := Vector2(view.x - 185.0, 9.0)
    draw_rect(Rect2(map_origin, Vector2(174, 82)), Color("#222c39"))
    _text("MAP", map_origin + Vector2(8, 13), 11, Color.WHITE)
    var min_cell := Vector2i(999, 999)
    var max_cell := Vector2i(-999, -999)
    for room in floor["rooms"]:
        var cell: Vector2i = room["grid"]
        min_cell.x = mini(min_cell.x, cell.x)
        min_cell.y = mini(min_cell.y, cell.y)
        max_cell.x = maxi(max_cell.x, cell.x)
        max_cell.y = maxi(max_cell.y, cell.y)
    var span_x: int = maxi(1, max_cell.x - min_cell.x + 1)
    var span_y: int = maxi(1, max_cell.y - min_cell.y + 1)
    var unit: float = minf(9.0, minf(156.0 / float(span_x), 60.0 / float(span_y)))
    for room in floor["rooms"]:
        var id: int = int(room["id"])
        if not visited.has(id) and id != int(floor["exit_id"]):
            continue
        var cell: Vector2i = room["grid"]
        var p: Vector2 = map_origin + Vector2(
            8.0 + float(cell.x - min_cell.x) * unit,
            20.0 + float(cell.y - min_cell.y) * unit)
        var color := Color("#788b9d")
        if id == current_room_id: color = Color.WHITE
        elif room["kind"] == "boss": color = Color("#ec9c9d")
        elif room["kind"] == "exit": color = Color("#eacb7b")
        elif room["kind"] == "guild_hall": color = Color("#a4efd6")
        draw_rect(Rect2(p, Vector2(maxf(3.0, unit - 1.0), maxf(3.0, unit - 1.0))), color)


func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
