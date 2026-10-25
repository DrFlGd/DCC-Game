extends Node
## RoomServices: interactables and trap plates of the current room (Wave 2E).
##
## Child of Game (created by Game._ready). Each frame Game calls update(),
## which arms/fires trap plates and picks the interactable in reach so the HUD
## can show its prompt; the `interact` action calls try_interact().
##
## Interaction registry: behaviour is keyed by the entry `kind`
## (interactables.gd). Built-ins: chest, shrine, rest, shop_sign. Other teams
## add their own without editing this file:
##
##   services.register_interaction("shop", prompt_fn, action_fn)
##   services.add_interactable(room_id, Interactables.make("shop", cell, room_id))
##
## `prompt_fn(entry) -> String` is the HUD text ("" hides the prompt);
## `action_fn(entry) -> void` runs on `interact`. Set entry["used"] = true for
## one-shot features. An action may open a modal with open_choice().
const Interactables = preload("res://scripts/interactables.gd")
const Hazards = preload("res://scripts/hazards.gd")
const Contents = preload("res://scripts/room_contents.gd")
const ContentDB = preload("res://scripts/content/content_db.gd")
const LootRules = preload("res://scripts/content/loot_rules.gd")
const ChoiceDialog = preload("res://scripts/ui/choice_dialog.gd")

## Emitted when a choice modal opens/closes; Game freezes the world in between.
signal modal_opened
signal modal_closed

const CHEST_TABLE := "treasure_room"

var game
## kind -> {prompt: Callable, action: Callable}
var handlers: Dictionary = {}
var dialog: ChoiceDialog
## HUD prompt for the interactable in reach ("" when none).
var prompt := ""
var _choice_callback: Callable = Callable()


func setup(game_node) -> void:
    game = game_node
    if dialog == null:
        dialog = ChoiceDialog.new()
        dialog.name = "ChoiceDialog"
        add_child(dialog)
        dialog.chosen.connect(_on_dialog_chosen)
        dialog.cancelled.connect(_on_dialog_cancelled)
    register_interaction("chest", func(_entry): return "[E] Open the chest", open_chest)
    register_interaction("shrine", func(_entry): return "[E] Approach the shrine", use_shrine)
    register_interaction("rest", func(_entry): return "[E] Rest (full heal, once per floor)",
        rest)
    register_interaction("shop_sign", func(_entry): return "[E] Read the shop sign", read_sign)


## Registers (or replaces) the behaviour of interactable `kind`.
func register_interaction(kind: String, prompt_fn: Callable, action_fn: Callable) -> void:
    handlers[kind] = {"prompt": prompt_fn, "action": action_fn}


## Adds an interactable entry to room `room_id` (persisted with the room).
func add_interactable(room_id: int, entry: Dictionary) -> void:
    if not RunState.room_states.has(room_id):
        return
    var state: Dictionary = RunState.room_states[room_id]
    if not state.has("interactables"):
        state["interactables"] = []
    state["interactables"].append(entry)


func interactables() -> Array:
    return RunState.current_room().get("interactables", [])


func plates() -> Array:
    return RunState.current_room().get("plates", [])


## The registered, available interactable in reach of the crawler, or {}.
func focus() -> Dictionary:
    var usable: Array = []
    for entry in interactables():
        if handlers.has(String(entry["kind"])):
            usable.append(entry)
    return Interactables.nearest(usable, game.player.world_position)


## Per-frame step while RUNNING: trap plates, then the HUD prompt.
func update(delta: float) -> void:
    _update_plates(delta)
    refresh_prompt()


func refresh_prompt() -> void:
    var entry: Dictionary = focus()
    prompt = "" if entry.is_empty() else String(handlers[String(entry["kind"])]["prompt"].call(entry))


## Uses the focused interactable. Returns true if something happened.
func try_interact() -> bool:
    var entry: Dictionary = focus()
    if entry.is_empty():
        return false
    handlers[String(entry["kind"])]["action"].call(entry)
    refresh_prompt()
    return true


## Opens the choice modal. `callback(option_id)` runs on a pick; nothing runs
## on cancel. options: [{id, label}].
func open_choice(title: String, body: String, options: Array, callback: Callable) -> void:
    _choice_callback = callback
    dialog.open(title, body, options)
    modal_opened.emit()


func is_modal_open() -> bool:
    return dialog != null and dialog.is_open()


# --- Built-in interactions -----------------------------------------------------

## Treasure chest: opens once and rolls the treasure_room table
## deterministically from (floor seed, depth, room id, chest salt).
func open_chest(entry: Dictionary) -> void:
    entry["used"] = true
    var db: Dictionary = ContentDB.default_db()
    var room_id: int = int(entry.get("room_id", RunState.current_room_id))
    var loot: Array[String] = LootRules.roll(db, CHEST_TABLE, RunState.floor_seed(),
        RunState.depth, room_id, int(entry.get("salt", 0)))
    entry["loot"] = loot
    var names: PackedStringArray = []
    for id in loot:
        names.append(String(ContentDB.record(id, db).get("name", id)))
    Events.chest_opened.emit(room_id, Array(loot))
    if names.is_empty():
        Events.say("The chest is empty. Someone got here first, or never did.", "progression")
    else:
        Events.say("Chest opened: %s. The sponsors pretend to be impressed." % ", ".join(names),
            "progression")


