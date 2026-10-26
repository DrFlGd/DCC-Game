extends Node
## Audio (Wave 3A): sound effects, ambience and music, driven by `Events`.
##
## Game creates one child named "Audio" in _ready. It plays the cues of
## data/audio.json (trigger -> {stream, bus, volume_db, pitch_var, cooldown,
## ...}; see validate()) on the buses of default_bus_layout.tres
## (Master -> Music, SFX, Ambient, UI) and applies the Settings volumes.
##
## - SFX / UI cues use a pool of AudioStreamPlayers (round-robin, first free
##   one, else the oldest is stolen). Each cue has a cooldown (shared by its
##   `group` when set), a cap on simultaneous copies (`max_instances`) and an
##   optional random pitch spread (`pitch_var`, e.g. 0.06 = +-6 %).
## - Music and Ambient each own two players and crossfade between them
##   (settings.crossfade_seconds) when the Game state, or the boss room, picks
##   another cue (data "states"). Re-picking the same stream only retunes its
##   volume, so title music runs on into the intermission at a lower mix.
## - Menu buttons are hooked through SceneTree.node_added: focus -> ui.move,
##   press -> ui.confirm; sliders: focus / value change -> ui.move.
##
## Other code can play a cue directly:  game.audio.play("item_used")
## (or get_node("/root/Main/Audio")). Mapping a new sound needs no code when a
## signal's cue has the signal's name (see SIMPLE_SIGNALS); variants (".x")
## are picked by the handlers below.
##
## No autoload identifiers here (Events is looked up at runtime), so tests may
## preload this script. Headless runs use Godot's Dummy audio driver, which
## still advances playback; nothing here depends on a real device.

const Settings = preload("res://scripts/core/settings.gd")

const DATA_PATH := "res://data/audio.json"
const SCHEMA_VERSION := 1
const BUSES := ["Music", "SFX", "Ambient", "UI"]
## Track layers: buses with their own crossfading player pair.
const LAYERS := ["Music", "Ambient"]
## Settings key behind each bus (Ambient follows music, UI follows effects).
const BUS_SETTINGS := {"Master": "master_volume", "Music": "music_volume",
    "Ambient": "music_volume", "SFX": "sfx_volume", "UI": "sfx_volume"}
const SILENT_DB := -80.0
## Cue namespaces that are not Events signals.
const RESERVED := ["ui", "music", "ambient"]
## Keys allowed in data "states" (Game state names, plus RUNNING.boss).
const STATE_KEYS := ["TITLE", "RUNNING", "RUNNING.boss", "LEVEL_UP", "PAUSED", "ENDED",
    "SUMMARY", "INTERMISSION", "MAP", "DIALOG"]
const CUE_KEYS := ["stream", "bus", "volume_db", "pitch_var", "cooldown", "max_instances",
    "pitch", "group", "loop"]
const SETTINGS_DEFAULTS := {"pool_size": 12, "max_instances": 3, "crossfade_seconds": 0.6,
    "attack_window": 0.5}
## Signals whose cue is just the signal's name (payload ignored).
const SIMPLE_SIGNALS := ["player_healed", "dodged", "player_died", "item_picked_up",
    "item_used", "chest_opened", "loot_box_opened", "doors_locked", "doors_unlocked",
    "xp_gained", "level_up", "grace_started", "hazard_spawned", "floor_cleared",
    "achievement_unlocked", "announcement_requested", "skill_learned", "skill_used"]
## Every cue the code can ask for (the shipped data must define each one).
const CODE_CUES := ["ui.move", "ui.confirm", "ui.back", "ui.open",
    "melee_swung.player", "melee_swung.enemy", "projectile_fired.player",
    "projectile_fired.enemy", "enemy_damaged", "enemy_damaged.melee", "enemy_damaged.ranged",
    "enemy_damaged.critical", "enemy_killed", "boss_defeated", "player_damaged",
    "player_damaged.hazard", "credits_changed.gain", "credits_changed.spend",
    "ticks_changed.gain", "ticks_changed.loss", "run_ended.victory", "run_ended.defeat",
    "message.collapse"]
