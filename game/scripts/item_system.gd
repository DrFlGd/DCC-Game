extends Node
## ItemSystem (Wave 2B): runs the content layer during play. Child of Game
## (created by Game._ready, after RoomServices).
##
## - Inventory lifecycle: the starting loadout on run_started (inventory.gd).
## - Passive stats: recomputed when dirty (inventory_changed, stats_changed,
##   status_changed, player_damaged/healed, level_up, skill_learned): RunState
##   stat_modifiers (max HP, AC), the crawler's speed and both attack profiles.
## - Triggers: on_room_enter, on_room_clear, on_level_up and periodic here;
##   on_hit / on_kill / on_damage_taken in Combat's damage pipeline; on_use
##   for the active item (`use_item`) and the selected consumable
##   (`use_consumable`, `next_consumable` cycles the belt).
## - Statuses: StatusSystem.tick_all() every frame; `evasive` keeps the
##   crawler's i-frames up; `stunned` blocks the crawler's actions (Game asks
##   player_can_act()).
## - Loot (pickups.gd): floor_start package, room_normal_clear on room_cleared
##   (gated by items.room_clear_chance_by_depth), chest contents
##   (Events.chest_opened), the boss loot box (boss_defeated; opened with
##   `interact`, rolls boss_kill), credits per kill and per room clear.
## - The guild shop: interaction kind "shop" (RoomServices registry).
## Determinism: loot rolls use LootRules' own seeds (never RunState.rng);
## RunState.rng is only used by effect chance/dice rolls, in trigger order.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const LootRules = preload("res://scripts/content/loot_rules.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Pickups = preload("res://scripts/pickups.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const EffectRunner = preload("res://scripts/effect_runner.gd")
const RPG = preload("res://scripts/rpg_rules.gd")
const ItemCard = preload("res://scripts/ui/item_card.gd")

const FLOOR_START_TABLE := "floor_start"
const ROOM_CLEAR_TABLE := "room_normal_clear"
const BOSS_TABLE := "boss_kill"
const SHOP_TABLE := "guild_hall_shop"
## Where the floor-start package lands: 40 px north of the start-room centre.
const FLOOR_START_SPOT := Vector2(192, 152)

var game
## HUD prompt for the pickup under the crawler ("" when none).
var prompt := ""
## The pickup within items.hover_radius of the crawler ({} when none); the
## HUD draws its tooltip.
var hover: Dictionary = {}
var card: ItemCard
var _dirty := true
var _profiles: Dictionary = {}
var _passive_speed := 105.0
var _periodic: Array = []
var _periodic_timers: Dictionary = {}
var _last_kill_pos := Vector2.INF


func setup(game_node) -> void:
    game = game_node
    for pair in [[Events.run_started, _on_run_started], [Events.floor_started, _on_floor_started],
            [Events.floor_cleared, _on_floor_cleared], [Events.room_entered, _on_room_entered],
            [Events.room_cleared, _on_room_cleared], [Events.enemy_killed, _on_enemy_killed],
            [Events.boss_defeated, _on_boss_defeated], [Events.chest_opened, _on_chest_opened],
            [Events.level_up, _on_level_up], [Events.inventory_changed, mark_dirty],
            [Events.stats_changed, _on_dirty_1], [Events.player_damaged, _on_dirty_2],
            [Events.player_healed, _on_dirty_1], [Events.status_changed, _on_status_changed],
            [Events.skill_learned, _on_dirty_2]]:
        var event: Signal = pair[0]
        if not event.is_connected(pair[1]):
            event.connect(pair[1])
    if game.services != null:
        game.services.register_interaction("shop", shop_prompt, open_shop)
    if card == null:
        card = ItemCard.new()
        card.name = "ItemCard"
        add_child(card)


func mark_dirty() -> void:
    _dirty = true


func _on_dirty_1(_a) -> void:
    _dirty = true


func _on_dirty_2(_a, _b) -> void:
    _dirty = true


func _on_status_changed(target: String, _status_id: String, _active: bool) -> void:
    if target == "player":
        _dirty = true


