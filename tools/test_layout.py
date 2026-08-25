# -*- coding: utf-8 -*-
"""Nothing may be drawn on top of anything else.

Aimee, after the last release: "the bosses tab is overlapping. the lockouts
tab on the bosses tab is overlapping. the new loot page is severely
overlapping."

WHY THIS SUITE IS ARITHMETIC AND NOT A LIST OF STRINGS. Every one of those
overlaps was in code that read correctly. `countText` at x 200 is a fine line
until you resolve where the From box lands; `MAX_ROWS = 16` is a fine number
until you add the height of a caveat that wraps to two lines. Grepping for
"200" would have passed on all of them. So this file pulls the CONSTANTS out
of the source, resolves the anchor chains the way the client would, measures
every string with the real font, and asserts that the rectangles do not
intersect. Change a constant and the arithmetic moves with it.

Widths come from tools/mockup_settings_tabs.measure, which is the same font
metric UI/Theme.lua's MeasureText uses. The repo rule is that widths are
measured and never estimated, and every number below is.
"""
import re
import sys

sys.path.insert(0, "tools")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import test_load
from mockup_settings_tabs import measure

FAILURES = []


def check(label, condition, detail=""):
    if condition:
        print("ok   " + label)
    else:
        FAILURES.append(label)
        print("FAIL " + label + ("  " + str(detail) if detail else ""))


def src(path):
    return test_load.ROOT.joinpath(path).read_text(encoding="utf-8")


def number(text, pattern, name):
    """One integer out of the source, so the test moves when the code does."""
    found = re.search(pattern, text)

    if not found:
        FAILURES.append("could not read " + name)
        print("FAIL could not read " + name)
        return 0

    return int(found.group(1))


def gap(name, a_end, b_start):
    """b must begin after a ends. Returns the clearance."""
    clear = b_start - a_end
    check(name, clear >= 0,
          "%.1f then %.1f, overlapping by %.1f" % (a_end, b_start, -clear))
    return clear


SMALL = 11        # Theme.sizes.rowSmall
SUBTITLE = 11     # Theme.sizes.subtitle
HEADER = 10       # Theme.sizes.columnHeader

MAIN = src("UI/MainWindow.lua")
BAR = src("UI/FilterBar.lua")

WINDOW_WIDTH = number(MAIN, r"local WINDOW_WIDTH = (\d+)", "WINDOW_WIDTH")
WINDOW_HEIGHT = number(MAIN, r"local WINDOW_HEIGHT = (\d+)", "WINDOW_HEIGHT")


# ==========================================================================
# The loot window's top row
# ==========================================================================
#
# One bar at y -100, 22 tall, holding the search box, the From and To date
# fields and Clear -- and the count line, which is not in the bar at all and
# was placed at a hardcoded x that used to be empty and is not any more.

print("-- loot window, top row " + "-" * 52)

BAR_INSET = 16
SEARCH_WIDTH = number(BAR, r'CreateTextInput\(bar, (\d+), "Search', "search")
CLEAR_WIDTH = number(BAR, r'CreateButton\(bar, (\d+), BAR_HEIGHT, "Clear"',
                     "Clear")
INPUT_INSET = number(BAR, r"local INPUT_INSET = (\d+)", "INPUT_INSET")
CARET_ROOM = number(BAR, r"local CARET_ROOM = (\d+)", "CARET_ROOM")

date_width = max(measure("MM-DD-YYYY", SMALL),
                 measure("0000-00-00", SMALL)) + INPUT_INSET + CARET_ROOM

x = BAR_INSET + SEARCH_WIDTH
FROM_START = x + 10 + measure("From", SMALL) + 2 + 4

for label in ("From", "To"):
    x += 10 + measure(label, SMALL) + 2 + 4 + date_width

DATES_END = x
CLEAR_START = WINDOW_WIDTH - BAR_INSET - CLEAR_WIDTH

# The widest line the count can hold: every clause at once, saturated.
WIDEST_COUNT = measure(
    "1280 of 3400 items  ·  2120 hidden  ·  170 ignored"
    "  ·  1280 selected", SUBTITLE)

count_inset = number(MAIN,
                     r'countText:SetPoint\("TOPRIGHT", -(\d+), -105\)',
                     "countText")

COUNT_RIGHT = WINDOW_WIDTH - count_inset
COUNT_LEFT = COUNT_RIGHT - WIDEST_COUNT

