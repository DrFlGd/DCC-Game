extends CanvasLayer
## Modal UI; gameplay is frozen by Game (LEVEL_UP / PAUSED states) while this
## overlay is visible. Scores and context come from RunState via game.gd.
## Esc toggles pause; level-up must be allocated before combat resumes.
## Wave 2F: the level-up overlay also lists every skill (context["skills"],
## SkillSystem.describe(), passed in by Game so this script stays
## autoload-free). A pick emits skill_learn_requested and Game answers with
## update_context(). Confirm needs every ability point staged and every skill
## point spent, unless nothing is learnable; "Save for later" banks skill
## points. The pause menu's Skills page lists learned skills, slot bindings
## and banked points, and spends them the same way.
## Wave 3C: fully gamepad / keyboard operable. Every page focuses a control
## when it opens; B (ui_cancel that is not `pause`) goes back to the overview
## or resumes from it; a focused list (achievements, inventory) scrolls with
## up / down before focus moves on. Text follows text_scale, the panel turns
## black and white in high contrast, and key names come from the live bindings
## for the last-used device (InputBindings).
signal resume_requested
signal allocation_confirmed(changes: Dictionary)
signal resolution_requested(size: Vector2i)
## Pause -> Settings: Game opens the shared settings screen above this menu.
signal settings_requested
## Pause -> Abandon run -> confirm: Game ends the run as "abandoned".
signal abandon_requested
## Level-up overlay or Skills page: learn one rank of `skill_id` (Game calls
## SkillSystem.learn and then update_context).
signal skill_learn_requested(skill_id: String)
## Skills page: bind learned active skill `skill_id` to `slot` (0-based).
signal skill_slot_requested(skill_id: String, slot: int)

const RPG = preload("res://scripts/rpg_rules.gd")
const Achievements = preload("res://scripts/core/achievements.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Accessibility = preload("res://scripts/core/accessibility.gd")
const InputBindings = preload("res://scripts/core/input_bindings.gd")
## Skill slot actions (SkillSystem.SLOT_ACTIONS), for live key names.
const SLOT_ACTIONS := ["use_skill_1", "use_skill_2"]
## Pixels one up / down press scrolls a focused list.
const SCROLL_STEP := 48
## Kept as an alias so callers and tests can keep using CharacterMenu's name;
## the list itself lives in settings.gd.
const RESOLUTION_PRESETS = Settings.RESOLUTION_PRESETS
const SLOT_KEYS := ["Z", "X"]
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


## Wave 3C: list scrolling and B on the pause pages (see the class comment).
func _input(event: InputEvent) -> void:
    if mode == "closed" or overlay == null or not overlay.visible:
        return
    var focused: Control = get_viewport().gui_get_focus_owner()
    if focused is ScrollContainer and center.is_ancestor_of(focused):
        var scroll := focused as ScrollContainer
        var limit: float = maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
        if event.is_action_pressed("ui_down", true) and scroll.scroll_vertical < int(limit):
            scroll.scroll_vertical = mini(int(limit), scroll.scroll_vertical + SCROLL_STEP)
            get_viewport().set_input_as_handled()
            return
        if event.is_action_pressed("ui_up", true) and scroll.scroll_vertical > 0:
            scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - SCROLL_STEP)
            get_viewport().set_input_as_handled()
            return
    if event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause"):
        if go_back():
            get_viewport().set_input_as_handled()


## B: a pause sub-page returns to the overview; the overview resumes the game.
## The level-up overlay ignores it. Returns true when something happened.
func go_back() -> bool:
    if mode != "pause":
        return false
    if page != "overview":
        _open_overview_page()
    else:
        _resume()
    return true


## Live key name of `action` for the last-used device.
static func key_name(action: String) -> String:
    return InputBindings.hint(action)


## Explicit left / right neighbours along a row of buttons (wrapping), so the
## D-pad walks the row instead of jumping to a wider control below it.
static func link_row(row: Container) -> void:
    var buttons: Array = []
    for child in row.get_children():
        if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
            buttons.append(child)
    for i in range(buttons.size()):
        var here: Control = buttons[i]
        here.focus_neighbor_left = here.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
        here.focus_neighbor_right = here.get_path_to(buttons[(i + 1) % buttons.size()])


