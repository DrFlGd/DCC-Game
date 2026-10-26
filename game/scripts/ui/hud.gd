extends CanvasLayer
## Screen-space HUD: status lines, last message, minimap and control hints;
## the loadout panel (2B) and the active-skill slots under it (2F).
## Reads RunState only; the message line is fed by `Events.message`. The
## end-of-run banner was replaced by the run summary screen (Wave 2A); Game
## hides the HUD on the title screen.
## Drawn in immediate mode on a full-rect Control that ignores the mouse, so
## clicks still reach gameplay. Layer 5 keeps it under CharacterMenu (layer 10).
## Wave 3C: hint lines name the bindings of the last-used device
## (InputBindings.hint, Events.input_device_changed) and wrap to the window;
## text sizes follow the text_scale setting, panels turn opaque with outlined
## text in high contrast, the ROOM CLEAR border stops pulsing with
## reduced_flash, and the gamepad aim reticle is drawn here (`reticle`).
const RPG = preload("res://scripts/rpg_rules.gd")
const Layout = preload("res://scripts/room_layout.gd")
const FloorMap = preload("res://scripts/ui/floor_map.gd")
const Inventory = preload("res://scripts/inventory.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const SkillSystem = preload("res://scripts/skill_system.gd")
const InputBindings = preload("res://scripts/core/input_bindings.gd")
const Accessibility = preload("res://scripts/core/accessibility.gd")
## Tick counter colour thresholds (COLLAPSE_SYSTEM §8).
const TICKS_AMBER := 6
const TICKS_RED := 3

## Room-to-window mapping from Layout.compute(); Game keeps it current.
var layout: Dictionary = Layout.compute(Vector2(960, 540))
## Newest Events.message text and category.
var message := ""
var message_category := "info"
## Interaction prompt for the feature in reach (set by Game from RoomServices).
var prompt := ""
## Pickup under the crawler (ItemSystem.hover, set by Game); its tooltip is
## drawn at 1.5x above it (COMBAT_AND_RPG §12).
var hover: Dictionary = {}
## Gamepad aim reticle in world px (Vector2.INF hides it; set by Game, 3C).
var reticle := Vector2.INF
## The aim snapped to an enemy (aim assist): the reticle closes up.
var reticle_assisted := false
var canvas: Control
## Seconds left on the "ROOM CLEAR" flourish (show_room_clear, Wave 2D).
var room_clear_left := 0.0
## Wave 3E: the Companion node while the prototype is on (set by Game), else null.
var companion = null
const ROOM_CLEAR_SECONDS := 1.1


func _ready() -> void:
    layer = 5
    canvas = Control.new()
    canvas.name = "Canvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    canvas.draw.connect(_draw_hud)
    add_child(canvas)
    Events.message.connect(_on_message)
    Events.input_device_changed.connect(func(_device): refresh())
    Events.settings_changed.connect(func(_values): refresh())


func _process(delta: float) -> void:
    room_clear_left = maxf(0.0, room_clear_left - delta)
    refresh()


## Starts the ~1 s "ROOM CLEAR" flourish (DoorLock calls it on a locking room's clear).
func show_room_clear() -> void:
    room_clear_left = ROOM_CLEAR_SECONDS
    refresh()


func refresh() -> void:
    if canvas != null:
        canvas.queue_redraw()


func _on_message(text: String, category: String) -> void:
    message = text
    message_category = category
    refresh()


func _draw_hud() -> void:
    if RunState.floor.is_empty():
        return
    var view: Vector2 = layout["viewport"]
    var room: Dictionary = RunState.floor["rooms"][RunState.current_room_id]
    var foes: Array = RunState.current_room().get("enemies", [])
    var level: int = RunState.level
    # Wave 3C: the status block's rows move down with the text size.
    var row: float = Accessibility.text_scale()
    # Ticks moved to the clock widget (_draw_clock, Wave 2E).
    _text("DCC | FLOOR %d/%d | ROOM %d %s | FOES %d" % [
        RunState.depth, int(RunState.config.get("run", {}).get("target_depth", 6)),
        RunState.current_room_id, String(room["kind"]).to_upper(),
        foes.size()], Vector2(14, 22 * row), 17, Color("#f2da99"))
    _text("HP %d/%d  AC %d  LV %d  XP %d/%s  PROF +%d" % [
        maxi(0, RunState.hp), RunState.max_hp, RunState.ac, level, RunState.xp,
        str(RPG.next_level_xp(level)) if level < 20 else "MAX",
        RunState.proficiency], Vector2(14, 43 * row), 15, Color("#e5eafa"))
    _draw_stamina_bar(Vector2(14, 43 * row + 4))
    _draw_companion_pip(Vector2(176, 43 * row + 4))
    var stat_parts: PackedStringArray = []
    for ability in RPG.ABILITIES:
        var score: int = int(RunState.ability_scores[ability])
        stat_parts.append("%s%d(%+d)" % [ability, score, RPG.modifier(score)])
    _text("  ".join(stat_parts), Vector2(14, 62 * row), 12, Color("#afd4ce"))
    _text(message, Vector2(14, 83 * row), 12, Color("#eccba6"))
    _draw_minimap(view)
    _draw_boss_bar(view)
    _draw_clock(view)
    _draw_grace_vignette(view)
    _draw_loadout(view)
    _draw_skills()
    _draw_tooltip()
    _draw_reticle()
    var hints_top: float = _draw_hints(view)
    _draw_prompt(view, hints_top)
    _draw_room_clear(view)


# --- Control hints and reticle (Wave 3C) ---------------------------------------

## Hint segments for `device` (the current one by default): [primary, secondary].
## Bindings come from the live Input Map, so remapped controls show up here.
static func hint_segments(device: String = "") -> Array:
    var key := func(action: String) -> String: return InputBindings.hint(action, device)
    var pad: bool = (InputBindings.device if device == "" else device) == InputBindings.GAMEPAD
    var primary: PackedStringArray = [
        "%s: move" % InputBindings.move_hint(device), "%s: aim" % InputBindings.aim_hint(device),
        "%s: shoot" % key.call("fire"), "%s: melee" % key.call("melee"),
        "%s: dodge" % key.call("dodge"), "%s: interact" % key.call("interact"),
        "%s: item" % key.call("use_item"),
        "%s/%s: belt" % [key.call("use_consumable"), key.call("next_consumable")],
        "%s/%s: skills" % [key.call("use_skill_1"), key.call("use_skill_2")]]
    var secondary: PackedStringArray = ["%s: pause / stats" % key.call("pause"),
        "%s: map" % key.call("map"), "%s: log" % key.call("toggle_log")]
    if not pad:
        secondary.append("R: replay")
        secondary.append("N: new seed")
    return [primary, secondary]


## Greedy word-wrap of `segments` joined by " | " into lines of at most
## `max_width` px at `font_size`.
static func wrap_segments(segments: PackedStringArray, max_width: float, font_size: int) -> PackedStringArray:
    var font: Font = ThemeDB.fallback_font
    var lines: PackedStringArray = []
    var line := ""
    for segment in segments:
        var candidate: String = segment if line == "" else line + " | " + segment
        if line != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
                font_size).x > max_width:
            lines.append(line)
            line = segment
        else:
            line = candidate
    if line != "":
        lines.append(line)
    return lines


