# -*- coding: utf-8 -*-
"""Two changes drawn before they are built: the detail pane, and sending.

LEFT AND MIDDLE are the Raiders detail pane at its real size -- 250 wide,
398 tall, the geometry in UI/RaidersDetailParts.lua. Left is what Aimee has
now; middle is the proposal.

Aimee: "i love how i can see the item and the track level but i can only see
5 items. so for rakahasa, it shows 5 items 'and 6 more' i want to be able to
see what those 6 more are, probably all season long. the info below the
characters name that breaks down the needs and greeds and points could maybe
go at the top ... so that the individual loot history can scroll"

The cap is not a count, it is the floor: RaidersDetailParts stops laying out
cards when the next one would cross HEIGHT minus RESERVED, and RESERVED is 56
pixels held back for the points breakdown and the ranking sentence pinned
underneath. So the footer costs the list six items, and the list cannot
scroll because nothing under it moves.

Moving the breakdown above the list buys those pixels back AND frees the
bottom edge, which is what lets the rest scroll. The stat row keeps its place:
6 RAID NIGHTS / 8 ITEMS / 640 POINTS is the headline and belongs at the top.

RIGHT is the send chooser. Aimee: "lets change this to have a button to share
it with individual players, all raid roster players (and their alts), or all
guild. let it be a button we press to send it rather than always happening on
login."

Rakahasa's numbers, the five items her screenshot showed and the six it did
not, are hers.

Writes screenshots/detail-scroll.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, BUTTON, C, GROUND, ROW_ALT, SCALE, SEP, TEXT_1,
    TEXT_2, TEXT_3, WINDOW, check, measure, problems, wrap,
)

PANE_W = 250
PANE_H = 398
PAD = 10

CLASS = {"SHAMAN": (0, 112, 221)}

WHO = "Rakahasa"
SHARE = "106.7"
STATS = [("6", "RAID NIGHTS"), ("8", "ITEMS"), ("640", "POINTS")]

MOG_LINE = "3 Mog wins worth nothing"
BREAKDOWN = "Need 6 × 100 + Greed 2 × 20 = 640"
RANKING = ("Ranked on points per night, lowest first — turning up more "
           "makes you more due, not less.")

# The five her screenshot showed, then the six it would not.
NIGHTS = [
    ("SEP 03", "100 points", [
        ("Ophidian Fangmail", "Need · The Twin Fangs", "H"),
    ]),
    ("SEP 01", "220 points", [
        ("Sentinel's Vitriolic Chain", "Need · Entombed Sentinels", "H"),
        ("Malevolent Spiritcudgel", "Greed · The Lost Explorers", "H"),
        ("Forgotten Grotto Girdle", "Mog · Nymrissa Wavecaller", "H"),
        ("Wavecaller's Seastone", "Need · Nymrissa Wavecaller", "H"),
    ]),
    ("AUG 27", "120 points", [
        ("Tideguard's Coral Band", "Need · Nymrissa Wavecaller", "M"),
        ("Abyssal Drifter's Cord", "Greed · The Twin Fangs", "H"),
    ]),
    ("AUG 25", "200 points", [
        ("Fangmarked Shoulderguards", "Need · The Twin Fangs", "H"),
        ("Silt-Choked Waders", "Mog · Entombed Sentinels", "H"),
    ]),
    ("AUG 20", "0 points", [
        ("Drowned Sentinel's Cowl", "Mog · Entombed Sentinels", "H"),
        ("Reefstalker's Grips", "Need · The Lost Explorers", "N"),
    ]),
]

CARD_H = 19
NIGHT_HEAD = 13
NIGHT_RULE = 6
NIGHT_GAP = 6
STAT_TOP = 32
STAT_HEIGHT = 36

BUTTON_H = 18
BUTTON_PAD = 14


def button(c, right_edge, y, label, width=None):
    w = width or int(round(measure(label, 11) + BUTTON_PAD * 2))
    x = right_edge - w
    c.rect(x, y, w, BUTTON_H, BUTTON)
    c.text(x + (w - measure(label, 11)) / 2, y + 3, label, 11, TEXT_1)
    check("button '%s'" % label, measure(label, 11), w - 8)
    return x


def header(c):
    c.text(PAD, 10, WHO, 12, CLASS["SHAMAN"])
    c.right(PANE_W - PAD, 10, SHARE, 12, TEXT_1)

    y = STAT_TOP
    c.rect(PAD, y, PANE_W - PAD * 2, STAT_HEIGHT, ROW_ALT)

    for index, (value, label) in enumerate(STATS):
        x = PAD + 8 + index * 76
        c.text(x, y + 4, value, 12, TEXT_1)
        c.text(x, y + 20, label, 9, TEXT_3)
        check("stat label", measure(label, 9), 74)

    return y + STAT_HEIGHT + 8


def card(c, y, name, meta, letter):
    c.rect(PAD, y, 2, CARD_H - 3, ACCENT_DIM)
    c.rect(PAD + 6, y + 1, 16, 16, BUTTON)

    room = PANE_W - PAD - 30 - 16
    c.text(PAD + 28, y, name, 9, TEXT_2)
    c.text(PAD + 28, y + 9, meta, 9, TEXT_3)
    c.right(PANE_W - PAD, y + 3, letter, 12, TEXT_3)

    check("card name '%s'" % name[:16], measure(name, 9), room)
    check("card meta '%s'" % meta[:16], measure(meta, 9), room)

    return y + CARD_H


def night_heading(c, y, label, points):
    c.text(PAD, y, label, 9, TEXT_3)
    c.right(PANE_W - PAD, y, points, 9, TEXT_3)
    c.rect(PAD, y + NIGHT_HEAD, PANE_W - PAD * 2, 1, SEP)
    return y + NIGHT_HEAD + NIGHT_RULE


# ------------------------------------------------------------------ before

def draw_before(c):
    y = header(c)

    c.text(PAD, y, MOG_LINE, 9, TEXT_3)
    y += 16

    # RESERVED = 56 held back at the bottom, which is what stops the list.
    floor = PANE_H - 56
    shown = 0
    left = 0

    for label, points, items in NIGHTS:
        if y + NIGHT_HEAD + NIGHT_RULE + CARD_H > floor:
            left += len(items)
            continue

        if left:
            left += len(items)
            continue

        y = night_heading(c, y, label, points)

        for name, meta, letter in items:
            if y + CARD_H > floor:
                left += 1
                continue

            y = card(c, y, name, meta, letter)
            shown += 1

        y += NIGHT_GAP

    c.text(PAD, y, "and %d more" % left, 9, TEXT_3)

    # The footer that costs the six.
    fy = PANE_H - 52
    c.rect(PAD, fy, PANE_W - PAD * 2, 1, SEP)
    c.text(PAD, fy + 6, BREAKDOWN, 9, TEXT_2)

    ly = fy + 18
    for line in wrap(RANKING, 9, PANE_W - PAD * 2):
        c.text(PAD, ly, line, 9, TEXT_3)
        ly += 11

    return shown, left


# ------------------------------------------------------------------- after

def draw_after(c):
    y = header(c)

    # The breakdown, moved up under the stat row where it explains the number
    # directly above it rather than the list above THAT.
    c.text(PAD, y, BREAKDOWN, 9, TEXT_2)
    y += 12
    c.text(PAD, y, MOG_LINE, 9, TEXT_3)
    y += 14
    c.rect(PAD, y, PANE_W - PAD * 2, 1, SEP)
    y += 8

    top = y
    shown = 0

    for label, points, items in NIGHTS:
        if y + NIGHT_HEAD + NIGHT_RULE + CARD_H > PANE_H - 4:
            break

        y = night_heading(c, y, label, points)

        for name, meta, letter in items:
            if y + CARD_H > PANE_H - 4:
                break
            y = card(c, y, name, meta, letter)
            shown += 1

        y += NIGHT_GAP

    # The scrollbar, drawn because it is the whole point: the list runs to the
    # bottom edge now and keeps going.
    track_x = PANE_W - 4
    c.rect(track_x, top, 2, PANE_H - top - 4, ROW_ALT)
    c.rect(track_x, top, 2, int((PANE_H - top - 4) * 0.62), ACCENT_DIM)

    return shown


# ------------------------------------------------------------------- share

SHARE_W = 300
SHARE_BODY = ("Nothing is sent unless you press one of these. Your roster no "
              "longer goes out on its own at login or when you tick somebody.")

CHOICES = [
    ("One player", "Nychar", "pick a name — 8 online"),
    ("The raid team", "11 people", "and every alt they have"),
    ("The whole guild", "15 people", "everyone with the addon"),
]


def draw_share(c):
    c.text(PAD + 6, 12, "Send my raid team", 15, TEXT_1)
    y = 38
    c.rect(PAD + 6, y, SHARE_W - (PAD + 6) * 2, 1, SEP)
    y += 12

    for line in wrap(SHARE_BODY, 11, SHARE_W - (PAD + 6) * 2):
        c.text(PAD + 6, y, line, 11, TEXT_2)
        y += 15

    y += 10

    for label, value, note in CHOICES:
        c.rect(PAD + 6, y, SHARE_W - (PAD + 6) * 2, 34, ROW_ALT)
        c.text(PAD + 14, y + 4, label, 11, TEXT_1)
        c.right(SHARE_W - PAD - 14, y + 4, value, 11, ACCENT)
        c.text(PAD + 14, y + 19, note, 9, TEXT_3)

        check("choice '%s'" % label,
              measure(label, 11) + measure(value, 11) + 20,
              SHARE_W - (PAD + 6) * 2 - 16)

        y += 40

    y += 2
    c.rect(PAD + 6, y, SHARE_W - (PAD + 6) * 2, 1, SEP)
    y += 12

    button(c, SHARE_W - PAD - 6, y, "Close")

    return y + BUTTON_H + 14


# -------------------------------------------------------------------- page

GAP = 34
MARGIN = 24

scratch = Image.new("RGB", (1600, 1600), GROUND)
before_shown, before_left = draw_before(C(scratch, 0, 0))
after_shown = draw_after(C(scratch, 400, 0))
SHARE_H = int(draw_share(C(scratch, 800, 0)))
problems.clear()

page_w = MARGIN * 2 + PANE_W * 2 + SHARE_W + GAP * 2
page_h = MARGIN * 2 + PANE_H + 60

img = Image.new("RGB", (int(page_w * SCALE), int(page_h * SCALE)), GROUND)

top = C(img, 0, 0)
top.text(MARGIN, 10, "The detail pane, and where sending moves to", 11, TEXT_3)

panes = [
    (0, draw_before, PANE_W, PANE_H,
     "now — %d items, %d hidden" % (before_shown, before_left)),
    (PANE_W + GAP, draw_after, PANE_W, PANE_H,
     "proposed — %d before scrolling, all 11 reachable" % after_shown),
    ((PANE_W + GAP) * 2, draw_share, SHARE_W, SHARE_H,
     "pressing Send my roster"),
]

for x, draw, width, height, caption in panes:
    pane = C(img, MARGIN + x, MARGIN + 14)
    pane.rect(0, 0, width, height, WINDOW)
    draw(pane)

    label = C(img, MARGIN + x, MARGIN + 14 + height + 12)
    label.text(0, 0, caption, 10, TEXT_3)

out = (__file__.replace("\\", "/").rsplit("/", 1)[0]
       + "/../screenshots/detail-scroll.png")

img.save(out)

if problems:
    for problem in problems:
        sys.stderr.write(problem + "\n")
    sys.exit(1)

sys.stdout.write("wrote " + out + "\n")