## Focusable list wrapper so a gamepad can scroll it (see _input).
func _focus_scroll(scroll: ScrollContainer) -> void:
    scroll.name = "scroll"
    scroll.focus_mode = Control.FOCUS_ALL


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


## Replaces the context (Game calls it after a skill pick or slot change)
## without touching staged ability points. The page is rebuilt next frame,
## because the request usually comes from one of its own buttons.
func update_context(new_context: Dictionary) -> void:
    context = new_context.duplicate(true)
    if is_inside_tree() and mode != "closed":
        call_deferred("_refresh")


## SkillSystem.describe() from the context ({} when Game passed none).
func skill_view() -> Dictionary:
    return context.get("skills", {})


## Banked skill points.
func skill_points() -> int:
    return int(skill_view().get("points", 0))


## Ids of the skills that can take a rank now.
func learnable_skills() -> Array:
    var result: Array = []
    for entry in skill_view().get("skills", []):
        if bool(entry.get("learnable", false)):
            result.append(String(entry["id"]))
    return result


## Asks Game to learn one rank of `skill_id` (level-up overlay or Skills page).
## Returns false when the skill is not learnable now.
func pick_skill(skill_id: String) -> bool:
    if mode == "closed" or not learnable_skills().has(skill_id):
        return false
    skill_learn_requested.emit(skill_id)
    return true


## Skills page: asks Game to bind `skill_id` to `slot`.
func assign_skill_slot(skill_id: String, slot: int) -> void:
    if mode == "pause":
        skill_slot_requested.emit(skill_id, slot)


## Confirm is allowed once every ability point is staged and every skill
## point is spent (or nothing is learnable, so nobody gets stuck).
func can_confirm() -> bool:
    return remaining_points() == 0 and (skill_points() == 0 or learnable_skills().is_empty())


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
    if mode != "level_up" or not can_confirm():
        return
    if RPG.validate_allocation(scores, staged, point_pool, score_cap):
        allocation_confirmed.emit(staged.duplicate(true))


## "Save for later": confirms the ability points and keeps the skill points
## banked (spend them on the pause menu's Skills page).
func bank_and_confirm() -> void:
    if mode != "level_up" or remaining_points() != 0:
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
    # Keyboard / gamepad focus survives a rebuild when the same control exists.
    var focused: Control = get_viewport().gui_get_focus_owner()
    var focus_name: String = String(focused.name) if focused != null \
        and center.is_ancestor_of(focused) else ""
    for node in center.get_children():
        center.remove_child(node)
        node.queue_free()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(576, 425)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#000000") if Accessibility.high_contrast() else Color("#172333")
    style.border_color = Color.WHITE if Accessibility.high_contrast() else Color("#d5b978")
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
    elif page == "inventory":
        _inventory_content(content)
    elif page == "skills":
        _skills_content(content)
    else:
        _pause_content(content)
    if focus_name != "":
        var again: Node = panel.find_child(focus_name, true, false)
        if again is Control and (again as Control).focus_mode != Control.FOCUS_NONE \
                and not (again is BaseButton and (again as BaseButton).disabled):
            (again as Control).grab_focus()