## Bottom-left hint lines, wrapped to the window. Returns the y of the top line.
func _draw_hints(view: Vector2) -> float:
    var groups: Array = hint_segments()
    var sizes := [Accessibility.px(13), Accessibility.px(12)]
    var colors := [Color("#dce9f2"), Color("#a7cfcb")]
    var max_width: float = view.x - 28.0
    var stacked: Array = []
    for i in range(2):
        for line in wrap_segments(groups[i], max_width, sizes[i]):
            stacked.append([line, sizes[i], colors[i]])
    var y: float = view.y - 21.0 * Accessibility.text_scale()
    var top: float = y
    for i in range(stacked.size() - 1, -1, -1):
        var entry: Array = stacked[i]
        canvas.draw_string_outline(ThemeDB.fallback_font, Vector2(14, y), String(entry[0]),
            HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(entry[1]), maxi(2, Accessibility.outline()),
            Color(0, 0, 0, 0.6 if Accessibility.outline() == 0 else 1.0))
        canvas.draw_string(ThemeDB.fallback_font, Vector2(14, y), String(entry[0]),
            HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(entry[1]), entry[2])
        top = y
        y -= float(entry[1]) + 10.0
    return top


## Gamepad aim reticle: a ring with four ticks at Player.reticle_point(); it
## tightens and turns gold while aim assist holds a target.
func _draw_reticle() -> void:
    if reticle == Vector2.INF:
        return
    var at: Vector2 = Layout.world_to_screen(reticle, layout)
    var scale: float = float(layout.get("scale", 1.0))
    var radius: float = (5.0 if reticle_assisted else 7.0) * scale
    var color := Color("#ffd86b") if reticle_assisted else Color("#e8f4ff")
    canvas.draw_arc(at, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 3.0)
    canvas.draw_arc(at, radius, 0.0, TAU, 24, color, 1.5)
    for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
        canvas.draw_line(at + direction * (radius + 2.0), at + direction * (radius + 5.0 * scale),
            color, 1.5)


