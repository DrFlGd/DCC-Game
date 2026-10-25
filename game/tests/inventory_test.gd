extends SceneTree
## Wave 2B inventory, loot and shop on the live Main.tscn: starting loadout,
## equip/swap/drop rules, consumable stacking and the belt cap, passive stack
## caps, active recharge in seconds / rooms_cleared / floors, pickups from
## scripted events and a real chest, the boss loot box, credits, the guild
## shop (purchase, refusal, sold out), passive stat modifiers on and off,
## grant_ticks ending a grace, and loot determinism for a seed.
## Run: godot --headless --path game --script res://tests/inventory_test.gd
## The modules preloaded below never name an autoload (they look RunState and
## Events up at runtime), so they are safe here; Game is load()ed.
const Inventory = preload("res://scripts/inventory.gd")
const Pickups = preload("res://scripts/pickups.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const ContentDB = preload("res://scripts/content/content_db.gd")
const LootRules = preload("res://scripts/content/loot_rules.gd")
const SEED := 424242
const FRAME := 1.0 / 60.0
var failures := 0
var game
var rs: Node
var events: Node
var seen: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, detail: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL INVENTORY: " + detail)


func _record(name: String, args: Array) -> void:
    if not seen.has(name):
        seen[name] = []
    seen[name].append(args)


func _count(name: String) -> int:
    return seen.get(name, []).size()


func _run() -> void:
    rs = get_root().get_node("RunState")
    events = get_root().get_node("Events")
    events.item_picked_up.connect(func(id): _record("item_picked_up", [id]))
    events.item_used.connect(func(id): _record("item_used", [id]))
    events.item_dropped.connect(func(id, pos): _record("item_dropped", [id, pos]))
    events.inventory_changed.connect(func(): _record("inventory_changed", []))
    events.credits_changed.connect(func(amount, total): _record("credits_changed", [amount, total]))
    events.loot_box_opened.connect(func(room, ids): _record("loot_box_opened", [room, ids]))
    events.announcement_requested.connect(func(trigger, ctx): _record("announce", [trigger, ctx]))
    game = load("res://scenes/Main.tscn").instantiate()
    get_root().add_child(game)
    _test_starting_loadout()
    _test_weapon_swap()
    _test_active_swap_and_recharge()
    _test_consumables()
    _test_passives_and_stats()
    _test_scripted_pickups()
    _test_chest_to_inventory()
    _test_boss_loot_box()
    _test_credits()
    _test_shop()
    _test_grant_ticks_grace()
    _test_loot_determinism()
    _test_input_map()
    game.queue_free()
    if failures == 0:
        print("PASS: loadout, swaps, belt, passives, recharge units, pickups, chest, loot box, credits, shop, grace, determinism")
    quit(1 if failures > 0 else 0)


func _fresh() -> void:
    game.start_run(SEED)
    seen.clear()


## Clears the current room's pickups so tests control what is on the floor.
func _clear_pickups() -> void:
    Pickups.current().clear()


func _test_starting_loadout() -> void:
    _fresh()
    var inv: Dictionary = rs.inventory
    check(inv["melee"] == "wpn_crowbar" and inv["ranged"] == "wpn_nail_pistol",
        "run.starting_loadout equips the crowbar and the nail pistol: %s" % [inv])
    check(inv["active"] == "" and inv["passives"].is_empty() and inv["consumables"].is_empty()
        and inv["credits"] == 0, "nothing else at the start")
    var view: Dictionary = Inventory.describe()
    check(view["melee"]["name"] == "Complimentary Crowbar" and view["belt_size"] == 6,
        "describe() names the slots; 6 belt slots")
    var owned: Array = Loadout.owned()
    check(owned.size() == 2 and owned[0]["id"] == "wpn_crowbar", "Loadout.owned: weapons first")
    rs.skills.append({"id": "skl_brawler", "rank": 2})
    var loadout: Array = Loadout.current()
    check(loadout.size() == 3 and loadout[2]["id"] == "skl_brawler" and loadout[2]["rank"] == 2,
        "Loadout.current includes RunState.skills with ranks")
    check(Loadout.current("melee").size() == 2, "slot filter drops the other weapon")
    rs.skills.clear()


func _test_weapon_swap() -> void:
    _fresh()
    _clear_pickups()
    var feet := Vector2(150, 192)
    var result: Dictionary = Inventory.acquire("wpn_box_cutter", feet)
    check(result["ok"] and result["dropped"] == "wpn_crowbar" and rs.inventory["melee"] == "wpn_box_cutter",
        "a weapon into a full slot swaps")
    var floor_items: Array = Pickups.current()
    check(floor_items.size() == 1 and floor_items[0]["id"] == "wpn_crowbar"
        and Vector2(floor_items[0]["pos"]).distance_to(feet) < 1.0, "the old weapon drops at the crawler's feet")
    check(_count("item_dropped") == 1 and seen["item_dropped"][0][0] == "wpn_crowbar", "item_dropped(id, pos)")
    check(_count("item_picked_up") == 1 and seen["item_picked_up"][0][0] == "wpn_box_cutter",
        "item_picked_up(id)")
    check(_count("inventory_changed") >= 1, "inventory_changed")
    var again: Dictionary = Inventory.acquire("wpn_box_cutter", feet)
    check(not again["ok"] and again["reason"] == "already_equipped", "same weapon refused")
    # Interact pickup: standing on the dropped crowbar swaps back.
    game.player.world_position = feet
    game.items.refresh_prompt()
    check(game.items.prompt.begins_with("[E] Take Complimentary Crowbar"), "weapon pickup prompt: %s"
        % game.items.prompt)
    game._redraw()
    check(game.hud.prompt == game.items.prompt and not game.hud.hover.is_empty(),
        "the HUD shows the pickup prompt and tooltip")
    game.items.update(FRAME)
    check(rs.inventory["melee"] == "wpn_box_cutter", "weapons are not taken on contact")
    var interact := InputEventAction.new()
    interact.action = "interact"
    interact.pressed = true
    game._unhandled_input(interact)
    check(rs.inventory["melee"] == "wpn_crowbar" and Pickups.current().size() == 1
        and Pickups.current()[0]["id"] == "wpn_box_cutter", "interact swaps the weapons back")
    var ranged: Dictionary = Inventory.acquire("wpn_siege_crossbow", feet)
    check(ranged["dropped"] == "wpn_nail_pistol" and rs.inventory["ranged"] == "wpn_siege_crossbow",
        "ranged slot swaps the same way")


func _test_active_swap_and_recharge() -> void:
    _fresh()
    _clear_pickups()
    game.player.world_position = Vector2(192, 192)
    check(Inventory.acquire("itm_safety_button")["ok"] and rs.inventory["active"] == "itm_safety_button",
        "an active fills the empty slot")
    check(Inventory.active_ready() and rs.inventory["active_state"]["unit"] == "seconds",
        "fresh actives are charged")
    # seconds: Customer Safety Button (20 s).
    check(game.items.use_active(), "use_item fires the active")
    check(rs.statuses.has("shielded") and int(rs.statuses["shielded"]["magnitude"]) == 8,
        "on_use applied the 8-point shield")
    check(_count("item_used") == 1 and not Inventory.active_ready(), "item_used; charge spent")
    check(not game.items.use_active(), "no charge, no use")
    Inventory.advance_active("seconds", 19.9)
    check(not Inventory.active_ready() and absf(Inventory.active_fraction() - 0.995) < 0.01,
        "recharging (fraction %.3f)" % Inventory.active_fraction())
    game.items.update(0.2)
    check(Inventory.active_ready(), "recharged after 20 s (ItemSystem.update advances seconds)")
    # Swap: the old active drops with its state; picking it up restores the state.
    game.items.use_active()
    var swap: Dictionary = Inventory.acquire("itm_floor_stomp", Vector2(192, 192))
    check(swap["dropped"] == "itm_safety_button" and rs.inventory["active"] == "itm_floor_stomp",
        "active swap drops the old one")
    var dropped: Dictionary = Pickups.current()[0]
    check(int(dropped["state"].get("charges", -1)) == 0, "the dropped active keeps its spent charge")
    game.items.take_pickup(dropped)
    check(rs.inventory["active"] == "itm_safety_button" and not Inventory.active_ready(),
        "re-taking it does not refill it")
    # rooms_cleared: Borrowed Time Pouch (3 rooms).
    rs.inventory["active"] = ""
    Inventory.acquire("itm_time_pouch")
    var before: int = rs.ticks
    check(game.items.use_active() and rs.ticks == before + 2, "time pouch grants 2 ticks")
    check(rs.tick_ledger.back()["source"] == "item:itm_time_pouch", "ledger source item:<id>")
    var room_id: int = rs.current_room_id
    for i in range(2):
        events.room_cleared.emit(room_id)
    check(not Inventory.active_ready(), "2 of 3 rooms cleared: still recharging")
    events.room_cleared.emit(room_id)
    check(Inventory.active_ready(), "3 rooms cleared: recharged")
    # floors: a one-floor active (no starter item uses floors; the unit is generic).
    rs.inventory["active_state"] = {"charges": 0, "max_charges": 2, "progress": 0.0,
        "cooldown": 1.0, "unit": "floors"}
    events.room_cleared.emit(room_id)
    check(not Inventory.active_ready(), "rooms do not recharge a floors item")
    events.floor_cleared.emit(rs.depth)
    check(int(rs.inventory["active_state"]["charges"]) == 2, "a cleared floor restores every charge")


func _test_consumables() -> void:
    _fresh()
    _clear_pickups()
    var take: Dictionary = Inventory.acquire("itm_bandage_roll", Vector2.INF, 7)
    var belt: Array = rs.inventory["consumables"]
    check(take["taken"] == 7 and belt.size() == 2 and belt[0]["count"] == 5 and belt[1]["count"] == 2,
        "bandages stack to stack_max 5, then use a second slot: %s" % [belt])
    for id in ["itm_sketchy_antidote", "itm_speed_draught", "itm_party_popper", "itm_tick_shard"]:
        Inventory.acquire(id)
    check(belt.size() == 6, "six slots filled")
    check(Inventory.acquire("itm_bandage_roll", Vector2.INF, 3)["taken"] == 3 and belt[1]["count"] == 5,
        "a partial stack still takes copies")
    var full: Dictionary = Inventory.acquire("itm_sponsored_medkit")
    check(not full["ok"] and full["reason"] == "belt_full", "a seventh id is refused")
    var cap: Dictionary = Inventory.can_accept("itm_bandage_roll")
    check(not cap["ok"], "full stacks and a full belt refuse more of the same id")
    # Use, select, swap.
    rs.hp = 3
    game.items.use_consumable()
    check(rs.hp == 9 and belt[0]["count"] == 4 and seen.get("item_used", []).back()[0] == "itm_bandage_roll",
        "use_consumable heals 6 and decrements")
    Inventory.select_next_consumable()
    Inventory.select_next_consumable()
    check(Inventory.consumable_at() == "itm_sketchy_antidote", "next_consumable cycles the selection")
    StatusSystem.apply("player", {"status": "poisoned", "magnitude": 1, "duration": 5})
    game.items.use_consumable()
    check(not rs.statuses.has("poisoned") and Inventory.consumable_count("itm_sketchy_antidote") == 0
        and belt.size() == 5, "the antidote cleanses poison and its emptied slot is removed")
    Inventory.acquire("itm_sketchy_antidote")
    check(belt.size() == 6, "belt full again")
    # Full-belt swap from the floor.
    var feet := Vector2(150, 150)
    Pickups.spawn("itm_sponsored_medkit", feet, rs.current_room_id)
    game.player.world_position = feet
    game.items.update(FRAME)
    check(Pickups.current().size() == 1, "a full belt leaves the consumable on the floor")
    check(game.items.prompt.begins_with("Belt full: [E] swap"), "swap prompt: %s" % game.items.prompt)
    var selected: String = Inventory.consumable_at()
    check(game.items.try_interact(), "interact swaps the selected slot")
    check(Inventory.consumable_at() == "itm_sponsored_medkit" and Pickups.current().size() == 1
        and Pickups.current()[0]["id"] == selected, "the old stack dropped at the crawler's feet")


func _test_passives_and_stats() -> void:
    _fresh()
    game.items.recompute()
    var base_ac: int = rs.ac
    var base_max: int = rs.max_hp
    Inventory.acquire("itm_hazard_vest")
    game.items.update(FRAME)
    check(rs.ac == base_ac + 1 and rs.max_hp == base_max + 4 and rs.hp == base_max + 4,
        "hazard vest: +1 AC, +4 max HP (and heals the gain): AC %d HP %d/%d" % [rs.ac, rs.hp, rs.max_hp])
    Inventory.acquire("itm_hazard_vest")
    game.items.update(FRAME)
    check(rs.ac == base_ac + 2 and rs.max_hp == base_max + 8, "two vests stack (stack_count:2)")
    var third: Dictionary = Inventory.acquire("itm_hazard_vest")
    check(not third["ok"] and third["reason"] == "max_stack", "stack_max 2 refuses a third")
    rs.inventory["passives"].clear()
    events.inventory_changed.emit()
    game.items.update(FRAME)
    check(rs.ac == base_ac and rs.max_hp == base_max and rs.hp <= rs.max_hp,
        "removing the passives restores AC and max HP")
    Inventory.acquire("itm_knockoff_sneakers")
    game.items.update(FRAME)
    check(is_equal_approx(game.player.speed, 105.0 * 1.12), "sneakers: move speed x1.12 (%.2f)" %
        game.player.speed)
    StatusSystem.apply("player", {"status": "slowed"})
    game.items.update(FRAME)
    check(is_equal_approx(game.player.speed, 105.0 * 1.12 * 0.6), "slowed stacks multiplicatively")
    Inventory.acquire("itm_ricochet_wax")
    game.items.update(FRAME)
    check(int(game.items.profile("ranged")["pierce"]) == 1, "ricochet wax: +1 pierce on the pistol")
    rs.inventory["passives"].append({"id": "itm_last_gasp_adrenaline", "count": 1})
    events.inventory_changed.emit()
    game.items.update(FRAME)
    check(is_equal_approx(game.items.cooldown("melee"), 0.5), "adrenaline idle above 35 % HP")
    rs.hp = 2
    events.player_damaged.emit(0, "test")
    check(is_equal_approx(game.items.cooldown("melee"), 0.4), "adrenaline: melee cooldown x0.8 below 35 %")


func _test_scripted_pickups() -> void:
    _fresh()
    _clear_pickups()
    var room_id: int = rs.current_room_id
    rs.room_states[room_id]["interactables"].append({"id": "chest_test", "kind": "chest",
        "pos": Vector2(100, 100), "cell": Vector2i(6, 6), "used": true, "room_id": room_id})
    events.chest_opened.emit(room_id, ["itm_vampire_straw", "itm_bandage_roll", "wpn_mop_pike"])
    var floor_items: Array = Pickups.current()
    check(floor_items.size() == 3, "chest_opened places every id as a pickup")
    for entry in floor_items:
        check(Vector2(entry["pos"]).distance_to(Vector2(100, 100)) < 26.0, "pickups ring the chest")
    for entry in floor_items.duplicate():
        game.player.world_position = entry["pos"]
        game.items.update(FRAME)
    check(Inventory.passive_count("itm_vampire_straw") == 1 and Inventory.consumable_count("itm_bandage_roll") == 1,
        "passives and consumables are taken on contact")
    check(Pickups.current().size() == 1 and Pickups.current()[0]["id"] == "wpn_mop_pike",
        "the weapon waits for interact")
    check(rs.telemetry["items_collected"] == 2, "items_collected telemetry")


func _test_chest_to_inventory() -> void:
    _fresh()
    var treasure_id: int = int(rs.floor["specials"]["treasure"][0])
    rs.current_room_id = treasure_id
    rs.visited[treasure_id] = true
    game._load_room(treasure_id)
    var chest: Dictionary = {}
    for feature in rs.current_room()["interactables"]:
        if feature["kind"] == "chest":
            chest = feature
    game.player.world_position = Vector2(chest["pos"]) + Vector2(0, 16)
    game.services.try_interact()
    var expected: Array[String] = LootRules.roll(ContentDB.default_db(), "treasure_room", SEED, 1,
        treasure_id, 0)
    var ids: Array = []
    for entry in Pickups.current():
        ids.append(entry["id"])
    check(ids == Array(expected), "the real chest's loot lies on the floor: %s" % [ids])
    for entry in Pickups.current().duplicate():
        game.player.world_position = entry["pos"]
        game.items.update(FRAME)
        if not Pickups.current().has(entry):
            continue
        game.items.try_interact()
    check(Pickups.current().size() <= 1, "chest loot moved into the inventory (swaps leave the old item)")
    for id in expected:
        var kind: String = Inventory.kind_of(id)
        var owned: bool = rs.inventory["melee"] == id or rs.inventory["ranged"] == id \
            or rs.inventory["active"] == id or Inventory.passive_count(id) > 0 \
            or Inventory.consumable_count(id) > 0
        check(owned, "%s (%s) is in the inventory" % [id, kind])


func _test_boss_loot_box() -> void:
    _fresh()
    var boss_id: int = int(rs.floor["boss_id"])
    rs.current_room_id = boss_id
    game._load_room(boss_id)
    _clear_pickups()
    var spot := Vector2(200, 120)
    events.enemy_killed.emit("test_boss", 0, spot)
    events.boss_defeated.emit("test_boss")
    var crate: Array = Pickups.current()
    check(crate.size() == 1 and crate[0]["id"] == Pickups.LOOT_BOX
        and Vector2(crate[0]["pos"]).distance_to(spot) < 12.0, "boss_defeated drops a loot box at the kill")
    game.player.world_position = crate[0]["pos"]
    game.items.update(FRAME)
    check(Pickups.current().size() == 1, "the crate is not opened on contact")
    check(game.items.prompt == "[E] Open the sponsor loot box", "loot box prompt")
    check(game.items.try_interact(), "interact opens it")
    var expected: Array[String] = LootRules.roll(ContentDB.default_db(), "boss_kill", SEED, 1, boss_id, 0)
    check(_count("loot_box_opened") == 1 and seen["loot_box_opened"][0][1] == Array(expected)
        and expected.size() == 2, "loot_box_opened rolls boss_kill: %s" % [seen.get("loot_box_opened")])
    var announced := false
    for entry in seen.get("announce", []):
        announced = announced or (entry[0] == "loot_box_opened" and String(entry[1]["text"]).begins_with("LOOT BOX OPENED"))
    check(announced, "announcement_requested(loot_box_opened, {text})")
    var ids: Array = []
    for entry in Pickups.current():
        ids.append(entry["id"])
    check(ids == Array(expected), "the box's rewards lie around it")
    check(rs.telemetry["loot_boxes_opened"] == 1, "loot_boxes_opened telemetry")
    for id in expected:
        check(ContentDB.record(id)["rarity"] != "common", "boss loot is never common")


func _test_credits() -> void:
    _fresh()
    events.enemy_killed.emit("rat_scavenger", 25, Vector2(100, 100))
    check(Inventory.credits() == 3 and seen["credits_changed"][0] == [3, 3],
        "a 25 XP kill pays round(25 x 0.1) = 3 credits")
    events.enemy_killed.emit("rat_pup", 0, Vector2(100, 100))
    check(Inventory.credits() == 3, "0 XP summons pay nothing")
    var normal_id := -1
    for room in rs.floor["rooms"]:
        if room["kind"] == "normal":
            normal_id = int(room["id"])
            break
    game._load_room(normal_id)
    events.room_cleared.emit(normal_id)
    check(Inventory.credits() == 7, "a normal room clear pays 4")
    check(rs.telemetry["credits_earned"] == 7, "credits_earned telemetry")
    check(not Inventory.spend_credits(8) and Inventory.spend_credits(7) and Inventory.credits() == 0,
        "spending checks the balance")


func _test_shop() -> void:
    _fresh()
    var guild_id: int = int(rs.floor["guild_id"])
    rs.current_room_id = guild_id
    rs.visited[guild_id] = true
    game._load_room(guild_id)
    var shop: Dictionary = {}
    for feature in rs.current_room()["interactables"]:
        if feature["kind"] == "shop":
            shop = feature
    check(not shop.is_empty(), "the guild hall has a shop")
    var stock: Array = game.items.shop_stock(shop)
    var rolled: Array[String] = LootRules.roll(ContentDB.default_db(), "guild_hall_shop", SEED, 1,
        guild_id, 0)
    check(stock.size() == 3 and stock[0]["id"] == rolled[0] and stock[2]["id"] == rolled[2],
        "three offers from guild_hall_shop, deterministic by floor seed and room")
    for offer in stock:
        var record: Dictionary = ContentDB.record(String(offer["id"]))
        var mult: float = {"common": 1.0, "uncommon": 1.25, "rare": 1.5, "epic": 2.0}[record["rarity"]]
        check(int(offer["price"]) == maxi(1, roundi(float(record["value"]) * mult)),
            "price = value x rarity multiplier (%s %d)" % [offer["id"], offer["price"]])
    game.player.world_position = Vector2(shop["pos"]) + Vector2(0, 16)
    game.services.update(FRAME)
    check(game.services.prompt.begins_with("[E] Browse the guild shop"), "shop prompt")
    game.services.try_interact()
    check(game.services.is_modal_open() and game.services.dialog.body.begins_with("Credits: 0"),
        "the dialog shows the credits")
    check(game.services.dialog.options.size() == 3, "one option per offer")
    game.services.dialog.cancel()
    check(game.items.buy(shop, 0) == "cannot_afford" and not stock[0]["sold"] and Inventory.credits() == 0,
        "refused without enough credits")
    Inventory.add_credits(1000)
    var id: String = String(stock[0]["id"])
    var price: int = int(stock[0]["price"])
    check(game.items.buy(shop, 0) == "bought" and Inventory.credits() == 1000 - price and stock[0]["sold"],
        "purchase deducts the price")
    var owned: bool = rs.inventory["melee"] == id or rs.inventory["ranged"] == id \
        or rs.inventory["active"] == id or Inventory.passive_count(id) > 0 or Inventory.consumable_count(id) > 0
    check(owned, "the purchase is in the inventory")
    check(game.items.buy(shop, 0) == "sold_out" and Inventory.credits() == 1000 - price, "sold out afterwards")
    game.services.try_interact()
    check(String(game.services.dialog.options[0]["label"]).begins_with("SOLD"), "the dialog shows SOLD")
    game.services.dialog.choose("1")
    check(stock[1]["sold"], "choosing an option buys it")
    if game.services.is_modal_open():
        game.services.dialog.cancel()
    # CHA discount: +3 modifier = 30 % off.
    rs.ability_scores["CHA"] = 16
    var record: Dictionary = ContentDB.record("itm_hazard_vest")
    check(game.items.price_of("itm_hazard_vest") == roundi(float(record["value"]) * 0.7),
        "CHA +3 takes 30 % off")


func _test_grant_ticks_grace() -> void:
    _fresh()
    rs.add_ticks(-rs.ticks, "test drain")
    check(rs.grace_active(), "draining to 0 starts grace")
    Inventory.acquire("itm_tick_shard")
    check(game.items.use_consumable(), "tick shard used")
    check(not rs.grace_active() and rs.ticks == 1 and rs.grace["outcome"] == "stabilised",
        "grant_ticks stabilises the floor and ends the grace")
    check(rs.tick_ledger.back()["source"] == "item:itm_tick_shard", "ledger source item:itm_tick_shard")


func _test_loot_determinism() -> void:
    var runs: Array = []
    for _i in range(2):
        _fresh()
        var start_items: Array = []
        for entry in Pickups.list(int(rs.floor["start_id"])):
            start_items.append(entry["id"])
        var clears: Array = []
        for room in rs.floor["rooms"]:
            if room["kind"] == "normal":
                clears.append([game.items.room_clear_roll_passes(int(room["id"])),
                    LootRules.roll(ContentDB.default_db(), "room_normal_clear", SEED, 1, int(room["id"]), 0)])
        runs.append([start_items, clears])
    check(runs[0] == runs[1], "same seed, same floor-start package and room-clear loot")
    check(runs[0][0].size() == 1 and Inventory.kind_of(String(runs[0][0][0])) == "consumable",
        "floor_start drops one consumable: %s" % [runs[0][0]])
    var gates := 0
    for entry in runs[0][1]:
        gates += 1 if entry[0] else 0
    check(gates > 0 and gates < runs[0][1].size(), "the room-clear gate is a real chance (%d/%d)" %
        [gates, runs[0][1].size()])


## The belt actions exist, and no key or gamepad button is bound to two
## gameplay actions (ui_* built-ins excluded; axes may be shared by design).
func _test_input_map() -> void:
    for action in ["use_item", "use_consumable", "next_consumable", "interact"]:
        check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
            "input action bound: " + action)
    var owners: Dictionary = {}
    for action in InputMap.get_actions():
        if String(action).begins_with("ui_"):
            continue
        for event in InputMap.action_get_events(action):
            var key := ""
            if event is InputEventKey:
                key = "key:%d" % (event.physical_keycode if event.physical_keycode != 0 else event.keycode)
            elif event is InputEventJoypadButton:
                key = "pad:%d" % event.button_index
            elif event is InputEventMouseButton:
                key = "mouse:%d" % event.button_index
            if key == "":
                continue
            check(not owners.has(key), "%s is bound to both %s and %s" % [key, owners.get(key, ""), action])
            owners[key] = action
