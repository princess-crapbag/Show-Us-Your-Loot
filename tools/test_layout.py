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

Widths come from tools/font_metrics.measure, which is the same font metric
UI/Theme.lua's MeasureText uses. The repo rule is that widths are measured and
never estimated, and every number below is.

That module measures for real where the game font exists and reads recorded
widths where it does not -- the release workflow runs this suite on a Linux
runner with no WoW install, and importing the drawing scripts there crashed at
the import and would have taken the release with it. See its header.
"""
import math
import re
import sys

sys.path.insert(0, "tools")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import test_load
from font_metrics import measure

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


MAIN = src("UI/MainWindow.lua")
BAR = src("UI/FilterBar.lua")
THEME = src("UI/Theme.lua")

SMALL = 11        # Theme.sizes.rowSmall
HEADER = 10       # Theme.sizes.columnHeader

# READ, NOT TYPED. The filter bar and the footer both draw at this size, and
# a test carrying its own copy of it would keep passing while the rows it
# checks were drawn at something else.
CONTROL = number(THEME, r"    control = (\d+),",
                 "Theme.sizes.control")

SUBTITLE = CONTROL   # what the count line is drawn at

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

date_width = max(measure("MM-DD-YYYY", CONTROL),
                 measure("0000-00-00", CONTROL)) + INPUT_INSET + CARET_ROOM

x = BAR_INSET + SEARCH_WIDTH
FROM_START = x + 10 + measure("From", CONTROL) + 2 + 4

for label in ("From", "To"):
    x += 10 + measure(label, CONTROL) + 2 + 4 + date_width

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

# THE WHOLE ROW AT ONE SIZE. Aimee asked for the top row and the button row
# smaller "so we dont risk issues" -- if one control keeps the old size the
# clearances below are computed against a string that is not what is drawn.
check("the search box draws at the control size",
      "editBox:SetFont(Theme.GetFontPath(), Theme.sizes.control" in BAR)

check("so does its placeholder",
      "Theme.CreateText(holder, Theme.sizes.control" in BAR)

check("so do the From and To labels",
      "local label = Theme.CreateText(parent, Theme.sizes.control" in BAR)

check("and the date boxes are measured at the size they are drawn",
      "Theme.MeasureText(Theme.sizes.control, DATE_PLACEHOLDER)" in BAR)

check("Clear's label comes down with the rest of the row",
      "Theme.SetTextSize(clearButton.label, Theme.sizes.control)" in BAR)

check("and so does the count line",
      "Theme.CreateText(parent, Theme.sizes.control" in MAIN)

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

# Every label each button can ever hold. Sized to only the opening one, each
# of these truncates the moment it is pressed.
ACTION_LABELS = [
    ("Select all", ("Select all",)),
    ("Deselect all", ("Deselect all",)),
    ("Ignore", ("Ignore", "Restore")),
    ("Hide", ("Hide", "Unhide")),
    ("Hide all", ("Hide all",)),
]

TOGGLE_LABELS = [
    ("Show hidden", ("Show hidden", "Hidden only")),
    ("All content", ("All content", "Raids only", "Dungeons only")),
    ("Gear only", ("Gear only", "Everything")),
    ("All seasons", ("All seasons", "This season")),
]

# NO LITERAL WIDTHS LEFT. Every footer button is sized by Theme.SizeToLabels
# from the labels it can hold, so the test does the same arithmetic the code
# does rather than reading numbers back out of it.
PADDING = number(THEME, r"Theme\.BUTTON_PADDING = (\d+)", "BUTTON_PADDING")


def sized(labels):
    return math.ceil(max(measure(one, CONTROL) for one in labels)) + PADDING


check("the footer sizes its buttons from their labels rather than from typed "
      "numbers",
      "Theme.SizeToLabels(control, labels)" in SEL)

# THE SIZING TABLE ITSELF, not the file. Every one of these labels also
# appears in the SetText call that swaps it, so searching the whole file
# proved nothing -- deleting a label from the table left the test passing.
block = re.search(r"for control, labels in pairs\(\{(.*?)\}\) do", SEL, re.S)

check("the sizing table is where the test thinks it is", block is not None)

# COMMENTS STRIPPED. The table carries a note explaining which label is the
# real one, and with the note left in, deleting the label from the table still
# satisfied the search -- a check passing on its own explanation.
SIZING = " ".join(
    line.split("--")[0] for line in (block.group(1) if block else "").splitlines())

for name, labels in ACTION_LABELS + TOGGLE_LABELS:
    for one in labels:
        check("'" + name + "' declares the label '" + one + "'",
              '"' + one + '"' in SIZING)

# And the other direction: anything the bar actually puts in a label has to
# be in that table, or the button was sized without it.
#
# Scanned to the matching paren rather than matched as one line, because the
# interesting ones are inside a conditional -- SetText(x == y and "Unhide" or
# "Hide") -- and those are exactly the labels a button gets sized without.
def set_labels(text):
    found = set()

    for start in [m.end() for m in re.finditer(r"label:SetText\(", text)]:
        depth, i = 1, start

        while i < len(text) and depth > 0:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            i += 1

        found.update(re.findall(r'"([^"]+)"', text[start:i]))

    return found


# Strings compared against are not labels -- SetText(scope == "raid" and
# "Raids only" ...) holds both the answer and the thing being asked about.
compared = set(re.findall(r'== "([^"]+)"', SEL))

spoken = set_labels(SEL) - compared

check("the label scan found the conditional ones too",
      "Unhide" in spoken and "Restore" in spoken
      and "Hidden only" in spoken,
      "found %r" % sorted(spoken))

check("and dropped the values that are only compared against",
      "raid" not in spoken and "dungeon" not in spoken,
      "found %r" % sorted(spoken))

for one in sorted(spoken):
    check("the label '" + one + "' is one the buttons were sized for",
          '"' + one + '"' in SIZING)

# Left chain: flows right from 16 in 6px steps.
x = 16
for name, labels in ACTION_LABELS:
    x += sized(labels) + 6

LEFT_END = x - 6

# Right chain: flows left from Close.
r = WINDOW_WIDTH - 16 - CLOSE_WIDTH

for name, labels in TOGGLE_LABELS:
    r -= 6 + sized(labels)

gap("the action group does not reach the toggles", LEFT_END, r)

check("and does so with real headroom, not by a pixel",
      r - LEFT_END >= 60, "%d px" % (r - LEFT_END))

check("Close's label is the same size as the row it sits on",
      "Theme.SetTextSize(closeButton.label, Theme.sizes.control)" in FOOTER)

check("and so are the archives bar's buttons",
      "Theme.SetTextSize(control.label, Theme.sizes.control)"
      in src("UI/ArchiveControls.lua"))

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


# ==========================================================================
# The Raiders tab's button row
# ==========================================================================
#
# RAIDERS, then four buttons chained off each other and off the title, all of
# them sitting over the board rather than over the detail pane beside it. This
# row had never been checked, and a fourth button was added to it -- which is
# the shape every overlap in this file started as: a chain that reads correctly
# and has never had its right-hand end resolved.
#
# The title is measured rather than assumed. RAIDERS is a fixed string, but it
# is drawn at Theme.sizes.title and the whole chain hangs off its right edge,
# so a font change moves all four buttons.

print("-- raiders tab, button row " + "-" * 49)

PANEL = src("UI/RaidersPanel.lua")

TITLE = number(THEME, r"    title = (\d+),", "Theme.sizes.title")

DETAIL_WIDTH = number(PANEL, r"local DETAIL_WIDTH = (\d+)", "DETAIL_WIDTH")
GUTTER = number(PANEL, r"local GUTTER = (\d+)", "GUTTER")
PANE_WIDTH = number(PANEL, r"local BOARD_WIDTH = (\d+) - DETAIL_WIDTH",
                    "the pane width")

BOARD_WIDTH = PANE_WIDTH - DETAIL_WIDTH - GUTTER

TITLE_X = 2
TITLE_END = TITLE_X + measure("RAIDERS", TITLE)


def button(pattern, name):
    """The width and the label of one Theme.CreateButton call."""
    found = re.search(pattern, PANEL)

    if not found:
        FAILURES.append("could not read " + name)
        print("FAIL could not read " + name)
        return 0, ""

    return int(found.group(1)), found.group(2)


# The audience button's label is not the string in the source -- it is
# relabelled on every refresh from Audience.LABELS -- so the widest of those is
# what has to fit, not "Raid team".
AUDIENCE_W, _ = button(
    r'CreateButton\(frame, (\d+), 20, "(Raid team)"', "audienceButton")
VIEW_W, _ = button(r'CreateButton\(frame, (\d+), 20, "(Board)"', "viewButton")
ARCHIVED_W, ARCHIVED_LABEL = button(
    r'CreateButton\(frame, (\d+), 20, "(Archived)"', "archivedButton")
ROSTER_W, ROSTER_LABEL = button(
    r'CreateButton\(frame, (\d+), 20, "(Full roster)"', "rosterButton")

# The anchor chain, resolved the way the client would: each button hangs off
# the right edge of the one before it, by the offset written in the source.
x = TITLE_END + 14
AUDIENCE_END = x + AUDIENCE_W

x = AUDIENCE_END + 10
VIEW_END = x + VIEW_W

x = VIEW_END + 8
ARCHIVED_END = x + ARCHIVED_W

x = ARCHIVED_END + 8
ROSTER_END = x + ROSTER_W

check("the four Raiders buttons fit beside the board",
      ROSTER_END <= BOARD_WIDTH,
      "the row ends at %.1f, board is %d wide" % (ROSTER_END, BOARD_WIDTH))

# The stricter half of the same question. Ending inside the board is what
# keeps the row off the bars; ending inside the pane is what keeps it out from
# under the detail pane, which is drawn over the top.
check("and clear of the detail pane",
      ROSTER_END <= PANE_WIDTH - DETAIL_WIDTH,
      "%.1f against a pane edge at %d"
      % (ROSTER_END, PANE_WIDTH - DETAIL_WIDTH))

# Every label inside its own button. A button 110 wide with a label of 112 is
# not an overlap and still reads as a bug -- the text is simply cut.
LABEL_PAD = 8

for label, width in (("Raid team", AUDIENCE_W), ("Everyone", AUDIENCE_W),
                     ("Board", VIEW_W), ("Roster", VIEW_W),
                     (ARCHIVED_LABEL, ARCHIVED_W),
                     (ROSTER_LABEL, ROSTER_W)):
    check('"%s" fits its button' % label,
          measure(label, SMALL) + LABEL_PAD <= width,
          "%.1f in %d" % (measure(label, SMALL) + LABEL_PAD, width))


# ==========================================================================
# The roster window's action bar
# ==========================================================================
#
# Eight controls chained left to right along the bottom, and a Close button
# anchored to the right-hand end of the same line. The chain used to end two
# pixels short of Close -- six chosen widths carrying 30 to 62 pixels of slack
# each -- so the bar was one control away from drawing underneath the one
# button every window has. The widths are measured now; this is the arithmetic
# that says the whole row still lands clear.

print("-- roster window, action bar " + "-" * 47)

CONTROLS = src("UI/RosterControls.lua")
ROSTER = src("UI/RosterWindow.lua")

R_WIDTH = number(ROSTER, r"local WINDOW_WIDTH = (\d+)", "roster WINDOW_WIDTH")
R_INSET = 16

ACTION_PAD = number(CONTROLS, r"local LABEL_PAD = (\d+)", "LABEL_PAD")

CLOSE_W = number(ROSTER, r'CreateButton\(frame, (\d+), 26, "Close"',
                 "roster Close")

# Read off the source so a renamed or reordered button moves this with it,
# rather than leaving the test asserting about a bar that no longer exists.
ACTION_LABELS = re.findall(r'ActionButton\(frame, "([^"]+)"', CONTROLS)

check("the action bar is built from measured buttons",
      len(ACTION_LABELS) == 7,
      "found %d: %s" % (len(ACTION_LABELS), ACTION_LABELS))

check("and Archive is one of them",
      "Archive" in ACTION_LABELS, ACTION_LABELS)

MAIN_INPUT_W = number(CONTROLS, r"SearchBox.Create\(\n?\s*frame, (\d+), \"Alt of whom",
                      "the alt-of input")

# The chain, in source order, with the gap that precedes each. The two 12s are
# the deliberate breaks either side of the alt-of input -- it is an argument to
# the button after it, not another action.
GAPS = {"Add to team": 0, "Remove": 6, "Archive": 6,
        "Alt of": 6, "Not an alt": 6, "Same character": 6, "Untick all": 12}

x = R_INSET

for label in ACTION_LABELS:
    x += GAPS[label]
    x += measure(label, SMALL) + ACTION_PAD

    # The alt-of input sits between Archive and Alt of, and is the argument to
    # the button that follows it.
    if label == "Archive":
        x += 12 + MAIN_INPUT_W

ACTIONS_END = x
CLOSE_START = R_WIDTH - R_INSET - CLOSE_W

gap("the roster action bar clears the Close button", ACTIONS_END, CLOSE_START)

# Not just "does not overlap". Two pixels is what it had before and it was one
# button away from breaking, so this asserts there is somewhere to put the
# next one.
check("with room left for another control",
      CLOSE_START - ACTIONS_END >= 24,
      "%.1f of clearance" % (CLOSE_START - ACTIONS_END))


print()
print("FAILURES: " + (", ".join(FAILURES) if FAILURES else "none"))
sys.exit(1 if FAILURES else 0)