const VICTORY_OUTCOMES := ["victory", "escaped"]
## States reached from RUNNING through a menu key (ui.open on entry).
const MENU_STATES := ["PAUSED", "MAP"]
## Modal states that return to RUNNING with ui.back.
const MODAL_STATES := ["PAUSED", "MAP", "DIALOG", "LEVEL_UP"]

## Parsed audio.json ({} when it failed validation; see `problems`).
var data: Dictionary = {}
var problems: Array[String] = []
var cues: Dictionary = {}
var config: Dictionary = SETTINGS_DEFAULTS.duplicate()
## Seconds since start (real time; advances during pause and hit-stop). Tests
## may set it to step cooldowns.
var clock := 0.0
## SFX / UI player pool.
var pool: Array[AudioStreamPlayer] = []
## Counters for tests and debugging.
var played := 0
var throttled := 0
var capped := 0
var last_cue := ""
var play_counts: Dictionary = {}
## Last Events.game_state_changed state (Game boots in TITLE without a signal).
var game_state := "TITLE"
var in_boss_room := false
var boss_dead := false

var _events: Node
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _cursor := 0
## Per pool player: the cue it plays and when it is free again.
var _pool_cue: Array[String] = []
var _busy_until: Array[float] = []
## cooldown key (group or cue id) -> clock of its last play
var _last_played: Dictionary = {}
## "player" attack kind and time, for picking melee vs ranged hit sounds.
var _last_attack := {"kind": "", "at": -100.0}
## layer -> {players: [a, b], active: int, cue: String, tweens: [a, b]}
var _layers: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _rng.seed = 30311  # fixed: audio never touches RunState.rng
    ensure_buses()
    data = load_data()
    problems = validate(data, _signal_names())
    if not problems.is_empty():
        push_warning("Audio map invalid, audio muted: %s" % [problems])
        data = {}
    cues = data.get("cues", {})
    config = SETTINGS_DEFAULTS.duplicate()
    config.merge(data.get("settings", {}), true)
    _build_players()
    apply_settings(Settings.shared().to_dict())
    attach(get_node_or_null("/root/Events"))
    _hook_ui_tree()
    _apply_tracks()


func _process(delta: float) -> void:
    clock += delta


# --- Public API ----------------------------------------------------------------

## Plays SFX / UI cue `id` (a key of audio.json "cues"). `pitch_scale`
## multiplies the cue's pitch. Returns false when the cue is unknown, is a
## music/ambient track, is cooling down or already has max_instances copies
## playing.
func play(id: String, pitch_scale: float = 1.0) -> bool:
    var cue: Dictionary = cues.get(id, {})
    if cue.is_empty() or LAYERS.has(String(cue["bus"])):
        return false
    var key := String(cue.get("group", id))
    if _last_played.has(key) and clock - float(_last_played[key]) < float(cue["cooldown"]):
        throttled += 1
        return false
    if active_count(id) >= int(cue.get("max_instances", config["max_instances"])):
        capped += 1
        return false
    var stream: AudioStream = _stream(cue)
    if stream == null or pool.is_empty():
        return false
    var index := _free_player()
    var player := pool[index]
    var spread := float(cue["pitch_var"])
    var pitch: float = float(cue.get("pitch", 1.0)) * pitch_scale \
        * (1.0 + _rng.randf_range(-spread, spread))
    player.stop()
    player.stream = stream
    player.bus = String(cue["bus"])
    player.volume_db = float(cue["volume_db"])
    player.pitch_scale = clampf(pitch, 0.1, 4.0)
    if player.is_inside_tree():
        player.play()
    _pool_cue[index] = id
    _busy_until[index] = clock + stream.get_length() / player.pitch_scale
    _last_played[key] = clock
    played += 1
    last_cue = id
    play_counts[id] = int(play_counts.get(id, 0)) + 1
    return true


## Pool players still busy with cue `id` (by the clock, so it also holds when
## no audio device advances playback).
func active_count(id: String) -> int:
    var count := 0
    for i in pool.size():
        if _pool_cue[i] == id and _busy_until[i] > clock:
            count += 1
    return count


## Pool players busy with any cue.
func busy_count() -> int:
    var count := 0
    for until in _busy_until:
        if until > clock:
            count += 1
    return count


