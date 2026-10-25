# Encounter Rules — budgets, composition, spawning

- **Status:** **Implemented** (Wave 2C) in [`enemy_system.gd`](../../game/scripts/enemy_system.gd) (`compose_encounter`, `generate_encounter`) with settings under `encounters` in [`enemies.json`](../../game/data/enemies.json); deviations in [§0](#0-implementation-status-wave-2c). §1 describes the replaced prototype.
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 4 (encounter budgets, composition, spawn constraints, validation)
- **Related:** [Enemy tiers](ENEMY_TIERS.md) · [Procedural generation](PROCEDURAL_GENERATION.md) · [Collapse system](COLLAPSE_SYSTEM.md) · [Combat and RPG](COMBAT_AND_RPG.md)

## 0. Implementation status (Wave 2C)

- **Implemented:** the §3 budget formula and intensity roll; R1–R6, R9, R10 and R12; the §4.1 algorithm (pressure role first, then weighted fill; rule-5 fallback); spawn constraints S1–S3, S5, S6 and S9; §6 re-entry (positions reset to spawn points, HP kept); boss pool by depth (ENEMY_TIERS §7). `generate_encounter(catalogue, kind, seed, room_id, blocked, depth = 1, links = {})`: the same `(floor_seed, depth, room_id, links)` always gives the same enemies.
- **Budget accuracy:** every normal room lands within **±10 %** of its budget (`encounters.budget.tolerance`), tighter than T6. A fill prefers picks after which the remaining slots can still reach the window; if a fill still misses, it is redrawn from the same RNG stream (up to `budget.attempts` = 12) and the closest fill is kept. Tests check 20 seeds × 8 rooms × depths 1–6.
- **Elites:** normal rooms roll `elite_chance` per band (0 / 0 / 10 % / 15 % / 20 %); the elite is picked first at ×2 threat. `elite` rooms (kind multiplier 1.5) always have exactly one elite. The floor generator does not emit `elite` rooms yet (2E).
- **Spawns:** ≥ 96 px from every linked portal centre (ranged ≥ 120 px) instead of the old 82 px from cell (12, 12); without links (tests) ≥ 82 px from the true midpoint (192, 192). Bosses spawn at (192, 192); escorts ≥ 48 px from the boss. Actors with radius ≥ 8 need clearance (`can_occupy` at the cell centre) and a clearance path from the portals; a second pass accepts plain-grid reachability if no strict spot exists (those actors path with clearance where possible and slide along obstacles otherwise). Boss rooms cap obstacles at `boss_obstacle_cap` (24).
- **Activation:** 0.6 s dormancy on every room entry (`encounters.dormancy`, applied by Combat on `Events.room_entered`), first cooldown 0.4–1.0 s, then the wind-up: the earliest hit is about 1.35 s after entry, as specified.
- **Not implemented:** R7 (introduction rule; needs per-run "seen" tracking), R8 (trap rooms and dart idols), R11 (biome affinity), the zoner door-lane rule in S3, S4 clearance *along the path* beyond the reachability flood, S7 and S8. Escort composition uses the budget (the fixed "1 scavenger + 1 spitting rat" escort is gone).
- **Tests:** `tests/enemies_test.gd` covers T1–T5, T7 (20 seeds), T8, T9 and T10; `tests/enemy_combat_test.gd` covers T11 and the telegraph and dormancy timing.

## 1. Prototype behaviour before Wave 2C

- **Tables:**
  - `normal` draws **2–4** enemies uniformly from the pool `[rat_scavenger, rat_scavenger, spitting_rat, hulking_rat]`, so scavengers are twice as likely.
  - `boss` is fixed: `[armored_brute, rat_scavenger, spitting_rat]`.
  - `start`, `guild_hall` and `exit` are empty.
- **Seed:** `seed × 73 + room_id × 10211 + 41`. The encounter is generated once, when the room is first loaded, and persists. Killed enemies stay dead.
- **Placement:**
  - Up to 150 attempts per enemy, on cells 2–21.
  - The cell must be walkable and pass `can_occupy(radius)`.
  - It must be **≥ 82 px from the centre of cell (12, 12)**, and BFS must reach (12, 12).
  - It must keep a gap of the two radii + 11 px from other enemies.
  - An enemy that cannot be placed is skipped with a warning.
- **Activation:** enemies act immediately. Their first attack cooldown is a random 0.2–0.8 s.
- **Known gap:** the crawler enters about 21 px inside a door, but the spawn distance is measured from the room centre. An enemy can therefore spawn next to the door the crawler walks through.

**Threat today:** with the v1 threat values (scavenger 2, spitter 3, hulking 4) the pool averages 2.75 per enemy. A normal room therefore holds 5.5–11 threat points, averaging about 8. The v1 depth-1 standard budget is set to match.

## 2. Threat points

Each archetype has a `threat` value in [ENEMY_TIERS.md §5](ENEMY_TIERS.md#5-starter-roster-normal-archetypes). Threat roughly means "how much of the crawler's attention this enemy takes".

| Modifier | Threat |
| --- | --- |
| Base archetype | `threat` (1–6 at bands I–III) |
| Veteran (per band above `min_band`) | +1 |
| Elite | × 2 (after veteran) |
| Summons (`rat_pup`) | 0 (their cost is inside the summoner's) |
| Trap actors | counted in a separate trap budget (§4, R8) |
| Boss | not budgeted; it is the room's fixed centrepiece |

## 3. Threat budget by depth

```
budget(room) = round((5 + 3 × depth) × intensity × kind_multiplier)

intensity        light 0.7 (25 %) · standard 1.0 (55 %) · heavy 1.3 (20 %), rolled per room
kind_multiplier  normal 1.0 · elite 1.5 · trap 0.5 · boss escort 0.5 (always standard intensity)
round            half away from zero (GDScript round())
```

| Depth (band) | Light | **Standard** | Heavy | Elite room (std) | Boss escort | Max enemies (non-summon) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 (I) | 6 | **8** | 10 | 12 | 4 | 4 |
| 2 (I) | 8 | **11** | 14 | 17 | 6 | 4 |
| 3 (II) | 10 | **14** | 18 | 21 | 7 | 5 |
| 4 (II) | 12 | **17** | 22 | 26 | 9 | 5 |
| 5 (III) | 14 | **20** | 26 | 30 | 10 | 6 |
| 6 (III) | 16 | **23** | 30 | 35 | 12 | 6 |

Bands IV and V use the same formula with maximum enemy counts of 7 and 8. Config: `encounters.budget.base` 5, `encounters.budget.per_depth` 3, `encounters.intensity` (weights and multipliers), `encounters.kind_multiplier`.

**Collapse interaction:** the clock is transition-based, so fight length never costs ticks. A heavy room and a light room cost the same 2 ticks. The door preview does not reveal intensity, so heavy rooms carry better drops (§7) to make the risk worth it.

## 4. Composition rules

These rules apply to normal, elite and trap rooms. A candidate that would break a rule is rejected and the next weighted pick is tried.

| # | Rule |
| --- | --- |
| R1 | **Count:** at least 2 non-summon enemies in normal rooms; at most the band maximum (§3). |
| R2 | **Band eligibility:** `min_band ≤ band(depth) ≤ max_band`. |
| R3 | **Role caps per room:** ranged (including artillery) ≤ 2 in band I and ≤ 3 from band II; summoner ≤ 1; support ≤ 1; zoner ≤ 1 in bands I–II and ≤ 2 from band III; tank ≤ 1 in bands II–III; charger ≤ 2. |
| R4 | **Pressure:** a room with ≥ 3 enemies contains ≥ 1 chaser or charger. |
| R5 | **No all-ranged rooms** in bands I–II. |
| R6 | **Support needs company:** a support enemy needs ≥ 2 other non-support enemies. |
| R7 | **Introduction:** the first time an archetype appears in a run (RunState tracks this), that room is forced to light or standard intensity and contains exactly 1 of the new archetype. |
| R8 | **Trap rooms:** 2 + ⌊depth / 3⌋ dart idols (maximum 4), on a separate trap budget, plus a 0.5× enemy budget. The enemy part may be empty if the remaining budget is under 4. |
| R9 | **Elite rooms:** exactly 1 elite (2 from band IV), picked from eligible non-trap, non-summon archetypes, plus normal fill. |
| R10 | **Repetition:** at most 3 of the same archetype per room, not counting summons. |
| R11 | **Biome affinity:** each archetype's base pick weight is multiplied by its `biome_affinity[biome]` (default 1.0; listed affinities 2.0). |
| R12 | **Boss rooms:** the boss is fixed from the depth's boss pool ([ENEMY_TIERS.md §7](ENEMY_TIERS.md#7-bosses)). The escort is filled with the budget above, with no summoner or support in band I. |

### 4.1 Algorithm (deterministic)

1. Seed the RNG with `floor_seed × 73 + room_id × 10211 + 41` (the existing formula, with the floor seed in place of the run seed).
2. Roll intensity, then compute the budget and the eligible pool (R2, R11).
3. If R7 applies, place the new archetype first.
4. Repeat: draw a weighted candidate. Accept it if its threat ≤ the remaining budget and rules R1–R10 still hold. Stop when the remaining budget is below the cheapest eligible threat, or the count cap is reached.
5. If fewer than 2 enemies were placed, add the cheapest eligible chaser even if it overspends by up to 2. This is the only overspend allowed.
6. Place each enemy with the spawn constraints in §5. If one cannot be placed, drop it and re-draw once from the remaining budget.

## 5. Spawn constraints

| # | Constraint | Status |
| --- | --- | --- |
| S1 | Cell in 2–21 on both axes, walkable, `can_occupy(radius)` | implemented |
| S2 | Distance from other spawns ≥ the two radii + 11 px | implemented |
| S3 | ≥ **96 px from every linked portal centre** (replaces "≥ 82 px from the room centre"). Ranged and artillery ≥ 120 px. Zoners ≥ 64 px from portals and door lanes. | implemented (zoner lane rule: no) |
| S4 | Clearance `k` for large actors ([PROCEDURAL_GENERATION.md §5](PROCEDURAL_GENERATION.md#5-room-interior-rules-v1)) at the spawn and along its path | implemented at the spawn; path via the reachability flood |
| S5 | Reachable from **every linked portal**, not only from the centre, with its clearance | implemented |
| S6 | The boss spawns at the centre (the midpoint 192, 192), and escorts spawn ≥ 48 px from the boss | implemented |
| S7 | Trap actors sit on wall-adjacent cells (column or row 1 or 22) outside the door lanes and face inward. Their lane must not cover portal rows or columns 11–12. | new |
| S8 | No spawn on hazard cells | new |
| S9 | **Activation:** 0.6 s dormancy after the crawler enters, then a first cooldown of 0.4–1.0 s, then the wind-up. The earliest possible hit is about 1.35 s after entry. | implemented |

Spawn positions depend only on `(floor_seed, room_id)`. They never depend on the door the crawler used, so encounters stay identical whatever route is taken.

## 6. Re-entry and persistence

- An encounter is generated once and persists for the floor (as implemented). With D-07 door locks ([COMBAT_AND_RPG.md §9](COMBAT_AND_RPG.md#9-d-07--door-lock-and-room-persistence)), a room is normally left only once it is cleared.
- If the crawler leaves during grace with enemies alive, those enemies keep their HP and statuses. Their positions reset to their spawn cells on re-entry. Statuses keep ticking (they are not paused).
- There are no respawns and no wandering reinforcements in the slice.

## 7. Rewards

Drops roll the Wave 1B loot tables with `loot_rules.roll(db, table_id, seed, depth, room_id, salt)` ([CONTENT_RULES.md §7](CONTENT_RULES.md#7-loot-tables-loot_tablesjson)). Rarity follows the 1B `rarity_weights_by_depth` curve (common to legendary, with bands from depths 1, 3, 5 and 8), and each table's `rarity_multipliers` adjust it. This page decides **which table rolls when**, and the room-intensity adjustments.

| Source | XP | Drop |
| --- | --- | --- |
| Normal enemy | `xp` from data (veteran ×1.5 per band) | none individually |
| Normal room clear | — | `room_normal_clear`: 1 roll, `empty_chance` 0.55, mostly consumables. **Proposed:** light rooms +0.10 empty chance, heavy rooms −0.15 |
| Elite enemy | ×2.5 | **guaranteed** 1 item. **Proposed** new table `elite_kill`: 1 roll, empty chance 0, minimum uncommon |
| Elite room clear | — | +1 collapse tick ([COLLAPSE_SYSTEM.md §5](COLLAPSE_SYSTEM.md#5-room-type-policy-table)) |
| Treasure chest | — | `treasure_room`: 2 distinct rewards, skewed toward better rarities |
| Boss | boss `xp` | **Boss loot box:** `boss_kill`, 2 distinct rewards that are never common; +1 roll at CHA mod ≥ +3 (`Events.loot_box_opened`, proposed) |
| Floor start | — | `floor_start`: one cheap consumable |
| Guild hall | — | `guild_hall_shop`: 4 offers (shop pricing in 2E) |
| Summons, splitting copies, invulnerable traps | 0 | none |

Use a distinct `salt` for each roll source in the same room (`"clear"`, `"elite:<instance_id>"`, `"chest"`), so that rolls stay independent and deterministic.

## 8. Validation tests engineers must write

Rules marked *fail* must break CI. Rules marked *report* print statistics and fail only when far outside the band.

| # | Test | Type |
| --- | --- | --- |
| T1 | Schema v2: every enemy has `role`, `rank`, `min_band`, `threat`, and each attack has `windup_s`, `recovery_s` and `telegraph`; enums are valid | fail |
| T2 | Wind-up ≥ the band minimum at `min_band`. Boss heavy and area attacks ≥ 0.5 s | fail |
| T3 | Hostile projectile speed ≤ the band cap; max non-crit hit ≤ the band cap; HP and AC within the band range | fail (HP/AC: report) |
| T4 | XP per threat point within the band range | fail |
| T5 | Determinism: same `(floor_seed, depth, room_id)` gives identical ids and positions | fail |
| T6 | Budget: spent ≤ budget + 2 always; spent ≥ 60 % of budget in ≥ 95 % of 1,000 sampled rooms per depth | fail / report |
| T7 | Composition rules R1–R12 hold for 1,000 rooms per depth 1–6 | fail |
| T8 | Spawn constraints S1–S8 hold for every placed enemy | fail |
| T9 | Difficulty curve: mean spent threat per normal room rises strictly with depth 1–6 over 200 seeds | fail |
| T10 | Boss rooms contain exactly 1 `rank: boss`, and the escort threat is ≤ its budget + 2 | fail |
| T11 | Summons give 0 XP and no drops, and die with their summoner (AI unit test) | fail |
| T12 | Room-clear condition ignores `required_for_clear: false` actors; every required enemy is reachable from every portal | fail |
| T13 | Introduction rule: in a simulated run, the first appearance of each archetype has count 1 | fail |
| T14 | Damage sanity: a standard room at the reference crawler HP ([ENEMY_TIERS.md §4](ENEMY_TIERS.md#4-stat-guardrails-per-band)) lasts ≥ 6 s with every enemy attacking on cooldown and hitting | report |

The existing smoke tests (normal rooms hold 2–4 enemies, boss rooms ≥ 2, spawns walkable and reachable) stay. The 2–4 check becomes "2 ≤ count ≤ band maximum".

## 9. Telemetry

Recorded per room: depth, kind, intensity, budget, threat spent, archetypes, time to clear, damage taken, crawler HP on entry and exit, statuses applied, and whether the room was cleared flawlessly.

**Tuning targets:** median clear time 12–25 s for standard rooms and 30–60 s for bosses; median damage taken per standard room ≤ 20 % of max HP in band I and ≤ 25 % in bands II–III.

## 10. Open questions

1. Should the door preview hint at intensity (for example, noise or a glow)? (Default: no. The surprise is offset by the rewards.)
2. Should threat budgets also scale with crawler level, a rubber-band? (Default: no; depth only.)
3. Should cleared rooms ever spawn a wandering patrol during grace? (Default: no.)
4. Should elite rooms show the elite's modifier on the door? (Default: no; it shows on room entry, during dormancy.)
5. Should summoner caps be per room (6 pups maximum) as well as per summoner (4)? (Default: yes, both.)
