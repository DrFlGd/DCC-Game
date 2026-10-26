#!/usr/bin/env python3
"""Generate the 128x96 standard biome atlases (placeholder art) for DCC Game.

Layout: docs/design/BIOMES_AND_TILESETS.md section 2 -- an 8 x 6 grid of 16 px
slots with named rows (floors, walls, corners, doors, decals, props, hazard
frames and hazard edges). Palettes are read from game/data/biomes.json, so the
art and the catalogue never disagree.

Outputs (all deterministic, all labelled as generated placeholders):
  game/assets/biomes/fungal_cavern/tileset_16x16.png + tiles.json
  game/assets/biomes/guild_interior/tileset_16x16.png + tiles.json
  game/assets/biomes/stone_crypt/tileset_16x16_full.png + tiles.json
      rows 0-1: the 12 filled slots of the free sampler (tileset_16x16.png,
      copied pixel for pixel, same rights caveat); every other slot generated
  game/assets/biomes/stone_crypt/tileset_16x16_original.png
      a fully generated (no sampler pixels) crypt atlas in the same layout, kept
      as a redistributable stand-in; not referenced by biomes.json
  docs/art/mockups/<biome>.png and <biome>@3x.png with --mockups
      416x416 room mock-ups (BIOMES_AND_TILESETS section 6) of the two
      original-art biomes

The shared "shell" (wall, edge, corner, door, threshold, stairs and chest
shapes) is one set of painters palette-swapped per biome (section 5); floors,
decals, props, features, destructibles and hazards are biome-specific.

Usage (from the repository root):
    python3 tools/gen_biome_tileset.py [--mockups]
Requires Pillow.
"""
import argparse
import json
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIOMES_JSON = os.path.join(ROOT, "game", "data", "biomes.json")
ASSETS = os.path.join(ROOT, "game", "assets", "biomes")
MOCKUPS = os.path.join(ROOT, "docs", "art", "mockups")
T = 16
COLUMNS, ROWS = 8, 6

# The standard layout, row by row (BIOMES_AND_TILESETS section 2).
LAYOUT = [
    ["floor_a", "floor_b", "wall_top", "wall_edge_e", "wall_edge_w", "wall_face",
     "wall_face_lit", "door_closed"],
    ["stairs_down", "obstacle_pillar", "chest", "obstacle_rubble", "floor_c", "floor_d",
     "decal_a", "decal_b"],
    ["wall_south", "corner_out_nw", "corner_out_ne", "corner_out_se", "corner_out_sw",
     "door_open", "door_locked", "threshold"],
    ["corner_in_nw", "corner_in_ne", "corner_in_se", "corner_in_sw", "decal_c", "decal_d",
     "prop_small_a", "prop_small_b"],
    ["hazard_f0", "hazard_f1", "hazard_f2", "hazard_f3", "destructible", "destructible_broken",
     "feature_a", "feature_b"],
    ["haz_edge_n", "haz_edge_e", "haz_edge_s", "haz_edge_w", "haz_corner_nw", "haz_corner_ne",
     "haz_corner_se", "haz_corner_sw"],
]
# Sampler slots copied into the crypt "full" atlas: (col, row) of the 12 filled tiles.
SAMPLER_SLOTS = [(c, 0) for c in range(8)] + [(c, 1) for c in range(4)]

# Short description of what each slot shows, per biome (written into tiles.json).
NOTES = {
    "stone_crypt": {
        "obstacle_pillar": "barrel (sampler)", "obstacle_rubble": "skull and bones (sampler)",
        "decal_a": "floor crack", "decal_b": "bone fragments", "decal_c": "cobweb",
        "decal_d": "damp stain", "prop_small_a": "candle stub", "prop_small_b": "pebbles",
        "hazard_f0": "crumbling flagstone 1/4 (hairline)", "hazard_f3": "crumbling flagstone 4/4 (pit)",
        "destructible": "urn", "destructible_broken": "urn shards",
        "feature_a": "sarcophagus lid", "feature_b": "brazier",
    },
    "fungal_cavern": {
        "obstacle_pillar": "giant mushroom cap (blocking)", "obstacle_rubble": "mossy boulder",
        "decal_a": "loose glowing spores", "decal_b": "mycelium threads",
        "decal_c": "luminous puddle (glow_puddle hazard)", "decal_d": "fallen cap pieces",
        "prop_small_a": "tiny mushroom cluster", "prop_small_b": "glowing sprout",
        "hazard_f0": "spore patch 1/4 (resting)", "hazard_f3": "spore patch 4/4 (swollen)",
        "destructible": "puffball", "destructible_broken": "burst puffball",
        "feature_a": "mushroom stalk", "feature_b": "glow-cap cluster (light pool)",
    },
    "guild_interior": {
        "obstacle_pillar": "crate", "obstacle_rubble": "barrel",
        "decal_a": "dropped notice", "decal_b": "ale stain", "decal_c": "spilled coins",
        "decal_d": "sawdust", "prop_small_a": "mug", "prop_small_b": "candle",
        "hazard_f0": "spilled ale 1/4 (cosmetic; the guild has no hazards)",
        "destructible": "grain sack", "destructible_broken": "torn sack",
        "feature_a": "service counter", "feature_b": "notice board",
    },
}


# --- Colour helpers ----------------------------------------------------------------

