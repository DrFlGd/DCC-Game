#!/usr/bin/env python3
"""Generate the placeholder application icon for DCC Game.

Writes a 128x128 PNG: a dark stone tile with a gold descending-stair glyph and
a red "collapse clock" notch. Original placeholder art, not a final icon.

Usage (from the repository root):
    python3 tools/gen_icon.py [--out game/assets/ui/icon.png]
Requires Pillow. Output is deterministic.
"""
import argparse
import os

from PIL import Image, ImageDraw

SIZE = 128
BG = (22, 26, 38, 255)
STONE = (58, 64, 82, 255)
STONE_DARK = (38, 42, 56, 255)
GOLD = (246, 212, 141, 255)
GOLD_DARK = (176, 132, 64, 255)
RED = (214, 72, 72, 255)
OUTLINE = (12, 10, 18, 255)


def draw_icon() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Rounded stone plate.
    d.rounded_rectangle([2, 2, SIZE - 3, SIZE - 3], radius=18, fill=BG, outline=OUTLINE, width=3)
    d.rounded_rectangle([10, 10, SIZE - 11, SIZE - 11], radius=12, fill=STONE, outline=STONE_DARK, width=2)
    # Masonry seams.
    for y in (38, 66, 94):
        d.line([14, y, SIZE - 15, y], fill=STONE_DARK, width=2)
    for row, y0 in enumerate((12, 38, 66, 94)):
        offset = 0 if row % 2 == 0 else 18
        for x in range(26 + offset, SIZE - 14, 36):
            d.line([x, y0 + 2, x, min(y0 + 26, SIZE - 14)], fill=STONE_DARK, width=2)
    # Descending stairs (gold), each step one tile lower and narrower.
    steps = 5
    for i in range(steps):
        x0 = 28 + i * 12
        y0 = 36 + i * 13
        x1 = 100
        y1 = y0 + 11
        d.rectangle([x0, y0, x1, y1], fill=GOLD if i % 2 == 0 else GOLD_DARK, outline=OUTLINE, width=2)
    # Collapse-clock notch: a red pie in the top-left corner.
    d.ellipse([16, 16, 44, 44], fill=OUTLINE)
    d.pieslice([18, 18, 42, 42], start=-90, end=150, fill=RED)
    return img


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="game/assets/ui/icon.png")
    args = parser.parse_args()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    draw_icon().save(args.out, optimize=True)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
