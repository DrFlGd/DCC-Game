# DCC Game

A game-design and development project inspired by **Dungeon Crawler Carl**. The intended experience is a top-down, room-based roguelike dungeon crawler with a 16-bit-inspired pixel-art aesthetic, expanded procedural floors, tactical pressure from a floor-collapse clock, action combat, RPG progression, and optional companions.

> **Project status:** The vertical-slice build-out is in progress; see the [full-game plan](docs/plans/2026-10-25-full-game-plan.md). The playable base is a Godot 4.7.2/GDScript prototype. It has **24×24 rooms built from 16×16 native tiles** (from the uploaded dungeon sampler), window scaling, obstacle-safe procedural layouts, multi-enemy encounters, configurable AI, six-stat RPG progression with **level-up stat allocation**, and an **Esc pause/character-sheet menu**. The design documents for the slice (run loop, collapse, combat, generation, biomes, enemies and encounters) are written, with proposed defaults for each open decision. Automated tests pass; hands-on visual playtesting remains.

## Start here

- **[Project roadmap](docs/ROADMAP.md)** — phases, deliverables, completion criteria, design questions, and first actionable tasks.
- **[D-01 engine and platform decision](docs/decisions/ADR-001-engine-and-platform.md)** — Godot 4.7.2 + GDScript selected; implementation record and test gate.
- **[Godot prototype: setup and controls](game/README.md)** — import `game/project.godot`, play the seeded dungeon-room spike, and run smoke tests.
- **[16×16 dungeon sampler and art files](game/assets/README.md)** — corrected crypt tiles, the user-provided 8-way rat sheet, independent character/enemy files, and asset conventions for future biomes and weapons.
- **[Room, enemy AI and RPG prototype specification](docs/design/ROOM_ENEMY_RPG_PROTOTYPE.md)** — fixed dimensions, safe obstacle placement, JSON-configurable enemy types, combat stats and XP progression.
- **[Full-game build-out plan (2026-10-25)](docs/plans/2026-10-25-full-game-plan.md)** — three waves of PRs toward the vertical slice, and how to track them.
- **[Game design: the run loop](docs/design/GAME_DESIGN.md)** — run, floor, room, boss, exit; victory and failure; what persists; screen flow; the dungeon-system announcer.
- **[Collapse system](docs/design/COLLAPSE_SYSTEM.md)** — tick rules, budget scaling by depth, the room-type policy table, the zero-clock grace period, and worked examples.
- **[Combat and RPG](docs/design/COMBAT_AND_RPG.md)** — melee ruleset (D-14), ranged, dodge, damage pipeline, statuses, telegraphs, level-ups, door lock (D-07), inventory (D-09).
- **[Procedural generation](docs/design/PROCEDURAL_GENERATION.md)** — floor graph as implemented, depth scaling (D-06), special rooms, feasibility checks, map and fog.
- **[Biomes and tilesets](docs/design/BIOMES_AND_TILESETS.md)** — the D-15 catalogue of six biomes, the standard 16×16 atlas layout, and the mock-up specification.
- **[Enemy tiers](docs/design/ENEMY_TIERS.md)** and **[encounter rules](docs/design/ENCOUNTER_RULES.md)** — roles, bands I–V, starter roster, elites and bosses, threat budgets, spawn rules and validation tests.
- **[Catalogue guide](docs/research/CATALOG_GUIDE.md)** and **[source index](docs/research/SOURCE_INDEX.md)** — how to research the books with citations and spoiler tags; the schema lives in [`data/canon/`](data/canon/README.md).
- The team has selected **Godot 4.7.2 + GDScript** and **24×24 rooms made of 16×16 environment tiles**. The next step is to playtest scaled room visibility, enemy AI and collision, experience pacing, and the collapse clock.
- The second goal is a **source-referenced canon catalogue** of Carl's and companions' interactions, equipment, enemies, skills, and other mechanics.
- The third and fourth goals are a **game-ready item/ability catalogue** and a **tiered enemy roster**.

## Core design pillars

1. **Explore versus escape:** Floors are substantially larger than typical room-based roguelikes. Entering new rooms advances an explicit collapse threat, making routing meaningful.
2. **Responsive top-down combat:** Aim and attack in any direction with ranged projectiles, melee attacks, usable items, abilities, and potentially companion assistance.
3. **Build variety:** Weapons, spells, skills, loot, and synergies change how each run plays.
4. **Escalating descent:** Procedural layouts and encounters increase in variety, danger, and complexity on deeper floors.
5. **Readable presentation:** Original 16-bit-inspired pixel art, clear combat telegraphs, and immediately legible collapse information.

## Working principles

- Treat the books as **research references**, not an unchangeable game-balance specification. Mark each proposed entry as *canon*, *adapted*, or *original*.
- Record exact **book/chapter or other verifiable source locations** for canon claims; keep observation separate from proposed mechanics, and mark spoilers.
- Prefer testable design decisions and small playable prototypes over speculative feature expansion.
- **IP note:** This is a project inspired by an existing copyrighted series. Any public or commercial release that uses protected characters, settings, names, or artwork may require permission or a license from the rights holders. Do not assume this repository grants those rights.

## Current next step

Run the **Godot 4.7.2 prototype** using [the game setup instructions](game/README.md), validate the controls and headless smoke tests, and continue **Phase 1: Foundational gameplay rules** in [the roadmap](docs/ROADMAP.md). Collapse values are configuration-driven hypotheses to tune through boss rooms, guild halls, and other room mechanics.

As the project grows, add more detailed design specifications, source catalogues, and structured content data under `docs/` and `data/` as outlined in the roadmap.