## Crossfades `layer` ("Music" / "Ambient") to track cue `id` ("" = silence).
func set_track(layer: String, id: String) -> void:
    if not _layers.has(layer):
        return
    var slot: Dictionary = _layers[layer]
    var cue: Dictionary = cues.get(id, {})
    if id != "" and (cue.is_empty() or String(cue["bus"]) != layer):
        id = ""
    if String(slot["cue"]) == id:
        return
    var fade := float(config["crossfade_seconds"])
    var current: AudioStreamPlayer = slot["players"][slot["active"]]
    var stream: AudioStream = _stream(cue) if id != "" else null
    slot["cue"] = id
    if stream != null and current.stream == stream and current.playing:
        _fade(slot, int(slot["active"]), float(cue["volume_db"]), fade, false)
        return
    if current.playing:
        _fade(slot, int(slot["active"]), SILENT_DB, fade, true)
    if stream == null:
        return
    slot["active"] = 1 - int(slot["active"])
    var next: AudioStreamPlayer = slot["players"][slot["active"]]
    next.stop()
    next.stream = stream
    next.volume_db = SILENT_DB if fade > 0.0 else float(cue["volume_db"])
    if next.is_inside_tree():
        next.play()
    _fade(slot, int(slot["active"]), float(cue["volume_db"]), fade, false)


## The track cue `layer` is playing or fading in ("" for none).
func current_track(layer: String) -> String:
    return String(_layers[layer]["cue"]) if _layers.has(layer) else ""


## The player currently carrying `layer`'s track (tests, debugging).
func track_player(layer: String) -> AudioStreamPlayer:
    var slot: Dictionary = _layers[layer]
    return slot["players"][slot["active"]]


## Sets every bus volume from a Settings.to_dict() dictionary.
func apply_settings(values: Dictionary) -> void:
    for bus in BUS_SETTINGS:
        var index := AudioServer.get_bus_index(bus)
        if index < 0:
            continue
        var linear := clampf(float(values.get(BUS_SETTINGS[bus], 1.0)), 0.0, 1.0)
        AudioServer.set_bus_volume_db(index, volume_to_db(linear))
        AudioServer.set_bus_mute(index, linear <= 0.0)


## Linear 0..1 slider value -> bus dB; 0 is -80 dB (silent), 1 is 0 dB.
static func volume_to_db(linear: float) -> float:
    if linear <= 0.0:
        return SILENT_DB
    return maxf(SILENT_DB, linear_to_db(minf(linear, 1.0)))


## Adds any of BUSES missing from the layout (sending to Master), so a
## missing or older default_bus_layout.tres never breaks playback.
static func ensure_buses() -> void:
    for bus in BUSES:
        if AudioServer.get_bus_index(bus) >= 0:
            continue
        AudioServer.add_bus()
        var index := AudioServer.bus_count - 1
        AudioServer.set_bus_name(index, bus)
        AudioServer.set_bus_send(index, "Master")


## Subscribes to an Events node (the autoload, or a stand-in in tests).
func attach(events: Node) -> void:
    if events == null or events == _events:
        return
    _events = events
    _connect("melee_swung", _on_melee_swung)
    _connect("projectile_fired", _on_projectile_fired)
    _connect("enemy_damaged", _on_enemy_damaged)
    _connect("enemy_killed", func(_id, _xp, _pos): play("enemy_killed"))
    _connect("boss_defeated", _on_boss_defeated)
    _connect("player_damaged", _on_player_damaged)
    _connect("credits_changed", _on_credits_changed)
    _connect("ticks_changed", _on_ticks_changed)
    _connect("run_ended", _on_run_ended)
    _connect("message", _on_message)
    _connect("game_state_changed", _on_game_state_changed)
    _connect("room_entered", _on_room_entered)
    _connect("floor_started", func(_depth, _floor): _reset_floor())
    _connect("run_started", func(_seed): _reset_floor())
    _connect("settings_changed", apply_settings)
    for signal_name in SIMPLE_SIGNALS:
        if events.has_signal(signal_name):
            var arity := _arity(signal_name)
            _connect(signal_name, play.bind(signal_name, 1.0).unbind(arity))


# --- Data -------------------------------------------------------------------------

