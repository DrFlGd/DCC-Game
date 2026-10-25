extends Node2D
## Game: run orchestrator and state machine on the root node of Main.tscn.
##
## Owns floor generation, room loading, door transitions (collapse evaluation,
## exit gate), the multi-floor descent, restarts, the F9 debug shortcut and the
## wiring of CharacterMenu and the full-screen menus. It composes the Player,
## Combat, RoomRenderer, Hud, CharacterMenu, TitleScreen, IntermissionScreen,
## SummaryScreen and SettingsScreen children (from Main.tscn, or created here
## when Game is instanced from script).
##
## Boot shows TITLE; nothing is generated until start_run(seed), which tests
## may call directly from any state.
## All run data lives in the `RunState` autoload; cross-system notifications go
## through the `Events` autoload. Game reacts to enemy_killed (XP, boss gate),
## level_up (modal) and player_died (defeat).
## Wave 2E adds three children created here: CollapseClock (zero-clock grace,
## collapse_clock.gd), RoomServices (interactables and trap plates,
## room_services.gd) and FloorMap (the M overlay, ui/floor_map.gd).
## Wave 2B adds ItemSystem (item_system.gd: inventory, statuses, triggers,
## pickups, loot, shop); Game only routes input and frame steps to it.
signal state_changed(previous: int, current: int)

## RUNNING: simulation ticks. LEVEL_UP / PAUSED: CharacterMenu is modal and the
## world is frozen. TITLE: title screen, no run yet (boot state).
## SUMMARY: run summary after any run_ended; R / N still restart.
## INTERMISSION: between-floor recap, waiting for Descend.
## ENDED is the single-floor prototype's end banner; it is kept so the values
## stay stable but is no longer entered (SUMMARY replaced it). Append new
## states at the end. Every change is also announced as
## Events.game_state_changed(previous_name, current_name).
## MAP / DIALOG (Wave 2E): floor map overlay or a RoomServices choice modal;
## the world is frozen as in PAUSED.
enum State { RUNNING, LEVEL_UP, PAUSED, ENDED, TITLE, SUMMARY, INTERMISSION, MAP, DIALOG }

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
const RunRules = preload("res://scripts/core/run_rules.gd")
const Settings = preload("res://scripts/core/settings.gd")
const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const IntermissionScreen = preload("res://scripts/ui/intermission_screen.gd")
const SummaryScreen = preload("res://scripts/ui/summary_screen.gd")
const SettingsScreen = preload("res://scripts/ui/settings_screen.gd")
const CollapseClock = preload("res://scripts/collapse_clock.gd")
const RoomServices = preload("res://scripts/room_services.gd")
const FloorMap = preload("res://scripts/ui/floor_map.gd")
const Announcer = preload("res://scripts/ui/announcer.gd")
const ItemSystem = preload("res://scripts/item_system.gd")
const Inventory = preload("res://scripts/inventory.gd")

## World room bounds; never changes with window size.
const ROOM := Layout.ARENA

var state: State = State.TITLE
var catalogue: Dictionary = {}
## CollapsePolicy for the current run (rebuilt from RunState.config each run).
var rules
var layout: Dictionary = {}
var player: Player
var combat: Combat
var renderer: RoomRenderer
var hud: Hud
var character_menu: CharacterMenu
var title_screen: TitleScreen
var intermission_screen: IntermissionScreen
var summary_screen: SummaryScreen
var settings_screen: SettingsScreen
## Wave 2E children (see the class comment).
var clock: CollapseClock
var services: RoomServices
var floor_map: FloorMap
## Wave 2B child (see the class comment).
var items: ItemSystem
## Shared player settings (Settings.shared()), loaded and applied in _ready.
var settings
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
    title_screen = _ensure_child("TitleScreen", TitleScreen) as TitleScreen
    intermission_screen = _ensure_child("IntermissionScreen", IntermissionScreen) \
        as IntermissionScreen
    summary_screen = _ensure_child("SummaryScreen", SummaryScreen) as SummaryScreen
    settings_screen = _ensure_child("SettingsScreen", SettingsScreen) as SettingsScreen
    clock = _ensure_child("CollapseClock", CollapseClock) as CollapseClock
    services = _ensure_child("RoomServices", RoomServices) as RoomServices
    floor_map = _ensure_child("FloorMap", FloorMap) as FloorMap
    clock.setup(self)
    services.setup(self)
    items = _ensure_child("ItemSystem", ItemSystem) as ItemSystem
    services.modal_opened.connect(func(): _change_state(State.DIALOG))
    services.modal_closed.connect(_on_modal_closed)
    settings = Settings.shared()
    settings.apply_window(get_window())
    announcer = _ensure_child("Announcer", Announcer) as Announcer
    combat.setup(player, catalogue)
    # After services (the shop registers there), before Game's own Events hooks.
    items.setup(self)
    renderer.setup(player, combat, null, catalogue)
    _relayout()
    character_menu.current_resolution = get_window().size
    character_menu.allocation_confirmed.connect(_confirm_stat_allocation)
    character_menu.resume_requested.connect(_on_resume_game)
    character_menu.resolution_requested.connect(_apply_resolution)
    character_menu.settings_requested.connect(open_settings)
    character_menu.abandon_requested.connect(_on_abandon)
    title_screen.new_run_requested.connect(func(): start_run(random_seed()))
    title_screen.seeded_run_requested.connect(start_run)
    title_screen.settings_requested.connect(open_settings)
    title_screen.quit_requested.connect(func(): get_tree().quit())
    intermission_screen.descend_requested.connect(descend)
    summary_screen.retry_requested.connect(func(): start_run(RunState.seed))
    summary_screen.new_run_requested.connect(func(): start_run(random_seed()))
    summary_screen.title_requested.connect(show_title)
    settings_screen.setting_changed.connect(_on_setting_changed)
    settings_screen.closed.connect(_on_settings_closed)
    Events.enemy_killed.connect(_on_enemy_killed)
    Events.level_up.connect(_on_level_up)
    Events.player_died.connect(_on_player_died)
    show_title()


