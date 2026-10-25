extends CanvasLayer
## Modal UI; gameplay is frozen by Game (LEVEL_UP / PAUSED states) while this
## overlay is visible. Scores and context come from RunState via game.gd.
## Esc toggles pause; level-up must be allocated before combat resumes.
signal resume_requested
signal allocation_confirmed(changes: Dictionary)
signal resolution_requested(size: Vector2i)
## Pause -> Settings: Game opens the shared settings screen above this menu.
signal settings_requested
## Pause -> Abandon run -> confirm: Game ends the run as "abandoned".
signal abandon_requested

const RPG = preload("res://scripts/rpg_rules.gd")
const Achievements = preload("res://scripts/core/achievements.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Settings = preload("res://scripts/core/settings.gd")
## Kept as an alias so callers and tests can keep using CharacterMenu's name;
## the list itself lives in settings.gd.
const RESOLUTION_PRESETS = Settings.RESOLUTION_PRESETS
const ABILITY_NAMES := {
    "STR": "Strength", "DEX": "Dexterity", "CON": "Constitution",
    "INT": "Intelligence", "WIS": "Wisdom", "CHA": "Charisma"
}

var mode := "closed"
var page := "overview"
var scores: Dictionary = {}
var context: Dictionary = {}
var staged: Dictionary = {}
var point_pool := 0
var score_cap := 20
var selected_resolution := Vector2i(960, 540)
var current_resolution := Vector2i(960, 540)
var resolution_feedback := ""
var overlay: Control
var center: CenterContainer


func _ready() -> void:
    layer = 10
    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(overlay)
    var dim := ColorRect.new()
    dim.color = Color(0.015, 0.025, 0.045, 0.86)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.add_child(dim)
    center = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(center)
    overlay.visible = false


func is_open() -> bool:
    return mode != "closed"


func close_menu() -> void:
    mode = "closed"
    overlay.visible = false


func show_pause(new_scores: Dictionary, new_context: Dictionary) -> void:
    scores = new_scores.duplicate(true)
    context = new_context.duplicate(true)
    mode = "pause"
    page = "overview"
    current_resolution = Vector2i(new_context.get("window_size", Vector2i(960, 540)))
    selected_resolution = current_resolution if RESOLUTION_PRESETS.has(current_resolution) else Vector2i(960, 540)
    resolution_feedback = ""
    _refresh()


func show_level_up(new_scores: Dictionary, new_context: Dictionary,
        available_points: int, maximum_score: int = 20) -> void:
    scores = new_scores.duplicate(true)
    context = new_context.duplicate(true)
    staged.clear()
    point_pool = maxi(0, available_points)
    score_cap = maximum_score
    mode = "level_up"
    _refresh()


func remaining_points() -> int:
    var used := 0
    for ability in RPG.ABILITIES:
        used += int(staged.get(ability, 0))
    return maxi(0, point_pool - used)


func stage_point(ability: String, change: int) -> bool:
    if mode != "level_up" or not RPG.ABILITIES.has(ability):
        return false
    var old: int = int(staged.get(ability, 0))
    var next: int = old + change
    if next < 0 or int(scores.get(ability, 10)) + next > score_cap:
        return false
    if change > 0 and remaining_points() < change:
        return false
    staged[ability] = next
    if is_inside_tree():
        call_deferred("_refresh")
    return true


func confirm_allocation() -> void:
    if mode != "level_up":
        return
    if RPG.validate_allocation(scores, staged, point_pool, score_cap):
        allocation_confirmed.emit(staged.duplicate(true))


func _resume() -> void:
    if mode != "pause":
        return
    close_menu()
    resume_requested.emit()


func _select_resolution(index: int) -> void:
    if mode != "pause" or index < 0 or index >= RESOLUTION_PRESETS.size():
        return
    selected_resolution = RESOLUTION_PRESETS[index]


func _apply_resolution() -> void:
    if mode != "pause" or not RESOLUTION_PRESETS.has(selected_resolution):
        return
    resolution_requested.emit(selected_resolution)
    resolution_feedback = "Requested %d × %d (windowed)" % [
        selected_resolution.x, selected_resolution.y
    ]
    _refresh()


func _open_character_page() -> void:
    if mode == "pause":
        page = "character"
        _refresh()


func _open_overview_page() -> void:
    if mode == "pause":
        page = "overview"
        _refresh()


func _open_abandon_page() -> void:
    if mode == "pause":
        page = "abandon"
        _refresh()


func _confirm_abandon() -> void:
    if mode == "pause" and page == "abandon":
        close_menu()
        abandon_requested.emit()


## Rebuilds the current page (Game calls it when the settings screen closes so
## focus returns here).
func refresh() -> void:
    _refresh()


func _refresh() -> void:
    if not is_inside_tree() or mode == "closed":
        return
    overlay.visible = true
    for node in center.get_children():
        center.remove_child(node)
        node.queue_free()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(576, 425)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#172333")
    style.border_color = Color("#d5b978")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    panel.add_theme_stylebox_override("panel", style)
    center.add_child(panel)

    var padding := MarginContainer.new()
    padding.add_theme_constant_override("margin_left", 19)
    padding.add_theme_constant_override("margin_right", 19)
    padding.add_theme_constant_override("margin_top", 13)
    padding.add_theme_constant_override("margin_bottom", 13)
    panel.add_child(padding)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 5)
    padding.add_child(content)

    if mode == "level_up":
        _level_up_content(content)
    elif page == "character":
        _character_content(content)
    elif page == "abandon":
        _abandon_content(content)
    elif page == "achievements":
        _achievements_content(content)
    else:
        _pause_content(content)


