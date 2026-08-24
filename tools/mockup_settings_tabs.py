# -*- coding: utf-8 -*-
"""The settings window in five tabs, drawn from her real settings.

THIS IS THE APPROVED SPEC for the settings redesign -- Aimee, on the
picture it produces: "i love it." Kept in tools/ rather than a session
scratchpad because the redesign is half built and whoever finishes it
needs to be able to re-render a tab after changing it. tools/ is already
excluded from the addon zip by .pkgmeta.

Writes screenshots/settings-five-tabs.png.

RE-RENDERED 2026-08-23 EVENING, after the redesign was finished, so the
picture and the addon agree again. Three things moved away from the drawing
Aimee approved that morning, and each one is marked NEW or noted below:

  /syl clear is OUT of the Tools list and into a danger block of its own, with
  the client's alert icon, an explanation in short words, and a dialog that
  will not act until the season's name has been typed. Aimee: "dont make it a
  normal button. or make it harder to do. [...] give an explanation of what it
  does so they youngest user can understand."

  The Raiders board gets a row. It is the headline screen of this addon and it
  had no door of its own anywhere -- the drawing listed "Roster", which is the
  standalone roster window, a different screen. Both are listed now.

  "Who the boards show" carries the current scope in its label, because a row
  that cycles a setting without showing it is one you press twice to find out
  where you started.

Item types are drawn all ticked, which is what a real install shows: the
default records everything, so that an addon upgrading from 0.4.0 captures
exactly what it captured yesterday.

Real width (560), real row height (20), real headings (18), real section gap
(24), real Nightfall palette composited the way the client composites it, real
game font. Her own switches: only Epic and Heirloom qualities are recorded,
all twelve features on, all seven dashboard widgets on, rank floor Off, guild
share 80%.

The three answers she gave this morning are built in:

  WEIGHTS ARE EDITABLE, with the caution said on the tab rather than buried.
  THE GUILD THRESHOLD IS A REAL SETTING, not the constant it is today.
  HOUSING DECOR IS A REAL ROW -- Enum.ItemClass.Housing, class 20, confirmed
  against five addons already installed on her machine rather than guessed.

And the fourth thing, which is hers too: "leave the 4 weights, i only want to
see the 3 for me if possible." Three rows show. Offspec is the fourth weight
and it stays -- linked to Greed, so it cannot silently drift from what she can
see. Unlink it and a fourth row appears. Her season has 16 offspec rolls and
zero offspec wins, so today the row would only be noise; the link is what
makes hiding it safe rather than merely tidy.
"""
import io
import json
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = (r"C:\Program Files (x86)\World of Warcraft\_retail_"
        r"\Interface\AddOns\DialogueUI\Fonts\frizqt__.ttf")

SCALE = 2

WIDTH = 560
PAD = 24
CONTENT = WIDTH - PAD * 2          # 512, what the sections lay out inside

ROW = 20
HEADING = 18
GAP = 24
NOTE = 30

GROUND = (18, 15, 30)


def over(rgba, under):
    r, g, b, a = rgba
    return tuple(int(round((c * 255) * a + u * (1 - a)))
                 for c, u in zip((r, g, b), under))


WINDOW = over((0.170, 0.145, 0.275, 0.97), GROUND)
TEXT_1 = over((0.97, 0.96, 1.00, 1), WINDOW)
TEXT_2 = over((0.82, 0.79, 0.92, 1), WINDOW)
TEXT_3 = over((0.64, 0.61, 0.78, 1), WINDOW)
ACCENT = over((0.55, 0.85, 1.00, 1), WINDOW)
ACCENT_DIM = over((0.55, 0.85, 1.00, 0.22), WINDOW)
WARNING = over((0.95, 0.35, 0.32, 1), WINDOW)
SEP = over((1, 1, 1, 0.15), WINDOW)
ROW_ALT = over((1, 1, 1, 0.05), WINDOW)
BUTTON = over((1, 1, 1, 0.12), WINDOW)
HEADER_BAR = over((0.220, 0.190, 0.340, 1), WINDOW)

QUALITY_COLOR = {
    "Poor (gray)": (157, 157, 157), "Common (white)": (255, 255, 255),
    "Uncommon (green)": (30, 255, 0), "Rare (blue)": (0, 112, 221),
    "Epic (purple)": (163, 53, 238), "Legendary (orange)": (255, 128, 0),
    "Artifact": (230, 204, 128), "Heirloom": (0, 204, 255),
}

_fonts = {}
_ruler = ImageDraw.Draw(Image.new("RGB", (1, 1)))


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(FONT, int(round(size * SCALE)))
    return _fonts[size]


