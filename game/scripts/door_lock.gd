extends Node
## DoorLock: the D-07 door lock (COMBAT_AND_RPG §9, GAME_DESIGN §3.3).
##
## Child of Game (created by Game._ready, like CollapseClock). Game calls
## update() every simulated RUNNING frame and asks is_locked() before a door
## transition; RoomRenderer reads `visual` to draw sealed doors and the HUD
## shows prompt().
##
## - Locking kinds (`feel.door_lock.locking_kinds`): normal, elite, boss, and
##   trap when it holds hostiles. start / guild_hall / exit / treasure /
##   shrine never lock.
## - Doors seal `delay` (0.5 s) after entry, once the crawler is `inset`
##   (24 px) away from every doorway of the room.
## - They open on `room_cleared` (summons count: Combat only clears the room
##   when summoner and summons are all dead), whenever the collapse grace runs
##   (CollapseClock.doors_unlocked() wins over the lock), and through the
##   failsafe: `failsafe_seconds` (15 s) in which no hostile has a grid path to
##   the crawler and no damage was dealt either way despawns them, with no XP,
##   a push_warning and the `failsafe_despawns` telemetry counter.
## - Clearing a locking room is the room-clear moment: a forced hit-stop, the
##   HUD "ROOM CLEAR" flourish, the doors fading open and the announcer's
##   `room_cleared` line.
const Enemies = preload("res://scripts/enemy_system.gd")
const Contents = preload("res://scripts/room_contents.gd")

const DEFAULTS := {"delay": 0.5, "inset": 24.0, "failsafe_seconds": 15.0,
    "locking_kinds": ["normal", "elite", "boss", "trap"]}
const NEVER_LOCK := ["start", "guild_hall", "exit", "treasure", "shrine"]
const PROMPT := "Sealed until clear"
const PATH_CHECK_SECONDS := 0.25
const BUMP_SECONDS := 1.2
## Seconds for the door tint to fade in (sealing) and out (opening).
const CLOSE_FADE := 0.15
const OPEN_FADE := 0.5

var game
var config: Dictionary = DEFAULTS.duplicate(true)
var room_id := -1
var kind := ""
## The current room locks: its kind locks and it held hostiles on entry.
var lockable := false
var locked := false
var since_entry := 0.0
## Seconds of "no path and no damage" so far (failsafe).
var failsafe := 0.0
## 0 = open .. 1 = sealed; animated toward is_locked() for the renderer.
var visual := 0.0
## Seconds the "Sealed until clear" prompt stays up after bumping a door.
var bump := 0.0
var _path_timer := 0.0
var _unreachable := false
var _damage_seen := false


func setup(game_node) -> void:
    game = game_node
    config = DEFAULTS.duplicate(true)
    config.merge(RunState.config.get("feel", {}).get("door_lock", {}), true)
    _connect(Events.room_entered, _on_room_entered)
    _connect(Events.room_cleared, _on_room_cleared)
    _connect(Events.grace_started, _on_grace_started)
    _connect(Events.enemy_damaged, _on_enemy_damaged)
    _connect(Events.player_damaged, _on_player_damaged)


## True when a room of `kind` holding `enemies` locks its doors.
static func kind_locks(room_kind: String, enemies: Array, kinds: Array) -> bool:
    if NEVER_LOCK.has(room_kind) or not kinds.has(room_kind):
        return false
    for foe in enemies:
        if int(foe.get("hp", 0)) > 0:
            return true
    return false


## True when `pos` is at least `inset` px from every linked doorway.
static func is_inside(pos: Vector2, links: Dictionary, inset: float) -> bool:
    for direction in links.keys():
        var portal: Vector2 = Enemies.PORTAL_CENTERS.get(String(direction), Vector2.INF)
        if portal != Vector2.INF and pos.distance_to(portal) < inset:
            return false
    return true


## True when no enemy in `enemies` has a grid path (4-neighbour, plain
## walkable cells, as the enemy pathfinder's fallback) to the crawler's cell.
static func hostiles_unreachable(enemies: Array, blocked: Dictionary, player_pos: Vector2) -> bool:
    var start: Vector2i = Contents.cell_of(player_pos)
    if not Contents.is_walkable(start, blocked):
        return false
    var reach: Dictionary = Enemies.flood(blocked, [start], 0.0)
    for foe in enemies:
        var cell: Vector2i = Contents.cell_of(Vector2(foe["pos"]))
        if reach.has(cell):
            return false
        for step in Contents.DIRECTIONS:
            if reach.has(cell + step):
                return false
    return true


