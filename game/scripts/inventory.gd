extends RefCounted
## The crawler's inventory (COMBAT_AND_RPG §12, D-09): one melee weapon, one
## ranged weapon, one active item, unlimited passives and a belt of
## consumable stack slots, plus credits. Static functions over
## `RunState.inventory`; every change is announced on `Events`
## (item_picked_up, item_used, item_dropped, inventory_changed,
## credits_changed).
##
## RunState.inventory shape (fields are filled by data() when missing):
##   melee, ranged, active: String content id ("" = empty)
##   active_state: {charges, max_charges, progress, cooldown, unit} for `active`
##       (progress counts up in `unit`: seconds, rooms_cleared or floors)
##   passives: Array of {id, count} (count <= the item's stack_max)
##   consumables: Array of {id, count}, at most items.consumable_slots (6)
##   selected: int, the belt slot use_consumable uses
##   credits: int
##   effect_cooldowns: {"<source>:<effect_id>": ready_time} internal cooldowns
##
## Swap rule: a weapon or active picked up into an occupied slot replaces it
## and the old record drops as a pickup at `drop_at` (pickups.gd). A full belt
## or a passive at stack_max refuses the pickup (reason "belt_full" /
## "max_stack"); swap_consumable() swaps the selected belt slot instead.
##
## Autoloads are looked up at runtime (Engine main loop), never by name at
## compile time, so tests may preload this module.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Pickups = preload("res://scripts/pickups.gd")

const WEAPON_SLOTS := ["melee", "ranged"]
const DEFAULT_LOADOUT := ["wpn_crowbar", "wpn_nail_pistol"]
const DEFAULT_BELT := 6
const RARITY_COLORS := {"common": Color("#d4d4d4"), "uncommon": Color("#6fd36f"),
    "rare": Color("#5aa8ff"), "epic": Color("#c77dff"), "legendary": Color("#ffb347")}


static func empty() -> Dictionary:
    return {"melee": "", "ranged": "", "active": "", "active_state": {}, "passives": [],
        "consumables": [], "selected": 0, "credits": 0, "effect_cooldowns": {}}


static func autoload(node_name: String) -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root.get_node_or_null(node_name) if tree != null else null


static func run_state() -> Node:
    return autoload("RunState")


static func emit(signal_name: String, args: Array = []) -> void:
    var events: Node = autoload("Events")
    if events != null:
        events.callv("emit_signal", [signal_name] + args)


static func config() -> Dictionary:
    var rs: Node = run_state()
    return rs.config if rs != null else {}


static func belt_size() -> int:
    return maxi(1, int(config().get("items", {}).get("consumable_slots", DEFAULT_BELT)))


static func starting_loadout() -> Array:
    var ids = config().get("run", {}).get("starting_loadout", DEFAULT_LOADOUT)
    return ids if ids is Array and not ids.is_empty() else DEFAULT_LOADOUT


## RunState.inventory with every field present (the same dictionary, so edits stick).
static func data() -> Dictionary:
    var rs: Node = run_state()
    var inv: Dictionary = rs.inventory
    var defaults: Dictionary = empty()
    for key in defaults.keys():
        if not inv.has(key):
            inv[key] = defaults[key]
    return inv


## Replaces the inventory with `loadout` (default run.starting_loadout) and the
## starting credits. Emits inventory_changed only (a loadout is not a pickup).
static func reset(loadout: Array = []) -> Dictionary:
    var rs: Node = run_state()
    var inv: Dictionary = empty()
    inv["credits"] = int(config().get("credits", {}).get("start", 0))
    rs.inventory = inv
    for id in (loadout if not loadout.is_empty() else starting_loadout()):
        _store(inv, String(id), 1, {})
    emit("inventory_changed")
    return inv


## The equipped weapon id for `slot`, or the starting weapon of that slot when
## the inventory is empty (the crawler is never unarmed).
static func weapon_id(slot: String) -> String:
    var id: String = String(run_state().inventory.get(slot, ""))
    if id != "":
        return id
    for starter in starting_loadout():
        if String(ContentDB.weapon(String(starter)).get("slot", "")) == slot:
            return String(starter)
    return ""


