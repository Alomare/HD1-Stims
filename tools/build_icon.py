"""Writes icon.jpg: the syringe of the HUD (tools/build_hud.py, the perk icon made solid) on a neutral dark
ground, filled white with round shading across it, outlined light blue.

Usage: python tools/build_icon.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import build_hud

ROOT = Path(__file__).resolve().parent.parent
SIZE = 512
GROUND = (30, 30, 30)
OUTLINE = (120, 200, 255)  # the light blue of the screen edge
OUTLINE_PX = 9
HEIGHT = 400


def main():
    a = build_hud.silhouette(build_hud.ICON)
    h, w = a.shape
    glyph = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")
    glyph = glyph.resize((int(w * HEIGHT / h), HEIGHT), Image.Resampling.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask.paste(glyph, ((SIZE - glyph.width) // 2, (SIZE - HEIGHT) // 2))
    m = np.asarray(mask, dtype=np.float32) / 255
    # Shading: brightest a little left of the middle of each row's shape, darker toward its sides, as a
    # cylinder lit from the upper left; a touch darker toward the bottom.
    # One shading for every row, across the width of the barrel (the most common width), so the grips and
    # the plunger take the barrel's light instead of starting their own.
    widths = (m > 0.5).sum(axis=1)
    rows = widths[widths > 0]
    barrel = int(np.median(rows[rows > rows.max() * 0.3]))
    centre = SIZE / 2
    t = (np.arange(SIZE) - centre) / (barrel / 2)  # -1 left edge of the barrel, 1 right edge
    light = 1 - 0.32 * np.clip(np.abs(t + 0.3) / 1.3, 0, 1) ** 1.5
    fill = light[None, :] * (1 - 0.10 * np.arange(SIZE)[:, None] / SIZE)
    white = np.clip(fill * 255, 0, 255)
    hard = mask.point(lambda v: 255 if v > 127 else 0)
    outline = np.asarray(hard.filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1)).filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255
    img = np.zeros((SIZE, SIZE, 3), np.float32)
    img[:] = GROUND
    o = outline[..., None]
    img = img * (1 - o) + np.array(OUTLINE, np.float32) * o
    mm = m[..., None]
    img = img * (1 - mm) + np.dstack([white, white, white]) * mm
    Image.fromarray(img.astype(np.uint8), "RGB").save(ROOT / "icon.jpg", quality=92)
    print(ROOT / "icon.jpg")


if __name__ == "__main__":
    main()