## Recomputes passive stats, speed, attack profiles and periodic effects.
func recompute() -> void:
    _dirty = false
    if RunState.config.is_empty():
        return
    var passive: Array[Dictionary] = Loadout.passive_modifiers()
    RunState.set_stat_modifiers(passive)
    _passive_speed = float(Resolver.apply_stat_modifiers({"move_speed": float(
        RunState.config.get("player_speed", 105.0))}, passive)["move_speed"])
    for slot in Inventory.WEAPON_SLOTS:
        _profiles[slot] = Loadout.attack_profile(slot)
    _periodic.clear()
    var defs: Dictionary = ContentDB.default_db()["index"]["effects"]
    for entry in Loadout.current():
        for reference in entry.get("effects", []):
            var effect: Dictionary = defs.get(String(reference), {})
            if String(effect.get("trigger", "")) == "periodic":
                var modifier: Dictionary = effect.duplicate(true)
                modifier["effect_id"] = String(reference)
                modifier["source"] = String(entry["id"])
                _periodic.append({"key": "%s:%s" % [entry["id"], reference], "modifier": modifier})


## Cached attack profile of `slot` (Loadout.attack_profile).
func profile(slot: String) -> Dictionary:
    if _dirty or not _profiles.has(slot):
        recompute()
    return _profiles.get(slot, {})


## Seconds between attacks of the equipped weapon in `slot`.
func cooldown(slot: String) -> float:
    return float(profile(slot).get("cooldown", 0.5))


## The crawler's move speed: passives x statuses.
func move_speed() -> float:
    if _dirty:
        recompute()
    return _passive_speed * StatusSystem.speed_multiplier("player")


## False while a status with blocks_actions (stunned) is on the crawler.
func player_can_act() -> bool:
    return not StatusSystem.has_flag("player", "blocks_actions")


## Per-frame step while Game is RUNNING.
func update(delta: float) -> void:
    if _dirty:
        recompute()
    StatusSystem.tick_all(game.combat, delta)
    if RunState.statuses.has("evasive"):
        game.player.dodge_iframes = maxf(game.player.dodge_iframes,
            float(RunState.statuses["evasive"].get("remaining", 0.0)))
    game.player.speed = move_speed()
    Inventory.advance_active("seconds", delta)
    _update_periodic(delta)
    _collect_contact_pickups()
    refresh_prompt()


func _update_periodic(delta: float) -> void:
    if _periodic.is_empty():
        return
    for entry in _periodic:
        var modifier: Dictionary = entry["modifier"]
        var interval: float = maxf(0.1, float(modifier.get("interval", 1.0)))
        var timer: float = float(_periodic_timers.get(entry["key"], 0.0)) + delta
        while timer >= interval:
            timer -= interval
            if Resolver.evaluate_condition(modifier.get("condition", {}),
                    EffectRunner.context(game.combat), RunState.rng):
                EffectRunner.execute(game.combat, [modifier])
        _periodic_timers[entry["key"]] = timer


# --- Pickups --------------------------------------------------------------------

func _items_config() -> Dictionary:
    return RunState.config.get("items", {})


## Takes every contact pickup (passives, consumables) the crawler touches.
func _collect_contact_pickups() -> void:
    if Pickups.current().is_empty():
        return
    var radius: float = float(_items_config().get("pickup_radius", 10.0)) \
        + float(Loadout.player_stats().get("pickup_radius", 0.0))
    for entry in Pickups.current().duplicate():
        var id: String = String(entry["id"])
        if id == Pickups.LOOT_BOX or Inventory.needs_interact(id):
            continue
        if Vector2(entry["pos"]).distance_to(game.player.world_position) > radius:
            continue
        take_pickup(entry)


## Moves a pickup into the inventory (contact or interact). Returns acquire()'s
## result; the pickup is removed when every copy was taken.
func take_pickup(entry: Dictionary) -> Dictionary:
    var id: String = String(entry["id"])
    var result: Dictionary = Inventory.acquire(id, game.player.world_position,
        int(entry.get("count", 1)), entry.get("state", {}))
    if bool(result["ok"]):
        entry["count"] = int(entry.get("count", 1)) - int(result["taken"])
        if int(entry["count"]) <= 0:
            Pickups.remove(entry)
    return result


func refresh_prompt() -> void:
    hover = Pickups.nearest(game.player.world_position,
        float(_items_config().get("hover_radius", 14.0)))
    prompt = pickup_prompt(hover)


