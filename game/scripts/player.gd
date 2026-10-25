extends Node
## The crawler: movement with obstacle collision, aim, facing and timers.
##
## Plain Node holding world-space state (384x384 room pixels); RoomRenderer
## draws it. Input is read through Input Map actions defined in project.godot
## (move_*, fire, melee, dodge). Game decides *when* to call these methods, so
## the player never acts while a menu is open or the run has ended.
##
## Wave 2D adds the dodge roll / dash state (start_dash, step_dash, i-frames in
## `dodge_iframes`) and attack phases (begin_attack: wind-up, active, recovery)
## that Combat.player_move_multiplier() turns into movement penalties. Stamina
## lives in RunState; Game spends it before calling start_dodge().
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
## Dodge defaults (COMBAT_AND_RPG §3); `feel.dodge` in prototype_rules.json
## overrides them through configure().
const DODGE_DISTANCE := 48.0
const DODGE_DURATION := 0.25
const DODGE_IFRAMES := 0.20
const DODGE_RECOVERY := 0.10
const DODGE_COST := 35.0
const DODGE_BUFFER := 0.12
## Melee/ranged phase defaults while 2B's weapon patterns are not in yet:
## the prototype swing resolves instantly, so it has no wind-up.
const MELEE_ACTIVE := 0.10
const MELEE_RECOVERY := 0.18
const RANGED_RECOVERY := 0.28

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

# Dodge roll / dash (Wave 2D).
## Seconds left in the current roll or dash (0 when not dashing).
var dodge_time := 0.0
var dodge_length := 0.0
var dodge_distance := 0.0
var dodge_direction := Vector2.ZERO
## Fraction of the dash distance already travelled (ease-out curve).
var dodge_progress := 0.0
## Dodge i-frames, separate from hit `invulnerability` (the `evasive` status).
var dodge_iframes := 0.0
## Recovery after a roll: no dodge, no attack.
var dodge_recovery := 0.0
## Recovery the current dash applies when it ends.
var dodge_recovery_length := 0.0
## Minimum-gap timer from the content stat `dodge_cooldown`.
var dodge_cooldown := 0.0
## Tunables (configure()). `dodge_gap` is the `dodge_cooldown` stat (s); the
## items team may raise it from loadout modifiers.
var dodge_cost := DODGE_COST
var dodge_gap := 0.0
var dodge_settings := {"distance": DODGE_DISTANCE, "duration": DODGE_DURATION,
    "iframes": DODGE_IFRAMES, "recovery": DODGE_RECOVERY, "buffer": DODGE_BUFFER}
## A dodge press is remembered for `buffer` s so a press during recovery fires.
var dodge_buffer := 0.0

# Attack phases (Wave 2D, COMBAT_AND_RPG §3/§4.1).
## Pattern of the attack in progress: "arc", "thrust", "spin", "ranged", or ""
## (the weapon `attack_pattern`; ranged patterns all read as "ranged").
var attack_pattern := ""
var attack_windup := 0.0
var attack_active := 0.0
var attack_recovery := 0.0
var attack_timing := {"melee_active": MELEE_ACTIVE, "melee_recovery": MELEE_RECOVERY,
    "ranged_recovery": RANGED_RECOVERY}


func reset(start: Vector2, move_speed: float = DEFAULT_SPEED) -> void:
    world_position = start
    aim_direction = Vector2.RIGHT
    facing = 0
    speed = move_speed
    fire_cooldown = 0.0
    melee_cooldown = 0.0
    melee_flash = 0.0
    invulnerability = 0.0
    cancel_dash()
    dodge_iframes = 0.0
    dodge_recovery = 0.0
    dodge_cooldown = 0.0
    dodge_buffer = 0.0
    attack_pattern = ""
    attack_windup = 0.0
    attack_active = 0.0
    attack_recovery = 0.0


## Applies `feel` from prototype_rules.json (dodge and attack timing).
func configure(feel: Dictionary) -> void:
    var dodge: Dictionary = feel.get("dodge", {})
    for key in dodge_settings.keys():
        dodge_settings[key] = float(dodge.get(key, dodge_settings[key]))
    dodge_cost = float(dodge.get("cost", DODGE_COST))
    dodge_gap = float(dodge.get("cooldown", 0.0))
    var timing: Dictionary = feel.get("attack_timing", {})
    for key in attack_timing.keys():
        attack_timing[key] = float(timing.get(key, attack_timing[key]))


func tick_timers(delta: float) -> void:
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    melee_cooldown = maxf(0.0, melee_cooldown - delta)
    melee_flash = maxf(0.0, melee_flash - delta)
    invulnerability = maxf(0.0, invulnerability - delta)
    dodge_iframes = count_down(dodge_iframes, delta)
    if dodge_time <= 0.0:
        dodge_recovery = count_down(dodge_recovery, delta)
    dodge_cooldown = count_down(dodge_cooldown, delta)
    dodge_buffer = count_down(dodge_buffer, delta)
    _tick_attack(delta)


## `value - delta`, clamped at 0 and snapped to 0 within a microsecond so
## frame-sized steps end timers on the expected frame.
static func count_down(value: float, delta: float) -> float:
    var left: float = value - delta
    return 0.0 if left <= 0.000001 else left


