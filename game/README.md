# DCC Game — Godot 16×16 Stone-Crypt Prototype

This is the **D-01 Option A technical spike**, not a finished game. The first environment now uses the **user-provided 16×16 dungeon sampler tiles** and separate graphics files for the stone-crypt biome, player, and two enemy types. All three actors have eight direction-dependent idle sprites. The projectile effects, HUD, guild marker, and melee telegraph remain simple debug graphics.

## Engine

**Godot 4.7.2 stable, standard/GDScript build** (not .NET). Engine version was pinned to the latest stable 4.7.2 listed in the official download archive when the project was set up. Get it at https://godotengine.org/download/archive/4.7.2-stable/.

## Quick start

1. Install Godot 4.7.2 standard.
2. Open Godot Project Manager and **Import** `game/project.godot` from this repository.
3. Press **F6** while `scenes/Main.tscn` is open, or **F5** to play the project.
4. Resize the game window by dragging an edge; the room remains **24×24 tiles** and scales to fit. Walk toward decorated door openings to enter the next room. Door labels show the *net tick change* (a negative value means ticks spent; a positive value means granted). Door artwork appears closed even though connected doors are traversable in this test build; opening animations are future work.

| Input (keyboard / mouse) | Gamepad default | Input Map action | Effect |
| --- | --- | --- | --- |
| WASD or arrow keys | Left stick or D-pad | `move_up/down/left/right` | Move |
| Mouse | — (right stick reserved as `aim_*`) | — | Aim freely in any direction |
| Hold left mouse button | Hold RT | `fire` | Shoot projectiles |
| Hold Space | Hold RB | `melee` | Melee attack in aim direction |
| Esc | Start | `pause` | Open pause menu, view character stats, or resume |
| Pause → Display resolution | — | — | Choose a common windowed resolution and click **Apply resolution** |
| F9 (prototype debug) | — | `debug_level_up` | Award XP up to the next level so you can test the level-up menu immediately |
| Mouse in level-up menu | — | — | Assign and refund points with + / −, then confirm |
| R | — | `restart_seed` | Restart using same seed |
| N | — | `new_seed` | Restart using a new seed |
| L | L3 (left stick press) | `toggle_log` | Show / hide the system log (see [The System](#the-system)) |

Gameplay code reads **Input Map actions** (Project → Project Settings → Input Map), never raw keycodes, so bindings can be changed without touching scripts. Movement uses physical key positions (WASD works on any layout). Reserved actions with default bindings for Wave 2 features: `dodge` (Shift / B), `use_item` (Q / LB), `swap_weapon` (Tab / Y), `interact` (E / A), `map` (M / Back) and `aim_up/down/left/right` (right stick). Aiming is still mouse-only.

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

Player stat allocation is validated by [`scripts/rpg_rules.gd`](scripts/rpg_rules.gd), and menu rendering/input live separately in [`scripts/character_menu.gd`](scripts/character_menu.gd). Gamepad bindings exist for movement, fire, melee and pause; gamepad aiming and menu navigation, plus more UI/audio accessibility, remain future tasks.

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

## The System

The dungeon is narrated by an indifferent, game-show-flavoured **system** (design: [GAME_DESIGN.md §8](../docs/design/GAME_DESIGN.md#8-the-dungeon-system-announcer-presentation-layer)). It is presentation only: it listens to `Events`, never changes the run, and never writes the HUD message line, which stays terse gameplay status.

- **Toasts.** Up to two at the top centre, above the room. Each line has a priority from 1 to 5. Toasts are spaced at least 2.5 s apart, except priority ≥ 4 (boss room, grace, level-up, achievements, outcome), which also replaces a weaker toast after it has been up for 1 s. While the pause or level-up menu is open, toasts wait: low-priority ones are dropped and priority ≥ 4 shows when the menu closes.
- **System log.** Press **L** (gamepad **L3**, action `toggle_log`) for the last 50 lines, during play or over the pause menu. Tab / Y were taken by `swap_weapon`.
- **Achievements.** 23 in [`data/achievements.json`](data/achievements.json). When one unlocks, a toast appears and the profile is saved. **Esc → Achievements** lists them all (secret ones show as ??? until earned).
- **Profile.** `user://profile.json` keeps unlocks (with timestamp and seed) and lifetime stats: runs, best depth, total kills and floors, victories, collapses, deaths by cause, last seed. It is saved on every unlock and at the end of every run. A missing file starts blank; an unreadable one is renamed to `profile.json.corrupt`. Read it anywhere with `const Profile = preload("res://scripts/core/profile.gd")` and `Profile.best_depth()`, `total_runs()`, `total_kills()`, `total_floors()`, `victories()`, `deaths_by_cause()`, `last_seed()`, `is_unlocked(id)`, `unlocked()` or `stats()`.
- **Telemetry.** Each finished run writes `user://telemetry/run-<unix>-<seed>.json`, and the newest 50 are kept. A report holds `RunState.summary()`, the tick ledger, seconds per room (`"<depth>:<room>"`), a count of every bus signal, the run's unlocks and every announcer line with its fate (`shown`, `preempted`, `dropped_modal`, `dropped_stale`, ...), for tuning.
- **Where `user://` is:** Linux `~/.local/share/godot/app_userdata/DCC Game — Technical Prototype/`, Windows `%APPDATA%\Godot\app_userdata\DCC Game — Technical Prototype\`, macOS `~/Library/Application Support/Godot/app_userdata/DCC Game — Technical Prototype/`. Headless test runs (`--script`) use the `test/` subfolder so they never touch your profile.

**Adding lines.** Edit [`data/announcer.json`](data/announcer.json): `lines` maps a trigger key to an array of `{"text", "weight", "priority", "cooldown_seconds", "once_per_run", "category"}`. Text is at most two lines (`\n`) of 90 characters. Placeholders are `{depth}`, `{kills}`, `{ticks}`, `{seed}`, `{level}`, `{hp}`, `{max_hp}`, `{xp}` and `{room}`, plus some that only certain triggers can use: `{enemy}` (kills, big hits, the defeat obituary), `{damage}`, `{streak}`, `{achievement}` / `{quip}` and `{idle}`. Categories are `flavour`, `warning`, `celebration`, `sponsor`, `taunt`, `obituary`, `achievement` and `system`. Selection is weighted and seeded (`run seed ^ request counter`), so a replayed seed replays its lines. A shown line puts its trigger on cooldown, and a `once_per_run` line is not repeated until the next run. `tests/announcer_test.gd` validates the file: known triggers, unique texts, placeholders allowed for the trigger, numeric ranges, and at least 5 lines per common trigger. Everything is original writing. Keep the tone corporate, cheerful and indifferent, aim the joke at the situation, never at people, and keep it PG-13.

**New triggers and custom announcements.** Room kinds get `room_entered.<kind>` (add the kind to `ROOM_KINDS` in `scripts/core/announcer_lines.gd`), each enemy may get `enemy_killed.<definition_id>`, and fixed keys live in `FIXED_TRIGGERS`. From any system:

```gdscript
Events.announcement_requested.emit("chest_opened", {})                  # a line from the data
Events.announcement_requested.emit("mimic_bit_you", {"text": "That chest had teeth.", "priority": 3})
```

Unknown triggers with a `text` show that text verbatim (priority defaults to 2, category to `system`). **New achievements** are a JSON record whose `event` is a signal name and whose `requires` maps keys (`run.kills`, `room.damage_taken`, `floor.revisits`, `floor.seconds`, `hp_fraction`, `ticks`, `depth`, `life.kills`, `event.<field>`, ...; see `TRACKER_KEYS` and `LIVE_KEYS` in `scripts/core/achievements.gd`) to `{"<op>": value}` with `>=`, `<=`, `>`, `<`, `==`, `!=`, `in` or `contains`. Achievements can also be granted directly with `Events.achievement_unlocked.emit(id)`.

## Run tests

From the repository root, with `godot` pointing to Godot 4.7.2 (or `GODOT=/path/to/godot`):

```sh
game/tests/run_all.sh
```

It runs, failing fast with a summary: the import step, `tests/scripts_parse_test.gd` (compiles every script; the import alone does not report parse errors), `tests/smoke_test.gd`, every other `tests/*_test.gd`, and a short launch of the main scene. A step fails on a non-zero exit, a timeout, or any `SCRIPT ERROR` in its output. GitHub Actions runs the same script (`.github/workflows/godot-ci.yml`).

| Test | Covers |
| --- | --- |
| `smoke_test.gd` | Pure logic: layout, assets, RPG math, allocation, catalogue, generation, obstacles, encounters, facing, Input Map |
| `determinism_test.gd` | Seed 424242 floor signature, obstacle maps, encounters and a scripted combat trace equal constants captured from the pre-refactor `main.gd` |
| `run_state_test.gd` | `RunState`: start_run, multi-level XP, allocation, damage/heal clamps, ticks, telemetry, summary |
| `events_test.gd` | `Events` signals during scripted door transitions, kills, boss gate, death, collapse and escape |
| `menu_integration_test.gd` | Live `Main.tscn`: level-up/pause modals, state machine, resolution, F9/R, Input-Map-driven physics loop |
| `scripts_parse_test.gd` | Every script under `scripts/` and `tests/` compiles |
| `announcer_test.gd` | Announcer data validator, placeholders, seeded selection, cooldowns, once-per-run, preemption, rate limit, modal suppression; live toasts, log, achievements page and telemetry in `Main.tscn` |
| `achievements_test.gd` | Achievements on scripted event sequences (never twice), profile save/load and corrupt-file recovery, telemetry report keys and 50-file retention |

**Writing tests that touch autoloads.** In `--script` mode (Godot 4.7.2) the `Events` and `RunState` autoload nodes already exist under `/root` when `_initialize()` runs (their `_ready()` runs a frame later), but their global identifiers are **not** visible to the test script or anything it `preload`s, because those compile before autoloads are registered. A compile error there makes Godot hang instead of exiting. So: fetch autoloads with `get_root().get_node("RunState")`, and `load()` game scripts or `res://scenes/Main.tscn` at runtime instead of `preload`ing them. Pure-logic modules that never mention an autoload can still be preloaded.

## Technical structure

The runtime is event-driven. Two autoloads hold shared state and messaging; `Game` orchestrates; each child node has one job; pure-logic modules stay free of nodes.

```text
game/
├── project.godot               # autoloads (Events, RunState) and the Input Map
├── README.md
├── assets/                     # see assets/README.md (separate files, 8-way facing contract)
├── scenes/Main.tscn            # Game root + Player, Combat, RoomRenderer, Hud, CharacterMenu
├── scripts/
│   ├── core/
│   │   ├── events.gd           # autoload Events: the signal bus (documented per signal)
│   │   ├── run_state.gd        # autoload RunState: run data, progression math, telemetry
│   │   ├── announcer_lines.gd  # announcer.json validator + {placeholder} resolver
│   │   ├── announcer_brain.gd  # seeded line picking, cooldowns, toast queue rules (pure)
│   │   ├── achievements.gd     # achievement tracker and rules (pure)
│   │   ├── profile.gd          # user://profile.json: unlocks, lifetime stats (static accessors)
│   │   └── telemetry.gd        # per-run report to user://telemetry/
│   ├── game.gd                 # orchestrator + State {RUNNING, LEVEL_UP, PAUSED, ENDED}:
│   │                           #   floor generation, room loading, doors/collapse, restarts, menus
│   ├── player.gd               # movement + collision, aim, facing, cooldowns, i-frames (Input Map)
│   ├── combat.gd               # projectiles, melee arc, d20 hits, enemy AI/attacks, apply_damage()
│   ├── room_renderer.gd        # immediate-mode drawing of the room, doors (tick previews), actors
│   ├── ui/hud.gd               # status lines, message line, minimap, hints, end-of-run overlay
│   ├── ui/announcer.gd         # "The System": toasts, system log, achievements, profile, telemetry
│   ├── character_menu.gd       # level-up allocation, pause and stat screens
│   ├── floor_generator.gd      # deterministic graph and route queries
│   ├── room_layout.gd          # fixed 24x24 world, fit-to-window scale
│   ├── room_contents.gd        # obstacle generator and reachability checks
│   ├── enemy_system.gd         # definitions, encounters, navigation
│   ├── rpg_rules.gd            # six stats, d20 attack and XP progression
│   └── collapse_policy.gd      # room-specific timing policy and ledger
├── data/
│   ├── prototype_rules.json    # collapse, obstacle count, player abilities
│   ├── enemies.json            # enemy behavior, stats, attacks, encounter tables
│   ├── announcer.json          # system lines by trigger, toast/rate-limit settings
│   └── achievements.json       # achievement definitions
└── tests/
    ├── run_all.sh              # runs everything below; used by CI
    └── *_test.gd               # see "Run tests"
```

**Data flow.** `RunState` is the single source of truth (seed, depth, floor, current room, ticks, XP/level, scores, HP/AC, visited rooms, persisted `room_states`, tick ledger, reserved `inventory`/`skills`, `telemetry`, parsed `config`). Systems change it through its methods (`start_run`, `reset_for_floor`, `award_xp`, `apply_damage_to_player`, `heal_player`, `apply_stat_allocation`, `apply_tick_entry`, `add_ticks`, `end_run`, `summary`), and everything that happens is announced on `Events` (`room_entered`, `ticks_changed`, `enemy_damaged`, `enemy_killed`, `player_damaged`, `level_up`, `run_ended`, `message`, ...). `Game` reacts to `enemy_killed` (XP, boss gate), `level_up` (modal) and `player_died` (defeat); `RunState` counts telemetry from the bus; `Hud` shows the newest `message`. All damage flows through `Combat.apply_damage(target, amount, context)`, and all combat dice use `RunState.rng`, so the same seed and inputs replay identically.

**Adding a feature** usually means: add state to `RunState` (or use the reserved `inventory`/`skills`), add or reuse a signal in `events.gd`, and subscribe from your own node rather than editing `game.gd`. Room drawing is still immediate mode; a `TileMapLayer` plus sprite nodes is the candidate follow-up when animation work starts.

### Important scope limits

This is a **technical prototype**, not a finished game. It supports multiple basic melee/ranged enemies and a starter XP/stat system, but it has only one floor, no classes or skill selection, no inventory/loot, no companion AI, no finished movement/attack animations, audio, or saves. The player cannot independently visit a floor overview; the minimap is a discovery/debugging aid. Enemy and boss abilities, guild-hall behavior, rewards, and clock numbers require playtesting and subsequent design decisions.

## Troubleshooting

- If Godot cannot locate the main scene, make sure you imported/opened the **game/** directory, not the repository root.
- If controls do not respond, click inside the running game window.
- Resize the window by dragging its border, or choose **Esc → Display resolution → Apply resolution**. The **24×24 room never changes**; only its visual scale/centering and screen-space HUD change.
- Replaying with **R** repeats the graph exactly but moment-to-moment mouse and keyboard inputs are not recorded.
- If an edited JSON file is invalid, the game reports an error and exits; use the headless smoke-test command after making rule changes.

**Asset distribution note:** The sampler README does not include an explicit redistribution license. Before publicly distributing builds or source asset files, confirm the permissions associated with the supplied pack.
