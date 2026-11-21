"""Builds the HUD art of Stims: the syringe the loadout card shows, white so the game tints it, and the
gui material that names it.

Usage: python tools/build_hud.py [perk icon]

The syringe is the game's Adrenaline perk icon (perk_adrenaline_01, read from the game through Minediver;
Mods/_assets/perk_icons holds a copy) made one solid shape: every pixel the icon covers, holes filled,
turned upright with the needle at the top. The barrel is cut into SEGMENTS cells by clear lines, one cell
per stim, and the rows of each cell are written to res/hud_layout.lua for src/hud.lua, which draws each
cell as its own band of the texture.

The boost edge (stims_edge) is the edges of the screen, white, stretched over the window.

Writes res/hud_syringe.texture, res/hud_edge.texture, res/hud.material, src/hud_layout.lua and internal/hud_preview.png.
Needs Pillow and numpy.

The material is a list of records as the game's own gui materials have them: the top 32 bits of
murmur64 of the sprite name, the template of the game's font material (it multiplies the texture by the
colour of each draw), and the texture as the diffuse map.
"""
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "res"
BASE = "stims/hud"
SPRITE = "stims_syringe"
EDGE = "stims_edge"
MATERIAL_VERSION = 10
TEMPLATE, DIFFUSE_MAP, VARIABLE = 0xba25de35, 0x3aa8b87e, 0x46f80ade
ICON = ROOT.parent.parent / "_assets" / "perk_icons" / "perk_adrenaline_01.png"
SEGMENTS = 4
HEIGHT = 256   # texture height in pixels; the width follows the shape, rounded up to a multiple of 4
GAP = 0.035    # clear line between two cells, as a share of the texture height
NEEDLE_LENGTH = 0.55  # share of the needle kept
NEEDLE_WIDTH = 0.22   # needle width as a share of the barrel width


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def dds_rgba(image):
    """Uncompressed BGRA with mips, a form the game's own textures take."""
    image = image.convert("RGBA")
    width, height = image.size
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x0002100F, height, width, width * 4, 0, len(mips))
    struct.pack_into("<II4sIIIII", header, 76, 32, 0x41, b"\0\0\0\0", 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    struct.pack_into("<I", header, 108, 0x00401008)
    body = b""
    for mip in mips:
        r, g, b, a = mip.split()
        body += Image.merge("RGBA", (b, g, r, a)).tobytes()
    return bytes(header) + body + bytes(4)


def fill_holes(mask):
    """mask with every clear region that doesn't reach the border filled in."""
    h, w = mask.shape
    outside = np.zeros_like(mask)
    stack = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    while stack:
        y, x = stack.pop()
        if outside[y, x] or mask[y, x]:
            continue
        outside[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    return ~outside


def silhouette(path):
    """The icon as one solid upright shape, needle up: a float alpha array at HEIGHT rows."""
    icon = Image.open(path).convert("RGBA")
    big = icon.resize((icon.width * 4, icon.height * 4), Image.Resampling.LANCZOS)
    a = np.asarray(big.getchannel("A"), dtype=np.float32) / 255
    solid = fill_holes(a > 0.25)
    # Turned a quarter clockwise: the needle, at the left, goes to the top.
    solid = np.rot90(solid, k=-1)
    ys, xs = np.nonzero(solid)
    solid = solid[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    # The needle, a few pixels wide, would vanish at the card's size: kept at NEEDLE_LENGTH of its length
    # and drawn NEEDLE_WIDTH of the barrel's width.
    widths = solid.sum(axis=1)
    barrel = int(np.median(widths[widths > widths.max() * 0.3]))
    thin = 0
    while widths[thin] < barrel * 0.2:
        thin += 1
    cut = int(thin * (1 - NEEDLE_LENGTH))
    solid = solid[cut:].copy()
    thin -= cut
    mid = solid.shape[1] / 2
    half = max(1, int(barrel * NEEDLE_WIDTH / 2))
    solid[:thin, :] = False
    solid[:thin, int(mid - half):int(mid + half)] = True
    image = Image.fromarray((solid * 255).astype(np.uint8), "L")
    w = max(4, int(round(image.width * HEIGHT / image.height / 4 + 0.5)) * 4)
    pad = Image.new("L", (w, HEIGHT), 0)
    scaled = image.resize((int(round(image.width * HEIGHT / image.height)), HEIGHT), Image.Resampling.LANCZOS)
    pad.paste(scaled, ((w - scaled.width) // 2, 0))
    return np.asarray(pad, dtype=np.float32) / 255


def barrel_rows(alpha):
    """First and last row of the barrel: the longest run of rows whose width stays near the most common
    wide width, below the needle and above the flange."""
    widths = (alpha > 0.5).sum(axis=1)
    top = widths.max()
    wide = [i for i, w in enumerate(widths) if w > top * 0.3]
    # Rows of the barrel: wider than the needle, narrower than the flange, in one run.
    runs, start = [], None
    target = np.median([widths[i] for i in wide])
    for i, w in enumerate(widths):
        ok = abs(w - target) <= max(2, target * 0.12)
        if ok and start is None:
            start = i
        if not ok and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(widths) - 1))
    return max(runs, key=lambda r: r[1] - r[0]), widths


def noise(shape, cells, seed):
    """Smooth value noise, cells across the width."""
    rng = np.random.default_rng(seed)
    h, w = shape
    gw, gh = cells + 2, max(2, round(cells * h / w)) + 2
    grid = rng.random((gh, gw))
    y, x = np.mgrid[0:h, 0:w]
    fx, fy = x / w * (gw - 2), y / h * (gh - 2)
    ix, iy = fx.astype(int), fy.astype(int)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = grid[iy, ix] * (1 - tx) + grid[iy, ix + 1] * tx
    b = grid[iy + 1, ix] * (1 - tx) + grid[iy + 1, ix + 1] * tx
    return a * (1 - ty) + b * ty


def edge(w=512, h=288):
    """The edges of the screen for the boost, strongest at the border and the corners, with a soft uneven
    inner edge (the look of Eyes of Liberty's hurt edge, smoother and thinner)."""
    y, x = np.mgrid[0:h, 0:w] + 0.5
    u, v = x / w, y / h
    d = np.minimum(np.minimum(u, 1 - u) * (w / h), np.minimum(v, 1 - v))
    cu, cv = np.abs(u - 0.5) * 2, np.abs(v - 0.5) * 2
    reach = 0.13 + 0.09 * (cu * cv) ** 2
    rough = 0.6 * noise((h, w), 7, 21) + 0.4 * noise((h, w), 17, 33)
    reach = reach * (0.75 + 0.5 * rough)
    a = np.clip(1 - d / reach, 0, 1) ** 2.2
    a = np.maximum(a, np.clip(1 - d / 0.01, 0, 1) * 0.8)
    rgba = np.dstack([np.full((h, w, 3), 255, np.uint8), (a * 255 + 0.5).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def material(sprites):
    records = []
    for sprite in sprites:
        name = murmur64(sprite.encode()) >> 32
        tex = murmur64(f"{BASE}/{sprite}".encode())
        records.append((name, struct.pack("<13I", name, TEMPLATE, 0, 0, 1, DIFFUSE_MAP, tex & 0xFFFFFFFF, tex >> 32, 1, VARIABLE, 0, 0, 0)))
    records.sort()
    return struct.pack("<II", MATERIAL_VERSION, len(records)) + b"".join(r for _, r in records)


def main():
    alpha = silhouette(Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else ICON)
    (b0, b1), widths = barrel_rows(alpha)
    if "--widths" in sys.argv: print(list(enumerate(widths.tolist())))
    gap = max(2, int(round(GAP * HEIGHT)))
    # SEGMENTS equal cells from b0 to b1, a clear line of `gap` rows between two.
    cell = (b1 - b0 + 1 - gap * (SEGMENTS - 1)) / SEGMENTS
    cells = []
    for i in range(SEGMENTS):
        top = b0 + i * (cell + gap)
        cells.append((int(round(top)), int(round(top + cell)) - 1))
    for (t0, t1), (n0, _) in zip(cells, cells[1:]):
        alpha[t1 + 1:n0, :] = 0
    h, w = alpha.shape
    rgba = np.dstack([np.full((h, w, 3), 255, np.uint8), (alpha * 255 + 0.5).astype(np.uint8)])
    image = Image.fromarray(rgba, "RGBA")
    RES.mkdir(exist_ok=True)
    (RES / "hud_syringe.texture").write_bytes(dds_rgba(image))
    (RES / "hud_edge.texture").write_bytes(dds_rgba(edge()))
    (RES / "hud.material").write_bytes(material([SPRITE, EDGE]))
    # Bands in texture rows from the top, as shares of the height: the cells bottom first (stim 1 is the
    # lowest cell), and the parts above and below the barrel.
    v = lambda row: round(row / h, 5)
    lines = [
        "-- Written by tools/build_hud.py. Do not edit.",
        "-- The syringe texture's bands as shares of its height from the top (v), stim 1 the lowest cell.",
        "return {",
        f"\tsprite = \"{SPRITE}\",",
        f"\taspect = {round(w / h, 5)}, -- width over height",
        f"\ttop = {{ 0, {v(cells[0][0])} }}, -- the needle and hub",
        f"\tbottom = {{ {v(cells[-1][1] + 1)}, 1 }}, -- the flange and plunger",
        "\tcells = {",
    ]
    for t0, t1 in reversed(cells):
        lines.append(f"\t\t{{ {v(t0)}, {v(t1 + 1)} }},")
    lines += ["\t},", "}", ""]
    (ROOT / "src" / "hud_layout.lua").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    # A look over the card's brown, at three sizes, full and with two stims.
    preview = Image.new("RGBA", (w * 4 + 80, h + 20), (92, 70, 48, 255))
    preview.alpha_composite(image, (10, 10))
    grey = image.copy()
    ga = np.asarray(grey).copy()
    ga[..., :3] = 128
    for t0, t1 in cells[:2]:
        pass
    two = np.asarray(image).copy()
    for t0, t1 in cells[:2]:  # the top two cells empty: two stims left
        two[t0:t1 + 1, :, :3] = 128
    preview.alpha_composite(Image.fromarray(two, "RGBA"), (w + 30, 10))
    small = image.resize((max(1, w * 40 // h), 40), Image.Resampling.LANCZOS)
    preview.alpha_composite(small, (2 * w + 60, 10))
    (ROOT / "internal").mkdir(exist_ok=True)
    preview.save(ROOT / "internal" / "hud_preview.png")
    print("size", w, h, "barrel rows", b0, b1, "cells", cells)
    print(SPRITE, f"{BASE}/{SPRITE}", hex(murmur64(f'{BASE}/{SPRITE}'.encode())))


if __name__ == "__main__":
    main()
