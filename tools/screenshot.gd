extends SceneTree
## Captures README screenshots from the live game at 1x (960x540).
## Needs a display with OpenGL; on a headless Linux box use Xvfb:
##   xvfb-run -a godot --path game --rendering-driver opengl3 \
##       --script ../tools/screenshot.gd -- [--seed N] [--out DIR]
## (the --script path may also be absolute). Writes 01-title.png,
## 02-stone-crypt-fight.png, 03-fungal-cavern.png and 04-level-up-skills.png to
## DIR (default: docs/art/screenshots/ in the repository). The player's HP is
## topped up every frame so a shot never lands on the death screen; the shots
## use the real renderer, HUD and menus, nothing is staged beyond that.
## Game scripts use autoloads, so everything is load()ed at runtime.

const Layout = preload("res://scripts/room_layout.gd")

var seed_value := 5150
var out_dir := ""
var game
var run_state: Node


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    for i in args.size():
        if args[i] == "--seed" and i + 1 < args.size():
            seed_value = int(args[i + 1])
        elif args[i] == "--out" and i + 1 < args.size():
            out_dir = args[i + 1]
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/art/screenshots").simplify_path()
    elif out_dir.is_relative_path():
        out_dir = OS.get_environment("PWD").path_join(out_dir).simplify_path()
    DirAccess.make_dir_recursive_absolute(out_dir)
    call_deferred("_run")


func _run() -> void:
    run_state = get_root().get_node("RunState")
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    await _frames(15)
    await _shot("01-title.png")

    game.start_run(seed_value)
    await _frames(5)
    _enter_hostile_room()
    await _fight(120)
    await _shot("02-stone-crypt-fight.png")

    game._start_floor(3)
    await _frames(5)
    _enter_hostile_room()
    await _fight(200)
    await _shot("03-fungal-cavern.png")

    Input.action_release("fire")
    run_state.award_xp(300)
    await _frames(20)
    await _shot("04-level-up-skills.png")
    quit(0)


## Walks through the first door of the start room that leads to a normal room.
func _enter_hostile_room() -> void:
    var room: Dictionary = run_state.floor["rooms"][run_state.current_room_id]
    for direction in ["N", "E", "S", "W"]:
        if room["neighbors"].has(direction):
            var next: Dictionary = run_state.floor["rooms"][int(room["neighbors"][direction])]
            if String(next["kind"]) == "normal":
                game._enter_neighbor(direction)
                return
    push_warning("screenshot: no normal room next to the start room for seed %d" % seed_value)


## Plays `frames` frames, aiming the mouse at the nearest live enemy and firing.
func _fight(frames: int) -> void:
    for i in frames:
        run_state.hp = run_state.max_hp
        var target := Vector2.INF
        for foe in run_state.current_room().get("enemies", []):
            if int(foe.get("hp", 0)) > 0:
                var pos := Vector2(foe["pos"])
                if target == Vector2.INF or pos.distance_to(game.player.world_position) \
                        < target.distance_to(game.player.world_position):
                    target = pos
        if target != Vector2.INF:
            get_root().warp_mouse(Layout.world_to_screen(target, game.layout))
            Input.action_press("fire")
        else:
            Input.action_release("fire")
        await process_frame


func _frames(count: int) -> void:
    for i in count:
        await process_frame


func _shot(file_name: String) -> void:
    await RenderingServer.frame_post_draw
    var image: Image = get_root().get_texture().get_image()
    var path := out_dir.path_join(file_name)
    var err := image.save_png(path)
    print("screenshot %s -> %s (%dx%d, error %d)" % [file_name, path, image.get_width(),
        image.get_height(), err])
