# ADR-001 — Game Engine, Language, and Initial Target Platform

- **Status:** Proposed — awaiting project owner selection / prototype validation
- **Date:** 2026-10-10
- **Decision ID:** D-01
- **Related:** [Development Roadmap](../ROADMAP.md), particularly Phase 1E
- **Decision owner:** Project owner
- **Proposed default:** Godot 4.x (pin stable patch version before implementation), GDScript, desktop-PC-first prototype

## Context

DCC Game is intended to be a top-down, 16-bit-inspired pixel-art roguelike with unusually large procedurally generated room-grid floors, per-entry collapse pressure, omnidirectional ranged and melee combat, data-driven RPG progression and equipment, many enemy types, and eventually companions. The game needs **repeatable seeds**, a **tunable collapse policy per room type**, and code/content architecture that can grow without rewriting every scene.

As of this ADR, the repository holds planning documentation only. We have **not** chosen an engine or started a prototype, and the project owner's OS, coding experience, team size, and release ambitions are not yet confirmed. These may change the selection.

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

**Prototype in Godot 4.x using GDScript with a desktop-first build.**

Why this wins under current assumptions:

1. The game is primarily **2D and mechanics-driven**, with no known requirement for Unity's larger ecosystem.
2. Procedural room generation and a per-room-type collapse rules service are well-suited to reusable scenes, data files, and testable pure logic.
3. No engine revenue thresholds or recurring charges simplify experimentation and possible later distribution.
4. GDScript minimizes setup/iteration overhead for early game mechanics; use typed GDScript where practical and automated validation for data-driven content.
5. Windows is a convenient **initial distributable test target**, not a restriction on the developer's workstation or a long-term exclusivity commitment. Export to the team’s development OS first for convenience; evaluate macOS/Linux builds after core-playable.

**No engine is selected or installed by this document.** The recommendation becomes an **Accepted** ADR only after the project owner approves it (or authorizes the recommendation) and the spike passes its gate.

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

- **Project owner choice:** _Pending_
- **Engine/version:** _Pending_
- **Language:** _Pending_
- **First target platform:** _Proposed: Windows desktop prototype; adapt to actual developer OS_
- **Decision outcome:** _Pending technical spike and acceptance_
