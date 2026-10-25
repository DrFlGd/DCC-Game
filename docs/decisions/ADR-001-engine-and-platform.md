# ADR-001 — Game Engine, Language, and Initial Target Platform

- **Status:** Accepted — Godot + GDScript selected by project owner on 2026-10-10; runtime validation pending
- **Date:** 2026-10-10
- **Decision ID:** D-01
- **Related:** [Development Roadmap](../ROADMAP.md), particularly Phase 1E
- **Decision owner:** Project owner
- **Selected stack:** **Godot 4.7.2 stable (standard/GDScript)**, desktop-PC-first prototype; Windows is the initial planned export target (no export generated yet)

## Context

DCC Game is intended to be a top-down, 16-bit-inspired pixel-art roguelike with unusually large procedurally generated room-grid floors, per-entry collapse pressure, omnidirectional ranged and melee combat, data-driven RPG progression and equipment, many enemy types, and eventually companions. The game needs **repeatable seeds**, a **tunable collapse policy per room type**, and code/content architecture that can grow without rewriting every scene.

**Implementation update (2026-10-10):** The owner chose Option A. A Godot project now lives under [`game/`](../../game/README.md) and implements seeded room graphs, transitions, a boss gate and guild-hall policy, omni-directional combat, and a collapse ledger. The developer's OS, team background, and release ambitions remain unconfirmed. The project requires an interactive smoke test before the technical spike is considered validated.

### Important design constraint: collapse must be tunable

Collapse-clock configuration should be **separate from the engine and map logic**, not hard-coded as "every room = one tick." A future ruleset must support at least:

- per-room-type policies for **normal rooms, boss rooms, guild halls/safe hubs, special rooms**, and revisits;
- options for no charge, entry cost, time extensions, paused clock, additional costs, or exceptions **without assuming which one is canon or finalized**;
- variable starting budgets and modifiers by floor/depth, event, item, skill, and difficulty;
- display/preview of expected transition impact; and
- deterministic tests for mandatory-route feasibility.

These are **configuration capabilities**, not finalized collapse balance. The game design will determine costs and behavior after tests.

## Decision criteria

Priorities are qualitative: **high:** efficient 2D workflow, procedural generation, deterministic seeds/testing, extensibility for thousands of definitions, source-control friendliness, predictable licensing. **Medium:** fast iteration, tooling/documentation, reliable physics and animation, cross-platform desktop export, controller support. **Future/unknown:** console SDKs, networking, mobile, 3D content, third-party asset marketplaces.

All four shortlisted engines are technically capable of this game; the differences are engineering workflow, licensing, and ecosystem rather than whether the core loop is possible.

## Options

| Option | Strengths for this project | Trade-offs / caution | Licensing and language |
| --- | --- | --- | --- |
| **A. Godot 4.x + GDScript** **(recommended)** | Strong dedicated 2D scene/TileMap workflows; small, composable nodes/scenes; quick iteration on collision, enemy states, map transitions, and HUD; editable text-based project assets; good for prototypes with custom generation rules | Smaller commercial integration/asset ecosystem than Unity; dynamic scripting requires disciplined schema validation and tests; console deployment involves separate third-party arrangements | MIT open-source engine with attribution requirement; no engine fees or royalties. GDScript recommended for first prototype. |
| **B. Unity 6 + C#** | Mature C# language/tooling, rich ecosystem and 2D tilemaps/physics, established profiling and production patterns | Heavier editor/build workflow for this 2D-focused scope; subscription eligibility and pricing need monitoring; more project/tooling configuration | Unity Personal free if eligible (official 2026 threshold: up to $200k revenue/funding); paid tiers above thresholds. C#. |
| **C. GameMaker + GML** | Fast 2D sprite/action iteration; straightforward room and combat prototypes | Multi-room procedural graph/content tooling requires custom planning; GameMaker-specific language/workflows; more commercial-license consideration if distributed for money | Noncommercial use free; Professional commercial licence listed at US$99.99 one-time, regional terms may vary. GML. |
| **D. Defold + Lua** | Lightweight editor/runtime, 2D tilemaps, small builds, simple cross-platform workflow | Lua-centric architecture, smaller plugin/community ecosystem; some editor/data authoring patterns will need custom tools | Free, source-available under Defold's own license (not MIT/OSI-open-source); no license fees or royalties. Lua. |