static func kind_of(id: String) -> String:
    if id.begins_with("wpn_"):
        return "weapon"
    return String(ContentDB.item(id).get("kind", ""))


## True when picking `id` up must go through `interact` (it may swap).
static func needs_interact(id: String) -> bool:
    var kind: String = kind_of(id)
    return kind == "weapon" or kind == "active"


static func passive_count(id: String) -> int:
    for entry in data()["passives"]:
        if String(entry["id"]) == id:
            return int(entry["count"])
    return 0


static func consumable_count(id: String) -> int:
    var total := 0
    for entry in data()["consumables"]:
        if String(entry["id"]) == id:
            total += int(entry["count"])
    return total


## Whether `id` x `count` could be added now without a swap:
## {ok, reason ("" | "max_stack" | "belt_full" | "already_equipped" | "unknown"), fits}.
static func can_accept(id: String, count: int = 1) -> Dictionary:
    var inv: Dictionary = data()
    var record: Dictionary = ContentDB.record(id)
    if record.is_empty():
        return {"ok": false, "reason": "unknown", "fits": 0}
    match kind_of(id):
        "weapon":
            if String(inv.get(String(record["slot"]), "")) == id:
                return {"ok": false, "reason": "already_equipped", "fits": 0}
            return {"ok": true, "reason": "", "fits": 1}
        "active":
            if String(inv["active"]) == id:
                return {"ok": false, "reason": "already_equipped", "fits": 0}
            return {"ok": true, "reason": "", "fits": 1}
        "passive":
            var room: int = maxi(1, int(record.get("stack_max", 1))) - passive_count(id)
            if room <= 0:
                return {"ok": false, "reason": "max_stack", "fits": 0}
            return {"ok": true, "reason": "", "fits": mini(room, count)}
        "consumable":
            var stack: int = maxi(1, int(record.get("stack_max", 1)))
            var fits := 0
            for entry in inv["consumables"]:
                if String(entry["id"]) == id:
                    fits += maxi(0, stack - int(entry["count"]))
            fits += (belt_size() - inv["consumables"].size()) * stack
            if fits <= 0:
                return {"ok": false, "reason": "belt_full", "fits": 0}
            return {"ok": true, "reason": "", "fits": mini(fits, count)}
    return {"ok": false, "reason": "unknown", "fits": 0}


## Adds `count` copies of `id`. Weapons and actives swap: the old one drops as a
## pickup at `drop_at` in the current room (an active keeps its charge state).
## `state` restores a dropped active's active_state. Returns {ok, reason,
## taken (copies added), dropped (id or "")}. Emits item_picked_up once per
## call that took something, then inventory_changed.
static func acquire(id: String, drop_at: Vector2 = Vector2.INF, count: int = 1,
        state: Dictionary = {}) -> Dictionary:
    var check: Dictionary = can_accept(id, count)
    if not bool(check["ok"]):
        return {"ok": false, "reason": check["reason"], "taken": 0, "dropped": ""}
    var inv: Dictionary = data()
    var result: Dictionary = _store(inv, id, int(check["fits"]), state)
    var dropped: String = String(result["dropped"])
    if dropped != "" and drop_at != Vector2.INF:
        var rs: Node = run_state()
        Pickups.spawn(dropped, drop_at, rs.current_room_id,
            {"state": result.get("dropped_state", {})})
    emit("item_picked_up", [id])
    emit("inventory_changed")
    return {"ok": true, "reason": "", "taken": int(check["fits"]), "dropped": dropped}


## Full-belt swap: the selected slot's stack drops at `drop_at` and `id`
## (x count, capped at stack_max) takes the slot. Returns acquire()'s shape.
static func swap_consumable(id: String, drop_at: Vector2, count: int = 1) -> Dictionary:
    var inv: Dictionary = data()
    if kind_of(id) != "consumable" or inv["consumables"].is_empty():
        return acquire(id, drop_at, count)
    var index: int = clampi(int(inv["selected"]), 0, inv["consumables"].size() - 1)
    var old: Dictionary = inv["consumables"][index]
    var stack: int = maxi(1, int(ContentDB.item(id).get("stack_max", 1)))
    var taken: int = mini(count, stack)
    inv["consumables"][index] = {"id": id, "count": taken}
    var rs: Node = run_state()
    Pickups.spawn(String(old["id"]), drop_at, rs.current_room_id, {"count": int(old["count"])})
    emit("item_picked_up", [id])
    emit("inventory_changed")
    return {"ok": true, "reason": "", "taken": taken, "dropped": String(old["id"])}


