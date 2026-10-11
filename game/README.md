# DCC Game — Godot 32×32 Stone-Crypt Prototype

This is the **D-01 Option A technical spike**, not a finished game. The first environment now uses a **32×32 logical tile grid** and a compact atlas of original placeholder pixel-art assets. The projectile effects, HUD, guild marker, and melee telegraph remain simple debug graphics.

## Engine

**Godot 4.7.2 stable, standard/GDScript build** (not .NET). Engine version was pinned to the latest stable 4.7.2 listed in the official download archive when the project was set up. Get it at https://godotengine.org/download/archive/4.7.2-stable/.

## Quick start

1. Install Godot 4.7.2 standard.
2. Open Godot Project Manager and **Import** `game/project.godot` from this repository.
3. Press **F6** while `scenes/Main.tscn` is open, or **F5** to play the project.
4. Walk toward the decorated door openings to enter the next room. Door labels show the *net tick change* (a negative value means ticks spent; a positive value means granted). Door artwork appears closed even though connected doors are traversable in this test build; opening animations are future work.

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
- **32×32 stone floor and rotated masonry wall tiles**, two-tile door gaps, direction-rotated doors, and original player/rat-scavenger/boss sprite placeholders. See [the atlas specification](assets/README.md).

## Visual and tile layout

The room interior is **24 columns × 10 rows = 768 × 320 logical pixels**, with one 32-pixel wall ring outside the floor. Doors occupy a **64-pixel (two-tile) opening** centered on each side where the procedural room graph provides a connection. Walls are rotated 0°/180°/±90° depending on the side; floor tiles rotate by 90° increments to vary repetition. Doors likewise rotate to face the direction of travel.

The sprite atlas uses a deliberately limited palette and nearest-neighbor filtering. The default player and regular enemy are drawn at **48×48 pixels** (1.5 tiles), while the boss is **96×96 pixels** (3 tiles). These are render footprints, **not final collision radii or finalized animation resolutions**. The source artwork was downscaled from larger exploratory pixel-art images and is provisional; final production tilesets will require cleaned-up edge transitions and animation frames. The game currently has 32px tile *drawing* and simple bounding-area traversal, not Godot TileMapLayer physics or collision-per-tile.

The 64-pixel door image is opaque and decorative, so connected doors currently look closed even when they permit travel. Real door-state sprites and animations are on the art backlog.


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
├── assets/
│   ├── README.md              # 32px atlas layout and rotations
│   └── crypt_atlas.png        # floor, wall, door, player, enemy, boss
├── scenes/Main.tscn
├── scripts/
│   ├── main.gd                 # renderer, input, room transitions, combat & HUD
│   ├── floor_generator.gd      # deterministic graph and route queries
│   └── collapse_policy.gd     # room-specific timing policy and ledger
├── data/prototype_rules.json # tweakable floor/combat/timer configuration
└── tests/smoke_test.gd       # headless logic checks
```

### Important scope limits

This is a **minimal engine-validation build**, not the Phase 5 vertical slice: combat uses a simple chasing enemy, room interiors have a starter tiling treatment rather than finished level art, there is only one floor, and there are no inventory/skills, companion AI, animation frames, audio, or saves. The player cannot independently visit a floor overview; the minimap is a discovery/debugging aid. Enemy and boss abilities, guild-hall behavior, rewards, and clock numbers require playtesting and subsequent design decisions.

## Troubleshooting

- If Godot cannot locate the main scene, make sure you imported/opened the **game/** directory, not the repository root.
- If controls do not respond, click inside the running game window.
- Replaying with **R** repeats the graph exactly but moment-to-moment mouse and keyboard inputs are not recorded.
- If an edited JSON file is invalid, the game reports an error and exits; use the headless smoke-test command after making rule changes.