check("the count hangs off the right edge like Clear does, not off a fixed x",
      'countText:SetPoint("TOPRIGHT"' in MAIN)

gap("the count clears the To box even at its widest", DATES_END, COUNT_LEFT)
gap("and never reaches Clear", COUNT_RIGHT, CLEAR_START)

# The bug as it shipped, so this fails if anyone puts the number back.
check("x 200 is inside the From box, which is why it cannot go back there",
      FROM_START < 200 < DATES_END,
      "the date fields run %.1f to %.1f" % (FROM_START, DATES_END))


# ==========================================================================
# The loot list's columns
# ==========================================================================

print("\n-- loot list, columns " + "-" * 54)

COLS = src("UI/Columns.lua")
ROWS = src("UI/Rows.lua")

entries = re.findall(
    r'\{ key = "(\w+)", label = "[^"]*", width = (\d+), gap = (\d+)', COLS)

SCROLL_USABLE = WINDOW_WIDTH - 70

check("every feed column is still declared in the shape syl_check reads",
      len(entries) == 8, "%d found" % len(entries))

total = sum(int(w) + int(g) for _, w, g in entries)

check("the columns fit the scroll frame",
      total <= SCROLL_USABLE, "%d needed of %d" % (total, SCROLL_USABLE))

widths = {k: int(w) for k, w, _ in entries}

# ITEM is drawn at Theme.sizes.row (12), not rowSmall -- the size mismatch
# that left the column 8px short of the one name the file cites as longest.
ICON_TEXT_GAP = number(ROWS, r"local ICON_TEXT_GAP = (\d+)", "ICON_TEXT_GAP")
DATE_MOVED = 19   # what FitDateColumn takes out of ITEM

item_box = widths.get("item", 0) - DATE_MOVED - ICON_TEXT_GAP
longest_cited = measure("Skullguard of the Risen Sacrifice", 12)

check("the ITEM cell fits the name the file calls longest, at the size it is "
      "actually drawn",
      item_box >= longest_cited,
      "box %.1f against %.1f" % (item_box, longest_cited))

check("TYPE fits its widest value and is not flush with it",
      widths.get("wintype", 0) >= measure("Bonus roll", SMALL) + 4,
      "%d against %.1f" % (widths.get("wintype", 0),
                           measure("Bonus roll", SMALL)))

check("DATE has no filter caret, because its panel could never have options",
      'width = 96, gap = 10, filterable = false' in COLS)


# ==========================================================================
# The loot window, top to bottom
# ==========================================================================

print("\n-- loot window, vertical " + "-" * 51)

SCROLL = src("UI/ScrollArea.lua")

LIST_TOP = number(MAIN, r"local LIST_TOP_INSET = (\d+)", "LIST_TOP_INSET")
LIST_BOTTOM = number(MAIN, r"local LIST_BOTTOM_INSET = (\d+)", "LIST_BOTTOM")
VISIBLE_ROWS = number(MAIN, r"local VISIBLE_ROWS = (\d+)", "VISIBLE_ROWS")
ROW_HEIGHT = number(src("UI/Theme.lua"), r"rowHeight = (\d+)", "rowHeight")

check("the scroll frame is told where the list starts rather than keeping a "
      "second copy of it",
      "config.listTop or TOP_INSET" in SCROLL
      and "listTop = LIST_TOP_INSET" in MAIN)

viewport = WINDOW_HEIGHT - LIST_TOP - LIST_BOTTOM

check("every row the window counts fits inside the frame that clips them",
      VISIBLE_ROWS * ROW_HEIGHT <= viewport,
      "%d rows of %d is %d, in %d"
      % (VISIBLE_ROWS, ROW_HEIGHT, VISIBLE_ROWS * ROW_HEIGHT, viewport))


# ==========================================================================
# The loot window's footer
# ==========================================================================

print("\n-- loot window, footer " + "-" * 53)

SEL = src("UI/SelectionBar.lua")
FOOTER = src("UI/MainFooter.lua")

CLOSE_WIDTH = number(FOOTER, r"local BUTTON_WIDTH = (\d+)", "Close width")

ACTIONS = [
    ("Select all", r"bar\.selectAll = Theme\.CreateButton\(parent, (\d+)"),
    ("Deselect all", r"bar\.deselect = Theme\.CreateButton\(parent, (\d+)"),
    ("Ignore", r"bar\.ignore = Theme\.CreateButton\(parent, (\d+)"),
    ("Hide", r"bar\.action = Theme\.CreateButton\(parent, (\d+)"),
    ("Hide all", r'CreateButton\(parent, (\d+), 20, "Hide all"'),
]

