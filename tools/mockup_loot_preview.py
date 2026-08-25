# -*- coding: utf-8 -*-
"""The Loot tab exactly as it will look when this is done.

Aimee: "give me a true preview of exactly how the screen will look once
complete."

So this is the whole window at its real 900 x 596, not a strip of it: the
title, the tabs, the one filter row, the column headers with their filter
carets, fourteen real rows out of her own database, and the action buttons on
the footer line beside Close.

EVERY NUMBER HERE IS THE ADDON'S OWN. The window is 900 x 596
(UI/MainWindow.lua), rows are 28 (Theme.metrics.rowHeight), the footer rule
sits 44 from the bottom with the buttons 12 from it (UI/MainFooter.lua), and
the columns are the widths in UI/Columns.lua with WHERE giving up 34 to DIFF.

WHERE THE EXTRA ROW COMES FROM. Today the list starts 180 from the top --
title, tabs, the filter bar, the selection bar, the count and the column
header, stacked. Taking the actions to the footer removes a whole 28px row
from that stack, and the footer had nothing on its left: UI/MainFooter.lua's
BUTTONS list is empty, because all six of its buttons became tabs. So the
list starts at 152 and fits fourteen rows instead of thirteen.

WINDOWS ARE SOLID. Hers: "no opacity slider. keep it solid." Every palette
has carried 0.97 since they were written and only the front window was ever
painted at 1. That goes to 1 everywhere -- see the note at the foot of the
picture for what has to replace it.

Writes screenshots/loot-preview.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, C, GROUND, SCALE, TEXT_1, TEXT_2, TEXT_3, WARNING, WINDOW,
    ROW_ALT, SEP, BUTTON, QUALITY_COLOR, over, measure, wrap,
)

WIDTH = 900
HEIGHT = 596
INSET = 16
ROW = WIDTH - INSET * 2

ROW_HEIGHT = 28
BAR_HEIGHT = 22

# UI/Columns.lua, plus DIFFICULTY. Measured, not chosen:
#
#   the header "DIFFICULTY" is 55px and is the WIDEST thing in the column --
#   "Normal", the longest value, is only 38.5 -- and the caret sits after it,
#   so the column needs 55 + 4 + 8 and gets 72. At 58 the caret ran into DATE,
#   which is exactly the kind of thing a drawing is for.
#
#   "The Tidebound Grotto" is 116, so WHERE keeps 122 rather than the 150 it
#   had; it never needed the other 28.
#
# The 14 comes from ITEM, which is the column with room to give: the widest
# real item name is "Skullguard of the Risen Sacrifice" at 166.5 plus a 20px
# icon, against 236. That is the same place UI/Columns.lua already takes a
# date-column shortfall from, and for the same reason.
COLUMNS = [
    ("", 16, 8), ("#", 30, 8), ("PLAYER", 130, 8), ("ITEM", 236, 10),
    ("TYPE", 76, 8), ("WHERE", 122, 6), ("DIFFICULTY", 72, 10),
    ("DATE", 96, 10),
]

FILTERED = {"PLAYER", "ITEM", "TYPE", "WHERE", "DIFFICULTY", "DATE"}

TABS = ["Dashboard", "Loot", "Raiders", "Calendar", "Bosses", "Keys",
        "Archives"]

CLASS = {
    "DEATHKNIGHT": (196, 30, 58), "DEMONHUNTER": (163, 48, 201),
    "DRUID": (255, 124, 10), "EVOKER": (51, 147, 127),
    "HUNTER": (170, 211, 114), "MAGE": (63, 199, 235),
    "MONK": (0, 255, 152), "PALADIN": (244, 140, 186),
    "PRIEST": (255, 255, 255), "ROGUE": (255, 244, 104),
    "SHAMAN": (0, 112, 221), "WARLOCK": (135, 136, 238),
    "WARRIOR": (198, 155, 109),
}

# Her raiders and the pugs in the 08/23 LFR, from the session rosters.
WHO = {
    "Arcangila": "HUNTER", "Camcar": "HUNTER", "Hawt": "ROGUE",
    "Jtkurayami": "PRIEST", "Phreestyle": "SHAMAN", "Rakahasa": "SHAMAN",
    "Razortongue": "WARRIOR", "Misothelioma": "MAGE", "Niwmn": "DEATHKNIGHT",
    "Pringlesbop": "PALADIN", "Syzzlac": "WARLOCK",
    # The LFR pugs. Unknown to the registry, so they draw plain -- which is
    # itself true to what the screen will do.
}

EPIC = QUALITY_COLOR["Epic (purple)"]

# Her real drops, newest first, as the new defaults will show them: raids
# only, gear only, personal loot hidden. The three Eastern Kingdoms world
# drops in her screenshot fall out because they are not raid content.
ROWS = [
    ("Xinnci", "Venomwoven Effigy", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:35 PM"),
    ("Shinryunin", "Venomcast Effigy", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:35 PM"),
    ("Xinnci", "Vexhul's Everflowing Gland", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:35 PM"),
    ("Kombatgodess", "Scaleplate Strangulators", "Need", "Venomous Abyss",
     "LFR", "08/23/26 7:35 PM"),
    ("Fangsnclaws", "Restless Spirit Shackles", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:20 PM"),
    ("Foehammer", "Skullguard of the Risen Sacrifice", "Need",
     "Venomous Abyss", "LFR", "08/23/26 7:20 PM"),
    ("Xinnci", "Hexing Spiritrender", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:20 PM"),
    ("Gerti", "Nek'zali's Spiritwalkers", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:20 PM"),
    ("Wraitheus", "Nek'zali's Spiritwalkers", "Need", "Venomous Abyss", "LFR",
     "08/23/26 7:20 PM"),
    ("Jtkurayami", "Grasps of the Eternal Shadow", "Greed", "Venomous Abyss",
     "Normal", "08/20/26 9:11 PM"),
    ("Hawt", "Baleful Hexblade", "Need", "Venomous Abyss", "Normal",
     "08/20/26 9:11 PM"),
    ("Camcar", "Ophidian Fangmail", "Need", "Venomous Abyss", "Normal",
     "08/20/26 7:36 PM"),
    ("Phreestyle", "Venomcast Effigy", "Need", "Venomous Abyss", "Normal",
     "08/20/26 7:36 PM"),
    ("Hawt", "Ravenous Feaster's Fang", "Greed", "Venomous Abyss", "Normal",
     "08/20/26 7:36 PM"),
]


def button(c, x, y, label, width=None, height=BAR_HEIGHT, color=TEXT_1):
    width = width or (measure(label, 11) + 24)
    c.rect(x, y, width, height, BUTTON)
    c.text(x + (width - measure(label, 11)) / 2, y + (height - 13) / 2,
           label, 11, color)
    return width


def draw(img, ox, oy):
    c = C(img, ox, oy)

    # SOLID. See the header.
    c.rect(0, 0, WIDTH, HEIGHT, WINDOW)
    c.rect(0, 0, 3, HEIGHT, ACCENT)

    c.text(INSET + 6, 18, "SHOW US YOUR LOOT", 15, TEXT_1)
    c.text(27, 40, "Midnight Season 2", 10, TEXT_3)
    c.right(WIDTH - 18, 18, "x", 12, WARNING)
    c.rect(WIDTH - 74, 14, 22, 22, BUTTON)

    # The tab strip.
    x = INSET + 6

    for name in TABS:
        width = measure(name, 11) + 26
        on = name == "Loot"

        c.text(x + 13, 68, name, 11, ACCENT if on else TEXT_3)

        if on:
            c.rect(x, 86, width, 2, ACCENT)

        x += width

    c.rect(INSET, 87, ROW, 1, SEP)

    # ONE FILTER ROW: search, the count, Clear. Nothing else can push it.
    c.rect(INSET, 100, 180, BAR_HEIGHT, ROW_ALT)
    c.text(INSET + 6, 105, "Search...", 11, TEXT_3)

    c.text(INSET + 194, 105, "38 of 53 items  ·  18 hidden", 11, TEXT_2)

    button(c, WIDTH - INSET - 54, 100, "Clear", 54)

    # THE COLUMN HEADERS, each with its own filter caret.
    top = 130
    x = INSET

    for label, width, gap in COLUMNS:
        if label:
            # TYPE and DIFF are narrowed in this picture, so they are drawn
            # the way a set filter reads: accent, not muted.
            active = label in ("TYPE", "DIFFICULTY")

            c.text(x, top + 4, label, 10, ACCENT if active else TEXT_3)

            if label in FILTERED:
                # In the gap after the name, so it costs the column nothing.
                c.text(x + measure(label, 10) + 4, top + 4, "v", 10,
                       ACCENT if active else TEXT_3)

        x += width + gap

    c.rect(INSET, top + 18, ROW, 1, SEP)

    # FOURTEEN ROWS. Today it is thirteen.
    listTop = 152

    for index, row in enumerate(ROWS):
        y = listTop + index * ROW_HEIGHT

        if index % 2 == 1:
            c.rect(INSET, y, ROW, ROW_HEIGHT, ROW_ALT)

        who, item, kind, where, diff, when = row
        x = INSET

        for position, (label, width, gap) in enumerate(COLUMNS):
            middle = y + 8

            if position == 0:
                c.box(x + 1, middle - 1, False)
            elif position == 1:
                c.text(x, middle, str(index + 1), 11, TEXT_3)
            elif position == 2:
                c.text(x, middle, who, 11,
                       CLASS.get(WHO.get(who, ""), TEXT_2))
            elif position == 3:
                c.rect(x, middle - 1, 14, 14, over((1, 1, 1, 0.10), WINDOW))
                c.text(x + 20, middle, item, 11, EPIC)
            elif position == 4:
                c.text(x, middle, kind, 11, TEXT_2)
            elif position == 5:
                c.text(x, middle, where, 11, TEXT_2)
            elif position == 6:
                c.text(x, middle, diff, 11, TEXT_2)
            else:
                c.text(x, middle, when, 11, TEXT_2)

            x += width + gap

    # THE FOOTER. The rule and Close are where they already are; the actions
    # take the left half, which UI/MainFooter.lua's empty BUTTONS list left
    # free when its six buttons became tabs.
    c.rect(INSET, HEIGHT - 44, ROW, 1, SEP)

    x = INSET

    for label in ("Select all", "Deselect all", "Ignore", "Hide", "Hide all",
                  "Show hidden"):
        x += button(c, x, HEIGHT - 38, label, height=26) + 6

    # The three scope toggles, right-aligned beside Close, because they
    # narrow the list rather than act on it.
    at = WIDTH - INSET - 100 - 6

    for label in ("All content", "Everything", "This season"):
        width = measure(label, 11) + 24
        at -= width
        button(c, at, HEIGHT - 38, label, width, height=26)
        at -= 6

    button(c, WIDTH - INSET - 100, HEIGHT - 38, "Close", 100, height=26)

    return HEIGHT


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    MARGIN = 40
    W = MARGIN * 2 + WIDTH
    H = 150 + HEIGHT + 190

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    G1 = over((0.97, 0.96, 1.00, 1), GROUND)
    G3 = over((0.64, 0.61, 0.78, 1), GROUND)
    GA = over((0.55, 0.85, 1.00, 1), GROUND)

    page.text(MARGIN, 28, "The Loot tab, finished", 15, G1)
    page.text(MARGIN, 56,
              "The whole window at its real 900 x 596, with your own drops. "
              "Raids only and Gear only are on, which is why the three "
              "Eastern Kingdoms world drops are not here.", 10, G3)
    page.text(MARGIN, 74,
              "Nothing overlaps: every width below is the addon's own, "
              "measured rather than chosen.", 10, G3)

    draw(img, MARGIN, 110)

    y = 110 + HEIGHT + 30

    for label, color, text in [
        ("ONE ROW ON TOP", GA,
         "Search, the count, Clear. The five dropdowns are gone from it, so "
         "it cannot overflow again however many filters are added later."),
        ("CARETS IN THE HEADERS", GA,
         "PLAYER, ITEM, TYPE, WHERE, DIFFICULTY and DATE each open the "
         "dropdown that used to sit on the bar, and the NAME still sorts the "
         "way it does today - two targets, one header. TYPE and DIFFICULTY "
         "are drawn accent here because they are narrowed, which is how a "
         "set filter reads at a glance."),
        ("DIFFICULTY, SPELLED OUT", GA,
         "The header is the widest thing in it at 55px - Normal, the longest "
         "value, is only 38.5 - and the caret sits after it, so it takes 72. "
         "WHERE keeps 122 against a widest of 116 for The Tidebound Grotto; "
         "it never needed the 150 it had. The 14 that is left comes out of "
         "ITEM, which has 49px of slack over the longest real item name."),
        ("FOURTEEN ROWS, NOT THIRTEEN", GA,
         "The actions move to the footer line, which was empty on the left - "
         "MainFooter's button list has been empty since its six buttons "
         "became tabs. That takes a 28px row out of the top stack and adds "
         "none at the bottom."),
        ("SOLID", G3,
         "Every palette drops 0.97 to 1. The alpha was doing one job besides "
         "looking nice - the front window was painted solid and the rest "
         "slightly through, which is how you could tell which was in front. "
         "That moves to the border color instead, or it is silently lost."),
        ("NONE", G3,
         "Fixed with this: \"nothing chosen yet\" and \"chosen nothing\" "
         "become different states, so None shows nothing instead of "
         "everything."),
    ]:
        page.text(MARGIN, y, label, 10, color)
        for n, part in enumerate(wrap(text, 10, W - MARGIN * 2 - 210)):
            page.text(MARGIN + 210, y + n * 13, part, 10, G3)
        y += max(18, len(wrap(text, 10, W - MARGIN * 2 - 210)) * 13 + 8)

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\loot-preview.png")
    img.save(out)

    print("wrote loot-preview.png", img.size)
