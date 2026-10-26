extends SceneTree
## Audio (Wave 3A): audio.json validation (streams exist, buses, every Events
## signal named exists, every code cue mapped), the bus layout, volume -> dB,
## then a live Audio node on the real Events bus (100-hit burst stays inside
## the pool, cooldowns and caps, payload variants, settings, state -> track
## selection and crossfade, button hooks) and Audio inside Main.tscn.
## Run: godot --headless --path game --script res://tests/audio_test.gd
## audio.gd reads no autoload identifiers, so it may be preloaded.
const Audio = preload("res://scripts/audio.gd")
const Settings = preload("res://scripts/core/settings.gd")
var failures := 0


func _initialize() -> void:
    _test_shipped_data()
    _test_validator_rejects()
    _test_volume_mapping()
    _test_bus_layout()
    _test_settings_keys()
    call_deferred("_test_live")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL AUDIO: " + detail)


func _signal_names() -> Array:
    var names: Array = []
    for info in load("res://scripts/core/events.gd").get_script_signal_list():
        names.append(String(info["name"]))
    return names


func _test_shipped_data() -> void:
    var data: Dictionary = Audio.load_data()
    check(not data.is_empty(), "audio.json parses")
    var signals := _signal_names()
    var problems: Array[String] = Audio.validate(data, signals)
    check(problems.is_empty(), "shipped audio.json validates: %s" % [problems])
    var cues: Dictionary = data.get("cues", {})
    for id in Audio.CODE_CUES:
        check(cues.has(id), "cue '%s' used by audio.gd is mapped" % id)
    var pending: Array = data.get("pending_signals", [])
    for name in Audio.SIMPLE_SIGNALS:
        check(signals.has(name) or pending.has(name),
            "simple hook %s is an Events signal or pending" % name)
        check(cues.has(name), "simple hook %s has a cue" % name)
    for id in cues:
        var space := String(id).split(".")[0]
        if not Audio.RESERVED.has(space) and not pending.has(space):
            check(signals.has(space), "cue %s names a real Events signal" % id)
        var stream := String(cues[id]["stream"])
        check(ResourceLoader.exists(stream), "cue %s stream %s is imported" % [id, stream])
    for state in ["TITLE", "RUNNING", "RUNNING.boss", "INTERMISSION", "SUMMARY"]:
        check(data["states"].has(state), "states maps " + state)
    # Every generated file is used, and the set stays small.
    var used: Dictionary = {}
    for id in cues:
        used[String(cues[id]["stream"])] = true
    var total := 0
    for folder in ["sfx", "ambient", "music"]:
        var dir_path := "res://assets/audio/%s/" % folder
        for file in DirAccess.get_files_at(dir_path):
            if file.ends_with(".wav"):
                total += FileAccess.get_file_as_bytes(dir_path + file).size()
                check(used.has(dir_path + file) or file in ["ui_move.wav"],
                    "audio file %s%s is mapped" % [dir_path, file])
    check(total > 0 and total < 3 * 1024 * 1024, "audio assets under 3 MB (%d bytes)" % total)
    var loop: AudioStreamWAV = load("res://assets/audio/ambient/crypt_drone.wav")
    check(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD,
        "ambient loop imported with its smpl forward loop")
    var sfx: AudioStreamWAV = load("res://assets/audio/sfx/melee_hit.wav")
    check(sfx != null and sfx.loop_mode == AudioStreamWAV.LOOP_DISABLED and sfx.get_length() < 0.5,
        "melee_hit is a short one-shot")


func _test_validator_rejects() -> void:
    var signals := _signal_names()
    var broken: Dictionary = Audio.load_data()
    var cues: Dictionary = broken["cues"]
    cues["not_a_signal"] = cues["enemy_killed"].duplicate()
    cues["enemy_killed"] = cues["enemy_killed"].duplicate()
    cues["enemy_killed"]["stream"] = "res://assets/audio/sfx/nope.wav"
    cues["level_up"] = cues["level_up"].duplicate()
    cues["level_up"]["bus"] = "Voices"
    cues["dodged"] = cues["dodged"].duplicate()
    cues["dodged"]["pitch_var"] = 0.9
    cues["dodged"]["mood"] = "smug"
    cues["item_used"] = cues["item_used"].duplicate()
    cues["item_used"]["cooldown"] = "soon"
    cues["xp_gained"] = cues["xp_gained"].duplicate()
    cues["xp_gained"]["max_instances"] = 99
    cues["music.title"] = cues["music.title"].duplicate()
    cues["music.title"]["bus"] = "SFX"
    cues["Bad.Id.Here"] = cues["item_used"].duplicate()
    broken["states"]["PAUSED"] = {"Music": "enemy_killed", "Voice": ""}
    broken["states"]["NOWHERE"] = {}
    broken["settings"]["pool_size"] = 0
    var joined := "\n".join(Audio.validate(broken, signals))
    for needle in ["'not_a_signal' is not an Events signal", "nope.wav does not exist",
            "bus must be one of", "pitch_var must be", "unknown key 'mood'", "cooldown must be",
            "max_instances must be", "music cues play on the Music bus", "lower case",
            "states.PAUSED.Music", "unknown layer 'Voice'", "unknown state 'NOWHERE'",
            "pool_size must be"]:
        check(needle in joined, "validator reports: " + needle)
    var pending: Dictionary = Audio.load_data()
    pending["pending_signals"] = []
    var gone := "\n".join(Audio.validate(pending, signals))
    if not signals.has("skill_used"):
        check("'skill_used' is not an Events signal" in gone,
            "an unlanded signal must be listed in pending_signals")
    check(not Audio.validate({}, signals).is_empty(), "validator rejects an empty map")


