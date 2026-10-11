# DCC Game — Godot Greybox Prototype

This is the **D-01 Option A technical spike**, not a finished game. It uses drawn debug shapes (no copyrighted art/assets) to test the mechanics and structure before adding content and sprites.

## Engine

**Godot 4.7.2 stable, standard/GDScript build** (not .NET). Engine version was pinned to the latest stable 4.7.2 listed in the official download archive when the project was set up. Get it at https://godotengine.org/download/archive/4.7.2-stable/.

## Quick start

1. Install Godot 4.7.2 standard.
2. Open Godot Project Manager and **Import** `game/project.godot` from this repository.
3. Press **F6** while `scenes/Main.tscn` is open, or **F5** to play the project.
4. Move through colored door openings to enter the next room. Door labels show the *net tick change* (a negative value means ticks spent; a positive value means granted).

| Input | Action |
| --- | --- |
| WASD or arrow keys | Move |
| Mouse | Aim freely in any direction |
| Hold left mouse button | Shoot projectiles |
| Hold Space | Melee attack in aim direction |
| R | Restart using same seed |
| N | Restart using a new seed |

**Goal:** defeat the boss (red/pink room), then enter the exit (gold room) before the clock hits zero. Green/cyan guild halls grant bonus ticks under the current *sample* configuration. Enemies in ordinary rooms chase and contact-damage the player. The minimap shows rooms that have been visited; the exit is visible from the start so the goal is discoverable.

## What works

- Seeded 2D procedural room graph with branches and adjacency-created loops, plus start/boss/guild-hall/exit tags.
- Room transitions via matching cardinal doors, room discovery, and an exit locked until the boss is defeated.
- Editable collapse rules for first entry, revisits, boss rooms, guild halls, and exit, with an entry ledger printed to Godot's **Output** panel.
- Visible tick/health HUD, door preview of net tick effects, and end-of-run/restart handling.
- Omnidirectional aim; ranged fire and directional melee; basic damage and enemy AI; enemy health/state maintained across revisits.
- A seeded smoke-test suite covering topology, deterministic generation, room tags, policies, and a route-budget diagnostic.

## Editing the clock and floor

Open `data/prototype_rules.json`. Restart the game after editing it.

- `seed`: initial deterministic layout. Use **R** to reproduce a run, **N** for a new seed.
- `room_count`: number of rooms in the floor; 22 is deliberately small for an engine spike.
- `start_ticks`: starting collapse budget.
- `collapse.default.first_entry_cost` / `revisit_cost`: fallback transition cost.
- `collapse.room_types.<kind>`: optional override for `start`, `normal`, `boss`, `guild_hall`, `exit`; currently boss costs 3, guild hall costs 0 and grants 3, exit costs 1.
- `first_entry_grant`: bonus ticks on first entry to the configured room type.

**No collapse values are final.** This prototype interprets zero remaining ticks as immediate defeat *after a transition*, and denies any transition whose entry cost exceeds remaining ticks. This is a test behavior, not final game design. Some seeds may be unusually generous/tight until the balancing work is completed. A nonbinding mandatory-route budget estimate is printed to the console.

## Run tests

From the repository root, with `godot` pointing to Godot 4.7.2:

```sh
godot --headless --path game --editor --quit
godot --headless --path game --script res://tests/smoke_test.gd
```

GitHub Actions also defines a headless smoke check in `.github/workflows/godot-ci.yml`.

## Technical structure

```text
game/
├── project.godot
├── README.md
├── scenes/Main.tscn
├── scripts/
│   ├── main.gd                 # renderer, input, room transitions, combat & HUD
│   ├── floor_generator.gd      # deterministic graph and route queries
│   └── collapse_policy.gd     # room-specific timing policy and ledger
├── data/prototype_rules.json # tweakable floor/combat/timer configuration
└── tests/smoke_test.gd       # headless logic checks
```

### Important scope limits

This is a **minimal engine-validation build**, not the Phase 5 vertical slice: combat uses a simple chasing dummy, room interiors are debug rectangles, there is only one floor, and there are no inventory/skills, companion AI, art assets, audio, or saves. The player cannot independently visit a floor overview; the minimap is a discovery/debugging aid. Enemy and boss abilities, guild-hall behavior, rewards, and clock numbers require playtesting and subsequent design decisions.

## Troubleshooting

- If Godot cannot locate the main scene, make sure you imported/opened the **game/** directory, not the repository root.
- If controls do not respond, click inside the running game window.
- Replaying with **R** repeats the graph exactly but moment-to-moment mouse and keyboard inputs are not recorded.
- If an edited JSON file is invalid, the game reports an error and exits; use the headless smoke-test command after making rule changes.
