extends RefCounted
## Deterministic loot rolls over res://data/content/loot_tables.json.
## The same (table, seed, depth, room, salt, exclusions) always yields the same ids.
## Algorithm per roll: empty_chance check -> pick a rarity from the depth curve x table
## multipliers (only rarities that still have an eligible record) -> pick a record of
## that rarity weighted by its source weight x optional loot_weight.

## Highest band of rarity_weights_by_depth whose min_depth <= depth.
static func rarity_weights(db: Dictionary, depth: int) -> Dictionary:
    var chosen: Dictionary = {}
    for band in db.get("loot", {}).get("rarity_weights_by_depth", []):
        if int(band.get("min_depth", 1)) <= depth:
            chosen = band.get("weights", {})
    return chosen

## Every record the table could drop at `depth`, as {"id", "rarity", "weight"},
## sorted by id. Applies min_depth, the table's min/max rarity, its sources and
## exclude list, plus `extra_exclude` (e.g. items the player already owns).
static func eligible_candidates(db: Dictionary, table_id: String, depth: int,
        extra_exclude: Array = []) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var loot: Dictionary = db.get("loot", {})
    var table: Dictionary = loot.get("tables", {}).get(table_id, {})
    if table.is_empty():
        return result
    var order: Array = loot.get("rarity_order", [])
    var low: int = order.find(String(table.get("min_rarity", order[0] if not order.is_empty() else "")))
    var high: int = order.find(String(table.get("max_rarity", order[-1] if not order.is_empty() else "")))
    var excluded: Array = Array(table.get("exclude", [])) + extra_exclude
    for source in table.get("sources", []):
        var from: String = String(source.get("from", ""))
        for entry in db.get(from, []):
            if not entry is Dictionary:
                continue
            var record_id: String = String(entry.get("id", ""))
            if excluded.has(record_id) or int(entry.get("min_depth", 1)) > depth:
                continue
            if source.has("kind") and String(entry.get("kind", "")) != String(source["kind"]):
                continue
            if source.has("slot") and String(entry.get("slot", "")) != String(source["slot"]):
                continue
            if source.has("tag") and not Array(entry.get("tags", [])).has(String(source["tag"])):
                continue
            var rank: int = order.find(String(entry.get("rarity", "")))
            if rank < 0 or rank < low or rank > high:
                continue
            var already := false
            for existing in result:
                if String(existing["id"]) == record_id:
                    already = true
                    break
            if already:
                continue
            result.append({"id": record_id, "rarity": String(entry["rarity"]),
                "weight": float(source.get("weight", 1.0)) * float(entry.get("loot_weight", 1.0))})
    result.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
    return result

## Stable 31-bit seed from every input that should change a roll.
static func seed_for(table_id: String, seed_value: int, depth: int, room_id: int, rng_salt: int) -> int:
    var mixed: int = table_id.hash() & 0x7FFFFFFF
    for part in [seed_value, depth, room_id, rng_salt]:
        mixed = ((mixed * 1000003) ^ (int(part) & 0x7FFFFFFF)) & 0x7FFFFFFF
    return mixed

## Rolls `table_id` and returns the dropped record ids (possibly empty).
static func roll(db: Dictionary, table_id: String, seed_value: int, depth: int,
        room_id: int, rng_salt: int = 0, extra_exclude: Array = []) -> Array[String]:
    var drops: Array[String] = []
    var loot: Dictionary = db.get("loot", {})
    var table: Dictionary = loot.get("tables", {}).get(table_id, {})
    if table.is_empty():
        push_warning("Unknown loot table: " + table_id)
        return drops
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_for(table_id, seed_value, depth, room_id, rng_salt)
    var rolls_value = table.get("rolls", 1)
    var rolls: int = int(rolls_value) if not rolls_value is Dictionary else rng.randi_range(
        int(rolls_value.get("min", 0)), int(rolls_value.get("max", 0)))
    var curve: Dictionary = rarity_weights(db, depth)
    var multipliers: Dictionary = table.get("rarity_multipliers", {})
    var order: Array = loot.get("rarity_order", [])
    var unique: bool = bool(table.get("unique", true))
    for _roll in range(rolls):
        var empty_roll: float = rng.randf()
        if empty_roll < float(table.get("empty_chance", 0.0)):
            continue
        var blocked: Array = extra_exclude.duplicate()
        if unique:
            blocked.append_array(drops)
        var candidates: Array[Dictionary] = eligible_candidates(db, table_id, depth, blocked)
        var rarity_weight: Dictionary = {}
        for candidate in candidates:
            var rarity: String = String(candidate["rarity"])
            rarity_weight[rarity] = float(curve.get(rarity, 0.0)) * float(multipliers.get(rarity, 1.0))
        var rarity_options: Array = []
        var rarity_weights_list: Array = []
        for rarity in order:
            if float(rarity_weight.get(rarity, 0.0)) > 0.0:
                rarity_options.append(rarity)
                rarity_weights_list.append(float(rarity_weight[rarity]))
        var picked_rarity: int = _weighted_index(rng, rarity_weights_list)
        if picked_rarity < 0:
            continue
        var pool: Array = []
        var pool_weights: Array = []
        for candidate in candidates:
            if String(candidate["rarity"]) == String(rarity_options[picked_rarity]):
                pool.append(candidate["id"])
                pool_weights.append(float(candidate["weight"]))
        var picked: int = _weighted_index(rng, pool_weights)
        if picked >= 0:
            drops.append(String(pool[picked]))
    return drops

static func _weighted_index(rng: RandomNumberGenerator, weights: Array) -> int:
    var total := 0.0
    for weight in weights:
        total += maxf(0.0, float(weight))
    if total <= 0.0:
        return -1
    var point: float = rng.randf() * total
    for i in range(weights.size()):
        point -= maxf(0.0, float(weights[i]))
        if point < 0.0:
            return i
    return weights.size() - 1
