# -*- coding: utf-8 -*-
"""Two dashboard tiles, drawn at their real size, now and proposed.

Aimee, of the loot feed: "could this part of the dashboard feed be better? it
only ever shows me because im masterlooter. maybe it doesnt show names?"

The names are not the problem and hiding them would throw away the fix. The
tile reads drop.winnerName, which under a loot council is the master looter on
every single item -- and it has never once read the credit she types
afterwards. Her own database for 09/03 holds the right answer on all five
drops: Hawt, Pringlescat, Rakahasa, Pringlescat, Arcangila. The tile has the
data and is not looking at it. Core/DropRules.CreditedKey is the same choke
point the board and the due list already go through.

The response is wrong too, for the same reason: three of the five are recorded
Greed and credited Need, so "11 went home with nothing" is counted off the
uncorrected state. Corrected it is 8.

And of the tier tile: "right now it says 22 of 23 killed. there are 8 bosses
in one raid and 1 boss in the other, plus there is LFR, Normal, Heroic,
Mythic ... id like to be able to choose which difficulty that section shows."

22 of 23 is every difficulty added together -- 8 Normal plus 6 Heroic plus 6
LFR in The Venomous Abyss, 1 Normal and 1 Heroic in The Tidebound Grotto, and
The Coiled Altar unkilled. The tile's own note in Core/Dashboard.lua claims
"kills per boss, kept separate by difficulty", which is exactly what it does
not do.

EVERY NUMBER HERE IS COMPUTED FROM HER SAVED VARIABLES, not typed in. The
first-kill dates come from raids[*].encounters, which already carries killed,
name, difficultyID and a timestamp per pull -- so nothing new has to be
tracked for the difficulty she raids. Weeks count from Tuesday 08/18, which
is week 1 by her own reckoning.

Writes screenshots/dashboard-tiles.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, BUTTON, C, GROUND, ROW_ALT, SCALE, SEP, TEXT_1,
    TEXT_2, TEXT_3, WARNING, WINDOW, check, measure, problems,
)

# (900 - 32 - 10 * 2) / 3, and the tall ratio, from UI/DashboardTab.lua.
TILE_W = 283
TILE_H = 185
PAD = 10
INNER = TILE_W - PAD * 2

ROW = 17
KILL_ROW = 17

CLASS = {
    "ROGUE": (255, 244, 104),
    "DRUID": (255, 124, 10),
    "SHAMAN": (0, 112, 221),
    "HUNTER": (170, 211, 114),
}

# 09/03/2026, off her own database. The winner is Arcangila on all five
# because she holds the loot; the credited name is what she typed afterwards.
DROPS = [
    ("Arcangila", "HUNTER", "Hawt", "ROGUE", "Venomcured Relic", "Need"),
    ("Arcangila", "HUNTER", "Pringlescat", "DRUID",
     "Idol of the Howling Nexus", "Greed"),
    ("Arcangila", "HUNTER", "Rakahasa", "SHAMAN",
     "Ophidian Fangmail", "Need"),
    ("Arcangila", "HUNTER", "Pringlescat", "DRUID",
     "Vexhul's Everflowing Gland", "Need"),
    ("Arcangila", "HUNTER", "Arcangila", "HUNTER",
     "Ophidian Fangmail", "Need"),
]

RAIDS = [("The Venomous Abyss", 6, 8), ("The Tidebound Grotto", 1, 1)]

# Heroic first kills, computed from raids[*].encounters.
# Dates, weeks and pull counts all computed from her raid nights.
FIRST_KILLS = [
    ("The Twin Fangs", "09/03", 3, 5),
    ("Sszorak", "09/03", 3, 15),
    ("Vashnik the Malignant", "09/01", 3, 2),
    ("Entombed Sentinels", "09/01", 3, 6),
    ("Nymrissa Wavecaller", "08/27", 2, 6),
    ("The Lost Explorers", "08/27", 2, 16),
    ("Nek'zali the Soulcoiler", "08/25", 2, 5),
]


def head(c, title, link, chip=None, headline=None):
    c.text(PAD, 8, title, 9, TEXT_3)

    x = TILE_W - PAD
    c.right(x, 8, link + " ›", 9, ACCENT)
    x -= measure(link + " ›", 9) + 10

    if chip:
        width = measure(chip, 9) + 16
        c.rect(x - width, 5, width, 15, BUTTON)
        c.text(x - width + 8, 7, chip, 9, TEXT_1)
        x -= width + 8

    if headline:
        c.right(x, 8, headline, 9, TEXT_2)
        check("tier header line",
              measure(title, 9) + measure(headline, 9)
              + measure(chip or "", 9) + 16 + measure(link + " ›", 9) + 24,
              INNER)

    c.rect(PAD, 24, INNER, 1, SEP)

    return 30


def caption(c, text, color=TEXT_3):
    y = TILE_H - 24
    c.rect(PAD, y - 6, INNER, 1, SEP)
    c.text(PAD, y, text, 9, color)
    check("caption", measure(text, 9), INNER)


# ---------------------------------------------------------------- the feed

NAME_W = 66


def feed_row(c, y, index, name, klass, item, response=None):
    if index % 2 == 1:
        c.rect(PAD - 2, y - 2, INNER + 4, ROW, ROW_ALT)

    c.text(PAD, y, name, 11, CLASS[klass])

    room = INNER - NAME_W - (34 if response else 0)
    c.text(PAD + NAME_W, y, item, 11, TEXT_2)
    check("feed item '%s'" % item[:18], measure(item, 11), room)

    if response:
        c.right(TILE_W - PAD, y + 1, response, 9,
                TEXT_2 if response == "Need" else TEXT_3)

    return y + ROW


def draw_feed_now(c):
    y = head(c, "LAST RAID NIGHT", "Feed")

    for index, (winner, wclass, _, _, item, _) in enumerate(DROPS):
        y = feed_row(c, y, index, winner, wclass, item)

    caption(c, "5 drops · 09/03/2026 · 11 went home with nothing")


def draw_feed_after(c):
    y = head(c, "LAST RAID NIGHT", "Feed")

    for index, (_, _, credited, cclass, item, _) in enumerate(DROPS):
        y = feed_row(c, y, index, credited, cclass, item)

    caption(c, "5 drops · 09/03/2026 · 8 went home with nothing")


# ---------------------------------------------------------------- the tier

def draw_tier_now(c):
    y = head(c, "TIER PROGRESS", "Bosses")

    c.text(PAD, y, "22", 15, TEXT_1)
    c.text(PAD + measure("22", 15) + 6, y + 4, "of 23 killed", 11, TEXT_3)
    y += 26

    c.text(PAD, y, "The Coiled Altar", 11, TEXT_2)
    c.right(TILE_W - PAD, y, "9 pulls, no kill", 11, WARNING)

    caption(c, "135 drops recorded across 23 bosses.")


def draw_tier_after(c):
    # Her own edit: both raids and the difficulty up on the header line.
    y = head(c, "TIER PROGRESS", "Bosses", chip="Heroic",
             headline="VA 6/8  TG 1/1")

    c.text(PAD, y, "FIRST KILLED", 9, TEXT_3)
    c.right(TILE_W - PAD, y, "newest first", 9, TEXT_3)
    y += ROW

    # Only what fits above the caption rule. A row drawn through the rule is
    # the defect this drawing existed to catch, and it caught it.
    floor = TILE_H - 30
    shown = 0

    for name, date, week, pulls in FIRST_KILLS:
        if y + KILL_ROW > floor:
            break

        c.text(PAD, y, name, 9, TEXT_2)

        stamp = "%s · wk %d" % (date, week)
        pull_text = "%d pulls" % pulls

        c.right(TILE_W - PAD, y, pull_text, 9, TEXT_3)
        c.right(TILE_W - PAD - measure(pull_text, 9) - 8, y, stamp, 9, TEXT_3)

        check("kill line '%s'" % name[:16],
              measure(name, 9) + measure(stamp, 9)
              + measure(pull_text, 9) + 16, INNER)

        y += KILL_ROW
        shown += 1

    left = len(FIRST_KILLS) - shown

    if left > 0:
        caption(c, "%d more on Bosses · next: The Coiled Altar, 9 pulls"
                % left, WARNING)
    else:
        caption(c, "next: The Coiled Altar · 9 pulls, no kill", WARNING)


# -------------------------------------------------------------------- page

GAP = 26
MARGIN = 24

PANELS = [
    (draw_feed_now, "now — the master looter, five times"),
    (draw_feed_after, "proposed — who you credited, and what they asked"),
    (draw_tier_now, "now — every difficulty added together"),
    (draw_tier_after, "proposed — one difficulty, with first kills and weeks"),
]

page_w = MARGIN * 2 + TILE_W * 2 + GAP
page_h = MARGIN * 2 + (TILE_H + 34) * 2 + 20

img = Image.new("RGB", (int(page_w * SCALE), int(page_h * SCALE)), GROUND)

top = C(img, 0, 0)
top.text(MARGIN, 8, "Two dashboard tiles at their real 283 × 185, rows equalised", 11, TEXT_3)

for index, (draw, note) in enumerate(PANELS):
    column = index % 2
    line = index // 2

    x = MARGIN + column * (TILE_W + GAP)
    y = MARGIN + 14 + line * (TILE_H + 34)

    tile = C(img, x, y)
    tile.rect(0, 0, TILE_W, TILE_H, WINDOW)
    draw(tile)

    label = C(img, x, y + TILE_H + 8)
    label.text(0, 0, note, 10, TEXT_3)

out = (__file__.replace("\\", "/").rsplit("/", 1)[0]
       + "/../screenshots/dashboard-tiles.png")

img.save(out)

if problems:
    for problem in problems:
        sys.stderr.write(problem + "\n")
    sys.exit(1)

sys.stdout.write("wrote " + out + "\n")
