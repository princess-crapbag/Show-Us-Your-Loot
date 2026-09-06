# -*- coding: utf-8 -*-
"""Where the version number goes, drawn three ways before anything is edited.

Aimee: "can we show the version number somewhere like in the settings page?"

Three placements at the real width, the real game font and the real Nightfall
palette, so the choice is made from a picture rather than a description. The
value is not typed here either -- it is read out of the .toc, the same place
Main.lua reads SYL.version from, so this cannot drift from what ships.

Writes screenshots/version-line.png.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import io
import os
import re

from PIL import Image

from mockup_settings_tabs import (
    C, SCALE, WIDTH, PAD, CONTENT, GROUND, WINDOW, ACCENT,
    TEXT_1, TEXT_2, TEXT_3, SEP, BUTTON, measure,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# THE SAME SOURCE THE ADDON USES. Main.lua reads it out of the .toc through
# GetAddOnMetadata, and the packager rewrites that line from the git tag when
# it builds the zip -- so a number typed into this file would be the one thing
# on screen that could be wrong.
TOC = io.open(os.path.join(ROOT, "ShowUsYourLoot.toc"), encoding="utf-8").read()
VERSION = re.search(r"^## Version:\s*(.+)$", TOC, re.M).group(1).strip()

TITLE = "Show Us Your Loot"

PANEL_H = 108
GAP = 18


def chrome(c, label):
    """The top of the settings window, for the option that lives up there."""
    c.rect(0, 0, WIDTH, PANEL_H, WINDOW)
    c.rect(0, 0, WIDTH, 3, ACCENT)

    c.text(PAD, 16, "SETTINGS", 15, TEXT_1)
    c.right(WIDTH - PAD, 16, "x", 12, TEXT_3)

    return label


def option_a(c):
    """Bottom left of the footer, opposite Close."""
    chrome(c, None)
    c.text(PAD, 40, "What gets recorded, and what runs at all", 10, TEXT_3)
    c.rect(PAD, 62, CONTENT, 1, SEP)

    c.rect(PAD, PANEL_H - 38, CONTENT, 1, SEP)

    text = TITLE + "  " + VERSION
    c.text(PAD, PANEL_H - 26, text, 10, TEXT_3)

    bw = measure("Close", 11) + 44
    c.rect(WIDTH - PAD - bw, PANEL_H - 32, bw, 24, BUTTON)
    c.text(WIDTH - PAD - bw + 22, PANEL_H - 27, "Close", 11, TEXT_1)

    return "A — footer, beside Close", measure(text, 10)


def option_b(c):
    """On the subtitle line, where the window already says what it is."""
    chrome(c, None)

    subtitle = "What gets recorded, and what runs at all"
    c.text(PAD, 40, subtitle, 10, TEXT_3)

    x = PAD + measure(subtitle, 10) + 8
    c.text(x, 40, "\u00b7", 10, SEP)
    c.text(x + 8, 40, VERSION, 10, ACCENT)

    c.rect(PAD, 62, CONTENT, 1, SEP)
    c.rect(PAD, PANEL_H - 38, CONTENT, 1, SEP)

    bw = measure("Close", 11) + 44
    c.rect(WIDTH - PAD - bw, PANEL_H - 32, bw, 24, BUTTON)
    c.text(WIDTH - PAD - bw + 22, PANEL_H - 27, "Close", 11, TEXT_1)

    return "B — on the subtitle line", x + 8 + measure(VERSION, 10)


def option_c(c):
    """Right of the title, the way an app names itself."""
    chrome(c, None)

    x = PAD + measure("SETTINGS", 15) + 10
    c.text(x, 21, TITLE + " " + VERSION, 10, TEXT_3)

    c.text(PAD, 40, "What gets recorded, and what runs at all", 10, TEXT_3)
    c.rect(PAD, 62, CONTENT, 1, SEP)
    c.rect(PAD, PANEL_H - 38, CONTENT, 1, SEP)

    bw = measure("Close", 11) + 44
    c.rect(WIDTH - PAD - bw, PANEL_H - 32, bw, 24, BUTTON)
    c.text(WIDTH - PAD - bw + 22, PANEL_H - 27, "Close", 11, TEXT_1)

    return "C — beside the title", x + measure(TITLE + " " + VERSION, 10)


OPTIONS = [option_a, option_b, option_c]

LABEL_H = 22
height = (PANEL_H + LABEL_H + GAP) * len(OPTIONS) + GAP

img = Image.new("RGB", (WIDTH * SCALE, height * SCALE), GROUND)

y = GAP
problems = []

for draw in OPTIONS:
    label_c = C(img, 0, y)
    panel = C(img, 0, y + LABEL_H)

    name, used = draw(panel)

    label_c.text(PAD, 4, name, 11, TEXT_2)

    # Nothing may reach the Close button, which is what a version string
    # growing to "0.4.10-alpha" would do if it were placed by eye.
    close_left = WIDTH - PAD - (measure("Close", 11) + 44)

    if used > close_left - 12:
        problems.append("%s: %d used, %d before Close"
                        % (name, used, close_left))

    y += PANEL_H + LABEL_H + GAP

out = os.path.join(ROOT, "screenshots", "version-line.png")
img.save(out)

print("version read from the .toc: " + VERSION)
print("wrote " + out)
print("clashes: " + (", ".join(problems) if problems else "none"))
