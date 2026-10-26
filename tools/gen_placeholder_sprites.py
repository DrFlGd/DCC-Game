#!/usr/bin/env python3
"""Generate placeholder 8-direction enemy sprite sheets for DCC Game.

Each sheet is one row of 8 frames in the order E, SE, S, SW, W, NW, N, NE
(see game/assets/README.md). Rat-family enemies are palette swaps of the
supplied rat sheet; every other archetype gets a simple silhouette whose shape
reads its role (charger wedge, zoner puffball, support bell-bearer, tank boulder,
artillery bomb-carrier, boss warden). These are placeholders, not final art.

It also writes the Wave 3E companion sheet
game/assets/characters/companion/facing_4.png: one row of 5 frames of 24x24
in the order E, S, W, N, downed (the Scrap Hound, an original placeholder:
a scruffy hound with a riveted plate on its back).

Usage (from the repository root):
    python3 tools/gen_placeholder_sprites.py [--out game/assets/enemies]
        [--companion-out game/assets/characters/companion]
        [--only all|enemies|companion]
Requires Pillow. Output is deterministic.
"""
import argparse
import colorsys
import math
import os

from PIL import Image, ImageDraw

OUTLINE = (18, 14, 24, 255)
DIRECTIONS = 8  # E, SE, S, SW, W, NW, N, NE; angle = index * 45 degrees, y down

# Rat palette swaps: (hue 0..1, saturation scale, value scale) applied to the
# grey body pixels; pink details keep their hue but follow the value scale.
RAT_VARIANTS = {
    "spitting_rat": {"body": (0.78, 0.45, 1.05), "detail_hue": 0.30},
    "hulking_rat": {"body": (0.03, 0.55, 0.80), "detail_hue": None},
    "rat_pup": {"body": (0.10, 0.35, 1.35), "detail_hue": None},
    "nest_mother": {"body": (0.93, 0.35, 1.10), "detail_hue": 0.95},
}


def rotate(points, angle, cx, cy):
    c, s = math.cos(angle), math.sin(angle)
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in points]


def ellipse(cx, cy, rx, ry, angle, offset=(0.0, 0.0), n=28):
    pts = [(offset[0] + rx * math.cos(t), offset[1] + ry * math.sin(t))
           for t in (2 * math.pi * i / n for i in range(n))]
    return rotate(pts, angle, cx, cy)


def poly(draw, points, fill, outline=OUTLINE):
    draw.polygon([(round(x), round(y)) for x, y in points], fill=fill, outline=outline)


def sheet(frame, painter):
    img = Image.new("RGBA", (frame * DIRECTIONS, frame), (0, 0, 0, 0))
    for index in range(DIRECTIONS):
        tile = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
        painter(ImageDraw.Draw(tile), frame, index * math.pi / 4.0)
        img.paste(tile, (index * frame, 0), tile)
    return img


# --- Role silhouettes -------------------------------------------------------------

def charger(draw, size, a):
    c = size / 2
    poly(draw, rotate([(-11, -3), (-11, 3), (-6, 0)], a, c, c), (60, 70, 52, 255))  # tail
    for side in (-1, 1):  # legs
        for fx in (-5, 3):
            poly(draw, rotate([(fx, side * 7), (fx + 3, side * 10), (fx + 4, side * 7)], a, c, c),
                 (40, 46, 40, 255))
    poly(draw, ellipse(c, c, 11, 8, a), (58, 112, 96, 255))  # shell
    poly(draw, ellipse(c, c, 7, 5, a, (-1, 0)), (84, 146, 120, 255), None)
    for k in (-4, 1):  # plate seams
        seg = rotate([(k, -6), (k, 6)], a, c, c)
        draw.line(seg, fill=(34, 70, 60, 255), width=1)
    poly(draw, rotate([(8, -4), (15, 0), (8, 4)], a, c, c), (196, 178, 120, 255))  # ram horn


def puffer(draw, size, a):
    c = size / 2
    for i in range(10):  # spikes
        t = a + i * 2 * math.pi / 10
        tip = (c + 14 * math.cos(t), c + 14 * math.sin(t))
        l = (c + 9 * math.cos(t - 0.25), c + 9 * math.sin(t - 0.25))
        r = (c + 9 * math.cos(t + 0.25), c + 9 * math.sin(t + 0.25))
        poly(draw, [l, tip, r], (150, 128, 40, 255))
    poly(draw, ellipse(c, c, 10, 10, a), (214, 188, 70, 255))
    for ox, oy in ((-3, -4), (2, 3), (-4, 3), (4, -2)):  # spots
        poly(draw, ellipse(c, c, 1.6, 1.6, a, (ox, oy), 8), (150, 168, 54, 255), None)
    poly(draw, ellipse(c, c, 2.5, 3.5, a, (7, 0), 10), (90, 60, 30, 255))  # vent


