extends SceneTree
## Achievements (pure rules over scripted event sequences), the persistent
## profile (save/load roundtrip, corrupt-file recovery, accessors) and the
## telemetry report writer (expected keys, retention of the newest 50 files).
## Run: godot --headless --path game --script res://tests/achievements_test.gd
## Everything preloaded here is pure: no Events/RunState references.
const Achievements = preload("res://scripts/core/achievements.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Telemetry = preload("res://scripts/core/telemetry.gd")
const PROFILE_PATH := "user://test/achievements_test/profile.json"
const TELEMETRY_DIR := "user://test/achievements_test/telemetry"
var failures := 0
## Scripted-run state for feed().
var tracker: Dictionary
var unlocked: Dictionary
var lifetime: Dictionary
var live: Dictionary


func _initialize() -> void:
    _test_definitions()
    _test_first_kill_and_rooms()
    _test_floor_rules()
    _test_run_end_rules()
    _test_misc_rules()
    _test_profile()
    _test_telemetry()
    if failures == 0:
        print("PASS: achievements unlock once on scripted runs; profile roundtrip and recovery; telemetry files")
    quit(1 if failures > 0 else 0)


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL ACHIEVEMENTS: " + detail)


func _new_run(lifetime_stats: Dictionary = {}) -> void:
    tracker = Achievements.new_tracker()
    unlocked = {}
    lifetime = lifetime_stats
    live = {"hp": 12, "max_hp": 12, "ticks": 20, "depth": 1, "level": 1, "outcome": "running",
        "seed": 1, "run_time": 0.0}
    feed("run_started")
    feed("floor_started", {"depth": 1})


## Observes one event, evaluates, marks results unlocked; returns new ids.
func feed(type: String, fields: Dictionary = {}) -> Array[String]:
    var event: Dictionary = fields.duplicate()
    event["type"] = type
    event["time"] = float(live["run_time"])
    Achievements.observe(tracker, event)
    var ids: Array[String] = Achievements.evaluate(
        Achievements.build_snapshot(tracker, live, lifetime, unlocked), event)
    for id in ids:
        check(not unlocked.has(id), "evaluate never returns an unlocked id: " + id)
        unlocked[id] = true
    return ids


func _test_definitions() -> void:
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(Achievements.PATH))
    check(parsed is Dictionary, "achievements.json parses")
    var problems: Array[String] = Achievements.validate(parsed)
    check(problems.is_empty(), "shipped achievements validate: %s" % [problems])
    check(Achievements.default_definitions().size() >= 16, "at least 16 achievements")
    var broken: Dictionary = parsed.duplicate(true)
    broken["achievements"].append(broken["achievements"][0].duplicate(true))
    broken["achievements"][1]["requires"] = {"run.kills": {"~": 1}}
    broken["achievements"][2]["requires"] = {"made.up": {">=": 1}}
    broken["achievements"][3]["event"] = "sneezed"
    broken["achievements"][4]["colour"] = "red"
    broken["achievements"][5]["quip"] = ""
    var joined: String = "\n".join(Achievements.validate(broken))
    for needle in ["duplicate id", "must be {\"<op>\": value}", "unknown requirement key 'made.up'",
            "event must be one of", "unknown key 'colour'", "quip must be a non-empty string"]:
        check(needle in joined, "validator reports: " + needle)


func _test_first_kill_and_rooms() -> void:
    _new_run()
    feed("room_entered", {"room_id": 3, "kind": "normal", "first_visit": true, "door": true})
    check(feed("enemy_killed", {"definition_id": "rat_scavenger"}) == ["first_blood"],
        "first kill unlocks first_blood")
    check(feed("enemy_killed", {"definition_id": "rat_scavenger"}).is_empty(),
        "second kill unlocks nothing new")
    check(feed("room_cleared", {"room_id": 3}).has("not_a_scratch"),
        "clearing a room without damage unlocks not_a_scratch")

    _new_run()
    feed("room_entered", {"room_id": 3, "kind": "normal", "first_visit": true, "door": true})
    feed("enemy_killed", {"definition_id": "rat_scavenger"})
    feed("player_damaged", {"amount": 3, "source": "rat_scavenger"})
    live["hp"] = 9
    check(not feed("room_cleared", {"room_id": 3}).has("not_a_scratch"),
        "damage taken in the room blocks not_a_scratch")
    feed("room_entered", {"room_id": 4, "kind": "normal", "first_visit": true, "door": true})
    feed("enemy_killed", {"definition_id": "rat_scavenger"})
    check(feed("room_cleared", {"room_id": 4}).has("not_a_scratch"),
        "room counters reset on the next room")
    live["hp"] = 1
    feed("room_entered", {"room_id": 5, "kind": "normal", "first_visit": true, "door": true})
    check(feed("room_cleared", {"room_id": 5}).has("one_hp_wonder"), "room cleared at 1 HP")

    _new_run()
    var unlocked_at := -1
    for kill in range(1, 31):
        if feed("enemy_killed", {"definition_id": "rat_scavenger"}).has("quarterly_quota"):
            unlocked_at = kill
    check(unlocked_at == 25, "quarterly_quota at exactly 25 kills (got %d)" % unlocked_at)
    check(unlocked.has("untouched_ten"), "ten kills without damage")