static func load_data(path: String = DATA_PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


## Problems with an audio.json dictionary ([] = valid). `signal_names` are the
## Events signals; a cue's namespace (text before the first ".") must be one
## of them, a RESERVED name or a "pending_signals" entry (a signal another
## wave has not landed yet).
static func validate(map: Dictionary, signal_names: Array) -> Array[String]:
    var out: Array[String] = []
    if map.is_empty():
        return ["audio.json is missing or not a JSON object"]
    for key in map:
        if not ["schema_version", "_doc", "settings", "pending_signals", "cues", "states"].has(key):
            out.append("unknown top-level key '%s'" % key)
    if int(map.get("schema_version", 0)) != SCHEMA_VERSION:
        out.append("schema_version must be %d" % SCHEMA_VERSION)
    var settings = map.get("settings", {})
    if not settings is Dictionary:
        out.append("settings must be an object")
        settings = {}
    for key in settings:
        if not SETTINGS_DEFAULTS.has(key):
            out.append("unknown setting '%s'" % key)
    var pool_size := int(settings.get("pool_size", SETTINGS_DEFAULTS["pool_size"]))
    if pool_size < 1 or pool_size > 64:
        out.append("settings.pool_size must be 1-64")
    if int(settings.get("max_instances", 3)) < 1:
        out.append("settings.max_instances must be >= 1")
    if not _in_range(settings.get("crossfade_seconds", 0.6), 0.0, 10.0):
        out.append("settings.crossfade_seconds must be 0-10")
    if not _in_range(settings.get("attack_window", 0.5), 0.0, 5.0):
        out.append("settings.attack_window must be 0-5")
    var pending = map.get("pending_signals", [])
    if not pending is Array:
        out.append("pending_signals must be an array")
        pending = []
    var all_cues = map.get("cues", {})
    if not all_cues is Dictionary or all_cues.is_empty():
        out.append("cues must be a non-empty object")
        all_cues = {}
    for id in all_cues:
        out.append_array(_validate_cue(String(id), all_cues[id], signal_names, pending, pool_size))
    var states = map.get("states", {})
    if not states is Dictionary:
        out.append("states must be an object")
        states = {}
    for state in states:
        if not STATE_KEYS.has(state):
            out.append("unknown state '%s'" % state)
        var layers = states[state]
        if not layers is Dictionary:
            out.append("states.%s must be an object" % state)
            continue
        for layer in layers:
            var cue_id := String(layers[layer])
            if not LAYERS.has(layer):
                out.append("states.%s: unknown layer '%s'" % [state, layer])
            elif cue_id != "" and (not all_cues.has(cue_id) or \
                    String(all_cues[cue_id].get("bus", "")) != layer):
                out.append("states.%s.%s: '%s' is not a %s cue" % [state, layer, cue_id, layer])
    return out


static func _validate_cue(id: String, cue, signal_names: Array, pending: Array,
        pool_size: int) -> Array[String]:
    var out: Array[String] = []
    var where := "cue '%s'" % id
    var parts := id.split(".")
    var valid_id := parts.size() <= 2
    for part in parts:
        valid_id = valid_id and part != "" and part.to_lower() == part and not " " in part
    if not valid_id:
        out.append("%s: ids are 'name' or 'name.variant' in lower case" % where)
    var space := parts[0]
    if not (signal_names.has(space) or RESERVED.has(space) or pending.has(space)):
        out.append("%s: '%s' is not an Events signal, pending signal or %s" % [where, space,
            "/".join(RESERVED)])
    if not cue is Dictionary:
        out.append(where + " must be an object")
        return out
    for key in cue:
        if not CUE_KEYS.has(key):
            out.append("%s: unknown key '%s'" % [where, key])
    var stream := String(cue.get("stream", ""))
    if not stream.begins_with("res://") or not stream.ends_with(".wav"):
        out.append("%s: stream must be a res:// .wav path" % where)
    elif not FileAccess.file_exists(stream) and not ResourceLoader.exists(stream):
        out.append("%s: stream file %s does not exist" % [where, stream])
    var bus := String(cue.get("bus", ""))
    if not BUSES.has(bus):
        out.append("%s: bus must be one of %s" % [where, BUSES])
    var track := space == "music" or space == "ambient"
    if track and bus != ("Music" if space == "music" else "Ambient"):
        out.append("%s: %s cues play on the %s bus" % [where, space,
            "Music" if space == "music" else "Ambient"])
    if track != bool(cue.get("loop", false)):
        out.append("%s: loop is true exactly for music./ambient. cues" % where)
    if not track and LAYERS.has(bus):
        out.append("%s: only music./ambient. cues use the %s bus" % [where, bus])
    if not _in_range(cue.get("volume_db"), -60.0, 6.0):
        out.append("%s: volume_db must be a number in -60..6" % where)
    if not _in_range(cue.get("pitch_var"), 0.0, 0.5):
        out.append("%s: pitch_var must be a number in 0..0.5" % where)
    if not _in_range(cue.get("cooldown"), 0.0, 10.0):
        out.append("%s: cooldown must be a number in 0..10 (seconds)" % where)
    if cue.has("pitch") and not _in_range(cue["pitch"], 0.25, 4.0):
        out.append("%s: pitch must be in 0.25..4" % where)
    if cue.has("max_instances") and (not _in_range(cue["max_instances"], 1, pool_size) \
            or float(cue["max_instances"]) != floorf(float(cue["max_instances"]))):
        out.append("%s: max_instances must be a whole number 1..pool_size" % where)
    if cue.has("group") and (not cue["group"] is String or String(cue["group"]) == ""):
        out.append("%s: group must be a non-empty string" % where)
    return out


static func _in_range(value, low: float, high: float) -> bool:
    return (value is float or value is int) and float(value) >= low and float(value) <= high


# --- Internals ----------------------------------------------------------------------

func _build_players() -> void:
    for player in pool:
        player.queue_free()
    pool.clear()
    _pool_cue.clear()
    _busy_until.clear()
    for i in int(config["pool_size"]):
        var player := AudioStreamPlayer.new()
        player.name = "Sfx%d" % i
        player.bus = "SFX"
        add_child(player)
        pool.append(player)
        _pool_cue.append("")
        _busy_until.append(-1.0)
    for layer in LAYERS:
        if _layers.has(layer):
            continue
        var players: Array = []
        for k in 2:
            var player := AudioStreamPlayer.new()
            player.name = "%s%d" % [layer, k]
            player.bus = layer
            add_child(player)
            players.append(player)
        _layers[layer] = {"players": players, "active": 0, "cue": "", "tweens": [null, null]}


func _free_player() -> int:
    var n := pool.size()
    for step in n:
        var index := (_cursor + step) % n
        if _busy_until[index] <= clock:
            _cursor = (index + 1) % n
            return index
    # All busy: steal the round-robin slot (the oldest start, roughly).
    var stolen := _cursor
    _cursor = (_cursor + 1) % n
    return stolen


func _stream(cue: Dictionary) -> AudioStream:
    var path := String(cue.get("stream", ""))
    if path == "":
        return null
    if not _streams.has(path):
        var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
        var wav := stream as AudioStreamWAV
        if wav != null and bool(cue.get("loop", false)) \
                and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
            # Fallback when the import did not pick up the WAV's smpl loop.
            wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
            wav.loop_begin = 0
            wav.loop_end = int(wav.get_length() * wav.mix_rate)
        _streams[path] = stream
    return _streams[path]


func _fade(slot: Dictionary, index: int, target_db: float, seconds: float, stop_after: bool) -> void:
    var player: AudioStreamPlayer = slot["players"][index]
    var old: Tween = slot["tweens"][index]
    if old != null and old.is_valid():
        old.kill()
    slot["tweens"][index] = null
    if seconds <= 0.0 or not player.is_inside_tree():
        player.volume_db = target_db
        if stop_after:
            player.stop()
        return
    var tween := create_tween()
    var from := db_to_linear(player.volume_db)
    var to := db_to_linear(target_db) if target_db > SILENT_DB else 0.0
    tween.tween_method(func(v: float): player.volume_db = linear_to_db(maxf(v, 0.0001)),
        from, to, seconds)
    if stop_after:
        tween.tween_callback(player.stop)
    slot["tweens"][index] = tween


## Picks the Music / Ambient cues for the current state (data "states").
func _apply_tracks() -> void:
    var states: Dictionary = data.get("states", {})
    var key := game_state
    if game_state == "RUNNING" and in_boss_room and states.has("RUNNING.boss"):
        key = "RUNNING.boss"
    if not states.has(key):
        return  # modal states keep whatever is playing
    var layers: Dictionary = states[key]
    for layer in LAYERS:
        set_track(layer, String(layers.get(layer, "")))


func _reset_floor() -> void:
    boss_dead = false
    in_boss_room = false
    _apply_tracks()


func _signal_names() -> Array:
    var names: Array = []
    var script: Script = load("res://scripts/core/events.gd")
    for info in script.get_script_signal_list():
        names.append(String(info["name"]))
    return names


func _arity(signal_name: String) -> int:
    for info in _events.get_signal_list():
        if info["name"] == signal_name:
            return info["args"].size()
    return 0


func _connect(signal_name: String, callable: Callable) -> void:
    if _events.has_signal(signal_name) and not _events.is_connected(signal_name, callable):
        _events.connect(signal_name, callable)


func _hook_ui_tree() -> void:
    if not is_inside_tree():
        return
    var tree := get_tree()
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    var stack: Array[Node] = [tree.root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        _on_node_added(node)
        stack.append_array(node.get_children())


func _on_node_added(node: Node) -> void:
    if not (node is BaseButton or node is Slider) or node.has_meta(&"audio_hooked"):
        return
    node.set_meta(&"audio_hooked", true)
    node.focus_entered.connect(play.bind("ui.move", 1.0))
    if node is BaseButton:
        node.pressed.connect(play.bind("ui.confirm", 1.0))
    else:
        node.value_changed.connect(play.bind("ui.move", 1.0).unbind(1))


# --- Event handlers -----------------------------------------------------------------

func _on_melee_swung(owner: String, _position: Vector2, _direction: Vector2) -> void:
    if owner == "player":
        _last_attack = {"kind": "melee", "at": clock}
    play("melee_swung." + owner)


func _on_projectile_fired(owner: String, _data: Dictionary) -> void:
    if owner == "player":
        _last_attack = {"kind": "ranged", "at": clock}
    play("projectile_fired." + owner)


func _on_enemy_damaged(_instance_id: String, _amount: int, critical: bool) -> void:
    if critical and cues.has("enemy_damaged.critical"):
        play("enemy_damaged.critical")
        return
    var id := "enemy_damaged"
    if clock - float(_last_attack["at"]) <= float(config["attack_window"]):
        var variant := "enemy_damaged." + String(_last_attack["kind"])
        if cues.has(variant):
            id = variant
    play(id)


func _on_boss_defeated(_definition_id: String) -> void:
    boss_dead = true
    in_boss_room = false
    play("boss_defeated")
    _apply_tracks()


func _on_player_damaged(_amount: int, source: String) -> void:
    var hazard := source.begins_with("hazard") or "debris" in source or "trap" in source
    play("player_damaged.hazard" if hazard and cues.has("player_damaged.hazard")
        else "player_damaged")


func _on_credits_changed(amount: int, _total: int) -> void:
    if amount > 0:
        play("credits_changed.gain")
    elif amount < 0:
        play("credits_changed.spend")


func _on_ticks_changed(before: int, after: int, _reason: String) -> void:
    if after > before:
        play("ticks_changed.gain")
    elif after < before:
        play("ticks_changed.loss")


func _on_run_ended(outcome: String, _summary: Dictionary) -> void:
    play("run_ended.victory" if VICTORY_OUTCOMES.has(outcome) else "run_ended.defeat")


func _on_message(_text: String, category: String) -> void:
    play("message." + category)  # only categories with a cue make a sound


func _on_game_state_changed(previous: String, current: String) -> void:
    game_state = current
    if previous == "RUNNING" and MENU_STATES.has(current):
        play("ui.open")
    elif current == "RUNNING" and MODAL_STATES.has(previous):
        play("ui.back")
    _apply_tracks()


func _on_room_entered(_room_id: int, kind: String, _entry: Dictionary, _first: bool) -> void:
    in_boss_room = kind == "boss" and not boss_dead
    _apply_tracks()
