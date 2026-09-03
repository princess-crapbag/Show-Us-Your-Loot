# -*- coding: utf-8 -*-
"""The two screens the roster sync fix adds, drawn at their real size.

WHY THERE IS A DRAWING OF THIS. A roster that arrives from somebody else and
silently replaces what a screen was showing is the bug Aimee's officer hit --
they turned on "Share roster", their own empty team went out over the guild,
and everybody's roster went with it. The answer is that an arriving roster
asks first. That is a new dialog, and a new button beside "Clear shared", and
both have to be looked at before they are written.

LEFT is what a receiver sees the first time a roster arrives from a name they
have not accepted before. Real geometry: 460 wide, the same as
UI/ClearSeasonDialog.lua, because it is the same kind of thing -- something
that explains before it asks.

RIGHT is the bottom of the Raiders -> Raid team screen at its real width
(868 usable, less the 250 detail pane and the 12 gutter = 606), with the send
button beside the clear button and the caption that says who the roster
came from.

The names are Aimee's guild, and the seven on the team are the seven her
officer's screenshot showed.

Writes screenshots/roster-share.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, BUTTON, C, GROUND, ROW_ALT, SCALE, SEP, TEXT_1,
    TEXT_2, TEXT_3, WINDOW, check, measure, problems, wrap,
)

# Class colors, straight off the client's RAID_CLASS_COLORS.
CLASS = {
    "HUNTER": (170, 211, 114),
    "ROGUE": (255, 244, 104),
    "PRIEST": (255, 255, 255),
    "PALADIN": (244, 140, 186),
    "DEATHKNIGHT": (196, 30, 58),
    "DRUID": (255, 124, 10),
    "SHAMAN": (0, 112, 221),
    "WARLOCK": (135, 136, 238),
    "MAGE": (63, 199, 235),
    "MONK": (0, 255, 152),
}

# The seven her officer's screenshot showed under "Raid team".
TEAM = [
    ("Hawt", "ROGUE", "DPS"),
    ("Jtkurayami", "PRIEST", "Healer"),
    ("Looniemoonie", "PRIEST", "DPS"),
    ("Niwmn", "DEATHKNIGHT", "Tank"),
    ("Pringlescat", "DRUID", "DPS"),
    ("Rakahasa", "SHAMAN", "Healer"),
    ("Arcangila", "HUNTER", "DPS"),
]

SHARER = "Arcangila"

# ------------------------------------------------------------------ left

DIALOG_W = 460
DIALOG_PAD = 20
DIALOG_CONTENT = DIALOG_W - DIALOG_PAD * 2

TITLE = SHARER + " sent you a raid team"

BODY = [
    "Seven people, with the roles they were given. Nothing has changed "
    "yet -- this is a question, not a notice.",
    "Say yes and their team shows on your roster beside anyone you have "
    "ticked yourself. It never touches your own ticks, and Clear shared "
    "removes it again whenever you like.",
    "Say yes once and their later changes arrive quietly. Nobody else can "
    "replace it or empty it -- anyone else who starts sharing asks you "
    "here, the same way.",
]

ACCEPT = "Use their roster"
DECLINE = "No thanks"

# ----------------------------------------------------------------- right

PANEL_W = 868 - 250 - 12          # UI/RaidersPanel.lua: less detail, gutter
ROW_H = 22
COL_TICK, COL_NAME, COL_ROLE, COL_NIGHTS, COL_NOTE = 4, 26, 190, 280, 340

STRIP = [
    ("Pringlescat", "DRUID", "DPS", "2 of 3", "Raider", True),
    ("Rakahasa", "SHAMAN", "Healer", "3 of 3", "Raider", True),
    ("Arcangila", "HUNTER", "DPS", "3 of 3", "Guild Master", True),
    ("Camcar", "HUNTER", "--", "2 of 3", "Initiate", False),
    ("Kotastrophe", "PALADIN", "--", "2 of 3", "Alt", False),
]

CAPTION = ("15 people on the roster  ·  7 marked as raiding  ·  "
           "shared by " + SHARER)

SEND = "Send my roster"
CLEAR = "Clear shared"

BUTTON_H = 18
BUTTON_PAD = 14                   # room either side of a label


def button(c, right_edge, y, label, width=None):
    """Draws right-aligned and returns its left edge, so the next one can sit
    beside it. Width is measured off the label rather than guessed -- a button
    too wide for its row is a defect the same as one too narrow."""
    w = width or int(round(measure(label, 11) + BUTTON_PAD * 2))
    x = right_edge - w

    c.rect(x, y, w, BUTTON_H, BUTTON)
    c.text(x + (w - measure(label, 11)) / 2, y + 3, label, 11, TEXT_1)
    check("button '%s'" % label, measure(label, 11), w - 8)

    return x


def draw_dialog(c):
    y = 16

    c.text(DIALOG_PAD, y, TITLE, 15, TEXT_1)
    check("dialog title", measure(TITLE, 15), DIALOG_CONTENT)
    y += 26

    c.rect(DIALOG_PAD, y, DIALOG_CONTENT, 1, SEP)
    y += 12

    for para in BODY:
        for line in wrap(para, 11, DIALOG_CONTENT):
            c.text(DIALOG_PAD, y, line, 11, TEXT_2)
            y += 15
        y += 8

    y += 2
    c.text(DIALOG_PAD, y, "THEIR TEAM", 10, TEXT_3)
    y += 16

    half = DIALOG_CONTENT / 2

    for index, (name, cls, role) in enumerate(TEAM):
        col = index % 2
        line = index // 2
        x = DIALOG_PAD + col * half
        ry = y + line * 18

        c.text(x, ry, name, 11, CLASS[cls])
        c.right(x + half - 16, ry, role, 11, TEXT_3)
        check("team name '%s'" % name,
              measure(name, 11) + measure(role, 11) + 12, half - 16)

    y += ((len(TEAM) + 1) // 2) * 18 + 14

    c.rect(DIALOG_PAD, y, DIALOG_CONTENT, 1, SEP)
    y += 14

    right = DIALOG_W - DIALOG_PAD
    left = button(c, right, y, DECLINE)
    button(c, left - 8, y, ACCEPT)

    return y + BUTTON_H + DIALOG_PAD


def draw_strip(c):
    y = 0

    c.text(COL_NAME, y, "RAIDER", 10, TEXT_3)
    c.text(COL_ROLE, y, "ROLE", 10, TEXT_3)
    c.text(COL_NIGHTS, y, "RAID NIGHTS", 10, TEXT_3)
    y += 18

    for index, (name, cls, role, nights, note, on) in enumerate(STRIP):
        if index % 2 == 1:
            c.rect(0, y, PANEL_W, ROW_H, ROW_ALT)

        c.box(COL_TICK, y + 4, on)
        c.text(COL_NAME, y + 5, name, 12, CLASS[cls])
        c.text(COL_ROLE, y + 5, role, 12, TEXT_2 if role != "--" else TEXT_3)
        c.text(COL_NIGHTS, y + 5, nights, 12, TEXT_2)
        c.text(COL_NOTE, y + 5, note, 12, TEXT_3)

        y += ROW_H

    y += 12

    c.text(2, y, CAPTION, 11, TEXT_3)

    # The two buttons, bottom right, the way UI/RaidersRoster.lua anchors
    # "Clear shared" today -- BOTTOMRIGHT -2, 1.
    left = button(c, PANEL_W - 2, y - 3, CLEAR, 104)
    left = button(c, left - 8, y - 3, SEND)

    check("caption beside the buttons", measure(CAPTION, 11), left - 10)

    y += 34

    c.text(2, y, "And what the sender is told, in chat:", 11, TEXT_3)
    y += 18
    c.text(2, y, "Show Us Your Loot:", 11, ACCENT)
    c.text(2 + measure("Show Us Your Loot: ", 11), y,
           "Sent your raid team of 7 to the guild.", 11, TEXT_2)

    return y + 20


# ------------------------------------------------------------------ page

GAP = 40
MARGIN = 24

# Measured rather than guessed, the same rule the buttons follow: draw both
# halves onto a scratch canvas, keep the heights they actually came to, and
# size the page off those. A picture with a field of empty ground under it
# reads as a screen with a field of empty ground in it.
scratch = Image.new("RGB", (2400, 2400), GROUND)
DIALOG_H = int(draw_dialog(C(scratch, 0, 0))) + 4
STRIP_H = int(draw_strip(C(scratch, 800, 0))) + 4
BODY_H = max(DIALOG_H, STRIP_H + 16)

problems.clear()

page_w = MARGIN * 2 + DIALOG_W + GAP + PANEL_W
page_h = MARGIN * 2 + BODY_H + 48

img = Image.new("RGB", (int(page_w * SCALE), int(page_h * SCALE)), GROUND)

top = C(img, 0, 0)
top.text(MARGIN, 10, "What a receiver sees, and where the sender presses",
         11, TEXT_3)

# Left: the dialog, on its own window ground.
dialog = C(img, MARGIN, MARGIN + 14)
dialog.rect(0, 0, DIALOG_W, BODY_H, WINDOW)
dialog.rect(0, 0, 3, BODY_H, ACCENT_DIM)
draw_dialog(dialog)

# Right: the bottom of the roster screen.
strip_x = MARGIN + DIALOG_W + GAP
strip = C(img, strip_x + 8, MARGIN + 14 + 8)
strip.rect(-8, -8, PANEL_W + 16, BODY_H, WINDOW)
draw_strip(strip)

label = C(img, 0, 0)
label.text(MARGIN, MARGIN + BODY_H + 26,
           "left: the prompt, 460 wide, the same as the erase dialog   "
           "·   right: the real 606-wide roster strip", 10, TEXT_3)

out = (__file__.replace("\\", "/").rsplit("/", 1)[0]
       + "/../screenshots/roster-share.png")

img.save(out)

if problems:
    for problem in problems:
        sys.stderr.write(problem + "\n")
    sys.exit(1)

sys.stdout.write("wrote " + out + "\n")