## HUD prompt for `entry` ("" for contact pickups that will be taken anyway).
func pickup_prompt(entry: Dictionary) -> String:
    if entry.is_empty():
        return ""
    var id: String = String(entry["id"])
    if id == Pickups.LOOT_BOX:
        return "[E] Open the sponsor loot box"
    var info: Dictionary = Inventory.label(id)
    var inv: Dictionary = Inventory.data()
    match String(info["kind"]):
        "weapon":
            var slot: String = String(ContentDB.weapon(id).get("slot", "melee"))
            if String(inv.get(slot, "")) == id:
                return "%s: already equipped" % info["name"]
            return "[E] Take %s (drops %s)" % [info["name"],
                Inventory.label(Inventory.weapon_id(slot))["name"]]
        "active":
            if String(inv["active"]) == "":
                return "[E] Take %s" % info["name"]
            if String(inv["active"]) == id:
                return "%s: already equipped" % info["name"]
            return "[E] Take %s (drops %s)" % [info["name"], Inventory.label(String(inv["active"]))["name"]]
        "consumable":
            var held: String = Inventory.consumable_at()
            if held != "":
                return "Belt full: [E] swap %s for %s" % [Inventory.label(held)["name"], info["name"]]
        "passive":
            return "%s: already at max stack" % info["name"]
    return ""


## Uses the pickup under the crawler. Returns false when nothing happened, so
## Game can fall back to RoomServices.try_interact().
func try_interact() -> bool:
    if hover.is_empty():
        refresh_prompt()
    if hover.is_empty():
        return false
    var entry: Dictionary = hover
    var id: String = String(entry["id"])
    if id == Pickups.LOOT_BOX:
        open_loot_box(entry)
    elif Inventory.needs_interact(id):
        var result: Dictionary = take_pickup(entry)
        if not bool(result["ok"]):
            return false
        Events.say("Equipped %s." % Inventory.label(id)["name"], "progression")
    elif Inventory.kind_of(id) == "consumable" and Inventory.consumable_at() != "":
        var swap: Dictionary = Inventory.swap_consumable(id, game.player.world_position,
            int(entry.get("count", 1)))
        entry["count"] = int(entry.get("count", 1)) - int(swap["taken"])
        if int(entry["count"]) <= 0:
            Pickups.remove(entry)
    else:
        return false
    refresh_prompt()
    return true


## Opens the boss loot box: rolls boss_kill (one extra roll at CHA mod >= +3,
## COMBAT_AND_RPG §11), places the drops around the crate, emits
## loot_box_opened and asks the announcer for a line.
func open_loot_box(entry: Dictionary) -> Array:
    var db: Dictionary = ContentDB.default_db()
    var room_id: int = int(entry.get("room_id", RunState.current_room_id))
    var table: String = String(entry.get("table", BOSS_TABLE))
    if table == "":
        table = BOSS_TABLE
    var loot: Array = Array(LootRules.roll(db, table, RunState.floor_seed(), RunState.depth, room_id, 0))
    if RPG.modifier(int(RunState.ability_scores.get("CHA", 10))) >= 3:
        for extra in LootRules.roll(db, table, RunState.floor_seed(), RunState.depth, room_id, 1, loot):
            loot.append(extra)
            break
    var center: Vector2 = entry["pos"]
    Pickups.remove(entry)
    Pickups.spawn_ring(loot, center, room_id, float(_items_config().get("drop_spread", 18.0)))
    var names: PackedStringArray = []
    for id in loot:
        names.append(String(Inventory.label(String(id))["name"]))
    Events.loot_box_opened.emit(room_id, loot)
    var text := "LOOT BOX OPENED: it was empty. The audience loved it."
    if not names.is_empty():
        text = "LOOT BOX OPENED: %s. The sponsors applaud from a safe distance." % ", ".join(names)
    Events.announcement_requested.emit("loot_box_opened", {"text": text, "priority": 4,
        "category": "celebration", "items": Array(names)})
    Events.say(text, "progression")
    return loot


# --- Using items ----------------------------------------------------------------

## `use_item`: fires the active item's on_use effects and spends a charge.
func use_active() -> bool:
    var inv: Dictionary = Inventory.data()
    var id: String = String(inv["active"])
    if id == "" or not player_can_act():
        return false
    var name: String = String(Inventory.label(id)["name"])
    if not Inventory.active_ready():
        Events.say("%s is recharging." % name, "info")
        return false
    EffectRunner.fire_item(game.combat, id, "on_use")
    Inventory.spend_active()
    Events.say("Activated %s." % name, "progression")
    return true


## `use_consumable`: uses one item from the selected belt slot.
func use_consumable() -> bool:
    var id: String = Inventory.consumable_at()
    if id == "" or not player_can_act():
        return false
    EffectRunner.fire_item(game.combat, id, "on_use")
    Inventory.spend_consumable()
    Events.say("Used %s." % Inventory.label(id)["name"], "progression")
    return true


