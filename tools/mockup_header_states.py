# -*- coding: utf-8 -*-
"""One column header, doing two jobs.

Aimee: "all the sort by filters in the columns, do they allow me to not only
sort by but also filter by?"

Yes, and the sorting half already exists -- UI/Columns.lua marks only the
tickbox and the # column `sortable = false`, so PLAYER, ITEM, TYPE, WHERE and
DATE have been clickable-to-sort since the header was written. What the caret
adds is the filter.

TWO HIT TARGETS IN ONE HEADER, and the split has to be obvious or it is worse
than either alone:

  THE NAME SORTS. That is what it does today and clicking it must not start
  doing something else.

  THE CARET FILTERS. It sits in the gap after the name, so it costs the
  column no width -- but a caret is eight pixels wide, and an eight pixel
  target is a target people miss. Its button is 18 wide and the full header
  height, reaching into the gap that is already there.

The two states are drawn on different channels on purpose. Sorted is an arrow
AFTER the caret; filtered is the NAME going accent. So a column that is both
sorted and filtered says both at once rather than one winning.

Writes screenshots/header-states.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, C, GROUND, SCALE, TEXT_1, TEXT_2, TEXT_3, WINDOW, ROW_ALT, SEP,
    over, measure, wrap,
)

HEADER_HEIGHT = 22
CELL = 150


def header(c, x, y, label, sorted_=None, filtered=False, targets=False):
    """One header cell. `sorted_` is None, 'up' or 'down'."""
    color = ACCENT if filtered else TEXT_3

    c.text(x, y + 5, label, 10, color)

    nameWidth = measure(label, 10)
    caretX = x + nameWidth + 5

    c.text(caretX, y + 5, "v", 10, color)

    if sorted_:
        c.text(caretX + 12, y + 5, "^" if sorted_ == "up" else "v", 10, ACCENT)

    if targets:
        # The name's button, which is what sorts.
        c.rect(x - 4, y, nameWidth + 8, HEADER_HEIGHT,
               over((0.55, 0.85, 1.00, 0.16), WINDOW))

        # The caret's, which is what filters. Wider than the caret it draws.
        c.rect(caretX - 5, y, 18, HEADER_HEIGHT,
               over((0.95, 0.35, 0.32, 0.22), WINDOW))

    return nameWidth


STATES = [
    ("PLAYER", None, False, "plain - not sorted, not filtered"),
    ("ITEM", "down", False, "sorted by this column, A to Z"),
    ("TYPE", None, True, "filtered: the name goes accent"),
    ("DATE", "up", True, "both at once, on two different channels"),
]


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    MARGIN = 40
    W = 900
    H = 470

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    G1 = over((0.97, 0.96, 1.00, 1), GROUND)
    G3 = over((0.64, 0.61, 0.78, 1), GROUND)
    GA = over((0.55, 0.85, 1.00, 1), GROUND)
    GW = over((0.95, 0.35, 0.32, 1), GROUND)

    page.text(MARGIN, 26, "One header, two jobs", 15, G1)
    page.text(MARGIN, 54,
              "Sorting already works on every column but the tickbox and the "
              "#. The caret is what adds filtering.", 10, G3)

    # The hit targets.
    y = 96
    page.text(MARGIN, y - 18, "WHERE YOU CLICK", 10, G1)

    c = C(img, MARGIN, y)
    c.rect(0, 0, W - MARGIN * 2, HEADER_HEIGHT + 8, WINDOW)
    header(c, 12, 4, "PLAYER", targets=True)
    header(c, 200, 4, "ITEM", targets=True)
    header(c, 400, 4, "WHERE", targets=True)

    page.text(MARGIN + 12, y + 40, "the name sorts", 10, GA)
    page.text(MARGIN + 200, y + 40, "the caret filters", 10, GW)

    for n, line in enumerate(wrap(
            "A caret is eight pixels wide and an eight pixel target is one "
            "people miss, so its button is 18 wide and the full height of the "
            "header - reaching into the gap that is already between columns, "
            "which costs the column nothing.", 10, W - MARGIN * 2)):
        page.text(MARGIN, y + 62 + n * 13, line, 10, G3)

    # The states.
    y = 216
    page.text(MARGIN, y - 18, "WHAT IT LOOKS LIKE", 10, G1)

    c = C(img, MARGIN, y)
    c.rect(0, 0, W - MARGIN * 2, HEADER_HEIGHT + 8, WINDOW)

    x = 12
    for label, sorted_, filtered, _note in STATES:
        header(c, x, 4, label, sorted_, filtered)
        x += CELL

    c.rect(0, HEADER_HEIGHT + 8, W - MARGIN * 2, 1, SEP)

    ny = y + 44
    for index, (label, _s, _f, note) in enumerate(STATES):
        page.text(MARGIN + 12, ny + index * 15,
                  label + " - " + note, 10,
                  GA if index in (2, 3) else G3)

    y = 330

    for label, color, text in [
        ("TWO CHANNELS, NOT ONE", GA,
         "The arrow says sorted; the name going accent says filtered. A "
         "column that is both says both, instead of one state hiding the "
         "other."),
        ("THE CARET IS ALWAYS THERE", G3,
         "Even on a column nothing is filtered by, so there is no hunting for "
         "which headers have one. Muted until it is used."),
    ]:
        page.text(MARGIN, y, label, 10, color)
        for n, part in enumerate(wrap(text, 10, W - MARGIN * 2 - 200)):
            page.text(MARGIN + 200, y + n * 13, part, 10, G3)
        y += len(wrap(text, 10, W - MARGIN * 2 - 200)) * 13 + 10

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\header-states.png")
    img.save(out)

    print("wrote header-states.png", img.size)
