# Biomes and Tilesets — D-15 catalogue

- **Status:** Proposed. Only `stone_crypt` is **implemented**, using the free 16×16 sampler. Everything else is a specification for Wave 2E (hazards) and 3B (second biome art).
- **Last updated:** 2026-10-25
- **Roadmap:** Phase 1E (D-15), §5A follow-up
- **Decisions covered:** D-15. Uses D-13 (16×16 native tiles) and D-16 (24×24 rooms).
- **Related:** [Procedural generation](PROCEDURAL_GENERATION.md#8-biome-assignment) · [Enemy tiers](ENEMY_TIERS.md) · [Encounter rules](ENCOUNTER_RULES.md) · [Asset conventions](../../game/assets/README.md)

**Tile scale:** every environment tile is **16×16 native pixels** (D-13 revised). A room is 24×24 tiles (384×384 px) with a one-tile wall ring, so the full drawn room is 416×416 px. Earlier roadmap text mentioning 32×32 is superseded.

## 1. Current prototype behaviour

- **Atlas:** [`stone_crypt/tileset_16x16.png`](../../game/assets/biomes/stone_crypt/tileset_16x16.png). It is 128×32 px, an 8×2 grid with 12 filled slots: floor ×2, wall top, wall edge ×2, wall face, wall torch, door, stairs, barrel, chest, bones. The slot map is in the [asset README](../../game/assets/README.md).
- **How `main.gd` draws a room:**
  - **Floor:** the alternate floor tile is used where `(x × 17 + y × 13) mod 9 == 0`.
  - **North wall:** wall-top tiles on row −1 and wall-face tiles on row 0, with torches at columns 5 and 18.
  - **South wall and corners:** the **wall-top tile rotated** into place, as a stand-in for missing art.
  - **Side walls:** the edge tiles.
  - **Doors:** each linked portal gets two door leaves, tinted by the destination kind.
  - **Room tints and props:** boss, guild-hall and exit rooms get a translucent tint. Pillars use the barrel tile and rubble uses the bones tile. The exit room has stairs drawn 32×32 at its centre.
- **Measured palette:** 24 colours in the sampler. The main ones are listed below. They define `stone_crypt` and are the reference for value contrast.

  `#0e0b16` outline · `#1a1426` `#2b2640` `#3d3656` `#564d72` `#736a8f` `#968db0` stone ramp · `#5e3430` `#8a5236` `#b87a4b` wood · `#4a4f5e` `#7a8194` metal · `#c4bca6` bone · `#e8a33a` flame

- **Gaps:**
  - The sampler has no south wall, corners, door jambs, or open/locked doors.
  - `main.gd` draws atlas (48, 0) on the **west** wall and (64, 0) on the **east** wall. The asset README describes (48, 0) as the *eastern* edge. Check this visually and fix either the code or the README.
- **Display scale:** at the default 960×540 window the room renders at ≈ 0.83× (`room_layout.gd`: (540 − 193) / 416). At the 720×480 minimum it renders at ≈ 0.69×. Native 16 px tiles therefore show at about 11–13 screen px with nearest-neighbour filtering at non-integer scales, so expect uneven pixels. See §8.

## 2. Standard atlas layout (all biomes)

Every biome ships `game/assets/biomes/<biome_id>/tileset_16x16.png` at **128×96 px**, an 8 × 6 grid of 16 px slots. **Rows 0–1 keep the current sampler positions**, so the existing renderer constants stay valid. Rows 2–5 add the missing families. The renderer reads slots by name from a per-biome `tiles.json` that defaults to this layout.

| Row | Col 0 | Col 1 | Col 2 | Col 3 | Col 4 | Col 5 | Col 6 | Col 7 |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | floor_a | floor_b | wall_top | wall_edge_e | wall_edge_w | wall_face | wall_face_lit | door_closed |
| 1 | stairs_down | obstacle_pillar | chest | obstacle_rubble | floor_c | floor_d | decal_a | decal_b |
| 2 | wall_south | corner_out_nw | corner_out_ne | corner_out_se | corner_out_sw | door_open | door_locked | threshold |
| 3 | corner_in_nw | corner_in_ne | corner_in_se | corner_in_sw | decal_c | decal_d | prop_small_a | prop_small_b |
| 4 | hazard_f0 | hazard_f1 | hazard_f2 | hazard_f3 | destructible | destructible_broken | feature_a | feature_b |
| 5 | haz_edge_n | haz_edge_e | haz_edge_s | haz_edge_w | haz_corner_nw | haz_corner_ne | haz_corner_se | haz_corner_sw |

**Minimum inventory per biome, 48 slots:**

| Family | Count |
| --- | ---: |
| Floors | 4 |
| Decals | 4 |
| Wall top | 1 |
| Wall faces | 2 |
| Side edges | 2 |
| South wall | 1 |
| Outer corners | 4 |
| Inner corners | 4 (reserved for irregular rooms later) |
| Door states (closed, open, locked) | 3 |
| Threshold | 1 |
| Blocking obstacles | 2 |
| Destructible obstacle (intact, broken) | 2 |
| Small non-blocking props | 2 |
| Biome features | 2 |
| Hazard animation frames | 4 |
| Hazard edge and corner transitions | 8 |
| Stairs | 1 |
| Chest | 1 |

Door leaves are drawn for the north portal and rotated for the other sides, as today. A biome can leave a slot transparent only if its `tiles.json` names a fallback slot.

## 3. Catalogue matrix

| Biome id | Depths (band) | Origin | Mood | Signature hazard | Enemy affinities ([ENEMY_TIERS.md](ENEMY_TIERS.md)) |
| --- | --- | --- | --- | --- | --- |
| `stone_crypt` | 1–2 (I) | Original (generic genre setting); sampler art | Cold, quiet, torchlit | none in band I; *crumbling flagstone* from band II if reused | rat family, dart idol; boss: armored brute |
| `fungal_cavern` | 3–4 (II) | Original | Damp, bioluminescent, organic | spore patches | spore puffer, nest mother, shellback charger |
| `flooded_catacombs` | 5–6 (III) | Original | Drowned, echoing, blue-green | shallow and deep water | lobber, bell acolyte, rubble golem, spitting rat; boss: sump warden |
| `maintenance_tunnels` | 7–8 (IV) | Original ("the dungeon's back-of-house") | Industrial, humming, hazard-striped | steam vents, conveyor plates | dart idol variants, shellback, golem |
| `bone_foundry` | 9+ (IV–V) | Original | Hot, ashen, rhythmic hammering | slag channels, spatter | golem, lobber, elites |
| `guild_interior` | any (guild-hall rooms only) | Original (generic "safe hub") | Warm, wooden, bustling | none | none (safe room) |

None of these is drawn from a specific location in the books. If a later catalogue record ([CATALOG_GUIDE.md](../research/CATALOG_GUIDE.md)) inspires a change, mark that biome `adapted` and cite the record.

## 4. Biome specifications

The hazard numbers are defaults that the 2E hazard system implements as data (`data/content/hazards.json` or similar, owned by 2E).

### 4.1 `stone_crypt` (implemented)

- **Palette:** the sampler palette (§1). Lighting is cool violet-grey, with warm `#e8a33a` torch pools.
- **Features:** sarcophagus (blocking feature), wall sconces, bone decals.
- **Hazard (band II reuse only), crumbling flagstone:** a cell cracks 0.6 s after the crawler steps on it, then becomes a pit for 4 s, dealing 2 damage and pushing the occupant to the nearest walkable cell.
- **Missing art for the 48-slot layout:** wall_south, 4 outer corners, 4 inner corners, door_open, door_locked, threshold, floor_c/d, decals, destructible (an urn), hazard frames.

### 4.2 `fungal_cavern`

- **Palette:** `#0f1512` outline · `#1d2a22` `#2f4436` `#4a6650` ground ramp · `#6b4f7a` `#9a73b0` mycelium violet · `#7fe0b0` glow cyan-green · `#e6d38a` spore yellow.
- **Lighting:** dark ambient. Glow caps make 48 px light pools.
- **Features:** giant mushroom stalk (blocking), glow-cap cluster (non-blocking light).
- **Hazard, spore patch:** a 2–6-cell patch. It puffs 0.4 s after the crawler enters (yellow swell telegraph) and applies Poison for 6 s. It re-arms after 3 s. Enemies with `spore` affinity are immune.
- **Room features:** organic room edges drawn with inner-corner tiles. The collision stays 24×24.
- **Destructible:** puffball. Breaking it releases one spore puff (2 cells, a hazard for enemies too).

### 4.3 `flooded_catacombs`

- **Palette:** `#0a1216` outline · `#16262e` `#24404a` `#3a6168` wet-stone ramp · `#2f6f7a` `#4fa3a5` water · `#c9e6df` foam · `#b08d57` old brass.
- **Lighting:** caustic shimmer on water cells, as a 4-frame animation.
- **Hazards:**
  - **Shallow water:** move speed −25 % for both the crawler and enemies, and it cleanses Burn.
  - **Deep water:** **blocks movement but not projectiles or LOS**. This needs a new cell class in the nav and collision code, separate from obstacles. It is never on door lanes.
- **Features:** an ossuary niche wall, and a submerged pillar (blocking).
- **Destructible:** a rotten crate that leaves a floating plank (cosmetic).

### 4.4 `maintenance_tunnels`

- **Palette:** `#101114` outline · `#23262b` `#3a3f47` `#5a616b` concrete and steel ramp · `#d9b13b` hazard yellow · `#2b2b2b` stripe black · `#c4572e` rust · `#9fd2e8` steam.
- **Lighting:** flickering strip lights, as a 2-frame animation on wall_face_lit.
- **Hazards:**
  - **Steam vent:** a 1×3 lane, 2.5 s on and 2.5 s off, with a 0.6 s hiss and particle telegraph. It applies Burn and 3 damage per second while the crawler is inside it.
  - **Conveyor plate:** pushes actors at 30 px/s in its arrow direction, shown by an animated arrow.
- **Features:** pipe bundle (blocking), control box (destructible: breaking it turns off one vent).

### 4.5 `bone_foundry`

- **Palette:** `#120b0a` outline · `#2a1a17` `#4a2c24` `#6e4535` scorched ramp · `#d8cbb0` bone · `#ff7a1a` `#ffc04a` molten · `#5c5c66` iron.
- **Lighting:** orange underglow from the channels, with a slow 1.2 s pulse.
- **Hazards:**
  - **Slag channel:** blocks movement, not projectiles. Standing next to it applies no damage.
  - **Spatter:** every 4 s a channel cell telegraphs for 0.7 s, then splashes a radius of 20 px for 4 damage plus Burn.
- **Features:** anvil (blocking), bone pile (destructible; it may drop a consumable at 10 %).

### 4.6 `guild_interior`

- **Palette:** `#160f0b` outline · `#3b2618` `#5e3d24` `#8a5a33` plank ramp · `#a33b3b` rug red · `#d9b36a` lamp gold · `#e8dcc0` parchment.
- **Lighting:** warm and even. This is the visual "safe" signal.
- **No hazards.** Obstacle density is 13, using counters, benches and crates. Features: a service counter (2E service point) and a notice board (an achievements and stats view).
- **Shared shell:** can reuse `stone_crypt` wall *shapes* via a palette swap once those shapes are original art (§5).

## 5. Sharing and recolouring

| Tile family | Shared across biomes? | How |
| --- | --- | --- |
| Wall, corner, door and threshold **shapes** | Yes | One original "shell" set, palette-swapped per biome (indexed ramps: 1 outline, 5 base, 3 accent, 2 highlight) |
| Floors | Partly | Shared tiling pattern, biome-specific texture detail |
| Doors (closed, open, locked) | Yes | Palette swap; the locked state adds a biome-neutral red bar so it reads the same everywhere |
| Stairs, chest | Yes | Palette swap |
| Props, features, destructibles | No | Biome-specific; these carry the identity |
| Hazard frames and transitions | No | Biome-specific, but every hazard edge set uses the same 8-slot shape layout |
| Decals | Partly | Generic cracks are shared; themed decals are per biome |

Palette swap is a shader (`palette_swap.gdshader`, owned by 3B) that maps source ramp indices to the biome ramp. It also serves the missing-art fallback ([PROCEDURAL_GENERATION.md §8](PROCEDURAL_GENERATION.md#8-biome-assignment)).

**Licence caveat:** the stone crypt art comes from a free sampler whose README has **no explicit licence or redistribution grant** ([asset README](../../game/assets/README.md)). A **recolour of sampler tiles is still sampler art** and carries the same caveat. The shared shell for other biomes must therefore be **original art**, or come from a pack with a verified licence. It must not be a palette swap of the sampler. Until then, palette-swapped sampler tiles are allowed only as private, team-internal placeholders, and must be labelled as such in each biome's `README.md`.

## 6. Mock-up specification

One mock-up per biome is required before that biome's art batch starts. The first is `fungal_cavern`, the 3B candidate.

1. **Canvas:** 416×416 px, the 24×24 interior plus the wall ring, exported at 1× and as a 3× nearest-neighbour copy. Target path: `docs/art/mockups/<biome_id>.png` and `<biome_id>@3x.png`.
2. **Must show:**
   - doors on all four sides, one each in the closed, open and locked states (the fourth may repeat);
   - all four outer corners;
   - one hazard patch of ≥ 4 cells with all of its edge and corner transitions;
   - 6 blocking obstacles, 1 destructible, 2 features and 4 decals;
   - the crawler (24×24) and one affinity enemy at their real render sizes.
3. **Alongside the mock-up:** a palette strip (every hex value) and the filled 128×96 atlas.
4. **Review checks:**
   - It must be legible at 0.69× (minimum window) and at 2× (1920×1080).
   - Actor silhouettes need a lightness difference of at least 25 % from the floor.
   - Hazards must be distinguishable by **pattern or animation, not hue alone** (colour-blind safety).
   - Locked doors must read as locked in greyscale.
   - No tile may be mistaken for a walkable floor if it blocks.

## 7. Engineering notes

- One tileset file per biome, plus `tiles.json` and `README.md` (with the source and licence) in `game/assets/biomes/<biome_id>/`.
- New cell classes the hazard work needs: `blocks_move_only` (deep water, slag), `hazard` (non-blocking, has an effect id), and `destructible` (blocking until broken; has HP).
- Hazard cells must be included in the feasibility checks ([PROCEDURAL_GENERATION.md §5](PROCEDURAL_GENERATION.md#5-room-interior-rules-v1)).

## 8. Open questions

1. Should rooms render at integer scales only (1×, 2×, 3×) with letterboxing, or keep the current fit-to-window non-integer scale? (Default: keep fit-to-window for now. 3C evaluates integer scaling or a scrolling camera.)
2. Should the slice have three art-complete biomes, or one finished biome plus two palette-swap fallbacks? (Default: crypt plus one new biome in 3B; the third stays a fallback.)
3. Does `guild_interior` need a distinct wall shell rather than a palette swap? (Default: palette swap plus unique props.)
4. Animated tiles: 4 frames at 6 fps for hazards and 2 frames for lights? (Default: yes.)
5. Who sources or creates the shared original shell set, and which licence does it use? (Blocking for any public build; see D-12 in [GAME_DESIGN.md §9](GAME_DESIGN.md#9-scope-and-ip--d-12).)