## `next_consumable`: selects the next belt slot.
func next_consumable() -> int:
    return Inventory.select_next_consumable()


# --- Event handlers -------------------------------------------------------------

func _on_run_started(_seed: int) -> void:
    Inventory.reset()
    _periodic_timers.clear()
    _last_kill_pos = Vector2.INF
    _dirty = true


func _on_floor_started(depth: int, _floor: Dictionary) -> void:
    _dirty = true
    if depth > 1 and not bool(_items_config().get("floor_start_every_floor", true)):
        return
    var start_id: int = int(RunState.floor.get("start_id", RunState.current_room_id))
    var loot: Array[String] = LootRules.roll(ContentDB.default_db(), FLOOR_START_TABLE,
        RunState.floor_seed(), depth, start_id, 0)
    Pickups.spawn_ring(Array(loot), FLOOR_START_SPOT, start_id, 0.0 if loot.size() <= 1 else 16.0)


func _on_floor_cleared(_depth: int) -> void:
    Inventory.advance_active("floors", 1.0)


func _on_room_entered(_room_id: int, _kind: String, _entry: Dictionary, _first: bool) -> void:
    _dirty = true
    if game != null and game.combat != null:
        EffectRunner.fire(game.combat, "on_room_enter")


func _on_enemy_killed(_definition_id: String, xp: int, position: Vector2) -> void:
    _last_kill_pos = position
    if xp <= 0:
        return
    var rules: Dictionary = RunState.config.get("credits", {})
    Inventory.add_credits(maxi(int(rules.get("min_per_kill", 1)),
        roundi(float(xp) * float(rules.get("per_kill_xp_ratio", 0.1)))))


func _on_room_cleared(room_id: int) -> void:
    if RunState.floor.is_empty():
        return
    var kind: String = String(RunState.floor["rooms"][room_id]["kind"])
    var credit_rules: Dictionary = RunState.config.get("credits", {}).get("room_clear", {})
    Inventory.add_credits(int(credit_rules.get(kind, 0)))
    if Array(_items_config().get("room_clear_kinds", ["normal", "elite", "trap"])).has(kind) \
            and room_clear_roll_passes(room_id):
        var loot: Array[String] = LootRules.roll(ContentDB.default_db(), ROOM_CLEAR_TABLE,
            RunState.floor_seed(), RunState.depth, room_id, 0)
        var spot: Vector2 = _last_kill_pos if _last_kill_pos != Vector2.INF else Vector2(192, 192)
        Pickups.spawn_ring(Array(loot), spot, room_id, 0.0 if loot.size() <= 1 else 16.0)
    if game != null and game.combat != null:
        EffectRunner.fire(game.combat, "on_room_clear")
    Inventory.advance_active("rooms_cleared", 1.0)


## Seeded gate before the room_normal_clear table (items.room_clear_chance_by_depth).
func room_clear_roll_passes(room_id: int) -> bool:
    var chance := 1.0
    for band in _items_config().get("room_clear_chance_by_depth", []):
        if int(band.get("min_depth", 1)) <= RunState.depth:
            chance = float(band.get("chance", 1.0))
    var gate := RandomNumberGenerator.new()
    gate.seed = LootRules.seed_for("room_clear_gate", RunState.floor_seed(), RunState.depth, room_id, 0)
    return gate.randf() < chance


func _on_boss_defeated(_definition_id: String) -> void:
    var spot: Vector2 = _last_kill_pos if _last_kill_pos != Vector2.INF else Vector2(192, 192)
    Pickups.spawn(Pickups.LOOT_BOX, spot, RunState.current_room_id, {"table": BOSS_TABLE})
    Events.announcement_requested.emit("loot_box_dropped", {"text":
        "A sponsor loot box drops from the ceiling. Press E to see what they think you deserve.",
        "priority": 3, "category": "sponsor"})


func _on_chest_opened(room_id: int, loot_ids: Array) -> void:
    var center := Vector2(192, 192)
    for feature in RunState.room_states.get(room_id, {}).get("interactables", []):
        if String(feature["kind"]) == "chest":
            center = feature["pos"]
            break
    Pickups.spawn_ring(loot_ids, center, room_id, float(_items_config().get("drop_spread", 18.0)))