## Stamina pool (Wave 2D): a thin bar under the HP line; amber when a dodge
## (35) is not affordable. Self-contained: reads RunState only.
func _draw_stamina_bar(origin: Vector2) -> void:
    var width := 120.0
    var maximum: float = maxf(1.0, RunState.max_stamina)
    var ratio: float = clampf(RunState.stamina / maximum, 0.0, 1.0)
    var cost: float = float(RunState.config.get("feel", {}).get("dodge", {}).get("cost", 35.0))
    var fill := Color("#6fd3a0") if RunState.stamina >= cost else Color("#d9a441")
    canvas.draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 6)), Color("#0b0f16"))
    canvas.draw_rect(Rect2(origin, Vector2(width * ratio, 4)), fill)
    var tick: float = width * clampf(cost / maximum, 0.0, 1.0)
    for i in range(1, int(maximum / maxf(1.0, cost)) + 1):
        canvas.draw_line(origin + Vector2(tick * i, 0), origin + Vector2(tick * i, 4),
            Color(0, 0, 0, 0.5), 1.0)
    _text("STA", origin + Vector2(width + 6, 5), 9, Color("#a7cfcb"))


## Wave 3E: a small companion HP pip right of the stamina bar (amber bar,
## STAY marker, DOWN with the revive progress while downed).
func _draw_companion_pip(origin: Vector2) -> void:
    if companion == null:
        return
    var info: Dictionary = companion.hud_info()
    if info.is_empty():
        return
    var width := 40.0
    canvas.draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 6)), Color("#0b0f16"))
    if String(info["state"]) == "downed":
        canvas.draw_rect(Rect2(origin, Vector2(width * float(info["revive"]), 4)), Color("#ffe08a"))
        _text("DOWN", origin + Vector2(width + 6, 5), 9, Color("#ff8a7a"))
        return
    var ratio: float = clampf(float(info["hp"]) / float(maxi(1, int(info["max_hp"]))), 0.0, 1.0)
    canvas.draw_rect(Rect2(origin, Vector2(width * ratio, 4)), Color("#e7b25b"))
    _text("PAL" if String(info["mode"]) == "follow" else "STAY", origin + Vector2(width + 6, 5), 9,
        Color("#a7cfcb"))