func _ensure_child(child_name: String, script: Script) -> Node:
    var node: Node = get_node_or_null(child_name)
    if node == null:
        node = script.new()
        node.name = child_name
        add_child(node)
    return node


## Starts a fresh run on floor 1 from any state (title, summary, mid-run or a
## test). Same seed + same inputs = same run.
func start_run(new_seed: int) -> void:
    RunState.start_run(new_seed)
    rules = Collapse.new(RunState.config.get("collapse", {}))
    renderer.rules = rules
    _close_screens()
    character_menu.close_menu()
    floor_map.close()
    if services.is_modal_open():
        services.dialog.close()
    _start_floor(1)
    _change_state(State.RUNNING)


## Returns to the title screen. The finished (or never started) run's data stays
## in RunState until the next start_run.
func show_title() -> void:
    _close_screens()
    character_menu.close_menu()
    title_screen.open()
    _change_state(State.TITLE)


## Intermission -> next floor (the Descend button). Ignored in other states.
func descend() -> void:
    if state != State.INTERMISSION:
        return
    intermission_screen.close()
    _start_floor(RunState.depth + 1)
    _change_state(State.RUNNING)


## Opens the settings page over the title screen or the pause menu.
func open_settings() -> void:
    if state == State.TITLE or state == State.PAUSED:
        settings_screen.open(settings)


## A positive 31-bit seed for "New run" / N.
static func random_seed() -> int:
    var dice := RandomNumberGenerator.new()
    dice.randomize()
    return dice.randi_range(1, 2147483646)


## Generates floor `depth` (room count from run.rooms_by_depth, seed from
## RunState.floor_seed(depth)), sets its fresh collapse budget, and places the
## player at the centre of its start room.
func _start_floor(depth: int) -> void:
    var room_count: int = RunRules.room_count(depth, RunState.config)
    # Wave 2E: depth drives special-room counts; the generator re-rolls
    # infeasible layouts and records route/budget/feasibility in the floor dict.
    var generated: Dictionary = Generator.generate(RunState.floor_seed(depth), room_count,
        {"depth": depth, "config": RunState.config})
    var route: int = RunRules.mandatory_route_cost(generated, rules)
    var budget: int = route + RunRules.slack(generated["rooms"].size(), RunState.config)
    RunState.reset_for_floor(depth, budget)
    RunState.floor = generated
    clock.reset_floor()
    floor_map.close()
    combat.clear_projectiles()
    combat.clear_hazards()
    player.reset(ROOM.get_center(), float(RunState.config.get("player_speed", Player.DEFAULT_SPEED)))
    var text := "Floor %d/%d | Seed %d | %d rooms | route %d + slack = %d ticks" % [
        depth, RunRules.target_depth(RunState.config), RunState.seed, room_count, route, budget]
    print(text)
    Events.say(text, "info")
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
    var kind: String = String(room["kind"])
    var contents: Dictionary = Contents.generate(floor_seed, id, room["neighbors"],
        kind, int(RunState.config.get("obstacle_count", 38)),
        RunState.config.get("room_obstacle_caps", {}),
        RunState.config.get("hazards", {}).get("trap_plates", {}))
    # 2C: depth scales the threat budget; links drive portal-distance and
    # reachability checks. Elite and trap rooms have their own budgets.
    var encounter: Array[Dictionary] = Enemies.generate_encounter(catalogue, kind, floor_seed,
        id, contents["blocked"], RunState.depth, room["neighbors"])
    RunState.room_states[id] = {"blocked": contents["blocked"], "props": contents["props"],
        "enemies": encounter, "interactables": contents["interactables"],
        "plates": contents["plates"]}


