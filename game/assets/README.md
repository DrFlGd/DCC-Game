# DCC Game — art asset structure (32×32 baseline)

Art is organized **by content family**, not one shared master atlas. New biomes, characters, enemies, and weapons each get their own sprite sheet or tileset file. Nothing should reference the retired `assets/crypt_atlas.png`.

## Paths

| Family | Current file | Grid / indexing |
| --- | --- | --- |
| Biome: Stone Crypt | [`biomes/stone_crypt/tileset.png`](biomes/stone_crypt/tileset.png) | 128×128 texture, 32px cells, plus one 64×64 door block |
| Character: Crawler | [`characters/crawler/facing_8.png`](characters/crawler/facing_8.png) | 384×48; 8 frames of 48×48 |
| Enemy: Rat scavenger | [`enemies/rat/facing_8.png`](enemies/rat/facing_8.png) | 384×48; 8 frames of 48×48 |
| Enemy: Armored brute | [`enemies/brute_boss/facing_8.png`](enemies/brute_boss/facing_8.png) | 768×96; 8 frames of 96×96 |
| Weapons | `weapons/<weapon_id>/...` | Separate equipment sheet; no finished weapon asset yet |

As a rule, biomes use modular **environment tilesets**, while characters/enemies use **directional sprite sheets** rather than TileSet terrain resources. The initial artwork is provisional pixel art made for this prototype. Production assets will need better animation, environmental edges and silhouettes.

## Stone-crypt tiles

Source pixel rectangles are in `biomes/stone_crypt/tileset.png`:

| Piece | Region (x, y, width, height) | Purpose |
| --- | --- | --- |
| `ART_FLOOR` | `(0, 0, 32, 32)` | Warm worn stone floor — corrected from the swapped floor/wall assignment |
| `ART_FLOOR_VARIANT` | `(32, 0, 32, 32)` | Rotated floor variation |
| `ART_WALL` | `(64, 0, 32, 32)` | Gray masonry wall |
| `ART_CORNER` | `(96, 0, 32, 32)` | Dedicated right-angle joining tile, rotated for four outer corners |
| `ART_DOOR` | `(64, 64, 64, 64)` | Two-tile-wide door art, rotated north/east/south/west |

The wall ring is one tile deep, with **two adjacent cells omitted for each linked doorway**. Corners are filled using the separate corner tile, not a straight wall piece. The renderer uses `_crypt_piece` to rotate the source region at 90° intervals without duplicating PNGs.

## Eight-way facing contract

Direction index across every sprite sheet, left to right:

| Frame | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Direction | E | SE | S | SW | W | NW | N | NE |

`_facing_from_vector` selects one of the eight images from a vector angle. **Player facing follows mouse aim**, regardless of movement direction; **enemy facing follows its pursuit direction**. This is a single idle/attack-neutral pose per facing, not eight full animations. No gameplay hitbox rotates with the artwork at present.

## Responsive display

`scripts/room_layout.gd` computes the size of the visible room based on the current window viewport, maintaining a **32px tile grid** with even row/column counts so the 64px portals remain centered. The scene moves the player, enemy and projectiles with its center after resizing. A minimum window size of 720×480 is set; the initial window is 960×540. `window/stretch/mode="disabled"` prevents the engine from treating every resized window as the original fixed-size drawing canvas. HUD footer and minimap are anchored to viewport edges.

## Next art tasks

- [ ] Seamless transition/cap tiles for door-adjacent masonry, interior corners, debris and floor-to-wall borders.
- [ ] Open/closed/locked/sealed door state art, rather than the same visually closed decorative arch.
- [ ] Animation frames for walking, melee, ranged attacks, hurt and death for each facing.
- [ ] Replace first-pass 8-way placeholder illustrations with approved character art.
- [ ] Separate per-weapon animation/effect sheets once items are implemented.
- [ ] Build a biome registry that points to the tileset for the currently generated floor.
- [ ] Add TileMapLayer and collision shapes when moving beyond the current debug boundary checks.

**Notes:** Generated images are original AI-assisted prototype placeholders, not copied game or book artwork. The 32px environment tile size is accepted under D-13; the content look and gameplay collision settings are not final.