def hexc(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def fade(color, alpha):
    return color[:3] + (alpha,)


class Tile:
    """A 16x16 RGBA canvas with clipped pixel helpers."""

    def __init__(self, base=None):
        self.im = Image.new("RGBA", (T, T), (0, 0, 0, 0)) if base is None else base.copy()
        self.px = self.im.load()

    def copy(self):
        return Tile(self.im)

    def p(self, x, y, c):
        if 0 <= x < T and 0 <= y < T and c is not None:
            self.px[int(x), int(y)] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.p(x, y, c)

    def frame(self, x0, y0, x1, y1, c):
        for x in range(x0, x1 + 1):
            self.p(x, y0, c)
            self.p(x, y1, c)
        for y in range(y0, y1 + 1):
            self.p(x0, y, c)
            self.p(x1, y, c)

    def disc(self, cx, cy, r, c, ry=None):
        ry = r if ry is None else ry
        for y in range(T):
            for x in range(T):
                if ((x + 0.5 - cx) / r) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.p(x, y, c)

    def ring(self, cx, cy, r, c, ry=None):
        ry = r if ry is None else ry
        inside = set()
        for y in range(T):
            for x in range(T):
                if ((x + 0.5 - cx) / r) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    inside.add((x, y))
        for (x, y) in inside:
            if any((x + dx, y + dy) not in inside for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                self.p(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(steps + 1):
            self.p(round(x0 + (x1 - x0) * i / steps), round(y0 + (y1 - y0) * i / steps), c)

    def paste(self, other):
        self.im.alpha_composite(other.im)
        self.px = self.im.load()
        return self

    def rotated(self, quarter_turns):
        return Tile(self.im.rotate(-90 * quarter_turns))

    def flipped(self):
        return Tile(self.im.transpose(Image.FLIP_LEFT_RIGHT))


def rng(biome, slot):
    return random.Random("%s/%s" % (biome, slot))


# --- Palette roles -------------------------------------------------------------------

def roles(biome_id, palette):
    """Maps a biomes.json palette onto the painter roles.

    w: wall top [mortar, base, top, rim]; face: wall face [shadow, mortar, base,
    light]; f: floor [grout, base, light, speck]; wood [dark, mid, light];
    metal [dark, light]; acc [light source, second accent].
    """
    o = hexc(palette["outline"])
    if biome_id == "stone_crypt":
        s = [hexc(c) for c in palette["stone"]]
        wood = [hexc(c) for c in palette["wood"]]
        return {"ol": o, "w": [s[0], s[1], s[2], s[3]], "face": [s[0], s[1], s[3], s[4]],
                "f": [s[2], s[3], s[4], s[5]], "wood": wood,
                "metal": [hexc(c) for c in palette["metal"]],
                "acc": [hexc(palette["flame"][0]), hexc("#ffd88a")],
                "bone": hexc(palette["bone"][0]), "lock": hexc("#b8303a"),
                "lock_hi": hexc("#ff8a7a")}
    if biome_id == "fungal_cavern":
        g = [hexc(c) for c in palette["ground"]]
        m = [hexc(c) for c in palette["mycelium"]]
        glow = hexc(palette["glow"][0])
        spore = hexc(palette["spore"][0])
        return {"ol": o, "w": [o, g[0], g[1], m[0]], "face": [o, g[0], g[1], g[2]],
                "f": [g[0], g[1], mix(g[1], g[2], 0.5), g[2]],
                "wood": [mix(o, m[0], 0.55), m[0], m[1]], "metal": [g[2], glow],
                "acc": [glow, spore], "myc": m, "glow": glow, "spore": spore,
                "bone": spore, "lock": hexc("#b8303a"), "lock_hi": hexc("#ff8a7a")}
    if biome_id == "guild_interior":
        p = [hexc(c) for c in palette["plank"]]
        parch = hexc(palette["parchment"][0])
        lamp = hexc(palette["lamp"][0])
        return {"ol": o, "w": [o, p[0], p[1], p[2]],
                "face": [p[0], p[1], mix(parch, p[2], 0.45), mix(parch, p[2], 0.15)],
                "f": [p[0], p[2], mix(p[2], lamp, 0.3), p[1]], "wood": p,
                "metal": [p[1], lamp], "acc": [lamp, parch], "rug": hexc(palette["rug"][0]),
                "parch": parch, "lamp": lamp, "bone": parch, "lock": hexc("#b8303a"),
                "lock_hi": hexc("#ff8a7a")}
    raise ValueError("no painter roles for biome %s" % biome_id)


# --- Shared shell (palette-swapped) --------------------------------------------------

def wall_top(R):
    t = Tile()
    mortar, base, top, _rim = R["w"]
    for y in range(T):
        course, row = divmod(y, 4)
        for x in range(T):
            joint = (x + (4 if course % 2 else 0)) % 8 == 7
            if row == 3 or joint:
                t.p(x, y, mortar)
            elif row == 0:
                t.p(x, y, top)
            else:
                t.p(x, y, base)
    return t


def wall_edge(R, side):
    """Wall top with the lit rim on the floor side: 'e' wall -> rim on its west
    side (x 0-1), 'w' wall -> rim on its east side, 's' wall -> rim on top."""
    t = wall_top(R)
    rim = R["w"][3]
    for i in range(T):
        if side == "e":
            t.p(0, i, R["ol"])
            t.p(1, i, rim)
        elif side == "w":
            t.p(15, i, R["ol"])
            t.p(14, i, rim)
        elif side == "s":
            t.p(i, 0, R["ol"])
            t.p(i, 1, rim)
    return t


def corner_out(R, which):
    """Outer ring corner: wall top whose only floor contact is the inner
    diagonal pixel block, where the two rims meet."""
    t = wall_top(R)
    rim = R["w"][3]
    ix = 0 if which in ("se", "ne") else 15
    iy = 0 if which in ("se", "sw") else 15
    dx = 1 if ix == 0 else -1
    dy = 1 if iy == 0 else -1
    if which in ("se", "sw"):
        t.p(ix, iy, R["ol"])
        t.p(ix + dx, iy, R["ol"])
        t.p(ix, iy + dy, R["ol"])
        t.p(ix + dx, iy + dy, rim)
    else:  # north corners: the west/east rim stops under the north wall top
        for y in range(10, 16):
            t.p(ix, y, R["ol"])
            t.p(ix + dx, y, rim)
        t.p(ix + dx, 9, R["ol"])
    return t


def corner_in(R, which):
    """Inner corner (reserved for irregular rooms): a wall block whose floor
    sides are the two sides opposite `which` (corner_in_nw: floor south and east)."""
    t = wall_top(R)
    rim = R["w"][3]
    for i in range(T):
        if "n" in which:
            t.p(i, 15, R["ol"])
            t.p(i, 14, rim)
        else:
            t.p(i, 0, R["ol"])
            t.p(i, 1, rim)
    for i in range(T):
        if "w" in which:
            t.p(15, i, R["ol"])
            t.p(14, i, rim)
        else:
            t.p(0, i, R["ol"])
            t.p(1, i, rim)
    return t


def wall_face(R, biome):
    t = Tile()
    shadow, mortar, base, light = R["face"]
    t.rect(0, 0, 15, 1, R["w"][2])
    for y in range(2, 14):
        course, row = divmod(y - 2, 4)
        for x in range(T):
            joint = (x + (4 if course % 2 else 0)) % 8 == 0
            if row == 3 or joint:
                t.p(x, y, mortar)
            elif row == 0:
                t.p(x, y, light)
            else:
                t.p(x, y, base)
    t.rect(0, 14, 15, 14, shadow)
    t.rect(0, 15, 15, 15, R["ol"])
    r = rng(biome, "wall_face")
    if biome == "fungal_cavern":  # hanging mycelium strands
        for x in (2, 9, 13):
            length = r.randint(4, 9)
            for y in range(2, 2 + length):
                t.p(x, y, R["myc"][0] if y < 1 + length else R["myc"][1])
            t.p(x, 2 + length, R["myc"][1])
    elif biome == "guild_interior":  # timber frame over plaster
        t.rect(0, 2, 15, 2, R["wood"][1])
        t.rect(0, 9, 15, 9, R["wood"][1])
        for x in (0, 7, 8, 15):
            t.rect(x, 2, x, 13, R["wood"][0] if x in (0, 15) else R["wood"][1])
        for y in range(3, 9):
            for x in range(1, 7):
                t.p(x, y, R["face"][3] if (x + y) % 5 else R["face"][2])
        for y in range(10, 14):
            for x in range(9, 15):
                t.p(x, y, R["face"][3] if (x * 3 + y) % 7 else R["face"][2])
    return t


def wall_face_lit(R, biome):
    t = wall_face(R, biome)
    if biome == "fungal_cavern":  # glow-cap cluster growing from the wall
        for cx, cy, r in ((5, 8, 3), (10, 6, 2.5), (9, 11, 2)):
            t.disc(cx, cy, r + 0.8, R["ol"], (r + 0.8) * 0.75)
            t.disc(cx, cy, r, R["glow"], r * 0.7)
            t.p(int(cx) - 1, int(cy) - 1, hexc("#e6fff4"))
            t.line(int(cx), int(cy) + 1, int(cx), int(cy) + 3, R["myc"][0])
    elif biome == "guild_interior":  # brass wall lamp
        t.rect(7, 10, 8, 13, R["wood"][0])
        t.disc(7.5 + 0.5, 7, 3.2, R["ol"])
        t.disc(7.5 + 0.5, 7, 2.4, R["lamp"])
        t.p(7, 6, R["parch"])
        t.p(8, 6, hexc("#fff4d6"))
    else:  # torch: iron bracket and flame
        t.rect(7, 9, 8, 13, R["metal"][0])
        t.rect(6, 9, 9, 9, R["metal"][1])
        t.disc(8, 6, 2.6, R["acc"][0], 3.2)
        t.disc(8, 7, 1.4, R["acc"][1], 1.6)
        t.p(7, 2, R["acc"][0])
    return t


def door_closed(R):
    t = Tile()
    dark, mid, light = R["wood"]
    t.rect(0, 0, 15, 15, R["ol"])
    t.rect(1, 1, 14, 15, mid)
    for x in (4, 8, 12):
        t.rect(x, 1, x, 15, dark)
    for x in (2, 6, 10):
        t.rect(x, 1, x, 15, light)
    for y in (3, 11):
        t.rect(1, y, 14, y + 1, R["metal"][0])
        t.rect(1, y, 14, y, R["metal"][1])
    t.rect(11, 7, 12, 8, R["acc"][0])
    return t


def door_open(R):
    t = Tile()
    t.rect(0, 0, 15, 15, R["ol"])
    t.rect(2, 1, 13, 15, mix(R["ol"], R["f"][0], 0.35))
    for y in range(1, 16, 3):  # a strip of the floor beyond the doorway
        t.rect(3, y, 12, y, mix(R["ol"], R["f"][1], 0.3))
    dark, mid, light = R["wood"]
    t.rect(0, 0, 2, 15, mid)  # leaf swung against the left jamb
    t.rect(0, 0, 0, 15, dark)
    t.rect(2, 0, 2, 15, light)
    t.rect(13, 0, 15, 15, R["w"][2])  # right jamb
    t.rect(13, 0, 13, 15, R["ol"])
    return t


def door_locked(R):
    t = door_closed(R)
    t.rect(0, 6, 15, 9, R["ol"])  # red bar with studs reads as locked in greyscale too
    t.rect(0, 7, 15, 8, R["lock"])
    for x in (2, 13):
        t.p(x, 7, R["lock_hi"])
    t.rect(6, 4, 9, 11, R["ol"])  # padlock
    t.rect(7, 5, 8, 10, R["lock_hi"])
    t.rect(7, 8, 8, 9, R["ol"])
    return t


def threshold(R, biome):
    t = Tile()
    if biome == "guild_interior":  # doormat on planks
        t.rect(0, 0, 15, 15, R["f"][1])
        t.rect(1, 2, 14, 13, R["rug"])
        t.frame(1, 2, 14, 13, R["lamp"])
        for x in range(3, 13, 2):
            t.p(x, 7, mix(R["rug"], R["lamp"], 0.5))
        return t
    grout, base, light, speck = R["f"]
    t.rect(0, 0, 15, 15, R["w"][1])
    t.rect(0, 2, 15, 13, base)
    t.rect(0, 2, 15, 2, light)
    t.rect(0, 13, 15, 13, grout)
    for x in (5, 10):
        t.rect(x, 3, x, 12, grout)
    if biome == "fungal_cavern":
        for x, y in ((2, 4), (7, 11), (12, 5), (13, 10)):
            t.p(x, y, R["myc"][1])
            t.p(x + 1, y, R["myc"][0])
    return t


def stairs(R):
    t = Tile()
    t.rect(0, 0, 15, 15, R["ol"])
    ramp = [R["face"][3], R["face"][2], R["w"][2], R["w"][1], R["w"][0]]
    for i, y in enumerate(range(1, 15, 3)):
        c = ramp[min(i, len(ramp) - 1)]
        t.rect(1, y, 14, y + 1, c)
        t.rect(1, y + 2, 14, y + 2, R["ol"])
    t.rect(0, 0, 0, 15, R["w"][2])
    t.rect(15, 0, 15, 15, R["w"][1])
    return t


def chest(R):
    t = Tile()
    dark, mid, light = R["wood"]
    t.rect(1, 3, 14, 14, R["ol"])
    t.rect(2, 4, 13, 13, mid)
    t.rect(2, 4, 13, 6, light)
    t.rect(2, 7, 13, 7, dark)
    for x in (4, 11):
        t.rect(x, 4, x, 13, R["metal"][1])
    t.rect(7, 6, 8, 9, R["acc"][0])
    t.p(7, 8, R["ol"])
    t.rect(2, 15, 13, 15, fade(R["ol"], 110))
    return t


# --- Biome-specific painters ----------------------------------------------------------

def floor_tile(R, biome, variant):
    t = Tile()
    grout, base, light, speck = R["f"]
    r = rng(biome, "floor_" + variant)
    if biome == "stone_crypt":  # offset 8x8 flagstones
        for y in range(T):
            for x in range(T):
                shift = 4 if y >= 8 else 0
                lx, ly = (x + shift) % 8, y % 8
                if lx == 7 or ly == 7:
                    t.p(x, y, grout)
                elif lx == 0 or ly == 0:
                    t.p(x, y, light)
                else:
                    t.p(x, y, base)
        if variant == "c":  # cracked slab
            t.line(2, 2, 5, 5, grout)
            t.line(5, 5, 4, 6, grout)
        elif variant == "d":  # worn slab with grit
            for _ in range(6):
                t.p(r.randint(9, 14), r.randint(9, 14), grout)
        return t
    if biome == "fungal_cavern":  # packed loam
        t.rect(0, 0, 15, 15, base)
        for _ in range(26):
            t.p(r.randrange(T), r.randrange(T), grout)
        for _ in range(14):
            t.p(r.randrange(T), r.randrange(T), light)
        if variant == "b":  # root lines
            x, y = 1, r.randint(4, 11)
            for _ in range(14):
                t.p(x, y, grout)
                x += 1
                y += r.choice((-1, 0, 0, 1))
        elif variant == "c":  # moss patch
            for _ in range(22):
                x, y = 4 + int(r.gauss(4, 2)), 4 + int(r.gauss(4, 2))
                t.p(x, y, speck if (x + y) % 3 else R["myc"][0])
        elif variant == "d":  # pebbles
            for _ in range(4):
                x, y = r.randint(1, 13), r.randint(1, 13)
                t.rect(x, y, x + 1, y, light)
                t.rect(x, y + 1, x + 1, y + 1, grout)
        return t
    # guild_interior: horizontal planks, staggered butt joints
    for y in range(T):
        plank, row = divmod(y, 4)
        joint = (3 + plank * 5 + (7 if variant == "b" else 0)) % 16
        for x in range(T):
            if row == 3:
                t.p(x, y, grout)
            elif x == joint:
                t.p(x, y, grout)
            elif row == 0:
                t.p(x, y, light)
            else:
                t.p(x, y, base)
    if variant == "b":  # knot
        t.p(10, 5, speck)
        t.p(11, 5, grout)
    elif variant == "c":  # nail heads
        for x, y in ((2, 1), (13, 1), (6, 9), (9, 13)):
            t.p(x, y, R["ol"])
    elif variant == "d":  # worn boards
        for x in range(4, 12):
            t.p(x, 6, light)
            t.p(x + 1, 10, light)
    return t


def decal(R, biome, which):
    t = Tile()
    r = rng(biome, "decal_" + which)
    ol = R["ol"]
    if biome == "stone_crypt":
        if which == "a":  # crack
            t.line(3, 4, 7, 8, ol)
            t.line(7, 8, 12, 9, ol)
            t.line(7, 8, 8, 12, ol)
        elif which == "b":  # bone fragments
            t.line(4, 9, 8, 7, R["bone"])
            t.p(4, 10, R["bone"])
            t.p(3, 9, R["bone"])
            t.line(10, 11, 12, 12, R["bone"])
        elif which == "c":  # cobweb in a corner
            web = fade(hexc("#c8c4d8"), 150)
            for i in range(0, 12, 3):
                t.line(0, i, i, 0, web)
            t.line(0, 0, 10, 10, web)
        else:  # damp stain
            t.disc(8, 8, 5, fade(R["ol"], 70), 3.5)
            t.disc(7, 8, 3, fade(R["ol"], 60), 2)
        return t
    if biome == "fungal_cavern":
        if which == "a":  # loose spores
            for _ in range(9):
                t.p(r.randint(2, 13), r.randint(2, 13), R["spore"] if r.random() < 0.5 else R["glow"])
        elif which == "b":  # mycelium threads
            for _ in range(3):
                x, y = r.randint(0, 4), r.randint(2, 13)
                for _ in range(12):
                    t.p(x, y, fade(R["myc"][1], 200))
                    x += 1
                    y += r.choice((-1, 0, 1))
        elif which == "c":  # luminous puddle
            t.disc(8, 8.5, 6.5, fade(R["ol"], 200), 4.5)
            t.disc(8, 8.5, 5.5, fade(R["glow"], 170), 3.6)
            t.disc(7, 8, 3, fade(hexc("#d6fff0"), 200), 1.8)
            t.p(10, 7, hexc("#ffffff"))
        else:  # fallen cap pieces
            for cx, cy in ((5, 6), (10, 10)):
                t.disc(cx, cy, 2.2, R["ol"], 1.6)
                t.disc(cx, cy, 1.5, R["myc"][1], 1.0)
        return t
    # guild_interior
    if which == "a":  # dropped notice
        t.rect(4, 5, 11, 11, ol)
        t.rect(5, 5, 11, 10, R["parch"])
        for y in (6, 8):
            t.line(6, y, 10, y, R["wood"][1])
    elif which == "b":  # ale stain
        t.disc(8, 8, 5, fade(R["wood"][0], 110), 3.5)
    elif which == "c":  # spilled coins
        for x, y in ((5, 6), (8, 9), (10, 6), (6, 11)):
            t.rect(x, y, x + 1, y, R["lamp"])
            t.p(x, y + 1, R["wood"][0])
    else:  # sawdust
        for _ in range(14):
            t.p(r.randint(2, 13), r.randint(3, 12), fade(R["parch"], 170))
    return t


def prop_small(R, biome, which):
    t = Tile()
    ol = R["ol"]
    if biome == "stone_crypt":
        if which == "a":  # candle stub
            t.rect(6, 7, 9, 13, ol)
            t.rect(7, 8, 8, 12, R["bone"])
            t.disc(8, 5, 1.6, R["acc"][0], 2.2)
            t.p(7, 5, R["acc"][1])
        else:  # pebbles
            for x, y in ((4, 9), (8, 11), (11, 8)):
                t.rect(x, y, x + 2, y + 1, ol)
                t.rect(x, y, x + 1, y, R["w"][3])
        return t
    if biome == "fungal_cavern":
        if which == "a":  # tiny mushroom cluster
            for cx, cy in ((5, 9), (9, 7), (11, 11)):
                t.rect(cx, cy, cx, cy + 3, R["spore"])
                t.disc(cx + 0.5, cy, 2.4, ol, 1.6)
                t.disc(cx + 0.5, cy, 1.6, R["myc"][1], 1.0)
        else:  # glowing sprout
            t.line(8, 13, 8, 7, R["f"][3])
            t.line(8, 9, 6, 7, R["f"][3])
            t.disc(8, 6, 1.8, R["glow"])
            t.disc(6, 6.5, 1.2, R["glow"])
        return t
    if which == "a":  # mug
        t.rect(5, 6, 10, 13, ol)
        t.rect(6, 7, 9, 12, R["wood"][2])
        t.rect(6, 7, 9, 8, R["parch"])
        t.rect(10, 8, 11, 11, ol)
    else:  # candle
        t.rect(6, 11, 9, 13, R["wood"][0])
        t.rect(7, 7, 8, 11, R["parch"])
        t.disc(8, 5, 1.5, R["lamp"], 2.2)
    return t


def obstacle(R, biome, which):
    t = Tile()
    ol = R["ol"]
    if biome == "stone_crypt":  # only used by the fully original crypt atlas
        if which == "pillar":  # stone column, top view
            t.disc(8, 8, 7, ol)
            t.disc(8, 8, 6, R["w"][2])
            t.disc(7, 7, 4, R["w"][3])
            t.ring(8, 8, 6, R["w"][1])
        else:  # rubble
            for x, y, w in ((2, 8, 5), (7, 5, 6), (8, 10, 5)):
                t.rect(x, y, x + w, y + 3, ol)
                t.rect(x + 1, y, x + w - 1, y + 2, R["w"][2])
                t.rect(x + 1, y, x + w - 1, y, R["w"][3])
        return t
    if biome == "fungal_cavern":
        if which == "pillar":  # giant mushroom cap, top view
            t.disc(8, 8, 7.6, ol)
            t.disc(8, 8, 6.6, R["myc"][0])
            t.disc(7, 7, 4.8, R["myc"][1])
            for x, y in ((5, 5), (10, 6), (7, 10), (11, 10), (4, 9)):
                t.rect(x, y, x + 1, y, R["spore"])
        else:  # mossy boulder
            t.disc(8, 9, 7, ol, 6)
            t.disc(8, 9, 6, R["face"][3], 5)
            t.disc(7, 8, 3.8, mix(R["face"][3], R["glow"], 0.3), 3)
            for x, y in ((5, 6), (6, 5), (9, 5), (10, 6), (8, 4)):
                t.p(x, y, R["glow"] if x == 9 else R["f"][3])
        return t
    if which == "pillar":  # crate
        dark, mid, light = R["wood"]
        t.rect(1, 1, 14, 14, ol)
        t.rect(2, 2, 13, 13, mid)
        t.frame(2, 2, 13, 13, light)
        t.line(3, 3, 12, 12, dark)
        t.line(3, 12, 12, 3, dark)
        return t
    # barrel, top view
    t.disc(8, 8, 7, ol)
    t.disc(8, 8, 6, R["wood"][1])
    t.ring(8, 8, 6, R["lamp"])
    t.ring(8, 8, 4, R["wood"][0])
    t.p(7, 6, R["wood"][2])
    return t


def destructible(R, biome, broken):
    t = Tile()
    ol = R["ol"]
    if biome == "stone_crypt":  # urn
        body = R["wood"][1]
        if broken:
            for x, y in ((3, 10), (8, 12), (11, 9), (6, 7)):
                t.rect(x, y, x + 2, y + 1, ol)
                t.rect(x, y, x + 1, y, body)
            return t
        t.disc(8, 9, 5.5, ol, 6)
        t.disc(8, 9, 4.5, body, 5)
        t.rect(6, 2, 9, 4, ol)
        t.rect(7, 3, 8, 3, R["wood"][2])
        t.line(5, 8, 10, 8, R["wood"][0])
        return t
    if biome == "fungal_cavern":  # puffball
        if broken:
            t.ring(8, 9, 6, R["spore"], 4)
            t.disc(8, 9, 4, fade(R["spore"], 90), 2.5)
            for x, y in ((3, 4), (12, 5), (13, 12)):
                t.p(x, y, R["spore"])
            return t
        t.disc(8, 9, 6.5, ol, 6)
        t.disc(8, 9, 5.5, mix(R["spore"], R["ol"], 0.15), 5)
        t.disc(7, 7, 3, mix(R["spore"], hexc("#ffffff"), 0.4), 2.2)
        t.p(10, 11, R["myc"][0])
        return t
    # grain sack
    if broken:
        t.disc(8, 11, 6, ol, 3)
        t.disc(8, 11, 5, R["parch"], 2)
        for x in range(3, 13, 2):
            t.p(x, 13, R["lamp"])
        return t
    t.disc(8, 9, 6, ol, 6.5)
    t.disc(8, 9, 5, mix(R["parch"], R["wood"][2], 0.4), 5.5)
    t.rect(6, 2, 9, 4, R["wood"][0])
    t.p(6, 9, R["wood"][2])
    return t


def feature(R, biome, which):
    t = Tile()
    ol = R["ol"]
    if biome == "stone_crypt":
        if which == "a":  # sarcophagus lid
            t.rect(2, 0, 13, 15, ol)
            t.rect(3, 1, 12, 14, R["face"][2])
            t.frame(3, 1, 12, 14, R["face"][3])
            t.frame(5, 3, 10, 12, R["w"][1])
            t.rect(7, 6, 8, 9, R["face"][3])
            return t
        t.disc(8, 10, 5.5, ol, 4)  # brazier
        t.disc(8, 10, 4.5, R["metal"][0], 3)
        t.disc(8, 7, 3, R["acc"][0], 4)
        t.disc(8, 8, 1.6, R["acc"][1], 2.2)
        return t
    if biome == "fungal_cavern":
        if which == "a":  # mushroom stalk (side view, short)
            t.rect(6, 7, 9, 15, ol)
            t.rect(7, 7, 8, 15, R["spore"])
            t.disc(8, 5, 7.6, ol, 4.8)
            t.disc(8, 5, 6.6, R["myc"][0], 3.8)
            t.disc(7, 4, 4, R["myc"][1], 2.2)
            return t
        for cx, cy, r in ((5, 10, 3), (10, 7, 3.5), (11, 12, 2)):  # glow caps
            t.rect(int(cx), int(cy), int(cx), int(cy) + 3, R["f"][3])
            t.disc(cx, cy, r + 0.8, R["ol"], (r + 0.8) * 0.7)
            t.disc(cx, cy, r, R["glow"], r * 0.6)
            t.p(int(cx) - 1, int(cy) - 1, hexc("#e6fff4"))
        return t
    if which == "a":  # service counter
        t.rect(0, 4, 15, 13, ol)
        t.rect(0, 5, 15, 12, R["wood"][1])
        t.rect(0, 5, 15, 6, R["wood"][2])
        t.rect(0, 7, 15, 7, R["lamp"])
        for x in (3, 8, 13):
            t.rect(x, 8, x, 12, R["wood"][0])
        return t
    t.rect(1, 2, 14, 12, ol)  # notice board
    t.rect(2, 3, 13, 11, R["wood"][1])
    for x, y in ((3, 4), (8, 5), (4, 8)):
        t.rect(x, y, x + 3, y + 2, R["parch"])
        t.p(x + 1, y, R["rug"])
    t.rect(4, 13, 4, 15, R["wood"][0])
    t.rect(11, 13, 11, 15, R["wood"][0])
    return t


def hazard_frame(R, biome, frame):
    t = Tile()
    r = rng(biome, "hazard")
    if biome == "stone_crypt":  # crumbling flagstone: crack, cracks, crumble, pit
        base = floor_tile(R, biome, "a")
        t.paste(base)
        ol = R["ol"]
        t.line(3, 3, 8, 8, ol)
        if frame >= 1:
            t.line(8, 8, 13, 6, ol)
            t.line(8, 8, 7, 13, ol)
        if frame >= 2:
            t.disc(8, 8, 4, R["w"][0])
            t.line(2, 11, 6, 9, ol)
        if frame >= 3:
            t.disc(8, 8, 6.5, R["ol"])
            t.ring(8, 8, 6.5, R["w"][1])
            for x, y in ((3, 4), (12, 11), (11, 3)):
                t.p(x, y, R["w"][3])
        return t
    if biome == "fungal_cavern":  # spore patch: felted mycelium with pulsing spores
        t.rect(0, 0, 15, 15, mix(R["f"][0], R["myc"][0], 0.45))
        for _ in range(30):
            t.p(r.randrange(T), r.randrange(T), R["myc"][0])
        for _ in range(10):
            t.p(r.randrange(T), r.randrange(T), R["f"][0])
        swell = [1.6, 2.2, 2.8, 3.4][frame]
        for cx, cy in ((4, 4), (11, 5), (7, 11), (13, 12)):
            t.disc(cx, cy, swell + 0.7, R["ol"])
            t.disc(cx, cy, swell, mix(R["spore"], R["myc"][1], 0.3 - 0.1 * frame))
            t.p(cx - 1, cy - 1, R["spore"] if frame < 3 else hexc("#fff6c8"))
        if frame == 3:
            for x, y in ((2, 9), (9, 2), (14, 8), (6, 14)):
                t.p(x, y, R["spore"])
        return t
    # guild_interior: spilled ale with a shimmer that walks across
    t.disc(8, 8, 7, fade(R["wood"][0], 170), 6)
    t.disc(8, 8, 6, fade(mix(R["wood"][2], R["lamp"], 0.5), 190), 5)
    sx = 3 + frame * 3
    t.line(sx, 6, sx + 2, 6, fade(R["parch"], 220))
    return t


def hazard_edge(R, biome, side):
    """Transparent overlay drawn on a hazard cell's border side (n/e/s/w) or,
    for corners (nw/ne/se/sw), where both adjacent sides are open."""
    t = Tile()
    if biome == "stone_crypt":
        a, b = R["ol"], R["w"][1]
    elif biome == "fungal_cavern":
        a, b = R["spore"], R["myc"][1]
    else:
        a, b = fade(R["wood"][0], 200), fade(R["lamp"], 200)
    r = rng(biome, "edge_" + side)

    def band(edge):
        for i in range(T):
            for depth in range(2):
                if (i + depth) % 2 == 0 or r.random() < 0.3:
                    c = a if depth == 0 else b
                    if edge == "n":
                        t.p(i, depth, c)
                    elif edge == "s":
                        t.p(i, 15 - depth, c)
                    elif edge == "w":
                        t.p(depth, i, c)
                    else:
                        t.p(15 - depth, i, c)

    if len(side) == 1:
        band(side)
    else:
        for x in range(5):
            for y in range(5):
                if x + y <= 4 and (x + y) % 2 == 0:
                    px = x if "w" in side else 15 - x
                    py = y if "n" in side else 15 - y
                    t.p(px, py, a if x + y < 3 else b)
    return t


# --- Atlas assembly ------------------------------------------------------------------

def paint(biome, R):
    tiles = {}
    tiles["floor_a"] = floor_tile(R, biome, "a")
    tiles["floor_b"] = floor_tile(R, biome, "b")
    tiles["floor_c"] = floor_tile(R, biome, "c")
    tiles["floor_d"] = floor_tile(R, biome, "d")
    tiles["wall_top"] = wall_top(R)
    tiles["wall_edge_e"] = wall_edge(R, "e")
    tiles["wall_edge_w"] = wall_edge(R, "w")
    tiles["wall_south"] = wall_edge(R, "s")
    tiles["wall_face"] = wall_face(R, biome)
    tiles["wall_face_lit"] = wall_face_lit(R, biome)
    tiles["door_closed"] = door_closed(R)
    tiles["door_open"] = door_open(R)
    tiles["door_locked"] = door_locked(R)
    tiles["threshold"] = threshold(R, biome)
    tiles["stairs_down"] = stairs(R)
    tiles["chest"] = chest(R)
    tiles["obstacle_pillar"] = obstacle(R, biome, "pillar")
    tiles["obstacle_rubble"] = obstacle(R, biome, "rubble")
    for d in ("nw", "ne", "se", "sw"):
        tiles["corner_out_" + d] = corner_out(R, d)
        tiles["corner_in_" + d] = corner_in(R, d)
    for k in "abcd":
        tiles["decal_" + k] = decal(R, biome, k)
    tiles["prop_small_a"] = prop_small(R, biome, "a")
    tiles["prop_small_b"] = prop_small(R, biome, "b")
    for f in range(4):
        tiles["hazard_f%d" % f] = hazard_frame(R, biome, f)
    tiles["destructible"] = destructible(R, biome, False)
    tiles["destructible_broken"] = destructible(R, biome, True)
    tiles["feature_a"] = feature(R, biome, "a")
    tiles["feature_b"] = feature(R, biome, "b")
    for s in ("n", "e", "s", "w"):
        tiles["haz_edge_" + s] = hazard_edge(R, biome, s)
    for d in ("nw", "ne", "se", "sw"):
        tiles["haz_corner_" + d] = hazard_edge(R, biome, d)
    return tiles


def assemble(tiles):
    atlas = Image.new("RGBA", (COLUMNS * T, ROWS * T), (0, 0, 0, 0))
    for row, names in enumerate(LAYOUT):
        for col, name in enumerate(names):
            atlas.paste(tiles[name].im, (col * T, row * T))
    return atlas


def tiles_json(biome, atlas_file, sampler=False):
    slots = {}
    for row, names in enumerate(LAYOUT):
        for col, name in enumerate(names):
            slots[name] = [col, row]
    notes = dict(NOTES.get(biome, {}))
    data = {
        "biome": biome,
        "atlas": atlas_file,
        "tile_size": T,
        "columns": COLUMNS,
        "rows": ROWS,
        "generated": True,
        "placeholder": True,
        "source": "tools/gen_biome_tileset.py (generated placeholder art)"
        + ("; rows 0-1 filled slots copied from the free 16x16 sampler (see README rights note)"
           if sampler else ""),
        "slots": slots,
        "fallbacks": {},
        "notes": notes,
    }
    return json.dumps(data, indent=2) + "\n"


def write(path, image_or_text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(image_or_text, str):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(image_or_text)
    else:
        image_or_text.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


# --- Mock-ups (BIOMES_AND_TILESETS section 6) ---------------------------------------

def mockup(biome, atlas):
    def tile(name):
        for row, names in enumerate(LAYOUT):
            if name in names:
                col = names.index(name)
                return atlas.crop((col * T, row * T, col * T + T, row * T + T))
        raise KeyError(name)

    size = 26 * T
    img = Image.new("RGBA", (size, size), (16, 23, 32, 255))

    def put(name, cx, cy, rot=0):
        piece = tile(name).rotate(-90 * rot)
        img.alpha_composite(piece, ((cx + 1) * T, (cy + 1) * T))

    for y in range(24):
        for x in range(24):
            put("floor_b" if (x * 17 + y * 13) % 9 == 0 else "floor_a", x, y)
    hazard = {(4, 15), (5, 15), (4, 16), (5, 16), (6, 16)}
    for i, (x, y) in enumerate(sorted(hazard)):
        put("hazard_f%d" % (i % 4), x, y)
        for side, (dx, dy) in (("n", (0, -1)), ("e", (1, 0)), ("s", (0, 1)), ("w", (-1, 0))):
            if (x + dx, y + dy) not in hazard:
                put("haz_edge_" + side, x, y)
    for x, y in ((5, 5), (18, 5), (6, 19), (17, 18), (19, 9), (3, 9)):
        put("obstacle_rubble" if (x + y) % 2 else "obstacle_pillar", x, y)
    put("destructible", 15, 15)
    put("feature_a", 8, 5)
    put("feature_b", 16, 6)
    for i, (x, y) in enumerate(((10, 18), (14, 4), (20, 15), (7, 12))):
        put("decal_" + "abcd"[i], x, y)
    put("prop_small_a", 13, 19)
    put("prop_small_b", 9, 7)
    put("chest", 15, 9)
    put("stairs_down", 12, 12)
    for x in range(24):
        if x not in (11, 12):
            put("wall_top", x, -1)
            put("wall_face_lit" if x in (5, 18) else "wall_face", x, 0)
            put("wall_south", x, 24)
        else:
            put("threshold", x, -1)
            put("threshold", x, 24, 2)
    for y in range(24):
        if y in (11, 12):
            put("threshold", -1, y, 3)
            put("threshold", 24, y, 1)
        else:
            put("wall_edge_w", -1, y)
            put("wall_edge_e", 24, y)
    put("corner_out_nw", -1, -1)
    put("corner_out_ne", 24, -1)
    put("corner_out_se", 24, 24)
    put("corner_out_sw", -1, 24)
    for x, state in ((11, "door_closed"), (12, "door_closed")):
        put(state, x, -1)
    for x in (11, 12):
        put("door_open", x, 24, 2)
    for y in (11, 12):
        put("door_locked", -1, y, 3)
        put("door_closed", 24, y, 1)
    # Actors at their render sizes: the crawler (24 px) and one affinity enemy.
    actors = [("characters/crawler/facing_8.png", (192, 236), 24)]
    enemy = {"fungal_cavern": "spore_puffer", "stone_crypt": "rat",
             "guild_interior": None}.get(biome)
    if enemy:
        actors.append(("enemies/%s/facing_8.png" % enemy, (236, 200), 24))
    for rel, (cx, cy), render in actors:
        path = os.path.join(ROOT, "game", "assets", rel)
        if not os.path.exists(path):
            continue
        sheet = Image.open(path).convert("RGBA")
        fw = sheet.width // 8
        frame = sheet.crop((2 * fw, 0, 3 * fw, sheet.height)).resize((render, render), Image.NEAREST)
        img.alpha_composite(frame, (T + cx - render // 2, T + cy - render // 2))
    return img


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mockups", action="store_true",
                        help="also write docs/art/mockups/<biome>.png and @3x copies")
    args = parser.parse_args()
    with open(BIOMES_JSON, encoding="utf-8") as handle:
        catalogue = json.load(handle)["biomes"]

    atlases = {}
    for biome in ("fungal_cavern", "guild_interior"):
        R = roles(biome, catalogue[biome]["palette"])
        atlas = assemble(paint(biome, R))
        atlases[biome] = atlas
        write(os.path.join(ASSETS, biome, "tileset_16x16.png"), atlas)
        write(os.path.join(ASSETS, biome, "tiles.json"), tiles_json(biome, "tileset_16x16.png"))

    crypt_roles = roles("stone_crypt", catalogue["stone_crypt"]["palette"])
    original = assemble(paint("stone_crypt", crypt_roles))
    write(os.path.join(ASSETS, "stone_crypt", "tileset_16x16_original.png"), original)
    sampler = Image.open(os.path.join(ASSETS, "stone_crypt", "tileset_16x16.png")).convert("RGBA")
    full = original.copy()
    for col, row in SAMPLER_SLOTS:
        box = (col * T, row * T, col * T + T, row * T + T)
        full.paste(sampler.crop(box), box[:2])
    atlases["stone_crypt"] = full
    write(os.path.join(ASSETS, "stone_crypt", "tileset_16x16_full.png"), full)
    write(os.path.join(ASSETS, "stone_crypt", "tiles.json"),
          tiles_json("stone_crypt", "tileset_16x16_full.png", sampler=True))

    if args.mockups:
        # Original-art biomes only: the crypt atlas still carries sampler pixels.
        for biome in ("fungal_cavern", "guild_interior"):
            img = mockup(biome, atlases[biome])
            write(os.path.join(MOCKUPS, biome + ".png"), img)
            write(os.path.join(MOCKUPS, biome + "@3x.png"),
                  img.resize((img.width * 3, img.height * 3), Image.NEAREST))


if __name__ == "__main__":
    main()
