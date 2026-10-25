# DCC Game — Plan to reach a full playable game

**Date:** 2026-10-25 · **Repo:** DrFlGd/DCC-Game (Godot 4.7.2, GDScript) · **Baseline:** main @ 9bb993d, CI green, all headless tests pass locally.

## 1. Where the project stands

The repo is a solid technical spike, not yet a game:

- **Works:** seeded 22-room floor graph, 24×24 fixed rooms with 16px tiles, obstacle generation with reachability checks, 4 data-driven rat/brute enemies with BFS pathing, d20 six-stat RPG with XP/levels, level-up allocation + pause/character sheet, collapse clock with per-room-type policy, minimap, headless smoke + menu integration tests in CI.
- **Missing for a game:** only one floor (no descent), no items/loot/inventory/weapons, no skills or abilities, no title screen or run summary, no enemy telegraphs/knockback/dodge, four enemies total, no special rooms beyond guild hall tick grants, no sound, no settings persistence, no gamepad, no save of any kind, no DCC-flavored "dungeon system" presentation.
- **Structural blocker:** `game/scripts/main.gd` is a 706-line monolith that owns rendering, input, combat, HUD and run state. Every feature above would have to be wedged into it. This must be split before features can be built in parallel.
- **Roadmap target:** Phase 5 "vertical slice" (start → explore → fight/loot/level → exit or fail, with run summary), then Phase 6 expansion.

## 2. Guiding decisions for this build-out

1. **Keep what is proven.** The pure-logic modules (floor_generator, room_contents, enemy_system, rpg_rules, collapse_policy) stay and keep their tests. Determinism per seed remains a hard requirement.
2. **Event-driven core.** A `RunState` autoload (seed, depth, ticks, XP, stats, inventory, telemetry) plus an `Events` signal bus so items, skills, announcer and audio hook into combat without editing it.
3. **Everything content is data.** Items, weapons, skills, enemies, encounter tables, biomes and announcer lines live in JSON with schema validators run in CI.
4. **Original flavor, no book text.** DCC inspiration shows up as a snarky dungeon-system announcer, achievement toasts, loot boxes, "crawler" terminology, descending floors. All lines are original writing; no characters or passages from the books.
5. **Placeholder art is generated, labeled, and swappable.** New enemies/items get procedurally generated or recolored 8-direction sheets under the existing asset conventions, clearly marked as placeholders.
6. **Headless-testable.** Every PR adds or extends tests runnable with `godot --headless`; CI stays green.

## 3. Work plan — three waves of PRs

### Wave 1 — Foundation (sequential; everything else branches from it)

