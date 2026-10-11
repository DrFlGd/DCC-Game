extends Node2D
## DCC Game greybox vertical traversal spike.
## Rooms are drawn programmatically to avoid external assets in the first prototype.

const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")

const VIEW_SIZE := Vector2(960, 540)
const ARENA := Rect2(86.0, 116.0, 788.0, 316.0)
const CENTER := Vector2(480, 274)
const DOOR_HALF_WIDTH := 44.0
const PLAYER_RADIUS := 11.0
const BULLET_SPEED := 445.0
const MOVE_LABELS := ["N", "E", "S", "W"]

var config: Dictionary = {}
var floor: Dictionary = {}
var rules: RefCounted
var current_room_id := 0
var visited: Dictionary = {}
var defeated: Dictionary = {}
var saved_enemy_hp: Dictionary = {}
var tick_ledger: Array[Dictionary] = []
var ticks := 0
var initial_seed := 0
var player_position := CENTER
var player_hp := 8
var boss_defeated := false
var outcome := "running"
var message := ""
var projectiles: Array[Dictionary] = []
var enemy: Dictionary = {}
var aim_direction := Vector2.RIGHT
var fire_cooldown := 0.0
var melee_cooldown := 0.0
var melee_flash := 0.0
var invincible_seconds := 0.0
var shots_fired := 0
var melee_swings := 0
var rooms_entered := 1


func _ready() -> void:
    var raw: String = FileAccess.get_file_as_string("res://data/prototype_rules.json")
    var parsed = JSON.parse_string(raw)
    if not parsed is Dictionary:
        push_error("Invalid prototype_rules.json; expected JSON object")
        get_tree().quit(1)
        return
    config = parsed
    _start_run(int(config.get("seed", 424242)))


func _start_run(seed_value: int) -> void:
    initial_seed = seed_value
    floor = Generator.generate(seed_value, int(config.get("room_count", 22)))
    rules = Collapse.new(config.get("collapse", {}))
    ticks = int(config.get("start_ticks", 26))
    current_room_id = int(floor["start_id"])
    visited = {current_room_id: true}
    defeated.clear()
    saved_enemy_hp.clear()
    tick_ledger.clear()
    projectiles.clear()
    player_position = CENTER
    player_hp = int(config.get("player_max_hp", 8))
    boss_defeated = false
    enemy.clear()
    aim_direction = Vector2.RIGHT
    fire_cooldown = 0.0
    melee_cooldown = 0.0
    melee_flash = 0.0
    invincible_seconds = 0.0
    shots_fired = 0
    melee_swings = 0
    rooms_entered = 1
    outcome = "running"
    var budget_floor: int = Collapse.mandatory_budget_floor(floor, rules)
    message = "Seed %d | estimated mandatory route minimum %d ticks" % [seed_value, budget_floor]
    if ticks < budget_floor:
        push_warning("Starting budget is below the route diagnostic: %d < %d" % [ticks, budget_floor])
    print(message)
    queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key_event: InputEventKey = event
        if not key_event.pressed or key_event.echo:
            return
        if key_event.keycode == KEY_R:
            _start_run(initial_seed)
        elif key_event.keycode == KEY_N:
            _start_run(int(Time.get_ticks_usec() % 2147483647))


func _physics_process(delta: float) -> void:
    if outcome != "running":
        queue_redraw()
        return

    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    melee_cooldown = maxf(0.0, melee_cooldown - delta)
    melee_flash = maxf(0.0, melee_flash - delta)
    invincible_seconds = maxf(0.0, invincible_seconds - delta)

    var move_axis := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        move_axis.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        move_axis.x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        move_axis.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        move_axis.y += 1.0
    player_position += move_axis.normalized() * float(config.get("player_speed", 210.0)) * delta
    _handle_doors()
    if outcome != "running":
        queue_redraw()
        return

    var target: Vector2 = get_global_mouse_position() - player_position
    if target.length_squared() > 9.0:
        aim_direction = target.normalized()
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0.0:
        _fire()
    if Input.is_key_pressed(KEY_SPACE) and melee_cooldown <= 0.0:
        _melee_attack()

    _move_projectiles(delta)
    _move_enemy(delta)
    queue_redraw()


