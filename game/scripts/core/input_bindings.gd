extends RefCounted
## Input Map bindings (Wave 3C, COMBAT_AND_RPG §2 / D-02): the remappable
## gameplay actions, compact event strings for user://settings.cfg, rebinding
## with conflict detection, defaults from project.godot, the last-used input
## device and the button / key names the hint lines show.
##
## Pure static helpers over the global InputMap: no nodes and no autoloads,
## so tests, the HUD and every menu may preload it. Game applies the saved
## overrides at boot (before the title screen) with apply_overrides(), the
## controls screen (ui/controls_screen.gd) rebinds through rebind(), and
## Settings persists overrides() under the [input] section.
##
## Event strings:
##   key:<physical_keycode>   keyboard key by physical position (rebinding stores these)
##   keycode:<keycode>        keyboard key by label (project defaults for Esc / R / N / F9)
##   mouse:<button_index>     mouse button (1 left, 2 right, 3 middle, 8 / 9 side)
##   joy_button:<index>       gamepad button (SDL layout: 0 A, 1 B, 2 X, 3 Y ...)
##   joy_axis:<axis>:+ / -    gamepad axis direction (0/1 left stick, 2/3 right, 4 LT, 5 RT)

## Gameplay actions shown on the controls screen, in order: [action, label].
const ACTIONS := [
    ["move_up", "Move up"], ["move_down", "Move down"], ["move_left", "Move left"],
    ["move_right", "Move right"], ["aim_up", "Aim up"], ["aim_down", "Aim down"],
    ["aim_left", "Aim left"], ["aim_right", "Aim right"], ["fire", "Shoot"],
    ["melee", "Melee"], ["dodge", "Dodge"], ["interact", "Interact"],
    ["use_item", "Use active item"], ["use_consumable", "Use belt item"],
    ["next_consumable", "Next belt item"], ["use_skill_1", "Skill slot 1"],
    ["use_skill_2", "Skill slot 2"], ["swap_weapon", "Swap weapon"], ["map", "Floor map"],
    ["toggle_log", "System log"], ["pause", "Pause / back"],
]
## Developer actions: bound in project.godot, never listed or remapped, but
## their keys stay reserved (rebinding onto them is refused).
const HIDDEN_ACTIONS := ["restart_seed", "new_seed", "debug_level_up"]
## Bindings that can never be removed: pause keeps Esc and Start whatever the
## player adds to it.
const LOCKED := {"pause": ["keycode:4194305", "joy_button:6"]}
## The keyboard / mouse column of these actions is the mouse pointer itself.
const MOUSE_AIM_ACTIONS := ["aim_up", "aim_down", "aim_left", "aim_right"]
const COLUMNS := ["kbm", "pad"]
## Device names (Events.input_device_changed).
const KEYBOARD := "keyboard"
const GAMEPAD := "gamepad"
## A stick or trigger counts as gamepad use (and as a captured axis) past this.
const AXIS_ACTIVE := 0.5
const AXIS_CAPTURE := 0.6
## Mouse motion shorter than this (px) does not switch the device back.
const MOUSE_SWITCH_PX := 2.0

const JOY_BUTTON_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start",
    7: "L3", 8: "R3", 9: "LB", 10: "RB", 11: "D-pad up", 12: "D-pad down", 13: "D-pad left",
    14: "D-pad right", 15: "Share", 16: "Paddle 1", 17: "Paddle 2", 18: "Paddle 3",
    19: "Paddle 4", 20: "Touchpad"}
const JOY_AXIS_NAMES := {"0:-": "L-stick left", "0:+": "L-stick right", "1:-": "L-stick up",
    "1:+": "L-stick down", "2:-": "R-stick left", "2:+": "R-stick right", "3:-": "R-stick up",
    "3:+": "R-stick down", "4:+": "LT", "5:+": "RT", "4:-": "LT (inverted)",
    "5:-": "RT (inverted)"}