**Sources — official documentation, checked 2026-10-10:**
- Godot license: https://godotengine.org/license/
- Godot 4.6 documentation/FAQ (2D, platforms, languages): https://docs.godotengine.org/en/4.6/about/faq.html
- Godot Windows export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html
- Unity pricing/eligibility: https://unity.com/products/pricing-updates
- Unity 6 Tilemap Collider 2D: https://docs.unity3d.com/6000.0/Documentation/Manual/tilemaps/work-with-tilemaps/tilemap-collider-2d-reference.html
- GameMaker license/pricing: https://gamemaker.io/en/help/articles/how-to-upgrade-your-gamemaker-licence
- Defold licensing: https://defold.com/license/
- Defold engine features: https://defold.com/

Licensing terms, package pricing, and engine versions may change. Recheck before selecting paid tooling or shipping.

## Proposed decision

**Accepted: Prototype in Godot 4.7.2 stable using GDScript, with desktop-first targets.**

Why this wins under current assumptions:

1. The game is primarily **2D and mechanics-driven**, with no known requirement for Unity's larger ecosystem.
2. Procedural room generation and a per-room-type collapse rules service are well-suited to reusable scenes, data files, and testable pure logic.
3. No engine revenue thresholds or recurring charges simplify experimentation and possible later distribution.
4. GDScript minimizes setup/iteration overhead for early game mechanics; use typed GDScript where practical and automated validation for data-driven content.
5. Windows is a convenient **initial distributable test target**, not a restriction on the developer's workstation or a long-term exclusivity commitment. Export to the team’s development OS first for convenience; evaluate macOS/Linux builds after core-playable.

**Owner selection is recorded, but gameplay validation is not complete.** The repository now contains the Godot project and headless test commands; the project has not been executed locally within this authoring environment. The acceptance gate for D-01's **technology selection** is satisfied; the separate **prototype quality gate** still requires Godot CI and a human playtest.

## Alternatives / decision paths for the project owner

- **Path A — Fastest recommended start:** Approve Godot + GDScript. Pin a stable patch release; scaffold `game/`; implement a small single-floor spike and run tests; accept D-01 on successful results.
- **Path B — Compare two prototypes:** Build the *same* minimal scenario in Godot/GDScript and Unity/C#; compare time to implement, file organization, testability, controls, and performance before choosing.
- **Path C — Optimize for 2D authoring speed:** Choose GameMaker/GML if the team prefers it and is comfortable with its scripting and licensing model; run the same proof-of-concept gate.
- **Path D — Optimize for minimal runtime:** Choose Defold/Lua if small runtime size and cross-platform lightweight export outweigh ecosystem concerns; run the same gate.

If the developer already has meaningful C# experience or existing Unity assets, **Path B** deserves extra weight. Avoid writing production content tied to one engine until the choice is accepted.

## Required prototype / spike (engine-neutral)

Make a debug-only build containing:

1. A seeded 2D **grid-of-rooms floor graph** with start, an exit, a boss room, a guild hall, and optional branches (placeholder rectangles are sufficient).
2. Controllable top-down character with **eight-direction movement and continuous/omnidirectional aiming** (depending on input type); one projectile attack, one melee attack, enemy dummy, hit detection.
3. Room transitions and state persistence on revisit; minimap/room graph and legible debug overlay.
4. A collapse controller that reads **data-driven room-type policies** and reports **why** the counter changed. Boss-room and guild-hall overrides must be demonstrated; no balance values locked yet.
5. Seed logging/replay plus a reachability/mandatory-route test; settings file for changing room counts, collapse costs, and start budget without modifying code.
6. A local runnable desktop build and a one-page record of test results, engineering friction, and any platform caveats.

### Gate and measurable checks