func _room() -> Dictionary:
    var rooms: Array = floor["rooms"]
    return rooms[current_room_id]


func _handle_doors() -> void:
    var door := ""
    if player_position.x < ARENA.position.x:
        if absf(player_position.y - CENTER.y) <= DOOR_HALF_WIDTH:
            door = "W"
    elif player_position.x > ARENA.end.x:
        if absf(player_position.y - CENTER.y) <= DOOR_HALF_WIDTH:
            door = "E"
    elif player_position.y < ARENA.position.y:
        if absf(player_position.x - CENTER.x) <= DOOR_HALF_WIDTH:
            door = "N"
    elif player_position.y > ARENA.end.y:
        if absf(player_position.x - CENTER.x) <= DOOR_HALF_WIDTH:
            door = "S"
    if door != "":
        _enter_neighbor(door)
    player_position.x = clampf(player_position.x, ARENA.position.x, ARENA.end.x)
    player_position.y = clampf(player_position.y, ARENA.position.y, ARENA.end.y)


func _enter_neighbor(direction: String) -> void:
    var links: Dictionary = _room()["neighbors"]
    if not links.has(direction):
        message = "No door in that direction."
        return
    var next_id: int = int(links[direction])
    if next_id == int(floor["exit_id"]) and not boss_defeated:
        message = "EXIT SEALED: defeat the boss to unlock this door."
        return

    var rooms: Array = floor["rooms"]
    var destination: Dictionary = rooms[next_id]
    var first_visit: bool = not visited.has(next_id)
    var entry: Dictionary = rules.evaluate(ticks, String(destination["kind"]), first_visit, next_id)
    if not bool(entry["allowed"]):
        message = "Entry blocked: %s; only %d ticks left." % [entry["reason"], ticks]
        return

    if not enemy.is_empty():
        saved_enemy_hp[current_room_id] = int(enemy["hp"])
    tick_ledger.append(entry)
    print("COLLAPSE LEDGER ", entry)
    ticks = int(entry["after"])
    current_room_id = next_id
    if first_visit:
        rooms_entered += 1
    visited[next_id] = true
    projectiles.clear()

    # Emerge from the opposite door, just inside the arena.
    match direction:
        "W":
            player_position = Vector2(ARENA.end.x - 18.0, CENTER.y)
        "E":
            player_position = Vector2(ARENA.position.x + 18.0, CENTER.y)
        "N":
            player_position = Vector2(CENTER.x, ARENA.end.y - 18.0)
        "S":
            player_position = Vector2(CENTER.x, ARENA.position.y + 18.0)
    _spawn_enemy()
    message = "Room %d [%s] | %s | %d -> %d ticks" % [
        next_id, String(destination["kind"]), entry["reason"], int(entry["before"]), ticks
    ]

    if bool(entry["collapses"]):
        outcome = "collapsed"
        message = "THE FLOOR COLLAPSED! Press R to replay seed; N for a new seed."
    elif destination["kind"] == "exit":
        outcome = "escaped"
        message = "FLOOR CLEARED! Press R to replay seed; N for a new seed."


func _spawn_enemy() -> void:
    enemy.clear()
    var kind: String = String(_room()["kind"])
    if defeated.has(current_room_id) or not (kind == "normal" or kind == "boss"):
        return
    var max_hp: int = 11 if kind == "boss" else 3
    enemy = {
        "pos": CENTER + Vector2(112, -30),
        "hp": int(saved_enemy_hp.get(current_room_id, max_hp)),
        "max_hp": max_hp,
        "radius": 23.0 if kind == "boss" else 14.0,
        "speed": float(config.get("enemy_speed", 56.0)) * (0.75 if kind == "boss" else 1.0)
    }


func _fire() -> void:
    fire_cooldown = 0.20
    shots_fired += 1
    projectiles.append({
        "pos": player_position + aim_direction * 17.0,
        "velocity": aim_direction * BULLET_SPEED,
        "ttl": 1.8
    })