func _test_floor_rules() -> void:
    _new_run()
    live["ticks"] = 3
    live["run_time"] = 200.0
    var ids: Array[String] = feed("floor_cleared", {"depth": 1})
    check(ids.has("exit_interview") and not ids.has("photo_finish"), "3 ticks is no photo finish")
    check(ids.has("untouchable") and ids.has("no_takebacks"), "flawless, no-revisit floor")
    check(not ids.has("express_elevator"), "200 s floor is not an express")

    _new_run()
    live["ticks"] = 2
    feed("room_entered", {"room_id": 2, "kind": "normal", "first_visit": true, "door": true})
    feed("room_entered", {"room_id": 0, "kind": "start", "first_visit": false, "door": true})
    feed("player_damaged", {"amount": 1, "source": "spitting_rat"})
    live["run_time"] = 45.0
    ids = feed("floor_cleared", {"depth": 1})
    check(ids.has("photo_finish") and ids.has("express_elevator"), "2 ticks, 45 s floor")
    check(not ids.has("untouchable") and not ids.has("no_takebacks"),
        "damage and a revisit block those floor achievements")
    check(feed("floor_started", {"depth": 3}).has("basement_tenant"), "reach floor 3")
    check(feed("floor_started", {"depth": 6}).has("subterranean_executive"), "reach floor 6")
    check(feed("floor_started", {"depth": 7}).is_empty(), "depth achievements only once")


func _test_run_end_rules() -> void:
    _new_run()
    feed("player_died", {"cause": "rat_scavenger"})
    live["outcome"] = "defeated"
    var ids: Array[String] = feed("run_ended", {"outcome": "defeated"})
    check(ids.has("rodent_review"), "dying to a rat on floor 1")

    _new_run()
    live["depth"] = 2
    feed("player_died", {"cause": "rat_scavenger"})
    live["outcome"] = "defeated"
    check(not feed("run_ended", {"outcome": "defeated"}).has("rodent_review"),
        "rodent_review needs floor 1")

    _new_run()
    feed("player_died", {"cause": "armored_brute"})
    live["outcome"] = "defeated"
    check(not feed("run_ended", {"outcome": "defeated"}).has("rodent_review"),
        "rodent_review needs a rat")

    _new_run({"runs": 4})
    live["outcome"] = "collapsed"
    ids = feed("run_ended", {"outcome": "collapsed"})
    check(ids.has("structural_feedback") and ids.has("loyalty_program"),
        "collapse and the fifth finished run")


func _test_misc_rules() -> void:
    _new_run({"total_kills": 99})
    check(feed("enemy_killed", {"definition_id": "rat_scavenger"}).has("career_exterminator"),
        "lifetime kills include this run")
    live["hp"] = 2
    check(feed("boss_defeated", {"definition_id": "armored_brute"}).has("down_to_the_wire"),
        "boss at <= 20 % HP")
    _new_run()
    live["hp"] = 10
    check(not feed("boss_defeated", {"definition_id": "armored_brute"}).has("down_to_the_wire"),
        "boss at high HP is not down to the wire")
    check(feed("chest_opened").has("unboxing"), "open a chest")
    check(feed("shrine_used").has("devout_ish") and feed("guild_rested").has("union_break"),
        "shrine and guild rest")
    check(feed("grace_ended").has("rubble_rouser"), "survive a grace period")
    check(feed("level_up", {"level": 5}).has("middle_management"), "level 5")
    for door in range(25):
        feed("room_entered", {"room_id": door, "kind": "normal", "first_visit": true, "door": true})
    check(unlocked.has("door_enthusiast"), "25 doors")
    var snapshot := {"unlocked": {"unboxing": true}}
    check(Achievements.evaluate(snapshot, {"type": "chest_opened"}).is_empty() or
        not Achievements.evaluate(snapshot, {"type": "chest_opened"}).has("unboxing"),
        "already-unlocked ids are never returned")
    check(Achievements.compare("rat_scavenger", "contains", "rat"), "contains comparator")
    check(Achievements.compare("victory", "in", ["victory", "escaped"]), "in comparator")
    check(not Achievements.compare(null, ">=", 1), "missing values never pass")