func _test_volume_mapping() -> void:
    check(Audio.volume_to_db(0.0) == -80.0, "volume 0 -> -80 dB")
    check(is_equal_approx(Audio.volume_to_db(1.0), 0.0), "volume 1 -> 0 dB")
    check(absf(Audio.volume_to_db(0.5) - (-6.0206)) < 0.01, "volume 0.5 -> -6 dB")
    check(Audio.volume_to_db(0.00001) == -80.0, "tiny volume clamps to -80 dB")
    check(Audio.volume_to_db(-1.0) == -80.0 and is_equal_approx(Audio.volume_to_db(3.0), 0.0),
        "out-of-range volumes clamp")


func _test_bus_layout() -> void:
    Audio.ensure_buses()
    for bus in Audio.BUSES:
        var index := AudioServer.get_bus_index(bus)
        check(index > 0, "bus %s exists" % bus)
        if index > 0:
            check(AudioServer.get_bus_send(index) == &"Master", "bus %s sends to Master" % bus)
    check(ProjectSettings.get_setting("audio/buses/default_bus_layout") ==
        "res://default_bus_layout.tres", "project uses default_bus_layout.tres")
    var layout: AudioBusLayout = load("res://default_bus_layout.tres")
    check(layout != null, "default_bus_layout.tres loads")


func _test_settings_keys() -> void:
    var fresh = Settings.new("user://test/audio_settings.cfg")
    check(is_equal_approx(fresh.music_volume, 0.8) and is_equal_approx(fresh.sfx_volume, 1.0),
        "music 0.8 / effects 1.0 defaults")
    fresh.set_value("music_volume", 0.25)
    fresh.set_value("sfx_volume", 7.0)
    check(is_equal_approx(fresh.music_volume, 0.25) and fresh.sfx_volume == 1.0,
        "volume keys accepted and clamped")
    DirAccess.make_dir_recursive_absolute("user://test")
    check(fresh.save_settings(), "settings save")
    var loaded = Settings.new("user://test/audio_settings.cfg")
    check(loaded.load_settings() and is_equal_approx(loaded.music_volume, 0.25)
        and loaded.to_dict().has("sfx_volume"), "volume keys persist")


func _connected_to(events: Node, signal_name: String, target: Object) -> bool:
    for connection in events.get_signal_connection_list(signal_name):
        var callable: Callable = connection["callable"]
        if callable.get_object() == target:
            return true
    return false