## "ROOM CLEAR" banner across the top third with a gold border pulse.
func _draw_room_clear(view: Vector2) -> void:
    if room_clear_left <= 0.0:
        return
    var t: float = 1.0 - room_clear_left / ROOM_CLEAR_SECONDS
    var alpha: float = clampf(minf(t * 6.0, room_clear_left * 3.0), 0.0, 1.0)
    var scale: float = 1.0 + 0.25 * maxf(0.0, 1.0 - t * 5.0)
    var size: int = Accessibility.px(34.0 * scale)
    var text := "ROOM CLEAR"
    var font: Font = ThemeDB.fallback_font
    var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
    var at := Vector2((view.x - width) * 0.5, view.y * 0.32)
    canvas.draw_rect(Rect2(Vector2(0, at.y - size - 8), Vector2(view.x, size + 22)),
        Color(0.05, 0.04, 0.02, 0.55 * alpha))
    var border := Color(1.0, 0.84, 0.35, 0.8 * alpha * Accessibility.steady(0.6 + 0.4 * sin(t * 18.0), 0.8))
    canvas.draw_rect(Rect2(Vector2(3, 3), view - Vector2(6, 6)), border, false, 3.0)
    canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 5,
        Color(0.1, 0.06, 0.0, alpha))
    canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
        Color(1.0, 0.86, 0.4, alpha))


## Small top-centre HP bar for a live boss in the current room (any enemy with
## "boss": true), with its phase as pips. Self-contained: reads RunState only.
func _draw_boss_bar(view: Vector2) -> void:
    var boss: Dictionary = {}
    for foe in RunState.current_room().get("enemies", []):
        if bool(foe.get("boss", false)) and int(foe["hp"]) > 0:
            boss = foe
            break
    if boss.is_empty():
        return
    var width := 240.0
    var origin := Vector2(floorf(view.x * 0.5 - width * 0.5), 86.0)
    var ratio: float = clampf(float(boss["hp"]) / float(maxi(1, int(boss["max_hp"]))), 0.0, 1.0)
    canvas.draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 13)), Color("#0b0f16"))
    canvas.draw_rect(Rect2(origin, Vector2(width * ratio, 11)), Color("#b8323c"))
    if int(boss.get("shield", 0)) + int(boss.get("ward", 0)) > 0:
        canvas.draw_rect(Rect2(origin + Vector2(0, 9), Vector2(width, 2)), Color("#7fc4ff"))
    var phase: int = int(boss.get("phase", 0))
    var label: String = "%s  %s" % [String(boss.get("name", "Boss")).to_upper(),
        "I".repeat(phase + 1) if phase < 3 else str(phase + 1)]
    _text_box(label, origin + Vector2(0, 9), width, 10, Color.WHITE)


# --- Loadout panel (Wave 2B) ---------------------------------------------------

