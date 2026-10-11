# Stone-Crypt Prototype Atlas

**Decision D-13:** 32×32 logical pixels per environment tile, selected for the initial DCC Game prototype. This atlas is an **art test**, not a complete production tileset.

## Source file

[`crypt_atlas.png`](crypt_atlas.png) — **192×160 pixels**, 64-color indexed PNG with transparency. Assembled from the initial exploratory pixel-art assets generated for this project, downscaled with nearest-neighbor interpolation, then palette-reduced. Attribution: original, AI-assisted prototype assets; not book illustrations or assets from another game.

## Atlas regions

Source rectangles use **(x, y, width, height)** in pixels. Drawing logic is in [`scripts/main.gd`](../scripts/main.gd).

| Symbol | Source rectangle | Render size | Purpose |
| --- | --- | --- | --- |
| `ART_FLOOR` | `(0, 0, 32, 32)` | 32×32 | Old stone floor, 0°/90°/180°/270° variants at runtime |
| `ART_WALL` | `(32, 0, 32, 32)` | 32×32 | Masonry perimeter; rotate to orient wall shading |
| `ART_DOOR` | `(64, 0, 64, 64)` | 64×64 | Door and stone surround, rotated to cardinal direction |
| `ART_PLAYER` | `(0, 64, 48, 48)` | 48×48 | Temporary crawler visual |
| `ART_ENEMY` | `(48, 64, 48, 48)` | 48×48 | Temporary rat-scavenger enemy |
| `ART_BOSS` | `(96, 64, 96, 96)` | 96×96 | Temporary armored brute boss |

### Room construction

- The traversable floor is 24 columns × 10 rows, **768×320 logical pixels**.
- The surrounding wall ring is one 32-pixel tile thick.
- Connected room edges reserve **two 32-pixel wall cells** at the midpoint, then draw a door/arch visual centered on that gap.
- North wall art uses 0°, south 180°, west -90°, and east +90°. Door art rotates by side as well.
- All rotation is implemented in Godot's draw transform: no redundant rotated PNGs are stored. It preserves exact square-grid geometry and reduces maintenance when art changes.
- Collision remains simple room-boundary clamping and door checks for the spike. Do not infer physics/TileMap collision from the visuals.

### Next art tasks

- [ ] Create true repeatable floor and wall patterns with edge/corner/cap transitions (rotating a single tile is temporary).
- [ ] Replace visually closed doors with distinct open, shut, locked, boss-sealed, and guild-hall portal states.
- [ ] Add 4+ facing/attack/hurt animation frames for the player and enemy.
- [ ] Establish sprite anchor/foot-position and tile-scale collision standards.
- [ ] Build the D-15 biome catalogue using this tile scale as baseline.
- [ ] Consider splitting the atlas into per-biome TileSet resources and sprite sheets once content grows.

Do not treat the sample asset palette, character look, or tile art as final production direction.