func _test_live() -> void:
    var events: Node = get_root().get_node("Events")
    var audio = Audio.new()
    audio.name = "AudioUnderTest"
    get_root().add_child(audio)
    check(audio.problems.is_empty(), "live audio loaded a valid map: %s" % [audio.problems])
    check(audio.pool.size() == 12, "12 pooled SFX players")
    check(audio.process_mode == Node.PROCESS_MODE_ALWAYS, "audio keeps running while paused")
    for name in ["melee_swung", "projectile_fired", "enemy_damaged", "enemy_killed",
            "player_damaged", "ticks_changed", "game_state_changed", "settings_changed",
            "chest_opened", "level_up", "doors_locked", "skill_learned"]:
        check(_connected_to(events, name, audio), "audio listens to Events." + name)
    check(audio.current_track("Music") == "music.title", "boots into title music")

    # Burst: 100 hits in one frame play once (cooldown) and never exceed the pool.
    audio.clock = 10.0
    var before: int = audio.played
    for i in 100:
        events.enemy_damaged.emit("1_%d" % i, 3, false)
    check(audio.played - before == 1, "100 simultaneous hits play once (%d)" % (audio.played - before))
    check(audio.throttled >= 99, "the rest are throttled")
    # Spread over time: cooldown lets some through, the cap holds the rest.
    for i in 100:
        audio.clock += 0.01
        events.enemy_damaged.emit("1_%d" % i, 3, false)
        check(audio.busy_count() <= audio.pool.size(), "busy players never exceed the pool")
        check(audio.active_count("enemy_damaged") <= 3, "at most 3 identical hits at once")

    # Cooldown on one cue.
    audio.clock = 100.0
    check(audio.play("enemy_killed"), "first death sound plays")
    check(not audio.play("enemy_killed"), "an immediate repeat is throttled")
    audio.clock += 0.06
    check(audio.play("enemy_killed"), "plays again after its 0.05 s cooldown")
    # Group cooldown: ui cues share one.
    check(audio.play("ui.confirm") and not audio.play("ui.move"), "ui cues share a cooldown group")
    # Cap on simultaneous copies, and pool stealing when everything is busy.
    audio.cues["test.long"] = {"stream": "res://assets/audio/sfx/boss_death.wav", "bus": "SFX",
        "volume_db": -40.0, "pitch_var": 0.0, "cooldown": 0.0, "max_instances": 2}
    var ok := 0
    for i in 5:
        ok += 1 if audio.play("test.long") else 0
    check(ok == 2 and audio.active_count("test.long") == 2, "max_instances caps copies (%d)" % ok)
    audio.cues["test.flood"] = {"stream": "res://assets/audio/sfx/boss_death.wav", "bus": "SFX",
        "volume_db": -40.0, "pitch_var": 0.0, "cooldown": 0.0, "max_instances": 64}
    for i in 30:
        check(audio.play("test.flood"), "flood play %d accepted (steals a player)" % i)
    check(audio.busy_count() == audio.pool.size(), "a flood fills, and stays inside, the pool")
    audio.cues.erase("test.long")
    audio.cues.erase("test.flood")
    # Pitch variation stays within the cue's spread.
    audio.clock = 200.0
    var pitches: Array = []
    for i in 20:
        audio.clock += 1.0
        audio.play("melee_swung.player")
        for player in audio.pool:
            if player.stream != null and player.stream.resource_path.ends_with("melee_swing.wav"):
                pitches.append(player.pitch_scale)
    var low: float = pitches.min()
    var high: float = pitches.max()
    check(low >= 0.94 - 0.0001 and high <= 1.06 + 0.0001 and high > low,
        "combat pitch varies within +-6 %% (%.3f..%.3f)" % [low, high])

    # Payload variants.
    audio.clock = 300.0
    events.melee_swung.emit("player", Vector2.ZERO, Vector2.RIGHT)
    events.enemy_damaged.emit("2_1", 4, false)
    check(audio.last_cue == "enemy_damaged.melee", "hit after a swing -> melee hit (%s)" % audio.last_cue)
    audio.clock += 1.0
    events.projectile_fired.emit("player", {})
    events.enemy_damaged.emit("2_1", 4, false)
    check(audio.last_cue == "enemy_damaged.ranged", "hit after a shot -> ranged hit")
    audio.clock += 1.0
    events.enemy_damaged.emit("2_1", 9, true)
    check(audio.last_cue == "enemy_damaged.critical", "critical hit cue")
    check(is_equal_approx(float(audio.cues["enemy_damaged.critical"]["pitch"]), 1.3),
        "critical hits play higher")
    audio.clock += 1.0
    events.enemy_damaged.emit("2_1", 1, false)
    check(audio.last_cue == "enemy_damaged", "a hit with no recent attack (DoT) -> generic hurt")
    audio.clock += 1.0
    events.projectile_fired.emit("enemy", {})
    check(audio.last_cue == "projectile_fired.enemy", "enemy shots have their own sound")
    audio.clock += 1.0
    audio._on_ticks_changed(5, 3, "door")
    check(audio.last_cue == "ticks_changed.loss", "ticks lost")
    audio.clock += 1.0
    audio._on_ticks_changed(3, 5, "shrine")
    check(audio.last_cue == "ticks_changed.gain", "ticks gained")
    audio.clock += 1.0
    audio._on_credits_changed(-20, 5)
    check(audio.last_cue == "credits_changed.spend", "spending credits -> shop sound")
    audio.clock += 1.0
    audio._on_player_damaged(2, "hazard:spore")
    check(audio.last_cue == "player_damaged.hazard", "hazard damage -> hazard hit")
    audio.clock += 1.0
    audio._on_run_ended("victory", {})
    check(audio.last_cue == "run_ended.victory", "victory sting")
    audio.clock += 2.0
    audio._on_run_ended("collapsed", {})
    check(audio.last_cue == "run_ended.defeat", "defeat sting")
    audio.clock += 2.0
    var count: int = audio.played
    events.message.emit("hello", "info")
    check(audio.played == count, "info messages are silent")
    events.message.emit("Grace!", "collapse")
    check(audio.last_cue == "message.collapse", "collapse messages blip")
    audio.clock += 2.0
    events.chest_opened.emit(3, [])
    check(audio.last_cue == "chest_opened", "simple hook: chest_opened")

    # Settings -> bus volumes.
    audio.apply_settings({"master_volume": 0.0, "music_volume": 1.0, "sfx_volume": 0.5})
    var master := AudioServer.get_bus_index("Master")
    check(AudioServer.get_bus_volume_db(master) == -80.0 and AudioServer.is_bus_mute(master),
        "master 0 -> -80 dB and muted")
    check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), 0.0),
        "music 1 -> 0 dB")
    check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")) + 6.02) < 0.01,
        "effects 0.5 -> UI bus -6 dB")
    var values: Dictionary = Settings.new().to_dict()
    values["sfx_volume"] = 0.25
    events.settings_changed.emit(values)
    check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) + 12.04) < 0.02,
        "Events.settings_changed re-applies volumes")
    check(not AudioServer.is_bus_mute(master), "master unmuted again")

    # Game state -> tracks.
    var title_player: AudioStreamPlayer = audio.track_player("Music")
    events.game_state_changed.emit("TITLE", "RUNNING")
    check(audio.current_track("Ambient") == "ambient.crypt" and audio.current_track("Music") == "",
        "RUNNING -> crypt ambience, no music")
    audio._on_room_entered(4, "boss", {}, true)
    check(audio.current_track("Ambient") == "ambient.boss", "boss room -> boss drone")
    events.game_state_changed.emit("RUNNING", "PAUSED")
    check(audio.current_track("Ambient") == "ambient.boss", "pause keeps the current track")
    check(audio.last_cue == "ui.open", "pausing opens with a ui sound")
    audio.clock += 1.0
    events.game_state_changed.emit("PAUSED", "RUNNING")
    check(audio.last_cue == "ui.back", "resuming plays ui.back")
    audio._on_boss_defeated("brute_boss")
    check(audio.current_track("Ambient") == "ambient.crypt", "boss dead -> crypt ambience")
    audio._on_room_entered(4, "boss", {}, false)
    check(audio.current_track("Ambient") == "ambient.crypt", "a cleared boss room stays calm")
    events.game_state_changed.emit("RUNNING", "INTERMISSION")
    check(audio.current_track("Music") == "music.intermission" and audio.current_track("Ambient") == "",
        "INTERMISSION -> low music")
    var low_player: AudioStreamPlayer = audio.track_player("Music")
    events.game_state_changed.emit("INTERMISSION", "SUMMARY")
    check(audio.current_track("Music") == "music.intermission", "SUMMARY -> low music")
    events.game_state_changed.emit("SUMMARY", "TITLE")
    check(audio.current_track("Music") == "music.title" and audio.track_player("Music") == low_player,
        "same stream: title music continues on the same player")
    check(low_player.playing, "music plays headless (Dummy driver)")
    audio._reset_floor()
    events.game_state_changed.emit("TITLE", "RUNNING")
    var ambient_player: AudioStreamPlayer = audio.track_player("Ambient")
    check(ambient_player.playing and ambient_player.stream.resource_path.ends_with("crypt_drone.wav"),
        "ambient player runs the crypt drone")
    await create_timer(0.9).timeout
    check(not low_player.playing, "the music faded out and stopped after the crossfade")
    check(absf(ambient_player.volume_db - float(audio.cues["ambient.crypt"]["volume_db"])) < 0.5,
        "the ambience faded in to its cue volume (%.1f dB)" % ambient_player.volume_db)
    check(title_player != null, "title player existed")

    # Buttons added later are hooked.
    var button := Button.new()
    get_root().add_child(button)
    check(button.has_meta(&"audio_hooked"), "new buttons are hooked through node_added")
    audio.clock += 5.0
    button.pressed.emit()
    check(audio.last_cue == "ui.confirm", "button press -> ui.confirm")
    button.queue_free()
    audio.queue_free()
    events.settings_changed.emit(Settings.new().to_dict())
    await process_frame
    _test_game()


func _test_game() -> void:
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    var audio = game.get_node_or_null("Audio")
    check(audio != null and audio == game.audio, "Game composes the Audio node")
    if audio == null:
        game.queue_free()
        _finish()
        return
    check(audio.problems.is_empty() and audio.current_track("Music") == "music.title",
        "title screen plays title music")
    check(audio.played == 0 or audio.last_cue.begins_with("ui."), "boot plays at most ui sounds")
    game.start_run(424242)
    check(audio.game_state == "RUNNING" and audio.current_track("Ambient") == "ambient.crypt",
        "a new run switches to the crypt ambience")
    for i in 5:
        await physics_frame
    game.queue_free()
    await process_frame
    _finish()


func _finish() -> void:
    if failures == 0:
        print("PASS: audio map, buses, volumes, pool/cooldown/cap, variants, tracks, crossfade, ui hooks, Game wiring")
    quit(1 if failures > 0 else 0)