const MOUSE_NAMES := {1: "LMB", 2: "RMB", 3: "MMB", 8: "Mouse 4", 9: "Mouse 5"}
const KEY_SHORT := {"Escape": "Esc", "Space": "Space", "Shift": "Shift", "Tab": "Tab",
    "Up": "Up", "Down": "Down", "Left": "Left", "Right": "Right", "Enter": "Enter"}

## Last device the player used ("keyboard" or "gamepad"). Game updates it
## from every input event and emits Events.input_device_changed.
static var device := KEYBOARD


# --- Actions ---------------------------------------------------------------------

static func action_ids() -> Array:
    var ids: Array = []
    for entry in ACTIONS:
        ids.append(String(entry[0]))
    return ids


static func action_label(action: String) -> String:
    for entry in ACTIONS:
        if String(entry[0]) == action:
            return String(entry[1])
    return action.capitalize()


## True when the player may change `column` ("kbm" / "pad") of `action`.
static func is_remappable(action: String, column: String) -> bool:
    if not action_ids().has(action) or not COLUMNS.has(column):
        return false
    return not (column == "kbm" and MOUSE_AIM_ACTIONS.has(action))


# --- Event strings ------------------------------------------------------------------

## Compact string for `event` ("" for an event that cannot be bound).
static func event_to_string(event: InputEvent) -> String:
    if event is InputEventKey:
        var key := event as InputEventKey
        if key.physical_keycode != 0:
            return "key:%d" % int(key.physical_keycode)
        if key.keycode != 0:
            return "keycode:%d" % int(key.keycode)
        return ""
    if event is InputEventMouseButton:
        return "mouse:%d" % int((event as InputEventMouseButton).button_index)
    if event is InputEventJoypadButton:
        return "joy_button:%d" % int((event as InputEventJoypadButton).button_index)
    if event is InputEventJoypadMotion:
        var motion := event as InputEventJoypadMotion
        if is_zero_approx(motion.axis_value):
            return ""
        return "joy_axis:%d:%s" % [int(motion.axis), "+" if motion.axis_value > 0.0 else "-"]
    return ""


## The event for `text` (any device, unpressed), or null when malformed.
static func string_to_event(text: String) -> InputEvent:
    var parts: PackedStringArray = text.strip_edges().split(":")
    if parts.size() < 2 or not parts[1].is_valid_int() or int(parts[1]) < 0:
        return null
    var value: int = int(parts[1])
    match parts[0]:
        "key", "keycode":
            if parts.size() != 2 or value == 0:
                return null
            var key := InputEventKey.new()
            if parts[0] == "key":
                key.physical_keycode = value as Key
            else:
                key.keycode = value as Key
            key.device = -1
            return key
        "mouse":
            if parts.size() != 2 or value < 1 or value > 9:
                return null
            var mouse := InputEventMouseButton.new()
            mouse.button_index = value as MouseButton
            mouse.device = -1
            return mouse
        "joy_button":
            if parts.size() != 2 or value >= 128:
                return null
            var button := InputEventJoypadButton.new()
            button.button_index = value as JoyButton
            button.device = -1
            return button
        "joy_axis":
            if parts.size() != 3 or value >= 10 or not (parts[2] == "+" or parts[2] == "-"):
                return null
            var motion := InputEventJoypadMotion.new()
            motion.axis = value as JoyAxis
            motion.axis_value = 1.0 if parts[2] == "+" else -1.0
            motion.device = -1
            return motion
    return null


## Identity used for conflicts: a key counts once whether it is bound by
## physical position or by label (the inventory_test collision rule).
static func identity(text: String) -> String:
    if text.begins_with("keycode:"):
        return "key:" + text.substr(8)
    return text


## "kbm" for keys and mouse buttons, "pad" for gamepad buttons and axes.
static func column_of(text: String) -> String:
    if text.begins_with("key") or text.begins_with("mouse:"):
        return "kbm"
    if text.begins_with("joy_"):
        return "pad"
    return ""