## Left-side panel: both weapons, the active item with its recharge arc, the
## consumable belt (selected slot outlined), credits and the crawler's statuses.
func _draw_loadout(view: Vector2) -> void:
    var view_model: Dictionary = Inventory.describe()
    var width: float = clampf(Vector2(layout["offset"]).x - 24.0, 150.0, 230.0)
    var origin := Vector2(10, maxf(102.0, 92.0 * Accessibility.text_scale() + 10.0))
    _panel(Rect2(origin, Vector2(width, 214)), Color(0.08, 0.11, 0.16, 0.78))
    var y: float = origin.y + 16.0
    _text("LOADOUT", Vector2(origin.x + 8, y), 11, Color("#f2da99"))
    _text("%d cr" % int(view_model["credits"]), Vector2(origin.x + width - 58, y), 12,
        Color("#ffd86b"))
    for slot in ["melee", "ranged"]:
        y += 18.0
        var weapon: Dictionary = view_model[slot]
        _text("M" if slot == "melee" else "R", Vector2(origin.x + 8, y), 11, Color("#8fa3b5"))
        _fit(String(weapon.get("name", "-")), Vector2(origin.x + 24, y), width - 30.0, 12,
            weapon.get("color", Color.WHITE))
    y += 26.0
    var active: Dictionary = view_model["active"]
    var center := Vector2(origin.x + 18, y - 4)
    canvas.draw_arc(center, 9.0, 0.0, TAU, 24, Color("#2c3a4c"), 3.0)
    if not active.is_empty():
        var fraction: float = float(active["fraction"])
        var ring: Color = Color("#7fe6a0") if fraction >= 1.0 else Color("#e0b85a")
        canvas.draw_arc(center, 9.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 24, ring, 3.0)
        _fit("[%s] %s" % [InputBindings.hint("use_item"), active["name"]], Vector2(origin.x + 34, y - 6), width - 40.0, 12,
            active.get("color", Color.WHITE))
        var detail: String = "%d/%d ready" % [int(active["charges"]), int(active["max_charges"])]
        if int(active["charges"]) <= 0:
            detail = _recharge_text(active)
        _text(detail, Vector2(origin.x + 34, y + 8), 10, Color("#a7b4c2"))
    else:
        _text("[%s] no active item" % InputBindings.hint("use_item"), Vector2(origin.x + 34, y - 1), 11, Color("#6f8090"))
    y += 22.0
    _fit("BELT  [%s] use  [%s] next" % [InputBindings.hint("use_consumable"),
        InputBindings.hint("next_consumable")], Vector2(origin.x + 8, y), width - 16.0, 10,
        Color("#8fa3b5"))
    y += 6.0
    var belt: Array = view_model["consumables"]
    var box: float = minf(28.0, (width - 16.0 - 5.0 * 4.0) / float(maxi(1, int(view_model["belt_size"]))))
    for i in range(int(view_model["belt_size"])):
        var at := Vector2(origin.x + 8 + float(i) * (box + 4.0), y)
        canvas.draw_rect(Rect2(at, Vector2(box, box)), Color("#1a2330"))
        if i < belt.size():
            var entry: Dictionary = belt[i]
            canvas.draw_rect(Rect2(at + Vector2(2, 2), Vector2(box - 4, box - 4)),
                Color(entry["color"], 0.35))
            _text(String(entry["name"]).substr(0, 2).to_upper(), at + Vector2(4, 13), 10, Color.WHITE)
            _text(str(int(entry["count"])), at + Vector2(box - 10, box - 3), 10, Color("#ffd86b"))
        if i == int(view_model["selected"]) and i < belt.size():
            canvas.draw_rect(Rect2(at - Vector2(1, 1), Vector2(box + 2, box + 2)), Color("#fff1a7"),
                false, 2.0)
    y += box + 14.0
    if int(view_model["selected"]) < belt.size():
        _fit(String(belt[int(view_model["selected"])]["name"]), Vector2(origin.x + 8, y),
            width - 16.0, 11, Color("#dce9f2"))
    y += 16.0
    var parts: PackedStringArray = []
    var ids: Array = RunState.statuses.keys()
    ids.sort()
    for status_id in ids:
        var instance: Dictionary = RunState.statuses[status_id]
        var label: String = "%s %.1fs" % [String(status_id).capitalize(), float(instance["remaining"])]
        if int(instance.get("stacks", 1)) > 1:
            label += " x%d" % int(instance["stacks"])
        if status_id == "shielded":
            label = "Shield %d" % int(instance.get("magnitude", 0))
        parts.append(label)
    if not parts.is_empty():
        _fit(", ".join(parts), Vector2(origin.x + 8, y), width - 16.0, 11, Color("#c9e3ff"))


# --- Skill slots (Wave 2F) -----------------------------------------------------

