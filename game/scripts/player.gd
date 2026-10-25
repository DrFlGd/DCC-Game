extends Node
## The crawler: movement with obstacle collision, aim, facing and timers.
##
## Plain Node holding world-space state (384x384 room pixels); RoomRenderer
## draws it. Input is read through Input Map actions defined in project.godot
## (move_*, fire, melee). Game decides *when* to call these methods, so the
## player never acts while a menu is open or the run has ended.
const Contents = preload("res://scripts/room_contents.gd")
const Layout = preload("res://scripts/room_layout.gd")

const RADIUS := 5.5
const DOOR_HALF := 16.0
const FIRE_COOLDOWN := 0.28
const MELEE_COOLDOWN := 0.50
const MELEE_FLASH := 0.17
const HIT_INVULNERABILITY := 0.8
const DEFAULT_SPEED := 105.0
## Distance from the wall where the player appears after a door transition.
const ENTRY_INSET := 21.0

var world_position := Layout.ARENA.get_center()
var aim_direction := Vector2.RIGHT
## 0..7, clockwise from east (E, SE, S, SW, W, NW, N, NE), matching the sheets.
var facing := 0
var speed := DEFAULT_SPEED
var fire_cooldown := 0.0
var melee_cooldown := 0.0
## Seconds left on the melee arc telegraph.
var melee_flash := 0.0
## Seconds of damage immunity left after being hit.
var invulnerability := 0.0


func reset(start: Vector2, move_speed: float = DEFAULT_SPEED) -> void:
    world_position = start
    aim_direction = Vector2.RIGHT
    facing = 0
    speed = move_speed
    fire_cooldown = 0.0
    melee_cooldown = 0.0
    melee_flash = 0.0
    invulnerability = 0.0


func tick_timers(delta: float) -> void:
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    melee_cooldown = maxf(0.0, melee_cooldown - delta)
    melee_flash = maxf(0.0, melee_flash - delta)
    invulnerability = maxf(0.0, invulnerability - delta)


## Movement vector from the move_* actions. Keyboard diagonals are normalised;
## analog sticks keep their magnitude (deadzone from the action settings).
func read_move_axis() -> Vector2:
    return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Moves by `change`, sliding along obstacles axis by axis. Returns the door
## direction ("N", "E", "S", "W") if the move would cross a doorway; in that
## case the player is not moved and Game decides whether the door opens.
func move(change: Vector2, blocked: Dictionary) -> String:
    var direction: String = door_crossed(world_position + change)
    if direction != "":
        return direction
    var horizontal := world_position + Vector2(change.x, 0.0)
    if Contents.can_occupy(horizontal, RADIUS, blocked):
        world_position.x = horizontal.x
    var vertical := world_position + Vector2(0.0, change.y)
    if Contents.can_occupy(vertical, RADIUS, blocked):
        world_position.y = vertical.y
    return ""


## Places the player just inside the door opposite to `direction`.
func enter_through(direction: String) -> void:
    var room: Rect2 = Layout.ARENA
    var mid: Vector2 = room.get_center()
    match direction:
        "N": world_position = Vector2(mid.x, room.end.y - ENTRY_INSET)
        "S": world_position = Vector2(mid.x, ENTRY_INSET)
        "W": world_position = Vector2(room.end.x - ENTRY_INSET, mid.y)
        "E": world_position = Vector2(ENTRY_INSET, mid.y)


## Aims at a world-space point (Game converts the mouse with Layout).
func aim_at(target: Vector2) -> void:
    var to_target: Vector2 = target - world_position
    if to_target.length_squared() > 9.0:
        aim_direction = to_target.normalized()
        facing = facing_from_vector(aim_direction)


## True (and starts the cooldown) when `fire` is held and the weapon is ready.
## Wave 2B: Game passes the equipped weapon's cooldown (attack profile).
func try_fire(cooldown: float = FIRE_COOLDOWN) -> bool:
    if not Input.is_action_pressed("fire") or fire_cooldown > 0.0:
        return false
    fire_cooldown = cooldown
    return true


## True (and starts the cooldown and arc telegraph) when `melee` is held and ready.
func try_melee(cooldown: float = MELEE_COOLDOWN) -> bool:
    if not Input.is_action_pressed("melee") or melee_cooldown > 0.0:
        return false
    melee_cooldown = cooldown
    melee_flash = MELEE_FLASH
    return true


func start_invulnerability() -> void:
    invulnerability = HIT_INVULNERABILITY


static func door_crossed(proposed: Vector2) -> String:
    var room: Rect2 = Layout.ARENA
    var mid: Vector2 = room.get_center()
    if proposed.x < RADIUS and absf(proposed.y - mid.y) <= DOOR_HALF:
        return "W"
    if proposed.x > room.end.x - RADIUS and absf(proposed.y - mid.y) <= DOOR_HALF:
        return "E"
    if proposed.y < RADIUS and absf(proposed.x - mid.x) <= DOOR_HALF:
        return "N"
    if proposed.y > room.end.y - RADIUS and absf(proposed.x - mid.x) <= DOOR_HALF:
        return "S"
    return ""


static func facing_from_vector(vector: Vector2) -> int:
    if vector.length_squared() < 0.0001:
        return 0
    return posmod(int(round(vector.angle() / (PI / 4.0))), 8)
