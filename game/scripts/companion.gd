extends Node
## Companion: the Wave 3E follower prototype (D-10, COMBAT_AND_RPG §13).
##
## Created by Game only while `RunState.companion_enabled` is true (the
## `companion.enabled` flag in prototype_rules.json, flipped per session by the
## F8 developer key `debug_toggle_companion`). OFF by default, so the default
## game and the determinism fixtures never see it.
##
## The AI is pure (companion_ai.gd); this node owns the live dictionary
## (`state`), its own RandomNumberGenerator and the side effects:
## - Bites roll d20 + to-hit against the enemy's AC and their dice with `rng`
##   (never RunState.rng) and deal damage through Combat.apply_damage() with
##   context {source: "companion"}: XP, credits and kill telemetry still go to
##   the crawler, item triggers (on_hit, on_kill) do not fire.
## - Enemy strikes and bullets reach it through Combat.hit_companion(), which
##   rolls against its AC with the same `rng`; damage lands in take_damage().
## - 0 HP -> "downed": the crawler stands within revive.radius for
##   revive.channel_seconds to revive it at revive.hp_ratio; it also gets up
##   after revive.auto_seconds, and fully at every floor start.
## - Command: hold `interact` for `companion.command_hold_seconds` (0.4 s)
##   with no interactable prompt showing -> toggles "stay" / "follow".
## - Buff: crawler_buffs.pickup_radius goes to RunState.companion_pickup_bonus
##   (read by Loadout.player_stats()) while the companion is up.
## - `rng` is reseeded to RunState.seed ^ depth at every floor start, so the
##   companion is deterministic per seed and the run's own dice are untouched.
## Signals: Events.companion_spawned / companion_downed / companion_revived /
## companion_killed_enemy; announcer lines via Events.announcement_requested
## with literal text (no announcer.json change).
const AI = preload("res://scripts/companion_ai.gd")
const Companions = preload("res://scripts/companions.gd")
const RPG = preload("res://scripts/rpg_rules.gd")

const DEFAULT_RULES := {"retarget_chance": 0.3, "retarget_radius": 64.0,
    "retarget_interval": 1.0, "command_hold_seconds": 0.4}
const DOWNED_FRAME := 4
const HP_BAR := Color("#e7b25b")

var game
var companion_id := Companions.DEFAULT_ID
var definition: Dictionary = {}
## The live companion dictionary (companion_ai.gd documents the keys); empty
## until spawn().
var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
## `companion` block of prototype_rules.json merged over DEFAULT_RULES.
var rules: Dictionary = DEFAULT_RULES.duplicate()
## Kills credited to the companion this run.
var kills := 0
var _hold := 0.0
var _hold_fired := false
var _texture: Texture2D


func _ready() -> void:
    Events.floor_started.connect(_on_floor_started)
    Events.room_entered.connect(_on_room_entered)
    Events.level_up.connect(_on_level_up)


## Binds the Game node and loads the definition named by `companion.id`.
func setup(game_node) -> void:
    game = game_node
    var config: Dictionary = RunState.config.get("companion", {})
    rules = DEFAULT_RULES.duplicate()
    rules.merge(config, true)
    companion_id = String(config.get("id", Companions.DEFAULT_ID))
    definition = Companions.definition(companion_id)
    if definition.is_empty():
        push_warning("Companion %s is not in companions.json" % companion_id)
    var sprite: String = String(definition.get("sprite", ""))
    if sprite != "" and ResourceLoader.exists(sprite):
        _texture = load(sprite) as Texture2D


func is_spawned() -> bool:
    return not state.is_empty()


func is_up() -> bool:
    return is_spawned() and not AI.is_down(state)


## Up and out of its post-hit i-frames.
func is_hittable() -> bool:
    return is_up() and float(state.get("iframes", 0.0)) <= 0.0


func position() -> Vector2:
    return state.get("pos", Vector2.INF)


func radius() -> float:
    return float(state.get("radius", 5.0))


func armor_class() -> int:
    return int(state.get("ac", 12))


## Fresh instance beside the crawler at the crawler's level; reseeds `rng`.
func spawn() -> void:
    if definition.is_empty() or game == null:
        return
    rng.seed = _seed()
    kills = 0
    state = AI.make_instance(definition, game.player.world_position, RunState.level, companion_id)
    AI.teleport(state, definition, _crawler_world())
    _sync_buff()
    Events.companion_spawned.emit(companion_id)
    _announce("spawned", 2, "flavour")


## Removes the companion (F8 off) and unbinds it from Game, so it ignores
## Events until the node is freed (Game queue_frees it).
func despawn() -> void:
    state = {}
    game = null
    RunState.companion_pickup_bonus = 0.0


## One simulation step. `world` is build_world() (tests pass their own).
func update(delta: float, world: Dictionary) -> void:
    if not is_spawned():
        return
    _poll_command(delta, world)
    for action in AI.step(state, definition, delta, world):
        match String(action["type"]):
            "bite":
                _resolve_bite(action, world)
            "revive":
                revive(float(definition.get("revive", {}).get("hp_ratio", 0.5)))