## Tries the door on side `direction` of the current room: exit gate, collapse
## cost, ledger, room swap, then the exit / zero-clock outcome.
## Wave 2E (D-03, D-05): a transition is never refused for lack of ticks (only
## the sealed exit refuses). The cost clamps at 0; reaching 0 starts the grace
## period after the room swap (CollapseClock), and entries during grace are
## free while first-entry grants still apply.
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
    clock.begin_transition(kind == "exit")
    RunState.apply_tick_entry(entry)
    RunState.current_room_id = next_id
    RunState.visited[next_id] = true
    combat.clear_projectiles()
    combat.clear_hazards()
    player.enter_through(direction)
    _load_room(next_id)
    Events.say("Room %d [%s] | %s | %d ticks left" % [
        next_id, kind, String(entry["reason"]), RunState.ticks], "collapse")
    print("COLLAPSE LEDGER ", entry)
    Events.room_entered.emit(next_id, kind, entry, first_visit)
    # Wave 2A ordering fix (GAME_DESIGN §3.4): the unsealed exit resolves as a
    # floor success BEFORE the collapse check, so paying the exit's cost with the
    # last tick is a success, not a collapse.
    if kind == "exit":
        # Wave 2E: the exit also ends an active grace (outcome "exit").
        clock.resolve_exit()
        clock.end_transition()
        _complete_floor()
    else:
        # Wave 2E: may start grace, or collapse at once on the floor's third zero.
        clock.end_transition()


## Exit taken: floor_cleared, then victory on target_depth or the intermission.
func _complete_floor() -> void:
    var depth: int = RunState.depth
    Events.floor_cleared.emit(depth)
    var recap: Dictionary = RunState.close_floor("cleared")
    var target: int = RunRules.target_depth(RunState.config)
    if depth >= target:
        _end_run("victory", "VICTORY! Floor %d cleared. R = repeat, N = new seed" % depth)
        return
    combat.clear_projectiles()
    recap["healed"] = RunState.intermission_heal()
    Events.say("FLOOR %d CLEARED. Descend when ready." % depth, "outcome")
    intermission_screen.open(recap, depth + 1, target, RunState.hp, RunState.max_hp)
    _change_state(State.INTERMISSION)


func _end_run(outcome: String, text: String, cause: String = "") -> void:
    character_menu.close_menu()
    floor_map.close()
    if services.is_modal_open():
        services.dialog.close()
    settings_screen.close()
    _change_state(State.SUMMARY)
    Events.say(text, "outcome")
    var result: Dictionary = RunState.end_run(outcome, cause)
    summary_screen.open(result)


func _close_screens() -> void:
    # Settings first: its `closed` handler may reopen the title screen.
    settings_screen.close()
    title_screen.close()
    intermission_screen.close()
    summary_screen.close()


func _change_state(next: State) -> void:
    # The HUD belongs to a run; the title screen has no run to show.
    hud.visible = next != State.TITLE
    if next == state:
        return
    var previous: State = state
    state = next
    state_changed.emit(previous, next)
    Events.game_state_changed.emit(State.keys()[previous], State.keys()[next])


func _physics_process(delta: float) -> void:
    if get_viewport_rect().size != Vector2(layout["viewport"]):
        _relayout()
    if state != State.RUNNING:
        _redraw()
        return
    RunState.advance_clock(delta)
    player.tick_timers(delta)
    # Wave 2B: `stunned` (blocks_actions) stops movement and attacks; speed
    # and attack cooldowns come from items (passives, statuses, weapons).
    var can_act: bool = items.player_can_act()
    var door := ""
    if can_act:
        door = player.move(player.read_move_axis() * items.move_speed() * delta, combat.blocked())
    if door != "":
        _enter_neighbor(door)
    if state != State.RUNNING:
        _redraw()
        return
    player.aim_at(Layout.screen_to_world(get_global_mouse_position(), layout))
    if can_act and player.try_fire(items.cooldown("ranged")):
        combat.player_fire()
    if can_act and player.try_melee(items.cooldown("melee")):
        combat.player_melee()
    combat.update_projectiles(delta)
    # A kill above may have opened the level-up modal; enemies freeze with it.
    if state == State.RUNNING:
        combat.update_enemies(delta)
    # Wave 2E: hazards, plates/prompts and the grace timer, each frozen by modals.
    if state == State.RUNNING:
        combat.update_hazards(delta)
    if state == State.RUNNING:
        items.update(delta)
    if state == State.RUNNING:
        services.update(delta)
    if state == State.RUNNING:
        clock.update(delta)
    _redraw()