func _on_level_up(_level: int, _points: int) -> void:
    _dirty = true
    if game != null and game.combat != null:
        EffectRunner.fire(game.combat, "on_level_up")


# --- Guild shop -----------------------------------------------------------------

func _shop_config() -> Dictionary:
    return RunState.config.get("shop", {})


## Price of `id`: value x rarity multiplier, less 10 % per positive CHA
## modifier (capped by shop.max_discount), at least shop.min_price.
func price_of(id: String) -> int:
    var rules: Dictionary = _shop_config()
    var record: Dictionary = ContentDB.record(id)
    var mult: float = float(rules.get("rarity_price_multipliers", {}).get(
        String(record.get("rarity", "common")), 1.0))
    var cha: int = maxi(0, RPG.modifier(int(RunState.ability_scores.get("CHA", 10))))
    var discount: float = minf(float(rules.get("max_discount", 0.5)),
        float(cha) * float(rules.get("cha_discount_per_mod", 0.1)))
    return maxi(int(rules.get("min_price", 1)),
        roundi(float(record.get("value", 0)) * mult * (1.0 - discount)))


## The shop entry's stock (rolled once per guild hall, deterministic by floor
## seed and room): [{id, price, sold}].
func shop_stock(entry: Dictionary) -> Array:
    if not entry.has("stock"):
        var room_id: int = int(entry.get("room_id", RunState.current_room_id))
        var ids: Array[String] = LootRules.roll(ContentDB.default_db(), SHOP_TABLE,
            RunState.floor_seed(), RunState.depth, room_id, int(entry.get("salt", 0)))
        var stock: Array = []
        for id in ids.slice(0, int(_shop_config().get("offers", 3))):
            stock.append({"id": id, "price": price_of(id), "sold": false})
        entry["stock"] = stock
    return entry["stock"]


func shop_prompt(_entry: Dictionary) -> String:
    return "[E] Browse the guild shop (%d credits)" % Inventory.credits()


## Opens the shop dialog: credits, then one option per offer ("SOLD" afterwards).
func open_shop(entry: Dictionary) -> void:
    var stock: Array = shop_stock(entry)
    var lines: PackedStringArray = ["Credits: %d. All sales final. All sales are also lightly cursed." %
        Inventory.credits()]
    var options: Array = []
    for i in range(stock.size()):
        var offer: Dictionary = stock[i]
        var info: Dictionary = Inventory.label(String(offer["id"]))
        if bool(offer["sold"]):
            options.append({"id": str(i), "label": "SOLD: %s" % info["name"]})
            continue
        lines.append("%s (%s %s, %d cr): %s" % [info["name"], info["rarity"], info["kind"],
            int(offer["price"]), info["description"]])
        options.append({"id": str(i), "label": "Buy %s - %d cr" % [info["name"], int(offer["price"])]})
    game.services.open_choice("GUILD SHOP", "\n".join(lines), options,
        func(choice: String): _on_shop_choice(entry, int(choice)))


func _on_shop_choice(entry: Dictionary, index: int) -> void:
    buy(entry, index)
    if RunState.outcome == "running":
        open_shop.call_deferred(entry)


## Buys offer `index`. Returns "bought", "sold_out", "cannot_afford",
## "no_room" or "invalid". Weapons and actives swap (the old one drops at the
## crawler's feet); a full belt or a maxed passive refuses without charging.
func buy(entry: Dictionary, index: int) -> String:
    var stock: Array = shop_stock(entry)
    if index < 0 or index >= stock.size():
        return "invalid"
    var offer: Dictionary = stock[index]
    var info: Dictionary = Inventory.label(String(offer["id"]))
    if bool(offer["sold"]):
        Events.say("%s is sold out. The shelf has a dust outline of it." % info["name"], "info")
        return "sold_out"
    if Inventory.credits() < int(offer["price"]):
        Events.say("Insufficient credits for %s (%d needed, %d held). No layaway." % [info["name"],
            int(offer["price"]), Inventory.credits()], "info")
        return "cannot_afford"
    if not bool(Inventory.can_accept(String(offer["id"]))["ok"]):
        Events.say("No room for %s. Your pockets file a complaint." % info["name"], "info")
        return "no_room"
    Inventory.spend_credits(int(offer["price"]))
    Inventory.acquire(String(offer["id"]), game.player.world_position)
    offer["sold"] = true
    Events.say("Bought %s for %d credits." % [info["name"], int(offer["price"])], "progression")
    return "bought"
