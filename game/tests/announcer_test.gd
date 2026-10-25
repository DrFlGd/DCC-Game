extends SceneTree
## Dungeon-system announcer: line data validator, placeholder resolution,
## seeded selection, cooldowns, once_per_run, priority preemption, rate limit,
## modal suppression (pure AnnouncerBrain), then the live Announcer inside
## Main.tscn (toasts, log, achievements, custom announcements, telemetry file).
## Run: godot --headless --path game --script res://tests/announcer_test.gd
## Only pure modules are preloaded; the Announcer node is load()ed via the scene.
const Lines = preload("res://scripts/core/announcer_lines.gd")
const Brain = preload("res://scripts/core/announcer_brain.gd")
const Profile = preload("res://scripts/core/profile.gd")
var failures := 0


func _initialize() -> void:
    _test_shipped_data()
    _test_validator_rejects()
    _test_placeholders()
    _test_determinism()
    _test_cooldown_and_once()
    _test_rate_limit_and_preemption()
    _test_modal()
    call_deferred("_test_live")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ANNOUNCER: " + detail)


func _line(text: String, priority: int, cooldown: float = 0.0, once: bool = false) -> Dictionary:
    return {"text": text, "weight": 1.0, "priority": priority, "cooldown_seconds": cooldown,
        "once_per_run": once, "category": "flavour"}


func _synthetic(settings: Dictionary = {}) -> Dictionary:
    return {"schema_version": 1, "settings": settings, "lines": {
        "low": [_line("low one {depth}", 1)],
        "mid": [_line("mid one", 3)],
        "high": [_line("high one", 4)],
        "top": [_line("top one", 5)],
        "cool": [_line("cool one", 1, 10.0)],
        "once": [_line("once a", 1, 0.0, true), _line("once b", 1, 0.0, true)]
    }}


func _test_shipped_data() -> void:
    var data: Dictionary = Lines.load_data()
    check(not data.is_empty(), "announcer.json parses")
    var problems: Array[String] = Lines.validate(data)
    check(problems.is_empty(), "shipped announcer.json validates: %s" % [problems])
    var counts: Dictionary = Lines.count_lines(data)
    var total := 0
    for trigger in counts:
        total += int(counts[trigger])
    check(total >= 120, "at least 120 lines (has %d)" % total)
    for trigger in Lines.COMMON_TRIGGERS:
        check(int(counts.get(trigger, 0)) >= 5, "common trigger %s has >= 5 lines" % trigger)
    for kind in Lines.ROOM_KINDS:
        check(counts.has("room_entered." + kind), "lines for room kind " + kind)
    var settings: Dictionary = Lines.settings_with_defaults(data["settings"])
    check(float(settings["rate_limit_seconds"]) == 2.5 and int(settings["max_visible"]) == 2,
        "shipped rate limit 2.5 s, two toasts")


func _test_validator_rejects() -> void:
    var broken: Dictionary = Lines.load_data()
    var lines: Dictionary = broken["lines"]
    lines["not_a_trigger"] = [_line("orphan", 1)]
    lines["run_started"][0]["text"] = "Welcome to {nowhere}."
    lines["run_started"][1]["priority"] = 9
    lines["run_started"][2]["category"] = "gossip"
    lines["run_started"][3]["text"] = lines["run_started"][4]["text"]
    lines["run_started"][5]["once_per_run"] = "yes"
    lines["level_up"][0]["text"] = "x".repeat(95)
    lines["low_hp"][0]["weight"] = 0
    lines["idle"][0]["text"] = "Unbalanced {depth"
    lines["first_blood"][0]["mood"] = "smug"
    lines.erase("ticks_low")
    lines["kill_streak.4"] = [_line("four", 1)]
    var problems: Array[String] = Lines.validate(broken)
    var joined: String = "\n".join(problems)
    for needle in ["unknown trigger 'not_a_trigger'", "placeholder {nowhere}", "priority must be in",
            "category must be one of", "duplicate text", "once_per_run must be", "longer than 90",
            "weight must be in", "malformed {placeholder}", "unknown key 'mood'",
            "ticks_low needs at least 5", "unknown trigger 'kill_streak.4'"]:
        check(needle in joined, "validator reports: " + needle)
    check(not Lines.validate({"schema_version": 1, "settings": {"max_visible": 9}, "lines": {}})
        .is_empty(), "validator rejects out-of-range settings")
    check(not Lines.validate({}).is_empty(), "validator rejects an empty file")


func _test_placeholders() -> void:
    check(Lines.resolve("Floor {depth}, {kills} kills, {nope}.", {"depth": 3, "kills": 7}) ==
        "Floor 3, 7 kills, ?.", "placeholders resolve; unknown ones become ?")
    check(Lines.placeholders("{enemy} hit for {damage}") == ["enemy", "damage"], "placeholder scan")
    check(Lines.placeholders_for("enemy_killed.rat_scavenger").has("enemy"), "prefix placeholders")
    check(not Lines.placeholders_for("run_started").has("enemy"), "no {enemy} on run_started")
    var brain := Brain.new(_synthetic())
    var entry: Dictionary = brain.pick("low", {"depth": 4}, 0.0)
    check(entry["text"] == "low one 4", "brain resolves the picked line")


