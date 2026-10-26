# DCC Game — Development Roadmap

**Status:** Pre-production; vertical-slice build-out in progress  
**Last updated:** 2026-10-25  
**Owner:** Project team (assign individual owners as work begins)  
**Scope:** Design research, content modelling, prototype, and eventual production for a *Dungeon Crawler Carl*-inspired game.

## 1. Game vision

Create a **top-down, single-player-first roguelike dungeon crawler** that takes inspiration from the room-based action and build variety of *The Binding of Isaac*, while introducing:

- **Much larger floors** built procedurally from connected rooms on a grid.
- **A tunable collapse clock** that responds to room transitions, with configurable rules for boss rooms, guild halls, revisits, and other special rooms.
- **Omnidirectional action combat** with projectiles, melee weapons, active items, spells/abilities, and eventually companion support.
- **RPG depth** through experience, levels, attributes, skills, equipment, and meaningful build synergies.
- **An escalating descent** featuring harder enemies, encounters, hazards, and bosses at greater dungeon depths.
- **Original 16-bit-inspired pixel-art presentation**, with clear combat and environmental telegraphs.

The books inform the game's world, characters, enemies, and ability ideas. **Source fidelity and good gameplay are separate design concerns**: catalogue book observations accurately, then document when and why an effect is adapted or invented for balance.

### Non-goals for the first playable build

- Full coverage of all books, characters, items, and monsters.
- Online multiplayer or multiple playable protagonists.
- Final-quality art, animation, sound, voice acting, or narrative.
- A commitment to a particular engine/platform before a short feasibility spike.
- Reproducing another game's assets, level designs, or exact mechanics.

## 2. Milestone overview

The four content/design phases below follow the project's requested order. Technical prototyping begins during Phase 1, not after the entire reference catalogue is complete.

| Phase | Focus | Key output | Completion gate |
| --- | --- | --- | --- |
| **0 — Setup** | Project framing | README and this roadmap | Repository has a clear starting point |
| **1 — Foundational gameplay rules** | Core loop, map, collapse, combat, RPG, technical choices | First game design document (GDD), test rules, greybox prototype | One complete, testable room-to-room loop |
| **2 — Canon interaction catalogue** | Source-based research into Carl, companions, encounters, equipment, skills | Traceable catalogue and tagging taxonomy | Representative, reviewed dataset with no unsourced canon claims |
| **3 — Weapons, spells, items, skills** | Adapt researched concepts into balanced game systems | Structured item/ability data and balance guidelines | A curated first-playable loadout with working effects |
| **4 — Enemy tiers and encounter design** | Scale enemy challenge as floors descend | Enemy database, behaviors, tiers, spawn rules | Complete early-floor roster with encounter tests |
| **5 — Vertical slice** | Bring systems and content together | Playable multi-room, single-floor loop | A player can start, explore, fight, progress, and finish/fail a run |
| **6 — Expansion and production** | Depth, polish, accessibility, content, testing | More floors, encounters, items, companions, visuals | Agreed release-quality targets met |

**Phase priority:** 1 → 2 → 3 → 4, with small prototype experiments throughout. Phase 5 integrates those deliverables. Revisiting earlier phases is expected.

**Latest engineering update (2026-10-11):** The [Godot prototype](../game/README.md) now uses the **uploaded 16×16 dungeon sampler** (D-13 revised), retains fixed **24×24 rooms** (384×384 world pixels), and adds a **pause-menu resolution selector** with common windowed presets. Combat, navigation and obstacle coordinates were rescaled to preserve tile-relative behavior. CI is used for script, navigation and display checks; **hands-on playtesting remains pending**.

**Current build-out (2026-10-25):** Work toward the Phase 5 vertical slice follows the [full-game plan](plans/2026-10-25-full-game-plan.md). It is organised as three waves of pull requests. Wave 1 is foundation: the architecture refactor, the content data layer and the design documents. Wave 2 builds the slice features in parallel, and Wave 3 handles polish and release. The Wave 1C design set is now in place:

- [Game design](design/GAME_DESIGN.md) (the run loop)
- [Collapse system](design/COLLAPSE_SYSTEM.md)
- [Combat and RPG](design/COMBAT_AND_RPG.md)
- [Procedural generation](design/PROCEDURAL_GENERATION.md)
- [Biomes and tilesets](design/BIOMES_AND_TILESETS.md)
- [Enemy tiers](design/ENEMY_TIERS.md) and [encounter rules](design/ENCOUNTER_RULES.md)
- Research: [catalogue guide](research/CATALOG_GUIDE.md) and [source index](research/SOURCE_INDEX.md)

Each open decision now has a **Proposed default** that engineers can build against. Those defaults become *Accepted* only after owner sign-off (see §3).

---

## Phase 0 — Establish the project (initialized)

**Objective:** Make the repository usable as the shared source of truth.

### Deliverables
- [x] Create a project overview in `README.md`.
- [x] Record the roadmap in `docs/ROADMAP.md`.
- [x] Document engine and platform options in [ADR-001](decisions/ADR-001-engine-and-platform.md); **Godot 4.x + GDScript, desktop-PC-first** is proposed, not yet approved.
- [x] Accept D-01: project owner selected **Godot 4.7.2 stable (standard/GDScript), desktop-PC-first** on 2026-10-10.
- [x] Add a runnable-project scaffold and headless smoke-test workflow under [`game/`](../game/README.md).
- [ ] Run Godot CI/editor smoke tests and verify scene navigation, combat input, and game outcome; technical quality gate **pending**.
- [ ] Decide whether this is a private fan prototype or intended for distribution; assess required intellectual-property permissions before public/commercial use.

