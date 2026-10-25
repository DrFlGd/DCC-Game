extends Node2D
## Game: run orchestrator and state machine on the root node of Main.tscn.
##
## Owns floor generation, room loading, door transitions (collapse evaluation,
## exit gate), restarts, the F9 debug shortcut and CharacterMenu wiring. It
## composes the Player, Combat, RoomRenderer, Hud and CharacterMenu children
## (from Main.tscn, or created here when Game is instanced from script).
## All run data lives in the `RunState` autoload; cross-system notifications go
## through the `Events` autoload. Game reacts to enemy_killed (XP, boss gate),
## level_up (modal) and player_died (defeat).
signal state_changed(previous: int, current: int)

## RUNNING: simulation ticks. LEVEL_UP / PAUSED: CharacterMenu is modal and the
## world is frozen. ENDED: outcome overlay, waiting for R / N.
## Wave 2A appends TITLE (before start_run) and SUMMARY (after ENDED); append
## new states at the end so existing values stay stable.
enum State { RUNNING, LEVEL_UP, PAUSED, ENDED }

const Generator = preload("res://scripts/floor_generator.gd")
const Collapse = preload("res://scripts/collapse_policy.gd")
const Layout = preload("res://scripts/room_layout.gd")
const Contents = preload("res://scripts/room_contents.gd")
const Enemies = preload("res://scripts/enemy_system.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const CharacterMenu = preload("res://scripts/character_menu.gd")
const Player = preload("res://scripts/player.gd")
const Combat = preload("res://scripts/combat.gd")
const RoomRenderer = preload("res://scripts/room_renderer.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Announcer = preload("res://scripts/ui/announcer.gd")

## World room bounds; never changes with window size.
const ROOM := Layout.ARENA
## Enemy definition whose death unlocks the exit.
## TODO(enemies team): replace with a data-driven "boss" flag in enemies.json.
const BOSS_DEFINITION := "armored_brute"

var state: State = State.RUNNING
var catalogue: Dictionary = {}
## CollapsePolicy for the current run (rebuilt from RunState.config each run).
var rules
var layout: Dictionary = {}
var player: Player
var combat: Combat
var renderer: RoomRenderer
var hud: Hud
var character_menu: CharacterMenu
## Dungeon-system announcer, achievements, profile and telemetry (Wave 2G).
var announcer: Announcer


func _ready() -> void:
    if not RunState.load_config():
        get_tree().quit(1)
        return
    catalogue = Enemies.load_catalogue()
    var problems: Array[String] = Enemies.validate_catalogue(catalogue)
    if not problems.is_empty():
        push_error("Invalid enemy definitions: %s" % [problems])
        get_tree().quit(1)
        return
    renderer = _ensure_child("RoomRenderer", RoomRenderer) as RoomRenderer
    player = _ensure_child("Player", Player) as Player
    combat = _ensure_child("Combat", Combat) as Combat
    hud = _ensure_child("Hud", Hud) as Hud
    character_menu = _ensure_child("CharacterMenu", CharacterMenu) as CharacterMenu
    announcer = _ensure_child("Announcer", Announcer) as Announcer
    combat.setup(player, catalogue)
    renderer.setup(player, combat, null, catalogue)
    _relayout()
    character_menu.allocation_confirmed.connect(_confirm_stat_allocation)
    character_menu.resume_requested.connect(_on_resume_game)
    character_menu.resolution_requested.connect(_apply_resolution)
    Events.enemy_killed.connect(_on_enemy_killed)
    Events.level_up.connect(_on_level_up)
    Events.player_died.connect(_on_player_died)
    start_run(int(RunState.config.get("seed", RunState.DEFAULT_SEED)))


func _ensure_child(child_name: String, script: Script) -> Node:
    var node: Node = get_node_or_null(child_name)
    if node == null:
        node = script.new()
        node.name = child_name
        add_child(node)
    return node


## Starts a fresh run on floor 1. Same seed + same inputs = same run.
func start_run(new_seed: int) -> void:
    RunState.start_run(new_seed)
    rules = Collapse.new(RunState.config.get("collapse", {}))
    renderer.rules = rules
    combat.clear_projectiles()
    player.reset(ROOM.get_center(), float(RunState.config.get("player_speed", Player.DEFAULT_SPEED)))
    character_menu.close_menu()
    _start_floor(1)
    var budget: int = Collapse.mandatory_budget_floor(RunState.floor, rules)
    var text := "24x24 fixed room | Seed %d | budget diagnostic %d ticks" % [RunState.seed, budget]
    print(text)
    Events.say(text, "info")
    _change_state(State.RUNNING)


## Generates floor `depth` and places the player in its start room.
## TODO(Wave 2): call with depth + 1 from the exit instead of ending the run.
func _start_floor(depth: int) -> void:
    RunState.reset_for_floor(depth)
    var generated: Dictionary = Generator.generate(RunState.floor_seed(),
        int(RunState.config.get("room_count", 22)))
    RunState.floor = generated
    var start_id: int = int(generated["start_id"])
    RunState.current_room_id = start_id
    RunState.visited[start_id] = true
    _load_room(start_id)
    Events.floor_started.emit(depth, generated)
    Events.room_entered.emit(start_id, String(generated["rooms"][start_id]["kind"]), {}, true)


## Generates (first visit) or restores the persisted contents of room `id`.
func _load_room(id: int) -> void:
    if RunState.room_states.has(id):
        return
    var room: Dictionary = RunState.floor["rooms"][id]
    var floor_seed: int = RunState.floor_seed()
    var contents: Dictionary = Contents.generate(floor_seed, id, room["neighbors"],
        String(room["kind"]), int(RunState.config.get("obstacle_count", 38)))
    var encounter: Array[Dictionary] = Enemies.generate_encounter(catalogue,
        String(room["kind"]), floor_seed, id, contents["blocked"])
    RunState.room_states[id] = {"blocked": contents["blocked"], "props": contents["props"],
        "enemies": encounter}


## Tries the door on side `direction` of the current room: exit gate, collapse
## cost, ledger, room swap, then collapse/escape outcome.
func _enter_neighbor(direction: String) -> void:
    var room: Dictionary = RunState.floor["rooms"][RunState.current_room_id]
    if not room["neighbors"].has(direction):
        return
    var next_id: int = int(room["neighbors"][direction])
    var next_room: Dictionary = RunState.floor["rooms"][next_id]
    var kind: String = String(next_room["kind"])
    if kind == "exit" and not RunState.boss_defeated:
        Events.say("EXIT SEALED: defeat the boss before descending.", "collapse")
        return
    var first_visit: bool = not RunState.visited.has(next_id)
    var entry: Dictionary = rules.evaluate(RunState.ticks, kind, first_visit, next_id)
    if not bool(entry["allowed"]):
        Events.say("Not enough collapse ticks for that doorway.", "collapse")
        return
    RunState.apply_tick_entry(entry)
    RunState.current_room_id = next_id
    RunState.visited[next_id] = true
    combat.clear_projectiles()
    player.enter_through(direction)
    _load_room(next_id)
    Events.say("Room %d [%s] | %s | %d ticks left" % [
        next_id, kind, String(entry["reason"]), RunState.ticks], "collapse")
    print("COLLAPSE LEDGER ", entry)
    Events.room_entered.emit(next_id, kind, entry, first_visit)
    if bool(entry["collapses"]):
        _end_run("collapsed", "THE FLOOR COLLAPSED! R = repeat, N = new seed")
    elif kind == "exit":
        Events.floor_cleared.emit(RunState.depth)
        _end_run("escaped", "FLOOR CLEARED! R = repeat, N = new seed")


func _end_run(outcome: String, text: String) -> void:
    _change_state(State.ENDED)
    Events.say(text, "outcome")
    RunState.end_run(outcome)


func _change_state(next: State) -> void:
    if next == state:
        return
    var previous: State = state
    state = next
    state_changed.emit(previous, next)


func _physics_process(delta: float) -> void:
    if get_viewport_rect().size != Vector2(layout["viewport"]):
        _relayout()
    if state != State.RUNNING:
        _redraw()
        return
    RunState.advance_clock(delta)
    player.tick_timers(delta)
    var door: String = player.move(player.read_move_axis() * player.speed * delta,
        combat.blocked())
    if door != "":
        _enter_neighbor(door)
    if state != State.RUNNING:
        _redraw()
        return
    player.aim_at(Layout.screen_to_world(get_global_mouse_position(), layout))
    if player.try_fire():
        combat.player_fire()
    if player.try_melee():
        combat.player_melee()
    combat.update_projectiles(delta)
    # A kill above may have opened the level-up modal; enemies freeze with it.
    if state == State.RUNNING:
        combat.update_enemies(delta)
    _redraw()


func _redraw() -> void:
    renderer.queue_redraw()
    hud.refresh()


func _relayout() -> void:
    layout = Layout.compute(get_viewport_rect().size)
    renderer.layout = layout
    hud.layout = layout


func _input(event: InputEvent) -> void:
    if not event.is_action_pressed("pause"):
        return
    if character_menu.mode == "pause":
        character_menu.close_menu()
        _change_state(State.RUNNING)
    elif character_menu.mode == "closed" and RunState.outcome == "running":
        character_menu.show_pause(RunState.ability_scores, _character_context())
        _change_state(State.PAUSED)
    get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
    if character_menu != null and character_menu.is_open():
        return
    if event.is_action_pressed("restart_seed"):
        start_run(RunState.seed)
    elif event.is_action_pressed("new_seed"):
        start_run(int(Time.get_ticks_usec() % 2147483647))
    elif event.is_action_pressed("debug_level_up") and RunState.outcome == "running" \
            and RunState.level < 20:
        # Prototype playtest shortcut: jump to the next XP threshold.
        RunState.award_xp(maxi(0, RPG.next_level_xp(RunState.level) - RunState.xp))


func _character_context() -> Dictionary:
    var context: Dictionary = RunState.progression_context()
    context["window_size"] = get_window().size
    return context


func _on_enemy_killed(definition_id: String, xp: int, _position: Vector2) -> void:
    RunState.award_xp(xp)
    if definition_id == BOSS_DEFINITION:
        RunState.boss_defeated = true
        Events.boss_defeated.emit(definition_id)
        Events.say("Boss defeated! +%d XP | Exit unlocked." % xp, "progression")


func _on_level_up(level: int, pending_points: int) -> void:
    Events.say("LEVEL UP! Level %d — %d ability points available." % [level, pending_points],
        "progression")
    if pending_points > 0:
        character_menu.show_level_up(RunState.ability_scores, _character_context(),
            pending_points, int(RunState.config.get("stat_score_cap", 20)))
        _change_state(State.LEVEL_UP)


func _on_player_died(_cause: String) -> void:
    _end_run("defeated", "YOU DIED! R = retry, N = new seed.")


func _confirm_stat_allocation(changes: Dictionary) -> void:
    if character_menu.mode != "level_up":
        return
    if not RunState.apply_stat_allocation(changes):
        push_warning("Invalid level-up stat point allocation")
        return
    character_menu.close_menu()
    _change_state(State.RUNNING)
    Events.say("Level %d stats confirmed. HP %d/%d  AC %d" % [
        RunState.level, RunState.hp, RunState.max_hp, RunState.ac], "progression")


func _on_resume_game() -> void:
    _change_state(State.RUNNING)
    _redraw()


func _apply_resolution(resolution: Vector2i) -> void:
    if not CharacterMenu.RESOLUTION_PRESETS.has(resolution):
        return
    var window: Window = get_window()
    window.mode = Window.MODE_WINDOWED
    window.size = resolution
    if not DisplayServer.get_name() == "headless":
        window.move_to_center()
    _relayout()
    character_menu.current_resolution = window.size
    _redraw()