func _level_up_content(content: VBoxContainer) -> void:
    content.add_child(_text("LEVEL UP!   Level %d" % int(context.get("level", 1)),
        25, Color("#f6d48d")))
    var points: int = skill_points()
    content.add_child(_text("Ability points %d/%d left  •  Skill points %d  •  max score %d" % [
        remaining_points(), point_pool, points, score_cap], 14, Color("#c5dee4")))
    content.add_child(_text("STR melee • DEX ranged, AC • CON HP • INT skill power • WIS stamina • CHA prices",
        12, Color("#9cbac6")))

    # Two abilities per row so the skill list fits a 480 px tall window.
    var grid := GridContainer.new()
    grid.columns = 8
    grid.add_theme_constant_override("h_separation", 6)
    grid.add_theme_constant_override("v_separation", 2)
    content.add_child(grid)
    for ability in RPG.ABILITIES:
        var score: int = int(scores.get(ability, 10)) + int(staged.get(ability, 0))
        var previous: int = int(scores.get(ability, 10))
        var detail := _text(ability, 14, Color.WHITE)
        detail.tooltip_text = ABILITY_NAMES[ability]
        detail.mouse_filter = Control.MOUSE_FILTER_PASS
        detail.custom_minimum_size.x = 38
        grid.add_child(detail)
        var value := _text("%d → %d (%+d)" % [previous, score, RPG.modifier(score)],
            14, Color("#a9e7c5"))
        value.custom_minimum_size.x = 112
        grid.add_child(value)
        var minus := _button("−", Callable(self, "_on_change_point").bind(ability, -1))
        minus.name = "minus_" + ability
        minus.custom_minimum_size.x = 34
        minus.disabled = int(staged.get(ability, 0)) <= 0
        grid.add_child(minus)
        var plus := _button("+", Callable(self, "_on_change_point").bind(ability, 1))
        plus.name = "plus_" + ability
        plus.custom_minimum_size.x = 34
        plus.disabled = remaining_points() == 0 or score >= score_cap
        grid.add_child(plus)

    var learnable: Array = learnable_skills()
    content.add_child(_text("SKILLS   %s" % ("pick a rank-up, or save the point for later" if points > 0
        else "no skill points left"), 14, Color("#f6d48d")))
    var first_skill: Button = _skill_list(content, 150.0, false)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    content.add_child(row)
    var confirm := _button("Confirm • Return to dungeon", Callable(self, "confirm_allocation"))
    confirm.name = "confirm"
    confirm.disabled = not can_confirm()
    confirm.custom_minimum_size.y = 34
    row.add_child(confirm)
    var bank: Button = null
    if points > 0 and not learnable.is_empty():
        bank = _button("Save %d skill point%s for later" % [points, "" if points == 1 else "s"],
            Callable(self, "bank_and_confirm"))
        bank.name = "bank"
        bank.disabled = remaining_points() != 0
        bank.custom_minimum_size.y = 34
        row.add_child(bank)
    var footer := "Combat and collapse are frozen."
    if remaining_points() > 0:
        footer += " Allocate every ability point to continue."
    elif points > 0 and not learnable.is_empty():
        footer += " Pick a skill or save the point."
    content.add_child(_text(footer, 12, Color("#e2c78e")))
    if remaining_points() == 0:
        if can_confirm():
            confirm.grab_focus()
        elif first_skill != null:
            first_skill.grab_focus()
        elif bank != null:
            bank.grab_focus()
    else:
        for ability in RPG.ABILITIES:
            var plus: Node = grid.find_child("plus_" + ability, false, false)
            if plus is Button and not (plus as Button).disabled:
                (plus as Button).grab_focus()
                break


