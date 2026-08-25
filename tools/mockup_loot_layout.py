# -*- coding: utf-8 -*-
"""The Loot tab: what overlaps today, and where the controls should go.

Aimee, on the screenshot: "the 2 rows of search bars has many places
overlapping and some check all vs check none buttons arent working properly
[...] its starting to feel a little cluttered. maybe the select all, deselect
all, ignore, hide, hide all and show hidden options can be at the bottom of
the frame to free up space on the top? [...] another thing to make it take up
less space would be the filter options are in the column header like it would
be in excel."

EVERY OVERLAP HERE IS MEASURED, not eyeballed. The real control widths are in
UI/FilterBar.lua and UI/SelectionBar.lua, the real column widths in
UI/Columns.lua, and the window is 900 with the bars inset 16 either side, so
the row they have to fit inside is 868.

TWO OF THE THREE OVERLAPS ARE MINE. Adding the Difficulty dropdown put 92px
on a row that had 12px of slack, and adding Hide all put 80px on a row whose
summary was already right up against the buttons. The third -- All and None
sitting on the header text inside a dropdown -- is older.

Writes screenshots/loot-layout.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, C, GROUND, SCALE, TEXT_1, TEXT_2, TEXT_3, WARNING, WINDOW,
    ROW_ALT, SEP, BUTTON, over, measure, wrap,
)

# The main window, and the row the bars have to fit inside.
WINDOW_WIDTH = 900
INSET = 16
ROW = WINDOW_WIDTH - INSET * 2          # 868

BAR_HEIGHT = 22
GAP = 6

# UI/Columns.lua, feed. width and the gap that follows it.
COLUMNS = [
    ("", 16, 8), ("#", 30, 8), ("PLAYER", 130, 8), ("ITEM", 250, 10),
    ("TYPE", 76, 8), ("WHERE", 150, 10), ("DATE", 96, 10),
]

# WHERE gives up 34px so DIFF can have a header of its own to filter from.
# It already prints the difficulty on the end of the instance name, so the
# row is no wider and the letter becomes scannable down a column.
PROPOSED_COLUMNS = [
    ("", 16, 8), ("#", 30, 8), ("PLAYER", 130, 8), ("ITEM", 250, 10),
    ("TYPE", 76, 8), ("WHERE", 116, 6), ("DIFF", 34, 10), ("DATE", 96, 10),
]

# Which column header carries which filter, once they move into the headers.
HEADER_FILTER = {
    "PLAYER": "player", "ITEM": "item", "TYPE": "win type",
    "WHERE": "location", "DIFF": "difficulty", "DATE": "dates",
}


def button(c, x, y, label, width=None, color=TEXT_1, fill=BUTTON):
    width = width or (measure(label, 11) + 26)
    c.rect(x, y, width, BAR_HEIGHT, fill)
    c.text(x + (width - measure(label, 11)) / 2, y + 5, label, 11, color)
    return width


def field(c, x, y, width, text, muted=True):
    c.rect(x, y, width, BAR_HEIGHT, ROW_ALT)
    c.text(x + 6, y + 5, text, 11, TEXT_3 if muted else TEXT_1)
    return width


# --------------------------------------------------------------------------
# Today
# --------------------------------------------------------------------------

def today(c):
    """The two bars as they are, with the overlaps drawn where they fall."""
    x = 0

    x += field(c, x, 0, 100, "Search...") + GAP

    for label in ("Player", "Item", "Location", "Win type", "Difficulty"):
        x += button(c, x, 0, label, 86) + GAP

    # The date fields, anchored left to right off the last dropdown.
    c.text(x + 4, 5, "From", 11, TEXT_3)
    x += measure("From", 11) + 14
    x += field(c, x, 0, 100, "MM-DD-YYYY") + 10

    c.text(x, 5, "To", 11, TEXT_3)
    x += measure("To", 11) + 10
    toEnd = x + 100
    field(c, x, 0, 100, "MM-DD-YYYY")

    # Clear is anchored to the RIGHT edge, so it does not move when the row
    # in front of it grows -- it just gets sat on.
    clearX = ROW - 54
    button(c, clearX, 0, "Clear", 54, WARNING)

    if toEnd > clearX:
        c.rect(clearX, 0, toEnd - clearX, BAR_HEIGHT,
               over((0.95, 0.35, 0.32, 0.45), ROW_ALT))

    # Second row: the summary on the left, the buttons flowed from the right.
    c.text(0, 30, "49 of 218 items · 18 hidden", 11, TEXT_2)
    summaryEnd = measure("49 of 218 items · 18 hidden", 11)

    at = ROW
    firstButtonX = at

    for label in ("Show hidden", "This season", "Everything", "All content",
                  "Hide all", "Hide", "Ignore", "Deselect all", "Select all"):
        width = measure(label, 11) + 26
        at -= width
        button(c, at, 28, label, width)
        at -= GAP
        firstButtonX = at + GAP

    if summaryEnd > firstButtonX:
        c.rect(firstButtonX, 28, summaryEnd - firstButtonX, BAR_HEIGHT,
               over((0.95, 0.35, 0.32, 0.45), ROW_ALT))

    return toEnd - clearX, summaryEnd - firstButtonX


# --------------------------------------------------------------------------
# The dropdown panel, today and fixed
# --------------------------------------------------------------------------

PANEL_WIDTH = 210


def dropdown_panel(c, x, y, fixed):
    height = 150

    c.rect(x, y, PANEL_WIDTH, height, WINDOW)
    c.rect(x, y, PANEL_WIDTH, 1, ACCENT)

    header = "4 options · 3 selected"

    if fixed:
        # The counts move under the buttons rather than beside them: two
        # short words and two 44px buttons do not fit 210px however they are
        # arranged, and the header is the part that can wrap.
        button(c, x + PANEL_WIDTH - 96, y + 5, "All", 44)
        button(c, x + PANEL_WIDTH - 48, y + 5, "None", 44)
        c.text(x + 8, y + 8, "Win type", 11, TEXT_1)
        c.text(x + 8, y + 30, header, 10, TEXT_3)
        top = y + 48
    else:
        c.text(x + 8, y + 8, header, 10, TEXT_3)
        button(c, x + PANEL_WIDTH - 96, y + 5, "All", 44)
        button(c, x + PANEL_WIDTH - 48, y + 5, "None", 44)

        # 8 + the header, against a button block starting at 210 - 96.
        overlap = (8 + measure(header, 10)) - (PANEL_WIDTH - 96)

        if overlap > 0:
            c.rect(PANEL_WIDTH - 96 + x, y + 5, overlap, 16,
                   over((0.95, 0.35, 0.32, 0.45), WINDOW))

        top = y + 26

    field(c, x + 8, top, PANEL_WIDTH - 16, "Type to narrow...")

    for index, (label, on) in enumerate(
            [("Greed", True), ("Mog", True), ("Need", True),
             ("Personal", False)]):
        rowY = top + 28 + index * 20
        c.box(x + 10, rowY, on)
        c.text(x + 30, rowY + 1, label, 11, TEXT_2 if on else TEXT_3)

    return height


# --------------------------------------------------------------------------
# Proposed
# --------------------------------------------------------------------------

def proposed(c):
    """One thin row on top, filters in the headers, actions along the bottom."""
    # TOP: search, the count, and Clear. Nothing else.
    field(c, 0, 0, 180, "Search...")

    c.text(190, 5, "49 of 218 items · 18 hidden", 11, TEXT_2)

    button(c, ROW - 54, 0, "Clear", 54)

    # THE COLUMN HEADERS, each carrying its own filter.
    y = 34
    c.rect(0, y + 18, ROW, 1, SEP)

    x = 0

    for label, width, gap in PROPOSED_COLUMNS:
        if label:
            active = label in ("TYPE", "WHERE")

            c.text(x, y + 4, label, 10, ACCENT if active else TEXT_3)

            key = HEADER_FILTER.get(label)

            if key:
                # The caret sits in the gap after the column, so it costs the
                # column no width at all -- the same trick the Raiders board's
                # sort arrow uses.
                caret = x + measure(label, 10) + 4
                c.text(caret, y + 4, "v", 10,
                       ACCENT if active else TEXT_3)

        x += width + gap

    # A couple of rows, so the headers read as headers.
    for index, row in enumerate([
        ("1", "Xinnci", "Venomwoven Effigy", "Need", "Venomous Abyss",
         "L", "08/23/26 7:35 PM"),
        ("2", "Shinryunin", "Venomcast Effigy", "Need", "Venomous Abyss",
         "L", "08/23/26 7:35 PM"),
    ]):
        rowY = y + 26 + index * 20

        if index % 2 == 0:
            c.rect(0, rowY - 3, ROW, 20, ROW_ALT)

        x = 0

        for position, (label, width, gap) in enumerate(PROPOSED_COLUMNS):
            if position == 0:
                c.box(x + 1, rowY, False)
            else:
                text = row[position - 1]
                c.text(x, rowY + 1, text, 11,
                       TEXT_1 if position == 2 else TEXT_2)

            x += width + gap

    # BOTTOM: everything that acts on the list, in one row above Close.
    bottom = 108

    c.rect(0, bottom - 8, ROW, 1, SEP)

    x = 0

    for label in ("Select all", "Deselect all", "Ignore", "Hide", "Hide all",
                  "Show hidden"):
        x += button(c, x, bottom, label) + GAP

    # The scope toggles keep their own group on the right, because they narrow
    # the list rather than acting on it.
    at = ROW

    for label in ("All content", "Everything", "This season"):
        width = measure(label, 11) + 26
        at -= width
        button(c, at, bottom, label, width)
        at -= GAP

    return bottom + BAR_HEIGHT


# --------------------------------------------------------------------------
# The page
# --------------------------------------------------------------------------

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    MARGIN = 40
    W = MARGIN * 2 + ROW + 300
    H = 760

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    G1 = over((0.97, 0.96, 1.00, 1), GROUND)
    G3 = over((0.64, 0.61, 0.78, 1), GROUND)
    GA = over((0.55, 0.85, 1.00, 1), GROUND)
    GW = over((0.95, 0.35, 0.32, 1), GROUND)

    page.text(MARGIN, 28, "The Loot tab: the overlaps, and where things go",
              15, G1)
    page.text(MARGIN, 56,
              "Measured against the real control widths. The window is 900 "
              "and the bars are inset 16 either side, so everything has to "
              "fit inside 868.", 10, G3)

    y = 110
    page.text(MARGIN, y - 20, "TODAY", 11, GW)

    body = C(img, MARGIN, y)
    clearOverlap, summaryOverlap = today(body)

    notes = [
        ("Clear sits on the To field",
         "%d px over. Clear is anchored to the right edge so it does not move "
         "when the row in front of it grows - it just gets sat on. The "
         "Difficulty dropdown I added is 92px on a row that had about 12 to "
         "spare." % clearOverlap),
        ("The count sits under Select all",
         "%d px over. Hide all is another 80px on a row whose summary was "
         "already against the buttons." % summaryOverlap),
    ]

    ny = y - 20
    for title, why in notes:
        page.text(MARGIN + ROW + 20, ny, title, 10, GW)
        lines = wrap(why, 10, 250)
        for n, line in enumerate(lines):
            page.text(MARGIN + ROW + 20, ny + 12 + n * 11, line, 10, G3)
        ny += 12 + len(lines) * 11 + 10

    y += 90

    page.text(MARGIN, y - 20,
              "THE DROPDOWNS - All and None sit on the header text, and None "
              "does not do what it says", 11, GW)

    dropdown_panel(C(img, MARGIN, y), 0, 0, False)
    dropdown_panel(C(img, MARGIN + PANEL_WIDTH + 40, y), 0, 0, True)

    page.text(MARGIN, y + 158, "today", 10, GW)
    page.text(MARGIN + PANEL_WIDTH + 40, y + 158, "fixed", 10, GA)

    page.text(MARGIN + ROW + 20, ny, "None shows everything", 10, GW)

    for n, line in enumerate(wrap(
            "None calls ClearField, and an empty selection means \"no "
            "constraint\" - so it shows EVERYTHING. It has always done that. "
            "It needs a real difference between \"nothing chosen yet\" and "
            "\"chosen nothing\".", 10, 250)):
        page.text(MARGIN + ROW + 20, ny + 12 + n * 11, line, 10, G3)

    y += 200

    page.text(MARGIN, y - 20, "PROPOSED", 11, GA)

    proposed(C(img, MARGIN, y))

    y += 170

    for label, color, text in [
        ("ONE ROW ON TOP", GA,
         "Search, the count, and Clear. The five dropdowns leave it, so it "
         "cannot overflow again however many filters get added."),
        ("FILTERS IN THE HEADERS", GA,
         "A caret beside each column name opens the same dropdown that "
         "exists today - PLAYER, ITEM, TYPE, WHERE and DATE. The caret sits "
         "in the gap after the name, so it costs the column no width. A "
         "header whose filter is set is drawn in the accent color, which is "
         "how you see at a glance that a list is narrowed."),
        ("ACTIONS ALONG THE BOTTOM", GA,
         "Select all, Deselect all, Ignore, Hide, Hide all and Show hidden, "
         "above the Close button. The scope toggles keep their own group on "
         "the right because they narrow the list rather than act on it."),
        ("DIFFICULTY GETS A COLUMN", GA,
         "Drawn above. WHERE gives up 34px and DIFF takes it, so the row is "
         "no wider - WHERE already printed the difficulty on the end of the "
         "instance name. It gets a header to filter from and the letter "
         "becomes scannable down a column. Say if you would rather it hung "
         "off WHERE instead."),
        ("NONE", GW,
         "Fixed as part of this: \"nothing chosen yet\" and \"chosen "
         "nothing\" become different states, so None shows nothing and Clear "
         "puts it back."),
        ("TRANSPARENCY", G3,
         "I checked and could not find a change. Theme.lua, Palettes.lua and "
         "WindowStack.lua are byte-identical to what shipped in v0.4.0 apart "
         "from the class-color move, and every palette has been 0.97 the "
         "whole time. I would rather give you an opacity setting on the "
         "Display tab than guess."),
    ]:
        page.text(MARGIN, y, label, 10, color)
        for n, part in enumerate(wrap(text, 10, W - MARGIN * 2 - 200)):
            page.text(MARGIN + 200, y + n * 13, part, 10, G3)
        y += max(18, len(wrap(text, 10, W - MARGIN * 2 - 200)) * 13 + 8)

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\loot-layout.png")
    img.save(out)

    print("wrote loot-layout.png", img.size)
    print("   Clear overlaps the To field by %.0f px" % clearOverlap)
    print("   the summary overlaps the buttons by %.0f px" % summaryOverlap)
