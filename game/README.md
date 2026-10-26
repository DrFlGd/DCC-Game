# DCC Game — Godot 16×16 Stone-Crypt Prototype

This is the **D-01 Option A technical spike**, not a finished game. The first environment now uses the **user-provided 16×16 dungeon sampler tiles** and separate graphics files for the stone-crypt biome, the player and each enemy type (generated placeholders for most of the Wave 2C roster). All actors have eight direction-dependent idle sprites. The projectile effects, HUD, guild marker, and melee telegraph remain simple debug graphics.

## Engine

**Godot 4.7.2 stable, standard/GDScript build** (not .NET). Engine version was pinned to the latest stable 4.7.2 listed in the official download archive when the project was set up. Get it at https://godotengine.org/download/archive/4.7.2-stable/.

## Quick start

1. Install Godot 4.7.2 standard.
2. Open Godot Project Manager and **Import** `game/project.godot` from this repository.
3. Press **F6** while `scenes/Main.tscn` is open, or **F5** to play the project. The game opens on the **title screen**: choose **New run** (random seed), type a whole number and choose **Seeded run**, open **Settings**, or **Quit**. Keyboard (arrows + Enter) and gamepad (D-pad + A) move between buttons.
4. Resize the game window by dragging an edge; the room remains **24×24 tiles** and scales to fit. Walk toward decorated door openings to enter the next room. Door labels show the *net tick change* (a negative value means ticks spent; a positive value means granted). Door artwork appears closed even though connected doors are traversable; doors **sealed** by a fight (D-07) get a red tint, an iron bar and a gold lock, and fade open when the room is cleared.

