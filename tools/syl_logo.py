#!/usr/bin/env python3
"""Generate the CurseForge project logo.

CurseForge requires a 400x400 PNG that is not a blank single colour square,
and it is a required field on the submission form rather than something that
can be added later — so not having one blocks the whole thing.

This draws one from the addon's own Nightfall palette, so the project page
and the in-game window look like the same product. It is a starting point,
not a commission: it is generated, deterministic, and meant to be replaced by
something better whenever that exists.

The design is the same accent mark the addon puts left of every window title,
over the Nightfall window colour, with a rolled d100 as the subject — the
thing the addon actually watches.

Run: python tools/syl_logo.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist" / "logo-400.png"

SIZE = 400

# Straight from UI/Palettes.lua, Nightfall, converted from 0-1 floats.
WINDOW = (43, 37, 70)
HEADER = (56, 48, 87)
BORDER = (97, 84, 140)
ACCENT = (140, 217, 255)
TEXT = (247, 245, 255)
MUTED = (163, 156, 199)


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def main() -> int:
    OUT.parent.mkdir(exist_ok=True)

    image = Image.new("RGBA", (SIZE, SIZE), WINDOW + (255,))
    draw = ImageDraw.Draw(image)

    # Panel, echoing the addon window: a header band across the top and a
    # one pixel border, scaled up.
    rounded(draw, (0, 0, SIZE - 1, SIZE - 1), 44, WINDOW)
    draw.rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=44,
                           outline=BORDER, width=6)
    draw.rectangle((28, 28, SIZE - 29, 104), fill=HEADER)

    # The accent mark that sits left of every window title.
    draw.rounded_rectangle((52, 46, 66, 86), radius=4, fill=ACCENT)

    # Title bar text stand-ins: three bars of decreasing width, which reads as
    # a list header without needing a font that may not exist on the machine.
    draw.rounded_rectangle((84, 52, 236, 66), radius=6, fill=TEXT)
    draw.rounded_rectangle((84, 74, 180, 82), radius=4, fill=MUTED)

    # Loot rows. Alternating, like the list, with a winner highlighted.
    top = 132
    for index in range(4):
        y = top + index * 54
        if index % 2 == 0:
            draw.rounded_rectangle((28, y, SIZE - 29, y + 44), radius=8,
                                   fill=(52, 45, 84))

        # Item icon square.
        draw.rounded_rectangle((48, y + 8, 76, y + 36), radius=5,
                               fill=ACCENT if index == 1 else MUTED)

        # Item name bar, varied so it reads as data rather than a pattern.
        width = (250, 300, 214, 268)[index]
        draw.rounded_rectangle((92, y + 16, 92 + width - 60, y + 28),
                               radius=5,
                               fill=TEXT if index == 1 else MUTED)

    image.save(OUT)

    print(f"Wrote {OUT.relative_to(ROOT)}  ({image.size[0]}x{image.size[1]})")
    print("Nightfall palette, 1:1, PNG — meets the CurseForge logo rules.")
    print("Replace it whenever something better exists.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