# --- Reading the Input Map --------------------------------------------------------------

## Every bound event of `action`, as strings, in Input Map order.
static func current_strings(action: String) -> PackedStringArray:
    var result: PackedStringArray = []
    if not InputMap.has_action(action):
        return result
    for event in InputMap.action_get_events(action):
        var text: String = event_to_string(event)
        if text != "":
            result.append(text)
    return result


## The bindings of `action` that belong to `column`.
static func column_strings(action: String, column: String) -> PackedStringArray:
    var result: PackedStringArray = []
    for text in current_strings(action):
        if column_of(text) == column:
            result.append(text)
    return result


## project.godot's events for `action`, as strings.
static func default_strings(action: String) -> PackedStringArray:
    var result: PackedStringArray = []
    var setting = ProjectSettings.get_setting("input/" + action)
    if not setting is Dictionary:
        return result
    for event in setting.get("events", []):
        if event is InputEvent:
            var text: String = event_to_string(event)
            if text != "":
                result.append(text)
    return result


## The non-ui action already bound to input `text` (by identity), other than
## `except_action`; "" when free.
static func find_owner(text: String, except_action: String = "") -> String:
    var wanted: String = identity(text)
    for action in InputMap.get_actions():
        var name: String = String(action)
        if name.begins_with("ui_") or name == except_action:
            continue
        for bound in current_strings(name):
            if identity(bound) == wanted:
                return name
    return ""


## Every input bound to two gameplay (non-ui) actions: ["text: a, b", ...].
## Empty means the inventory_test collision rule holds (axes included here).
static func conflicts() -> Array:
    var owners: Dictionary = {}
    var problems: Array = []
    for action in InputMap.get_actions():
        var name: String = String(action)
        if name.begins_with("ui_"):
            continue
        for bound in current_strings(name):
            var id: String = identity(bound)
            if owners.has(id) and String(owners[id]) != name:
                problems.append("%s: %s, %s" % [id, owners[id], name])
            owners[id] = name
    return problems


# --- Changing the Input Map ------------------------------------------------------------

## Replaces every event of `action` with `strings` (invalid entries skipped);
## LOCKED events are always kept.
static func set_strings(action: String, strings: PackedStringArray) -> void:
    if not InputMap.has_action(action):
        return
    var wanted: PackedStringArray = []
    for text in LOCKED.get(action, []):
        wanted.append(String(text))
    for text in strings:
        if not wanted.has(text) and string_to_event(text) != null:
            wanted.append(text)
    InputMap.action_erase_events(action)
    for text in _ordered(wanted):
        InputMap.action_add_event(action, string_to_event(text))


## Keyboard / mouse first, then gamepad (stable within each column).
static func _ordered(strings: PackedStringArray) -> PackedStringArray:
    var result: PackedStringArray = []
    for column in COLUMNS:
        for text in strings:
            if column_of(text) == column:
                result.append(text)
    return result