| Input (keyboard / mouse) | Gamepad default | Input Map action | Effect |
| --- | --- | --- | --- |
| WASD or arrow keys | Left stick | `move_up/down/left/right` | Move (the D-pad is the consumable belt since Wave 2B) |
| Mouse | — (right stick reserved as `aim_*`) | — | Aim freely in any direction |
| Hold left mouse button | Hold RT | `fire` | Shoot projectiles |
| Hold Space | Hold RB | `melee` | Melee attack in aim direction |
| Shift | B | `dodge` | Dodge roll: 48 px in the move direction (aim direction when standing still), i-framed for 0.2 s, costs 35 stamina |
| Esc | Start | `pause` | Open pause menu, view character stats, or resume; closes the settings page |
| Pause → Display resolution | — | — | Choose a common windowed resolution and click **Apply resolution** (saved to settings) |
| Pause → Settings / Abandon run | — | — | Open the settings page; abandon the run (asks to confirm, ends as *abandoned*) |
| Arrows / Enter on menus | D-pad / A | `ui_*` (built in) | Move between and press buttons on the title, intermission, summary and settings screens |
| F9 (prototype debug) | — | `debug_level_up` | Award XP up to the next level so you can test the level-up menu immediately |
| Mouse in level-up menu | — | — | Assign and refund points with + / −, then confirm |
| R | — | `restart_seed` | Restart using same seed (during a run or on the run summary) |
| N | — | `new_seed` | Restart using a new seed (during a run or on the run summary) |
| L | L3 (left stick press) | `toggle_log` | Show / hide the system log (see [The System](#the-system)) |
| E | A | `interact` | Use the feature in reach when the HUD shows a prompt: open a chest, pray at a shrine, rest at the guild hall, browse the shop, pick up a weapon / active item / loot box, swap a belt slot |
| Q | LB | `use_item` | Use the active item (when charged) |
| C | D-pad down | `use_consumable` | Use the selected consumable belt slot |
| V | D-pad right | `next_consumable` | Select the next belt slot |
| M | Back / Select | `map` | Open / close the full floor map (the world freezes; Esc also closes it) |
| 1 / 2, mouse | D-pad / A | — | Pick a shrine option; Esc walks away without using it |

Gameplay code reads **Input Map actions** (Project → Project Settings → Input Map), never raw keycodes, so bindings can be changed without touching scripts. Movement uses physical key positions (WASD works on any layout). `dodge` is live (Wave 2D). `use_item`, `use_consumable` and `next_consumable` are live (Wave 2B). Reserved actions with default bindings: `swap_weapon` (Tab / Y) and `aim_up/down/left/right` (right stick); `interact` and `map` are live (Wave 2E). Free gamepad inputs: X, LT, R3, D-pad up / left. `tests/inventory_test.gd` fails if two gameplay actions share a key or button. Aiming is still mouse-only.

**Goal:** on each floor, defeat the boss (red/pink room), then enter the exit (gold room) before the clock hits zero. Taking the exit opens the **intermission** (floor recap, a heal of half your missing HP, **Descend**), and the next, larger floor starts with a fresh clock. Clearing the exit of floor **6** (`run.target_depth`) wins the run. Death, collapse, abandoning or winning opens the **run summary** (outcome, cause, depth, rooms, ticks spent/granted, kills, damage, level/XP, time, copyable seed) with **Retry seed**, **New run** and **Title**. Guild halls grant sample bonus ticks. Normal rooms spend a **threat budget that grows with depth** (2–4 enemies on floors 1–2, up to 6 by floor 5); every enemy attack has a visible **wind-up telegraph** you can dodge, and enemies wait 0.6 s when you enter. Boss rooms hold the depth's boss (Armored Brute on floors 1–2, Sump Warden from floor 3) plus an escort; bosses change phase at HP thresholds and show an HP bar at the top. Killing enemies earns XP and levels. The minimap shows visited rooms and the exit location.

## What works

- Seeded 2D procedural room graph with branches and adjacency-created loops, plus start/boss/guild-hall/exit tags and side-room **treasure, elite, trap and shrine** rooms; infeasible layouts are re-rolled deterministically.
- **Collapse clock v1:** never-refused doors, a zero-clock grace period with escalating debris, stabilising by regaining ticks, and a hard collapse when the grace runs out.
- **Interactions** (E): treasure chests, shrines, the guild-hall rest station and shop; spike and tick-drain pressure plates in trap rooms.
- **Floor map** (M): visited and scouted rooms by kind, door costs from the current room.
- Room transitions via matching cardinal doors, room discovery, and an exit locked until the boss is defeated.
- Editable collapse rules for first entry, revisits, boss rooms, guild halls, and exit, with an entry ledger printed to Godot's **Output** panel.
- Visible tick/health HUD (`FLOOR d/6`), door preview of net tick effects, and restart handling.
- **Six-floor run loop:** title screen (random or typed seed), per-depth room counts and fresh collapse budgets, between-floor intermission, victory on floor 6, run summary for every outcome, abandon from pause, and persisted settings.
- Omnidirectional aim; ranged fire and directional melee; basic damage and enemy AI; enemy health/state maintained across revisits.
- A seeded smoke-test suite covering topology, deterministic generation, room tags, policies, and a route-budget diagnostic.
- **16×16 dungeon sampler stone floors, masonry, torches, side edges, double-leaf doors and prop sprites**. Free sampler omits true corner/south wall pieces, so temporary matching wall-top rotations fill those joins.
- **Eight-way facing sprites** for the player (mouse aim) and every enemy (AI facing); see [`assets/enemies/README.md`](assets/enemies/README.md).
- **Separate per-biome and per-character/enemy assets** rather than a master atlas. See [asset conventions](assets/README.md).
- **Fixed 24×24 interior tiles (384×384 world pixels)**; resize changes only rendering scale and screen-space HUD. Minimum window 720×480, with selectable common window resolutions from the pause menu.
- **Deterministic rubble and pillar obstacles**, tested for walkable routes from room center to every connected exit.
- **Data-driven enemy roster** (9 archetypes across 7 roles, 2 elite modifiers, 2 phased bosses), depth-scaled threat budgets, telegraphed attacks, hazards and summons, and a six-ability d20-inspired XP/level system.
- **Automatic level-up menu** when XP crosses a threshold. Combat freezes while you allocate ability points; the menu shows live previews and protects against overspending.
- **Esc pause menu and character-stat page** with HP, AC, level, XP, proficiency, six scores/modifiers, and derived melee/ranged attack bonuses.

## Items and loot

Wave 2B wires the content layer (`data/content/*.json`, Wave 1B) into play. Design: [CONTENT_RULES.md §10](../docs/design/CONTENT_RULES.md) and [COMBAT_AND_RPG.md §5, §7, §12](../docs/design/COMBAT_AND_RPG.md#12-d-09--inventory-and-resources).

- **Loadout.** You hold 1 melee weapon, 1 ranged weapon, 1 active item, any number of passives (stacked up to `stack_max`) and a 6-slot consumable belt. A run starts with the crowbar and the nail pistol (`run.starting_loadout`), which reproduce the prototype attacks exactly. The HUD's loadout panel (bottom right) shows weapons, the active item's recharge, the belt with the selected slot, credits and your statuses. **Esc → Inventory** lists everything with descriptions.
- **Weapons.** Each weapon's `attack_pattern` decides the attack: melee `arc`, `thrust` (a lane, nearest first, through `pierce`) or `spin`; ranged `single`, `spread`, `burst` or `beam` (hitscan). Damage, cooldown, reach, knockback and pierce come from the weapon record, plus passives and statuses (`Loadout.attack_profile`).
- **Pickups.** Loot lies on the floor as a rarity-coloured diamond; standing on it shows its card as a tooltip. Passives and consumables are picked up on contact. Weapons, active items and loot boxes need **E**; the replaced weapon or active drops where you stand. With a full belt, **E** swaps the selected slot for the new consumable. A **NEW ITEM** card slides in at the right for every pickup.
- **Where loot comes from.** A `floor_start` package at the start of every floor; `room_normal_clear` when a normal, elite or trap room is cleared (80 % on floors 1–2, 90 % on 3–4, always from 5); chests drop their roll as pickups around the chest; a boss leaves a **loot box** (one more roll at CHA modifier +3 or higher). Loot rolls use their own seeded RNG (seed, depth, room, salt), never `RunState.rng`, so loot never changes the combat dice.
- **Credits** come from kills (a tenth of the XP, at least 1) and room clears (normal 4, elite 10, trap 4, boss 20). The guild-hall **shop** (E) offers 3 items from `guild_hall_shop`. Prices rise with rarity, and each positive CHA modifier takes 10 % off, up to half. Bought items are marked sold out.
- **Statuses** (`burning`, `poisoned`, `bleeding`, `slowed`, `stunned`, `shielded`, `hasted`, `evasive`, `concealed`) work on you and on enemies. They are shown as coloured pips above HP bars. Enemy attacks and hazards can apply them (spore puddles poison, firebombs burn). Bosses ignore stun and root, and slows last half as long on them.
- **Triggers.** Item effects fire on `on_hit`, `on_kill`, `on_damage_taken`, `on_room_enter`, `on_room_clear`, `on_level_up`, `on_dodge`, `on_use` and `periodic`. A clock-touching item (`grant_ticks`) also stabilises the collapse grace like any other tick gain.
- **For other systems.** `Loadout.current(slot, weapon_id)` returns the equipped entries for `EffectResolver.collect_modifiers()`. `StatusSystem.apply(target, effect, source)` applies a status to `"player"` or an enemy dictionary. `EffectRunner.fire(combat, trigger, extra)` fires a trigger. `Pickups.spawn(room_id, id, pos)` drops an item.

## Feel

Combat feel lives in Wave 2D. Design: [COMBAT_AND_RPG.md §3, §8, §9](../docs/design/COMBAT_AND_RPG.md#3-movement-dodge-and-stamina).

- **Dodge roll.** Press **Shift** (gamepad **B**) to roll 48 px in 0.25 s. The roll passes through enemies, slides along obstacles and cannot pass a sealed door. The first 0.2 s are invulnerable, and a 0.1 s recovery follows in which you cannot attack or dodge. A dodge cancels attack recovery but not an attack's wind-up or active frames.
- **Stamina.** The roll uses the pool shown as the bar under the HP line: 100 stamina, 35 per roll, refilling at 30/s (+10 % per positive WIS modifier) after 0.6 s without spending. That is two rolls back to back, then a third about 0.75 s later.
- **Attack movement penalty.** Attacking slows you: melee arcs to 60 % (thrust 40 %, spin 50 %), shooting to 85 %.
- **Knockback.** Melee hits knock enemies back, 20 px by default. `knockback_resist` reduces this, and bosses take a quarter at most. A push stops at walls without wall-slam damage, and it interrupts a bell acolyte's chant.
- **Hit feedback.** Your hits stop time briefly (40 ms, 70 ms on a crit, 90 ms on a kill or boss phase change) and flash the target. Damage floats up as numbers: yellow for a crit, grey `MISS`, red on you. The screen shakes and kills burst into particles. The *Damage numbers* and *Screen shake* settings control those two cues.
- **Sealed rooms (D-07).** In normal, elite, boss and trap rooms with enemies, the doors seal 0.5 s after you are 24 px past the doorway. They open on clear with a **ROOM CLEAR** moment, or as soon as the collapse grace starts. A 15 s failsafe removes enemies that cannot reach you (with no XP) and logs it as a generator bug.
- **For skills and items.**
  - `RunState.spend_stamina(cost) -> bool` spends stamina.
  - `Events.dodged(direction)` and `Events.stamina_changed(current, max)` report rolls and stamina.
  - `Events.doors_locked(room_id)` and `doors_unlocked(room_id, reason)` report the door lock.
  - `combat.on_player_dodged(direction)` is the `on_dodge` hook.
  - `combat.fx` triggers feedback: `request_hitstop(s)`, `hitstop_for(cue)`, `shake(Fx.SHAKE_*)`, `number(key, pos, value, style)`, `flash(key, color)` and `burst(pos, color)`.
  - A skill dash is `player.start_dash(direction, distance, duration, iframes, recovery)` followed by `combat.on_player_dodged(direction)`.

## Visual and tile layout

**D-13 revised:** Standard environment tile dimensions are **16×16 native pixels**. The stone-crypt floor uses the provided [`tileset_16x16.png`](assets/biomes/stone_crypt/tileset_16x16.png), an 8-column/2-row sampler atlas with 12 supplied sprites: two floors, wall top and edges, wall face/torch, wood door, stairs, barrel, chest and bones. Each connected side has a **two-tile-wide (32px) opening**, decorated with two native 16px door leaves.

**Every room remains exactly 24×24 tiles = 384×384 world pixels**, independently of display resolution. Game movement speeds, combat ranges, collision footprints and enemy AI spacings were halved relative to the previous 32px prototype to keep approximately the same gameplay-to-tile proportions. The window can still scale the room up or down. Use **Esc → Display resolution → Apply resolution** or drag the window border; neither changes the dungeon tile count.

This is the **free sampler**, not the complete tile pack. Its README mentions dedicated bottom corners and a south-wall edge that are **not included in the supplied 12-tile assets**. We temporarily join outer corners and south walls with rotated wall-top tiles, and use wall faces/torches for the north side. These transitions can be revisited after acquiring/creating the missing pieces.

Player and rat sprite sheets remain separate. The **crawler and ordinary enemies render at 24×24** (about 1.5 terrain tiles), and the **boss at 48×48** (3 tiles). They retain all eight compass facings E, SE, S, SW, W, NW, N, NE. Source frames can be higher resolution; the renderer displays them with nearest-neighbor scaling. The 8 poses are prototype facings, not movement animations.

See [asset conventions and tile index](assets/README.md) for the complete mapping. Doors still look closed even when the procedural graph permits passage; proper door open/locked sprites and animation remain future work.

## Enemy and RPG design references

See [the gameplay systems specification](../docs/design/ROOM_ENEMY_RPG_PROTOTYPE.md) for how to add enemy types, pick a behaviour mode, choose BFS/direct/stationary navigation, edit attacks and abilities, and tune enemy XP. [ENEMY_TIERS.md](../docs/design/ENEMY_TIERS.md) lists the roster, bands, guardrails and the `enemies.json` v2 schema; [ENCOUNTER_RULES.md](../docs/design/ENCOUNTER_RULES.md) the budgets and spawn rules. `Enemies.validate_catalogue()` rejects an unknown behaviour, attack type or ability by name, and checks every attack against the per-band guardrails (wind-up, damage, projectile speed). The player HUD shows six attributes, AC, HP, proficiency, level, and cumulative XP. D20 attacks use relevant stat modifiers, proficiency, and armor class. This is an action-game adaptation, **not full tabletop D&D**.

## Level-up and pause menus

When XP crosses a level threshold, combat stops and a **Level Up** overlay appears. For quick testing, press **F9 during gameplay** to jump to the next level (debug-only shortcut). The default is **2 free ability points per level gained** (this is a game-design adaptation, **not** D&D's class-specific Ability Score Improvement rule). The screen shows each of the six ability scores and its modifier, with **+** and **−** buttons to stage/undo points. Points are only applied when you select **Confirm allocation**, and confirmation remains disabled until all available points are assigned. Level jumps grant points for every level earned in that XP award. Scores cannot exceed the configured cap (default **20**).

New scores immediately update AC (DEX), max HP (CON), STR-based melee and DEX-based ranged attack bonuses, and any relevant damage modifiers on new attacks. Raising CON grants the corresponding max-HP increase to current HP. All points are lost on starting a new run.

Press **Esc** to open the pause menu. Choose **View character stats** to see your build, select one of the built-in **windowed resolution presets** (800×600, 960×540, 1024×768, 1280×720, 1280×800, 1366×768, 1440×900, 1600×900, 1920×1080, 2560×1440, 3840×2160) and click **Apply resolution**, or select **Resume game** to return. Large options may be limited by your monitor/window manager; resizing affects the viewport, not the fixed 24×24 room. Esc resumes from either pause page. Pausing and leveling both freeze player movement, enemy AI, cooldowns, and projectiles; the collapse clock does not change. **The level-up screen cannot be skipped**; this is intentional for the current prototype.

Player stat allocation is validated by [`scripts/rpg_rules.gd`](scripts/rpg_rules.gd), and menu rendering/input live separately in [`scripts/character_menu.gd`](scripts/character_menu.gd). Gamepad bindings exist for movement, fire, melee and pause; gamepad aiming and menu navigation, plus more UI/audio accessibility, remain future tasks.

## Run flow and screens

`Game` (`scripts/game.gd`) is a state machine: `TITLE → RUNNING ⇄ PAUSED / LEVEL_UP → INTERMISSION → RUNNING (next floor) … → SUMMARY → TITLE or RUNNING`. Every change emits `Events.game_state_changed(previous, current)` with the state names. The screens are code-built `CanvasLayer`s in `scripts/ui/` (`title_screen.gd`, `intermission_screen.gd`, `summary_screen.gd`, `settings_screen.gd`, sharing `screen_base.gd`); they only emit requests, and `Game` acts on them. Simulation and the run clock (`run_time_seconds`) only advance in `RUNNING`.

**Settings** (`scripts/core/settings.gd`, a plain `RefCounted` with one shared instance, `Settings.shared()`) hold the window resolution preset, fullscreen, master, music and effects volumes (applied to the audio buses by `scripts/audio.gd`), damage numbers on/off and screen-shake intensity. They are loaded and the window settings applied at startup, saved to `user://settings.cfg` on every change, and announced with `Events.settings_changed(values)`. `--script` test runs use `user://settings_test.cfg` instead.

## Editing the clock and floor

Open `data/prototype_rules.json`. Restart the game after editing it.

- `seed`: default seed (424242) used by tests and CI; the title screen picks a random seed for **New run** or takes one for **Seeded run**. Use **R** to reproduce a run, **N** for a new seed.
- `run.target_depth`: the floor whose exit wins the run (default 6).
- `run.rooms_by_depth`: number of **rooms per floor** for depths 1–6 (22, 26, 30, 34, 40, 44), unrelated to the fixed 24×24 **tiles per room**. Deeper floors add `run.rooms_per_extra_depth` (6) per floor, capped at `run.max_rooms` (80). Floor *d* is generated from `RunState.floor_seed(d)`; floor 1 uses the run seed unchanged.
- `run.intermission_heal_ratio`: share of *missing* HP restored at the intermission (0.5, rounded up).
- `obstacle_count`: target blocking prop count for normal rooms; safe rooms use fewer.
- `player_ability_scores`: six editable starting attributes (STR/DEX/CON/INT/WIS/CHA); HP, AC, attack bonuses, and progression derive from these.
- `stat_points_per_level`: points earned for each new level (default 2).
- `stat_score_cap`: upper limit for each ability score (default 20).
- `collapse.budget.min_slack` / `slack_ratio`: each floor's fresh budget is **cheapest mandatory route cost + max(min_slack, ceil(slack_ratio × rooms))** (8 and 0.45; [COLLAPSE_SYSTEM.md §4](../docs/design/COLLAPSE_SYSTEM.md#4-starting-budget-and-depth-scaling)), computed in `scripts/core/run_rules.gd`. The route cost is a Dijkstra search start → boss → exit over first-entry costs, with each room's net cost clamped at 0 and the exit cost included. For seed 424242, floor 1 is 16 + 10 = **26** ticks (as before), floor 2 is 30. Leftover ticks never carry over.
- `start_ticks`: provisional clock set by `RunState.start_run` before the floor budget replaces it (and what `RunState` uses on its own in unit tests).
- `collapse.default.first_entry_cost` / `revisit_cost`: fallback transition cost.
- `collapse.default.clear_refund`: ticks refunded when any room is cleared (0, an experiment knob).
- `collapse.room_types.<kind>`: per-kind override of `first_entry_cost`, `revisit_cost`, `first_entry_grant` and `clear_grant` for `start` (0), `normal` (default 2), `boss` (3), `guild_hall` (0, grants 3), `exit` (1), `treasure` (2), `elite` (3, +1 on clear), `trap` (1) and `shrine` (1).
- `collapse.budget.max_start_ticks` (70) / `guild_max_ratio` (0.5): generator feasibility limits: a floor budget above 70, or a guild hall whose cheapest path costs more than half the budget, re-rolls the layout.
- `collapse.grace.seconds` (10) / `repeat_seconds` (5) / `max_per_floor` (2): the zero-clock grace period. `collapse.grace.waves[]` is the debris table (`above` seconds left, `interval`, `markers` per wave, `shake` px); `collapse.grace.debris` the marker (`radius` 14, `telegraph` 0.8 s, `damage` 2, `duration` 0.15 s, `hits_enemies`).
- `generation.special_rooms.counts_by_depth[]`: treasure / elite / trap / shrine counts; the last row whose `min_depth` ≤ depth wins, missing kinds keep the previous row's value (defaults: 1 treasure everywhere, elite 1 from depth 2, trap 1 from depth 2 and 2 from depth 5, shrine 1 from depth 3). `guild_min_hops` (2) and `elite_min_hops` (3) are placement distances from the start room.
- `generation.feasibility.max_attempts` (20) / `seed_stride` (104729): an infeasible floor is regenerated with `seed + attempt × stride`; the outcome is stored in `floor["feasibility"]`.
- `hazards.spike_plate` / `drain_plate` / `trap_plates`: pressure-plate hazards in trap rooms (spikes: 3 damage after 0.5 s, rearm 2 s; drain: −1 tick after 0.6 s if you are still on it, one-shot; 2–4 plates per room, 1–2 of them drains).
- `room_obstacle_caps`: obstacle cap per kind (13 for start, guild hall, exit, treasure and shrine; 20 trap; 30 elite; boss and normal use `obstacle_count`).
- `interaction.radius` (26 px), `shrine_ticks` (+2), `shrine_heal_ratio` (0.5 of max HP).
- `run.starting_loadout` (`["wpn_crowbar", "wpn_nail_pistol"]`): content ids granted at run start.
- `items`: `consumable_slots` 6, `pickup_radius` 10 px (contact pickups), `hover_radius` 14 px (tooltip and E), `drop_spread` 18 px, `floor_start_every_floor`, `room_clear_kinds`, `room_clear_chance_by_depth` (a gate before the loot table's own `empty_chance`), `nearby_enemy_radius` 64 px (the `nearby_enemies` condition).
- `credits`: `start` 0, `per_kill_xp_ratio` 0.1, `min_per_kill` 1, `room_clear` by kind.
- `shop`: `offers` 3, `rarity_price_multipliers`, `cha_discount_per_mod` 0.1, `max_discount` 0.5, `min_price` 1.
- `feel.stamina` (`max` 100, `regen_per_second` 30, `regen_delay` 0.6, `wis_regen_per_mod` 0.1).
- `feel.dodge` (`cost` 35, `distance` 48, `duration` 0.25, `iframes` 0.2, `recovery` 0.1, `cooldown` 0, the input `buffer` 0.12).
- `feel.attack_timing` (melee active / recovery 0.1 / 0.18 s, ranged recovery 0.28 s) and `feel.attack_move_multipliers` (arc 0.6, thrust 0.4, spin 0.5, ranged 0.85).
- `feel.knockback` (`default_melee` 20 px, `boss_mult` 0.25, `str_bonus_per_mod` 0.05).
- `feel.hitstop`: seconds per cue, plus the `window` / `window_budget` cap of 120 ms per 0.5 s.
- `feel.door_lock` (`delay` 0.5, `inset` 24, `failsafe_seconds` 15, `locking_kinds`).

**The collapse clock (v1, [COLLAPSE_SYSTEM.md](../docs/design/COLLAPSE_SYSTEM.md)).** Doors are never refused for lack of ticks; only the sealed exit refuses. A cost larger than what is left takes the clock to 0. When the clock reaches 0 by anything other than the exit, a **10 s grace period** starts: the tick counter becomes a red countdown, doors stay unlocked, entering rooms is free (first-entry grants still apply) and falling-debris markers telegraph for 0.8 s before dealing 2 damage (a dodge's i-frames avoid them). Regaining any ticks (guild hall, shrine, elite clear, items) stabilises the floor; a second zero on the same floor gives 5 s, a third collapses at once. The timer running out ends the run as **collapsed**. The unsealed exit always resolves first, so leaving with exactly the last tick, or during grace, clears the floor. Pause, level-up, the map and the shrine prompt freeze the grace timer and hazards. The HUD counter turns amber at ≤ 6 and red at ≤ 3, and a door label ends in a red `!` when walking through would leave the clock at 0. No values are final; each floor's room count, route cost and budget are printed to the console when it starts.

**Special rooms.** Side rooms (never the guaranteed spine) can be a **treasure** room (a chest that rolls the `treasure_room` loot table), a **trap** room (spike and tick-drain pressure plates), a **shrine** (one choice: +2 ticks or heal 50 %), or an **elite** room (a harder fight; until the enemies team adds an `elite` table it uses the normal one). The **guild hall** has a rest station (full heal, once per floor) and a shop sign (the shop arrives with the items team). Chest loot is announced (`Events.chest_opened`) but not yet added to an inventory.

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

## Audio

Sound is a presentation layer on the `Events` bus (`scripts/audio.gd`, the `Audio` child of `Game`); nothing in the simulation depends on it, and it never touches `RunState.rng`.

- **Buses.** [`default_bus_layout.tres`](default_bus_layout.tres) defines `Master → Music, SFX, Ambient, UI` (wired in `project.godot`, `[audio] buses/default_bus_layout`). `Audio.ensure_buses()` adds any that are missing, so a stale layout never breaks playback.
- **Settings.** `master_volume`, `music_volume` (also the Ambient bus) and `sfx_volume` (also the UI bus) are 0–1 sliders on the settings page, saved to `user://settings.cfg` and applied on `Events.settings_changed` with `linear_to_db` (0 is -80 dB and mutes the bus, 1 is 0 dB). Defaults: 1.0 / 0.8 / 1.0.
- **Sound effects.** A pool of 12 `AudioStreamPlayer`s plays one-shots round-robin; when every player is busy the oldest slot is reused. Each cue has a `cooldown` (so thirty rat hits in one frame play once), a `max_instances` cap on simultaneous copies and a `pitch_var` spread (combat sounds vary ±6 %). Hits after a swing use the melee hit, after a shot the ranged hit, criticals a higher-pitched variant.
- **Music and ambience.** The Music and Ambient buses each own two players and crossfade (0.6 s) when the Game state changes: `TITLE` → title theme, `RUNNING` → crypt drone, a live boss room → boss drone, `INTERMISSION` / `SUMMARY` → the theme at a lower mix. Pause, map and dialog keep the current tracks. Both loops are seamless (whole-cycle oscillators, a `smpl` loop chunk the importer picks up).
- **Menus.** Every `Button` / `Slider` in the tree is hooked through `SceneTree.node_added`: focus plays `ui.move`, a press `ui.confirm`; opening the pause menu plays `ui.open`, resuming `ui.back`.
- **Headless.** The Dummy audio driver still advances playback, so `tests/audio_test.gd` runs the real node; nothing needs a device.

**Regenerating sounds.** Every WAV is synthesised by [`tools/gen_sfx.py`](../tools/gen_sfx.py) (Python 3, standard library only, deterministic): `python3 tools/gen_sfx.py` from the repository root rewrites `assets/audio/{sfx,ambient,music}/*.wav` (22050 Hz, 16-bit mono, peak -6 dBFS, about 2 MB in total); `--only melee_hit level_up` rewrites a subset. See [`assets/audio/README.md`](assets/audio/README.md).

**Adding or retuning a sound.** Edit [`data/audio.json`](data/audio.json). `cues` maps a trigger to `{"stream", "bus", "volume_db", "pitch_var", "cooldown"}` plus optional `max_instances`, `pitch`, `group` (cues in a group share one cooldown) and `loop` (music/ambient only). A trigger is an `Events` signal name (`chest_opened`), a signal with a payload variant that `audio.gd` picks (`melee_swung.player`, `projectile_fired.enemy`, `enemy_damaged.critical`, `enemy_damaged.melee` / `.ranged`, `player_damaged.hazard`, `credits_changed.gain` / `.spend`, `ticks_changed.gain` / `.loss`, `run_ended.victory` / `.defeat`, `message.<category>`), or a reserved `ui.*`, `music.*` or `ambient.*` name. A signal that is only a cue name (`SIMPLE_SIGNALS` in `audio.gd`, e.g. `item_used`, `level_up`, `skill_learned`) needs no code; delete a cue to mute it. Signals another wave has not landed yet go in `pending_signals` (currently `skill_used`). `states` maps Game states (and `RUNNING.boss`) to a Music and an Ambient cue. From code: `game.audio.play("item_used")` (returns false when throttled or capped), `audio.set_track("Music", "music.title")`. `tests/audio_test.gd` validates the file: streams exist, buses, numeric ranges, every signal named exists on `Events`, every cue the code asks for is mapped.

## Run tests

From the repository root, with `godot` pointing to Godot 4.7.2 (or `GODOT=/path/to/godot`):

```sh
game/tests/run_all.sh
```

It runs, failing fast with a summary: the import step, `tests/scripts_parse_test.gd` (compiles every script; the import alone does not report parse errors), `tests/smoke_test.gd`, every other `tests/*_test.gd`, and a short launch of the main scene. A step fails on a non-zero exit, a timeout, or any `SCRIPT ERROR` in its output. GitHub Actions runs the same script (`.github/workflows/godot-ci.yml`).

| Test | Covers |
| --- | --- |
| `smoke_test.gd` | Pure logic: layout, assets, RPG math, allocation, catalogue, generation, obstacles, encounters, facing, Input Map |
| `determinism_test.gd` | Seed 424242 floor signature, kind-masked geometry, obstacle maps, encounters and a scripted combat trace equal captured constants (regenerated in Wave 2E for the special rooms; the geometry and combat trace are unchanged since the pre-refactor `main.gd`) |
| `run_state_test.gd` | `RunState`: start_run, multi-level XP, allocation, damage/heal clamps, ticks, telemetry, summary |
| `enemies_test.gd` | Enemy schema v2 (shipped and broken records), roster, budgets within 10 % and composition rules over 20 seeds × depths 1–6, boss/elite rooms, spawn constraints, veteran/elite scaling, phases, twin_shot geometry, dormancy and wind-up state machine |
| `enemy_combat_test.gd` | Live `Combat`: wind-up timing and dodging, dormancy on entry, twin_shot hits a still crawler, boss phase roars, bulwark/volatile elites, summon caps, hazards, support wards, knockback, `boss_defeated` for both bosses |
| `events_test.gd` | `Events` signals during scripted door transitions, kills, boss gate, death, collapse and floor clear |
| `menu_integration_test.gd` | Live `Main.tscn`: level-up/pause modals, state machine, resolution, F9/R, Input-Map-driven physics loop |
| `run_loop_test.gd` | Title → `start_run`, room counts and budgets by depth (26 on floor 1 for 424242), exit → intermission → fresh floor with carried XP/HP, last-tick exit, victory on floor 6, summary after death/abandon with Retry/New/Title, run-time freeze, pause → settings, `user://` settings roundtrip |
| `scripts_parse_test.gd` | Every script under `scripts/` and `tests/` compiles |
| `announcer_test.gd` | Announcer data validator, placeholders, seeded selection, cooldowns, once-per-run, preemption, rate limit, modal suppression; live toasts, log, achievements page and telemetry in `Main.tscn` |
| `collapse_test.gd` | Collapse clock v1: never-refused doors, grace lifecycle (10 s, stabilise, 5 s, third zero), debris waves vs the wave table, exit during grace, modal freeze, hazards module, `budget_for` (26 for 424242; 30/36/40/46/50 for depths 2–6), route sweep, feasibility re-roll |
| `rooms_test.gd` | Special-room placement over 20 seeds × 6 depths, interiors and obstacle caps, chest / shrine / guild rest / trap plates on the live game, the interaction registry, the floor map overlay |
| `inventory_test.gd` | Wave 2B: starting loadout, weapon / active swaps and drops, active recharge by seconds / rooms / floors, the belt, passive stacking and stats, scripted pickups, chest and boss loot box, credits, the shop, `grant_ticks` stabilising the grace, loot determinism, Input Map collisions |
| `items_combat_test.gd` | Wave 2B: starter weapons equal the prototype numbers, spread / burst / beam / pierce, melee arc / thrust / spin geometry, `on_hit` and DoT, shields and player statuses, the decoy, boss immunity, `on_kill` / `on_damage_taken`, hazard statuses, a render pass |
| `combat_feel_test.gd` | Wave 2D: dodge distance, timing and i-frames, stamina cost/delay/regen and the two-chain rule, dodge refusals, knockback (resist, walls, interrupts, boss cap, crawler), hit-stop freeze and budget, damage numbers and the setting, movement penalties, door lock timing/kinds/grace/clear, locked-door dodge, 15 s failsafe |
| `achievements_test.gd` | Achievements on scripted event sequences (never twice), profile save/load and corrupt-file recovery, telemetry report keys and 50-file retention |

**Writing tests that touch autoloads.** In `--script` mode (Godot 4.7.2) the `Events` and `RunState` autoload nodes already exist under `/root` when `_initialize()` runs (their `_ready()` runs a frame later), but their global identifiers are **not** visible to the test script or anything it `preload`s, because those compile before autoloads are registered. A compile error there makes Godot hang instead of exiting. So: fetch autoloads with `get_root().get_node("RunState")`, and `load()` game scripts or `res://scenes/Main.tscn` at runtime instead of `preload`ing them. Pure-logic modules that never mention an autoload can still be preloaded.

## Technical structure

The runtime is event-driven. Two autoloads hold shared state and messaging; `Game` orchestrates; each child node has one job; pure-logic modules stay free of nodes.

```text
game/
├── project.godot               # autoloads (Events, RunState), audio bus layout and the Input Map
├── default_bus_layout.tres     # Master -> Music, SFX, Ambient, UI
├── README.md
├── assets/                     # see assets/README.md (separate files, 8-way facing contract)
│   └── audio/                  # generated WAVs (tools/gen_sfx.py): sfx/, ambient/, music/
├── scenes/Main.tscn            # Game root + Player, Combat, RoomRenderer, Hud, CharacterMenu
├── scripts/
│   ├── core/
│   │   ├── events.gd           # autoload Events: the signal bus (documented per signal)
│   │   ├── run_state.gd        # autoload RunState: run data, progression math, telemetry
│   │   ├── run_rules.gd        # rooms by depth, floor budget (route + slack), target depth
│   │   ├── settings.gd         # player settings <-> user://settings.cfg (Settings.shared())
│   │   ├── announcer_lines.gd  # announcer.json validator + {placeholder} resolver
│   │   ├── announcer_brain.gd  # seeded line picking, cooldowns, toast queue rules (pure)
│   │   ├── achievements.gd     # achievement tracker and rules (pure)
│   │   ├── profile.gd          # user://profile.json: unlocks, lifetime stats (static accessors)
│   │   └── telemetry.gd        # per-run report to user://telemetry/
│   ├── audio.gd                # SFX pool, music/ambient crossfade, Events -> data/audio.json cues
│   ├── game.gd                 # orchestrator + State {RUNNING, LEVEL_UP, PAUSED, ENDED(unused),
│   │                           #   TITLE, SUMMARY, INTERMISSION, MAP, DIALOG}: floors, doors, screens
│   ├── collapse_clock.gd       # zero-clock grace driver: timer, debris waves, hard collapse
│   ├── hazards.gd              # ground hazards: telegraph -> active -> expire, drawing (pure)
│   ├── interactables.gd        # interactable entries (chest, shrine, rest, sign...) (pure)
│   ├── room_services.gd        # interact registry + prompts, chest/shrine/rest/sign, trap plates
│   ├── player.gd               # movement + collision, aim, facing, cooldowns, i-frames, dodge/dash, attack phases
│   ├── combat.gd               # projectiles, melee arc, d20 hits, enemy AI/attacks, apply_damage() + feedback/knockback
│   ├── fx.gd                   # hit feedback state: hit-stop, shake, flashes, numbers, death bursts (pure)
│   ├── door_lock.gd            # D-07 door lock, unreachable-enemy failsafe, room-clear moment
│   ├── inventory.gd            # RunState.inventory: slots, belt, credits, active recharge (static)
│   ├── loadout.gd              # Loadout.current(): owned content -> ContentDB.loadout, attack profiles
│   ├── status_system.gd        # statuses on the crawler and enemies: apply, tick, flags, absorb
│   ├── effect_runner.gd        # fires content triggers and executes their effects
│   ├── pickups.gd              # floor pickups per room (room_states[id].pickups)
│   ├── item_system.gd          # node: pickups, loot sources, active / consumables, shop, credits
│   ├── ui/item_card.gd         # NEW ITEM reward card
│   ├── room_renderer.gd        # immediate-mode drawing of the room, doors (tick previews), actors
│   ├── ui/hud.gd               # status lines (FLOOR d/target), clock / grace countdown, prompt, minimap
│   ├── ui/floor_map.gd         # full floor map overlay (M); build_model() is pure
│   ├── ui/choice_dialog.gd     # small modal choice prompt (shrine)
│   ├── ui/announcer.gd         # "The System": toasts, system log, achievements, profile, telemetry
│   ├── ui/title_screen.gd      # New run / Seeded run / Settings / Quit
│   ├── ui/intermission_screen.gd # floor recap + Descend
│   ├── ui/summary_screen.gd    # run summary + Retry seed / New run / Title
│   ├── ui/settings_screen.gd   # settings page (title and pause menu)
│   ├── ui/screen_base.gd       # shared panel/button helpers for the screens above
│   ├── character_menu.gd       # level-up allocation, pause and stat screens
│   ├── floor_generator.gd      # deterministic graph, special rooms, feasibility re-roll
│   ├── room_layout.gd          # fixed 24x24 world, fit-to-window scale
│   ├── room_contents.gd        # obstacles, chests/shrines/rest, trap plates, reachability
│   ├── enemy_system.gd         # catalogue v2 + validator, threat budgets, spawns, enemy AI state machine
│   ├── rpg_rules.gd            # six stats, d20 attack and XP progression
│   └── collapse_policy.gd      # transition pricing, budget (via run_rules), route rooms, grace rules
├── data/
│   ├── prototype_rules.json    # run (depths, rooms), collapse + budget, obstacles, abilities
│   ├── enemies.json            # enemy roster (schema v2), sprite sheets, band guardrails, budgets, elites
│   ├── announcer.json          # system lines by trigger, toast/rate-limit settings
│   ├── audio.json              # Events trigger -> sound cue, state -> music/ambient track
│   └── achievements.json       # achievement definitions
└── tests/
    ├── run_all.sh              # runs everything below; used by CI
    └── *_test.gd               # see "Run tests"
```

**Data flow.** `RunState` is the single source of truth (seed, depth, floor, current room, ticks, XP/level, scores, HP/AC, visited rooms, persisted `room_states`, tick ledger, `inventory` (Wave 2B), `statuses`, reserved `skills`, `telemetry`, parsed `config`). Systems change it through its methods (`start_run`, `reset_for_floor(depth, budget)`, `floor_stats`, `close_floor`, `intermission_heal`, `award_xp`, `apply_damage_to_player`, `heal_player`, `apply_stat_allocation`, `apply_tick_entry`, `add_ticks`, `end_run`, `summary`), and everything that happens is announced on `Events` (`room_entered`, `ticks_changed`, `enemy_damaged`, `enemy_killed`, `player_damaged`, `level_up`, `run_ended`, `message`, ...). `Game` reacts to `enemy_killed` (XP, boss gate), `level_up` (modal) and `player_died` (defeat), and emits `floor_cleared`, `game_state_changed` and `settings_changed`; `RunState` counts telemetry from the bus; `Hud` shows the newest `message`. All damage flows through `Combat.apply_damage(target, amount, context)`, and all combat dice use `RunState.rng`, so the same seed and inputs replay identically.

**Adding a feature** usually means: add state to `RunState` (or use the reserved `inventory`/`skills`), add or reuse a signal in `events.gd`, and subscribe from your own node rather than editing `game.gd`. Room drawing is still immediate mode; a `TileMapLayer` plus sprite nodes is the candidate follow-up when animation work starts.

### Important scope limits

This is a **technical prototype**, not a finished game. It supports multiple basic melee/ranged enemies, a starter XP/stat system and a six-floor descent, but floors differ only in size, seed and enemy roster so far (no biomes yet), and it has no classes or skill selection, no companion AI, no finished movement/attack animations, only placeholder synthesised audio, and no mid-run saves (only settings persist). Items have no selling, and weapon swing timing is not yet per-weapon. Enemy and boss abilities, guild-hall services, rewards, and clock numbers require playtesting and subsequent design decisions.

## Troubleshooting

- If Godot cannot locate the main scene, make sure you imported/opened the **game/** directory, not the repository root.
- If controls do not respond, click inside the running game window.
- Resize the window by dragging its border, or choose **Esc → Display resolution → Apply resolution**. The **24×24 room never changes**; only its visual scale/centering and screen-space HUD change.
- Replaying with **R** repeats the graph exactly but moment-to-moment mouse and keyboard inputs are not recorded.
- If an edited JSON file is invalid, the game reports an error and exits; use the headless smoke-test command after making rule changes.

**Asset distribution note:** The sampler README does not include an explicit redistribution license. Before publicly distributing builds or source asset files, confirm the permissions associated with the supplied pack.