func _sequence(seed_value: int) -> Array:
    var data: Dictionary = Lines.load_data()
    var brain := Brain.new(data)
    brain.reset_run(seed_value)
    var texts: Array = []
    var now := 0.0
    var context := {"depth": 2, "kills": 5, "ticks": 9, "seed": seed_value, "level": 3, "hp": 4,
        "max_hp": 12, "xp": 300, "room": 7, "enemy": "Rat", "damage": 5, "streak": 3,
        "achievement": "A", "quip": "Q", "idle": 30}
    for _round in range(4):
        for trigger in ["run_started", "room_entered.normal", "level_up", "low_hp", "idle",
                "ticks_low", "boss_defeated", "chest_opened"]:
            now += 100.0
            texts.append(String(brain.pick(trigger, context, now).get("text", "")))
    return texts


func _test_determinism() -> void:
    var first: Array = _sequence(424242)
    check(first == _sequence(424242), "same seed and events replay the same lines")
    check(first != _sequence(77), "a different seed picks different lines")
    check(not first.has(""), "every request in the sequence picked a line")


func _test_cooldown_and_once() -> void:
    var brain := Brain.new(_synthetic())
    brain.reset_run(1)
    check(not brain.pick("cool", {}, 0.0).is_empty(), "cooldown trigger fires")
    check(brain.pick("cool", {}, 5.0).is_empty(), "cooldown blocks a repeat")
    check(not brain.pick("cool", {}, 10.5).is_empty(), "cooldown expires")
    var seen: Dictionary = {}
    for _i in range(2):
        seen[brain.pick("once", {}, 0.0).get("text", "")] = true
    check(seen.has("once a") and seen.has("once b"), "both once_per_run lines used")
    check(brain.pick("once", {}, 1.0).is_empty(), "once_per_run lines exhausted for the run")
    brain.reset_run(2)
    check(not brain.pick("once", {}, 2.0).is_empty(), "reset_run restores once_per_run lines")
    check(brain.pick("missing", {}, 0.0).is_empty(), "unknown trigger picks nothing")


func _test_rate_limit_and_preemption() -> void:
    var brain := Brain.new(_synthetic())
    brain.reset_run(1)
    var first: Dictionary = brain.announce("low", {}, 0.0)
    check(first["status"] == "shown", "first toast shows immediately")
    var second: Dictionary = brain.announce("low", {}, 0.5)
    check(second["status"] == "queued", "second low-priority toast waits for the rate limit")
    brain.update(2.0)
    check(second["status"] == "queued", "still rate limited at 2.0 s")
    brain.update(2.6)
    check(second["status"] == "shown" and first["status"] == "expired",
        "queued toast shows after 2.5 s, first expired")

    brain = Brain.new(_synthetic())
    brain.reset_run(1)
    var low: Dictionary = brain.announce("low", {}, 0.0)
    var high: Dictionary = brain.announce("high", {}, 0.1)
    check(high["status"] == "shown" and brain.on_screen.size() == 2,
        "priority 4 bypasses the rate limit into the second slot")
    var top: Dictionary = brain.announce("top", {}, 0.2)
    check(top["status"] == "queued", "no preemption before the minimum on-screen time")
    brain.update(1.05)
    check(top["status"] == "shown" and low["status"] == "preempted",
        "higher priority preempts the weakest toast after the minimum time")
    check(brain.on_screen.size() == 2, "never more than two toasts")
    var mid: Dictionary = brain.announce("mid", {}, 1.1)
    var high2: Dictionary = brain.custom("custom high", 4, "system", 1.1)
    check(brain.queue[0] == high2 and brain.queue[1] == mid, "queue is ordered by priority")

    brain = Brain.new(_synthetic({"rate_limit_seconds": 10.0}))
    brain.reset_run(1)
    brain.announce("low", {}, 0.0)
    var waiting: Dictionary = brain.announce("mid", {}, 0.5)
    brain.update(5.0)
    check(waiting["status"] == "dropped_stale", "low-priority toasts go stale in the queue")
    check(Brain.duration_for("short", brain.settings) == 2.5, "short toasts last 2.5 s")
    check(Brain.duration_for("x".repeat(400), brain.settings) == 5.0, "long toasts capped")


func _test_modal() -> void:
    var brain := Brain.new(_synthetic())
    brain.reset_run(1)
    var shown_high: Dictionary = brain.announce("high", {}, 0.0)
    brain.set_modal(true, 0.3)
    check(brain.on_screen.is_empty(), "opening a modal hides toasts")
    check(shown_high["status"] == "queued", "a fresh priority-4 toast is requeued, not lost")
    var low: Dictionary = brain.announce("low", {}, 0.4)
    var top: Dictionary = brain.announce("top", {}, 0.5)
    check(low["status"] == "dropped_modal", "low priority dropped while modal")
    brain.update(3.0)
    check(top["status"] == "queued" and brain.on_screen.is_empty(), "nothing shows while modal")
    brain.set_modal(false, 9.0)
    check(top["status"] == "shown" and shown_high["status"] == "shown",
        "priority >= 4 toasts show once the modal closes, however long it was open")
    check(brain.log_lines.size() == 3, "log keeps every selected line, shown or not")


