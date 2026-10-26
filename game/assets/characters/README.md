# Character sprite sheets

| Folder | Used by | Source | Frames | Render |
| --- | --- | --- | --- | --- |
| `crawler/facing_8.png` | the crawler (`room_renderer.gd`) | supplied | 8 × 48×48, order **E, SE, S, SW, W, NW, N, NE** | 24×24 |
| `companion/facing_4.png` | the Scrap Hound companion prototype (`cmp_scrap_hound` in [`data/companions.json`](../../data/companions.json)) | **generated placeholder** | 5 × 24×24, order **E, S, W, N, downed** | 20×20 |

**`companion/` is a placeholder.** [`tools/gen_placeholder_sprites.py`](../../../tools/gen_placeholder_sprites.py)
generates it with Pillow, and the output is deterministic. It is original art: a top-down scruffy hound
with a riveted plate on its back, and a flopped-over downed pose. Replace it with real art without
changing the contract: one row of 5 equal frames, with the four facings first and the downed pose last.
`companions.json` `frame` / `render` give the source and in-world sizes. The renderer draws it through
`Companion.draw_on()` with nearest-neighbour filtering.

To regenerate only the companion sheet, run this from the repository root, then let Godot re-import and
commit the PNG with its `.import` file:

```sh
python3 tools/gen_placeholder_sprites.py --only companion
```