## One row per skill (name, rank X/Y, kind, cost, description, next rank or
## the locked reason; unlearnable rows greyed). `with_slots` adds slot buttons
## for learned actives (Skills page). Returns the first enabled pick button.
func _skill_list(content: VBoxContainer, height: float, with_slots: bool) -> Button:
    var first: Button = null
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(538, height)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    content.add_child(scroll)
    var rows := VBoxContainer.new()
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows.add_theme_constant_override("separation", 3)
    scroll.add_child(rows)
    var entries: Array = skill_view().get("skills", [])
    if entries.is_empty():
        rows.add_child(_text("No skills on file. The System is still drafting the paperwork.", 12,
            Color("#8ea3b3")))
    for entry in entries:
        var id: String = String(entry["id"])
        var rank: int = int(entry.get("rank", 0))
        var max_rank: int = int(entry.get("max_rank", 1))
        var learnable: bool = bool(entry.get("learnable", false))
        var reason: String = String(entry.get("reason", ""))
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        rows.add_child(row)
        var label := "Learn" if rank == 0 else "Rank up"
        if rank >= max_rank:
            label = "Maxed"
        elif not learnable and reason != "points":
            label = "Locked"
        var pick := _button(label, Callable(self, "pick_skill").bind(id))
        pick.name = "learn_" + id
        pick.custom_minimum_size.x = 78
        pick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        pick.disabled = not learnable
        row.add_child(pick)
        if learnable and first == null:
            first = pick
        var info := VBoxContainer.new()
        info.add_theme_constant_override("separation", 0)
        info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(info)
        var kind: String = String(entry.get("kind", "passive"))
        var heading := "%s   rank %d/%d   %s   cost %d" % [String(entry.get("name", id)), rank,
            max_rank, kind, int(entry.get("cost", 1))]
        if kind == "active":
            heading += "   %d stamina, %.1fs" % [int(entry.get("stamina_cost", 0)),
                float(entry.get("cooldown", 0.0))]
            if int(entry.get("slot", -1)) >= 0:
                heading += "   [%s]" % key_name(SLOT_ACTIONS[int(entry["slot"])]) \
                    if int(entry["slot"]) < SLOT_ACTIONS.size() else SLOT_KEYS[int(entry["slot"])]
        var color := Color("#a9e7c5") if rank > 0 else (Color.WHITE if learnable else Color("#7d8b99"))
        info.add_child(_text(heading, 13, color))
        var lines: PackedStringArray = [String(entry.get("description", ""))]
        if rank >= max_rank:
            lines.append("Now: " + ", ".join(PackedStringArray(entry.get("effects", []))))
        elif not entry.get("next", []).is_empty():
            lines.append(("Next: " if rank > 0 else "Rank 1: ") + ", ".join(PackedStringArray(entry["next"])))
        if not learnable and String(entry.get("detail", "")) != "" and rank < max_rank:
            lines.append("Locked: " + String(entry["detail"]) if reason != "points"
                else String(entry["detail"]))
        var detail := _text("\n".join(lines), 11, Color("#8ea3b3") if learnable or rank > 0
            else Color("#66737f"))
        detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        detail.custom_minimum_size.x = 420
        info.add_child(detail)
        if with_slots and kind == "active" and rank > 0:
            var slot_row := HBoxContainer.new()
            slot_row.add_theme_constant_override("separation", 6)
            info.add_child(slot_row)
            for slot in range(skill_view().get("slots", []).size()):
                var bind := _button("Slot %d [%s]" % [slot + 1, key_name(SLOT_ACTIONS[slot]) if slot < SLOT_ACTIONS.size()
                    else str(slot + 1)], Callable(self, "assign_skill_slot").bind(id, slot))
                bind.name = "slot_%d_%s" % [slot, id]
                bind.custom_minimum_size.y = 26
                bind.disabled = int(entry.get("slot", -1)) == slot
                slot_row.add_child(bind)
    return first


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
    row.add_child(_button("Inventory", Callable(self, "_open_inventory_page")))
    var banked: int = skill_points()
    row.add_child(_button("Skills (%d)" % banked if banked > 0 else "Skills",
        Callable(self, "_open_skills_page")))
    row.add_child(_button("Settings", func(): settings_requested.emit()))
    row.add_child(_button("Achievements", Callable(self, "_open_achievements_page")))
    row.add_child(_button("Abandon run", Callable(self, "_open_abandon_page")))
    var resume := _button("Resume game  (%s)" % key_name("pause"), Callable(self, "_resume"))
    resume.name = "resume"
    content.add_child(resume)
    link_row(row)
    link_row(resolution_row)
    content.add_child(_text("%s: move   %s: aim   %s: shoot   %s: melee   %s / %s: skills   %s" % [
        InputBindings.move_hint(), InputBindings.aim_hint(), key_name("fire"), key_name("melee"),
        key_name("use_skill_1"), key_name("use_skill_2"),
        "B: back" if InputBindings.is_gamepad() else "Esc: back"], 12, Color("#9eb8c4")))
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
    var back := _button("Back to pause menu", Callable(self, "_open_overview_page"))
    content.add_child(back)
    content.add_child(_button("Resume game  (%s)" % key_name("pause"), Callable(self, "_resume")))
    back.grab_focus()


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
    _focus_scroll(scroll)
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
    content.add_child(_button("Resume game  (%s)" % key_name("pause"), Callable(self, "_resume")))
    scroll.grab_focus()


## Inventory page (Wave 2B): weapons, active item, passives with stack counts,
## the consumable belt and credits, from context["inventory"]
## (Inventory.describe(), passed in by Game so this script stays autoload-free).
func _open_inventory_page() -> void:
    if mode == "pause":
        page = "inventory"
        _refresh()


