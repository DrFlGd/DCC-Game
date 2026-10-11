# Room, enemy, and RPG prototype systems

**Status:** Implemented as a first gameplay prototype, not a final balance or full D&D rules conversion.

## Fixed-size rooms versus window resolution

- **D-16 accepted:** Each interior is **24×24 tiles × 32 logical pixels = 768×768 world pixels**. Walls extend 32px beyond those interior bounds. The 24×24 layout **never changes** when a window is resized.
- [`room_layout.gd`](../../game/scripts/room_layout.gd) computes a fit-to-window **render scale and offset**. Gameplay positions, obstacle positions, movement speed, melee reach, and projectile velocity remain in unchanged world pixels.
- Mouse aiming uses the inverse screen-to-world transform, so player facing and attacks still point accurately after resizing.
- Default window 960×540, minimum 720×480. At smaller windows the entire room is downscaled; because a square room must fit inside a landscape viewport, actors can appear small. Future UX evaluation should compare whole-room fit versus a camera that scrolls around a fixed-size room.
- **Not a new room-size rule:** number of rooms per floor (currently 22) is a different variable from number of tiles per room (fixed 24×24).

## Props, collision, and reachability

[`room_contents.gd`](../../game/scripts/room_contents.gd) deterministically scatters **rubble and pillars** using the run seed and room ID. The initial count target (`obstacle_count: 38`) is configured in [`prototype_rules.json`](../../game/data/prototype_rules.json).

The generator:

1. Reserves a central combat/spawn zone and 64px-wide lanes at each potential cardinal exit.
2. Randomizes candidate grid cells using a seeded RNG.
3. Adds blocking obstacles one at a time.
4. Rejects a placement if breadth-first search cannot reach **every linked exit** from the center. Because all exits connect to that center, they remain mutually reachable.
5. Records both collision cells and visual props, so projectiles and actors use the same obstacles. Attack line-of-sight checks use obstacle cells too.

**Remaining limitations:** Validation is performed on a tile-cell grid, not a clearance-expanded navigation mesh for differently sized creatures. A large boss might still struggle in a one-cell passage. Planned improvements include swept collision, different actor footprints, door-edge clearance, more natural cluster generation, and destructible props.

## Multi-enemy encounters and AI

The data-driven source is [`game/data/enemies.json`](../../game/data/enemies.json); runtime logic is [`enemy_system.gd`](../../game/scripts/enemy_system.gd).

Each enemy type has an ID and these fields:

| Field | Example | Meaning |
| --- | --- | --- |
| `name`, `sprite` | `Rat Scavenger`, `rat` | UI and art selection |
| `level`, `xp`, `hp`, `ac` | `1`, `25`, `7`, `12` | Combat challenge, rewards, defenses |
| `scores` | `{ "STR":10, "DEX":14, ... }` | Six ability scores |
| `speed`, `collision_radius` | `86`, `12` | Movement and world-space footprint |
| `behavior.mode` | `chase`, `kite`, `guard` | Pursuit or preferred-spacing behavior |
| `behavior.pathfinding` | `grid_bfs`, `direct`, `stationary` | Choose grid BFS, direct steering, or no movement |
| `behavior.preferred_distance` | `26` or `210` | Close-in for melee, keep range for ranged |
| `behavior.repath_seconds` | `0.35` | Navigation refresh period |
| `attacks[]` | `bite` or `spit` | Melee/ranged, STR/DEX, die, cooldown, range, projectile speed |
| `abilities[]` | `lunge`, `twin_shot` | Implemented modifiers: close-range speed boost, paired shots |

You can add enemy definitions and reference them in `encounter_tables.normal.pool`, adjusting `min`/`max`. Currently normal encounters use **2–4 enemies**, while the boss room contains an armored brute plus two smaller enemies. Enemies persist in their room between visits; killing one removes only that instance. The two rat varieties currently reuse the **user-provided eight-frame rat GIF**, converted into the game's E/SE/S/SW/W/NW/N/NE order; a violet marker distinguishes ranged attackers.

The enemy definitions are schema-validated at startup and in CI. If you invent a new `behavior.mode` or `attacks[].type`, add corresponding logic and a test. A JSON label alone does not implement a new ability.

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

### Starter enemies

| Type | Behavior | Attack | XP |
| --- | --- | --- | ---: |
| Rat Scavenger | Chase / BFS | Melee bite | 25 |
| Spitting Rat | Kite / BFS | Ranged paired projectiles | 50 |
| Hulking Rat | Chase / BFS; lunge at close range | Heavy melee | 100 |
| Armored Brute | Boss chase / BFS; lunge | Boss melee | 250 |

Actual balancing numbers are editable test values, not canon claims.

## Testing and next decisions

The [Godot CI workflow](../../.github/workflows/godot-ci.yml) imports scripts/assets, runs [deterministic smoke tests](../../game/tests/smoke_test.gd), and launches the scene headlessly. The tests check unchanged 24×24 dimensions under four window sizes, coordinate transforms, exit connectivity, seeded obstacles, multi-enemy spawns, and D&D-style level/attack calculations.

**Further decisions to review:** Whether entire rooms should always fit onscreen (small sprite drawback), terrain clearance for large enemies, obstruction density, ranged-weapon dodge fairness, RPG classes/skill trees, loot and stat effects, and whether higher floors use challenge-rating budgets rather than raw counts.
