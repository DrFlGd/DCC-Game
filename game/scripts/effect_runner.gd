extends RefCounted
## Fires content triggers and executes the resulting effects (Wave 2B).
##
## fire(combat, trigger, extra, slot, weapon_id) collects the trigger's
## effects from Loadout.current() through EffectResolver.collect_modifiers()
## (conditions, stacking, internal cooldowns; `chance` rolls use RunState.rng,
## and only when an effect actually has a chance), starts their cooldowns in
## inventory.effect_cooldowns and executes them. fire_item() does the same for
## one record only (an active's or a consumable's on_use); fire_skill() for one
## skill at a given rank (Wave 2F: an active skill's on_use, INT-scaled).
##
## `extra` context keys: target (enemy dictionary), origin (Vector2 centre for
## enemies_in_radius; default the crawler), slot, weapon_id, damage, source.
## Operations: heal (x heal_mult), damage (auto-hit, through
## combat.apply_damage with source "effect:<id>"), apply_status / set-status
## (StatusSystem), grant_ticks (RunState.add_ticks(n, "item:<id>" or
## "skill:<id>")), cooldown_reduction (melee, ranged, items, skills, dodge,
## all; 2F added skills = every active-skill cooldown in
## RunState.skill_cooldowns and dodge = the player's dodge_cooldown gap).
## Stat operations on non-passive triggers are
## ignored (timed stat buffs are statuses, CONTENT_RULES §10).
## Autoloads are looked up at runtime, so tests may preload this module.
const ContentDB = preload("res://scripts/content/content_db.gd")
const Resolver = preload("res://scripts/content/effect_resolver.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Loadout = preload("res://scripts/loadout.gd")
const StatusSystem = preload("res://scripts/status_system.gd")

const NEARBY_RADIUS := 64.0


## Condition context for a trigger (see EffectResolver.evaluate_condition).
static func context(combat, extra: Dictionary = {}) -> Dictionary:
    var rs: Node = Inventory.run_state()
    var inv: Dictionary = Inventory.data()
    var origin: Vector2 = combat.player.world_position if combat != null else Vector2.ZERO
    var nearby := 0
    var radius: float = float(rs.config.get("items", {}).get("nearby_enemy_radius", NEARBY_RADIUS))
    if combat != null:
        for foe in combat.enemies():
            if Vector2(foe["pos"]).distance_to(origin) <= radius:
                nearby += 1
    var ctx := {"db": ContentDB.default_db(), "rng": rs.rng, "now": StatusSystem.now(),
        "cooldowns": inv["effect_cooldowns"], "hp": rs.hp, "max_hp": rs.max_hp,
        "ticks": rs.ticks, "depth": rs.depth, "room_kind": rs.current_room_kind(),
        "nearby_enemies": nearby, "slot": String(extra.get("slot", ""))}
    var target = extra.get("target")
    if target is Dictionary:
        ctx["target_statuses"] = StatusSystem.statuses_of(target)
        ctx["target_tags"] = target.get("tags", [])
    var weapon: String = String(extra.get("weapon_id", ""))
    if weapon == "" and ctx["slot"] != "":
        weapon = Inventory.weapon_id(String(ctx["slot"]))
    if weapon != "":
        ctx["weapon_tags"] = ContentDB.weapon(weapon).get("tags", [])
    return ctx


## Fires `trigger` for everything the crawler owns. Returns the executed modifiers.
static func fire(combat, trigger: String, extra: Dictionary = {}, slot: String = "",
        weapon_id: String = "") -> Array[Dictionary]:
    var equipped: Array[Dictionary] = Loadout.current(slot, weapon_id)
    if not _has_trigger(equipped, trigger):
        return []
    return _collect_and_run(combat, equipped, trigger, extra)


## Fires `trigger` for record `id` alone (an active's or a consumable's on_use).
static func fire_item(combat, id: String, trigger: String = "on_use",
        extra: Dictionary = {}) -> Array[Dictionary]:
    var equipped: Array[Dictionary] = ContentDB.loadout([id])
    return _collect_and_run(combat, equipped, trigger, extra)


## Fires `trigger` for skill `id` at `rank` alone (an active skill's on_use).
## The entry carries Loadout.skill_magnitude_mult() (INT scaling).
static func fire_skill(combat, id: String, rank: int, trigger: String = "on_use",
        extra: Dictionary = {}) -> Array[Dictionary]:
    var equipped: Array[Dictionary] = ContentDB.loadout([{"id": id, "rank": rank, "stacks": 1,
        "magnitude_mult": Loadout.skill_magnitude_mult()}])
    return _collect_and_run(combat, equipped, trigger, extra)


static func _has_trigger(equipped: Array[Dictionary], trigger: String) -> bool:
    var defs: Dictionary = ContentDB.default_db().get("index", {}).get("effects", {})
    for entry in equipped:
        for reference in entry.get("effects", []):
            var effect: Dictionary = reference if reference is Dictionary \
                else defs.get(String(reference), {})
            if String(effect.get("trigger", "")) == trigger:
                return true
    return false


static func _collect_and_run(combat, equipped: Array[Dictionary], trigger: String,
        extra: Dictionary) -> Array[Dictionary]:
    var ctx: Dictionary = context(combat, extra)
    var modifiers: Array[Dictionary] = Resolver.collect_modifiers(equipped, trigger, ctx)
    if modifiers.is_empty():
        return modifiers
    var inv: Dictionary = Inventory.data()
    inv["effect_cooldowns"] = Resolver.start_cooldowns(inv["effect_cooldowns"], modifiers,
        float(ctx["now"]))
    execute(combat, modifiers, extra)
    return modifiers


## Executes already-collected modifiers (no condition checks).
static func execute(combat, modifiers: Array, extra: Dictionary = {}) -> void:
    var rs: Node = Inventory.run_state()
    for modifier in modifiers:
        var effect_id: String = String(modifier.get("effect_id", modifier.get("id", "")))
        var source: String = String(modifier.get("source", ""))
        match String(modifier.get("operation", "")):
            "heal":
                var stats: Dictionary = Loadout.player_stats()
                var amount: int = Resolver.resolve_amount(modifier, rs.rng)
                rs.heal_player(maxi(0, roundi(float(amount) * float(stats.get("heal_mult", 1.0)))))
            "damage":
                for target in _targets(combat, modifier, extra):
                    if target is Dictionary and int(target["hp"]) > 0:
                        combat.apply_damage(target, Resolver.resolve_amount(modifier, rs.rng),
                            {"source": "effect:" + effect_id, "effect": effect_id,
                                "damage_type": "physical"})
            "apply_status", "set":
                if not modifier.has("status"):
                    continue
                for target in _targets(combat, modifier, extra):
                    var instance_extra := {}
                    if String(modifier["status"]) == "concealed" and combat != null:
                        instance_extra["decoy_pos"] = combat.player.world_position
                    StatusSystem.apply(target, modifier, source, instance_extra)
            "grant_ticks":
                var prefix: String = "skill:" if source.begins_with("skl_") else "item:"
                rs.add_ticks(maxi(0, roundi(float(modifier.get("magnitude", 0)))), prefix + source)
            "cooldown_reduction":
                _reduce_cooldowns(combat, String(modifier.get("stat", "all")),
                    float(modifier.get("magnitude", 0.0)))


## Targets of a modifier: "player" (self), the context target, or enemies of the
## current room within `radius` of extra.origin (default the crawler).
static func _targets(combat, modifier: Dictionary, extra: Dictionary) -> Array:
    match String(modifier.get("target", "self")):
        "self":
            return ["player"]
        "target":
            var target = extra.get("target")
            return [target] if target is Dictionary and int(target.get("hp", 0)) > 0 else []
        "enemies_in_radius":
            if combat == null:
                return []
            var origin: Vector2 = extra.get("origin", combat.player.world_position)
            var radius: float = float(modifier.get("radius", 32.0))
            var result: Array = []
            for foe in combat.enemies().duplicate():
                if int(foe["hp"]) > 0 and Vector2(foe["pos"]).distance_to(origin) \
                        <= radius + float(foe.get("radius", 0.0)):
                    result.append(foe)
            return result
    return []


static func _reduce_cooldowns(combat, key: String, seconds: float) -> void:
    if seconds <= 0.0:
        return
    if combat != null and (key == "melee" or key == "all"):
        combat.player.melee_cooldown = maxf(0.0, combat.player.melee_cooldown - seconds)
    if combat != null and (key == "ranged" or key == "all"):
        combat.player.fire_cooldown = maxf(0.0, combat.player.fire_cooldown - seconds)
    if key == "items" or key == "all":
        Inventory.reduce_active_cooldown(seconds)
    if key == "skills" or key == "all":
        var cooldowns: Dictionary = Inventory.run_state().skill_cooldowns
        for id in cooldowns.keys():
            var left: float = float(cooldowns[id]) - seconds
            if left <= 0.000001:
                cooldowns.erase(id)
            else:
                cooldowns[id] = left
    if combat != null and (key == "dodge" or key == "all"):
        combat.player.dodge_cooldown = maxf(0.0, combat.player.dodge_cooldown - seconds)