func _melee_attack() -> void:
    melee_cooldown = 0.44
    melee_flash = 0.16
    melee_swings += 1
    if enemy.is_empty():
        return
    var toward_enemy: Vector2 = enemy["pos"] - player_position
    if toward_enemy.length() <= 64.0 + float(enemy["radius"]):
        if aim_direction.dot(toward_enemy.normalized()) > 0.45:
            _hurt_enemy(2)


func _move_projectiles(delta: float) -> void:
    for index in range(projectiles.size() - 1, -1, -1):
        var bullet: Dictionary = projectiles[index]
        bullet["pos"] = Vector2(bullet["pos"]) + Vector2(bullet["velocity"]) * delta
        bullet["ttl"] = float(bullet["ttl"]) - delta
        var position: Vector2 = bullet["pos"]
        if float(bullet["ttl"]) <= 0.0 or not ARENA.has_point(position):
            projectiles.remove_at(index)
            continue
        if not enemy.is_empty():
            if position.distance_to(Vector2(enemy["pos"])) <= float(enemy["radius"]) + 5.0:
                _hurt_enemy(1)
                projectiles.remove_at(index)


func _hurt_enemy(amount: int) -> void:
    if enemy.is_empty():
        return
    enemy["hp"] = int(enemy["hp"]) - amount
    saved_enemy_hp[current_room_id] = int(enemy["hp"])
    if int(enemy["hp"]) <= 0:
        defeated[current_room_id] = true
        saved_enemy_hp.erase(current_room_id)
        enemy.clear()
        if current_room_id == int(floor["boss_id"]):
            boss_defeated = true
            message = "Boss defeated! The exit door is unlocked."
        else:
            message = "Enemy defeated. Room cleared."


func _move_enemy(delta: float) -> void:
    if enemy.is_empty():
        return
    var enemy_pos: Vector2 = enemy["pos"]
    var displacement: Vector2 = player_position - enemy_pos
    if displacement.length_squared() > 100.0:
        enemy_pos += displacement.normalized() * float(enemy["speed"]) * delta
    enemy_pos.x = clampf(enemy_pos.x, ARENA.position.x + 24.0, ARENA.end.x - 24.0)
    enemy_pos.y = clampf(enemy_pos.y, ARENA.position.y + 24.0, ARENA.end.y - 24.0)
    enemy["pos"] = enemy_pos
    if enemy_pos.distance_to(player_position) <= float(enemy["radius"]) + PLAYER_RADIUS + 5.0:
        if invincible_seconds <= 0.0:
            player_hp -= 1
            invincible_seconds = 1.1
            message = "Hit! %d HP remaining." % player_hp
            if player_hp <= 0:
                outcome = "defeated"
                message = "YOU DIED! Press R to replay seed; N for a new seed."


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("#101721"))
    _draw_room()
    _draw_combat()
    _draw_hud()
    if outcome != "running":
        draw_rect(Rect2(100, 198, 760, 123), Color(0.02, 0.03, 0.06, 0.93))
        var title := "FLOOR CLEARED" if outcome == "escaped" else "RUN ENDED: " + outcome.to_upper()
        _text(title, Vector2(326, 244), 24, Color("#f7d98b"))
        _text("Rooms: %d   Shots: %d   Melee swings: %d   Seed: %d" % [
            rooms_entered, shots_fired, melee_swings, initial_seed
        ], Vector2(242, 274), 15, Color.WHITE)
        _text("R = replay this seed     N = new seed", Vector2(323, 299), 14, Color.WHITE)


