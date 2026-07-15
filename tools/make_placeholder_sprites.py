"""Generate placeholder pixel-art sprites and effect textures as PNGs.

Buildings are rendered as colored pixel-art crates with their name baked
into the artwork using a tiny 3x5 pixel font.

Run with: python3 tools/make_placeholder_sprites.py
Edit the parameters and rerun to tweak.
"""
import math
import os
import struct
import zlib

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write_png(path: str, width: int, height: int, pixels: list) -> None:
    """pixels: flat list of (r, g, b, a) tuples, row-major, width*height long."""
    raw = b""
    for y in range(height):
        raw += b"\x00"  # filter: none
        for x in range(width):
            raw += bytes(pixels[y * width + x])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    full = os.path.join(PROJECT_ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "wb") as f:
        f.write(png)
    print("wrote", full)


# --- Tiny 3x5 pixel font (M/W are 5 wide, N is 4) ---------------------------

FONT = {
    "A": ["010", "101", "111", "101", "101"],
    "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"],
    "G": ["011", "100", "101", "101", "011"],
    "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "J": ["001", "001", "001", "101", "010"],
    "K": ["101", "110", "100", "110", "101"],
    "L": ["100", "100", "100", "100", "111"],
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "N": ["1001", "1101", "1011", "1001", "1001"],
    "O": ["111", "101", "101", "101", "111"],
    "P": ["111", "101", "111", "100", "100"],
    "Q": ["111", "101", "101", "111", "001"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "V": ["101", "101", "101", "101", "010"],
    "W": ["10001", "10001", "10101", "10101", "01010"],
    "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"],
    "Z": ["111", "001", "010", "100", "111"],
    " ": ["00", "00", "00", "00", "00"],
}


def text_width(text: str) -> int:
    glyphs = [FONT[ch] for ch in text.upper()]
    return sum(len(g[0]) for g in glyphs) + (len(glyphs) - 1)


def blit_text(pixels: list, width: int, text: str, x: int, y: int, color: tuple) -> None:
    cursor = x
    for ch in text.upper():
        glyph = FONT[ch]
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    pixels[(y + gy) * width + cursor + gx] = color
        cursor += len(glyph[0]) + 1


# --- Labeled crate sprites ---------------------------------------------------


def scale(color: tuple, factor: float) -> tuple:
    return tuple(min(255, int(c * factor)) for c in color[:3]) + (255,)


def luminance(color: tuple) -> float:
    return (0.299 * color[0] + 0.587 * color[1] + 0.114 * color[2]) / 255.0


def make_labeled_crate(path: str, text: str, fill: tuple, width: int = 24, height: int = 20) -> None:
    fill = fill[:3] + (255,)
    outline = scale(fill, 0.35)
    highlight = scale(fill, 1.25)
    shade = scale(fill, 0.75)
    text_color = (35, 28, 22, 255) if luminance(fill) > 0.5 else (248, 244, 234, 255)

    pixels = []
    for y in range(height):
        for x in range(width):
            on_border = x == 0 or y == 0 or x == width - 1 or y == height - 1
            if on_border:
                pixels.append(outline)
            elif y == 1:
                pixels.append(highlight)
            elif y >= height - 3:
                pixels.append(shade)
            else:
                pixels.append(fill)

    tw = text_width(text)
    assert tw <= width - 2, f"'{text}' too wide for {width}px sprite"
    blit_text(pixels, width, text, (width - tw) // 2, (height - 5) // 2, text_color)
    write_png(path, width, height, pixels)


# --- Buildings -------------------------------------------------------------
# No placeholder generation here anymore: every building type (Oven,
# Shipping Bin, Cutting Station, Assembly Table, Mixer, and — as of
# 2026-07-13 — every Ingredient Source: Flour/Butter/Egg/Milk/Sugar) now
# has real hand-drawn art, cropped + downscaled from user-provided source
# images the same way flour/butter's item art was originally (see
# decisions.md). Several also have extra per-state sprites swapped in by
# their own building scripts (Oven on/off; Shipping Bin closed/open;
# Cutting Station waiting/active-up/active-down; Assembly Table
# idle/active-1/active-2; Mixer idle/progress-1..4) — see architecture.md.
# If a new building type is ever added before real art exists for it,
# make_labeled_crate() (above) is still the tool to reach for; there's
# just nothing left currently using it here.

# --- Cats ---------------------------------------------------------------
# No placeholder here: cats use a real, hand-drawn sprite sheet
# (assets/sprites/cats/sprite_sheet.png, 4 frames of a walk cycle), not a
# generated crate. See cat.tscn/cat.gd.

# --- Items ---------------------------------------------------------------
# No placeholder generation here anymore: every item (flour/butter, plus
# all 32 formerly-generated crate tiles) is now real hand-drawn art,
# cropped + downscaled from user-provided source images the same way
# flour/butter were originally — see decisions.md. If a new item is ever
# added before real art exists for it, make_labeled_crate() (above) is
# still the tool to reach for; there's just nothing left currently using
# it here.

# --- Blob shadow: soft dark ellipse, 32x32 ---------------------------------

BLOB_SIZE = 32
blob = []
center = (BLOB_SIZE - 1) / 2.0
for y in range(BLOB_SIZE):
    for x in range(BLOB_SIZE):
        r = math.hypot(x - center, y - center) / (BLOB_SIZE / 2.0)
        alpha = max(0.0, 1.0 - r * r) * 0.45
        blob.append((60, 50, 40, int(alpha * 255)))

write_png("assets/sprites/effects/blob_shadow.png", BLOB_SIZE, BLOB_SIZE, blob)