def acolyte(draw, size, a):
    c = size / 2
    poly(draw, ellipse(c, c + 1, 9, 9, a), (92, 70, 120, 255))  # robe
    poly(draw, ellipse(c, c + 1, 6, 6, a, (-1, 0)), (120, 96, 150, 255), None)
    poly(draw, ellipse(c, c, 4.5, 4.5, a, (3, 0), 14), (60, 44, 82, 255))  # hood
    draw.line(rotate([(4, 5), (11, 7)], a, c, c), fill=(170, 140, 90, 255), width=1)  # handle
    poly(draw, ellipse(c, c, 3.4, 3.4, a, (12, 7), 12), (232, 196, 82, 255))  # bell


def golem(draw, size, a):
    c = size / 2
    poly(draw, rotate([(-14, -12), (10, -14), (14, 0), (10, 14), (-14, 12), (-17, 0)], a, c, c),
         (110, 100, 92, 255))
    poly(draw, rotate([(-8, -8), (4, -9), (6, 0), (2, 8), (-9, 7)], a, c, c),
         (138, 126, 112, 255), None)
    for side in (-1, 1):  # fists
        poly(draw, ellipse(c, c, 6, 5, a, (11, side * 15), 12), (92, 84, 78, 255))
    for p in ((-10, 4), (0, -6), (-4, 9)):  # cracks
        draw.point(rotate([p], a, c, c)[0], fill=(64, 58, 54, 255))
    eye = rotate([(10, -5), (14, -1), (14, 1), (10, 5)], a, c, c)  # eye slit
    poly(draw, eye, (255, 168, 64, 255), (120, 60, 20, 255))


def lobber(draw, size, a):
    c = size / 2
    poly(draw, ellipse(c, c, 7, 8, a, (-6, 0), 16), (130, 96, 60, 255))  # sack
    poly(draw, ellipse(c, c, 7, 7, a, (1, 0)), (86, 102, 70, 255))  # body
    poly(draw, ellipse(c, c, 3.5, 3.5, a, (5, 0), 12), (66, 80, 54, 255))  # head
    draw.line(rotate([(2, 5), (9, 8)], a, c, c), fill=(66, 80, 54, 255), width=2)  # arm
    poly(draw, ellipse(c, c, 3.2, 3.2, a, (11, 8), 12), (40, 36, 36, 255))  # bomb
    spark = rotate([(13, 6)], a, c, c)[0]
    draw.point(spark, fill=(255, 120, 40, 255))
    draw.point((spark[0] + 1, spark[1]), fill=(255, 220, 90, 255))


def warden(draw, size, a):
    c = size / 2
    for k in (-1, 0, 1):  # trailing tendrils
        pts = [(-18, k * 14 - 3), (-42, k * 22), (-40, k * 22 + 5), (-18, k * 14 + 3)]
        poly(draw, rotate(pts, a, c, c), (34, 82, 92, 255))
    poly(draw, ellipse(c, c, 30, 26, a), (40, 104, 120, 255))  # mantle
    poly(draw, ellipse(c, c, 22, 18, a, (-2, 0)), (58, 136, 150, 255), None)
    for k in range(-2, 3):  # ribbing
        draw.line(rotate([(-14, k * 7), (10, k * 6)], a, c, c), fill=(36, 92, 104, 255), width=2)
    plate = rotate([(14, -14), (30, -8), (34, 0), (30, 8), (14, 14), (18, 0)], a, c, c)
    poly(draw, plate, (122, 120, 104, 255))  # grate face plate
    for k in (-6, 0, 6):
        draw.line(rotate([(18, k), (30, k * 0.8)], a, c, c), fill=(60, 58, 52, 255), width=2)
    for side in (-1, 1):  # eyes
        poly(draw, ellipse(c, c, 3, 3, a, (25, side * 5), 10), (140, 255, 240, 255), None)
    for side in (-1, 1):  # claws
        poly(draw, rotate([(16, side * 24), (36, side * 30), (20, side * 18)], a, c, c),
             (30, 70, 80, 255))


SILHOUETTES = {
    "shellback_charger": (32, charger),
    "spore_puffer": (32, puffer),
    "bell_acolyte": (32, acolyte),
    "lobber": (32, lobber),
    "rubble_golem": (48, golem),
    "sump_warden": (96, warden),
}


# --- Companion (Wave 3E) -----------------------------------------------------------

HOUND_FUR = (166, 118, 72, 255)
HOUND_DARK = (112, 76, 44, 255)
HOUND_PLATE = (150, 160, 170, 255)
HOUND_RIVET = (226, 210, 120, 255)
HOUND_HEAD = (196, 146, 92, 255)