## Shrine: one-time choice between ticks and healing.
func use_shrine(entry: Dictionary) -> void:
    var rules: Dictionary = RunState.config.get("interaction", {})
    var ticks: int = int(rules.get("shrine_ticks", 2))
    var heal_pct: int = int(round(float(rules.get("shrine_heal_ratio", 0.5)) * 100.0))
    open_choice("SHRINE OF QUESTIONABLE WARRANTY",
        "It hums. A plaque reads: ONE WISH PER CUSTOMER. NO REFUNDS. NO EYE CONTACT.",
        [{"id": "stabilise", "label": "Stabilise (+%d ticks)" % ticks},
            {"id": "mend", "label": "Mend (heal %d %%)" % heal_pct}],
        func(choice: String): apply_shrine(entry, choice))


## Applies a shrine choice ("stabilise" | "mend") to `entry`. Ignored if used.
func apply_shrine(entry: Dictionary, choice: String) -> void:
    if bool(entry.get("used", false)) or not ["stabilise", "mend"].has(choice):
        return
    var rules: Dictionary = RunState.config.get("interaction", {})
    entry["used"] = true
    entry["choice"] = choice
    if choice == "stabilise":
        RunState.add_ticks(int(rules.get("shrine_ticks", 2)), "shrine")
        Events.say("The shrine props up the ceiling. Briefly. Probably.", "collapse")
    else:
        var amount: int = int(ceil(float(RunState.max_hp) * float(rules.get("shrine_heal_ratio", 0.5))))
        var healed: int = RunState.heal_player(amount)
        Events.say("The shrine mends you for %d HP. It wants you to know it noticed." % healed,
            "progression")
    Events.shrine_used.emit(choice)


## Guild rest station: full heal, once per floor (room state resets per floor).
func rest(entry: Dictionary) -> void:
    entry["used"] = true
    var healed: int = RunState.heal_player(RunState.max_hp - RunState.hp)
    Events.guild_rested.emit()
    Events.say("You nap on a guild cot (+%d HP). It smells of other people's victories." % healed,
        "progression")


## Shop placeholder until the items team (2B) ships the guild shop.
func read_sign(_entry: Dictionary) -> void:
    Events.say("SHOP: CLOSED FOR INVENTORY. The inventory is also closed.", "info")


# --- Trap plates ---------------------------------------------------------------

## Arms, rearms and fires the current room's pressure plates. A spike plate
## spawns a telegraphed spike hazard and rearms after `hazards.spike_plate.rearm`
## seconds; a drain plate is one-shot and drains `ticks` if the crawler is
## still on it when the telegraph ends.
func _update_plates(delta: float) -> void:
    var list: Array = plates()
    if list.is_empty():
        return
    var cell: Vector2i = Contents.cell_of(game.player.world_position)
    var hazard_rules: Dictionary = RunState.config.get("hazards", {})
    for plate in list:
        if not bool(plate["armed"]):
            if String(plate["kind"]) == "spike" and float(plate["rearm"]) > 0.0:
                plate["rearm"] = float(plate["rearm"]) - delta
                if float(plate["rearm"]) <= 0.0:
                    plate["armed"] = true
            continue
        if Vector2i(plate["cell"]) != cell:
            continue
        plate["armed"] = false
        var center: Vector2 = Contents.cell_center(plate["cell"])
        if String(plate["kind"]) == "drain":
            var drain: Dictionary = hazard_rules.get("drain_plate", {})
            var ticks: int = int(drain.get("ticks", 1))
            plate["rearm"] = 0.0
            game.combat.spawn_hazard(Hazards.make("drain", center,
                float(drain.get("radius", 9.0)), float(drain.get("telegraph", 0.6)), 0,
                float(drain.get("duration", 0.2)), "hazard:drain_plate",
                {"ticks": ticks, "label": "-%d" % ticks, "color": Color("#c46bff"),
                    "plate": String(plate["id"])}))
        else:
            var spike: Dictionary = hazard_rules.get("spike_plate", {})
            plate["rearm"] = float(spike.get("rearm", 2.0))
            game.combat.spawn_hazard(Hazards.make("spike", center,
                float(spike.get("radius", 9.0)), float(spike.get("telegraph", 0.5)),
                int(spike.get("damage", 3)), float(spike.get("duration", 0.2)),
                "hazard:spike_plate", {"color": Color("#e8e8e8"), "plate": String(plate["id"])}))


func _on_dialog_chosen(option_id: String) -> void:
    var callback: Callable = _choice_callback
    _choice_callback = Callable()
    modal_closed.emit()
    if callback.is_valid():
        callback.call(option_id)


func _on_dialog_cancelled() -> void:
    _choice_callback = Callable()
    modal_closed.emit()