## Binds input `text` as the primary `column` binding of `action`.
## A conflict with another gameplay action is refused (`mode` "refuse") or
## swapped (`mode` "swap", the default): when the input is the other action's
## primary in that column it takes this action's old primary, otherwise it is
## just removed there. Inputs of the hidden developer actions and the locked
## Esc / Start of pause are always refused.
## Returns {ok: bool, reason: String, swapped_with: String}; reasons:
## "locked", "invalid", "wrong_column", "reserved", "conflict", "unchanged".
static func rebind(action: String, column: String, text: String, mode: String = "swap") -> Dictionary:
    var result := {"ok": false, "reason": "", "swapped_with": ""}
    if not is_remappable(action, column) or not InputMap.has_action(action):
        result["reason"] = "locked"
        return result
    if string_to_event(text) == null:
        result["reason"] = "invalid"
        return result
    if column_of(text) != column:
        result["reason"] = "wrong_column"
        return result
    var wanted: String = identity(text)
    var own: PackedStringArray = _free_strings(action, column)
    if not own.is_empty() and identity(own[0]) == wanted:
        result["ok"] = true
        result["reason"] = "unchanged"
        return result
    for locked_text in LOCKED.get(action, []):
        if identity(String(locked_text)) == wanted:
            result["ok"] = true
            result["reason"] = "unchanged"
            return result
    var owner: String = find_owner(text, action)
    if owner != "":
        if HIDDEN_ACTIONS.has(owner) or not action_ids().has(owner) or _is_locked(owner, wanted):
            result["reason"] = "reserved"
            return result
        if mode != "swap":
            result["reason"] = "conflict"
            return result
    var old_primary: String = own[0] if not own.is_empty() else ""
    if owner != "":
        var theirs: PackedStringArray = _free_strings(owner, column)
        var index: int = -1
        for i in range(theirs.size()):
            if identity(theirs[i]) == wanted:
                index = i
        if index == 0 and old_primary != "" and find_owner(old_primary, action) in ["", owner]:
            theirs[0] = old_primary
        elif index >= 0:
            theirs.remove_at(index)
        _set_column(owner, column, theirs)
        result["swapped_with"] = owner
    var mine: PackedStringArray = [text]
    for i in range(1, own.size()):
        if identity(own[i]) != wanted:
            mine.append(own[i])
    _set_column(action, column, mine)
    result["ok"] = true
    return result


## Bindings of `action` in `column` that the player controls (LOCKED excluded).
static func _free_strings(action: String, column: String) -> PackedStringArray:
    var result: PackedStringArray = []
    var locked: Array = LOCKED.get(action, [])
    for text in column_strings(action, column):
        if not locked.has(text):
            result.append(text)
    return result


static func _is_locked(action: String, wanted_identity: String) -> bool:
    for text in LOCKED.get(action, []):
        if identity(String(text)) == wanted_identity:
            return true
    return false


static func _set_column(action: String, column: String, strings: PackedStringArray) -> void:
    var other: String = "pad" if column == "kbm" else "kbm"
    var merged: PackedStringArray = column_strings(action, other)
    merged.append_array(strings)
    set_strings(action, merged)


## Restores project.godot's bindings for every listed action.
static func reset_defaults() -> void:
    for action in action_ids():
        set_strings(action, default_strings(action))


## {action: PackedStringArray} for every listed action whose bindings differ
## from project.godot (what Settings saves under [input]).
static func overrides() -> Dictionary:
    var result: Dictionary = {}
    for action in action_ids():
        var now: PackedStringArray = current_strings(action)
        if _ordered(now) != _ordered(default_strings(action)):
            result[action] = now
    return result


## Applies saved overrides on top of the defaults. Unknown actions and
## malformed strings are ignored; if the result would bind one input to two
## gameplay actions, every listed action falls back to its defaults. Returns
## true when the overrides were applied as saved.
static func apply_overrides(saved: Dictionary) -> bool:
    reset_defaults()
    for action in saved.keys():
        var name: String = String(action)
        if not action_ids().has(name):
            continue
        var strings: PackedStringArray = []
        for text in saved[action]:
            if string_to_event(String(text)) != null:
                strings.append(String(text))
        if MOUSE_AIM_ACTIONS.has(name):
            # The mouse column stays the pointer: keep only gamepad entries.
            var pad_only: PackedStringArray = []
            for text in strings:
                if column_of(text) == "pad":
                    pad_only.append(text)
            strings = pad_only
        set_strings(name, strings)
    if not conflicts().is_empty():
        push_warning("Saved input bindings conflict; restoring defaults")
        reset_defaults()
        return false
    return true


# --- Device and names ----------------------------------------------------------------

