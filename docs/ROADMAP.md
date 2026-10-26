# DCC Game — Roadmap

**Status:** Playable vertical slice (Waves 1–3 of the [full-game plan](plans/2026-10-25-full-game-plan.md) merged); next is balance and playtesting  
**Last updated:** 2026-10-26  
**Owner:** Project team  
**Scope:** An original top-down roguelite built on the "the dungeon is a game show" premise, made in Godot 4.7.2 + GDScript for desktop PC.

## 1. Game vision

Build a **top-down, single-player roguelite dungeon crawler** that has the room-to-room action and build variety of games like *The Binding of Isaac*, and adds:

- **Much larger floors**, generated as connected rooms on a grid.
- **A tunable collapse clock** driven by room transitions, with configurable rules for boss rooms, guild halls, revisits and other special rooms.
- **Omnidirectional action combat**: projectiles, melee weapons, active items, skills, and later companion support.
- **RPG depth**: experience, levels, attributes, skills, equipment and build synergies.
- **An escalating descent**: harder enemies, encounters, hazards and bosses at greater depth.
- **Readable presentation**: original 16-bit-inspired pixel art and clear telegraphs, with a snarky dungeon System narrating.

**Non-goals for now:** online multiplayer; more than one playable protagonist; final art, animation, voice acting or narrative; reproducing another game's or book's assets, text, characters or level designs.

## 2. Decision log

*Implemented* means the default has been built and tested. *Accepted* means the owner has signed it off. A decision can be implemented and still wait for sign-off and playtesting. Each row links to the design section that records the decision and any deviations.