def measure(text, size):
    return _ruler.textlength(str(text), font=font(size)) / SCALE


def wrap(text, size, width):
    words, lines, cur = str(text).split(), [], ""
    for w in words:
        c = (cur + " " + w) if cur else w
        if measure(c, size) <= width or not cur:
            cur = c
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


problems = []


def check(what, width, limit):
    if width > limit + 0.01:
        problems.append("%s: %.1f over %.1f" % (what, width, limit))


class C:
    def __init__(self, img, ox, oy):
        self.d = ImageDraw.Draw(img)
        self.ox, self.oy = ox, oy

    def _p(self, x, y):
        return (int(round((self.ox + x) * SCALE)),
                int(round((self.oy + y) * SCALE)))

    def text(self, x, y, s, size, color):
        self.d.text(self._p(x, y), str(s), font=font(size), fill=color,
                    anchor="la")

    def right(self, x, y, s, size, color):
        self.text(x - measure(s, size), y, s, size, color)

    def rect(self, x, y, w, h, color):
        a, b = self._p(x, y)
        c, d = self._p(x + w, y + h)
        self.d.rectangle([a, b, c - 1, d - 1], fill=color)

    def box(self, x, y, on):
        """The 14x14 checkbox the addon already draws."""
        self.rect(x, y, 14, 14, SEP)
        self.rect(x + 1, y + 1, 12, 12, WINDOW)
        if on:
            self.rect(x + 3, y + 3, 8, 8, ACCENT)


HERE = __file__.rsplit("\\", 1)[0]

DATA = json.load(io.open(HERE + chr(92) + "mockup_settings.json",
                         encoding="utf-8"))
COMMANDS = json.load(io.open(HERE + chr(92) + "mockup_commands.json",
                             encoding="utf-8"))


def heading(c, y, text, right=None):
    c.text(PAD, y, text, 10, TEXT_3)
    if right:
        c.right(WIDTH - PAD, y, right, 10, TEXT_3)
    return y + HEADING


def grid(c, y, rows, columns, cell_width=None):
    """The addon's own grid: columns across, ROW tall, left to right."""
    cell = cell_width or (CONTENT / columns)
    for index, row in enumerate(rows):
        col = index % columns
        line = index // columns
        x = PAD + col * cell
        ry = y + line * ROW

        c.box(x, ry + 3, row["on"])

        label = row["label"]
        room = cell - 24 - 6
        c.text(x + 20, ry + 4, label, 11, row.get("color") or TEXT_2)
        check("grid label '%s'" % label[:18], measure(label, 11), room)

    lines = (len(rows) + columns - 1) // columns
    return y + lines * ROW


def note(c, y, text, color=TEXT_3):
    for n, line in enumerate(wrap(text, 10, CONTENT)):
        c.text(PAD, y + n * 12, line, 10, color)
    return y + len(wrap(text, 10, CONTENT)) * 12 + 6


def value_row(c, y, label, value):
    """A cycling setting: label on the left, value and a chevron on the right."""
    c.text(PAD, y + 4, label, 11, TEXT_2)
    chev = "  >"
    c.right(WIDTH - PAD, y + 4, value + chev, 11, ACCENT)
    return y + ROW


def number_row(c, y, label, value, hint=None):
    """An editable number: the field is a box you type in."""
    c.text(PAD, y + 4, label, 11, TEXT_2)

    box_w = 54
    bx = WIDTH - PAD - box_w

    c.rect(bx, y + 2, box_w, 16, ROW_ALT)
    c.rect(bx, y + 2, 1, 16, ACCENT_DIM)
    c.right(bx + box_w - 6, y + 4, str(value), 11, TEXT_1)

    if hint:
        c.right(bx - 10, y + 5, hint, 10, TEXT_3)

    return y + ROW


# --------------------------------------------------------------------------
# The five tabs
# --------------------------------------------------------------------------

TABS = ["Recording", "Scoring", "Features", "Display", "Tools"]

# NEW on Recording. Housing is Enum.ItemClass.Housing = 20, confirmed against
# RCLootCouncil, Auctionator, Syndicator, EllesmereUIBags and WilduTools --
# all installed here, all keying on the same constant. It was the one row the
# 08-19 proposal could not verify.
# Order and labels read straight off Core/ItemTypes.ORDER and .NAMES.
# All ticked, because that is the default and the default is deliberate.
ITEM_TYPES = [
    {"label": "Raid gear", "on": True},
    {"label": "Warbound gear", "on": True},
    {"label": "Pets", "on": True},
    {"label": "Mounts", "on": True},
    {"label": "Toys", "on": True},
    {"label": "Housing decor", "on": True},
    {"label": "Profession supplies", "on": True},
    {"label": "Quest items", "on": True},
    {"label": "Sparks and hides", "on": True},
]


