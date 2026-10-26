# DCC Game — art asset structure (16×16 terrain baseline)

Art remains organized by family, not in one shared master sheet. The environment uses **16×16-native source tiles**, while character and enemy assets remain independent eight-direction sheets.

| Family | Current asset | Format |
| --- | --- | --- |
| Stone Crypt, sampler source | [`biomes/stone_crypt/tileset_16x16.png`](biomes/stone_crypt/tileset_16x16.png) | **128×32 PNG**, 8 columns × 2 rows of 16px tiles (12 filled slots); kept untouched, copied into rows 0–1 of the full atlas |
| Stone Crypt, active | [`biomes/stone_crypt/tileset_16x16_full.png`](biomes/stone_crypt/tileset_16x16_full.png) + [`tiles.json`](biomes/stone_crypt/tiles.json) | **128×96 PNG** standard atlas: rows 0–1 = the sampler, rows 2–5 = generated placeholders (south wall, corners, door states, threshold, decals, props, urn, hazard frames) |
| Stone Crypt, all-original | [`biomes/stone_crypt/tileset_16x16_original.png`](biomes/stone_crypt/tileset_16x16_original.png) | 128×96 atlas with **no sampler pixels** (generated stand-in for a redistributable build); not referenced by `biomes.json` |
| Stone Crypt, historical | [`biomes/stone_crypt/tileset.png`](biomes/stone_crypt/tileset.png) | Earlier 32px prototype; no longer used by the room renderer |
| Fungal Cavern (floors 3–4) | [`biomes/fungal_cavern/tileset_16x16.png`](biomes/fungal_cavern/tileset_16x16.png) + `tiles.json` | 128×96 generated placeholder atlas (loam floors, mycelium walls, glow caps, puffball, spore patch frames) |
| Guild Interior (guild halls) | [`biomes/guild_interior/tileset_16x16.png`](biomes/guild_interior/tileset_16x16.png) + `tiles.json` | 128×96 generated placeholder atlas (planks, timber walls, lamp, crates, counter, notice board) |
| Flooded Catacombs, Maintenance Tunnels, Bone Foundry | none yet | Drawn as the active crypt atlas × `fallback_tint` from [`data/biomes.json`](../data/biomes.json) |

See [`biomes/README.md`](biomes/README.md) for the standard 8×6 slot layout, the generator and the placeholder labelling.
| Crawler | [`characters/crawler/facing_8.png`](characters/crawler/facing_8.png) | 8×48px source frames, rendered at 24×24 |
| Rat | [`enemies/rat/facing_8.png`](enemies/rat/facing_8.png) | 8×32px frames from supplied directional GIF, rendered at 24×24 |
| Armored boss | [`enemies/brute_boss/facing_8.png`](enemies/brute_boss/facing_8.png) | 8×96px source frames, rendered at 48×48 |
| Weapons | `weapons/<weapon_id>/...` | Independent per-weapon sheets (future task) |
| Audio | [`audio/`](audio/README.md) (`sfx/`, `ambient/`, `music/`) | 38 generated 22050 Hz 16-bit mono WAVs from `tools/gen_sfx.py`; mapped by `data/audio.json` |

## Imported sampler tile coordinates

All coordinates are **source pixels**, written (x, y, width, height). The ZIP's `tileset_index.txt` assigns them in row-major order:

| Tile | Source region | Role |
| --- | --- | --- |
| Floor stone 1 | (0, 0, 16, 16) | Main dungeon floor |
| Floor stone 2 | (16, 0, 16, 16) | Subtle alternate floor |
| Wall top | (32, 0, 16, 16) | Northern wall, rotated placeholder south and corners |
| Wall top edge left (`wall_edge_e`) | (48, 0, 16, 16) | **Eastern** wall (its lit rim faces west, toward the floor). The renderer drew it on the west wall until Wave 3B; fixed |
| Wall top edge right (`wall_edge_w`) | (64, 0, 16, 16) | **Western** wall (rim faces east, toward the floor) |
| Wall face | (80, 0, 16, 16) | Northern inner wall face |
| Wall with torch | (96, 0, 16, 16) | Occasional northern wall decoration |
| Closed wood door | (112, 0, 16, 16) | Double 16px doors at each 32px entrance |
| Stairs down | (0, 16, 16, 16) | Exit landmark |
| Barrel | (16, 16, 16, 16) | Blocking pillar prop |
| Chest | (32, 16, 16, 16) | Included but not placed yet |
| Skull and bones | (48, 16, 16, 16) | Blocking rubble prop |

The sampler explicitly lacks the corner and south-edge tiles described in its bundled README. Since Wave 3B those come from **generated placeholder slots** in rows 2–5 of `tileset_16x16_full.png` (`wall_south`, `corner_out_*`, `threshold`, `door_open`, `door_locked`), so wall-top rotations are no longer drawn. The sampler file itself is an 8×8 pack *sampler* with only 12 tiles; its unused regions are transparent.

## Eight-direction sprite contract

Frames run left to right: **E, SE, S, SW, W, NW, N, NE**. Player facing follows the mouse; enemies follow movement orientation. The rat's original GIF frames were reordered to match this convention. Character art dimensions can differ from world-tile dimensions; native art is scaled using nearest-neighbor texture filtering.

## World and display scaling

Each room is always **24×24 cells of 16×16 world pixels**, giving a **384×384 world-pixel interior** and a one-tile-thick wall outside. The world geometry, obstacles, and attack hit ranges do not change when the user resizes the window or applies a pause-menu resolution preset. The layout script fits that world into the viewport.

## Follow-up art tasks

- [x] South-wall edge, convex corner and threshold tiles replace the temporary rotations (generated placeholders, 3B; concave corners reserved for irregular rooms).
- [x] Open, closed and locked door frames (generated placeholders, 3B).
- [x] Prop, floor and hazard variations with deterministic, biome-appropriate placement (3B).
- [ ] Replace the generated placeholder tiles with final art (and the sampler rows with licensed or original art).
- [ ] Animate locomotion and attack frames for all eight facings.
- [ ] Maintain independent tileset and sprite files by biome/character/enemy/weapon.

**Rights note:** The 16px sampler artwork (`stone_crypt/tileset_16x16.png`, and rows 0–1 of `stone_crypt/tileset_16x16_full.png`, which copies it pixel for pixel) comes from the user's uploaded `Dungeon_Tiles_16x16_FREE_SAMPLER.zip`. The bundled README provides usage directions but no explicit license or redistribution grant. Verify the sampler's permissions before redistributing its art in a public release or source package. Every other biome tile (fungal cavern, guild interior, crypt rows 2–5, `tileset_16x16_original.png`) is generated by `tools/gen_biome_tileset.py` and is a placeholder with no third-party pixels.
