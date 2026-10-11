# DCC Game — Godot 16×16 Stone-Crypt Prototype

This is the **D-01 Option A technical spike**, not a finished game. The first environment now uses the **user-provided 16×16 dungeon sampler tiles** and separate graphics files for the stone-crypt biome, player, and two enemy types. All three actors have eight direction-dependent idle sprites. The projectile effects, HUD, guild marker, and melee telegraph remain simple debug graphics.

## Engine

**Godot 4.7.2 stable, standard/GDScript build** (not .NET). Engine version was pinned to the latest stable 4.7.2 listed in the official download archive when the project was set up. Get it at https://godotengine.org/download/archive/4.7.2-stable/.

## Quick start

1. Install Godot 4.7.2 standard.
2. Open Godot Project Manager and **Import** `game/project.godot` from this repository.
3. Press **F6** while `scenes/Main.tscn` is open, or **F5** to play the project.
4. Resize the game window by dragging an edge; the room remains **24×24 tiles** and scales to fit. Walk toward decorated door openings to enter the next room. Door labels show the *net tick change* (a negative value means ticks spent; a positive value means granted). Door artwork appears closed even though connected doors are traversable in this test build; opening animations are future work.

| Input | Action |
| --- | --- |
| WASD or arrow keys | Move |
| Mouse | Aim freely in any direction |
| Hold left mouse button | Shoot projectiles |
| Hold Space | Melee attack in aim direction |
| Esc | Open pause menu, view character stats, or resume |
| Pause → Display resolution | Choose a common windowed resolution and click **Apply resolution** |
| F9 (prototype debug) | Award XP up to the next level so you can test the level-up menu immediately |
| Mouse in level-up menu | Assign and refund points with + / −, then confirm |
| R | Restart using same seed |
| N | Restart using a new seed |

**Goal:** defeat the boss (red/pink room), then enter the exit (gold room) before the clock hits zero. Guild halls grant sample bonus ticks. Normal rooms contain **2–4 enemies** using melee or ranged attacks and basic pathfinding; the boss room contains multiple enemies. Killing enemies earns XP and levels. The minimap shows visited rooms and the exit location.

## What works

- Seeded 2D procedural room graph with branches and adjacency-created loops, plus start/boss/guild-hall/exit tags.
- Room transitions via matching cardinal doors, room discovery, and an exit locked until the boss is defeated.
- Editable collapse rules for first entry, revisits, boss rooms, guild halls, and exit, with an entry ledger printed to Godot's **Output** panel.
- Visible tick/health HUD, door preview of net tick effects, and end-of-run/restart handling.
- Omnidirectional aim; ranged fire and directional melee; basic damage and enemy AI; enemy health/state maintained across revisits.
- A seeded smoke-test suite covering topology, deterministic generation, room tags, policies, and a route-budget diagnostic.
- **16×16 dungeon sampler stone floors, masonry, torches, side edges, double-leaf doors and prop sprites**. Free sampler omits true corner/south wall pieces, so temporary matching wall-top rotations fill those joins.
- **Eight-way facing sprites** for the player (mouse aim), rat enemy, and armored boss (AI pursuit direction).
- **Separate per-biome and per-character/enemy assets** rather than a master atlas. See [asset conventions](assets/README.md).
- **Fixed 24×24 interior tiles (384×384 world pixels)**; resize changes only rendering scale and screen-space HUD. Minimum window 720×480, with selectable common window resolutions from the pause menu.
- **Deterministic rubble and pillar obstacles**, tested for walkable routes from room center to every connected exit.
- **Data-driven multi-enemy encounters**, pathfinding/attack behavior, and a six-ability d20-inspired XP/level system.
- **Automatic level-up menu** when XP crosses a threshold. Combat freezes while you allocate ability points; the menu shows live previews and protects against overspending.
- **Esc pause menu and character-stat page** with HP, AC, level, XP, proficiency, six scores/modifiers, and derived melee/ranged attack bonuses.

## Visual and tile layout

**D-13 revised:** Standard environment tile dimensions are **16×16 native pixels**. The stone-crypt floor uses the provided [`tileset_16x16.png`](assets/biomes/stone_crypt/tileset_16x16.png), an 8-column/2-row sampler atlas with 12 supplied sprites: two floors, wall top and edges, wall face/torch, wood door, stairs, barrel, chest and bones. Each connected side has a **two-tile-wide (32px) opening**, decorated with two native 16px door leaves.

**Every room remains exactly 24×24 tiles = 384×384 world pixels**, independently of display resolution. Game movement speeds, combat ranges, collision footprints and enemy AI spacings were halved relative to the previous 32px prototype to keep approximately the same gameplay-to-tile proportions. The window can still scale the room up or down. Use **Esc → Display resolution → Apply resolution** or drag the window border; neither changes the dungeon tile count.

This is the **free sampler**, not the complete tile pack. Its README mentions dedicated bottom corners and a south-wall edge that are **not included in the supplied 12-tile assets**. We temporarily join outer corners and south walls with rotated wall-top tiles, and use wall faces/torches for the north side. These transitions can be revisited after acquiring/creating the missing pieces.

Player and rat sprite sheets remain separate. The **crawler and ordinary enemies render at 24×24** (about 1.5 terrain tiles), and the **boss at 48×48** (3 tiles). They retain all eight compass facings E, SE, S, SW, W, NW, N, NE. Source frames can be higher resolution; the renderer displays them with nearest-neighbor scaling. The 8 poses are prototype facings, not movement animations.