func _level_up_content(content: VBoxContainer) -> void:
    content.add_child(_text("LEVEL UP!   Level %d" % int(context.get("level", 1)),
        25, Color("#f6d48d")))
    content.add_child(_text("Spend %d ability points  •  %d remaining  •  max score %d" % [
        point_pool, remaining_points(), score_cap], 14, Color("#c5dee4")))
    content.add_child(_text("STR: melee  •  DEX: ranged + AC  •  CON: maximum HP", 12,
        Color("#9cbac6")))

    var grid := GridContainer.new()
    grid.columns = 4
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 2)
    content.add_child(grid)
    for ability in RPG.ABILITIES:
        var score: int = int(scores.get(ability, 10)) + int(staged.get(ability, 0))
        var previous: int = int(scores.get(ability, 10))
        var detail := _text("%s  %s" % [ability, ABILITY_NAMES[ability]], 14, Color.WHITE)
        detail.custom_minimum_size.x = 230
        grid.add_child(detail)
        var value := _text("%d → %d  (%+d)" % [previous, score, RPG.modifier(score)],
            14, Color("#a9e7c5"))
        value.custom_minimum_size.x = 155
        grid.add_child(value)

        var minus := _button("−", Callable(self, "_on_change_point").bind(ability, -1))
        minus.custom_minimum_size.x = 38
        minus.disabled = int(staged.get(ability, 0)) <= 0
        grid.add_child(minus)
        var plus := _button("+", Callable(self, "_on_change_point").bind(ability, 1))
        plus.custom_minimum_size.x = 38
        plus.disabled = remaining_points() == 0 or score >= score_cap
        grid.add_child(plus)

    content.add_child(_text("INT / WIS / CHA are reserved for future skills, spells, and checks.",
        12, Color("#b4c4d2")))
    var confirm := _button("Confirm allocation • Return to dungeon",
        Callable(self, "confirm_allocation"))
    confirm.disabled = remaining_points() != 0
    confirm.custom_minimum_size.y = 34
    content.add_child(confirm)
    content.add_child(_text("Combat and collapse are frozen. Allocate all points to continue.",
        12, Color("#e2c78e")))
    if remaining_points() == 0:
        confirm.grab_focus()


func _on_change_point(ability: String, change: int) -> void:
    stage_point(ability, change)


func _pause_content(content: VBoxContainer) -> void:
    content.add_child(_text("PAUSED", 27, Color("#f6d48d")))
    content.add_child(_text("Floor %d/%d  •  Room %d  •  Collapse %d ticks" % [
        int(context.get("depth", 1)), int(context.get("target_depth", 6)),
        int(context.get("room_id", 0)), int(context.get("ticks", 0))],
        15, Color("#d2e0e8")))
    content.add_child(_text("Level %d    XP %d    HP %d/%d    AC %d" % [
        int(context.get("level", 1)), int(context.get("xp", 0)),
        int(context.get("hp", 1)), int(context.get("max_hp", 1)),
        int(context.get("ac", 10))], 18, Color.WHITE))
    content.add_child(_button("View character stats", Callable(self, "_open_character_page")))
    content.add_child(_text("DISPLAY RESOLUTION (windowed)", 14, Color("#f6d48d")))
    var resolution_row := HBoxContainer.new()
    resolution_row.add_theme_constant_override("separation", 10)
    content.add_child(resolution_row)
    var selector := OptionButton.new()
    selector.custom_minimum_size = Vector2(225, 32)
    for resolution in RESOLUTION_PRESETS:
        selector.add_item("%d × %d" % [resolution.x, resolution.y])
    selector.select(RESOLUTION_PRESETS.find(selected_resolution))
    selector.item_selected.connect(_select_resolution)
    resolution_row.add_child(selector)
    var apply := _button("Apply resolution", Callable(self, "_apply_resolution"))
    resolution_row.add_child(apply)
    content.add_child(_text("Current: %d × %d  |  World room remains 24 × 24 tiles" % [
        current_resolution.x, current_resolution.y
    ], 12, Color("#9eb8c4")))
    if not resolution_feedback.is_empty():
        content.add_child(_text(resolution_feedback, 12, Color("#a9e7c5")))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    content.add_child(row)
    row.add_child(_button("Settings", func(): settings_requested.emit()))
    row.add_child(_button("Achievements", Callable(self, "_open_achievements_page")))
    row.add_child(_button("Abandon run", Callable(self, "_open_abandon_page")))
    var resume := _button("Resume game  (Esc)", Callable(self, "_resume"))
    content.add_child(resume)
    content.add_child(_text("WASD: move   Mouse: aim   Left click: shoot   Space: melee",
        12, Color("#9eb8c4")))
    resume.grab_focus()