func _inventory_content(content: VBoxContainer) -> void:
    var view: Dictionary = context.get("inventory", {})
    content.add_child(_text("INVENTORY   %d credits" % int(view.get("credits", 0)), 25,
        Color("#f6d48d")))
    var scroll := ScrollContainer.new()
    _focus_scroll(scroll)
    scroll.custom_minimum_size = Vector2(538, 290)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.add_child(scroll)
    var rows := VBoxContainer.new()
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows.add_theme_constant_override("separation", 1)
    scroll.add_child(rows)
    for slot in [["melee", "Melee"], ["ranged", "Ranged"], ["active", "Active [%s]" % key_name("use_item")]]:
        var entry: Dictionary = view.get(slot[0], {})
        var suffix := ""
        if slot[0] == "active" and not entry.is_empty():
            suffix = "   %d/%d charges" % [int(entry.get("charges", 0)), int(entry.get("max_charges", 1))]
        _inventory_row(rows, "%s: %s%s" % [slot[1], String(entry.get("name", "(empty)")), suffix],
            entry)
    rows.add_child(_text("PASSIVES", 14, Color("#f6d48d")))
    var passives: Array = view.get("passives", [])
    if passives.is_empty():
        rows.add_child(_text("None yet. The sponsors are watching your spending habits.", 12,
            Color("#8ea3b3")))
    for entry in passives:
        _inventory_row(rows, "%s  x%d/%d" % [String(entry["name"]), int(entry["count"]),
            int(entry.get("stack_max", 1))], entry)
    rows.add_child(_text("BELT  (%d slots, %s uses the selected one, %s cycles)" % [int(
        view.get("belt_size", 6)), key_name("use_consumable"), key_name("next_consumable")], 14,
        Color("#f6d48d")))
    var belt: Array = view.get("consumables", [])
    if belt.is_empty():
        rows.add_child(_text("Empty.", 12, Color("#8ea3b3")))
    for i in range(belt.size()):
        var entry: Dictionary = belt[i]
        _inventory_row(rows, "%s%d. %s  x%d/%d" % ["> " if i == int(view.get("selected", 0)) else "  ",
            i + 1, String(entry["name"]), int(entry["count"]), int(entry.get("stack_max", 1))], entry)
    content.add_child(_button("Back to pause menu", Callable(self, "_open_overview_page")))
    content.add_child(_button("Resume game  (%s)" % key_name("pause"), Callable(self, "_resume")))
    scroll.grab_focus()


## Skills page (Wave 2F): banked points, slot bindings, then every skill with
## its rank; banked points are spent here exactly as on the level-up overlay.
func _open_skills_page() -> void:
    if mode == "pause":
        page = "skills"
        _refresh()


func _skills_content(content: VBoxContainer) -> void:
    var view: Dictionary = skill_view()
    var points: int = skill_points()
    content.add_child(_text("SKILLS   %d point%s banked" % [points, "" if points == 1 else "s"], 25,
        Color("#f6d48d")))
    var parts: PackedStringArray = []
    for entry in view.get("slots", []):
        parts.append("[%s] %s" % [String(entry.get("key", "?")),
            String(entry["name"]) if String(entry.get("id", "")) != "" else "empty"])
    content.add_child(_text("Active slots:  " + "    ".join(parts) if not parts.is_empty()
        else "Active slots: none", 14, Color("#c5dee4")))
    var first: Button = _skill_list(content, 262.0, true)
    var back := _button("Back to pause menu", Callable(self, "_open_overview_page"))
    content.add_child(back)
    content.add_child(_button("Resume game  (%s)" % key_name("pause"), Callable(self, "_resume")))
    if first != null:
        first.grab_focus()
    else:
        back.grab_focus()


func _inventory_row(rows: VBoxContainer, heading: String, entry: Dictionary) -> void:
    rows.add_child(_text(heading, 15, entry.get("color", Color.WHITE)))
    if String(entry.get("description", "")) != "":
        var detail := _text(String(entry["description"]), 12, Color("#8ea3b3"))
        detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        detail.custom_minimum_size.x = 510
        rows.add_child(detail)


func _button(label: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size.y = roundf(31.0 * Accessibility.text_scale())
    button.add_theme_font_size_override("font_size", Accessibility.px(14))
    button.pressed.connect(callback)
    return button


func _text(value: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", Accessibility.px(font_size))
    label.add_theme_color_override("font_color", color)
    if Accessibility.high_contrast():
        label.add_theme_constant_override("outline_size", Accessibility.OUTLINE)
        label.add_theme_color_override("font_outline_color", Accessibility.OUTLINE_COLOR)
    return label