func _redraw() -> void:
    renderer.queue_redraw()
    hud.prompt = "" if state != State.RUNNING else (
        items.prompt if items.prompt != "" else services.prompt)
    hud.hover = items.hover if state == State.RUNNING else {}
    hud.refresh()


func _relayout() -> void:
    layout = Layout.compute(get_viewport_rect().size)
    renderer.layout = layout
    hud.layout = layout


func _input(event: InputEvent) -> void:
    # Wave 2E: the floor map toggles on `map` and also closes on `pause`;
    # a RoomServices choice modal handles its own keys.
    if event.is_action_pressed("map") or (state == State.MAP and event.is_action_pressed("pause")):
        if state == State.MAP:
            close_map()
        elif event.is_action_pressed("map"):
            open_map()
        get_viewport().set_input_as_handled()
        return
    if state == State.DIALOG or not event.is_action_pressed("pause"):
        return
    if settings_screen.is_open():
        settings_screen.close()
    elif character_menu.mode == "pause":
        character_menu.close_menu()
        _change_state(State.RUNNING)
    elif character_menu.mode == "closed" and state == State.RUNNING:
        character_menu.show_pause(RunState.ability_scores, _character_context())
        _change_state(State.PAUSED)
    get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
    if character_menu != null and character_menu.is_open():
        return
    if settings_screen != null and settings_screen.is_open():
        return
    # Wave 2E: `interact` uses the interactable in reach (RoomServices).
    if event.is_action_pressed("interact"):
        if state == State.RUNNING and not items.try_interact():
            services.try_interact()
        return
    # Wave 2B: active item, selected consumable, belt cycling.
    if state == State.RUNNING:
        if event.is_action_pressed("use_item"):
            items.use_active()
            return
        if event.is_action_pressed("use_consumable"):
            items.use_consumable()
            return
        if event.is_action_pressed("next_consumable"):
            items.next_consumable()
            return
    # R / N restart mid-run and on the summary (muscle memory), not on the
    # title or intermission screens.
    if state != State.RUNNING and state != State.SUMMARY:
        return
    if event.is_action_pressed("restart_seed"):
        start_run(RunState.seed)
    elif event.is_action_pressed("new_seed"):
        start_run(random_seed())
    elif event.is_action_pressed("debug_level_up") and state == State.RUNNING \
            and RunState.level < 20:
        # Prototype playtest shortcut: jump to the next XP threshold.
        RunState.award_xp(maxi(0, RPG.next_level_xp(RunState.level) - RunState.xp))


## Opens the floor map overlay (only from RUNNING); the world freezes.
func open_map() -> bool:
    if state != State.RUNNING:
        return false
    floor_map.open(FloorMap.build_model(RunState.floor, RunState.visited,
        RunState.current_room_id, RunState.ticks, rules, RunState.room_states,
        RunState.boss_defeated))
    _change_state(State.MAP)
    return true


func close_map() -> void:
    floor_map.close()
    if state == State.MAP:
        _change_state(State.RUNNING)


func _on_modal_closed() -> void:
    if state == State.DIALOG:
        _change_state(State.RUNNING)


func _character_context() -> Dictionary:
    var context: Dictionary = RunState.progression_context()
    context["window_size"] = get_window().size
    context["inventory"] = Inventory.describe()
    return context


func _on_enemy_killed(definition_id: String, xp: int, _position: Vector2) -> void:
    RunState.award_xp(xp)
    # Data-driven: any enemy flagged "boss" in enemies.json unlocks the exit.
    if Enemies.is_boss(catalogue, definition_id):
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


func _on_player_died(cause: String) -> void:
    _end_run("defeated", "YOU DIED! R = retry, N = new seed.", cause)


func _on_abandon() -> void:
    if state == State.PAUSED:
        _end_run("abandoned", "RUN ABANDONED. R = retry, N = new seed.", "abandoned")


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


## Pause-menu "Apply resolution": windowed at `resolution`, saved to settings.
func _apply_resolution(resolution: Vector2i) -> void:
    if not CharacterMenu.RESOLUTION_PRESETS.has(resolution):
        return
    settings.set_value("fullscreen", false)
    settings.set_value("resolution", resolution)
    _on_setting_changed("resolution", resolution)


## Settings screen (or pause menu) changed `key`: save, apply window settings,
## and announce Events.settings_changed.
func _on_setting_changed(key: String, _value) -> void:
    settings.save_settings()
    if key == "resolution" or key == "fullscreen":
        settings.apply_window(get_window())
        _relayout()
        character_menu.current_resolution = get_window().size
    Events.settings_changed.emit(settings.to_dict())
    _redraw()


func _on_settings_closed() -> void:
    if state == State.TITLE:
        title_screen.open()
    elif state == State.PAUSED and character_menu.mode == "pause":
        character_menu.current_resolution = get_window().size
        character_menu.refresh()