def tab_recording(c, y):
    y = heading(c, y, "RECORD THESE ITEM QUALITIES")

    rows = [dict(r, color=QUALITY_COLOR.get(r["label"], TEXT_2))
            for r in DATA["qualities"]]

    y = grid(c, y, rows, 3) + GAP

    y = heading(c, y, "RECORD THESE ITEM TYPES", "NEW")
    y = grid(c, y, ITEM_TYPES, 3)
    y = note(c, y + 4,
             "Unticked types and qualities are never recorded. Neither "
             "removes records you already have.") + 6

    y = heading(c, y, "CAPTURE")
    y = grid(c, y, [
        {"label": "Record group loot from Loot History", "on": True},
        {"label": "Announce gear in chat", "on": True},
    ], 1)

    # THIS SENTENCE WAS BEING DRAWN ON EVERY TAB, 244px down, at an offset
    # computed for the single scrolling column that no longer exists. It
    # shipped that way in 7efaad7. It belongs here, under the heading about
    # what gets recorded.
    y = note(c, y + 4,
             "Your client only sees other people's loot while you are grouped "
             "with them, so counting gear taken without a roll mostly counts "
             "yours.")

    return y


def tab_scoring(c, y):
    y = heading(c, y, "FAIRNESS")

    y = value_row(c, y, "Rank raiders after",
                  "their first night" if DATA["floor"] == 0
                  else "%d nights" % DATA["floor"])
    y = number_row(c, y, "Count a night as the guild's at",
                   "%d%%" % round(DATA["guildShare"] * 100), "NEW")

    y = note(c, y + 4,
             "The threshold decides which nights count at all -- attendance, "
             "the calendar, and since 0.4.0 whether a drop scores. Raising it "
             "mid-season re-scores nights you have already raided.") + 6

    y = heading(c, y, "WHAT A WIN IS WORTH", "EDITABLE")

    y = number_row(c, y, "Need", 100)
    y = number_row(c, y, "Greed", 20, "offspec too")
    y = number_row(c, y, "Mog", 0)

    y = note(c, y + 4,
             "Your client reports offspec separately from greed. Yours are "
             "worth the same, so only one row shows and offspec follows it. "
             "Unlink them if your guild scores them differently.")

    y = grid(c, y, [{"label": "Score offspec separately", "on": False}], 1)

    y = note(c, y + 6,
             "Changing a weight re-scores every night already raided, not "
             "just the next one. Set these before a season and leave them.",
             WARNING)

    return y


def tab_features(c, y):
    y = heading(c, y, "FEATURES")
    y = grid(c, y, DATA["features"], 3)
    y = note(c, y + 6,
             "Sharing switches send to your guild. Everything you receive can "
             "be cleared from the screen it arrived on. Most need a /reload.")
    return y


def tab_display(c, y):
    y = heading(c, y, "APPEARANCE")
    y = value_row(c, y, "Color scheme", "Nightfall")
    y = value_row(c, y, "Output window", "Chat 7")
    y = grid(c, y, [
        {"label": "Show the minimap button", "on": True},
        {"label": "Show debug messages", "on": False},
    ], 1)

    y = note(c, y + 4,
             "The minimap button is the door to the command menu. Turning it "
             "off leaves the Tools tab as the only way to click most of "
             "them.") + 6

    y = heading(c, y, "DASHBOARD WIDGETS", "DEFAULT ORDER  >")
    y = grid(c, y, DATA["widgets"], 3)

    return y


# The Tools tab, grouped by what a person came looking for rather than by the
# alphabet. Every row runs the real dispatcher, so this and the minimap menu
# and /syl help can never disagree -- one list, three doors.
TOOL_GROUPS = [
    ("OPEN A SCREEN", [
        # NEW. The headline screen of this addon, and it had no door of its
        # own anywhere -- the only way to it was the tab strip on a window you
        # already had open.
        ("Raiders board", "raiders"),
        ("Players", "players"), ("Raid nights", "raids"),
        ("Who is due", "due"), ("Bosses", "bosses"),
        # Renamed from "Roster": this is the standalone window with search and
        # buff coverage, which is a different screen from the board above.
        ("Full roster", "roster"), ("Schedule", "schedule"),
        ("Keystones", "keys"), ("Export for Discord", "export"),
    ]),
    ("THIS SEASON", [
        ("Season status", "season"), ("Rename season...", "rename"),
        ("Archive and start new...", "archive"),
        ("Archived seasons", "archives"),
        # `clear` is deliberately NOT here. See the danger block below.
    ]),
    ("PEOPLE", [
        ("Mark somebody out...", "out"), ("Cancel an absence...", "in"),
        ("Alts and mains", "alts"), ("Add a recruit...", "addraider"),
        ("Remove a recruit...", "dropraider"),
        # Carries its current value, like the cycling rows on Display do.
        ("Who the boards show: Raid team", "scope"),
    ]),
    ("SHARING AND TRADES", [
        ("Sync status", "sync"), ("Trade advisor", "trade"),
        ("Dashboard links...", "link"),
    ]),
    ("REPORTS IN CHAT", [
        ("Recent drops", "drops"), ("Tonight so far", "tonight"),
        ("Command list", "help"),
    ]),
    ("IF SOMETHING GOES WRONG", [
        ("Reset window sizes", "resetwindows"),
    ]),
]

