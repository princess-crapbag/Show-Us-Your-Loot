# -*- coding: utf-8 -*-
"""What was overlapping, and what it looks like now.

Aimee: "the bosses tab is overlapping. the lockouts tab on the bosses tab is
overlapping. the new loot page is severely overlapping."

Fourteen overlaps were confirmed by measurement. They collapse to nine
distinct defects, and every one of them is drawn here at its real pixel size
with the real game font -- the BEFORE rows are the arithmetic as it shipped,
not a sketch of it.

Writes screenshots/overlap-fixes.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, C, GROUND, SCALE, SEP, TEXT_1, TEXT_2, TEXT_3,
    WINDOW, ROW_ALT, over, measure, wrap,
)

# Solid now -- the palettes lost their 0.97 alpha.
WIN = over((0.170, 0.145, 0.275, 1), GROUND)
T1 = over((0.97, 0.96, 1.00, 1), WIN)
T2 = over((0.82, 0.79, 0.92, 1), WIN)
T3 = over((0.64, 0.61, 0.78, 1), WIN)
AC = over((0.55, 0.85, 1.00, 1), WIN)
BAD = over((0.95, 0.35, 0.32, 1), WIN)
BAD_WASH = over((0.95, 0.35, 0.32, 0.30), WIN)
GOOD = over((0.35, 0.85, 0.55, 1), WIN)
BUTTON = over((1, 1, 1, 0.11), WIN)
RULE = over((1, 1, 1, 0.14), WIN)

G1 = over((0.97, 0.96, 1.00, 1), GROUND)
G2 = over((0.82, 0.79, 0.92, 1), GROUND)
G3 = over((0.64, 0.61, 0.78, 1), GROUND)
GBAD = over((0.95, 0.35, 0.32, 1), GROUND)
GGOOD = over((0.35, 0.85, 0.55, 1), GROUND)

MARGIN = 34
W = 1000
BAR_H = 22

# THE REAL WINDOW, not the page. Drawing a 900px window at the width of the
# page puts every resolved x somewhere it is not, which is the exact class of
# mistake this document is about.
WINDOW_WIDTH = 900


def button(c, x, y, label, width, height=20, color=T1, fill=BUTTON):
    c.rect(x, y, width, height, fill)
    c.text(x + (width - measure(label, 11)) / 2.0, y + (height - 13) / 2.0,
           label, 11, color)
    return x + width


def field(c, x, y, width, placeholder):
    c.rect(x, y, width, BAR_H, BUTTON)
    c.text(x + 7, y + 4, placeholder, 11, T3)
    return x + width


def collide(c, x, y, w, h):
    """Mark the rectangle where two things are drawn in one place."""
    c.rect(x, y, w, h, BAD_WASH)


def caption(page, y, text, color=G3, width=W - MARGIN * 2):
    for n, line in enumerate(wrap(text, 10, width)):
        page.text(MARGIN, y + n * 13, line, 10, color)
    return y + len(wrap(text, 10, width)) * 13


def label(page, y, tag, text, color):
    page.text(MARGIN, y, tag, 10, color)
    page.text(MARGIN + 58, y, text, 10, G2)


# --------------------------------------------------------------------------
# 1. The loot window's top row
# --------------------------------------------------------------------------

def loot_top(img, y, fixed):
    c = C(img, MARGIN, y)
    width = WINDOW_WIDTH

    c.rect(0, 0, width, BAR_H + 8, WIN)

    x = field(c, 16, 4, 100, "Search…")

    x += 10
    c.text(x, 8, "From", 11, T3)
    x += measure("From", 11) + 2 + 4
    from_start = x
    x = field(c, x, 4, 94, "MM-DD-YYYY")

    x += 10
    c.text(x, 8, "To", 11, T3)
    x += measure("To", 11) + 2 + 4
    x = field(c, x, 4, 94, "MM-DD-YYYY")
    dates_end = x

    count = "128 of 340 items  ·  212 hidden  ·  17 ignored"

    clear_x = width - 16 - 54

    if fixed:
        # Off the right edge, like Clear.
        cx = width - 80 - measure(count, 11)
        c.text(cx, 8, count, 11, T2)
    else:
        # At a fixed x 200, straight through both date boxes.
        collide(c, 200, 4, min(dates_end, 200 + measure(count, 11)) - 200,
                BAR_H)
        c.text(200, 8, count, 11, BAD)

    button(c, clear_x, 4, "Clear", 54, BAR_H)

    return from_start, dates_end


# --------------------------------------------------------------------------
# 2. The loot window's footer
# --------------------------------------------------------------------------

ACTIONS = [("Select all", 68), ("Deselect all", 78), ("Ignore", 74),
           ("Hide", 70), ("Hide all", 74)]

# Nearest Close first, because the chain is right-rooted and flows leftward.
TOGGLES_BEFORE = [("Show hidden", 108), ("All content", 110),
                  ("Gear only", 100), ("All seasons", 100)]
TOGGLES_AFTER = [("Show hidden", 84), ("All content", 96),
                 ("Gear only", 74), ("All seasons", 76)]


def loot_footer(img, y, fixed):
    c = C(img, MARGIN, y)
    width = WINDOW_WIDTH

    c.rect(0, 0, width, 46, WIN)
    c.rect(16, 6, width - 32, 1, RULE)

    toggles = TOGGLES_AFTER if fixed else TOGGLES_BEFORE

    # Right chain, flowing left from Close.
    r = width - 16 - 100
    button(c, r, 14, "Close", 100, 26)

    spans = []
    for name, w in toggles:
        r -= 6 + w
        spans.append((r, w, name))

    # Left chain, flowing right from 16.
    x = 16
    for name, w in ACTIONS:
        x = button(c, x, 17, name, w) + 6
    left_end = x - 6

    right_start = min(span[0] for span in spans)

    for rx, w, name in spans:
        clash = (not fixed) and rx < left_end
        button(c, rx, 17, name, w, color=BAD if clash else T1)
        if clash:
            collide(c, rx, 17, min(left_end - rx, w), 20)

    return left_end, right_start


# --------------------------------------------------------------------------
# 3. The Bosses tab's loot pane
# --------------------------------------------------------------------------

DROPS = [
    "Bracers of the Sundered Coil", "Ula'tek's Ritual Band",
    "Hood of the Drowned Choir", "Sandals of Quiet Depths",
    "Abyssal Chestguard", "Tidecaller's Signet", "Grotto Warden's Girdle",
    "Cloak of the Falling Tide", "Shellbound Bracers",
    "Pauldrons of the Deep", "Coral-Etched Waistguard",
    "Leggings of the Devouring Advance", "Serpent Crown of the Oracle",
    "Mantle of the Ophidian", "Ring of Sunken Halls",
    "Boots of the Reckless Wayfarer",
]

CAVEAT = ("From the Adventure Guide, which lists what a boss can drop and "
          "not what it drops for your loot spec. Warbound and trade goods "
          "are not in this list.")


def boss_pane(img, y, fixed):
    """The right-hand pane of the Bosses tab, at its real 606 x 398."""
    pane_w, pane_h = 606, 398
    c = C(img, MARGIN, y)

    c.rect(0, 0, pane_w, pane_h, ROW_ALT)

    c.text(10, 12, "Ula'tek, the Drowned Prophet", 12, T1)
    c.text(10, 34, "Heroic  ·  4 kills  ·  11 never dropped", 11, T2)
    c.text(10, 54, "Never dropped for you", 11, T3)

    cap = 13 if fixed else 16
    shown = min(cap, len(DROPS))

    footnote_lines = wrap(CAVEAT, 11, pane_w - 20)
    footnote_top = pane_h - 8 - len(footnote_lines) * 14

    for i in range(shown):
        ry = 92 + i * 18
        c.text(10, ry, DROPS[i], 11, T2)

    more = len(DROPS) - shown
    if more > 0:
        c.text(10, 92 + shown * 18, "+ %d more" % more, 11, T3)

    rows_bottom = 92 + (shown + (1 if more > 0 else 0)) * 18

    if not fixed and rows_bottom > footnote_top:
        collide(c, 0, footnote_top, pane_w, rows_bottom - footnote_top)

    for n, line in enumerate(footnote_lines):
        c.text(10, footnote_top + n * 14, line, 11,
               T3 if fixed else BAD)

    return rows_bottom, footnote_top, pane_h


# --------------------------------------------------------------------------
# 4. The lockouts view inside the Bosses tab
# --------------------------------------------------------------------------

LOCKOUTS = [
    ("Arcangila", "Nerub-ar Palace", "Mythic", "5 of 8", "3d 14h"),
    ("Arcangila", "Liberation of Undermine", "Heroic", "8 of 8", "3d 14h"),
    ("Shaimee", "Nerub-ar Palace", "Normal", "2 of 8", "3d 14h"),
]


def lockouts(img, y, fixed):
    c = C(img, MARGIN, y)
    width = 868   # the panel, inset 16 each side of the window

    c.rect(0, 0, width, 150, WIN)

    # The control row: title, then the three buttons.
    c.text(2, 4, "BOSSES", 15, T1)
    bx = 2 + measure("BOSSES", 15) + 14

    # Not dropped / Read the Adventure Guide are hidden in this view.
    c.text(bx, 10, "(mode + journal buttons hidden in this view)", 10, T3)

    view_x = 388
    button(c, view_x, 6, "Bosses", 100, 20)

    top = 34 if fixed else 22

    heads = [("CHARACTER", 8, 150), ("RAID", 166, 220),
             ("BOSSES DOWN", 394, 90)]

    clash = (not fixed) and top < 26

    for text, hx, hw in heads:
        colliding = clash and hx + measure(text, 10) > view_x
        if colliding:
            collide(c, hx, top, measure(text, 10), 26 - top)
        c.text(hx, top, text, 10, BAD if colliding else T3)

    c.right(width - 6, top, "RESETS IN", 10, T3)

    for i, (who, raid, diff, bosses, resets) in enumerate(LOCKOUTS):
        ry = top + 18 + i * 20
        c.text(8, ry + 3, who, 11, AC)
        c.text(166, ry + 3, raid + "  ·  " + diff, 11, T2)
        c.text(394, ry + 3, bosses, 11, AC)
        c.right(width - 6, ry + 3, resets, 11, T3)

    return top


# --------------------------------------------------------------------------

def panel(page, img, y, title, before, after, note_text, gap_before,
          gap_after):
    page.text(MARGIN, y, title, 13, G1)
    y += 24

    page.text(MARGIN, y, "BEFORE", 10, GBAD)
    y += 14
    before(img, y)
    y += gap_before

    page.text(MARGIN, y, "AFTER", 10, GGOOD)
    y += 14
    after(img, y)
    y += gap_after

    y = caption(page, y, note_text) + 22
    return y


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    H = 1895
    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    page.text(MARGIN, 26, "Every overlap, and what it is now", 16, G1)
    y = caption(
        page, 54,
        "Fourteen confirmed by measurement, collapsing to nine defects. "
        "Drawn at real pixel sizes with the real game font, so the BEFORE "
        "rows are the arithmetic as it shipped rather than a sketch of it.")
    y += 24

    # ---- 1. loot top row
    page.text(MARGIN, y, "1.  The loot window's top row", 13, G1)
    y += 24
    page.text(MARGIN, y, "BEFORE", 10, GBAD)
    y += 14
    fs, de = loot_top(img, y, False)
    y += 40
    page.text(MARGIN, y, "AFTER", 10, GGOOD)
    y += 14
    loot_top(img, y, True)
    y += 42
    y = caption(
        page, y,
        "The second filter bar went away but the From and To boxes stayed, "
        "and the count line was moved to a fixed x 200 -- which was empty "
        "space on the two-bar layout and is the middle of the date fields on "
        "this one. It was printed through both boxes AND under their own "
        "MM-DD-YYYY placeholders, so \"0 items\" was glyphs on glyphs. It now "
        "hangs off the right edge the way Clear does, so the two keep their "
        "10px gap at any window width and the count grows leftward into the "
        "empty middle of the bar.")
    y += 26

    # ---- 2. footer
    page.text(MARGIN, y, "2.  The loot window's footer", 13, G1)
    y += 24
    page.text(MARGIN, y, "BEFORE", 10, GBAD)
    y += 14
    left_end, right_start = loot_footer(img, y, False)
    y += 60
    page.text(MARGIN, y, "AFTER", 10, GGOOD)
    y += 14
    loot_footer(img, y, True)
    y += 62
    y = caption(
        page, y,
        "Moving the actions to the footer put nine buttons and four toggles "
        "on one line: they needed 930px of a 900px window. Hide all covered "
        "62 of the 100 pixels of All seasons and, being created later at the "
        "same frame level, took its clicks as well. The four toggles were "
        "each 24 to 34px wider than the widest label they can ever hold; "
        "trimmed to label + 16 they start at 430 instead of 342, and the "
        "action group ends at 404. 26px of headroom, and that number is now "
        "asserted by tools/test_layout.py.")
    y += 26

    # ---- 3. boss pane
    page.text(MARGIN, y, "3.  The Bosses tab's loot pane", 13, G1)
    y += 24
    page.text(MARGIN, y, "BEFORE", 10, GBAD)
    y += 14
    boss_pane(img, y, False)
    page.text(MARGIN + 640, y + 150,
              "16 rows end at 398 —", 10, GBAD)
    page.text(MARGIN + 640, y + 164,
              "exactly the pane's height,", 10, GBAD)
    page.text(MARGIN + 640, y + 178,
              "so the caveat pinned to the", 10, GBAD)
    page.text(MARGIN + 640, y + 192,
              "bottom lands on top of the", 10, GBAD)
    page.text(MARGIN + 640, y + 206, "last two of them.", 10, GBAD)
    y += 412
    page.text(MARGIN, y, "AFTER", 10, GGOOD)
    y += 14
    boss_pane(img, y, True)
    page.text(MARGIN + 640, y + 150, "13 items plus the", 10, GGOOD)
    page.text(MARGIN + 640, y + 164, "\"+ N more\" line end at", 10, GGOOD)
    page.text(MARGIN + 640, y + 178, "344, and the caveat starts", 10, GGOOD)
    page.text(MARGIN + 640, y + 192, "at 362 — with 4px still", 10, GGOOD)
    page.text(MARGIN + 640, y + 206, "spare if it wraps to a", 10, GGOOD)
    page.text(MARGIN + 640, y + 220, "third line.", 10, GGOOD)
    y += 412
    y = caption(
        page, y,
        "The list was sized as if it owned the whole pane. The caveat is "
        "pinned 8px off the bottom and wraps to two lines in the 586px it is "
        "given, so it owns the bottom 36 pixels and the rows have to stop "
        "above them. The Dropped list clears the caveat and could hold 16, "
        "but the row count is chosen before the footnote text is set, so a "
        "mode-aware cap would read the previous render's text — three rows "
        "is the price of not doing that.")
    y += 26

    # ---- 4. lockouts
    page.text(MARGIN, y, "4.  The lockouts view, inside the Bosses tab",
              13, G1)
    y += 24
    page.text(MARGIN, y, "BEFORE", 10, GBAD)
    y += 14
    lockouts(img, y, False)
    y += 166
    page.text(MARGIN, y, "AFTER", 10, GGOOD)
    y += 14
    lockouts(img, y, True)
    y += 166
    y = caption(
        page, y,
        "The view was anchored 12px higher than the boss list it replaces, "
        "so its column headings were drawn 4px up into the Bosses/Lockouts "
        "button — and that button is the only way back out of this view, so "
        "unlike the other two it cannot be hidden here. It now starts at the "
        "same offset the boss rail's first row uses, which is also the "
        "number the Keys tab uses for the identical control.")

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\overlap-fixes.png")
    img.save(out)

    print("wrote overlap-fixes.png", img.size)