def hound(draw, size, a):
    """Top-down Scrap Hound facing angle `a`: tail, legs, body, riveted plate, head."""
    c = size / 2
    poly(draw, rotate([(-8, -1), (-12, -3), (-11, 1)], a, c, c), HOUND_DARK)  # tail
    for side in (-1, 1):  # legs
        for fx in (-5, 3):
            poly(draw, rotate([(fx - 1, side * 3), (fx, side * 6), (fx + 2, side * 6),
                               (fx + 2, side * 3)], a, c, c), HOUND_DARK)
    poly(draw, ellipse(c, c, 7, 4, a, (-1, 0)), HOUND_FUR)  # body
    poly(draw, rotate([(-4, -2), (1, -2), (1, 2), (-4, 2)], a, c, c), HOUND_PLATE)  # plate
    for x, y in rotate([(-3, 0), (0, 0)], a, c, c):
        draw.point((round(x), round(y)), fill=HOUND_RIVET)
    for side in (-1, 1):  # ears
        poly(draw, rotate([(6, side * 2), (4, side * 6), (8, side * 3)], a, c, c), HOUND_DARK)
    poly(draw, ellipse(c, c, 4, 3.5, a, (8, 0), n=16), HOUND_HEAD)  # head
    for x, y in rotate([(9, -1.5), (9, 1.5)], a, c, c):  # eyes
        draw.point((round(x), round(y)), fill=OUTLINE)
    nose = rotate([(10.5, 0)], a, c, c)[0]
    draw.point((round(nose[0]), round(nose[1])), fill=OUTLINE)


def hound_downed(draw, size):
    """Downed pose: flopped on its side, legs out, X eyes."""
    c = size / 2
    for fx in (-5, -1, 3, 6):
        draw.line([(c + fx, c + 2), (c + fx + 1, c + 7)], fill=HOUND_DARK, width=1)
    poly(draw, ellipse(c, c, 8, 3.5, 0.0, (0, 1)), HOUND_FUR)
    poly(draw, [(c - 4, c - 2), (c + 1, c - 2), (c + 1, c + 1), (c - 4, c + 1)], HOUND_PLATE)
    poly(draw, ellipse(c, c, 4, 3.5, 0.0, (8, 0), n=16), HOUND_HEAD)
    ex, ey = c + 8, c
    draw.line([(ex - 1, ey - 1), (ex + 1, ey + 1)], fill=OUTLINE)
    draw.line([(ex - 1, ey + 1), (ex + 1, ey - 1)], fill=OUTLINE)
    draw.line([(c - 8, c + 1), (c - 12, c + 3)], fill=HOUND_DARK)  # limp tail


def companion_sheet(frame=24):
    img = Image.new("RGBA", (frame * 5, frame), (0, 0, 0, 0))
    for index in range(5):
        tile = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
        if index < 4:
            hound(ImageDraw.Draw(tile), frame, index * math.pi / 2.0)
        else:
            hound_downed(ImageDraw.Draw(tile), frame)
        img.paste(tile, (index * frame, 0), tile)
    return img


# --- Rat palette swaps -------------------------------------------------------------

def recolor_rat(source, variant):
    body_h, sat_scale, val_scale = variant["body"]
    out = source.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, alpha = px[x, y]
            if alpha == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < 0.25:  # grey fur -> tinted fur
                h, s = body_h, min(1.0, 0.15 + sat_scale * (1.0 - v) * 0.9 + sat_scale * 0.25)
            elif variant["detail_hue"] is not None:
                h = variant["detail_hue"]
            v = max(0.0, min(1.0, v * val_scale))
            nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), alpha)
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=os.path.join(root, "game", "assets", "enemies"))
    parser.add_argument("--companion-out",
                        default=os.path.join(root, "game", "assets", "characters", "companion"))
    parser.add_argument("--only", choices=["all", "enemies", "companion"], default="all")
    args = parser.parse_args()
    if args.only in ("all", "enemies"):
        rat = Image.open(os.path.join(args.out, "rat", "facing_8.png")).convert("RGBA")
        for enemy_id, variant in RAT_VARIANTS.items():
            _save(recolor_rat(rat, variant), args.out, enemy_id)
        for enemy_id, (frame, painter) in SILHOUETTES.items():
            _save(sheet(frame, painter), args.out, enemy_id)
    if args.only in ("all", "companion"):
        os.makedirs(args.companion_out, exist_ok=True)
        path = os.path.join(args.companion_out, "facing_4.png")
        companion_sheet().save(path, optimize=True)
        print("wrote %s (%dx%d)" % (os.path.relpath(path), 24 * 5, 24))


def _save(image, out_dir, enemy_id):
    folder = os.path.join(out_dir, enemy_id)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "facing_8.png")
    image.save(path, optimize=True)
    print("wrote %s (%dx%d)" % (os.path.relpath(path), image.width, image.height))


if __name__ == "__main__":
    main()