static func _store(inv: Dictionary, id: String, count: int, state: Dictionary) -> Dictionary:
    var record: Dictionary = ContentDB.record(id)
    var result := {"dropped": "", "dropped_state": {}}
    match kind_of(id):
        "weapon":
            var slot: String = String(record.get("slot", "melee"))
            result["dropped"] = String(inv.get(slot, ""))
            inv[slot] = id
        "active":
            result["dropped"] = String(inv["active"])
            result["dropped_state"] = Dictionary(inv["active_state"]).duplicate(true)
            inv["active"] = id
            inv["active_state"] = state.duplicate(true) if not state.is_empty() \
                else fresh_active_state(record)
        "passive":
            for entry in inv["passives"]:
                if String(entry["id"]) == id:
                    entry["count"] = int(entry["count"]) + count
                    return result
            inv["passives"].append({"id": id, "count": count})
        "consumable":
            var stack: int = maxi(1, int(record.get("stack_max", 1)))
            var left: int = count
            for entry in inv["consumables"]:
                if left <= 0:
                    break
                if String(entry["id"]) == id and int(entry["count"]) < stack:
                    var add: int = mini(left, stack - int(entry["count"]))
                    entry["count"] = int(entry["count"]) + add
                    left -= add
            while left > 0 and inv["consumables"].size() < belt_size():
                var add: int = mini(left, stack)
                inv["consumables"].append({"id": id, "count": add})
                left -= add
    return result


static func fresh_active_state(record: Dictionary) -> Dictionary:
    var charges: int = maxi(1, int(record.get("charges", 1)))
    return {"charges": charges, "max_charges": charges, "progress": 0.0,
        "cooldown": maxf(0.0, float(record.get("cooldown", 0.0))),
        "unit": String(record.get("cooldown_unit", "seconds"))}


# --- Using items ----------------------------------------------------------------

## True when the active item has a charge.
static func active_ready() -> bool:
    var inv: Dictionary = data()
    return String(inv["active"]) != "" and int(inv["active_state"].get("charges", 0)) > 0


## Spends one active charge (the caller ran the on_use effects). Emits
## item_used and inventory_changed. Returns the active id, or "" if not ready.
static func spend_active() -> String:
    if not active_ready():
        return ""
    var inv: Dictionary = data()
    var id: String = String(inv["active"])
    inv["active_state"]["charges"] = int(inv["active_state"]["charges"]) - 1
    emit("item_used", [id])
    emit("inventory_changed")
    return id


## Advances the active's recharge by `amount` in `unit` ("seconds",
## "rooms_cleared", "floors"); a full recharge restores every charge.
## Returns true when the item became ready. inventory_changed is emitted only
## when charges change (not for every second of progress).
static func advance_active(unit: String, amount: float) -> bool:
    var inv: Dictionary = data()
    var state: Dictionary = inv["active_state"]
    if String(inv["active"]) == "" or state.is_empty() or String(state.get("unit", "")) != unit:
        return false
    if int(state["charges"]) >= int(state["max_charges"]):
        state["progress"] = 0.0
        return false
    state["progress"] = float(state["progress"]) + amount
    if float(state["progress"]) + 0.000001 >= float(state["cooldown"]):
        state["charges"] = int(state["max_charges"])
        state["progress"] = 0.0
        emit("inventory_changed")
        return true
    return false


## 0..1 recharge progress of the active (1 = at least one charge ready).
static func active_fraction() -> float:
    var inv: Dictionary = data()
    var state: Dictionary = inv["active_state"]
    if String(inv["active"]) == "" or state.is_empty():
        return 0.0
    if int(state.get("charges", 0)) > 0:
        return 1.0
    return clampf(float(state["progress"]) / maxf(0.0001, float(state["cooldown"])), 0.0, 1.0)