NEEDS_INPUT = {"rename", "archive", "out", "in", "link",
               "addraider", "dropraider"}


# THE DANGER BLOCK, which is what /syl clear became instead of a row.
#
# Aimee: "dont make it a normal button. or make it harder to do. make sure
# there is an explanation as to why someone should use this button and what
# will happen if they do. maybe have a danger image near it. or it can just be
# a slash command. but dont make it a normal button and give an explanation of
# what it does so they youngest user can understand."
#
# So there are four guards, and only the first two are visible here: it is
# below everything under its own warning rule beside the client's own alert
# icon, and it says in short words what goes and what to do instead. The other
# two are in the dialog it opens -- the season's name has to be typed, and the
# Erase button is dead until it matches. UI/ClearSeasonDialog.lua.
DANGER_HEADING = "ERASING A SEASON CANNOT BE UNDONE"
DANGER_LINK = "Erase this season's records..."
DANGER_NOTE = (
    "This throws away everything the addon has written down for the season "
    "you are raiding now, and you cannot get it back. Use it only if it "
    "recorded a lot you did not want. If the season is just over, use "
    "Archive and start new above -- that keeps everything."
)


def danger_block(c, y):
    c.rect(PAD, y, CONTENT, 1, WARNING)

    # The client's own alert icon, drawn here as the square it occupies.
    c.rect(PAD, y + 12, 24, 24, WARNING)

    c.text(PAD + 32, y + 16, DANGER_HEADING, 10, WARNING)
    c.text(PAD + 30, y + 33, DANGER_LINK, 11, WARNING)

    lines = wrap(DANGER_NOTE, 10, CONTENT - 32)

    for n, line in enumerate(lines):
        c.text(PAD + 32, y + 54 + n * 12, line, 10, TEXT_3)

    return y + 54 + len(lines) * 12 + 8


def tab_tools(c, y):
    y = note(c, y,
             "Every one of these also has a slash command. The command is the "
             "shortcut; this is how anybody else finds it.") + 2

    left = PAD
    col_w = CONTENT / 2
    tops = [y, y]

    # Packed into whichever column is shorter, not alternated by index --
    # the groups are nine rows and one row, so alternating put eighteen rows
    # on the left against eight on the right. Same rule as BuildGroups in
    # UI/SettingsTools.lua.
    for title, entries in TOOL_GROUPS:
        col = 0 if tops[0] <= tops[1] else 1
        x = left + col * col_w
        at = tops[col]

        c.text(x, at, title, 10, TEXT_3)
        at += HEADING - 2

        for label, cmd in entries:
            c.text(x + 6, at + 3, label, 11, TEXT_2)

            if cmd in NEEDS_INPUT:
                c.right(x + col_w - 14, at + 3, "...", 10, TEXT_3)

            check("tool '%s'" % label, measure(label, 11), col_w - 34)

            at += ROW - 2

        tops[col] = at + 10

    y = max(tops)

    return danger_block(c, y + 6)


DRAW = {
    "Recording": tab_recording, "Scoring": tab_scoring,
    "Features": tab_features, "Display": tab_display, "Tools": tab_tools,
}


# --------------------------------------------------------------------------
# The window around them
# --------------------------------------------------------------------------

CHROME_TOP = 74     # accent mark, SETTINGS, subtitle, rule
TAB_STRIP = 30
FOOTER = 46


