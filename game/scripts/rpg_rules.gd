extends RefCounted
## Six-ability d20 prototype influenced by the D&D 5e SRD's basic conventions.
## Not a claim of complete tabletop rules compatibility.
const ABILITIES := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
# Cumulative XP to reach levels 1..20.
const XP_THRESHOLDS := [0, 300, 900, 2700, 6500, 14000, 23000, 34000,
    48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000,
    225000, 265000, 305000, 355000]

static func modifier(score: int) -> int:
    return int(floorf((float(score) - 10.0) / 2.0))

static func level_for_xp(total_xp: int) -> int:
    var level := 1
    for index in range(XP_THRESHOLDS.size()):
        if total_xp >= int(XP_THRESHOLDS[index]):
            level = index + 1
    return level

static func next_level_xp(level: int) -> int:
    return int(XP_THRESHOLDS[clampi(level, 1, 19)]) if level < 20 else -1

static func proficiency(level: int) -> int:
    return 2 + int(floorf(float(clampi(level, 1, 20) - 1) / 4.0))

static func armor_class(scores: Dictionary, bonus: int = 0) -> int:
    return 10 + modifier(int(scores.get("DEX", 10))) + bonus

static func attack_bonus(scores: Dictionary, ability: String, level: int, proficient: bool = true) -> int:
    return modifier(int(scores.get(ability, 10))) + (proficiency(level) if proficient else 0)

static func roll_to_hit(rng: RandomNumberGenerator, bonus: int, target_ac: int) -> Dictionary:
    var d20: int = rng.randi_range(1, 20)
    return {"d20": d20, "total": d20 + bonus,
        "critical": d20 == 20, "hit": d20 == 20 or (d20 != 1 and d20 + bonus >= target_ac)}

static func roll_damage(rng: RandomNumberGenerator, die: int, bonus: int, critical: bool) -> int:
    var total: int = rng.randi_range(1, maxi(1, die))
    if critical:
        total += rng.randi_range(1, maxi(1, die))
    return maxi(1, total + bonus)

static func player_base_scores() -> Dictionary:
    return {"STR": 14, "DEX": 14, "CON": 14, "INT": 10, "WIS": 12, "CHA": 10}

static func player_hp_at_level(level: int, scores: Dictionary) -> int:
    var con_mod: int = modifier(int(scores.get("CON", 10)))
    return maxi(1, 10 + con_mod + (clampi(level, 1, 20) - 1) * maxi(1, 6 + con_mod))

static func player_progression(total_xp: int, scores: Dictionary) -> Dictionary:
    var level: int = level_for_xp(total_xp)
    return {"level": level, "xp": total_xp, "next_xp": next_level_xp(level),
        "proficiency": proficiency(level), "max_hp": player_hp_at_level(level, scores),
        "ac": armor_class(scores)}
