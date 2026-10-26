# Procedural Generation — floors, rooms and depth scaling

- **Status:** Implemented with deviations. §1 is the prototype base. Wave 2A added room counts by depth (§3, `run.rooms_by_depth`). Wave 2E added special rooms (§4), the room interior rules (§5, partly), the feasibility re-roll (§6, partly) and the full map (§7). See [Implementation status](#implementation-status-wave-2e). Code: [`floor_generator.gd`](../../game/scripts/floor_generator.gd), [`room_contents.gd`](../../game/scripts/room_contents.gd), [`enemy_system.gd`](../../game/scripts/enemy_system.gd), [`floor_map.gd`](../../game/scripts/ui/floor_map.gd).
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 1A
- **Decisions covered:** D-06 (floor size, room shapes, branch/loop distribution). Uses D-13 and D-16 (accepted).
- **Related:** [Collapse system](COLLAPSE_SYSTEM.md) · [Encounter rules](ENCOUNTER_RULES.md) · [Biomes](BIOMES_AND_TILESETS.md) · [Game design](GAME_DESIGN.md)

## Implementation status (Wave 2E)

- **Signature:** `Generator.generate(seed, count, {depth, config, budget})`. With no options it reads `prototype_rules.json`, so a plain `generate(seed, 22)` equals what Game builds for floor 1. The returned floor adds `depth`, `spine_length`, `specials {kind: [ids]}`, `relaxations [{kind, level, note}]`, `mandatory_route`, `mandatory_route_cost`, `budget`, `generation_seed` and `feasibility {ok, attempt, attempts, checks}`.
- **Geometry unchanged:** every new draw comes after the prototype's guild-hall draw, so existing seeds keep their rooms and links. The determinism test checks the kind-masked signature for seed 424242. Room kinds do change: seed 424242 gains a treasure room (11), and its guild hall moves from room 13 (reachable only through the boss room) to room 18.
- **Counts (§4.1), deviation:** `generation.special_rooms.counts_by_depth` defaults to **1 treasure** on every floor (not 1 + ⌊depth / 3⌋), **elite 0 / 1 / 1 / 1 / 1 / 1** (capped at 1, not ⌊depth / 2⌋), and trap and shrine as in the table.
- **Placement (§4.2):** implemented in assignment order, with relaxation levels 0 (all rules), 1 (no preferences), 2 (no adjacency rules 5–7) and 3 (count − 1). Every relaxation is logged in `floor.relaxations`. **Deviation (guild hall):** the prototype pick is kept unless it is within 2 hops of the start, on the cheapest route, or costs more than `collapse.budget.guild_max_ratio` (50 %) of the budget to reach. In those cases it is re-picked with one extra draw; this happens for about half of all seeds. An elite, trap or shrine that would land on the cheapest route is moved to another candidate.
- **Interiors (§5):** obstacle caps per kind come from `room_obstacle_caps` (13 for safe kinds, trap 20, elite 30). **Boss rooms keep 38** until the clearance check (F8) exists. Treasure rooms have one chest, shrine rooms one shrine, and the guild hall a rest station and a shop sign. These features stand on the always-open staging ring and block their cell. Trap rooms have 2–4 pressure plates, 1–2 of them tick drains and always at least one spike; they are not entities with their own AI. Hazard cells are not implemented. Feature draws use their own RNG stream (`seed + room × 7919 + 83492`).
- **Feasibility (§6):** implemented checks are F1/F2 (a route exists), F3 (budget − route ≥ `min_slack`, budget ≤ `max_start_ticks` 70), F5 (no elite, trap, shrine or guild hall on the cheapest route) and the guild-hall reachability limit. A failed floor re-rolls with `seed + k × 104729` (`generation.feasibility`), up to 20 attempts. Exhausting them calls `push_error` and falls back to attempt 0. F4 is covered by the relaxation log. F7–F9 are not implemented.
- **Not implemented:** `link_probability` (§2.3; every adjacency is still linked at every depth) and the topology report (§9.5). Biomes per depth (§8) landed in Wave 3B.
- **Map (§7), deviation:** the full map (M) shows visited rooms filled with their kind colour, scouted rooms as outlines (boss, exit and guild hall with their icon, other specials as `?`), links touching a visited room, and the net cost of the current room's doors. The exit appears only once it is discovered (visited or scouted), not from floor start, and the boss is not pre-revealed. The cheapest-path-to-exit overlay is not drawn. The minimap only gains kind colours.

## 1. Current prototype behaviour

### 1.1 Floor graph (`floor_generator.gd`)

1. `count = max(8, requested)`. The default request is 22 (`room_count`).
2. Room 0 is placed at grid (0, 0).
3. **Spine:** `spine = min(max(round(0.35 × count), 5), count − 3)` steps. Each step moves **east or south** with equal probability, so the spine is monotone and never self-intersects. Rooms 1…spine are spine rooms.
4. **Boss** = room `spine − 1`; **exit** = room `spine`. The exit is always adjacent to the boss.
5. **Side growth:** the generator repeatedly picks a random empty cell that is 4-adjacent to any existing room, until `count` rooms exist.
6. **Links:** *every* pair of 4-adjacent occupied cells gets a reciprocal door (`neighbors` uses N/E/S/W → room id). This automatically creates loops.
7. **Guild hall:** one random room among ids `spine + 1 … count − 1`, so it is never on the spine.
8. **Output:** `{seed, rooms, start_id, boss_id, exit_id, guild_id}`. `path_between()` is a BFS by hop count. `signature()` is the determinism fingerprint used by tests.

For the default 22 rooms: spine 8, boss id 7, exit id 8, 13 side rooms, 1 guild hall, 18 normal rooms. The start → boss distance is always 7 hops, because the spine is a shortest path.

### 1.2 Room interiors (`room_contents.gd`)

- The interior is a fixed 24×24 grid of 16 px cells (D-16). Door portals are the two middle cells of each linked side: cells 11–12 on the north (row 0), south (row 23), west (column 0) and east (column 23) edges.
- **Obstacle candidates** are cells 2–21 on both axes, excluding:
  - the 7×7 staging square at the centre (|x − 12| ≤ 3 and |y − 12| ≤ 3);
  - door approach lanes: columns 9–14 within 4 cells of the north and south walls, and rows 9–14 within 4 cells of the west and east walls.
- The candidates are shuffled with a seeded Fisher–Yates shuffle (`seed + room_id × 7919 + 39317`). Cells are then added one at a time, and a cell is **rejected if BFS from cell (12, 12) can no longer reach every linked portal**.
- **Density** is `obstacle_count` (38) for every room kind. `start`, `guild_hall` and `exit` rooms are capped at 13. **Boss rooms use the full 38.**
- Each obstacle is rubble (63 %) or a pillar (37 %). Both block movement, projectiles and LOS.

### 1.3 Encounter placement (`enemy_system.gd`)

- The RNG seed is `seed × 73 + room_id × 10211 + 41`.
- Tables come from `enemies.json`. `normal` picks 2–4 from a weighted pool, `boss` is fixed, and safe kinds are empty.
- Each enemy gets up to 150 placement attempts. A cell from 2–21 is accepted if it is walkable, `can_occupy(radius)` passes, it is ≥ 82 px from the centre of cell (12, 12), BFS reaches (12, 12), and it keeps a gap of the two radii + 11 px from other spawns. An enemy that still cannot be placed is skipped with a warning.

## 2. Floor graph rules v1

The existing algorithm stays. The changes below are **append-only to the RNG sequence**: new random draws happen *after* the guild-hall pick, so depth-1 layouts for an existing seed keep their geometry and guild hall.

1. **Seed per floor:** `floor_seed` as defined in [GAME_DESIGN.md §3.1](GAME_DESIGN.md#31-run).
2. **Room count:** from the depth table in §3.
3. **Tree edges and optional links:**
   - Record the growth parent of each side room. Tree edges (spine plus growth parents) are always linked.
   - Other adjacencies are linked with probability `link_probability(depth)`. This is 1.0 at depths 1–2, which matches today's behaviour, and 0.75 from depth 3, which gives more dead ends and fewer trivial loops.
4. **Special kinds:** assigned after the guild hall (§4).
5. **Topology targets** (measured over 200 seeds, not enforced per seed):
   - dead ends (degree 1) are 15–30 % of rooms;
   - cycle count (edges − rooms + 1) is ≥ 2 at 22 rooms and ≥ 5 at 44 rooms;
   - the spine is 30–40 % of rooms.

## 3. Depth scaling — D-06

**Proposed default (D-06):** the test range is **22–44 rooms for the six slice floors**, and **50–80 for depth 7+**. The roadmap's original 40–80 hypothesis is therefore first tested at depths 5–9. Rooms stay single-cell 24×24 in the slice.

| Depth | Band | Rooms | Spine | `link_probability` | Biome | Start ticks (see [collapse](COLLAPSE_SYSTEM.md#4-starting-budget-and-depth-scaling)) |
| ---: | :---: | ---: | ---: | ---: | --- | ---: |
| 1 | I | 22 | 8 | 1.00 | stone_crypt | 26 |
| 2 | I | 26 | 9 | 1.00 | stone_crypt | 30 |
| 3 | II | 30 | 11 | 0.75 | fungal_cavern | 36 |
| 4 | II | 34 | 12 | 0.75 | fungal_cavern | 40 |
| 5 | III | 40 | 14 | 0.75 | flooded_catacombs | 46 |
| 6 | III | 44 | 15 | 0.75 | flooded_catacombs | 50 |
| 7 / 8 / 9 | IV | 50 / 56 / 62 | — | 0.70 | maintenance_tunnels → bone_foundry | formula |
| 10+ | V | 70, then 80 (cap) | — | 0.70 | bone_foundry | formula |

Config shape: `generation.depth_table[]` with the fields `{depth, room_count, link_probability, biome}`. Depths beyond the table reuse its last row.

## 4. Special room kinds

| Kind | Purpose | Contents | Locks? | Collapse (see [§5 of collapse](COLLAPSE_SYSTEM.md#5-room-type-policy-table)) |
| --- | --- | --- | --- | --- |
| `start` | Spawn | none; stairs-up decal | no | 0 |
| `normal` | Combat | encounter from the budget | yes | 2 |
| `boss` | Floor objective | boss + escort | yes | 3 |
| `exit` | Descend | stairs down; sealed until the boss dies | no | 1 |
| `guild_hall` | Safe service hub | heal, services (2E), time grant | no | 0, +3 |
| `treasure` | Loot | 1 chest, which rolls the 1B `treasure_room` loot table (2 rewards skewed toward better rarities); no enemies | no | 2 |
| `trap` | Hazard puzzle | 2–4 trap entities + optional light encounter (0.5× budget); up to 2 tick-drain plates | only with hostiles | 1 |
| `shrine` | Risk/reward trade | 1 shrine: HP → ticks, or HP → a random passive | no | 1 |
| `elite` | Hard fight | encounter at 1.5× budget, including ≥ 1 elite | yes | 3, +1 on clear |

### 4.1 Counts per floor

| Kind | Formula | D1 | D2 | D3 | D4 | D5 | D6 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| guild_hall | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| treasure | 1 + ⌊depth / 3⌋ | 1 | 1 | 2 | 2 | 2 | 3 |
| elite | ⌊depth / 2⌋ | 0 | 1 | 1 | 2 | 2 | 3 |
| trap | depth ≥ 2: 1 + ⌊(depth − 1) / 4⌋ | 0 | 1 | 1 | 1 | 2 | 2 |
| shrine | depth ≥ 3: 1 | 0 | 0 | 1 | 1 | 1 | 1 |
| normal | remainder | 17 | 19 | 21 | 24 | 29 | 31 |

### 4.2 Placement constraints (in assignment order)

1. **Every special kind goes on side rooms only** (ids > spine), as the guild hall already does. This is never relaxed, because it keeps the mandatory route made of normal rooms ([COLLAPSE_SYSTEM.md §9](COLLAPSE_SYSTEM.md#9-generator-feasibility-requirements)).
2. **guild_hall:** ≥ 2 hops from the start. The rest is as implemented.
3. **treasure:** prefer dead ends. Never adjacent to the start.
4. **elite:** ≥ 3 hops from the start. Rooms adjacent to a treasure room get 2× weight, which makes guarded vaults.
5. **trap:** never adjacent to the guild hall. Never a dead end, because a trap room should be a shortcut, not a cul-de-sac.
6. **shrine:** never adjacent to another special room.
7. **No two specials of the same kind may be adjacent.**
8. **Relaxation order** when constraints cannot be met: drop preferences (dead end, 2× weight), then adjacency rules (5–7), then reduce the count of the kind by 1 and log it. Telemetry records every relaxation.

## 5. Room interior rules v1

| Kind | Obstacle density | Hazard cells (biome) | Notes |
| --- | ---: | ---: | --- |
| normal | 38 | band I: 0 · band II: up to 6 · band III+: up to 12 | as implemented, plus hazards |
| elite | 30 | band II+: up to 8 | more open space for a harder fight |
| boss | **24** (prototype: 38) | 0 | must satisfy boss-radius clearance (below) |
| trap | 20 | trap entities instead | trap lanes line up with walls |
| start / guild_hall / exit / treasure / shrine | 13 | 0 | as implemented for start, guild hall and exit |

- **Hazard cells** do not block movement or projectiles. They must avoid the staging square, the door lanes and portal cells. Each connected hazard patch is ≤ 6 cells, and the crawler must always have a hazard-free path between portals.
- **Clearance for large actors:** a spawn cell and the route to the centre must have free cells within Chebyshev radius `k = ceil((radius − 7) / 16)` around every step. That gives `k = 0` for radius ≤ 7 (current rats), `k = 1` for radius 8–23 (hulking rat 9, brute 14), and `k = 2` for radius 24–39. A boss room's obstacle generation rejects any obstacle that breaks the boss's clearance path from its spawn to the centre and to every portal.
- **Props** are chosen by the biome's weights ([BIOMES_AND_TILESETS.md](BIOMES_AND_TILESETS.md)). Non-blocking decals are unlimited and do not affect navigation.

## 6. Feasibility checks

The generator runs every check. A failing floor is **re-rolled deterministically**: attempt *k* uses `floor_seed + k × 104729`, with at most 20 attempts. Exhausting all 20 is an error. CI fails, and a release build falls back to attempt 0 and logs the failure.

| # | Check | Implemented? |
| --- | --- | --- |
| F1 | Graph connected; a start → exit path exists | path test exists (smoke test, 8 seeds) |
| F2 | A start → boss → exit path exists on the linked graph after `link_probability` | new |
| F3 | Collapse budget minus the mandatory route cost is ≥ `min_slack` ([collapse §9](COLLAPSE_SYSTEM.md#9-generator-feasibility-requirements)) | diagnostic only today |
| F4 | Special-room counts met, or a logged relaxation exists | new |
| F5 | No special kind on the cheapest mandatory route | new |
| F6 | Every room: each portal is reachable from the centre | implemented, per obstacle |
| F7 | Every enemy spawn is reachable from the entry portals with its clearance `k` | partially: reachability to the centre, no clearance |
| F8 | The boss room satisfies boss clearance from spawn to the centre and to every portal | new |
| F9 | Spawn distance rules from [ENCOUNTER_RULES.md §5](ENCOUNTER_RULES.md#5-spawn-constraints) | new (the prototype measures from the room centre) |

## 7. Fog, minimap and the full map

**Current:** the minimap (top right, 174×82 px) draws visited rooms plus the exit, which is always shown. Colours: current room white, boss pink, exit gold, guild hall teal, other rooms grey.

**v1 (2E):**

| Room state | Minimap | Full map (M) |
| --- | --- | --- |
| Unknown | not drawn | not drawn |
| Scouted (adjacent to a visited room) | outline only | outline, cost label; an icon for boss, exit and guild hall (which the door tints already reveal); `?` for other specials |
| Visited | filled, kind colour | filled, kind icon, cleared or uncleared marker |
| Always revealed at floor start | start, boss, exit position | same |

- **Links:** a link line is drawn between two rooms when at least one of them is visited.
- **The full map** pauses simulation (as an overlay) and shows the cheapest path to the exit given the current ticks.

## 8. Biome assignment

**Implemented (Wave 3B):** `Biomes.for_depth(depth)` reads the depth bands of [`data/biomes.json`](../../game/data/biomes.json) (the §3 table: 1–2 crypt, 3–4 fungal, 5–6 flooded, 7–8 maintenance, 9+ foundry; depths past the last band reuse it) rather than a `depth_table[].biome` column. `Generator.generate()` calls `Biomes.assign(floor)` after the layout and feasibility pass: it sets `floor.biome` and every `room.biome` from depth and kind only, draws no random numbers, and `signature()` ignores the field, so existing seeds and the determinism fixtures are unchanged. The fallback below is live for `flooded_catacombs`, `maintenance_tunnels` and `bone_foundry` (see [BIOMES_AND_TILESETS §0](BIOMES_AND_TILESETS.md#0-implementation-status-wave-3b)).

- `biome(depth)` comes from the depth table (§3). Guild-hall rooms **always** use `guild_interior`, whatever the depth.
- **Missing art fallback:** if a biome's `tileset_16x16.png` is missing, render with `stone_crypt` art multiplied by the biome's `fallback_tint`, and keep the biome's hazards and enemy affinities. This lets 2E and 3B ship mechanics before the art exists.
- **Later option:** at band boundaries, 20 % of side rooms could use the next biome ("intrusion rooms"). Off for the slice.

## 9. Tests engineers must add

1. Determinism: identical `signature()` for the same `(floor_seed, depth)` across 2 runs, for 50 seeds at each depth 1–6.
2. Depth-1 layouts are unchanged by the v1 code for the smoke-test seeds (regression on `signature()` with special kinds masked).
3. F1–F9 hold for 200 seeds per depth 1–6.
4. Special counts match §4.1 (or a logged relaxation) for 200 seeds per depth.
5. Topology targets in §2.5 are met in aggregate (a report test that fails only if outside the band by more than 25 %).
6. The boss room passes the clearance check for the brute's radius (14) on all tested seeds.

## 10. Open questions

1. Multi-cell rooms (2×1, 2×2) at depth ≥ 5? (Default: not in the slice. They need camera work, because D-16 fixes 24×24 per cell.)
2. Should the spine bend in all four directions on deep floors, for less predictable boss placement? (Default: east/south only, as now.)
3. Should the exit sometimes *not* be adjacent to the boss? (Default: adjacent, for the slice.)
4. Should treasure rooms ever be locked behind a key dropped by an elite? (Default: no.)
5. Hazard density: should hazards scale with depth or only with biome? (Default: biome sets the type, depth sets the count: 0 / 6 / 12 for bands I / II / III.)