## The world dictionary for AI.step() from the live Game.
func build_world() -> Dictionary:
    var prompt: String = ""
    if game.door_lock != null:
        prompt = game.door_lock.prompt()
    if prompt == "" and game.items != null:
        prompt = game.items.prompt
    if prompt == "" and game.services != null:
        prompt = game.services.prompt
    return {"crawler_pos": game.player.world_position, "crawler_aim": game.player.aim_direction,
        "blocked": game.combat.blocked(), "foes": game.combat.enemies(),
        "preferred_id": game.combat.last_player_target, "can_command": prompt == ""}


## Adds the companion keys to Combat's enemy `world` (enemy_system.gd
## update_companion_target documents them).
func add_to_world(world: Dictionary) -> void:
    world["companion_alive"] = is_up()
    world["companion_pos"] = position()
    world["companion_rules"] = rules
    world["retarget_seed"] = _seed()


## Damage from Combat.apply_damage(): HP, i-frames, number, downed.
func take_damage(amount: int, context: Dictionary) -> int:
    if amount <= 0 or not is_up():
        return 0
    var applied: int = mini(amount, int(state["hp"]))
    state["hp"] = int(state["hp"]) - applied
    state["iframes"] = float(definition.get("hit_iframes", 0.4))
    if game != null and game.combat != null:
        game.combat.fx.flash("companion", Color(4, 0.8, 0.8, 1))
        game.combat.fx.number("companion", position(), applied, "player")
    if int(state["hp"]) <= 0:
        AI.knock_down(state)
        _sync_buff()
        Events.say("%s is down! Stand over it to revive." % state["name"], "combat")
        Events.companion_downed.emit()
        _announce("downed", 3, "warning")
    elif String(context.get("source", "")) != "":
        Events.say("%s takes %d damage (%d/%d)." % [state["name"], applied, int(state["hp"]),
            int(state["max_hp"])], "combat")
    return applied


func revive(ratio: float) -> void:
    if not AI.is_down(state):
        return
    AI.stand_up(state, ratio)
    _sync_buff()
    Events.say("%s is back up (%d/%d HP)." % [state["name"], int(state["hp"]),
        int(state["max_hp"])], "combat")
    Events.companion_revived.emit()
    _announce("revived", 3, "celebration")


## Toggles "stay" / "follow". Returns the new mode.
func toggle_command() -> String:
    if not is_up():
        return String(state.get("mode", "follow"))
    state["mode"] = "follow" if String(state["mode"]) == "stay" else "stay"
    state["target_id"] = ""
    state["waypoints"] = []
    Events.say("%s: %s." % [state["name"], "STAY" if state["mode"] == "stay" else "FOLLOW"], "info")
    _announce(String(state["mode"]), 1, "flavour")
    return String(state["mode"])


## {name, hp, max_hp, state, mode, revive (0..1)} for the HUD pip.
func hud_info() -> Dictionary:
    if not is_spawned():
        return {}
    var channel: float = maxf(0.01, float(definition.get("revive", {}).get("channel_seconds", 2.0)))
    return {"name": String(state["name"]), "hp": int(state["hp"]), "max_hp": int(state["max_hp"]),
        "state": String(state["state"]), "mode": String(state["mode"]),
        "revive": clampf(float(state.get("revive_progress", 0.0)) / channel, 0.0, 1.0)}


## Drawn by RoomRenderer in its actor pass (world coordinates, its transform).
func draw_on(canvas: CanvasItem) -> void:
    if not is_spawned():
        return
    var at: Vector2 = position()
    var size := Vector2(float(definition.get("render", [20, 20])[0]),
        float(definition.get("render", [20, 20])[1]))
    var down: bool = AI.is_down(state)
    var modulation := Color.WHITE
    if game != null and game.combat != null:
        var amount: float = game.combat.fx.flash_amount("companion")
        if amount > 0.0:
            modulation = modulation.lerp(game.combat.fx.flash_color("companion"), amount)
    if float(state.get("iframes", 0.0)) > 0.0 and not down:
        modulation.a = 0.5 if int(float(Time.get_ticks_msec()) / 62.5) % 2 == 0 else 0.9
    if _texture != null:
        var frame := Vector2(_texture.get_width() / 5.0, _texture.get_height())
        var column: int = DOWNED_FRAME if down else posmod(int(state["facing"]), 4)
        canvas.draw_texture_rect_region(_texture, Rect2(at - size * 0.5, size),
            Rect2(float(column) * frame.x, 0.0, frame.x, frame.y), modulation)
    else:
        canvas.draw_circle(at, radius(), Color("#c58b4a") if not down else Color("#6b4a2a"))
    if float(state.get("wind_up", 0.0)) > 0.0:
        var aim: Vector2 = state.get("aim", Vector2.RIGHT)
        canvas.draw_arc(at, 12.0, aim.angle() - 0.8, aim.angle() + 0.8, 8, Color("#ffd27a"), 1.0)
    var top: float = at.y - size.y * 0.5 - 4.0
    if down:
        var progress: float = hud_info()["revive"]
        var revive_radius: float = float(definition.get("revive", {}).get("radius", 24.0))
        canvas.draw_arc(at, revive_radius, 0.0, TAU, 32, Color(1.0, 0.85, 0.4, 0.35), 1.0)
        if progress > 0.0:
            canvas.draw_arc(at, revive_radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 32,
                Color("#ffe08a"), 2.0)
        return
    var ratio: float = clampf(float(state["hp"]) / float(maxi(1, int(state["max_hp"]))), 0.0, 1.0)
    canvas.draw_rect(Rect2(at.x - 8, top, 16, 2), Color("#151b25"))
    canvas.draw_rect(Rect2(at.x - 8, top, 16 * ratio, 2), HP_BAR)
    if String(state["mode"]) == "stay":
        canvas.draw_rect(Rect2(at.x - 2, top - 5, 4, 3), Color("#8fd3ff"))