| ID | Decision | Status |
| --- | --- | --- |
| D-01 | Engine and platform | **Accepted and implemented** ([ADR-001](decisions/ADR-001-engine-and-platform.md)): Godot 4.7.2 stable, GDScript, desktop PC first. There are export presets for Linux, Windows and unsigned macOS (Wave 3D). |
| D-02 | Aiming and input | **Implemented (Wave 3C)** ([COMBAT_AND_RPG §2](design/COMBAT_AND_RPG.md#2-input--d-02)): mouse or right-stick aim, chosen by the last-used device, with 8° gamepad aim assist. Controls are remappable, and there are text scale, high-contrast, reduced-flash and patterned-telegraph options. |
| D-03 | What the collapse clock charges for | **Implemented (Wave 2E)** ([COLLAPSE_SYSTEM §3](design/COLLAPSE_SYSTEM.md#3-tick-unit-and-triggers--d-03)): a room costs ticks on first entry and nothing on revisits. Room kinds can override this, events can grant or drain ticks, and a door is never refused. |
| D-04 | Clock unit and starting budget | **Implemented (Waves 2A, 2E)** ([COLLAPSE_SYSTEM §4](design/COLLAPSE_SYSTEM.md#4-starting-budget-and-depth-scaling)): integer ticks. Budget = cheapest mandatory route + max(8, ⌈0.45 × rooms⌉), which gives 26 / 30 / 36 / 40 / 46 / 50 on floors 1–6. |
| D-05 | What happens at zero | **Implemented (Wave 2E)** ([COLLAPSE_SYSTEM §6](design/COLLAPSE_SYSTEM.md#6-zero-clock-outcome--d-05)): a 10 s grace period with debris waves. A second grace lasts 5 s, and the third zero collapses the floor. |
| D-06 | Floor size and shape | **Implemented (Waves 2A, 2E)** ([PROCEDURAL_GENERATION §3](design/PROCEDURAL_GENERATION.md#3-depth-scaling--d-06)): 22–44 rooms on floors 1–6 and 50–80 deeper, plus special rooms. Floors that fail the feasibility check are re-rolled. |
| D-07 | Locking doors during fights; room re-entry | **Implemented (Wave 2D)** ([COMBAT_AND_RPG §9](design/COMBAT_AND_RPG.md#9-d-07--door-lock-and-room-persistence)): doors seal 0.5 s after you enter a hostile room and open on clear or grace. Enemies do not respawn. A 15 s failsafe handles enemies that cannot reach you. |
| D-08 | Death, unlocks and resets | **Partly implemented (Waves 2A, 2G)** ([GAME_DESIGN §4](design/GAME_DESIGN.md#4-what-persists--d-08)): each run is a full reset; only achievements, lifetime stats and telemetry persist. **Open:** unlock-based meta-progression. |
| D-09 | Inventory and resources | **Implemented (Wave 2B)** ([COMBAT_AND_RPG §12](design/COMBAT_AND_RPG.md#12-d-09--inventory-and-resources)): 1 melee, 1 ranged and 1 active slot, unlimited passives, a 6-slot belt, credits, and one stamina pool. There is no mana. |
| D-10 | Companions | **Prototype implemented (Wave 3E)** ([COMBAT_AND_RPG §13](design/COMBAT_AND_RPG.md#13-companions--d-10)): the Scrap Hound, behind `companion.enabled` (off by default). Playtest pending. |
| D-11 | Book scope, citations and spoilers (research only) | **Proposed** ([SOURCE_INDEX](research/SOURCE_INDEX.md)): chapter-level citations and per-record spoiler levels. The catalogue is still empty. |
| D-12 | Private prototype or wider distribution; IP | **Proposed** ([GAME_DESIGN §9](design/GAME_DESIGN.md#9-scope-and-ip--d-12)): a private, non-commercial prototype with all game-facing expression original. The export workflow therefore only creates **draft** releases. **Open:** owner decision and an IP and asset-rights review. |
| D-13 | Tile size | **Accepted and implemented**: 16×16 native tiles. The crypt's missing corners, south wall and door states were generated in Wave 3B ([BIOMES §0](design/BIOMES_AND_TILESETS.md#0-implementation-status-wave-3b)). |
| D-14 | Melee rules | **Implemented (Waves 2B, 2D)** ([COMBAT_AND_RPG §4](design/COMBAT_AND_RPG.md#4-melee--d-14)): arc, thrust and spin patterns per weapon, with wind-up, active and recovery frames, multi-target hits and knockback. Playtest pending. |
| D-15 | Biome catalogue and tilesets | **Implemented (Wave 3B)** ([BIOMES §0](design/BIOMES_AND_TILESETS.md#0-implementation-status-wave-3b)): six biomes catalogued and assigned by depth. Stone crypt, fungal cavern and guild interior have art and hazards; the other three use a tinted fallback. |
| D-16 | Room geometry vs screen scaling | **Accepted and implemented**: every room is 24×24 tiles (384×384 px). Changing the window size only changes the render scale. |
| D-17 | Enemies, AI and navigation in data | **Implemented (Wave 2C)** ([ENEMY_TIERS §0](design/ENEMY_TIERS.md#0-implementation-status-wave-2c), [ENCOUNTER_RULES §0](design/ENCOUNTER_RULES.md#0-implementation-status-wave-2c)): schema v2 with 12 enemies, two elite modifiers, two phased bosses, depth budgets and per-band guardrails. |
| D-18 | Six-stat d20 RPG | **Implemented (Waves 1A, 2F)** ([COMBAT_AND_RPG §11](design/COMBAT_AND_RPG.md#11-rpg-progression-and-skills)): six abilities, AC, proficiency, XP and levels, and an 8-skill tree. **Open:** classes, saving throws, spells. |
| D-19 | Level-up and pause UI | **Implemented (Waves 1A, 2A, 3C)**: level-up allocation, a pause menu with stats, inventory, skills and achievements pages, settings, resolution presets, and full gamepad navigation. |

Record final choices with their date, alternatives and rationale under `docs/decisions/`.

## 3. What exists

The game can be played from the title screen to a win on floor 6. The run ends in a summary for every outcome: victory, death, collapse or abandoning the run. Each system below links to the section of the [engineering README](../game/README.md) that describes it.

| System | State | Where |
| --- | --- | --- |
| **Run loop** | Title screen (random or typed seed); six floors with fresh budgets; intermission (half heal, Descend); victory on floor 6; a summary for every outcome; settings saved to disk. | [Run flow](../game/README.md#run-flow-and-screens) |
| **Floors** | A seeded graph with branches and loops. Start, boss, guild hall and exit rooms, plus treasure, elite, trap and shrine side rooms. Infeasible floors are re-rolled. Obstacles are reachability-checked. A minimap and a full floor map (M). | [Clock and floor](../game/README.md#editing-the-clock-and-floor) |
| **Collapse clock** | Each door previews its net cost. Ticks can be granted back. Grace period with debris; a stabilise rule; hard collapse. Tick ledger and telemetry. | [COLLAPSE_SYSTEM](design/COLLAPSE_SYSTEM.md#implementation-status-wave-2e) |
| **Combat** | d20 hits; melee arc, thrust and spin; ranged single, spread, burst and beam. Dodge with i-frames, and stamina. Knockback, hit-stop, shake, damage numbers. Doors seal during fights. | [Feel](../game/README.md#feel) |
| **Enemies** | 10 normal enemies in 7 roles; 2 elite modifiers (bulwark, volatile); 2 phased bosses. Every attack is telegraphed. Summons, hazards and support wards. Biome affinities. | [ENEMY_TIERS](design/ENEMY_TIERS.md#0-implementation-status-wave-2c) |
| **RPG and skills** | 6 abilities; 2 ability points and 1 skill point per level; 8 skills with ranks and prerequisites; 2 active-skill slots with cooldowns; INT scales skills. | [Skills](../game/README.md#skills) |
| **Items and loot** | 10 weapons, 4 actives, 10 passives, 6 consumables, 9 statuses. Effect triggers. Chests, room-clear drops, boss loot boxes. Credits and a guild-hall shop. | [Items and loot](../game/README.md#items-and-loot) |
| **Biomes** | Stone crypt (floors 1–2), fungal cavern (3–4) with spore and puddle hazards, and a guild interior, all with generated atlases. Three more biomes use a tinted fallback. | [Biomes](../game/README.md#biomes) |
| **The System** | Event-driven toasts and a log with 200+ original lines, 23 achievements, a profile, and per-run telemetry. | [The System](../game/README.md#the-system) |
| **Audio** | 38 generated WAVs (effects, ambience, music); four buses with volume settings; state-driven crossfades. | [Audio](../game/README.md#audio) |
| **Input and accessibility** | Switches between keyboard and gamepad by the last-used device; gamepad aim assist and reticle; remappable controls; text scale, high contrast, reduced flash, patterned telegraphs. | [Input and accessibility](../game/README.md#input-and-accessibility) |
| **Companion** | The Scrap Hound prototype behind a flag: follows, targets, bites, can be downed and revived, and can be told to stay. | [Companion](../game/README.md#companion-prototype) |
| **Release pipeline** | Export presets for Linux, Windows and macOS; a version stamp shown on the title screen; a tag-driven export workflow that creates draft releases; CI with a clean import. | [Run tests](../game/README.md#run-tests), [root README](../README.md#run-test-and-build) |
| **Tests** | `run_all.sh` runs the import, a compile check, 23 headless suites and a scene launch. Seed 424242 is pinned by the determinism fixtures. | [Run tests](../game/README.md#run-tests) |

## 4. Next milestones

In rough priority order. Each item should become one or more pull requests with tests, like the waves in the [plan](plans/2026-10-25-full-game-plan.md).

1. **Balance pass and playtest loop.** Play many seeded runs. Read the per-run telemetry (`user://telemetry/`) to tune clock budgets, room counts, threat budgets, loot rates, skill values and boss HP. Write down the target numbers ([GAME_DESIGN §10](design/GAME_DESIGN.md#10-pacing-targets-for-telemetry-checks)) and add a telemetry summary script. Then confirm or revise the *Proposed* decisions and get the owner's sign-off.
2. **Unblock CI.** Fix Actions billing. Run `godot-ci.yml` and a `workflow_dispatch` of `godot-export.yml` once to prove the template install on GitHub's runners.
3. **Mid-run saves.** Save and resume at floor boundaries (the intermission) first, then optionally at room entry. `RunState` is already the single source of truth, and every random stream is seeded.
4. **More biomes' art and hazards.** Flooded catacombs (floors 5–6), maintenance tunnels and the bone foundry, each with its hazards from [BIOMES_AND_TILESETS §4](design/BIOMES_AND_TILESETS.md#4-biome-specifications). Animated doors and tiles.
5. **More content.** Band IV–V enemies and a third boss, more elite modifiers, more weapons, items and synergies, a weapon swap (`swap_weapon` is reserved), and a skill tree beyond 8 skills, possibly with class paths (D-18).
6. **Meta-progression (D-08).** Decide whether to have unlocks between runs, then fill the reserved `RunState` hooks.
7. **Companions beyond the prototype.** Playtest the Scrap Hound, then add recruitment, commands, more companion types and companion equipment or skills (D-10).
8. **Real art and audio.** Replace the generated placeholders and the crypt sampler (rights) with commissioned or licensed art. Add walk and attack animations, VFX and a real soundtrack.
9. **Localisation.** Move UI and announcer text to translation tables. The text-scale work already handles longer strings.
10. **Store packaging.** Signed and notarised macOS builds, a Windows code signature, and itch.io and Steam pages and depots. This waits on D-12 and the rights review.

## 5. Risks still open

| Risk | Mitigation |
| --- | --- |
| **Balance has never been playtested.** The clock may be trivial or punishing, and fights too long or too short. | Milestone 1: telemetry-driven tuning and a short playtest checklist per change. |
| Big floors may get repetitive. | Track decision density and seconds per room in telemetry; add room features and events per biome. |
| The collapse clock may make seeds unwinnable or discourage exploring. | The feasibility re-roll and route sweep are tested; keep watching skip rates and collapse rates in telemetry. |
| **Asset rights.** The crypt sampler tiles have no explicit licence. | Keep releases as drafts; switch to `tileset_16x16_original.png` or licensed art before any public build. |
| **IP and distribution (D-12)** are undecided. | All game-facing expression is original; get an owner decision and review before publishing. |
| CI has never run on GitHub since the billing block. | Local `run_all.sh --clean` and local exports are the gate until Actions is restored. |
| Content becomes hard to tune as it grows. | Shared JSON schemas, validators in tests, and deterministic seeds. |
| Deeper floors could become plain HP inflation. | Grow difficulty through roles, combinations, telegraph speed and hazards, within the band guardrails. |

## 6. Research and the canon catalogue

The book research is separate from the game and **never ships**. Its rules are in the [catalogue guide](research/CATALOG_GUIDE.md) and the [source index](research/SOURCE_INDEX.md), and its schema is in [`data/canon/`](../data/canon/README.md). In short:
- Keep what the source shows separate from any gameplay adaptation.
- Cite every canon claim by book and chapter.
- Summarise in your own words, never with pasted passages.
- Never fabricate an entry.
- Tag spoilers.
- Mark every game concept `canon`, `adapted` or `original`. Game-facing names and text are always original.

The catalogue is empty apart from one example record. Research is not a gate for any game milestone.

## 7. Definition of done

A design, content or code task is done when it:
1. Exists in the repository as a version-controlled document, data file or working feature.
2. Records its assumptions and open questions instead of presenting them as settled rules.
3. Has behaviour a player or a test can observe, with a headless test where the logic allows it.
4. Leaves `game/tests/run_all.sh --clean` passing.
5. Updates the relevant design doc section and this roadmap if it changes a decision or milestone.

**Change control:** update this roadmap when a milestone lands, a decision changes status, or a playtest disproves an assumption.
