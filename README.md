# DCC Game

A game-design and development project inspired by **Dungeon Crawler Carl**. The intended experience is a top-down, room-based roguelike dungeon crawler with a 16-bit-inspired pixel-art aesthetic, expanded procedural floors, tactical pressure from a floor-collapse clock, action combat, RPG progression, and optional companions.

> **Project status:** Pre-production / foundational rules and research. No gameplay implementation has been started in this repository.

## Start here

- **[Project roadmap](docs/ROADMAP.md)** — phases, deliverables, completion criteria, design questions, and first actionable tasks.
- The first goal is to **define and test the core gameplay loop** before committing to an engine or building a large content library.
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

Work through **Phase 1: Foundational gameplay rules** in [the roadmap](docs/ROADMAP.md). In particular, decide exactly how the collapse clock works, how large and navigable floors should be, and what counts as success or failure in a run.

As the project grows, add more detailed design specifications, source catalogues, and structured content data under `docs/` and `data/` as outlined in the roadmap.