## "gamepad", "keyboard", or "" when `event` says nothing about the device
## (small mouse jitter, a stick resting near centre, releases).
static func classify(event: InputEvent) -> String:
    if event is InputEventJoypadButton:
        return GAMEPAD if (event as InputEventJoypadButton).pressed else ""
    if event is InputEventJoypadMotion:
        return GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) >= AXIS_ACTIVE else ""
    if event is InputEventKey:
        return KEYBOARD if (event as InputEventKey).pressed else ""
    if event is InputEventMouseButton:
        return KEYBOARD if (event as InputEventMouseButton).pressed else ""
    if event is InputEventMouseMotion:
        return KEYBOARD if (event as InputEventMouseMotion).relative.length() >= MOUSE_SWITCH_PX else ""
    return ""


## Short name for one event string: "Space", "LMB", "RB", "LT", "D-pad down".
static func label(text: String) -> String:
    var parts: PackedStringArray = text.split(":")
    if parts.size() < 2:
        return "?"
    match parts[0]:
        "key", "keycode":
            var name: String = OS.get_keycode_string(int(parts[1]) as Key)
            return String(KEY_SHORT.get(name, name)) if name != "" else "Key %s" % parts[1]
        "mouse":
            return String(MOUSE_NAMES.get(int(parts[1]), "Mouse %s" % parts[1]))
        "joy_button":
            return String(JOY_BUTTON_NAMES.get(int(parts[1]), "Button %s" % parts[1]))
        "joy_axis":
            var key: String = "%s:%s" % [parts[1], parts[2] if parts.size() > 2 else "+"]
            return String(JOY_AXIS_NAMES.get(key, "Axis %s" % key))
    return "?"


## Every binding of `action` in `column`, joined: "W / Up", "LT". Mouse-aim
## actions show "Mouse" in the keyboard column; "—" when unbound.
static func column_label(action: String, column: String) -> String:
    if column == "kbm" and MOUSE_AIM_ACTIONS.has(action):
        return "Mouse"
    var names: PackedStringArray = []
    for text in column_strings(action, column):
        names.append(label(text))
    return " / ".join(names) if not names.is_empty() else "—"


## The primary binding of `action` for `for_device` (the current device by
## default), for hint lines: "Space" / "RB". "—" when unbound.
static func hint(action: String, for_device: String = "") -> String:
    var which: String = device if for_device == "" else for_device
    var column: String = "pad" if which == GAMEPAD else "kbm"
    if column == "kbm" and MOUSE_AIM_ACTIONS.has(action):
        return "Mouse"
    var strings: PackedStringArray = column_strings(action, column)
    if strings.is_empty():
        return "—"
    # pause: the player's own binding is listed after the locked Esc / Start.
    return label(strings[0])


## Movement hint: "WASD" for single-letter keys, "L-stick" for the default
## stick, otherwise the four bindings joined with "/".
static func move_hint(for_device: String = "") -> String:
    var names: PackedStringArray = []
    for action in ["move_up", "move_left", "move_down", "move_right"]:
        names.append(hint(action, for_device))
    if names[0].begins_with("L-stick") and names[1].begins_with("L-stick") \
            and names[2].begins_with("L-stick") and names[3].begins_with("L-stick"):
        return "L-stick"
    var short := true
    for name in names:
        short = short and name.length() == 1
    return "".join(names) if short else "/".join(names)


## Aim hint: "Mouse" on keyboard, "R-stick" (or the bound axes) on gamepad.
static func aim_hint(for_device: String = "") -> String:
    var which: String = device if for_device == "" else for_device
    if which != GAMEPAD:
        return "Mouse"
    var names: PackedStringArray = []
    for action in ["aim_up", "aim_left", "aim_down", "aim_right"]:
        names.append(hint(action, GAMEPAD))
    for name in names:
        if not name.begins_with("R-stick"):
            return "/".join(names)
    return "R-stick"


static func is_gamepad() -> bool:
    return device == GAMEPAD