func _draw_room() -> void:
    var kind: String = String(_room()["kind"])
    var tiles: Color = Color("#263443")
    match kind:
        "boss":
            tiles = Color("#3b2635")
        "guild_hall":
            tiles = Color("#243d38")
        "exit":
            tiles = Color("#423926")

    draw_rect(ARENA, tiles)
    # Checkerboard gives scale/visual structure without art dependencies.
    for ix in range(25):
        for iy in range(10):
            if (ix + iy) % 2 == 0:
                var cell_pos := ARENA.position + Vector2(ix * 32.0, iy * 32.0)
                draw_rect(Rect2(cell_pos, Vector2(32, 32)), Color(1.0, 1.0, 1.0, 0.027))

    var wall := Color("#111821")
    draw_rect(Rect2(ARENA.position.x - 16, ARENA.position.y - 16, ARENA.size.x + 32, 16), wall)
    draw_rect(Rect2(ARENA.position.x - 16, ARENA.end.y, ARENA.size.x + 32, 16), wall)
    draw_rect(Rect2(ARENA.position.x - 16, ARENA.position.y, 16, ARENA.size.y), wall)
    draw_rect(Rect2(ARENA.end.x, ARENA.position.y, 16, ARENA.size.y), wall)

    var links: Dictionary = _room()["neighbors"]
    for direction in MOVE_LABELS:
        if not links.has(direction):
            continue
        var next_id: int = int(links[direction])
        var next_room: Dictionary = floor["rooms"][next_id]
        var preview: Dictionary = rules.evaluate(
            ticks, String(next_room["kind"]), not visited.has(next_id), next_id
        )
        var color: Color = Color("#69cca8")
        if next_room["kind"] == "guild_hall":
            color = Color("#7ac9ff")
        elif next_room["kind"] == "boss":
            color = Color("#f08282")
        elif next_room["kind"] == "exit":
            color = Color("#f4cd7b") if boss_defeated else Color("#bd5969")
        var width := DOOR_HALF_WIDTH * 2.0
        var bar: Rect2
        var label_pos: Vector2
        match direction:
            "N":
                bar = Rect2(CENTER.x - DOOR_HALF_WIDTH, ARENA.position.y - 16, width, 16)
                label_pos = Vector2(CENTER.x - 22, ARENA.position.y + 12)
            "S":
                bar = Rect2(CENTER.x - DOOR_HALF_WIDTH, ARENA.end.y, width, 16)
                label_pos = Vector2(CENTER.x - 22, ARENA.end.y - 6)
            "W":
                bar = Rect2(ARENA.position.x - 16, CENTER.y - DOOR_HALF_WIDTH, 16, width)
                label_pos = Vector2(ARENA.position.x + 4, CENTER.y + 4)
            _:
                bar = Rect2(ARENA.end.x, CENTER.y - DOOR_HALF_WIDTH, 16, width)
                label_pos = Vector2(ARENA.end.x - 45, CENTER.y + 4)
        draw_rect(bar, color)
        var change: int = int(preview["cost"]) - int(preview["grant"])
        _text("%s%+d" % [direction, -change], label_pos, 13, Color.WHITE)

    if kind == "guild_hall":
        draw_rect(Rect2(CENTER + Vector2(-30, -27), Vector2(60, 54)), Color("#3e9e8a"))
        _text("GUILD", CENTER + Vector2(-25, 5), 12, Color.WHITE)
    elif kind == "boss":
        _text("BOSS CHAMBER", Vector2(409, 160), 18, Color("#ffacbd"))
    elif kind == "exit":
        draw_rect(Rect2(CENTER + Vector2(-32, -30), Vector2(64, 60)), Color("#c49b52"))
        _text("EXIT", CENTER + Vector2(-20, 6), 15, Color("#151721"))