func _test_profile() -> void:
    Profile.use_path(PROFILE_PATH)
    DirAccess.remove_absolute(PROFILE_PATH)
    DirAccess.remove_absolute(PROFILE_PATH + ".corrupt")
    var fresh: Dictionary = Profile.load_profile()
    check(fresh == Profile.blank(), "missing profile loads blank")
    check(Profile.best_depth() == 0 and Profile.total_runs() == 0, "accessors on a blank profile")
    var data: Dictionary = Profile.current()
    check(Profile.unlock(data, "first_blood", 424242, 1000), "unlock records")
    check(not Profile.unlock(data, "first_blood", 424242, 2000), "unlock is idempotent")
    Profile.record_run(data, {"depth": 3, "kills": 12, "seed": 424242, "run_time_seconds": 61.5},
        "defeated", "hulking_rat", 2, 3000)
    Profile.record_run(data, {"depth": 2, "kills": 5, "seed": 99, "run_time_seconds": 10.0},
        "collapsed", "", 1, 4000)
    Profile.record_run(data, {"depth": 4, "kills": 20, "seed": 7}, "victory", "", 4, 5000)
    check(Profile.save_current(), "profile saves")
    Profile.refresh()
    check(Profile.best_depth() == 4 and Profile.total_runs() == 3, "best depth and runs persist")
    check(Profile.total_kills() == 37 and Profile.total_floors() == 7 and Profile.victories() == 1,
        "kills, floors, victories persist")
    check(Profile.deaths_by_cause() == {"hulking_rat": 1, "collapse": 1}, "deaths by cause persist")
    check(Profile.last_seed() == 7 and Profile.is_unlocked("first_blood"), "last seed, unlocks persist")
    check(int(Profile.unlocked()["first_blood"]["unlocked_at"]) == 1000, "unlock timestamp kept")
    check(is_equal_approx(float(Profile.stats()["total_run_seconds"]), 71.5), "run seconds summed")

    var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
    file.store_string("{\"stats\": {\"runs\": 3,,, not json")
    file.close()
    Profile.refresh()
    check(Profile.total_runs() == 0 and Profile.unlocked().is_empty(), "corrupt profile loads blank")
    check(FileAccess.file_exists(PROFILE_PATH + ".corrupt"), "corrupt file kept as .corrupt")
    check(Profile.save_current() and Profile.load_profile()["version"] == Profile.VERSION,
        "a fresh profile replaces the corrupt one")
    file = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
    file.store_string("{\"stats\": {\"runs\": \"2\"}, \"achievements\": {\"x\": 5}}")
    file.close()
    var partial: Dictionary = Profile.load_profile()
    check(int(partial["stats"]["runs"]) == 2 and partial["achievements"].is_empty() and
        partial["stats"].has("deaths_by_cause"), "partial profiles are normalised")
    Profile.use_path(Profile.DEFAULT_PATH)


func _test_telemetry() -> void:
    if DirAccess.dir_exists_absolute(TELEMETRY_DIR):
        for name in DirAccess.get_files_at(TELEMETRY_DIR):
            DirAccess.remove_absolute(TELEMETRY_DIR.path_join(name))
    var recorder := Telemetry.new()
    var bus := _FakeBus.new()
    recorder.attach(bus)
    bus.run_started.emit(5)
    bus.floor_started.emit(1, {})
    bus.room_entered.emit(0, "start", {}, true)
    bus.room_entered.emit(4, "normal", {"cost": 2}, true)
    bus.ping.emit()
    recorder.note_unlock("first_blood", 123)
    var report: Dictionary = recorder.build_report({"seed": 5, "outcome": "defeated", "kills": 1},
        [{"cost": 2, "after": 24}], [{"trigger": "run_started", "text": "Hi", "priority": 3,
        "category": "system", "status": "shown", "created_at": 0.0}], 1700000000)
    check(report["event_counts"] == {"run_started": 1, "floor_started": 1, "room_entered": 2,
        "ping": 1}, "event counts by signal, any arity")
    check(report["room_seconds"].has("1:0") and report["room_seconds"].has("1:4"), "per-room time")
    var path: String = Telemetry.write_report(report, TELEMETRY_DIR)
    check(path.get_file() == "run-1700000000-5.json", "file named run-<unix>-<seed>.json")
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    check(parsed is Dictionary, "telemetry file is JSON")
    if parsed is Dictionary:
        for key in ["schema_version", "written_at_unix", "seed", "outcome", "summary",
                "tick_ledger", "room_seconds", "event_counts", "achievements", "announcer_lines"]:
            check(parsed.has(key), "telemetry key " + key)
    check(Telemetry.write_report(report, TELEMETRY_DIR).get_file() == "run-1700000000-5-2.json",
        "same-second reports do not clobber")
    for i in range(60):
        report["written_at_unix"] = 1700000100 + i
        Telemetry.write_report(report, TELEMETRY_DIR)
    var kept: Array[String] = Telemetry.list_reports(TELEMETRY_DIR)
    check(kept.size() == Telemetry.MAX_FILES, "keeps the newest 50 reports (has %d)" % kept.size())
    check(kept.back() == "run-1700000159-5.json" and not kept.has("run-1700000000-5.json"),
        "oldest reports pruned first")
    recorder.free()
    bus.free()


class _FakeBus extends Object:
    signal run_started(seed: int)
    signal floor_started(depth: int, floor: Dictionary)
    signal room_entered(room_id: int, kind: String, ledger_entry: Dictionary, first_visit: bool)
    signal ping