## Under the loadout panel: one row per active-skill slot with its key, name,
## a cooldown sweep and the seconds left; greyed while the stamina cost is not
## affordable. Banked skill points are flagged in the header.
func _draw_skills() -> void:
    var width: float = clampf(Vector2(layout["offset"]).x - 24.0, 150.0, 230.0)
    var origin := Vector2(10, maxf(102.0, 92.0 * Accessibility.text_scale() + 10.0) + 220.0)
    var slots: Array = SkillSystem.describe_slots()
    _panel(Rect2(origin, Vector2(width, 22.0 + 20.0 * slots.size())),
        Color(0.08, 0.11, 0.16, 0.78))
    _text("SKILLS", origin + Vector2(8, 15), 11, Color("#f2da99"))
    if RunState.skill_points > 0:
        _fit("%d pt: %s > Skills" % [RunState.skill_points, InputBindings.hint("pause")], origin + Vector2(58, 15), width - 64.0,
            10, Color("#a9e7c5"))
    var y: float = origin.y + 22.0
    for entry in slots:
        var center := Vector2(origin.x + 16, y + 7)
        canvas.draw_arc(center, 7.0, 0.0, TAU, 20, Color("#2c3a4c"), 3.0)
        # Wave 3C: the slot's live binding for the current device.
        var slot_index: int = int(entry.get("slot", 0))
        var key: String = "[%s] " % (InputBindings.hint(SkillSystem.SLOT_ACTIONS[slot_index])
            if slot_index < SkillSystem.SLOT_ACTIONS.size() else String(entry["key"]))
        if String(entry["id"]) == "":
            _text(key + "empty", Vector2(origin.x + 30, y + 11), 11, Color("#6f8090"))
            y += 20.0
            continue
        var left: float = float(entry["cooldown_left"])
        var fraction: float = 1.0 if left <= 0.0 \
            else clampf(1.0 - left / maxf(0.01, float(entry["cooldown"])), 0.0, 1.0)
        var ring: Color = Color("#7fe6a0") if bool(entry["ready"]) else (
            Color("#e0b85a") if left > 0.0 else Color("#6f8090"))
        canvas.draw_arc(center, 7.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 20, ring, 3.0)
        var affordable: bool = bool(entry["affordable"])
        _fit(key + String(entry["name"]), Vector2(origin.x + 30, y + 11), width - 86.0, 12,
            Color.WHITE if affordable else Color("#7d8b99"))
        var detail: String = "%.1fs" % left if left > 0.0 else (
            "ready" if affordable else "%d sta" % int(entry["stamina_cost"]))
        _text(detail, Vector2(origin.x + width - 50, y + 11), 10,
            Color("#a7b4c2") if affordable else Color("#d9a441"))
        y += 20.0


static func _recharge_text(active: Dictionary) -> String:
    var left: float = maxf(0.0, float(active["cooldown"]) - float(active["progress"]))
    match String(active["unit"]):
        "rooms_cleared":
            return "recharge: %d room%s" % [ceili(left), "" if ceili(left) == 1 else "s"]
        "floors":
            return "recharge: %d floor%s" % [ceili(left), "" if ceili(left) == 1 else "s"]
    return "recharge: %.1fs" % left


## Hover tooltip for the pickup under the crawler: name in rarity colour, kind,
## description, at 1.5x the HUD's small text.
func _draw_tooltip() -> void:
    if hover.is_empty():
        return
    var id: String = String(hover["id"])
    var info: Dictionary = {"name": "Sponsor Loot Box", "rarity": "epic", "kind": "crate",
        "description": "Two rewards inside, never common. Opening it is mandatory for the ratings.",
        "color": Inventory.RARITY_COLORS["epic"]} if id == "loot_box" else Inventory.label(id)
    var font: Font = ThemeDB.fallback_font
    var width := 300.0
    var anchor: Vector2 = Layout.world_to_screen(Vector2(hover["pos"]), layout)
    var description: String = String(info["description"])
    var body: int = Accessibility.px(15)
    var text_height: float = font.get_multiline_string_size(description,
        HORIZONTAL_ALIGNMENT_LEFT, width - 16.0, body).y
    var height: float = 48.0 * Accessibility.text_scale() + text_height
    var view: Vector2 = layout["viewport"]
    var at := Vector2(clampf(anchor.x - width * 0.5, 6.0, view.x - width - 6.0),
        maxf(96.0, anchor.y - height - 18.0))
    _panel(Rect2(at, Vector2(width, height)), Color(0.05, 0.07, 0.1, 0.92))
    canvas.draw_rect(Rect2(at, Vector2(width, height)), info["color"], false, 1.5)
    var row: float = Accessibility.text_scale()
    canvas.draw_string(font, at + Vector2(8, 21 * row), String(info["name"]), HORIZONTAL_ALIGNMENT_LEFT,
        width - 16.0, Accessibility.px(18), info["color"])
    var count: int = int(hover.get("count", 1))
    canvas.draw_string(font, at + Vector2(8, 38 * row), "%s %s%s" % [String(info["rarity"]).to_upper(),
        String(info["kind"]), " x%d" % count if count > 1 else ""], HORIZONTAL_ALIGNMENT_LEFT,
        -1.0, Accessibility.px(14), Color("#a7b4c2"))
    canvas.draw_multiline_string(font, at + Vector2(8, 56 * row), description, HORIZONTAL_ALIGNMENT_LEFT,
        width - 16.0, body, -1, Color("#e5eafa"))