TOGGLES = [
    ("Show hidden", r'CreateButton\(parent, (\d+), 20, "Show hidden"',
     ("Show hidden", "Hide hidden")),
    ("All content", r'CreateButton\(parent, (\d+), 20, "All content"',
     ("All content", "Raids only", "Dungeons only")),
    ("Gear only", r'CreateButton\(parent, (\d+), 20, "Gear only"',
     ("Gear only", "Everything")),
    ("All seasons", r'CreateButton\(parent, (\d+), 20, "All seasons"',
     ("All seasons", "This season")),
]

# Left chain: flows right from 16 in 6px steps.
x = 16
for name, pattern in ACTIONS:
    width = number(SEL, pattern, name)

    check("'" + name + "' fits its own button",
          width >= measure(name, SMALL) + 8,
          "%d against %.1f" % (width, measure(name, SMALL)))

    x += width + 6

LEFT_END = x - 6

# Right chain: flows left from Close.
r = WINDOW_WIDTH - 16 - CLOSE_WIDTH

for name, pattern, labels in TOGGLES:
    width = number(SEL, pattern, name)
    widest = max(measure(one, SMALL) for one in labels)

    check("'" + name + "' fits every label it swaps to",
          width >= widest + 8, "%d against %.1f" % (width, widest))

    # Slack here is what pushed this group left until Hide all covered it.
    check("'" + name + "' is not carrying dead width",
          width <= widest + 20,
          "%d for a %.1f label" % (width, widest))

    r -= 6 + width

gap("the action group does not reach the toggles", LEFT_END, r)

check("Close outranks the resize grip that sits on its corner",
      "closeButton:SetFrameLevel(parent:GetFrameLevel() + 11)" in FOOTER)

ARCHIVE = src("UI/ArchiveControls.lua")

FOOTER_Y = number(SEL, r"local FOOTER_Y = (\d+)", "FOOTER_Y")
archive_y = number(ARCHIVE, r'bar:SetPoint\("BOTTOMLEFT", 16, (\d+)\)',
                   "archive bar y")
rule_y = number(FOOTER, r'separator:SetPoint\("BOTTOMLEFT", 16, (\d+)\)',
                "footer rule y")

check("the archives bar sits on the footer line with everything else",
      archive_y == FOOTER_Y, "%d against %d" % (archive_y, FOOTER_Y))

check("and below the rule that used to be drawn through it",
      archive_y + 24 <= rule_y,
      "the bar tops out at %d and the rule is at %d"
      % (archive_y + 24, rule_y))


# ==========================================================================
# The Bosses tab
# ==========================================================================

print("\n-- bosses tab " + "-" * 62)

BOSSES = src("UI/BossesPanel.lua")
BOSSLOOT = src("UI/BossLoot.lua")

PANEL_HEIGHT = WINDOW_HEIGHT - 100 - 52     # panel is TOPLEFT -100, BOTTOM 52

B_LIST_TOP = number(BOSSES, r"local LIST_TOP = (\d+)", "bosses LIST_TOP")
PANE_HEIGHT = PANEL_HEIGHT - (B_LIST_TOP - 8) - 20

L_TOP = number(BOSSLOOT, r"local LIST_TOP = (\d+)", "pane LIST_TOP")
L_ROW = number(BOSSLOOT, r"local ROW_HEIGHT = (\d+)", "pane ROW_HEIGHT")
MAX_ROWS = number(BOSSLOOT, r"local MAX_ROWS = (\d+)", "MAX_ROWS")

# The caveat is pinned 8 from the bottom and wraps to two lines of 14 in the
# 586px it is given. Rows are capped so they stop above it.
FOOTNOTE_HEIGHT = 2 * 14

rows_bottom = L_TOP + (MAX_ROWS + 1) * L_ROW    # +1 for the "+ N more" line
footnote_top = PANE_HEIGHT - 8 - FOOTNOTE_HEIGHT

gap("the boss loot list stops above its own caveat", rows_bottom, footnote_top)

check("with room for the caveat to wrap to a third line",
      rows_bottom <= footnote_top - 14,
      "%d against %d" % (rows_bottom, footnote_top - 14))

# The control row, and the lockouts view that was drawn up into it.
bx = 2 + measure("BOSSES", 15) + 14