See [asset conventions and tile index](assets/README.md) for the complete mapping. Doors still look closed even when the procedural graph permits passage; proper door open/locked sprites and animation remain future work.

## Enemy and RPG design references

See [the gameplay systems specification](../docs/design/ROOM_ENEMY_RPG_PROTOTYPE.md) for how to add enemy types, pick chase/kite/guard behavior, choose BFS/direct/stationary navigation, edit melee or ranged attacks/abilities, and tune enemy XP. The player HUD shows six attributes, AC, HP, proficiency, level, and cumulative XP. D20 attacks use relevant stat modifiers, proficiency, and armor class. This is an action-game adaptation, **not full tabletop D&D**.

## Level-up and pause menus

When XP crosses a level threshold, combat stops and a **Level Up** overlay appears. For quick testing, press **F9 during gameplay** to jump to the next level (debug-only shortcut). The default is **2 free ability points per level gained** (this is a game-design adaptation, **not** D&D's class-specific Ability Score Improvement rule). The screen shows each of the six ability scores and its modifier, with **+** and **−** buttons to stage/undo points. Points are only applied when you select **Confirm allocation**, and confirmation remains disabled until all available points are assigned. Level jumps grant points for every level earned in that XP award. Scores cannot exceed the configured cap (default **20**).

New scores immediately update AC (DEX), max HP (CON), STR-based melee and DEX-based ranged attack bonuses, and any relevant damage modifiers on new attacks. Raising CON grants the corresponding max-HP increase to current HP. All points are lost on starting a new run.

Press **Esc** to open the pause menu. Choose **View character stats** to see your build, select one of the built-in **windowed resolution presets** (800×600, 960×540, 1024×768, 1280×720, 1280×800, 1366×768, 1440×900, 1600×900, 1920×1080, 2560×1440, 3840×2160) and click **Apply resolution**, or select **Resume game** to return. Large options may be limited by your monitor/window manager; resizing affects the viewport, not the fixed 24×24 room. Esc resumes from either pause page. Pausing and leveling both freeze player movement, enemy AI, cooldowns, and projectiles; the collapse clock does not change. **The level-up screen cannot be skipped**; this is intentional for the current prototype.

Player stat allocation is validated by [`scripts/rpg_rules.gd`](scripts/rpg_rules.gd), and menu rendering/input live separately in [`scripts/character_menu.gd`](scripts/character_menu.gd). More UI/audio accessibility and gamepad support remain future tasks.

## Editing the clock and floor

Open `data/prototype_rules.json`. Restart the game after editing it.

- `seed`: initial deterministic layout. Use **R** to reproduce a run, **N** for a new seed.
- `room_count`: number of **rooms in the floor**, unrelated to the fixed 24×24 **tiles per room**; 22 is a test value.
- `obstacle_count`: target blocking prop count for normal rooms; safe rooms use fewer.
- `player_ability_scores`: six editable starting attributes (STR/DEX/CON/INT/WIS/CHA); HP, AC, attack bonuses, and progression derive from these.
- `stat_points_per_level`: points earned for each new level (default 2).
- `stat_score_cap`: upper limit for each ability score (default 20).
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
│   ├── README.md              # separate categories, 8-way contract
│   ├── biomes/stone_crypt/tileset_16x16.png
│   ├── characters/crawler/facing_8.png
│   ├── enemies/rat/facing_8.png
│   ├── enemies/brute_boss/facing_8.png
│   └── weapons/README.md      # future weapon-specific sprite files
├── scenes/Main.tscn
├── scripts/
│   ├── main.gd                 # renderer, input, room transitions, combat & HUD
│   ├── floor_generator.gd      # deterministic graph and route queries
│   ├── room_layout.gd          # fixed 24x24 world, fit-to-window scale
│   ├── room_contents.gd        # obstacle generator and reachability checks
│   ├── enemy_system.gd         # definitions, encounters, navigation
│   ├── rpg_rules.gd            # six stats, d20 attack and XP progression
│   ├── character_menu.gd       # level-up allocation, pause and stat screens
│   └── collapse_policy.gd     # room-specific timing policy and ledger
├── data/
│   ├── prototype_rules.json    # collapse, obstacle count, player abilities
│   └── enemies.json            # enemy behavior, stats, attacks, encounter tables
└── tests/smoke_test.gd       # headless logic checks
```

### Important scope limits

This is a **technical prototype**, not a finished game. It supports multiple basic melee/ranged enemies and a starter XP/stat system, but it has only one floor, no classes or skill selection, no inventory/loot, no companion AI, no finished movement/attack animations, audio, or saves. The player cannot independently visit a floor overview; the minimap is a discovery/debugging aid. Enemy and boss abilities, guild-hall behavior, rewards, and clock numbers require playtesting and subsequent design decisions.

## Troubleshooting

- If Godot cannot locate the main scene, make sure you imported/opened the **game/** directory, not the repository root.
- If controls do not respond, click inside the running game window.
- Resize the window by dragging its border, or choose **Esc → Display resolution → Apply resolution**. The **24×24 room never changes**; only its visual scale/centering and screen-space HUD change.
- Replaying with **R** repeats the graph exactly but moment-to-moment mouse and keyboard inputs are not recorded.
- If an edited JSON file is invalid, the game reports an error and exits; use the headless smoke-test command after making rule changes.

**Asset distribution note:** The sampler README does not include an explicit redistribution license. Before publicly distributing builds or source asset files, confirm the permissions associated with the supplied pack.