func _draw_combat() -> void:
    for projectile in projectiles:
        var point: Vector2 = projectile["pos"]
        draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), Color("#fce38a"))
    if not enemy.is_empty():
        var point: Vector2 = enemy["pos"]
        var radius: float = float(enemy["radius"])
        draw_rect(Rect2(point - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
            Color("#bb526d") if _room()["kind"] == "boss" else Color("#e18b68"))
        var hp_ratio: float = float(enemy["hp"]) / float(enemy["max_hp"])
        draw_rect(Rect2(point.x - 21.0, point.y - radius - 12.0, 42.0, 5.0), Color("#181a24"))
        draw_rect(Rect2(point.x - 21.0, point.y - radius - 12.0, 42.0 * hp_ratio, 5.0),
            Color("#a5d49b"))

    var player_color := Color("#8de5e2")
    if invincible_seconds > 0.0:
        player_color = Color("#ffffff")
    draw_rect(Rect2(player_position - Vector2(PLAYER_RADIUS, PLAYER_RADIUS),
        Vector2(PLAYER_RADIUS * 2.0, PLAYER_RADIUS * 2.0)), player_color)
    draw_line(player_position, player_position + aim_direction * 25.0, Color("#ffe0a1"), 3.0)
    if melee_flash > 0.0:
        draw_arc(player_position, 55.0, aim_direction.angle() - 0.70,
            aim_direction.angle() + 0.70, 12, Color("#f7e6a3"), 5.0)


func _draw_hud() -> void:
    var room: Dictionary = _room()
    _text("DCC GAME | GREYBOX", Vector2(18, 26), 20, Color("#f5dda2"))
    _text("SEED %d | ROOM %d (%s) | VISITED %d/%d" % [
        initial_seed, current_room_id, String(room["kind"]).to_upper(),
        visited.size(), (floor["rooms"] as Array).size()
    ], Vector2(18, 47), 14, Color("#e5eef8"))
    var tick_color := Color("#f3d18a") if ticks > 6 else Color("#fb8383")
    _text("COLLAPSE %d TICKS  |  HP %d  |  BOSS %s" % [
        ticks, player_hp, "CLEARED" if boss_defeated else "ACTIVE"
    ], Vector2(18, 70), 18, tick_color)
    _text(message, Vector2(18, 96), 12, Color("#b4d4e1"))
    _draw_minimap()
    _text("WASD / arrows: move  |  mouse: aim  |  left click: fire  |  space: melee",
        Vector2(18, 475), 15, Color("#e0e9f0"))
    _text("R: replay seed  |  N: new seed  |  Door labels preview tick change",
        Vector2(18, 498), 14, Color("#b8cfde"))
    _text("Boss defeats unlock exit.  Guild halls can grant ticks.  Settings: data/prototype_rules.json",
        Vector2(18, 521), 12, Color("#97d2b7"))


func _draw_minimap() -> void:
    draw_rect(Rect2(735, 5, 217, 104), Color("#202d38"))
    _text("MAP", Vector2(743, 21), 12, Color("#ccdde8"))
    var rooms: Array = floor["rooms"]
    var min_grid := Vector2i(999, 999)
    var max_grid := Vector2i(-999, -999)
    for room in rooms:
        var cell: Vector2i = room["grid"]
        min_grid.x = mini(min_grid.x, cell.x)
        min_grid.y = mini(min_grid.y, cell.y)
        max_grid.x = maxi(max_grid.x, cell.x)
        max_grid.y = maxi(max_grid.y, cell.y)
    var span_x: int = maxi(1, max_grid.x - min_grid.x + 1)
    var span_y: int = maxi(1, max_grid.y - min_grid.y + 1)
    var cell_size: float = minf(11.0, minf(196.0 / float(span_x), 77.0 / float(span_y)))
    for room in rooms:
        var room_id: int = int(room["id"])
        if not visited.has(room_id) and room_id != int(floor["exit_id"]):
            continue
        var cell: Vector2i = room["grid"]
        var position := Vector2(
            742.0 + float(cell.x - min_grid.x) * cell_size,
            25.0 + float(cell.y - min_grid.y) * cell_size
        )
        var color := Color("#718697")
        if room["kind"] == "guild_hall":
            color = Color("#7ec9da")
        elif room["kind"] == "boss":
            color = Color("#e88995")
        elif room["kind"] == "exit":
            color = Color("#e5cf86")
        if room_id == current_room_id:
            color = Color("#ffffff")
        draw_rect(Rect2(position, Vector2(maxf(3.0, cell_size - 2.0),
            maxf(3.0, cell_size - 2.0))), color)


func _text(value: String, position: Vector2, size: int, color: Color) -> void:
    draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
