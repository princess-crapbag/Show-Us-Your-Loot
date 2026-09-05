# -*- coding: utf-8 -*-
"""The Bosses tab, drawn at its real size: now and proposed.

Aimee: "on the bosses tab where we see loot that has or has not dropped. can
we have a filter there so we dont see all difficulties at once? do we need a
button that says dropped and not dropped? couldnt it just show 2 lists of
dropped and not dropped? can the items on both lists show the actual tooltip
for the item like we have in other places? can you also make sure the text in
this section is very clear and not confusing to other users?"

Four asks and they all point the same way. Today the rail lists every boss
once PER DIFFICULTY -- her eight Heroic kills sit in the same list as the same
bosses on Normal and LFR, so the rail is three times longer than the raid is
-- and the pane shows one of two lists behind a toggle, so answering "what has
this boss still not given us" means finding the right row and then pressing a
button to see the other half of the answer.

Both lists side by side removes the toggle and the question it was answering.
The pane is 606 wide, which is two columns of 295 with a gutter -- measured,
not guessed.

THE WORDING. "Not dropped" reads as a fact about the boss; it is a fact about
this guild's luck, and only for the difficulty being looked at. The headings
say so, and the caveat that used to be a footnote in small print -- the
Adventure Guide lists what a boss can drop for ANY specialization -- is said
where it changes what the number means.

Names and counts are hers, off the 09/03 database: The Twin Fangs on Heroic
has given Ophidian Fangmail twice and Vexhul's Everflowing Gland once.

Writes screenshots/boss-loot.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, BUTTON, C, GROUND, ROW_ALT, SCALE, SEP, TEXT_1,
    TEXT_2, TEXT_3, WARNING, WINDOW, check, measure, problems, wrap,
)

RAIL_WIDTH = 250
GUTTER = 12
PANE_WIDTH = 868 - RAIL_WIDTH - GUTTER      # 606
PANEL_HEIGHT = 398

PAD = 10
ROW_HEIGHT = 18

QUALITY = (163, 53, 238)                    # epic

# Her Heroic bosses, in kill order, from raids[*].encounters.
BOSSES = [
    ("Nek'zali the Soulcoiler", "The Venomous Abyss", 3),
    ("The Lost Explorers", "The Venomous Abyss", 2),
    ("Entombed Sentinels", "The Venomous Abyss", 2),
    ("Vashnik the Malignant", "The Venomous Abyss", 4),
    ("Sszorak", "The Venomous Abyss", 1),
    ("The Twin Fangs", "The Venomous Abyss", 3),
    ("Nymrissa Wavecaller", "The Tidebound Grotto", 2),
]

# The same rail as it is today: every boss once per difficulty.
BOSSES_NOW = [
    ("Nek'zali the Soulcoiler", "H", 3),
    ("Nek'zali the Soulcoiler", "N", 5),
    ("Nek'zali the Soulcoiler", "LFR", 2),
    ("The Lost Explorers", "H", 2),
    ("The Lost Explorers", "N", 4),
    ("The Lost Explorers", "LFR", 1),
    ("Entombed Sentinels", "H", 2),
    ("Entombed Sentinels", "N", 3),
]

DROPPED = [
    ("Ophidian Fangmail", 2),
    ("Vexhul's Everflowing Gland", 1),
]

NOT_DROPPED = [
    "Fangmarked Shoulderguards",
    "Venomsteeped Legguards",
    "Coilfang Bracers",
    "Serpentscale Warboots",
    "Tongue of the Deep",
    "Twinfang Signet",
]


def head(c, text, right=None, size=10):
    c.text(PAD, 0, text, size, TEXT_3)

    if right:
        c.right(PANE_WIDTH - PAD, 0, right, size, TEXT_3)

    return 16


def item_row(c, y, name, note, index, width, x=0):
    if index % 2 == 1:
        c.rect(x, y - 2, width, ROW_HEIGHT, ROW_ALT)

    # The icon a tooltip hangs off, drawn because it is what a player reaches
    # for -- the same 16px square the loot list uses.
    c.rect(x + PAD, y, 14, 14, BUTTON)

    room = width - PAD - 20 - (measure(note, 10) + 10 if note else 0) - PAD
    c.text(x + PAD + 20, y + 1, name, 11, QUALITY)

    if note:
        c.right(x + width - PAD, y + 2, note, 10, TEXT_3)

    check("item '%s'" % name[:18], measure(name, 11), room)

    return y + ROW_HEIGHT


# ------------------------------------------------------------------ now

def draw_now(c, img, ox, oy):
    # The rail, with every difficulty in it.
    c.rect(0, 0, RAIL_WIDTH, PANEL_HEIGHT, WINDOW)

    y = 8
    c.text(PAD, y, "BOSS", 10, TEXT_3)
    c.right(RAIL_WIDTH - PAD, y, "KILLS", 10, TEXT_3)
    y += 18

    for index, (name, diff, kills) in enumerate(BOSSES_NOW):
        if index % 2 == 1:
            c.rect(0, y - 2, RAIL_WIDTH, ROW_HEIGHT, ROW_ALT)

        c.text(PAD, y, name, 11, TEXT_2)
        c.right(RAIL_WIDTH - 46, y, diff, 10, TEXT_3)
        c.right(RAIL_WIDTH - PAD, y, str(kills), 11, TEXT_2)
        y += ROW_HEIGHT

    y += 10
    c.text(PAD, y, "…and the same bosses again on", 9, TEXT_3)
    c.text(PAD, y + 12, "every other difficulty", 9, TEXT_3)

    # The pane: one list, behind a toggle.
    px = RAIL_WIDTH + GUTTER

    c.rect(px, 0, PANE_WIDTH, PANEL_HEIGHT, WINDOW)

    c.text(px + PAD, 8, "THE TWIN FANGS", 11, TEXT_1)
    c.text(px + PAD, 26, "The Venomous Abyss · Heroic · 3 kills", 10, TEXT_3)

    # The toggle that is the question.
    bw = int(measure("Not dropped", 11) + 28)
    c.rect(px + PANE_WIDTH - PAD - bw, 6, bw, 20, BUTTON)
    c.text(px + PANE_WIDTH - PAD - bw + 14, 9, "Not dropped", 11, ACCENT)

    y = 52
    c.text(px + PAD, y, "6 of 8 never dropped · 2 seen", 10, TEXT_3)
    y += 18

    for index, name in enumerate(NOT_DROPPED):
        if index % 2 == 1:
            c.rect(px, y - 2, PANE_WIDTH, ROW_HEIGHT, ROW_ALT)
        c.text(px + PAD, y + 1, name, 11, QUALITY)
        y += ROW_HEIGHT

    fy = PANEL_HEIGHT - 40
    for line in wrap("The Adventure Guide lists what a boss can drop for any "
                     "specialization, so this includes items nobody here can "
                     "use.", 9, PANE_WIDTH - PAD * 2):
        c.text(px + PAD, fy, line, 9, TEXT_3)
        fy += 12


# ------------------------------------------------------------- proposed

COLUMN = (PANE_WIDTH - GUTTER) // 2


def draw_after(c, img, ox, oy):
    # The rail: one difficulty at a time, so it is as long as the raid is.
    c.rect(0, 0, RAIL_WIDTH, PANEL_HEIGHT, WINDOW)

    y = 8
    c.text(PAD, y, "BOSS", 10, TEXT_3)
    c.right(RAIL_WIDTH - PAD, y, "KILLS", 10, TEXT_3)
    y += 18

    for index, (name, raid, kills) in enumerate(BOSSES):
        if index % 2 == 1:
            c.rect(0, y - 2, RAIL_WIDTH, ROW_HEIGHT, ROW_ALT)

        selected = name == "The Twin Fangs"

        if selected:
            c.rect(0, y - 2, 2, ROW_HEIGHT, ACCENT)

        c.text(PAD, y, name, 11, TEXT_1 if selected else TEXT_2)
        c.right(RAIL_WIDTH - PAD, y, str(kills), 11, TEXT_2)

        check("rail boss '%s'" % name[:16],
              measure(name, 11), RAIL_WIDTH - PAD * 2 - 24)

        y += ROW_HEIGHT

    y += 12
    c.text(PAD, y, "Heroic only · 7 bosses killed", 9, TEXT_3)

    # The pane: both lists at once.
    px = RAIL_WIDTH + GUTTER

    c.rect(px, 0, PANE_WIDTH, PANEL_HEIGHT, WINDOW)

    c.text(px + PAD, 8, "The Twin Fangs", 12, TEXT_1)
    c.text(px + PAD, 27, "The Venomous Abyss · Heroic · killed 3 times",
           10, TEXT_3)

    chip = int(measure("Heroic", 9) + 16)
    c.rect(px + PANE_WIDTH - PAD - chip, 6, chip, 16, BUTTON)
    c.text(px + PANE_WIDTH - PAD - chip + 8, 8, "Heroic", 9, TEXT_1)

    top = 54
    c.rect(px + PAD, top - 8, PANE_WIDTH - PAD * 2, 1, SEP)

    # Left: what it has given.
    left = C(img, ox + px, oy + top)
    left.text(PAD, 0, "IT HAS GIVEN YOU", 10, TEXT_3)
    left.right(COLUMN - PAD, 0, "2 of 8", 10, TEXT_3)

    ly = 18
    for index, (name, count) in enumerate(DROPPED):
        ly = item_row(left, ly, name, "×%d" % count if count > 1 else "",
                      index, COLUMN)

    # Right: what it has not.
    right = C(img, ox + px + COLUMN + GUTTER, oy + top)
    right.text(PAD, 0, "IT HAS NOT GIVEN YOU", 10, TEXT_3)
    right.right(COLUMN - PAD, 0, "6 of 8", 10, TEXT_3)

    ry = 18
    for index, name in enumerate(NOT_DROPPED):
        ry = item_row(right, ry, name, "", index, COLUMN)

    # The divider between them, so two lists read as two.
    c.rect(px + COLUMN + GUTTER // 2, top - 4, 1,
           PANEL_HEIGHT - top - 40, SEP)

    fy = PANEL_HEIGHT - 34
    c.rect(px + PAD, fy - 8, PANE_WIDTH - PAD * 2, 1, SEP)

    note = ("Both lists are Heroic only. \"Not given\" comes from the "
            "Adventure Guide, which lists every item a boss can drop for any "
            "class -- so some of these are for nobody in your raid.")

    for line in wrap(note, 9, PANE_WIDTH - PAD * 2):
        c.text(px + PAD, fy, line, 9, TEXT_3)
        fy += 12


# -------------------------------------------------------------------- page

MARGIN = 24
GAP = 30

WIDTH = RAIL_WIDTH + GUTTER + PANE_WIDTH

page_w = MARGIN * 2 + WIDTH
page_h = MARGIN * 2 + (PANEL_HEIGHT + 40) * 2

img = Image.new("RGB", (int(page_w * SCALE), int(page_h * SCALE)), GROUND)

top = C(img, 0, 0)
top.text(MARGIN, 8, "The Bosses tab at its real 868 × 398", 11, TEXT_3)

for index, (draw, note) in enumerate((
    (draw_now, "now — every difficulty in the rail, one list behind a toggle"),
    (draw_after, "proposed — one difficulty, both lists, tooltips on every "
                 "item"),
)):
    y = MARGIN + 14 + index * (PANEL_HEIGHT + 40)

    panel = C(img, MARGIN, y)
    draw(panel, img, MARGIN, y)

    label = C(img, MARGIN, y + PANEL_HEIGHT + 8)
    label.text(0, 0, note, 10, TEXT_3)

out = (__file__.replace("\\", "/").rsplit("/", 1)[0]
       + "/../screenshots/boss-loot.png")

img.save(out)

if problems:
    for problem in problems:
        sys.stderr.write(problem + "\n")
    sys.exit(1)

sys.stdout.write("wrote " + out + "\n")