# --- Internals ---------------------------------------------------------------------

func _seed() -> int:
    return RunState.seed ^ RunState.depth


func _crawler_world() -> Dictionary:
    return {"crawler_pos": game.player.world_position, "crawler_aim": game.player.aim_direction,
        "blocked": game.combat.blocked()}


func _resolve_bite(action: Dictionary, world: Dictionary) -> void:
    var foe: Dictionary = AI.find(world.get("foes", []), String(action["target_id"]))
    if foe.is_empty() or game == null:
        return
    var attack: Dictionary = action["attack"]
    var numbers: Dictionary = AI.attack_numbers(definition, attack, RunState.level)
    var definition_id: String = String(foe["definition"])
    var foe_ac: int = int(foe.get("ac", game.combat.definition_of(foe).get("ac", 10)))
    var roll: Dictionary = RPG.roll_to_hit(rng, int(numbers["to_hit"]), foe_ac)
    if not bool(roll["hit"]):
        game.combat.fx.number(String(foe["instance_id"]), Vector2(foe["pos"]), "MISS", "miss")
        return
    var damage: int = RPG.roll_damage(rng, int(numbers["die"]), int(numbers["bonus"]),
        bool(roll["critical"]))
    var direction: Vector2 = (Vector2(foe["pos"]) - position()).normalized()
    game.combat.apply_damage(foe, damage, {"source": "companion", "slot": "melee",
        "critical": bool(roll["critical"]), "direction": direction,
        "knockback": float(attack.get("knockback", 0.0)), "knockback_direction": direction,
        "damage_type": String(attack.get("damage_type", "physical"))})
    if int(foe["hp"]) <= 0:
        kills += 1
        RunState.count("companion_kills")
        Events.companion_killed_enemy.emit(definition_id)


## Hold `interact` (nothing to interact with) for command_hold_seconds.
func _poll_command(delta: float, world: Dictionary) -> void:
    if not InputMap.has_action("interact"):
        return
    if not Input.is_action_pressed("interact") or not bool(world.get("can_command", false)):
        _hold = 0.0
        _hold_fired = false
        return
    _hold += delta
    if _hold >= float(rules.get("command_hold_seconds", 0.4)) and not _hold_fired:
        _hold_fired = true
        toggle_command()


func _sync_buff() -> void:
    var bonus: float = float(definition.get("crawler_buffs", {}).get("pickup_radius", 0.0))
    RunState.companion_pickup_bonus = bonus if is_up() else 0.0


func _announce(kind: String, priority: int, category: String) -> void:
    var lines: Array = definition.get("lines", {}).get(kind, [])
    if lines.is_empty():
        return
    var text: String = String(lines[rng.randi_range(0, lines.size() - 1)]) if lines.size() > 1 \
        else String(lines[0])
    Events.announcement_requested.emit("companion_" + kind, {"text": text, "priority": priority,
        "category": category})


func _on_floor_started(depth: int, _floor: Dictionary) -> void:
    if game == null:
        return
    if depth <= 1 or not is_spawned():
        spawn()
        return
    rng.seed = _seed()
    var revive_rules: Dictionary = definition.get("revive", {})
    state["max_hp"] = AI.max_hp_for(definition, RunState.level)
    if bool(revive_rules.get("on_floor_start", true)):
        if AI.is_down(state):
            revive(1.0)
        state["hp"] = int(state["max_hp"])
    state["mode"] = "follow"
    AI.teleport(state, definition, _crawler_world())
    _sync_buff()


## Room entry (and the floor's start room): appear beside the crawler,
## following. A downed companion is carried along, still downed.
func _on_room_entered(_room_id: int, _kind: String, _entry: Dictionary, _first: bool) -> void:
    if not is_spawned() or game == null:
        return
    state["mode"] = "follow"
    AI.teleport(state, definition, _crawler_world())


func _on_level_up(level: int, _pending: int) -> void:
    if not is_spawned():
        return
    var old_max: int = int(state["max_hp"])
    state["max_hp"] = AI.max_hp_for(definition, level)
    if is_up():
        state["hp"] = mini(int(state["max_hp"]), int(state["hp"]) + int(state["max_hp"]) - old_max)
