# Room, enemy, and RPG prototype systems

**Status:** Implemented as a first gameplay prototype, not a final balance or full D&D rules conversion.

## Fixed-size rooms versus window resolution

- **D-16 accepted:** Each interior is **24×24 tiles × 16 logical pixels = 384×384 world pixels**. Walls extend 16px beyond those interior bounds. The 24×24 layout **never changes** when a window is resized.
- [`room_layout.gd`](../../game/scripts/room_layout.gd) computes a fit-to-window **render scale and offset**. Gameplay positions, obstacle positions, movement speed, melee reach, and projectile velocity remain in unchanged world pixels.
- Mouse aiming uses the inverse screen-to-world transform, so player facing and attacks still point accurately after resizing.
- Default window 960×540, minimum 720×480. At smaller windows the entire room is downscaled; because a square room must fit inside a landscape viewport, actors can appear small. Future UX evaluation should compare whole-room fit versus a camera that scrolls around a fixed-size room.
- **Not a new room-size rule:** number of rooms per floor (currently 22) is a different variable from number of tiles per room (fixed 24×24).

### Window resolution controls

The **Esc pause menu** offers common windowed resolutions, including 800×600, 960×540, 1024×768, 1280×720, 1366×768, 1600×900, 1920×1080, 2560×1440, and 3840×2160. Choosing an entry and clicking **Apply resolution** changes the actual Godot window size. The scene recalculates only its visual scale/offset, and inverse-transform mouse aiming still works. Room and obstacle coordinates remain 24×24 cells at 16px each. These settings are session-only in the prototype and do not yet include fullscreen or monitor selection.

### Imported sampler boundaries

The user-provided 16px sampler contains 12 sprites in an 8×2 atlas, including floors, wall tops/faces, edges, wood door, stairs, barrel, chest and bones. Explicit bottom corners and south wall edges described in its README are **not included** in the ZIP, so the renderer currently uses rotated wall-top sections as temporary joins. The uploaded pack's README has no explicit redistribution license; verify that separately before publishing art.

## Props, collision, and reachability

[`room_contents.gd`](../../game/scripts/room_contents.gd) deterministically scatters **rubble and pillars** using the run seed and room ID. The initial count target (`obstacle_count: 38`) is configured in [`prototype_rules.json`](../../game/data/prototype_rules.json).

The generator:

1. Reserves a central combat/spawn zone and 32px-wide lanes at each potential cardinal exit.
2. Randomizes candidate grid cells using a seeded RNG.
3. Adds blocking obstacles one at a time.
4. Rejects a placement if breadth-first search cannot reach **every linked exit** from the center. Because all exits connect to that center, they remain mutually reachable.
5. Records both collision cells and visual props, so projectiles and actors use the same obstacles. Attack line-of-sight checks use obstacle cells too.

**Remaining limitations:** Validation is performed on a tile-cell grid, not a clearance-expanded navigation mesh for differently sized creatures. A large boss might still struggle in a one-cell passage. Planned improvements include swept collision, different actor footprints, door-edge clearance, more natural cluster generation, and destructible props.

## Multi-enemy encounters and AI

The data-driven source is [`game/data/enemies.json`](../../game/data/enemies.json) (schema v2); runtime logic is [`enemy_system.gd`](../../game/scripts/enemy_system.gd) (catalogue, encounters, AI state machine) and the enemy half of [`combat.gd`](../../game/scripts/combat.gd) (attack resolution, hazards, summons). The full schema, roster and guardrails are in [ENEMY_TIERS.md](ENEMY_TIERS.md); budgets and spawn rules are in [ENCOUNTER_RULES.md](ENCOUNTER_RULES.md).

Each enemy type has an ID and, among others, these fields:

| Field | Example | Meaning |
| --- | --- | --- |
| `name`, `sprite` | `Rat Scavenger`, `rat` | UI name; `sprite_sheets` id (frame and render size) |
| `role`, `band`, `min_depth`/`max_depth`, `threat` | `chaser`, `1`, `1`/`6`, `2` | Encounter budget and composition inputs |
| `level`, `xp`, `hp`, `ac`, `dr` | `1`, `25`, `7`, `12`, `0` | Combat challenge, rewards, defences |
| `scores` | `{ "STR":10, "DEX":14, ... }` | Six ability scores |
| `speed`, `collision_radius`, `knockback_resist` | `43`, `6`, `0.0` | Movement, footprint, push resistance |
| `tags`, `resistances`, `boss` | `["beast"]`, `{"poisoned": 0.5}`, `false` | `target_tag` conditions, damage/status multipliers, exit gate |
| `behavior.mode` | `chase`, `kite`, `guard`, `charge`, `zone`, `summon`, `support` | Movement between attacks |
| `behavior.pathfinding` | `grid_bfs`, `direct`, `stationary` | BFS (with clearance for radius ≥ 8), direct steering, or none |
| `attacks[]` | `bite`, `spit`, `ram`, `slam`, ... | `type`, `telegraph`, `wind_up`, `recovery`, `cooldown`, range, dice, type-specific fields |
| `abilities[]` | `twin_shot`, `dash`, `puddle`, `summon`, ... | Required by some attack types; `twin_shot` doubles single shots |
| `phases[]` | `{below: 0.5, attacks: [...]}` | Bosses only: HP thresholds that switch attack sets |