## Draws `value` clipped to `max_width` (an ellipsis when it does not fit).
func _fit(value: String, position: Vector2, max_width: float, font_size: int, color: Color) -> void:
    var font: Font = ThemeDB.fallback_font
    var text: String = value
    while text.length() > 3 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
            Accessibility.px(font_size)).x > max_width:
        text = text.substr(0, text.length() - 2)
    if text != value:
        text = text.substr(0, text.length() - 1) + "…"
    _text(text, position, font_size, color)


# --- Collapse clock widget (Wave 2E) -------------------------------------------

## Colour of the tick counter: amber at <= 6, red at <= 3.
static func ticks_color(ticks: int) -> Color:
    if ticks <= TICKS_RED:
        return Color("#ff6b6b")
    if ticks <= TICKS_AMBER:
        return Color("#ffc15e")
    return Color("#f2da99")


## Tick counter left of the minimap; during grace a large red countdown and a
## remaining-grace bar replace it.
func _draw_clock(view: Vector2) -> void:
    var origin := Vector2(view.x - 330.0, 9.0)
    var grace: Dictionary = RunState.grace
    if bool(grace.get("active", false)):
        var remaining: float = float(grace.get("remaining", 0.0))
        var duration: float = maxf(0.01, float(grace.get("duration", 1.0)))
        _panel(Rect2(origin, Vector2(138, 82)), Color(0.25, 0.02, 0.03, 0.92))
        _text("COLLAPSE IN", origin + Vector2(8, 15), 12, Color("#ffb3b3"))
        _text("%.1f" % remaining, origin + Vector2(8, 58), 40, Color("#ff3b3b"))
        canvas.draw_rect(Rect2(origin + Vector2(8, 66), Vector2(122, 8)), Color("#3a0a0d"))
        canvas.draw_rect(Rect2(origin + Vector2(8, 66), Vector2(122.0 * remaining / duration, 8)),
            Color("#ff3b3b"))
        return
    _panel(Rect2(origin, Vector2(138, 82)), Color("#222c39"))
    _text("COLLAPSE TICKS", origin + Vector2(8, 15), 11, Color.WHITE)
    _text(str(RunState.ticks), origin + Vector2(8, 60), 40, ticks_color(RunState.ticks))
    var budget: int = int(RunState.floor.get("budget", 0))
    if budget > 0:
        _text("/ %d" % budget, origin + Vector2(80, 60), 13, Color("#a7b4c2"))


## Red dust vignette while grace runs; it thickens as time runs out.
func _draw_grace_vignette(view: Vector2) -> void:
    var grace: Dictionary = RunState.grace
    if not bool(grace.get("active", false)):
        return
    var urgency: float = 1.0 - float(grace.get("remaining", 0.0)) \
        / maxf(0.01, float(grace.get("duration", 1.0)))
    var edge: float = 10.0 + 26.0 * urgency
    var tint := Color(0.55, 0.05, 0.05, 0.22 + 0.25 * urgency)
    canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(view.x, edge)), tint)
    canvas.draw_rect(Rect2(Vector2(0, view.y - edge), Vector2(view.x, edge)), tint)
    canvas.draw_rect(Rect2(Vector2(0, edge), Vector2(edge, view.y - edge * 2.0)), tint)
    canvas.draw_rect(Rect2(Vector2(view.x - edge, edge), Vector2(edge, view.y - edge * 2.0)), tint)