# --- Live Announcer inside Main.tscn ----------------------------------------

func _test_live() -> void:
    var events: Node = get_root().get_node("Events")
    var run_state: Node = get_root().get_node("RunState")
    Profile.use_path("user://test/announcer_live_profile.json")
    DirAccess.remove_absolute(Profile.profile_path)
    Profile.refresh()
    var unlocked: Array = []
    var messages: Array = []
    events.achievement_unlocked.connect(func(id): unlocked.append(id))
    events.message.connect(func(text, _category): messages.append(text))
    var game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    var announcer = game.get_node_or_null("Announcer")
    check(announcer != null and announcer == game.announcer, "Game composes the Announcer")
    if announcer == null:
        _finish()
        return
    var brain = announcer.brain
    check(announcer.problems.is_empty(), "live announcer loaded valid lines")
    check(announcer.layer > 20, "toast layer sits above run-loop screens")
    check(_triggers(brain).has("run_started"), "run_started line on boot")
    check(InputMap.has_action("toggle_log") and not InputMap.action_get_events("toggle_log").is_empty(),
        "toggle_log action bound")

    # First kill: first_blood line + achievement (toast, profile), once only.
    messages.clear()
    events.enemy_killed.emit("rat_scavenger", 0, Vector2.ZERO)
    check(_triggers(brain).has("first_blood"), "first kill -> first_blood")
    check(unlocked.count("first_blood") == 1 and Profile.is_unlocked("first_blood"),
        "first kill unlocks and saves the achievement")
    check(_triggers(brain).has("achievement_unlocked"), "achievement toast queued")
    events.enemy_killed.emit("rat_scavenger", 0, Vector2.ZERO)
    check(unlocked.count("first_blood") == 1, "achievement never unlocks twice")
    var reloaded: Dictionary = Profile.load_profile()
    check(reloaded["achievements"].has("first_blood"), "unlock persisted to disk")

    # Custom announcements from other systems; the HUD line is left alone.
    events.announcement_requested.emit("trap_room_custom", {"text": "Custom words.", "priority": 4})
    check(_texts(brain).has("Custom words."), "custom text announcement")
    events.announcement_requested.emit("chest_opened", {})
    check(_triggers(brain).has("chest_opened"), "announcement_requested picks data lines")
    check(messages.is_empty(), "announcer never writes the HUD message line")

    # Modal: pause suppresses toasts; the log still records.
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    game._input(escape)
    announcer._process(0.016)
    check(announcer.is_modal() and brain.modal and brain.on_screen.is_empty(),
        "pause menu suppresses toasts")
    game.character_menu._open_achievements_page()
    check(game.character_menu.page == "achievements", "pause menu has an Achievements page")
    game._input(escape)
    announcer._process(0.016)
    check(not brain.modal, "closing the pause reopens the toast gate")

    # System log panel.
    announcer.toggle_log()
    announcer._process(0.016)
    check(announcer._log_panel.visible and announcer._log_text.get_parsed_text().length() > 0,
        "toggle_log shows the system log")
    announcer.toggle_log()

    # Death: obituary line, profile stats, telemetry report.
    game.player.invulnerability = 0.0
    for _i in range(100):
        if run_state.hp <= 0:
            break
        game.player.invulnerability = 0.0
        game.combat.hit_player(30, 6, 1, "rat_scavenger")
    check(_triggers(brain).has("run_ended.defeated"), "death -> run_ended.defeated line")
    check(Profile.total_runs() == 1 and Profile.deaths_by_cause().get("rat_scavenger", 0) == 1,
        "profile records the run and cause")
    check(Profile.best_depth() == 1, "Profile.best_depth() static accessor")
    var path: String = announcer.last_report_path
    check(not path.is_empty() and FileAccess.file_exists(path), "telemetry report written: " + path)
    var report = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
    check(report is Dictionary, "telemetry report is JSON")
    if report is Dictionary:
        for key in ["summary", "tick_ledger", "room_seconds", "event_counts", "achievements",
                "announcer_lines", "seed", "outcome"]:
            check(report.has(key), "telemetry has " + key)
        check(int(report["event_counts"].get("enemy_killed", 0)) == 2, "event counts by signal")
        check(report["outcome"] == "defeated", "telemetry outcome")
        check(report["achievements"].size() >= 1, "telemetry lists this run's unlocks")
        check(String(path.get_file()).begins_with("run-"), "report file name run-<unix>-<seed>")
    game.queue_free()
    _finish()


func _triggers(brain) -> Array:
    var result: Array = []
    for entry in brain.history:
        result.append(entry["trigger"])
    return result


func _texts(brain) -> Array:
    var result: Array = []
    for entry in brain.history:
        result.append(entry["text"])
    return result


func _finish() -> void:
    if failures == 0:
        print("PASS: announcer data, seeded selection, cooldowns, preemption, rate limit, modal, live toasts/log/telemetry")
    quit(1 if failures > 0 else 0)
