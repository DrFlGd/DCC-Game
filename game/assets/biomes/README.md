# Biome tilesets

**Status: generated placeholders** (Wave 3B), except the stone-crypt sampler rows.
Everything here other than `stone_crypt/tileset_16x16.png` (the free sampler) and
`stone_crypt/tileset.png` (historical) is produced by
[`tools/gen_biome_tileset.py`](../../../tools/gen_biome_tileset.py) (Pillow,
deterministic) from the palettes in [`data/biomes.json`](../../data/biomes.json).
They exist so every biome is readable in playtests; replace them with real art without
changing the layout contract below. The design is
[BIOMES_AND_TILESETS.md](../../../docs/design/BIOMES_AND_TILESETS.md).

## Contract

- One folder per biome id: `tileset_16x16.png` (**128×96**, 8 columns × 6 rows of 16 px
  slots) plus `tiles.json`, which names every slot: `slots {name: [col, row]}`, optional
  `fallbacks {name: other_slot}`, `generated`, `placeholder`, `source`, `notes`.
- [`scripts/biomes.gd`](../../scripts/biomes.gd) resolves `Biomes.region(biome, slot)`;
  unnamed slots use the standard layout. The renderer draws only by slot name.
- A biome with an empty `tileset` in `biomes.json` draws the `fallback_art` biome's atlas
  multiplied by its `fallback_tint` (today: flooded catacombs, maintenance tunnels, bone
  foundry).

## Standard layout (rows are families)

| Row | Slots |
| ---: | --- |
| 0 | floor_a, floor_b, wall_top, wall_edge_e, wall_edge_w, wall_face, wall_face_lit, door_closed |
| 1 | stairs_down, obstacle_pillar, chest, obstacle_rubble, floor_c, floor_d, decal_a, decal_b |
| 2 | wall_south, corner_out_nw, corner_out_ne, corner_out_se, corner_out_sw, door_open, door_locked, threshold |
| 3 | corner_in_nw, corner_in_ne, corner_in_se, corner_in_sw, decal_c, decal_d, prop_small_a, prop_small_b |
| 4 | hazard_f0, hazard_f1, hazard_f2, hazard_f3, destructible, destructible_broken, feature_a, feature_b |
| 5 | haz_edge_n, haz_edge_e, haz_edge_s, haz_edge_w, haz_corner_nw, haz_corner_ne, haz_corner_se, haz_corner_sw |

Rows 0–1 keep the sampler's positions, so the crypt's sampler pixels sit at the same
coordinates in the full atlas. `wall_edge_e` is the **east** wall tile (its lit rim faces
west, toward the floor); `wall_edge_w` mirrors it. `wall_south` has its rim on top. The
`corner_in_*` slots are reserved for irregular rooms and are not drawn yet.

## Files

| Biome | Files | Notes |
| --- | --- | --- |
| `stone_crypt` | `tileset_16x16.png` (sampler, 128×32), `tileset_16x16_full.png` (active), `tileset_16x16_original.png`, `tiles.json` | Full = sampler rows 0–1 copied pixel for pixel + generated rows 2–5. Original = the same layout with **no sampler pixels**, kept as a redistributable stand-in; not referenced. |
| `fungal_cavern` | `tileset_16x16.png`, `tiles.json` | Loam floors, mycelium-hung cave walls, glow-cap light features, mushroom-cap obstacles, puffball destructible, spore-patch hazard frames. |
| `guild_interior` | `tileset_16x16.png`, `tiles.json` | Plank floors, timber-and-plaster walls, brass lamp, crates and barrels, service counter, notice board. No hazards (row 4 frames are a cosmetic ale spill). |

**Rights:** the sampler rows carry the caveat in [the asset README](../README.md) (no
explicit licence). The generated tiles contain no third-party pixels. The shared wall,
door, threshold, stairs and chest *shapes* are one set of original painters palette-swapped
per biome at generation time; props, features and hazards are drawn per biome.

**Regenerate:** `python3 tools/gen_biome_tileset.py --mockups` from the repository root
(also writes `docs/art/mockups/<biome>.png` and `@3x` copies for the two original-art
biomes), then let Godot re-import (`godot --headless --path game --editor --quit`) and
commit the PNGs with their `.import` files.