**Attack flow.** Every attack is telegraphed: an enemy enters `winding_up` (it stops, its sprite blends toward the attack colour and the renderer draws an arc, aim line, dash lane or ground circle where the hit will land), tracks the crawler for the first 60 % of the wind-up (80 % for shots), resolves at the end (melee and area hits are tested against the crawler's position at that moment, so stepping out dodges), then recovers. Enemies are dormant for 0.6 s whenever the crawler enters their room.

**Encounters.** Rooms spend a threat budget that grows with depth (`round((5 + 3 × depth) × intensity × kind)`; depth 1 standard = 8). Normal rooms hold **2 to 4 enemies at depths 1–2, up to 5 at depths 3–4 and 6 at depths 5–6**. Boss rooms place the depth's boss at the room midpoint plus an escort on half a standard budget. Enemies persist in their room between visits; killing one removes only that instance; summons die with their summoner.

The enemy definitions are schema-validated at startup and in CI. If you invent a new `behavior.mode`, attack `type` or ability, validation fails with a message naming it: add the logic and a test first. A JSON label alone does not implement a behaviour.

## D20 RPG starter rules

The prototype adopts recognizable **D&D-style** conventions, without claiming to implement the full tabletop rules or official DCC mechanics.

- Attributes: **Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma** (`STR`, `DEX`, `CON`, `INT`, `WIS`, `CHA`).
- Ability modifier = **floor((score − 10) / 2)**.
- Attacks roll a seeded **d20 + proficiency bonus + relevant ability modifier** against the target's Armor Class (AC).
- Natural 1 misses, natural 20 is a critical hit that doubles damage dice (not static modifiers).
- Damage = one configured weapon die plus its relevant ability modifier and any explicit bonus, minimum 1 on a hit.
- Default unarmored AC = **10 + DEX modifier**.
- XP rewards belong to each enemy definition and are granted once on defeat.
- Cumulative XP milestones follow the familiar 5e progression (300 XP to level 2, 900 XP to level 3, etc., capped at level 20). Proficiency starts at +2 and increases every four levels.
- Starting HP = **10 + CON modifier**; each later level adds **6 + CON modifier**, minimum 1. Level-ups immediately increase max HP and award that HP increase.
- Default starting six scores are defined in `game/data/prototype_rules.json`, not hard-coded in the renderer. Death/restart resets run XP.

Not yet implemented: classes/subclasses, species traits, feats, saving throws, spell slots, spellcasting, initiative, armor/equipment bonuses, ability score improvements, skill proficiencies, or true turn-based action economy. Combat remains real-time; attack cooldowns replace tabletop turns.

### Enemy roster (Wave 2C)

| Type | Role / band | Behaviour | Signature attack | XP |
| --- | --- | --- | --- | ---: |
| Rat Scavenger | chaser, I | chase / BFS | bite (arc, 0.35 s) | 25 |
| Spitting Rat | ranged, I | kite at 105–136 px | twin spit: one aimed, one leading (line, 0.45 s) | 50 |
| Hulking Rat | light tank, I | chase | hop-lunge dash and claw | 100 |
| Shellback Charger | charger, II | hold at 90–117 px | 120 px ram; stunned by walls | 90 |
| Spore Puffer | zoner, II | stationary | 32 px spore puddle | 60 |
| Nest Mother | summoner, II | kite at 120 px | summons rat pups (cap 4) | 120 |
| Bell Acolyte | support, III | stays near allies, flees the crawler | wards / heals allies in 80 px | 90 |
| Rubble Golem | tank, III | slow chase | 28 px slam with knockback | 150 |
| Cinder Lobber | artillery, III | kite at 140 px | firebomb lands 0.9 s after the throw | 100 |
| Armored Brute | boss, I | chase | maul; below 50 % adds a shoulder charge | 250 |
| Sump Warden | boss, II–III | kite at 90 px | tide spray, flood pulse; then drains and undertow; enraged below 25 % | 450 |

Actual balancing numbers are editable test values, not canon claims.

## Testing and next decisions

The [Godot CI workflow](../../.github/workflows/godot-ci.yml) imports scripts/assets, runs [deterministic smoke tests](../../game/tests/smoke_test.gd), and launches the scene headlessly. The tests check unchanged 24×24 dimensions under four window sizes, coordinate transforms, exit connectivity, seeded obstacles, multi-enemy spawns, and D&D-style level/attack calculations.

**Further decisions to review:** Whether entire rooms should always fit onscreen (small sprite drawback), terrain clearance for large enemies, obstruction density, ranged-weapon dodge fairness, RPG classes/skill trees, loot and stat effects, and whether higher floors use challenge-rating budgets rather than raw counts.