**Gate:** Documentation can be found and project goals are written down.

## Phase 1 — Foundational gameplay rules

**Objective:** Establish a coherent ruleset, then prove that its most distinctive features feel fun in a small greybox prototype.

### 1A. Run structure and dungeon topology
- [x] Define what a *run*, *floor*, *room*, *encounter*, *boss*, *exit*, and *collapse* mean. See [GAME_DESIGN.md](design/GAME_DESIGN.md).
- [x] Specify a procedural **room-grid graph**: adjacent connections, doors, branches, loops, dead ends, special rooms, gated routes, and discovery/fog-of-war. See [PROCEDURAL_GENERATION.md](design/PROCEDURAL_GENERATION.md).
- [x] Define room interior tile grids, collision, hazards, destructibles, and interaction points separately from the overall floor map. See [PROCEDURAL_GENERATION.md §5](design/PROCEDURAL_GENERATION.md#5-room-interior-rules-v1) and [BIOMES_AND_TILESETS.md §7](design/BIOMES_AND_TILESETS.md#7-engineering-notes).
- [x] **D-13 — Revise environment tile baseline to 16×16 native pixels.** Integrate the uploaded dungeon sampler; use 24×24 environment cells per room. Sprite animation cycles and missing sampler corner/south-edge tiles remain follow-ups.
- [x] **D-16 — Lock each room interior to 24×24 tiles** (now 384×384 world pixels at D-13's 16px grid); window resizing changes only render scale/offset, not the tile count.
- [x] Generate seeded blocking debris/pillars and check paths from center to every linked exit before accepting each obstacle.
- [ ] Extend connectivity to account for actor sizes, destructible obstacles, and multi-tile hazards.
- [x] Set **large-floor design targets**. Evaluate initial test sizes such as 40–80 rooms per floor, then tune based on traversal time and decision density; these are hypotheses, not final requirements. D-06 proposed default: 22–44 rooms on slice floors 1–6 and 50–80 from depth 7 ([PROCEDURAL_GENERATION.md §3](design/PROCEDURAL_GENERATION.md#3-depth-scaling--d-06)).
- [ ] Require every generated floor to have an achievable critical route from start to exit/objective, with optional risk/reward branches. Specified in [COLLAPSE_SYSTEM.md §9](design/COLLAPSE_SYSTEM.md#9-generator-feasibility-requirements) and [PROCEDURAL_GENERATION.md §6](design/PROCEDURAL_GENERATION.md#6-feasibility-checks); implementation is Wave 2E.
- [x] Decide whether floor progression is linear, branching, or includes optional side objectives. The descent is linear, through branching floors with optional special rooms ([GAME_DESIGN.md §3](design/GAME_DESIGN.md#3-the-loop)).

### 1B. Collapse-clock system — signature mechanic
- [x] Define the clock unit (e.g., abstract **collapse ticks**), starting budget, floor/depth tuning parameters, and minimum feasible budget for mandatory routes. See [COLLAPSE_SYSTEM.md §3–4](design/COLLAPSE_SYSTEM.md#3-tick-unit-and-triggers--d-03).
- [x] Define **configurable** clock triggers (first entry, every transition, events, and revisits), rather than committing to a uniform cost per room.
- [x] Provide data-driven policy overrides for **normal rooms, boss rooms, guild halls/safe hubs, special rooms, and revisits**; charge, waiver, pause, and refund behaviors remain design/testing decisions. Implemented in `collapse_policy.gd`; the table for new kinds is in [COLLAPSE_SYSTEM.md §5](design/COLLAPSE_SYSTEM.md#5-room-type-policy-table).
- [x] Show the player the expected cost **before** they choose a room transition; keep current budget visible during exploration. Door net-cost labels and the HUD tick counter are implemented.
- [x] Decide what happens at zero (immediate collapse, escape grace period, changing hazards, or another explicit rule). D-05 proposed default: a 10 s grace period with escalating hazards ([COLLAPSE_SYSTEM.md §6](design/COLLAPSE_SYSTEM.md#6-zero-clock-outcome--d-05)).
- [x] Define mechanisms that increase/decrease/pause time, including earned time, traps, room-type modifiers, loot, and character skills; log clock changes for tuning. See [COLLAPSE_SYSTEM.md §7 and §12](design/COLLAPSE_SYSTEM.md#7-time-granting-sources).
- [ ] Test for unwinnable procedural seeds, accidental softlocks, and incentives to avoid exploring altogether. The test plan and anti-patterns are in [COLLAPSE_SYSTEM.md §9–10](design/COLLAPSE_SYSTEM.md#10-anti-patterns-and-safeguards); the tests themselves are still to be written.

**Key design tension:** The player should be tempted to explore *one more room* without feeling punished for random, unknowable requirements.

### 1C. Player, companions, and combat
- [x] Specify movement, collision, dodge/avoidance, damage, health, death, invulnerability frames, and hit feedback. See [COMBAT_AND_RPG.md](design/COMBAT_AND_RPG.md).
- [x] Support **full-direction aiming/attacking** from a top-down view (input method to be decided). Mouse aim is implemented, and Wave 1A added Input Map actions with right-stick `aim_*` gamepad defaults (D-02).
- [ ] Prototype projectile and melee attacks with hitboxes, range, speed, cooldowns, attack arcs, knockback, and damage types. The rules are specified in [COMBAT_AND_RPG.md §4–6](design/COMBAT_AND_RPG.md#4-melee--d-14); implementation is Wave 2D.
- [x] **Design the full melee ruleset (D-14).** Proposed default: aimed arc, thrust and spin patterns ([COMBAT_AND_RPG.md §4](design/COMBAT_AND_RPG.md#4-melee--d-14)); playtest pending. Decide whether attacks use directionally aimed arcs, straight thrusts, close-range contact, or weapon-specific patterns; how aim and attack inputs work; whether holding attack repeats; hitboxes/active frames, reach, cleave and multiple-target hits, knockback, cooldowns/stamina, animation tells, and how melee compares to projectile builds. Include companion melee behavior and environmental interactions as later considerations.
- [x] Define inventory/equipment slots, pickup interactions, consumables, and active versus passive items. See D-09 in [COMBAT_AND_RPG.md §12](design/COMBAT_AND_RPG.md#12-d-09--inventory-and-resources).
- [x] Establish companions as a later system, but choose foundational assumptions now: follower AI, target selection, positioning, commands, buffs, survivability, and independent attacks. See D-10 in [COMBAT_AND_RPG.md §13](design/COMBAT_AND_RPG.md#13-companions--d-10).
- [x] Prototype multi-enemy rooms and editable melee/ranged attack definitions, AI modes and BFS obstacle navigation via [`enemies.json`](../game/data/enemies.json).
- [ ] Improve path clearance, enemy separation, ranged counterplay, and encounter budgets with real playtests.
- [x] Decide combat persistence on leaving/re-entering rooms and whether doors are locked during encounters. See D-07 in [COMBAT_AND_RPG.md §9](design/COMBAT_AND_RPG.md#9-d-07--door-lock-and-room-persistence).

### 1D. RPG and build systems
- [x] Implement a first-pass RPG: six STR/DEX/CON/INT/WIS/CHA attributes, d20 roll-to-hit against AC, proficiency, XP-per-kill, cumulative level thresholds, and HP growth.
- [x] Implement **automatic level-up allocation:** pause combat on level gain, award two configurable stat points per level, allow preview/undo/confirm across six abilities, and recompute HP/AC/attack effects.
- [x] Implement an **Esc pause menu** with a character-stat page (attributes, modifiers, AC, HP, level, XP, proficiency, combat bonuses).
- [ ] Tune the RPG for real-time play; choose classes/skill paths, spellcasting and rewards, ability-score upgrades versus D&D class-specific improvements, and how death resets meta-progression.
- [ ] Playtest mouse/keyboard accessibility, readable UI at minimum window sizes, and future controller navigation for both menus.
- [x] Decide how skills are learned/upgraded, including prerequisites and active/passive categories. Each level-up gives a pick of 1 skill from 3, up to rank 3 ([COMBAT_AND_RPG.md §11](design/COMBAT_AND_RPG.md#11-rpg-progression-and-skills)).
- [x] Specify spells/abilities, cooldowns, mana/stamina/other costs, status effects, and stacking rules. The rules, the stamina resource and the status table are in [COMBAT_AND_RPG.md §7, §12](design/COMBAT_AND_RPG.md#7-status-effects); individual skill records belong to the Wave 1B content data.
- [x] Decide what resets on death versus persists between runs (full reset, unlock-based meta-progression, or hybrid). D-08 proposed default: full reset, with reserved unlock hooks ([GAME_DESIGN.md §4](design/GAME_DESIGN.md#4-what-persists--d-08)).
- [x] Establish rough guardrails for damage, health, mobility, and power growth by floor. See [ENEMY_TIERS.md §4](design/ENEMY_TIERS.md#4-stat-guardrails-per-band) and [COMBAT_AND_RPG.md §11](design/COMBAT_AND_RPG.md#11-rpg-progression-and-skills).

### 1E. Presentation and technology
- [ ] Set a pixel-art art bible: 16-bit-inspired style, sprite scale, tiles, palettes, silhouette readability, animations, effects, and UI.
- [x] **D-15 — Catalogue dungeon biomes and their tilesets.** Create a proposed biome list and define the visual/environmental identity of each; for every biome specify tile families (floors, walls, corners, doors, thresholds, obstacles, decals, hazards, and transitions), palette and lighting, room features, navigation/collision requirements, and environmental gameplay hooks. Distinguish source-inspired candidates from original designs. Use the accepted D-13 **16×16** environment-tile baseline (revised 2026-10-11) and keep one tileset file per biome. See [BIOMES_AND_TILESETS.md](design/BIOMES_AND_TILESETS.md).
- [x] Evaluate engine and platform options against 2D tilemaps, deterministic procedural generation, combat collision, content architecture, licensing, and export; see [ADR-001](decisions/ADR-001-engine-and-platform.md).
- [x] Implement a first seeded generator/combat/collapse technical spike in [`game/`](../game/README.md).
- [ ] Validate the Godot 4.7.2 prototype via headless tests and interactive playtesting (not executed in this authoring environment).
- [ ] Choose input targets, minimum performance targets, and initial development platform. D-02 proposes the input targets ([COMBAT_AND_RPG.md §2](design/COMBAT_AND_RPG.md#2-input--d-02)); performance targets are still open.
- [x] Establish deterministic seeds, basic HUD/debug output, validated room layouts/obstacles, and CI smoke tests.

**Documents:** created on 2026-10-25: [GAME_DESIGN.md](design/GAME_DESIGN.md), [COLLAPSE_SYSTEM.md](design/COLLAPSE_SYSTEM.md), [PROCEDURAL_GENERATION.md](design/PROCEDURAL_GENERATION.md), [COMBAT_AND_RPG.md](design/COMBAT_AND_RPG.md), [BIOMES_AND_TILESETS.md](design/BIOMES_AND_TILESETS.md). Created on 2026-10-10: [ADR-001](decisions/ADR-001-engine-and-platform.md).

**Acceptance criteria**
1. The design docs describe a complete start → explore → choose doors → fight/loot/level → exit/fail loop.
2. A greybox build generates a connected floor with a fixed seed, accepts movement and aim input, supports one melee and one projectile attack, and decrements a visible collapse clock on the defined entry event.
3. A playtest demonstrates that entering an extra room is a deliberate, understandable risk/reward choice.
4. Open mechanical questions are recorded as decisions rather than silently assumed.

## Phase 2 — Catalogue book interactions, weapons, and mechanics

**Objective:** Build a **verifiable, spoiler-aware reference catalogue** of relevant interactions involving Carl and companions throughout the series, to identify existing enemies, combat patterns, items, spells, equipment, attributes, and system rules.

### Research workflow
- [x] Define covered books/editions and a spoiler policy (the catalogue may contain spoilers by design). D-11 proposed default is in [SOURCE_INDEX.md](research/SOURCE_INDEX.md).
- [ ] Create a source index with book and chapter/scene references; **do not infer citations or fabricate canon entries**. A skeleton with the citation format is in [SOURCE_INDEX.md](research/SOURCE_INDEX.md); the editions and entries are still to be filled in.
- [ ] Catalogue notable encounters and interactions involving Carl or companions, including opponents, noncombat hazards, loot acquisition, skill usage, equipment changes, environmental manipulation, and unusual rule interactions.
- [ ] Extract weapons, spells, items, enemy types, companion abilities, environmental effects, and dungeon-system behaviors into normalized records.
- [ ] Keep **observed behavior** separate from **gameplay adaptation**. Record uncertainty where descriptions are ambiguous.
- [ ] Tag entries by type, actors, book, floor/depth when known, combat role, status effect, source confidence, and gameplay suitability.
- [ ] Perform a second-pass audit for duplicates, contradictory descriptions, missing source locations, and unclear spoilers.

### Minimum catalogue record
| Field | Purpose |
| --- | --- |
| `id`, `name`, `category` | Stable lookup key and classification |
| `source_book`, `source_chapter_or_scene` | Verifiable provenance |
| `spoiler_level`, `source_confidence` | Research handling and uncertainty |
| `participants`, `context` | Who is involved and under what conditions |
| `observed_behavior` | What the story actually establishes |
| `gameplay_candidate` | Proposed mechanic or content translation |
| `adaptation_type` | `canon`, `adapted`, or `original` |
| `tags`, `notes`, `review_status` | Search, follow-up, and quality control |

**Outputs:** [SOURCE_INDEX.md](research/SOURCE_INDEX.md), [CATALOG_GUIDE.md](research/CATALOG_GUIDE.md), and a JSON catalogue in [`data/canon/`](../data/canon/README.md) with a JSON Schema. The catalogue is empty apart from one `example_` record. Avoid pasting long copyrighted book passages; use succinct original summaries with citations to the books.

**Acceptance criteria**
1. The catalogue schema supports encounters, weapons/items, enemies, skills, and companion actions.
2. A representative sample from the selected source material has been entered and cross-checked.
3. Every entry labelled `canon` has a traceable source location; adaptations are clearly marked.
4. Designers can filter records into item/ability and enemy candidates without re-reading the source corpus.

**Note:** “Complete all books” is a long-running research goal, **not** a prerequisite for the first playable build.

## Phase 3 — Design weapons, spells, items, and skills

**Objective:** Translate selected catalogue ideas, plus appropriate original designs, into an extensive but coherent game-ready content system.

### Content families
- [ ] **Weapons:** melee, ranged, throwable/explosive, unusual/special; attacks in any direction as appropriate.
- [ ] **Spells and abilities:** offensive, defensive, mobility, control, support, and companion-linked.
- [ ] **Items:** active-use, passive, consumable, equipment, quest/special, and currency or crafting components if those systems are approved.
- [ ] **Skills/perks:** level-based upgrades, class/build identities, passives, and unlock paths.
- [ ] **Effects and synergies:** damage types, status effects, debuffs, buffs, environmental manipulation, projectile modifiers, and combinational interactions.

### Design and data tasks
- [ ] Agree on naming conventions, IDs, rarity, tiers, and acquisition methods.
- [ ] Define a standard effect model: trigger → condition → target → magnitude/duration → stacking → cooldown/cost.
- [ ] Give each weapon consistent measurable fields: attack pattern, damage, reach/range, cadence, resource cost, scaling, keywords, synergies, VFX/SFX needs, and balance notes.
- [ ] Give spells/active items targeting rules, resource costs, cooldowns, duration, and counterplay.
- [ ] Define loot pools/drop tables, rarity distributions, shop/reward rules (if used), and level/depth availability.
- [ ] Tag each concept `canon`, `adapted`, or `original`, with source reference when applicable.
- [ ] Create build archetypes and a synergy matrix; flag combinations likely to trivialize the collapse clock or progression.
- [ ] Build a small deterministic simulation or test harness for damage, cooldowns, stacking, and item interactions.

**Proposed outputs:** `docs/design/CONTENT_RULES.md`, `docs/design/BALANCE_GUIDELINES.md`, `data/content/weapons.*`, `spells.*`, `items.*`, `skills.*`, and `effects.*`.

**Acceptance criteria**
1. Each record is data-driven, references defined effects, and passes schema validation.
2. A curated *starter pool* contains **at least 2 melee weapons, 2 ranged weapons, 2 active items/spells, 4 passives, and 3 skills** (planning targets, adjustable).
3. There are several distinct, viable build directions and no obviously mandatory item.
4. Source-inspired effects have documented reasons for gameplay-specific changes.

## Phase 4 — Build a tiered enemy roster

**Objective:** Populate the dungeon with recognizable, varied opponents whose threat increases across descending floors, without relying only on larger health pools.

### Enemy taxonomy
- [x] Classify by **role**: chaser, ranged attacker, charger, zoner, summoner, tank, support, trap/hazard, elite, miniboss, boss. See [ENEMY_TIERS.md](design/ENEMY_TIERS.md).
- [x] Classify by **difficulty tier** and intended earliest/latest floor depth.
- [x] Record stats: health, speed, attack cadence, damage, resistances, footprint, movement mode, rewards, and drops. These are recorded for the starter roster.
- [x] Record AI state/behavior, attack telegraphs, projectile patterns, reactions, environmental dependencies, and counters.
- [x] Tag canon lineage/source where appropriate; distinguish invented and adapted enemies. Every enemy in the starter roster is `original`.
- [x] Define room encounter budgets, composition rules, environmental hazards, spawn placement constraints, and floor-specific themes. See [ENCOUNTER_RULES.md](design/ENCOUNTER_RULES.md).
- [x] Cross-reference encounter tables with the D-15 biome catalogue so enemy placement, hazards, and environmental effects suit each biome.

### Provisional progression bands

| Band | Intended use | New challenges |
| --- | --- | --- |
| **I — Introduction** | Early floors | One clear attack, generous telegraphs, core movement/attack learning |
| **II — Pressure** | Early–mid floors | Mixed melee/ranged threats, positioning, basic status effects |
| **III — Synergy** | Mid floors | Enemy combinations, area denial, coordinated pressure, specialists |
| **IV — Punishment** | Mid–late floors | Faster patterns, layered hazards, elites, build-specific counters |
| **V — Apex** | Deep floors | Bosses and multi-phase encounters with readable but demanding mechanics |

Bands are *game-design tiers*, not claims about canonical book-floor classifications. Exact floor boundaries and stats are TBD.

### Scaling and validation
- [ ] Increase difficulty using combinations of AI complexity, attack patterns, density, room layout, resistances, and stats.
- [x] Bound unavoidable damage, projectile saturation, spawn proximity, and off-screen attacks. Guardrails are in [ENEMY_TIERS.md §4](design/ENEMY_TIERS.md#4-stat-guardrails-per-band) and [ENCOUNTER_RULES.md §5](design/ENCOUNTER_RULES.md#5-spawn-constraints).
- [ ] Balance encounter duration against collapse-clock rules so mandatory fights do not quietly make floors impossible.
- [x] Define rewards and progression pacing by depth; include boss and elite drop logic. See [ENCOUNTER_RULES.md §7](design/ENCOUNTER_RULES.md#7-rewards).
- [ ] Test enemies in isolation, then in mixed-room compositions and seeded floors.

**Outputs:** [ENCOUNTER_RULES.md](design/ENCOUNTER_RULES.md) and [ENEMY_TIERS.md](design/ENEMY_TIERS.md), both created 2026-10-25. Still to come: `data/content/enemies.*` and `encounters.*` (Wave 2C).

**Acceptance criteria**
1. Every enemy has a defined behavior loop, legible threat/counterplay, and floor/depth placement.
2. The starter roster includes **at least 5 normal enemy archetypes, 1 elite variation, and 1 boss** (planning targets).
3. Encounter generation produces a rising difficulty curve with valid placement and no unavoidable softlocks.
4. Early-floor difficulty feels differentiated from deeper floors in playtests, not just in spreadsheets.

## Phase 5 — Integrate a playable vertical slice

**Objective:** Prove that the design pillars work together as a complete, repeatable experience.

### Required first-playable loop
- [ ] Start a run with a deterministic/random seed.
- [ ] Spawn on a procedurally generated, **larger-than-reference** room-grid floor with reachable goals and optional branches.
- [ ] Explore the floor with visible map discovery and a clearly communicated collapse budget.
- [ ] Fight using omnidirectional melee and projectiles, collect items, use an active effect, gain XP, and acquire at least one skill.
- [ ] Encounter multiple enemy roles plus an objective/boss, then exit or lose to combat/collapse.
- [ ] Receive a run summary covering rooms explored, collapse ticks consumed, encounters, loot, and failure/success reason.
- [ ] Optionally trial one simple companion if the core loop is stable; do **not** make it a gate for the first slice.

### Quality gates
- Procedural seeds are reproducible and generated floors are reachable.
- Inputs and hit feedback feel responsive; projectile and melee hit detection are consistent.
- The collapse mechanic reliably affects route decisions, not just the UI.
- A complete run can be finished or lost without developer intervention.
- Basic telemetry supports tuning room count, time budget, enemy density, and drop rates.

**Milestone output:** An internally playable build, not a public release.

## Phase 6 — Expand, test, and prepare for release

- [ ] Extend supported floors, special rooms, biomes/themes, hazards, bosses, and narrative framing.
- [ ] Continue book-by-book reference research and expand item/enemy/skill catalogues.
- [ ] Add companion behavior, commandability, equipment/skill interactions, and balance testing.
- [ ] Produce original pixel-art sprites, VFX, UI, music, and sound that remain legible at the chosen resolution.
- [ ] Add remappable controls, accessible text/contrast settings, reduced-flash options, pause support, and save/resume behavior.
- [ ] Automate content schema checks, map reachability tests, smoke tests, and regression tests.
- [ ] Playtest many seeded runs, track difficulty and completion metrics, and iterate on build diversity.
- [ ] Review release scope, IP/permission status, distribution channel, and compliance before publishing.

## 3. Decisions that must be made early

Keep these in a living decision log and resolve them in Phase 1 unless noted.

| ID | Decision | Current stance |
| --- | --- | --- |
| D-01 | Engine and deployment platform | **Accepted (ADR-001):** Godot **4.7.2 stable** + GDScript, desktop-PC-first. Prototype scaffold committed; Godot CI and playtest results pending. |
| D-02 | Controller/keyboard/mouse aiming rules | **Proposed default in [COMBAT_AND_RPG.md §2](design/COMBAT_AND_RPG.md#2-input--d-02):** mouse aim on desktop and right-stick aim on gamepad, both through the Wave 1A Input Map actions (`fire` on LMB/RT, `melee` on Space/RB, `dodge` on Shift/B, `use_item`, `interact`, `map`, `pause`). Skill and consumable actions are added later. Aim assist is off. |
| D-03 | Collapse charge: first visit vs. every transition | **Proposed default in [COLLAPSE_SYSTEM.md §3](design/COLLAPSE_SYSTEM.md#3-tick-unit-and-triggers--d-03):** charge on first entry; revisits free; per-kind overrides; events can grant or drain ticks; transitions are never refused. |
| D-04 | Clock unit and starting budget | **Proposed default in [COLLAPSE_SYSTEM.md §4](design/COLLAPSE_SYSTEM.md#4-starting-budget-and-depth-scaling):** integer ticks; `start_ticks` = cheapest mandatory route cost + max(8, ceil(0.45 × rooms)), which gives 26 / 30 / 36 / 40 / 46 / 50 on floors 1–6. |
| D-05 | What happens at zero clock | **Proposed default in [COLLAPSE_SYSTEM.md §6](design/COLLAPSE_SYSTEM.md#6-zero-clock-outcome--d-05):** a 10 s grace period with escalating debris hazards and unlocked doors; regaining ticks stabilises the floor (a second grace lasts 5 s); otherwise a hard collapse ends the run. |
| D-06 | Floor size, room shapes, branch/loop distribution | **Proposed default in [PROCEDURAL_GENERATION.md §3](design/PROCEDURAL_GENERATION.md#3-depth-scaling--d-06):** 22 / 26 / 30 / 34 / 40 / 44 rooms on floors 1–6 and 50–80 from depth 7; single-cell rooms; optional-link probability 1.0, then 0.75 from depth 3. |
| D-07 | Combat lock-in and room re-entry | **Proposed default in [COMBAT_AND_RPG.md §9](design/COMBAT_AND_RPG.md#9-d-07--door-lock-and-room-persistence):** doors lock 0.5 s after entry until the room is cleared (normal, elite, boss, and trap rooms with hostiles); safe rooms never lock; doors unlock during grace; no respawns. |
| D-08 | Death, permanent unlocks, and RPG resets | **Proposed default in [GAME_DESIGN.md §4](design/GAME_DESIGN.md#4-what-persists--d-08):** full reset per run; only achievements and lifetime stats persist; unlock hooks are reserved in RunState and empty in the slice. |
| D-09 | Inventory/equipment limits and spell resources | **Proposed default in [COMBAT_AND_RPG.md §12](design/COMBAT_AND_RPG.md#12-d-09--inventory-and-resources):** 1 melee + 1 ranged + 1 active + unlimited passives + 6 consumable stack slots; a single stamina pool (100) for dodge and skills; mana deferred. |
| D-10 | Companions at launch versus later | **Proposed default in [COMBAT_AND_RPG.md §13](design/COMBAT_AND_RPG.md#13-companions--d-10):** none in the slice; one follower behind a flag in Wave 3E; foundation assumptions recorded. |
| D-11 | Source-books scope, edition references, spoiler policy | **Proposed default in [SOURCE_INDEX.md](research/SOURCE_INDEX.md):** all published main-series books are in scope; chapter-level `B<n>-C<n>` citations; per-record spoiler levels (none, minor, major, ending) with inline spoiler tags. |
| D-12 | Fan prototype vs. broader distribution; IP permissions | **Proposed default in [GAME_DESIGN.md §9](design/GAME_DESIGN.md#9-scope-and-ip--d-12):** private, non-commercial fan prototype; no distributed builds before an IP review; all game-facing expression original. |
| D-13 | Standard tile size for room elements and art scale | **Revised 2026-10-11:** **16×16 native environment tiles** using the uploaded free sampler. Fixed 24×24 rooms now occupy 384×384 logical pixels, 32px door openings. Missing dedicated sampler corner/south-wall art remains open. |
| D-14 | Full melee combat mechanics | **Proposed default in [COMBAT_AND_RPG.md §4](design/COMBAT_AND_RPG.md#4-melee--d-14):** aimed, weapon-specific arc, thrust and spin patterns with wind-up, active and recovery frames; multi-target with a per-swing hit registry; knockback; cooldown-gated (stamina reserved for dodge and skills); the drawn shape equals the hitbox. Playtest pending. |
| D-15 | Biome catalogue and associated room tilesets | **Proposed default in [BIOMES_AND_TILESETS.md](design/BIOMES_AND_TILESETS.md):** six biomes (stone crypt on floors 1–2, fungal cavern on 3–4, flooded catacombs on 5–6, maintenance tunnels on 7–8, bone foundry from 9, and a guild interior for guild halls); a standard 128×96 atlas of 16×16 tiles with 48 slots; palette-swap sharing; the sampler licence caveat applies. |
| D-16 | Fixed room geometry versus display scaling | **Accepted:** 24×24 environment tiles per room (384×384 logical pixels at 16px per tile). Window resolution affects rendering scale/UI layout only, never tile count or world-space gameplay geometry. |
| D-17 | Data-driven enemy encounters, AI and navigation | **Prototype implemented:** JSON definitions for attack/ability/stat/XP configuration, melee vs. ranged enemies, chase/kite/guard and BFS/direct/stationary nav, 2–4 normal foes and multi-foe boss. Tune AI fairness, difficulty budgets and large-creature clearance. |
| D-18 | D&D-inspired six-stat RPG and XP | **Prototype implemented:** six abilities, modifiers, AC, proficiency, d20 attacks, damage dice, XP per enemy and levels 1–20. **Open:** classes, skills, saving throws, spells, progression balance and deviations from tabletop conventions. |
| D-19 | Level-up allocation and pause/character-sheet UI | **Prototype implemented:** level-up stat allocation, Esc pause/character sheet and **windowed resolution presets** (800×600 through 3840×2160), applied without changing room tile count. **Open:** controller support, visual playtesting and advanced display settings. |

Record final choices with date, alternatives, rationale, and implications under `docs/decisions/`.

## 4. Recommended repository layout (to add incrementally)

```text
/
├── README.md
├── docs/
│   ├── ROADMAP.md
│   ├── design/
│   │   ├── GAME_DESIGN.md
│   │   ├── COLLAPSE_SYSTEM.md
│   │   ├── PROCEDURAL_GENERATION.md
│   │   ├── COMBAT_AND_RPG.md
│   │   ├── CONTENT_RULES.md
│   │   ├── BALANCE_GUIDELINES.md
│   │   ├── ENCOUNTER_RULES.md
│   │   └── ENEMY_TIERS.md
│   ├── research/
│   │   ├── SOURCE_INDEX.md
│   │   └── CATALOG_GUIDE.md
│   ├── plans/           # Dated build-out plans
│   └── decisions/
│       └── ADR-001-engine-and-platform.md
├── data/
│   ├── canon/           # Source-checked observations
│   └── content/         # Gameplay-ready definitions
└── game/                # Engine project, once selected
```

Do not generate empty placeholder files solely to match this tree. Add documents when their phase starts and decide actual data extensions once tooling is selected.

## 5. Immediate backlog — the first ten implementable tasks

These are ordered, small enough to turn into GitHub issues, and explicitly tied to exit criteria.

1. **Write the game loop contract.** Define victory, failure, floor advance, per-run progression, and what happens between rooms. Deliver: `GAME_DESIGN.md` outline and one-page flow. **Done 2026-10-25:** [GAME_DESIGN.md](design/GAME_DESIGN.md).
2. **Specify collapse clock v0.** Document tick triggers, starting budget, HUD, zero-clock outcome, and edge cases. Deliver: `COLLAPSE_SYSTEM.md` with examples. **Done 2026-10-25:** [COLLAPSE_SYSTEM.md](design/COLLAPSE_SYSTEM.md).
3. **Verify the D-01 engine spike (code committed; test gate pending).** Run Godot headless tests and the scene in the editor, then exercise seeded room graph, movement/aim, projectiles/melee, and boss-room/guild-hall costs; record test results per [ADR-001](decisions/ADR-001-engine-and-platform.md).
4. **Extend seeded generation and navigation.** Add connected floor layout, optional branches, room transitions, minimap, and visit persistence.
5. **Prototype combat primitives.** One ranged projectile and one melee attack in any direction; basic enemy dummy and collision/damage.
6. **Prototype configurable collapse integration.** Clock uses category/entry/revisit policy, previews costs, and enforces a consistent fail state.
7. **Define the RPG/inventory minimum.** XP, one level-up choice, one equippable weapon, and one active-use item.
8. **Create the source taxonomy and catalogue schema.** Pick book/chapter citation format, spoiler handling, review fields, and stable IDs. **Done 2026-10-25:** [CATALOG_GUIDE.md](research/CATALOG_GUIDE.md), [SOURCE_INDEX.md](research/SOURCE_INDEX.md), [`data/canon/schema.json`](../data/canon/schema.json).
9. **Catalogue a small verified research sample.** Select one agreed source segment, record interactions and equipment, and test filtering into gameplay candidates.
10. **Define the first enemy/loot test set.** Build a few basic enemy and item records, then playtest a full start-to-exit run.

**Next working session recommendation:** start with tasks **1 and 2**; their decisions directly shape map generation, pacing, balance, and the eventual content system.

## 5A. Follow-up design questions (deferred, tracked)

These open quality and expansion tasks do **not** block the initial engine smoke test. Address them before final art production, comprehensive room authoring, or combat-content balance.

- [x] **D-13 — Standard environment tile size:** Adopt **16×16 pixels** from the uploaded sampler. The [game demo](../game/README.md) uses 24×24 rooms (384×384 world px), 32px door gaps, rescaled combat/collision and separate character/enemy facing sheets. **Follow-up:** source/create missing dedicated corner and south-edge art, animations and clean transitions.
- [ ] **D-14 — Define melee combat:** Compare radial/directional arc swipes, thrusts, and weapon-dependent patterns; decide how aim, attack input, hitboxes, active frames, multi-target hits, range, cooldown/resource costs, knockback, and enemy telegraphs work. Test feel alongside projectile combat and specify how weapons vary. Record the result in [`docs/design/COMBAT_AND_RPG.md`](design/COMBAT_AND_RPG.md#4-melee--d-14). **Done when:** one playable melee ruleset has been playtested and its collision/timing behaviors are documented. *Status 2026-10-25: the ruleset is documented as a proposed default; implementation (Wave 2D) and the playtest are pending.*
- [ ] **D-15 — Catalogue biomes and design their tilesets:** Propose biomes (illustrative candidates: stone crypt, fungal cavern, industrial maintenance, flooded catacombs, volcanic foundry, guild/safe-hub interior), tag floor/depth and lore origin, and specify for each a palette, environmental hazards/interactions, enemy affinities, and minimum tile inventory: floor variants, walls, corners, doors, transitions, obstacles, props, and decorative decals. Identify which assets can be shared/recolored across biomes; create mock-ups in the accepted **16×16** tile scale (D-13 revised); use `assets/biomes/<biome>/tileset.png` and separate files for characters, enemies, weapons, and effects before final art production. Track in [`docs/design/BIOMES_AND_TILESETS.md`](design/BIOMES_AND_TILESETS.md). **Done when:** a reviewable biome matrix and one minimum viable tileset specification/mock-up are ready, with no final-size assumptions embedded. *Status 2026-10-26: done. The matrix, the standard atlas specification and the mock-ups are in place; Wave 3B shipped `data/biomes.json`, biome-by-depth, the slot-name renderer, generated placeholder atlases for `fungal_cavern`, `guild_interior` and the crypt's missing rows (`docs/art/mockups/`), fungal hazards and R11 affinities; the three remaining biomes run on the tinted-crypt fallback.*

**Current prototype behavior (not a committed melee design):** Space triggers a directional melee swipe on a 0.50-second cooldown. Damage uses a d6 + STR modifier and d20 attack check against each nearby target's AC. The swipe can hit several enemies, but animation and weapon-specific hitboxes remain open D-14 work. Obstacles and 24×24 geometry are currently schematic placeholder art.

## 6. Definition of done for any design or content task

A task is done when its output:
1. Has a version-controlled file or working prototype in the repository.
2. Records assumptions and open questions instead of disguising them as decided rules.
3. Has clear input/output or user-observable behavior.
4. Is testable or reviewable using a short acceptance checklist.
5. Links to book/scene provenance for canon claims, without reproducing large copyrighted passages.
6. Is reflected in this roadmap if it materially changes a milestone or dependency.

## 7. Risks and mitigation

| Risk | Mitigation |
| --- | --- |
| Huge floor size becomes repetitive | Test critical-path length, unique room functions, navigation friction, and optional detours early |
| Biomes and art production explode before tile dimensions are decided | Build biome/tileset taxonomy first; resolve D-13 scale, reuse tile modules across biomes, then produce art in batches |
| Collapse clock creates unwinnable or frustrating runs | Seed validation; mandatory route cost; boss/guild-hall-specific tuning; previewed clock impact; grace/recovery design |
| Exhaustive book cataloguing delays the game | Build representative samples and a playable core first; expand catalogue continuously |
| Content becomes difficult to tune | Shared schemas, deterministic tests, separate canon facts from game stats |
| Descending floors become numerical HP inflation | Design enemy roles, encounters, counters, and telegraphs, not just stat multipliers |
| IP/rights uncertainty limits publication | Clarify use and permissions before public distribution; create original art and original expressive content |

---

**Change control:** Update this roadmap when a phase gate is passed, a design decision changes scope, or a prototype disproves an assumption. Dates are intentionally omitted until the engine, team capacity, and initial design are settled.