## Interaction prompt, centred above the hint lines (`hints_top`, Wave 3C).
func _draw_prompt(view: Vector2, hints_top: float = -1.0) -> void:
    if prompt == "":
        return
    var font: Font = ThemeDB.fallback_font
    var size: int = Accessibility.px(15)
    var width: float = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
    var baseline: float = view.y - 72.0 if hints_top < 0.0 else minf(view.y - 72.0,
        hints_top - float(Accessibility.px(13)) - 16.0)
    var at := Vector2((view.x - width) * 0.5, baseline)
    _panel(Rect2(at + Vector2(-10, -size - 3), Vector2(width + 20, size + 11)),
        Color(0.05, 0.07, 0.1, 0.85))
    _text(prompt, at, 15, Color("#fff1a7"))


func _draw_minimap(view: Vector2) -> void:
    var floor_data: Dictionary = RunState.floor
    var map_origin := Vector2(view.x - 185.0, 9.0)
    _panel(Rect2(map_origin, Vector2(174, 82)), Color("#222c39"))
    _text("MAP", map_origin + Vector2(8, 13), 11, Color.WHITE)
    var min_cell := Vector2i(999, 999)
    var max_cell := Vector2i(-999, -999)
    for room in floor_data["rooms"]:
        var cell: Vector2i = room["grid"]
        min_cell.x = mini(min_cell.x, cell.x)
        min_cell.y = mini(min_cell.y, cell.y)
        max_cell.x = maxi(max_cell.x, cell.x)
        max_cell.y = maxi(max_cell.y, cell.y)
    var span_x: int = maxi(1, max_cell.x - min_cell.x + 1)
    var span_y: int = maxi(1, max_cell.y - min_cell.y + 1)
    var unit: float = minf(9.0, minf(156.0 / float(span_x), 60.0 / float(span_y)))
    for room in floor_data["rooms"]:
        var id: int = int(room["id"])
        if not RunState.visited.has(id) and id != int(floor_data["exit_id"]):
            continue
        var cell: Vector2i = room["grid"]
        var p: Vector2 = map_origin + Vector2(
            8.0 + float(cell.x - min_cell.x) * unit,
            20.0 + float(cell.y - min_cell.y) * unit)
        var color: Color = FloorMap.KIND_COLORS.get(String(room["kind"]), Color("#788b9d"))
        if id == RunState.current_room_id: color = Color.WHITE
        canvas.draw_rect(Rect2(p, Vector2(maxf(3.0, unit - 1.0), maxf(3.0, unit - 1.0))), color)


## HUD text at `font_size` x text_scale, outlined in high contrast (3C).
func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
    var size: int = Accessibility.px(font_size)
    if Accessibility.outline() > 0:
        canvas.draw_string_outline(ThemeDB.fallback_font, position, value,
            HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Accessibility.outline(), Accessibility.OUTLINE_COLOR)
    canvas.draw_string(ThemeDB.fallback_font, position, value,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## Centred text in a `width` box (boss bar label).
func _text_box(value: String, position: Vector2, width: float, font_size: int, color: Color) -> void:
    var size: int = Accessibility.px(font_size)
    if Accessibility.outline() > 0:
        canvas.draw_string_outline(ThemeDB.fallback_font, position, value,
            HORIZONTAL_ALIGNMENT_CENTER, width, size, Accessibility.outline(), Accessibility.OUTLINE_COLOR)
    canvas.draw_string(ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_CENTER, width,
        size, color)


## A HUD panel: `normal` fill, or opaque black with a white edge in high contrast.
func _panel(rect: Rect2, normal: Color) -> void:
    canvas.draw_rect(rect, Accessibility.panel(normal))
    if Accessibility.high_contrast():
        canvas.draw_rect(rect, Accessibility.HIGH_CONTRAST_BORDER, false, 1.0)
