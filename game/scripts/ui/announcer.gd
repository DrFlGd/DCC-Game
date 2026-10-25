extends CanvasLayer
## The dungeon "system" (GAME_DESIGN.md §8): a presentation-only announcer.
##
## Listens to `Events`, picks flavour lines from data/announcer.json through
## the pure AnnouncerBrain, and shows them as toasts at the top centre plus a
## scrolling system log (Input Map action `toggle_log`, L / L3). It also runs
## achievements (data/achievements.json -> Events.achievement_unlocked), keeps
## the profile (user://profile.json) and writes a telemetry report per run
## (user://telemetry/). It never changes game state and never emits
## `Events.message`: the HUD message line stays terse gameplay status.
##
## Other systems ask for lines with
##   Events.announcement_requested.emit("chest_opened", {"enemy": "Mimic"})
## or show literal text with
##   Events.announcement_requested.emit("my_feature", {"text": "...", "priority": 3})
const Lines = preload("res://scripts/core/announcer_lines.gd")
const Brain = preload("res://scripts/core/announcer_brain.gd")
const Achievements = preload("res://scripts/core/achievements.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Telemetry = preload("res://scripts/core/telemetry.gd")
const Enemies = preload("res://scripts/enemy_system.gd")

## Above the run-loop screens (12) and settings (20) so toasts show over them.
## Toasts are held back while a modal (pause, level-up) is open.
const LAYER := 25
## Game states (Events.game_state_changed, Wave 2A) that count as modal.
const MODAL_STATES := ["LEVEL_UP", "PAUSED"]
## Signals from other Wave 2 teams; connected only if Events declares them.
const OPTIONAL_SIGNALS := ["grace_started", "grace_ended", "hazard_spawned", "chest_opened",
    "shrine_used", "guild_rested", "game_state_changed"]
const VICTORY_OUTCOMES := ["victory", "escaped"]
const TOAST_TOP := 90.0
const TOAST_GAP := 6.0
const TOAST_FONT := 15
const TOAST_PADDING := Vector2(14, 6)
const LOG_FONT := 12
const CATEGORY_COLORS := {
    "flavour": Color("#e5eafa"), "warning": Color("#ffb36b"), "celebration": Color("#f6d48d"),
    "sponsor": Color("#d2b6ff"), "taunt": Color("#bfe3ea"), "obituary": Color("#ff9a9a"),
    "achievement": Color("#a9e7c5"), "system": Color("#9fd3ff")
}

var brain: Brain
## Parsed announcer.json ({} if it failed validation; see `problems`).
var data: Dictionary = {}
var problems: Array[String] = []
var definitions: Array = []
## Per-run achievement counters (Achievements.observe).
var tracker: Dictionary = Achievements.new_tracker()
var telemetry: Telemetry
## Seconds since this node started; the brain's clock (real time, not run time).
var clock := 0.0
## Force the modal gate shut (e.g. a screen that is not a Game state).
var modal_override := false
## Write profile and telemetry files. Under `--script` (tests) they go to user://test/.
var persist := true
var telemetry_dir := Telemetry.DEFAULT_DIR
var last_report_path := ""
var log_open := false
var enemy_names: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _state_modal := false
## Last Events.game_state_changed state ("" until 2A's signal fires).
var _game_state := ""
var _last_input_at := 0.0
var _low_hp_armed := true
var _ticks_low_armed := true
var _killer := ""
var _canvas: Control
var _log_panel: PanelContainer
var _log_text: RichTextLabel
var _hint: Label
var _log_version := -1


func _ready() -> void:
    layer = LAYER
    _configure_storage()
    data = Lines.load_data()
    problems = Lines.validate(data)
    if not problems.is_empty():
        push_warning("Announcer lines invalid, announcer muted: %s" % [problems])
        data = {}
    brain = Brain.new(data)
    definitions = Achievements.default_definitions()
    _definitions_by_id = Achievements.by_id(definitions)
    enemy_names = _load_enemy_names()
    telemetry = Telemetry.new()
    telemetry.name = "Telemetry"
    telemetry.clock = _run_clock
    add_child(telemetry)
    telemetry.attach(Events)
    _build_ui()
    Events.run_started.connect(_on_run_started)
    Events.floor_started.connect(_on_floor_started)
    Events.room_entered.connect(_on_room_entered)
    Events.room_cleared.connect(_on_room_cleared)
    Events.ticks_changed.connect(_on_ticks_changed)
    Events.enemy_killed.connect(_on_enemy_killed)
    Events.player_damaged.connect(_on_player_damaged)
    Events.player_healed.connect(_on_player_healed)
    Events.player_died.connect(_on_player_died)
    Events.level_up.connect(_on_level_up)
    Events.boss_defeated.connect(_on_boss_defeated)
    Events.floor_cleared.connect(_on_floor_cleared)
    Events.run_ended.connect(_on_run_ended)
    Events.achievement_unlocked.connect(_on_achievement_unlocked)
    Events.announcement_requested.connect(_on_announcement_requested)
    for signal_name in OPTIONAL_SIGNALS:
        _connect_optional(signal_name)


## Picks a line for `trigger` (placeholders from RunState, overridden by
## `extra`) and queues it. Returns the entry, or {} if nothing was picked.
func announce(trigger: String, extra: Dictionary = {}) -> Dictionary:
    return brain.announce(trigger, _context(extra), clock)


func is_modal() -> bool:
    return modal_override or _state_modal or _menu_open()


func toggle_log() -> void:
    log_open = not log_open
    _log_panel.visible = log_open
    _log_version = -1


func _process(delta: float) -> void:
    clock += delta
    brain.set_modal(is_modal(), clock)
    _check_idle()
    brain.update(clock)
    _layout_ui()
    _canvas.queue_redraw()
    if log_open and _log_version != brain.log_version:
        _refresh_log()


func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion or (event is InputEventJoypadMotion \
            and absf((event as InputEventJoypadMotion).axis_value) > 0.3) \
            or (event.is_pressed() and not event.is_echo()):
        _last_input_at = clock
    if InputMap.has_action("toggle_log") and event.is_action_pressed("toggle_log"):
        toggle_log()
        get_viewport().set_input_as_handled()


# --- Signal handlers ---------------------------------------------------------

func _on_run_started(run_seed: int) -> void:
    brain.reset_run(run_seed)
    _track("run_started", {"seed": run_seed})
    _low_hp_armed = true
    _ticks_low_armed = true
    _killer = ""
    _last_input_at = clock
    announce("run_started")


func _on_floor_started(depth: int, _floor: Dictionary) -> void:
    _track("floor_started", {"depth": depth})
    _ticks_low_armed = true
    if depth > 1:
        announce("floor_started")


func _on_room_entered(room_id: int, kind: String, entry: Dictionary, first_visit: bool) -> void:
    _track("room_entered", {"room_id": room_id, "kind": kind, "first_visit": first_visit,
        "door": not entry.is_empty()})
    if entry.is_empty():
        return  # a floor's start room: run_started / floor_started speak for it
    if kind == "boss" and not RunState.boss_defeated:
        announce("boss_room_entered")
    elif first_visit or kind == "start" or kind == "boss":
        announce("room_entered." + kind)


func _on_room_cleared(room_id: int) -> void:
    _track("room_cleared", {"room_id": room_id})


func _on_ticks_changed(before: int, after: int, reason: String) -> void:
    _track("ticks_changed", {"before": before, "after": after, "reason": reason})
    var limit: int = int(brain.settings["ticks_low"])
    if after > limit:
        _ticks_low_armed = true
    elif _ticks_low_armed and after > 0 and after < before:
        _ticks_low_armed = false
        announce("ticks_low")


func _on_enemy_killed(definition_id: String, xp: int, _position: Vector2) -> void:
    _track("enemy_killed", {"definition_id": definition_id, "xp": xp})
    var context := {"enemy": enemy_name(definition_id)}
    if int(tracker["run.kills"]) == 1:
        announce("first_blood", context)
        return
    var streak: int = int(tracker["run.streak"])
    var streak_key := "kill_streak.%d" % streak
    if brain.has_trigger(streak_key):
        context["streak"] = streak
        announce(streak_key, context)
    else:
        announce("enemy_killed." + definition_id, context)


func _on_player_damaged(amount: int, source: String) -> void:
    _track("player_damaged", {"amount": amount, "source": source})
    if RunState.hp <= 0:
        return
    var max_hp: int = maxi(1, RunState.max_hp)
    var fraction: float = float(RunState.hp) / float(max_hp)
    var context := {"enemy": enemy_name(source), "damage": amount}
    if _low_hp_armed and fraction <= float(brain.settings["low_hp_fraction"]):
        _low_hp_armed = false
        announce("low_hp", context)
    elif float(amount) >= float(brain.settings["big_hit_fraction"]) * float(max_hp):
        announce("player_damaged_big", context)


func _on_player_healed(_amount: int) -> void:
    if float(RunState.hp) / float(maxi(1, RunState.max_hp)) >= float(brain.settings["low_hp_rearm_fraction"]):
        _low_hp_armed = true


func _on_player_died(cause: String) -> void:
    _killer = cause
    _track("player_died", {"cause": cause})


func _on_level_up(level: int, pending_points: int) -> void:
    _track("level_up", {"level": level, "pending_points": pending_points})
    announce("level_up")


func _on_boss_defeated(definition_id: String) -> void:
    _track("boss_defeated", {"definition_id": definition_id})
    announce("boss_defeated", {"enemy": enemy_name(definition_id)})


func _on_floor_cleared(depth: int) -> void:
    _track("floor_cleared", {"depth": depth})
    announce("floor_cleared")


func _on_run_ended(outcome: String, summary: Dictionary) -> void:
    if _killer.is_empty() and outcome == "defeated":
        _killer = String(summary.get("cause", ""))
    if outcome == "defeated" and String(tracker["run.cause"]).is_empty():
        tracker["run.cause"] = _killer
    _track("run_ended", {"outcome": outcome})
    var key: String = "run_ended." + ("victory" if VICTORY_OUTCOMES.has(outcome) else outcome)
    announce(key, {"enemy": enemy_name(_killer)})
    var profile: Dictionary = Profile.current()
    Profile.record_run(profile, summary, outcome, _killer, int(tracker["run.floors_cleared"]))
    if not persist:
        return
    Profile.save_current()
    var unix: int = int(Time.get_unix_time_from_system())
    var report: Dictionary = telemetry.build_report(summary, RunState.tick_ledger,
        brain.history, unix)
    last_report_path = Telemetry.write_report(report, telemetry_dir)


func _on_achievement_unlocked(id: String) -> void:
    var unix: int = int(Time.get_unix_time_from_system())
    if not Profile.unlock(Profile.current(), id, RunState.seed, unix):
        return
    telemetry.note_unlock(id, unix)
    if persist:
        Profile.save_current()
    var definition: Dictionary = _definitions_by_id.get(id, {})
    announce("achievement_unlocked", {"achievement": String(definition.get("title", id)),
        "quip": String(definition.get("quip", ""))})


func _on_announcement_requested(trigger: String, context: Dictionary) -> void:
    if brain.has_trigger(trigger):
        announce(trigger, context)
    elif context.has("text"):
        brain.custom(String(context["text"]), int(context.get("priority", 2)),
            String(context.get("category", "system")), clock, trigger)


func _on_optional(signal_name: String, args: Array) -> void:
    match signal_name:
        "game_state_changed":
            _game_state = String(args[1]) if args.size() >= 2 else ""
            _state_modal = MODAL_STATES.has(_game_state)
        "grace_started":
            _track(signal_name, {})
            announce("grace_started")
        "grace_ended":
            var declined: bool = not args.is_empty() and args[0] is bool and not args[0]
            if RunState.outcome == "running" and RunState.hp > 0 and not declined:
                _track(signal_name, {})
                announce("grace_stabilised")
        "hazard_spawned":
            announce("hazard_spawned")
        _:
            _track(signal_name, {})
            announce(signal_name)


# --- Helpers -----------------------------------------------------------------

## Display name for an enemy definition id ("" -> "dungeon").
func enemy_name(definition_id: String) -> String:
    if definition_id.is_empty():
        return "dungeon"
    return String(enemy_names.get(definition_id, definition_id.replace("_", " ").capitalize()))


## Folds an event into the achievement tracker and emits any unlocks.
func _track(type: String, fields: Dictionary) -> void:
    var event: Dictionary = fields.duplicate()
    event["type"] = type
    event["time"] = _run_clock()
    Achievements.observe(tracker, event)
    var profile: Dictionary = Profile.current()
    var snapshot: Dictionary = Achievements.build_snapshot(tracker, _live(), profile["stats"],
        profile["achievements"])
    for id in Achievements.evaluate(snapshot, event, definitions):
        Events.achievement_unlocked.emit(id)


func _context(extra: Dictionary) -> Dictionary:
    var context := {
        "depth": RunState.depth, "kills": int(RunState.telemetry.get("kills", 0)),
        "ticks": RunState.ticks, "seed": RunState.seed, "level": RunState.level,
        "hp": maxi(0, RunState.hp), "max_hp": RunState.max_hp, "xp": RunState.xp,
        "room": RunState.current_room_id
    }
    context.merge(extra, true)
    return context


func _live() -> Dictionary:
    return {"hp": RunState.hp, "max_hp": RunState.max_hp, "ticks": RunState.ticks,
        "depth": RunState.depth, "level": RunState.level, "outcome": RunState.outcome,
        "seed": RunState.seed, "run_time": _run_clock()}


func _run_clock() -> float:
    return float(RunState.telemetry.get("run_time_seconds", 0.0))


func _check_idle() -> void:
    var playing: bool = _game_state.is_empty() or _game_state == "RUNNING"
    if RunState.floor.is_empty() or RunState.outcome != "running" or brain.modal or not playing:
        _last_input_at = clock
        return
    var idle: float = clock - _last_input_at
    if idle >= float(brain.settings["idle_seconds"]):
        announce("idle", {"idle": int(idle)})
        _last_input_at = clock


func _menu_open() -> bool:
    var parent: Node = get_parent()
    if parent == null:
        return false
    var menu = parent.get("character_menu")
    return menu is Object and is_instance_valid(menu) and menu.has_method("is_open") \
        and bool(menu.is_open())


func _connect_optional(signal_name: String) -> void:
    if not Events.has_signal(signal_name):
        return
    var arity := 0
    for info in Events.get_signal_list():
        if info["name"] == signal_name:
            arity = (info["args"] as Array).size()
    var handler: Callable
    match arity:
        0: handler = func(): _on_optional(signal_name, [])
        1: handler = func(a): _on_optional(signal_name, [a])
        2: handler = func(a, b): _on_optional(signal_name, [a, b])
        3: handler = func(a, b, c): _on_optional(signal_name, [a, b, c])
        4: handler = func(a, b, c, d): _on_optional(signal_name, [a, b, c, d])
        _: return
    Events.connect(signal_name, handler)


## Tests (`--script`) keep their profile and telemetry away from the player's.
func _configure_storage() -> void:
    if not OS.get_cmdline_args().has("--script"):
        return
    if Profile.profile_path == Profile.DEFAULT_PATH:
        Profile.use_path("user://test/profile.json")
    if telemetry_dir == Telemetry.DEFAULT_DIR:
        telemetry_dir = "user://test/telemetry"


func _load_enemy_names() -> Dictionary:
    var names: Dictionary = {}
    var catalogue: Dictionary = Enemies.load_catalogue()
    var enemies: Dictionary = catalogue.get("enemies", {})
    for id in enemies:
        names[String(id)] = String(enemies[id].get("name", id))
    return names


# --- Drawing -----------------------------------------------------------------

func _build_ui() -> void:
    _canvas = Control.new()
    _canvas.name = "Toasts"
    _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _canvas.draw.connect(_draw_toasts)
    add_child(_canvas)
    _log_panel = PanelContainer.new()
    _log_panel.name = "SystemLog"
    _log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
    style.border_color = Color("#5fb3b3")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    style.set_content_margin_all(10)
    _log_panel.add_theme_stylebox_override("panel", style)
    var column := VBoxContainer.new()
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(column)
    var title := Label.new()
    title.text = "SYSTEM LOG  (L to close)"
    title.add_theme_font_size_override("font_size", 13)
    title.add_theme_color_override("font_color", Color("#f6d48d"))
    column.add_child(title)
    _log_text = RichTextLabel.new()
    _log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_text.scroll_active = true
    _log_text.scroll_following = true
    _log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _log_text.add_theme_font_size_override("normal_font_size", LOG_FONT)
    column.add_child(_log_text)
    _log_panel.visible = false
    add_child(_log_panel)
    _hint = Label.new()
    _hint.text = "L: system log"
    _hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hint.add_theme_font_size_override("font_size", 11)
    _hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9, 0.55))
    add_child(_hint)


