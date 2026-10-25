extends RefCounted
## The one place effects are gathered (Wave 2B): builds the
## ContentDB.loadout() input from the inventory (weapons, active, passives)
## and RunState.skills, and resolves passive stats and attack profiles.
##
## RunState.skills entries may be plain ids ("skl_brawler", rank 1) or
## {"id": "skl_brawler", "rank": 2}; the skills PR fills them.
## Autoloads are looked up at runtime, so tests may preload this module.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const Inventory = preload("res://scripts/inventory.gd")
const StatusSystem = preload("res://scripts/status_system.gd")
const DEFAULT_SPEED := 105.0


## Owned records as loadout input ({id, rank, stacks}). `slot` ("melee" or
## "ranged") leaves out the *other* weapon so a weapon's on_hit effects only
## fire for its own attacks; `weapon_id` overrides the weapon in `slot` (a
## projectile keeps the weapon that fired it).
static func owned(slot: String = "", weapon_id: String = "") -> Array:
    var rs: Node = Inventory.run_state()
    var inv: Dictionary = rs.inventory
    var result: Array = []
    for weapon_slot in Inventory.WEAPON_SLOTS:
        if slot != "" and weapon_slot != slot:
            continue
        var id: String = weapon_id if weapon_id != "" and weapon_slot == slot \
            else Inventory.weapon_id(weapon_slot)
        if id != "":
            result.append({"id": id, "rank": 1, "stacks": 1})
    if String(inv.get("active", "")) != "":
        result.append({"id": String(inv["active"]), "rank": 1, "stacks": 1})
    for entry in inv.get("passives", []):
        result.append({"id": String(entry["id"]), "rank": 1, "stacks": int(entry["count"])})
    for skill in rs.skills:
        if skill is Dictionary:
            result.append({"id": String(skill.get("id", "")), "rank": int(skill.get("rank", 1)),
                "stacks": 1})
        else:
            result.append({"id": String(skill), "rank": 1, "stacks": 1})
    return result


## ContentDB.loadout() of owned(): the entries EffectResolver.collect_modifiers() takes.
static func current(slot: String = "", weapon_id: String = "") -> Array[Dictionary]:
    return ContentDB.loadout(owned(slot, weapon_id))


## Condition inputs for passives (hp, max_hp, ticks, depth, room_kind). No RNG:
## passive effects with a `chance` never switch on, and passives consume no rolls.
static func passive_context() -> Dictionary:
    var rs: Node = Inventory.run_state()
    return {"db": ContentDB.default_db(), "hp": rs.hp, "max_hp": rs.max_hp,
        "ticks": rs.ticks, "depth": rs.depth, "room_kind": rs.current_room_kind()}


## Passive stat and projectile modifiers from every owned record.
static func passive_modifiers(slot: String = "") -> Array[Dictionary]:
    return Resolver.collect_modifiers(current(slot), "passive", passive_context())


## Passive modifiers plus the crawler's status modifiers (hasted, slowed...).
static func combat_modifiers(slot: String = "") -> Array[Dictionary]:
    var modifiers: Array[Dictionary] = passive_modifiers(slot)
    modifiers.append_array(StatusSystem.player_modifiers())
    return modifiers


## ContentDB.attack_profile() for the equipped weapon in `slot`, with passives
## and statuses applied, plus `effects` (the weapon's effect ids) and `tags`.
static func attack_profile(slot: String, weapon_id: String = "") -> Dictionary:
    var rs: Node = Inventory.run_state()
    var id: String = weapon_id if weapon_id != "" else Inventory.weapon_id(slot)
    var record: Dictionary = ContentDB.weapon(id)
    var profile: Dictionary = ContentDB.attack_profile(record, rs.ability_scores, rs.level,
        combat_modifiers(slot))
    profile["effects"] = Array(record.get("effects", [])).duplicate()
    profile["tags"] = Array(record.get("tags", [])).duplicate()
    profile["name"] = String(record.get("name", id))
    return profile


## The crawler's derived non-RPG stats: move_speed, damage_taken_mult,
## heal_mult, pickup_radius, xp_mult (passives and statuses applied).
static func player_stats() -> Dictionary:
    var rs: Node = Inventory.run_state()
    var base := {"move_speed": float(rs.config.get("player_speed", DEFAULT_SPEED)),
        "damage_taken_mult": 1.0, "heal_mult": 1.0, "pickup_radius": 0.0, "xp_mult": 1.0}
    return Resolver.apply_stat_modifiers(base, combat_modifiers())