for label, width in (("Not dropped", 110),
                     ("Read the Adventure Guide", 190),
                     ("Lockouts", 100)):
    check("'" + label + "' fits its button",
          width >= measure(label, SMALL) + 8,
          "%d against %.1f" % (width, measure(label, SMALL)))

    bx += width + 8

check("the control row fits the panel", bx - 8 <= 868, "%.1f" % (bx - 8))

CONTROLS_BOTTOM = 26      # the buttons occupy y -6 to -26

check("the lockouts view is anchored at the same offset as the boss rail",
      'frame.lockouts:SetPoint("TOPLEFT", 2, -LIST_TOP)' in BOSSES)

gap("the lockouts headings start below the Bosses/Lockouts button",
    CONTROLS_BOTTOM, B_LIST_TOP)


# ==========================================================================
# The lockouts view
# ==========================================================================

print("\n-- lockouts " + "-" * 64)

LOCK = src("UI/RaidLockoutsView.lua")

L_HEADER = number(LOCK, r"local HEADER_HEIGHT = (\d+)", "HEADER_HEIGHT")
L_ROWH = number(LOCK, r"local ROW_HEIGHT = (\d+)", "lockout ROW_HEIGHT")
L_ROWS = number(LOCK, r"local VISIBLE_ROWS = (\d+)", "lockout VISIBLE_ROWS")

view_height = PANEL_HEIGHT - B_LIST_TOP
rows_end = L_HEADER + L_ROWS * L_ROWH
caption_top = view_height - 4 - 12.5

gap("the lockout rows stop above the caption", rows_end, caption_top)

# Headings have to line up with the columns in the rows beneath them.
NAME_END = 6 + 150
RAID_X = NAME_END + 8
PROGRESS_X = RAID_X + 220 + 8

check("the RAID heading lines up with the instance column",
      'Heading("RAID", %d, 220)' % RAID_X in LOCK,
      "expected x %d" % RAID_X)

check("and BOSSES DOWN lines up with the progress column",
      'Heading("BOSSES DOWN", %d, 90)' % PROGRESS_X in LOCK,
      "expected x %d" % PROGRESS_X)

check("RESETS IN clears the progress column",
      PROGRESS_X + 90 < 868 - measure("RESETS IN", HEADER) - 6)


# ==========================================================================
# The filter dropdown
# ==========================================================================

print("\n-- filter dropdown " + "-" * 57)

DROP = src("UI/FilterDropdown.lua")

D_PADDING = number(DROP, r"local PANEL_PADDING = (\d+)", "PANEL_PADDING")
D_HEADER = number(DROP, r"local PANEL_HEADER = (\d+)", "PANEL_HEADER")
PANEL_WIDTH = number(DROP, r"math\.max\(config\.width, (\d+)\)", "panel width")

content = PANEL_WIDTH - D_PADDING * 2

worst_header = measure("200 options  ·  200 selected", HEADER)

check("the count line fits the panel",
      worst_header <= content, "%.1f in %d" % (worst_header, content))

check("and is bounded, so a longer one truncates instead of escaping",
      'panel.headerText:SetPoint("TOPRIGHT", -PANEL_PADDING, -26)' in DROP)

# The CODE path, not the word -- the comment beside it explains why it went,
# and a check that fails on its own explanation is a check nobody keeps.
check("the clause that overran it is gone",
      'and " matching" or ""' not in DROP)

check("the header is tall enough for the buttons and the count on two lines",
      D_HEADER >= 44,
      "%d, with a %.1f count line beside two 44px buttons"
      % (D_HEADER, worst_header))

check("the panel picks its side when it opens, not when it is built",
      'panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)' not in DROP
      and 'self.panel:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)'
      in DROP)

check("and is clamped to the screen like the window that owns it",
      "panel:SetClampedToScreen(true)" in DROP)

check("a click on another column's caret opens that filter rather than only "
      "closing this one",
      'other:GetScript("OnClick")(other, mouseButton)' in DROP)

check("the catcher forwards left clicks only, since carets are left-click",
      'if mouseButton == "LeftButton" then' in DROP)

check("and every caret registers itself so the catcher can find it",
      "table.insert(buttons, button)" in DROP)

check("ticking a box no longer closes the panel",
      "view.feedHeader:Hide()\n        view.filterBar:Hide()" in MAIN
      and "    view.feedHeader:Hide()\n\n    -- A panel owns" not in MAIN)


print()
print("FAILURES: " + (", ".join(FAILURES) if FAILURES else "none"))
sys.exit(1 if FAILURES else 0)