def draw_window(img, ox, oy, active, body_height):
    c = C(img, ox, oy)

    height = CHROME_TOP + TAB_STRIP + body_height + FOOTER

    c.rect(0, 0, WIDTH, height, WINDOW)
    c.rect(0, 0, WIDTH, 3, ACCENT)

    c.text(PAD, 16, "SETTINGS", 15, TEXT_1)
    c.text(PAD, 40, "What gets recorded, and what runs at all", 10, TEXT_3)
    c.right(WIDTH - PAD, 16, "x", 12, TEXT_3)

    c.rect(PAD, 62, CONTENT, 1, SEP)

    # The tab strip, using the widget the main window already uses:
    # Theme.CreateTab, auto width, selected state as an underline.
    x = PAD

    for name in TABS:
        w = measure(name, 11) + 26
        on = name == active

        c.text(x + 13, CHROME_TOP - 6, name, 11, ACCENT if on else TEXT_3)

        if on:
            c.rect(x, CHROME_TOP + 12, w, 2, ACCENT)

        x += w

    c.rect(PAD, CHROME_TOP + 13, CONTENT, 1, SEP)

    body = C(img, ox, oy + CHROME_TOP + TAB_STRIP)
    DRAW[active](body, 0)

    c.rect(PAD, height - FOOTER + 8, CONTENT, 1, SEP)

    bw = measure("Close", 11) + 44
    c.rect(WIDTH - PAD - bw, height - 34, bw, 24, BUTTON)
    c.text(WIDTH - PAD - bw + 22, height - 29, "Close", 11, TEXT_1)

    return height


def body_height(name):
    probe = Image.new("RGB", (WIDTH * SCALE, 4000 * SCALE), GROUND)
    return DRAW[name](C(probe, 0, 0), 0) + 12


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    heights = {name: body_height(name) for name in TABS}
    totals = {n: CHROME_TOP + TAB_STRIP + heights[n] + FOOTER for n in TABS}

    MARGIN = 40
    GAP_X = 40

    top = 96
    tallest = max(totals.values())

    across = 3
    rows_of = (len(TABS) + across - 1) // across

    W = MARGIN * 2 + across * WIDTH + (across - 1) * GAP_X
    H = top + rows_of * (tallest + 76) + 150

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    G1 = over((0.97, 0.96, 1.00, 1), GROUND)
    G3 = over((0.64, 0.61, 0.78, 1), GROUND)
    GA = over((0.55, 0.85, 1.00, 1), GROUND)

    page.text(MARGIN, 28, "Settings in five tabs", 15, G1)
    page.text(MARGIN, 56,
              "Your real settings, at the real 560px width. Today it is one "
              "656px column; the tallest tab here is %d." % max(totals.values()),
              10, G3)

    for index, name in enumerate(TABS):
        col = index % across
        row = index // across

        x = MARGIN + col * (WIDTH + GAP_X)
        y = top + row * (tallest + 76)

        page.text(x, y - 20, "%d  %s" % (index + 1, name), 11, GA)
        page.right(x + WIDTH, y - 20, "%d px" % totals[name], 10, G3)

        draw_window(img, x, y, name, heights[name])

    y = top + rows_of * (tallest + 76) + 10

    for n, line in enumerate([
        "Weights are editable, with the warning on the tab rather than buried: "
        "changing one re-scores every night already raided.",
        "Three weight rows, not four. Offspec is still there and still scores "
        "-- it follows Greed unless you unlink it, so it can never drift from "
        "what you can see.",
        "Housing decor is a real filter now: Enum.ItemClass.Housing, class 20, "
        "confirmed against five addons already on your machine.",
        "The Tools tab is the second door. The minimap menu already lists 30 "
        "of the 34 commands -- but it is a checkbox, and turning it off today "
        "leaves thirteen of them unreachable by any click.",
        "Erasing a season is not a row in that list. It sits under its own "
        "warning rule with the client's alert icon and an explanation, and "
        "the dialog it opens will not do anything until the season's name has "
        "been typed into it. Archive is offered first and is the bigger of "
        "the two buttons.",
        "Three commands could not simply be wired to their own names: bosses "
        "and roster open standalone windows rather than the tabs, and due "
        "prints to chat unless you append 'window'. Scope had no click "
        "anywhere in the addon at all.",
    ]):
        for m, part in enumerate(wrap(line, 10, W - MARGIN * 2)):
            page.text(MARGIN, y + m * 14, part, 10, G3)
        y += len(wrap(line, 10, W - MARGIN * 2)) * 14 + 8

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\settings-five-tabs.png")
    img.save(out)

    print("wrote settings-five-tabs.png", img.size)
    print()
    for name in TABS:
        print("   %-10s body %3d   window %3d px" % (name, heights[name], totals[name]))
    print()
    print("   today, one column: 656 px")
    print()
    if problems:
        print("OVERFLOWS (%d):" % len(problems))
        for p in sorted(set(problems)):
            print("  ", p)
    else:
        print("no overflows")