| PR | Scope | Files |
| --- | --- | --- |
| **1A Architecture refactor** | Split `main.gd` into `game.gd` (state machine: title/running/level_up/paused/summary), `player.gd`, `combat.gd` (projectiles, hit resolution, damage pipeline emitting events), `room_renderer.gd`, `hud.gd`; add `RunState` and `Events` autoloads; move raw key checks to Input Map actions (gamepad-ready); `tests/run_all.sh` runner. All existing tests pass unchanged in behavior. | game/scripts/**, project.godot, tests |
| **1B Content data layer** | `data/content/{weapons,items,skills,effects}.json`, standard effect model (trigger → condition → target → magnitude/duration → stacking), `scripts/content/*.gd` loaders/validators/effect resolver with unit tests. Pure logic, no integration yet. Starter pool: 3 melee, 3 ranged weapons, 3 active items, 6 passives, 4 consumables, 6 skills. | data/content, scripts/content, tests |
| **1C Design docs** | `GAME_DESIGN.md` (loop contract), `COLLAPSE_SYSTEM.md` (v0 rules + zero-clock decision), `COMBAT_AND_RPG.md` (D-14 melee ruleset), `BIOMES_AND_TILESETS.md` (D-15 catalogue), `ENEMY_TIERS.md` + `ENCOUNTER_RULES.md`, research `CATALOG_GUIDE.md` + schema (no fabricated canon entries). Roadmap decision log updated. | docs/** |

### Wave 2 — Vertical-slice features (parallel after 1A merges)

| PR | Scope |
| --- | --- |
| **2A Run loop & screens** | Multi-floor descent (exit → next floor, depth-scaled room count/ticks/encounters), title screen with seed entry, death/collapse/victory flow, run summary (rooms, ticks, kills, loot, cause), settings persisted to `user://`. |
| **2B Items, loot & inventory** | Integrate 1B: floor pickups, chests (treasure rooms), loot boxes on boss kill, weapon slots (melee + ranged) with swap, active item slot with cooldown, consumables, passives via effect resolver, inventory page in pause menu, HUD slots. |
| **2C Enemy roster & telegraphs** | ≥8 normal archetypes across roles (chaser, ranged, charger, zoner, summoner, tank, support), elite modifiers, second boss with phases, wind-up telegraphs for all attacks, encounter budgets by depth, placeholder 8-way sheets. |
| **2D Combat feel** | Dodge roll with i-frames and stamina, knockback, hit-stop/flash, screen shake, floating damage numbers, death bursts, door lock during encounters (D-07), room-clear reward moment. |
| **2E Collapse v1 & special rooms** | Zero-clock rule implemented (grace + hazard escalation), time-granting pickups/skills, guild hall as a service room (heal, reroll, buy), treasure/trap/shrine rooms, floor overview map (M), mandatory-route feasibility assert in generator. |
| **2F Skills & abilities** | Skill picks at level-up alongside stats, active abilities with cooldown/stamina, 6+ skills from 1B wired into combat, skill page in pause menu. |
| **2G Dungeon-system announcer** | Event-driven message log and toast layer, original snarky announcer lines (JSON), achievements, run telemetry written to `user://telemetry/`. |

### Wave 3 — Polish & production (after wave 2)

| PR | Scope |
| --- | --- |
| **3A Audio** | Generated SFX/ambient (WAV built by script, committed), audio bus settings, hooks on events. |
| **3B Second biome** | Biome catalogue → second tileset (recolored/generated), biome by depth, biome-specific hazards. |
| **3C Input & accessibility** | Gamepad aiming (D-02), remappable controls UI, text size/contrast options, reduced flash. |
| **3D Release pipeline** | GitHub Actions Windows/Linux export artifacts, version stamp, README/ROADMAP rewrite to reflect the real game. |
| **3E Companion prototype** | One follower companion (D-10) behind a flag: follow, target, independent attacks. |

## 4. Execution rules

- Worker agents: Opus, high effort, one PR each, each in its own git worktree off the correct base branch.
- Every PR: tests pass locally with Godot 4.7.2 headless (`game/tests/run_all.sh`), CI green, no new asset without a license note, docs updated for user-visible changes.
- Wave 2 branches are stacked on `wave1/architecture` until it merges; GitHub retargets them to `main` automatically.
- PRs are opened in dependency order; later PRs are rebased onto merged work by the orchestrator.

## 5. Open questions for Jerred (non-blocking, defaults in parentheses)

1. Merge policy: should the orchestrator merge PRs once CI is green, or wait for your review on each? (Default while waiting: stack branches, do not merge.)
2. Zero-clock outcome: immediate collapse vs. short grace period with escalating hazards (default: 10-second grace with hazards, documented in COLLAPSE_SYSTEM.md).
3. Meta-progression (D-08): full reset per run vs. unlocks between runs (default: full reset now, unlock hooks reserved in RunState).

## 6. How to track

*(Added to the repository copy; everything above is the orchestrator's plan, copied verbatim.)*

- **One PR per row.** Each row in §3 (1A–1C, 2A–2G, 3A–3E) becomes exactly one pull request on GitHub (`DrFlGd/DCC-Game`). Its title starts with the row ID, for example `1C: design documents and roadmap update`. Find them under **Pull requests**, filtered by that prefix or by branch.
- **Branches** follow `wave<N>/<slug>`, for example `wave1/architecture` and `wave1/design-docs`. Wave 2 branches are stacked on `wave1/architecture` until it merges (§4).
- **Status lives in the PRs, not in this file.** Draft = in progress; open and CI green = ready for review; merged = done. This plan is not edited to record progress; the [roadmap](../ROADMAP.md) is updated when a phase gate or decision changes.
- **Design references for Wave 2 engineers:**
  - [Game design](../design/GAME_DESIGN.md) for 2A and 2G
  - [Collapse](../design/COLLAPSE_SYSTEM.md) and [procedural generation](../design/PROCEDURAL_GENERATION.md) for 2E
  - [Combat and RPG](../design/COMBAT_AND_RPG.md) for 2B, 2D and 2F
  - [Enemy tiers](../design/ENEMY_TIERS.md) and [encounter rules](../design/ENCOUNTER_RULES.md) for 2C
  - [Biomes](../design/BIOMES_AND_TILESETS.md) for 3B
- **Decisions:** where a design doc sets a *Proposed default*, the PR that implements it links the doc section. Owner sign-off moves the decision to *Accepted* in the roadmap's decision table (§3 of the roadmap).
- **Open questions for the owner** (§5 above) are answered in the PR conversation or the project chat. Answers are then copied into the relevant design doc.