## Wind-up, then active, then recovery; leftover time carries into the next phase.
func _tick_attack(delta: float) -> void:
    var left: float = delta
    if attack_windup > 0.0:
        var used: float = minf(left, attack_windup)
        attack_windup -= used
        left -= used
    if left > 0.0 and attack_active > 0.0:
        var used: float = minf(left, attack_active)
        attack_active -= used
        left -= used
    if left > 0.0 and attack_recovery > 0.0:
        attack_recovery = maxf(0.0, attack_recovery - left)
    if attack_windup <= 0.0 and attack_active <= 0.0 and attack_recovery <= 0.0:
        attack_pattern = ""


## Starts an attack's phases. 2B's weapon patterns call this with the weapon's
## `windup` / `active` / `recovery`; the prototype attacks call it from
## try_fire / try_melee.
func begin_attack(pattern: String, windup: float, active: float, recovery: float) -> void:
    attack_pattern = pattern
    attack_windup = maxf(0.0, windup)
    attack_active = maxf(0.0, active)
    attack_recovery = maxf(0.0, recovery)


## "windup", "active", "recovery" or "" (no attack in progress).
func attack_phase() -> String:
    if attack_windup > 0.0:
        return "windup"
    if attack_active > 0.0:
        return "active"
    if attack_recovery > 0.0:
        return "recovery"
    return ""


# --- Dodge roll / dash (Wave 2D) ------------------------------------------------

func is_dodging() -> bool:
    return dodge_time > 0.0


## Hit i-frames or dodge i-frames.
func is_invulnerable() -> bool:
    return invulnerability > 0.0 or dodge_iframes > 0.0


## True when a dodge could start now (stamina is RunState's check): not
## dashing or recovering, no minimum-gap timer, and no attack wind-up or active
## frames. Attack recovery does not block; the dodge cancels it.
func can_dodge() -> bool:
    return dodge_time <= 0.0 and dodge_recovery <= 0.0 and dodge_cooldown <= 0.0 \
        and attack_windup <= 0.0 and attack_active <= 0.0


## Dodge direction: the movement input, or the aim when standing still.
func dodge_direction_for(move_axis: Vector2) -> Vector2:
    if move_axis.length_squared() > 0.01:
        return move_axis.normalized()
    return aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else Vector2.RIGHT


## Starts a dodge roll with the configured distance, duration, i-frames and
## recovery. Returns the roll direction. Game checks can_dodge() and spends
## the stamina first.
func start_dodge(move_axis: Vector2) -> Vector2:
    var direction: Vector2 = dodge_direction_for(move_axis)
    start_dash(direction, float(dodge_settings["distance"]), float(dodge_settings["duration"]),
        float(dodge_settings["iframes"]), float(dodge_settings["recovery"]))
    dodge_cooldown = dodge_gap
    return direction


## Generic dash (dodge roll, or a skill such as a charge): moves `distance` px
## along `direction` over `duration` s on an ease-out curve, i-framed for the
## first `iframes` s, then `recovery` s with no dodge or attack. Cancels attack
## recovery. Movement still collides with obstacles and slides along walls
## (Game moves the crawler with step_dash() through move()).
func start_dash(direction: Vector2, distance: float, duration: float, iframes: float = 0.0,
        recovery: float = 0.0) -> void:
    dodge_direction = direction.normalized() if direction.length_squared() > 0.0001 else aim_direction
    dodge_distance = maxf(0.0, distance)
    dodge_length = maxf(0.01, duration)
    dodge_time = dodge_length
    dodge_progress = 0.0
    dodge_iframes = maxf(dodge_iframes, iframes)
    dodge_recovery_length = maxf(0.0, recovery)
    dodge_recovery = 0.0
    dodge_buffer = 0.0
    attack_recovery = 0.0
    if attack_windup <= 0.0 and attack_active <= 0.0:
        attack_pattern = ""
    facing = facing_from_vector(dodge_direction)


## Displacement for this frame of the dash; starts the recovery when it ends.
func step_dash(delta: float) -> Vector2:
    if dodge_time <= 0.0:
        return Vector2.ZERO
    dodge_time = count_down(dodge_time, delta)
    var t: float = 1.0 - dodge_time / dodge_length
    var progress: float = 1.0 - (1.0 - t) * (1.0 - t)
    var change: Vector2 = dodge_direction * dodge_distance * (progress - dodge_progress)
    dodge_progress = progress
    if dodge_time <= 0.0:
        dodge_recovery = dodge_recovery_length
    return change


func cancel_dash() -> void:
    dodge_time = 0.0
    dodge_progress = 0.0
    dodge_direction = Vector2.ZERO


## Attacks wait while dashing and during the dash recovery.
func attack_locked() -> bool:
    return dodge_time > 0.0 or dodge_recovery > 0.0


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
    cancel_dash()
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
    if not Input.is_action_pressed("fire") or fire_cooldown > 0.0 or attack_locked():
        return false
    fire_cooldown = cooldown
    begin_attack("ranged", 0.0, 0.0, float(attack_timing["ranged_recovery"]))
    return true


## True (and starts the cooldown and arc telegraph) when `melee` is held and ready.
## Wave 2B: `cooldown` and `pattern` ("arc", "thrust", "spin") come from the
## equipped melee weapon's attack profile.
func try_melee(cooldown: float = MELEE_COOLDOWN, pattern: String = "melee") -> bool:
    if not Input.is_action_pressed("melee") or melee_cooldown > 0.0 or attack_locked():
        return false
    melee_cooldown = cooldown
    melee_flash = MELEE_FLASH
    begin_attack(pattern, 0.0, float(attack_timing["melee_active"]),
        float(attack_timing["melee_recovery"]))
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