## Doors are sealed now (grace always opens them).
func is_locked() -> bool:
    if not locked:
        return false
    return game == null or game.clock == null or not game.clock.doors_unlocked()


## HUD prompt while the crawler pushes against a sealed door.
func prompt() -> String:
    return PROMPT if bump > 0.0 and is_locked() else ""


## Game calls this when a transition was refused because the doors are sealed.
func bump_door() -> void:
    if bump <= 0.0:
        Events.say("Sealed until clear.", "combat")
    bump = BUMP_SECONDS


## Advances the lock, the failsafe and the door animation. Game calls this
## only while RUNNING and outside hit-stop.
func update(delta: float) -> void:
    bump = maxf(0.0, bump - delta)
    var target: float = 1.0 if is_locked() else 0.0
    var fade: float = CLOSE_FADE if target > visual else OPEN_FADE
    visual = move_toward(visual, target, delta / fade)
    if not lockable or game == null or RunState.current_room_id != room_id:
        return
    var foes: Array = RunState.current_room().get("enemies", [])
    if foes.is_empty():
        lockable = false
        if locked:
            _unlock("cleared")
        return
    if RunState.grace_active():
        if locked:
            _unlock("grace")
        return
    since_entry += delta
    if not locked:
        var links: Dictionary = RunState.floor["rooms"][room_id]["neighbors"]
        if since_entry >= float(config["delay"]) and is_inside(game.player.world_position,
                links, float(config["inset"])):
            _lock()
        return
    _update_failsafe(delta, foes)


func _update_failsafe(delta: float, foes: Array) -> void:
    _path_timer -= delta
    if _path_timer <= 0.0:
        _path_timer = PATH_CHECK_SECONDS
        _unreachable = hostiles_unreachable(foes, RunState.current_room().get("blocked", {}),
            game.player.world_position)
    if _damage_seen or not _unreachable:
        _damage_seen = false
        failsafe = 0.0
        return
    failsafe += delta
    if failsafe >= float(config["failsafe_seconds"]):
        _despawn(foes)


## Failsafe: removes every remaining hostile (no XP, no enemy_killed), logs it
## as a generator bug and opens the doors. A stuck boss still unlocks the exit.
func _despawn(foes: Array) -> void:
    var count: int = foes.size()
    var names: PackedStringArray = []
    for foe in foes:
        names.append(String(foe.get("definition", "?")))
        if bool(foe.get("boss", false)) and not RunState.boss_defeated:
            RunState.boss_defeated = true
            Events.boss_defeated.emit(String(foe["definition"]))
    foes.clear()
    push_warning("DoorLock failsafe: room %d (%s, floor seed %d) had %d unreachable hostiles %s; despawned." % [
        room_id, kind, RunState.floor_seed(), count, names])
    RunState.record_failsafe_despawn(count)
    Events.say("The System removed %d stuck hostile%s. No XP, no refunds." % [count,
        "" if count == 1 else "s"], "combat")
    failsafe = 0.0
    lockable = false
    _unlock("failsafe")


func _lock() -> void:
    locked = true
    failsafe = 0.0
    _path_timer = 0.0
    _damage_seen = false
    Events.doors_locked.emit(room_id)
    Events.say("Doors sealed. Clear the room.", "combat")


func _unlock(reason: String) -> void:
    locked = false
    Events.doors_unlocked.emit(room_id, reason)


func _on_room_entered(id: int, room_kind: String, _entry: Dictionary, _first: bool) -> void:
    room_id = id
    kind = room_kind
    lockable = kind_locks(room_kind, RunState.current_room().get("enemies", []),
        config["locking_kinds"])
    locked = false
    since_entry = 0.0
    failsafe = 0.0
    visual = 0.0
    bump = 0.0
    _path_timer = 0.0
    _unreachable = false
    _damage_seen = false


## The room-clear moment (locking rooms only).
func _on_room_cleared(id: int) -> void:
    if id != room_id:
        return
    var moment: bool = lockable
    lockable = false
    if locked:
        _unlock("cleared")
    if not moment or game == null:
        return
    game.combat.fx.hitstop_for("room_clear")
    if game.hud != null and game.hud.has_method("show_room_clear"):
        game.hud.show_room_clear()
    Events.announcement_requested.emit("room_cleared", {})


func _on_grace_started(_seconds: float) -> void:
    if locked:
        _unlock("grace")


func _on_enemy_damaged(_instance_id: String, _amount: int, _critical: bool) -> void:
    _damage_seen = true


func _on_player_damaged(_amount: int, _source: String) -> void:
    _damage_seen = true


func _connect(event: Signal, handler: Callable) -> void:
    if not event.is_connected(handler):
        event.connect(handler)
