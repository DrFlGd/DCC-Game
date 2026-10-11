# DCC Game — art asset structure (16×16 terrain baseline)

Art remains organized by family, not in one shared master sheet. The environment uses **16×16-native source tiles**, while character and enemy assets remain independent eight-direction sheets.

| Family | Current asset | Format |
| --- | --- | --- |
| Stone Crypt, active | [`biomes/stone_crypt/tileset_16x16.png`](biomes/stone_crypt/tileset_16x16.png) | **128×32 PNG**, 8 columns × 2 rows of 16px tiles |
| Stone Crypt, historical | [`biomes/stone_crypt/tileset.png`](biomes/stone_crypt/tileset.png) | Earlier 32px prototype; no longer used by the room renderer |
| Crawler | [`characters/crawler/facing_8.png`](characters/crawler/facing_8.png) | 8×48px source frames, rendered at 24×24 |
| Rat | [`enemies/rat/facing_8.png`](enemies/rat/facing_8.png) | 8×32px frames from supplied directional GIF, rendered at 24×24 |
| Armored boss | [`enemies/brute_boss/facing_8.png`](enemies/brute_boss/facing_8.png) | 8×96px source frames, rendered at 48×48 |
| Weapons | `weapons/<weapon_id>/...` | Independent per-weapon sheets (future task) |

## Imported sampler tile coordinates

All coordinates are **source pixels**, written (x, y, width, height). The ZIP's `tileset_index.txt` assigns them in row-major order:

| Tile | Source region | Role |
| --- | --- | --- |
| Floor stone 1 | (0, 0, 16, 16) | Main dungeon floor |
| Floor stone 2 | (16, 0, 16, 16) | Subtle alternate floor |
| Wall top | (32, 0, 16, 16) | Northern wall, rotated placeholder south and corners |
| Wall top edge left | (48, 0, 16, 16) | Eastern edge (floor on left) |
| Wall top edge right | (64, 0, 16, 16) | Western edge (floor on right) |
| Wall face | (80, 0, 16, 16) | Northern inner wall face |
| Wall with torch | (96, 0, 16, 16) | Occasional northern wall decoration |
| Closed wood door | (112, 0, 16, 16) | Double 16px doors at each 32px entrance |
| Stairs down | (0, 16, 16, 16) | Exit landmark |
| Barrel | (16, 16, 16, 16) | Blocking pillar prop |
| Chest | (32, 16, 16, 16) | Included but not placed yet |
| Skull and bones | (48, 16, 16, 16) | Blocking rubble prop |

The sampler explicitly lacks the additional corner and south-edge tiles described in its bundled README, so **north wall-top rotations are temporary join assets**, not an approved final corner solution. This atlas is an 8×8 pack *sampler* with only 12 tiles; the unused regions are transparent.

## Eight-direction sprite contract

Frames run left to right: **E, SE, S, SW, W, NW, N, NE**. Player facing follows the mouse; enemies follow movement orientation. The rat's original GIF frames were reordered to match this convention. Character art dimensions can differ from world-tile dimensions; native art is scaled using nearest-neighbor texture filtering.

## World and display scaling

Each room is always **24×24 cells of 16×16 world pixels**, giving a **384×384 world-pixel interior** and a one-tile-thick wall outside. The world geometry, obstacles, and attack hit ranges do not change when the user resizes the window or applies a pause-menu resolution preset. The layout script fits that world into the viewport.

## Follow-up art tasks

- [ ] Create dedicated south-wall edge, convex/concave corner and door jamb tiles to replace temporary rotations.
- [ ] Produce open, closed and locked door frames.
- [ ] Add more prop, floor and hazard variations with deterministic/biome-appropriate placement.
- [ ] Animate locomotion and attack frames for all eight facings.
- [ ] Maintain independent tileset and sprite files by biome/character/enemy/weapon.

**Rights note:** The 16px artwork comes from the user's uploaded `Dungeon_Tiles_16x16_FREE_SAMPLER.zip`. The bundled README provides usage directions but no explicit license or redistribution grant. Verify the sampler's permissions before redistributing its art in a public release or source package.