## Takes seconds off a seconds-based active recharge (cooldown_reduction "items").
static func reduce_active_cooldown(seconds: float) -> void:
    advance_active("seconds", seconds)


## Id in belt slot `index` (default: the selected slot), or "".
static func consumable_at(index: int = -1) -> String:
    var inv: Dictionary = data()
    var slot: int = int(inv["selected"]) if index < 0 else index
    if slot < 0 or slot >= inv["consumables"].size():
        return ""
    return String(inv["consumables"][slot]["id"])


## Uses one from belt slot `index` (default: selected; the caller ran the
## effects). An emptied slot is removed. Emits item_used and inventory_changed.
static func spend_consumable(index: int = -1) -> String:
    var inv: Dictionary = data()
    var slot: int = int(inv["selected"]) if index < 0 else index
    if slot < 0 or slot >= inv["consumables"].size():
        return ""
    var entry: Dictionary = inv["consumables"][slot]
    var id: String = String(entry["id"])
    entry["count"] = int(entry["count"]) - 1
    if int(entry["count"]) <= 0:
        inv["consumables"].remove_at(slot)
        inv["selected"] = clampi(int(inv["selected"]), 0, maxi(0, inv["consumables"].size() - 1))
    emit("item_used", [id])
    emit("inventory_changed")
    return id


## Selects the next occupied belt slot (wraps). Returns the new index.
static func select_next_consumable() -> int:
    var inv: Dictionary = data()
    var size: int = inv["consumables"].size()
    inv["selected"] = 0 if size == 0 else posmod(int(inv["selected"]) + 1, size)
    emit("inventory_changed")
    return int(inv["selected"])


# --- Credits --------------------------------------------------------------------

static func credits() -> int:
    return int(data()["credits"])


## Adds (or with a negative value removes, never below 0) credits.
static func add_credits(amount: int) -> int:
    var inv: Dictionary = data()
    var before: int = int(inv["credits"])
    inv["credits"] = maxi(0, before + amount)
    var change: int = int(inv["credits"]) - before
    if change != 0:
        emit("credits_changed", [change, int(inv["credits"])])
    return change


## Spends `amount` if affordable. Returns false (and changes nothing) otherwise.
static func spend_credits(amount: int) -> bool:
    if amount < 0 or credits() < amount:
        return false
    add_credits(-amount)
    return true


# --- Views ----------------------------------------------------------------------

static func label(id: String) -> Dictionary:
    var record: Dictionary = ContentDB.record(id)
    var rarity: String = String(record.get("rarity", "common"))
    return {"id": id, "name": String(record.get("name", id)), "rarity": rarity,
        "kind": kind_of(id), "description": String(record.get("description", "")),
        "color": RARITY_COLORS.get(rarity, Color.WHITE)}


## Plain view model for the HUD and the pause-menu inventory page.
static func describe() -> Dictionary:
    var inv: Dictionary = data()
    var view: Dictionary = {"credits": int(inv["credits"]), "selected": int(inv["selected"]),
        "belt_size": belt_size(), "passives": [], "consumables": []}
    for slot in WEAPON_SLOTS:
        view[slot] = label(weapon_id(slot))
    view["active"] = {}
    if String(inv["active"]) != "":
        var active: Dictionary = label(String(inv["active"]))
        var state: Dictionary = inv["active_state"]
        active.merge({"charges": int(state.get("charges", 0)),
            "max_charges": int(state.get("max_charges", 1)), "fraction": active_fraction(),
            "progress": float(state.get("progress", 0.0)),
            "cooldown": float(state.get("cooldown", 0.0)),
            "unit": String(state.get("unit", "seconds"))})
        view["active"] = active
    for entry in inv["passives"]:
        var passive: Dictionary = label(String(entry["id"]))
        passive["count"] = int(entry["count"])
        passive["stack_max"] = int(ContentDB.item(String(entry["id"])).get("stack_max", 1))
        view["passives"].append(passive)
    for entry in inv["consumables"]:
        var consumable: Dictionary = label(String(entry["id"]))
        consumable["count"] = int(entry["count"])
        consumable["stack_max"] = int(ContentDB.item(String(entry["id"])).get("stack_max", 1))
        view["consumables"].append(consumable)
    return view