func _abandon_content(content: VBoxContainer) -> void:
    content.add_child(_text("ABANDON RUN?", 25, Color("#f6d48d")))
    content.add_child(_text("The run ends here and counts as a failure. The dungeon keeps the floor.",
        14, Color("#c5dee4")))
    var back := _button("No, keep crawling", Callable(self, "_open_overview_page"))
    content.add_child(back)
    content.add_child(_button("Yes, abandon this run", Callable(self, "_confirm_abandon")))
    back.grab_focus()


func _character_content(content: VBoxContainer) -> void:
    content.add_child(_text("CHARACTER STATS", 25, Color("#f6d48d")))
    content.add_child(_text("Level %d  •  XP %d/%s  •  Proficiency +%d" % [
        int(context.get("level", 1)), int(context.get("xp", 0)),
        str(context.get("next_xp", "?")), int(context.get("proficiency", 2))],
        14, Color("#c5dee4")))
    content.add_child(_text("HP %d/%d    AC %d    STR melee %+d    DEX ranged %+d" % [
        int(context.get("hp", 1)), int(context.get("max_hp", 1)),
        int(context.get("ac", 10)), int(context.get("melee_bonus", 0)),
        int(context.get("ranged_bonus", 0))], 14, Color("#dae3e9")))
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 28)
    grid.add_theme_constant_override("v_separation", 7)
    content.add_child(grid)
    for ability in RPG.ABILITIES:
        var score: int = int(scores.get(ability, 10))
        grid.add_child(_text("%s   %s" % [ability, ABILITY_NAMES[ability]], 15,
            Color.WHITE))
        grid.add_child(_text("%d    modifier %+d" % [score, RPG.modifier(score)],
            15, Color("#a9e7c5")))
    content.add_child(_button("Back to pause menu", Callable(self, "_open_overview_page")))
    content.add_child(_button("Resume game  (Esc)", Callable(self, "_resume")))


## Achievements page (Wave 2G): every definition, unlocked ones from the profile.
func _open_achievements_page() -> void:
    if mode == "pause":
        page = "achievements"
        _refresh()


func _achievements_content(content: VBoxContainer) -> void:
    var definitions: Array = Achievements.default_definitions()
    var unlocked: Dictionary = Profile.unlocked()
    var earned := 0
    for definition in definitions:
        if unlocked.has(String(definition.get("id", ""))):
            earned += 1
    content.add_child(_text("ACHIEVEMENTS   %d / %d" % [earned, definitions.size()], 25,
        Color("#f6d48d")))
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(538, 290)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.add_child(scroll)
    var rows := VBoxContainer.new()
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows.add_theme_constant_override("separation", 1)
    scroll.add_child(rows)
    for definition in definitions:
        var got: bool = unlocked.has(String(definition.get("id", "")))
        var hidden: bool = not got and bool(definition.get("secret", false))
        rows.add_child(_text("%s  %s" % ["[x]" if got else "[  ]",
            "???" if hidden else String(definition.get("title", ""))], 15,
            Color("#a9e7c5") if got else Color("#b4c4d2")))
        var detail := _text("Classified until earned." if hidden else String(
            definition.get("quip" if got else "description", "")), 12,
            Color("#e2c78e") if got else Color("#8ea3b3"))
        detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        detail.custom_minimum_size.x = 510
        rows.add_child(detail)
    content.add_child(_button("Back to pause menu", Callable(self, "_open_overview_page")))
    content.add_child(_button("Resume game  (Esc)", Callable(self, "_resume")))


func _button(label: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size.y = 31
    button.add_theme_font_size_override("font_size", 14)
    button.pressed.connect(callback)
    return button


func _text(value: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label