func _layout_ui() -> void:
    var view: Vector2 = get_viewport().get_visible_rect().size
    var width: float = clampf(view.x * 0.3, 220.0, 340.0)
    _log_panel.position = Vector2(view.x - width - 12.0, 100.0)
    _log_panel.size = Vector2(width, maxf(120.0, view.y - 170.0))
    _hint.position = Vector2(view.x - 92.0, view.y - 38.0)
    _hint.visible = not RunState.floor.is_empty() and _game_state != "TITLE"


func _refresh_log() -> void:
    _log_version = brain.log_version
    _log_text.clear()
    for entry in brain.log_lines:
        _log_text.push_color(CATEGORY_COLORS.get(entry["category"], Color.WHITE))
        _log_text.add_text("• " + String(entry["text"]).replace("\n", " — "))
        _log_text.pop()
        _log_text.newline()


func _draw_toasts() -> void:
    var font: Font = ThemeDB.fallback_font
    var view: Vector2 = _canvas.size
    var max_text: float = minf(640.0, view.x - 60.0) - TOAST_PADDING.x * 2.0
    var y: float = TOAST_TOP
    for entry in brain.on_screen:
        var text: String = String(entry["text"])
        var alpha: float = brain.alpha_for(entry, clock)
        var natural: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
            -1, TOAST_FONT)
        var text_width: float = minf(natural.x, max_text)
        var text_size: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
            text_width, TOAST_FONT)
        var box := Rect2(Vector2((view.x - text_width) * 0.5 - TOAST_PADDING.x, y),
            Vector2(text_width, text_size.y) + TOAST_PADDING * 2.0)
        var accent: Color = CATEGORY_COLORS.get(entry["category"], Color.WHITE)
        _canvas.draw_rect(box, Color(0.03, 0.05, 0.09, 0.9 * alpha))
        _canvas.draw_rect(box, Color(accent, alpha * (1.0 if int(entry["priority"]) >= 4 else 0.55)),
            false, 2.0 if int(entry["priority"]) >= 4 else 1.0)
        _canvas.draw_multiline_string(font, box.position + Vector2(TOAST_PADDING.x,
            TOAST_PADDING.y + font.get_ascent(TOAST_FONT)), text, HORIZONTAL_ALIGNMENT_CENTER,
            text_width, TOAST_FONT, -1, Color(accent, alpha))
        y += box.size.y + TOAST_GAP
