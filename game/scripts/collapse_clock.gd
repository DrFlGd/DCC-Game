extends Node
## CollapseClock: drives the zero-clock outcome (COLLAPSE_SYSTEM §6, D-05).
##
## Child of Game (created by Game._ready). It listens to `Events.ticks_changed`
## so every way of reaching 0 is covered: door transitions
## (RunState.apply_tick_entry) and everything else (RunState.add_ticks:
## hazards, items, skills). The rules themselves are the pure grace_* functions
## in collapse_policy.gd; this node owns the timer, the debris spawns and the
## hard collapse.
##
## - Reaching 0 (not via the exit) starts grace: 10 s, then 5 s for the second
##   on a floor; a third zero collapses at once (`collapse.grace.*`).
## - Any tick gain during grace stabilises the floor.
## - The timer reaching 0 is a hard collapse: Game ends the run "collapsed".
## - update() is only called while Game is RUNNING, so modals (pause, level-up,
##   map, shrine) freeze the timer and the debris with the rest of the world.
const Collapse = preload("res://scripts/collapse_policy.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Contents = preload("res://scripts/room_contents.gd")

const COLLAPSE_TEXT := "THE FLOOR COLLAPSED! R = repeat, N = new seed"

var game
## collapse.grace with defaults (CollapsePolicy.grace_config).
var config: Dictionary = Collapse.grace_config({})
## Debris placement RNG, reseeded at each grace start from the floor seed.
var rng := RandomNumberGenerator.new()
## Shake amplitude (px) of the current wave, for the renderer. 0 outside grace.
var shake := 0.0
var _in_transition := false
var _exit_transition := false
var _zero_pending := false


func setup(game_node) -> void:
    game = game_node
    if not Events.ticks_changed.is_connected(_on_ticks_changed):
        Events.ticks_changed.connect(_on_ticks_changed)
    if not Events.player_died.is_connected(_on_player_died):
        Events.player_died.connect(_on_player_died)
    if not Events.room_cleared.is_connected(_on_room_cleared):
        Events.room_cleared.connect(_on_room_cleared)


## Called by Game at every floor start (after RunState.reset_for_floor()).
func reset_floor() -> void:
    config = Collapse.grace_config(RunState.config.get("collapse", {}))
    RunState.grace = Collapse.grace_initial()
    shake = 0.0
    _in_transition = false
    _exit_transition = false
    _zero_pending = false


## Brackets a door transition so a zero reached on entry is resolved after the
## room swap (and never for the exit, which resolves before collapse).
func begin_transition(to_exit: bool) -> void:
    _in_transition = true
    _exit_transition = to_exit
    _zero_pending = false


func end_transition() -> void:
    _in_transition = false
    _exit_transition = false
    if _zero_pending:
        _zero_pending = false
        _on_zero()


## The exit was reached: an active grace ends without stabilising.
func resolve_exit() -> void:
    if RunState.grace_active():
        _finish("exit", false)


## Doors stay unlocked during grace (hook for the D-07 door lock, Wave 2D).
func doors_unlocked() -> bool:
    return RunState.grace_active()


## Advances the grace timer and spawns debris waves. Game calls this from
## _physics_process only while RUNNING.
func update(delta: float) -> void:
    if not RunState.grace_active() or RunState.outcome != "running":
        return
    var remaining_before: float = float(RunState.grace["remaining"])
    var step: Dictionary = Collapse.grace_advance(RunState.grace, delta, config)
    var wave: Dictionary = step["wave"]
    if not wave.is_empty():
        shake = float(wave.get("shake", 0.0))
    for index in range(int(step["markers"])):
        _spawn_debris(index == 0, {"wave_markers": int(step["markers"]),
            "grace_remaining": remaining_before})
    if bool(step["expired"]):
        shake = 0.0
        Events.grace_ended.emit(false)
        _hard_collapse()


func _on_ticks_changed(before: int, after: int, _reason: String) -> void:
    if RunState.outcome != "running":
        return
    if before > 0 and after == 0:
        if _exit_transition:
            return
        if _in_transition:
            _zero_pending = true
            return
        _on_zero()
    elif after > before and RunState.grace_active():
        _finish("stabilised", true)
        Events.say("Clock stabilised: %d ticks. The ceiling reconsiders." % after, "collapse")


func _on_zero() -> void:
    if RunState.outcome != "running":
        return
    if Collapse.grace_on_zero(RunState.grace, config) == "collapse":
        _hard_collapse()
        return
    var seconds: float = float(RunState.grace["duration"])
    rng.seed = int(RunState.floor_seed()) * 31 + int(RunState.grace["count"]) * 7349 + 977
    Events.grace_started.emit(seconds)
    Events.say("COLLAPSE IMMINENT: %d seconds. Doors unlocked. Run." % int(seconds), "collapse")


func _finish(outcome: String, stabilised: bool) -> void:
    Collapse.grace_finish(RunState.grace, outcome)
    shake = 0.0
    Events.grace_ended.emit(stabilised)


func _hard_collapse() -> void:
    RunState.grace["outcome"] = "collapse"
    RunState.grace["active"] = false
    if game != null:
        game._end_run("collapsed", COLLAPSE_TEXT, "collapse on floor %d" % RunState.depth)


func _on_player_died(_cause: String) -> void:
    if RunState.grace_active():
        _finish("death", false)


## Elite rooms (and `default.clear_refund`) give ticks back on clear.
func _on_room_cleared(room_id: int) -> void:
    if game == null or game.rules == null or RunState.floor.is_empty():
        return
    var kind: String = String(RunState.floor["rooms"][room_id]["kind"])
    var amount: int = game.rules.clear_grant(kind)
    if amount > 0:
        RunState.add_ticks(amount, "room_clear")
        Events.say("%s room cleared: +%d tick%s." % [kind.capitalize(), amount,
            "" if amount == 1 else "s"], "collapse")


## One debris marker: the first of a wave lands on the crawler, the rest on
## random walkable cells of the current room.
func _spawn_debris(on_player: bool, extra: Dictionary) -> void:
    if game == null:
        return
    var settings: Dictionary = config.get("debris", {})
    var position: Vector2 = game.player.world_position
    if not on_player:
        var blocked: Dictionary = game.combat.blocked()
        for _attempt in range(40):
            var cell := Vector2i(rng.randi_range(1, Contents.SIZE - 2),
                rng.randi_range(1, Contents.SIZE - 2))
            if Contents.is_walkable(cell, blocked):
                position = Contents.cell_center(cell)
                break
    extra.merge({"hits_enemies": bool(settings.get("hits_enemies", true)),
        "color": Color("#d9a066")}, true)
    game.combat.spawn_hazard(Hazards.make("debris", position,
        float(settings.get("radius", 14.0)), float(settings.get("telegraph", 0.8)),
        int(settings.get("damage", 2)), float(settings.get("duration", 0.15)),
        "hazard:debris", extra))