- **Deterministic generation:** same seed/settings yield the same room graph and applicable room-policy events.
- **Reachability:** all generated test seeds have a reachable required route and exit; any budget infeasibility is detected explicitly rather than left as an unavoidable trap.
- **Authoring:** adjust room-type collapse costs and floor size via data alone; changing policies does not require a combat or map rewrite.
- **Playable feel:** input and collisions support a functional 60 FPS target on an ordinary development desktop (capture actual machine details and measurements).
- **Portability:** a second developer can clone, follow README setup, run the project, and reproduce the same seed.
- **Scope:** no final art, companion AI, giant floor, canonical catalogue, or production-quality balancing required for this decision gate.

## Suggested implementation boundaries after acceptance

Even in a small prototype, prefer reusable responsibilities:

- `FloorGenerator`: seed → graph and tagged room metadata; avoids direct dependence on scene rendering.
- `RoomController`: room entry/exit events, encounter state, special room tags.
- `CollapsePolicy`: configuration plus pure transition evaluation; outputs a ledger entry (previous value, cost/modifiers, new value, reason) for debug/UI.
- `Combat`: movement/aim, attacks, collisions, damage/status pipeline.
- `ContentDefinitions`: validated JSON/Resources (final format TBD) for items, enemies, spells, skills.
- `RunState`: floor depth, unlocked rooms, RNG seed/state, progression, and run outcome.

Avoid prematurely building an abstract "universal engine"; these are modular responsibilities, not demands for separate packages.

## Consequences and review triggers

- **Positive:** low licensing friction, focused 2D prototyping, accessible content architecture.
- **Cost:** learning GDScript / Godot-specific workflows and writing our own generation/balance tools.
- **Risks:** extremely large scene trees, runtime content validation, and console limitations need measurement or separate decisions.
- **Revisit D-01 if:** the spike fails responsiveness or content authoring targets; the team is significantly more productive in C#; target platforms change; a required middleware tool is unavailable; or legal/commercial distribution constraints change.

## Approval record

- **Project owner choice:** _Option A: Godot/GDScript selected on 2026-10-10_
- **Engine/version:** _Godot 4.7.2 stable, standard build_
- **Language:** _GDScript_
- **First target platform:** _Desktop PC, Windows export planned; run in editor on developer OS_
- **Decision outcome:** _Engine accepted and prototype scaffolded; execution/quality checks pending_


## Implementation record — 2026-10-10

- Godot project: [`game/project.godot`](../../game/project.godot)
- Scene and gameplay: [`game/scenes/Main.tscn`](../../game/scenes/Main.tscn), [`game/scripts/game.gd`](../../game/scripts/game.gd) (orchestrator and state machine). The original monolithic `main.gd` was split by the Wave 1A refactor (2026-10-25) into `game.gd`, [`player.gd`](../../game/scripts/player.gd), [`combat.gd`](../../game/scripts/combat.gd), [`room_renderer.gd`](../../game/scripts/room_renderer.gd) and [`ui/hud.gd`](../../game/scripts/ui/hud.gd).
- Core autoloads: [`core/run_state.gd`](../../game/scripts/core/run_state.gd) (`RunState`, all run data) and [`core/events.gd`](../../game/scripts/core/events.gd) (`Events`, signal bus)
- Deterministic room generator: [`game/scripts/floor_generator.gd`](../../game/scripts/floor_generator.gd)
- Data-driven clock policy: [`game/scripts/collapse_policy.gd`](../../game/scripts/collapse_policy.gd), [`game/data/prototype_rules.json`](../../game/data/prototype_rules.json)
- Smoke tests: [`game/tests/smoke_test.gd`](../../game/tests/smoke_test.gd); every headless check runs through [`game/tests/run_all.sh`](../../game/tests/run_all.sh), which CI calls
- CI: [`.github/workflows/godot-ci.yml`](../../.github/workflows/godot-ci.yml)

**Verification:** File creation and repository read-back succeeded. Godot runtime execution and graphics/input playtest were **not performed in this workspace** because Godot is not installed and the runtime could not be fetched. GitHub Actions is configured to run a headless import, smoke tests, and a brief scene launch after relevant pushes, but its execution result has not been independently confirmed. Do not mark the prototype spike as fully validated until those pass and the controls/room transitions are tested in the editor.
