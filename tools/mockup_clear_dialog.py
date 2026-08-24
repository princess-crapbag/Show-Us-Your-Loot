# -*- coding: utf-8 -*-
"""The erase-a-season dialog, drawn at its real size.

WHY THERE IS A DRAWING OF THIS AT ALL. /syl clear is the only command in the
addon that destroys a season's worth of recording, and it once emptied one on
a single click from the minimap menu -- Core/CommandList.lua:155-165 keeps
that record. Aimee, asked what the Tools tab should do with it:

    "dont make it a normal button. or make it harder to do. make sure there
    is an explanation as to why someone should use this button and what will
    happen if they do. maybe have a danger image near it. or it can just be
    a slash command. but dont make it a normal button and give an explanation
    of what it does so they youngest user can understand."

So this is the answer to that, drawn rather than described. Four guards, and
the picture shows all four:

  1. It is not in the Tools list. It sits under its own warning rule at the
     bottom of the tab, beside the client's alert icon.
  2. This dialog explains before it asks, in short words, with the real
     counts, saying what goes, what stays, and what to do instead.
  3. The season's NAME has to be typed. Not "confirm" -- that can be typed
     without reading. The name cannot.
  4. Erase is dead until the name matches, and the line under the box says
     which of the two states it is in.

Both states are drawn side by side, because the locked one is the state
anybody will actually meet and it has to look deliberate rather than broken.

Writes screenshots/clear-season-dialog.png.
Left panel is the real UI/ClearSeasonDialog.lua geometry: 460 wide, 420 tall.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, C, GROUND, SCALE, TEXT_1, TEXT_2, TEXT_3, WARNING, WINDOW,
    BUTTON, SEP, ROW_ALT, measure, wrap,
)

WIDTH = 460
HEIGHT = 420
PAD = 20

SEASON = "Midnight Season 2"

BODY = [
    "This erases everything this addon has written down for "
    + SEASON + ".",
    "43 group-loot drops and 12 chat items go. Who is due, who turned up, "
    "and what each boss has given all go back to nothing, because they are "
    "all worked out from those records.",
    "It cannot be undone. There is no backup and no undo button.",
    "Use this only if the addon wrote down a lot you did not want -- a test "
    "run, somebody else's raid, or loot from before you set your filters.",
    "If this season is simply over, press Archive instead. That keeps every "
    "record and starts a fresh season next to it.",
]


def draw(img, ox, oy, unlocked):
    c = C(img, ox, oy)

    c.rect(0, 0, WIDTH, HEIGHT, WINDOW)

    # The alert icon, drawn as the 32x32 square it occupies.
    c.rect(16, 16, 32, 32, WARNING)

    c.text(58, 22, "ERASE THIS SEASON", 15, WARNING)
    c.right(WIDTH - 16, 20, "x", 12, TEXT_3)

    c.rect(16, 56, WIDTH - 32, 1, WARNING)

    y = 68

    for paragraph in BODY:
        for line in wrap(paragraph, 11, WIDTH - PAD * 2):
            c.text(PAD, y, line, 11, TEXT_2)
            y += 14
        y += 8

    # The prompt, the box, and the line that says whether it is locked.
    prompt = "To erase it, type its name here exactly:  " + SEASON
    c.text(PAD, 274, prompt, 11, TEXT_1)

    # THE BOX IS EDGED IN THE WARNING COLOR, not the ordinary border -- it is
    # the only field in the addon that is a guard rather than an input.
    c.rect(PAD, 308, WIDTH - PAD * 2, 26, WARNING)
    c.rect(PAD + 1, 309, WIDTH - PAD * 2 - 2, 24, WINDOW)

    typed = SEASON if unlocked else "Midnight Sea"
    c.text(PAD + 7, 314, typed, 11, TEXT_1)

    if not unlocked:
        # The caret, so the locked panel reads as half-typed rather than as a
        # field nobody has touched.
        c.rect(PAD + 9 + measure(typed, 11), 313, 1, 16, TEXT_3)

    c.text(PAD + 1, 340,
           "The name matches. Erase is unlocked." if unlocked
           else "Erase stays locked until the name matches.",
           10, WARNING if unlocked else TEXT_3)

    # ERASE IS ON THE LEFT AND ARCHIVE IS ON THE RIGHT, where the button
    # somebody presses without reading lives. Nearly everybody who reaches
    # this screen wanted Archive and not the other one.
    c.rect(PAD, HEIGHT - 44, 150, 26, BUTTON if unlocked else ROW_ALT)
    c.text(PAD + 75 - measure("Erase", 11) / 2, HEIGHT - 39, "Erase", 11,
           WARNING if unlocked else TEXT_3)

    c.rect(WIDTH - PAD - 150, HEIGHT - 44, 150, 26, BUTTON)
    c.text(WIDTH - PAD - 75 - measure("Archive instead", 11) / 2,
           HEIGHT - 39, "Archive instead", 11, TEXT_1)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    MARGIN = 40
    GAP = 40
    TOP = 104

    W = MARGIN * 2 + WIDTH * 2 + GAP
    H = TOP + HEIGHT + 150

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    def over(rgba, under=GROUND):
        r, g, b, a = rgba
        return tuple(int(round((ch * 255) * a + u * (1 - a)))
                     for ch, u in zip((r, g, b), under))

    G1 = over((0.97, 0.96, 1.00, 1))
    G3 = over((0.64, 0.61, 0.78, 1))
    GA = over((0.55, 0.85, 1.00, 1))

    page.text(MARGIN, 28, "Erasing a season, and the four things in the way",
              15, G1)
    page.text(MARGIN, 56,
              "Reached from the Tools tab's danger block, not from the "
              "command list. Real size: 460 x 420.", 10, G3)

    page.text(MARGIN, TOP - 20, "1  As anybody will meet it", 11, GA)
    page.text(MARGIN + WIDTH + GAP, TOP - 20,
              "2  Once the name has been typed", 11, GA)

    draw(img, MARGIN, TOP, False)
    draw(img, MARGIN + WIDTH + GAP, TOP, True)

    y = TOP + HEIGHT + 24

    for line in [
        "Guard 1 is on the tab: this is not a row in the Tools list. It sits "
        "under its own warning rule with the client's alert icon.",
        "Guard 2 is this screen: what goes, what stays, and what to do "
        "instead, in the shortest words that carry it.",
        "Guard 3 is the name. /syl clear takes the word 'confirm', which can "
        "be typed without reading. A season's name cannot -- you have to look "
        "at which one you are about to destroy.",
        "Guard 4 is the dead button, and the line under the box that says so. "
        "A control that looks pressable and is not reads as broken; one that "
        "says why it is not reads as a lock.",
        "Archive is offered first and is the button under the hand that "
        "presses without reading. It keeps every record and starts a fresh "
        "season beside it.",
        "The command still works exactly as it did: /syl clear confirm. This "
        "dialog runs that, rather than emptying the tables itself, so the "
        "account-wide recovery stamp cannot be forgotten in one of two places.",
    ]:
        for part in wrap(line, 10, W - MARGIN * 2):
            page.text(MARGIN, y, part, 10, G3)
            y += 14
        y += 8

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\clear-season-dialog.png")
    img.save(out)

    print("wrote clear-season-dialog.png", img.size)
