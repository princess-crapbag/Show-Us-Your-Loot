# -*- coding: utf-8 -*-
"""The raid-night pane: what it says today, and what it should say.

Drawn at the real 866px width from her own recorded nights - 2026-08-18,
2026-08-20 and 2026-08-22 - with every number computed from her saved
variables rather than invented. Nothing here is illustrative; if a figure is
wrong in this picture it is wrong in the addon.

SECOND PASS, after her notes on the first. What changed and why:

  TIMES ARE 12-HOUR WITH A ZONE. Her preference, and she is in Mountain. The
  zone label matters because a raid night is a wall-clock thing people
  remember - "we started at 6:30" - and 18:42 does not read as that.

  BOSSES ARE OVER THE RAID'S TOTAL, not over the bosses engaged. Her call:
  "there are 8 bosses in the venomous abyss but i realize we only pulled 6, 5
  of which we killed. i think it probably makes the most sense to say 5 of 8".
  So the denominator is what the instance holds, which is also the number an
  officer already carries in their head.

  DIFFICULTY IS IN THE HOVER, NOT THE HEADLINE. Her question: the Abyss has 8
  and the Grotto has 1, "but they can be done on normal and heroic so we
  should account for that in a way that scales well but is also clear". A
  headline of "3 of 18" would be arithmetic nobody asked for. The headline
  counts a boss once - killed at any difficulty - and the hover splits it by
  instance and difficulty, which is where a progression guild actually reads
  it.

  "DROPS THAT COUNT" IS NOW "PIECES OF LOOT". Hers.

  "WENT HOME WITH GEAR" EXCLUDES TRANSMOG. Hers: "i dont want to say someone
  went home with loot if all they got was a mog item." Need, offspec and
  greed count; mog does not. This CHANGES a number - 2026-08-20 goes from six
  people to five, because Razortongue's only item that night was a mog.

  "LONGEST FIGHT" IS NOW "MOST PULL ATTEMPTS". Hers.

  NAMES ARE IN CLASS COLOR. Hers, and Theme.GetClassColor already exists.

Writes screenshots/night-pane-redesign.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, C, GROUND, SCALE, TEXT_1, TEXT_2, TEXT_3, WARNING, WINDOW,
    ROW_ALT, SEP, over, measure, wrap,
)

# The Nights calendar is 7 cells of 122 with 2px gaps, so the pane under it is
# 866 wide. The stat panel is 152 tall today (UI/NightsPanel.lua:36).
WIDTH = 866
PAD = 10

# UI/NightStats.lua: figures are 150x34 holders on a 158px pitch.
FIGURE_PITCH = 158
FIGURE_TOP = 58

# The client's own class colors, which is what Theme.GetClassColor returns.
CLASS = {
    "DEATHKNIGHT": (196, 30, 58), "DEMONHUNTER": (163, 48, 201),
    "DRUID": (255, 124, 10), "EVOKER": (51, 147, 127),
    "HUNTER": (170, 211, 114), "MAGE": (63, 199, 235),
    "MONK": (0, 255, 152), "PALADIN": (244, 140, 186),
    "PRIEST": (255, 255, 255), "ROGUE": (255, 244, 104),
    "SHAMAN": (0, 112, 221), "WARLOCK": (135, 136, 238),
    "WARRIOR": (198, 155, 109),
}

# Her raiders, from the 08-18 and 08-20 session rosters.
WHO = {
    "Arcangila": "HUNTER", "Camcar": "HUNTER", "Hawt": "ROGUE",
    "Jtkurayami": "PRIEST", "Looniemoonie": "PRIEST", "Niwmn": "DEATHKNIGHT",
    "Phreestyle": "SHAMAN", "Pringlesbop": "PALADIN", "Rakahasa": "SHAMAN",
    "Razortongue": "WARRIOR", "Saebie": "DEMONHUNTER", "Syzzlac": "WARLOCK",
    "Misothelioma": "MAGE",
}


def name_color(who):
    return CLASS.get(WHO.get(who, ""), TEXT_2)


def figure(c, index, value, label, color=TEXT_1, row=0):
    x = PAD + index * FIGURE_PITCH
    y = FIGURE_TOP + row * 38

    c.text(x, y, value, 12, color)
    c.text(x, y + 17, label, 11, TEXT_3)


def pane(img, ox, oy, height, draw):
    c = C(img, ox, oy)
    c.rect(0, 0, WIDTH, height, ROW_ALT)
    draw(c)
    return height


def names_line(c, x, y, people, size=10):
    """A comma list in class color, wrapped by the caller."""
    for n, who in enumerate(people):
        text = who + ("," if n < len(people) - 1 else "")
        c.text(x, y, text, size, name_color(who))
        x += measure(text + " ", size)
    return x


# --------------------------------------------------------------------------
# What it says today
# --------------------------------------------------------------------------

def today_0818(c):
    c.text(PAD, 10, "08/18/2026", 12, TEXT_1)
    c.text(PAD, 32,
           "The Venomous Abyss  ·  Normal  ·  2 sessions, one night  ·  1 out",
           11, TEXT_2)

    # DRAWN WHERE THE ADDON DRAWS IT, six pixels above the first row of
    # figures - UI/NightStats.lua anchors absences at -52 and figures at -58.
    # The overlap in this picture is the overlap on screen.
    c.text(PAD, 50, "Out: Looniemoonie (holiday)  ·  set by Aimee", 11, TEXT_2)

    for i, (v, l, col) in enumerate([
        ("5/10", "bosses killed", WARNING), ("11", "raiders there", TEXT_1),
        ("22", "drops", WARNING), ("14", "upgrades", ACCENT),
    ]):
        figure(c, i, v, l, col)

    for i, (v, l, col) in enumerate([
        ("2h 42m", "in the instance", WARNING),
        ("0", "went home with nothing", WARNING),
        ("50%", "of pulls killed", WARNING),
        ("2.0", "drops per raider", WARNING),
    ]):
        figure(c, i, v, l, col, row=1)


TODAY_FAULTS = [
    ("5/10 bosses killed",
     "5 kills over 10 PULLS. The Venomous Abyss holds 8 bosses; they pulled "
     "6 and killed 5. Ten was never a number of bosses."),
    ("22 drops",
     "Every drop with that calendar date. 11 of the 22 are from the 5:05pm "
     "LFR run this same panel excluded for being 2% guild."),
    ("14 upgrades",
     "Reads the raw roll state. Never asks DropRules, so no bind-on-equip "
     "test and no guild-night test - and it ignores all 16 of her hand-made "
     "credit corrections."),
    ("2h 42m in the instance",
     "Not the instance. First pull to last pull of one session. They were in "
     "at 6:30 and the first pull was 6:42."),
    ("0 went home with nothing",
     "max(0, 11 raiders - 14 upgrades). Items subtracted from people, then "
     "clamped so the negative never showed."),
    ("50% of pulls killed",
     "Figure one's two numbers divided. It reads backwards too - 50% on the "
     "night they cleared five bosses, 17% on the night they killed three."),
    ("2.0 drops per raider",
     "22/11, and half the 22 is LFR loot."),
]


# --------------------------------------------------------------------------
# What it should say
# --------------------------------------------------------------------------

def proposed(heading, subheading, people, figures, story):
    """The people line moved UNDER the figures.

    Today UI/NightStats.lua anchors the absences region at -52 and the first
    row of figures at -58, six pixels apart, and the absence text wraps. On a
    night with two people out it draws straight through the figures.
    """
    def draw(c):
        c.text(PAD, 10, heading, 12, TEXT_1)
        c.text(PAD, 32, subheading, 11, TEXT_2)

        for index, (value, label, color) in enumerate(figures):
            figure(c, index, value, label, color)

        c.rect(PAD, 104, WIDTH - PAD * 2, 1, SEP)

        x = PAD
        for label, who, color in people:
            c.text(x, 112, label, 11, color)
            x += measure(label + " ", 11)

            if who:
                c.text(x, 112, who, 11, name_color(who))
                x += measure(who, 11) + 24

        c.right(WIDTH - PAD, 112, story, 10, TEXT_3)

    return draw


P_0818 = proposed(
    "08/18/2026",
    "The Venomous Abyss  ·  Normal  ·  12 of 12 guild  ·  "
    "6:42 - 9:24 PM MST  ·  2h 42m",
    [("Out:", "Looniemoonie", TEXT_2), ("Never came:", "Saebie", WARNING)],
    [("5 of 8", "bosses down", TEXT_1),
     ("11", "raiders there", TEXT_1),
     ("11", "pieces of loot", TEXT_1),
     ("6 of 11", "went home with gear", ACCENT)],
    "Most pull attempts: Vashnik the Malignant, 3   ·   "
    "hover any figure for the names",
)

P_0820 = proposed(
    "08/20/2026",
    "Tidebound Grotto, Venomous Abyss  ·  Normal and Heroic  ·  13 of 13 guild"
    "  ·  6:37 - 9:11 PM MST  ·  2h 34m",
    [("Nobody marked out, and everyone on the team came", None, TEXT_3)],
    [("3 of 9", "bosses down", TEXT_1),
     ("13", "raiders there", TEXT_1),
     ("7", "pieces of loot", TEXT_1),
     ("5 of 13", "went home with gear", ACCENT)],
    "Most pull attempts: The Coiled Altar, 11 of the night's 17   ·   "
    "hover any figure for the names",
)


def p_0822(c):
    """A recorded raid the panel refuses to call a night. Today it vanishes."""
    c.text(PAD, 10, "08/22/2026", 12, TEXT_1)
    c.text(PAD, 32,
           "The Venomous Abyss  ·  Normal  ·  1 of 33 guild  ·  "
           "12:24 - 1:01 PM MST  ·  37m", 11, TEXT_2)

    c.text(PAD, 58, "Not a guild night, so nothing here counts.", 11, WARNING)
    c.text(PAD, 76,
           "Seven pulls on Ula'tek, no kill. Recorded, and kept out of every "
           "fairness figure because only one of the 33 people there was in "
           "the guild.", 10, TEXT_3)
    c.text(PAD, 94,
           "Today this day draws \"Pick a shaded day\" and the evening is "
           "invisible.", 10, TEXT_3)


# --------------------------------------------------------------------------
# The calendar cells
# --------------------------------------------------------------------------

# Her note: "can the color on the calendar be different from the guild raid
# days? id prefer the guild raids to standout and the non guild raids blend in
# more." So a guild night keeps the accent edge it has; a recorded raid that
# is not a guild night gets a muted dotted edge and no fill - present, but not
# competing.
CELL_W = 122
CELL_H = 96


def calendar_strip(img, ox, oy):
    c = C(img, ox, oy)

    # Her real week. Each guild night carries its own figures; a recorded
    # raid that is not a guild night carries only enough to say it happened.
    days = [
        ("17", None, None),
        ("18", "guild", ["5 of 8 down", "11 raiders", "11 loot"]),
        ("19", None, None),
        ("20", "guild", ["3 of 9 down", "13 raiders", "7 loot"]),
        ("21", None, None),
        ("22", "other", ["not a guild", "night", "7 pulls"]),
        ("23", "other", ["not a guild", "night", "9 loot"]),
    ]

    for index, (label, kind, lines) in enumerate(days):
        x = index * (CELL_W + 2)

        if kind == "guild":
            c.rect(x, 0, CELL_W, CELL_H, over((0.55, 0.85, 1.00, 0.10), WINDOW))
            c.rect(x, 0, CELL_W, 2, ACCENT)
        elif kind == "other":
            c.rect(x, 0, CELL_W, CELL_H, over((1, 1, 1, 0.03), WINDOW))
            for dot in range(0, CELL_W, 6):
                c.rect(x + dot, 0, 3, 1, SEP)
        else:
            c.rect(x, 0, CELL_W, CELL_H, over((1, 1, 1, 0.02), WINDOW))

        c.text(x + 8, 8, label, 11,
               TEXT_1 if kind == "guild" else TEXT_3)

        for n, line in enumerate(lines or []):
            c.text(x + 8, 30 + n * 14, line, 10,
                   TEXT_2 if (kind == "guild" and n == 0) else TEXT_3)

    return CELL_H


# --------------------------------------------------------------------------
# The hovers
# --------------------------------------------------------------------------

HOVER_WIDTH = 300


def hover_bosses(c):
    c.text(10, 10, "5 of 8 bosses down", 11, TEXT_1)
    c.text(10, 30, "The Venomous Abyss  ·  Normal", 10, TEXT_3)

    rows = [
        ("Nek'zali the Soulcoiler", "killed 6:50 PM", True),
        ("Entombed Sentinels", "killed 7:12 PM", True),
        ("The Lost Explorers", "killed 7:36 PM", True),
        ("Sszorak", "killed 8:16 PM, 2 pulls", True),
        ("Vashnik the Malignant", "killed 8:56 PM, 3 pulls", True),
        ("The Twin Fangs", "2 pulls, no kill", False),
        ("Two never pulled", "", None),
    ]

    for n, (left, right, ok) in enumerate(rows):
        y = 48 + n * 15
        c.text(10, y, left, 10,
               ACCENT if ok else (WARNING if ok is False else TEXT_3))
        if right:
            c.right(HOVER_WIDTH - 10, y, right, 10, TEXT_3)

    return 48 + len(rows) * 15 + 10


def hover_bosses_0820(c):
    """The difficulty question, answered. Same night, two instances."""
    c.text(10, 10, "3 of 9 bosses down", 11, TEXT_1)

    rows = [
        ("The Tidebound Grotto", "1 of 1", None),
        ("  Nymrissa Wavecaller   Normal", "killed 6:43 PM", True),
        ("  Nymrissa Wavecaller   Heroic", "3 pulls, no kill", False),
        ("The Venomous Abyss", "2 of 8", None),
        ("  The Twin Fangs   Normal", "killed 7:36 PM", True),
        ("  The Coiled Altar   Normal", "killed 9:11 PM, 11 pulls", True),
    ]

    for n, (left, right, ok) in enumerate(rows):
        y = 32 + n * 15
        c.text(10, y, left, 10,
               ACCENT if ok else (WARNING if ok is False else TEXT_2))
        if right:
            c.right(HOVER_WIDTH - 10, y, right, 10, TEXT_3)

    c.text(10, 32 + len(rows) * 15 + 6,
           "A boss counts once, at any difficulty.", 10, TEXT_3)

    return 32 + len(rows) * 15 + 26


def hover_raiders(c):
    c.text(10, 10, "11 raiders there", 11, TEXT_1)

    there = [["Arcangila", "Camcar", "Hawt"],
             ["Jtkurayami", "Misothelioma", "Niwmn"],
             ["Phreestyle", "Pringlesbop", "Rakahasa"],
             ["Razortongue", "Syzzlac"]]

    for n, row in enumerate(there):
        names_line(c, 10, 32 + n * 15, row)

    y = 32 + len(there) * 15 + 10

    c.text(10, y, "Out", 10, TEXT_3)
    names_line(c, 40, y, ["Looniemoonie"])

    c.text(10, y + 15, "Never came", 10, WARNING)
    names_line(c, 78, y + 15, ["Saebie"])

    return y + 40


def hover_gear(c):
    c.text(10, 10, "6 of 11 went home with gear", 11, TEXT_1)

    c.text(10, 32, "Got gear", 10, ACCENT)
    got = [["Arcangila", "Jtkurayami", "Phreestyle"],
           ["Pringlesbop", "Rakahasa", "Razortongue"]]
    for n, row in enumerate(got):
        names_line(c, 10, 48 + n * 15, row)

    y = 48 + len(got) * 15 + 8
    c.text(10, y, "Nothing", 10, WARNING)
    nothing = [["Camcar", "Hawt", "Misothelioma"], ["Niwmn", "Syzzlac"]]
    for n, row in enumerate(nothing):
        names_line(c, 10, y + 16 + n * 15, row)

    y = y + 16 + len(nothing) * 15 + 6
    c.text(10, y, "Need, offspec and greed. A mog does not count.", 10, TEXT_3)

    return y + 20


HOVERS = [hover_bosses, hover_bosses_0820, hover_raiders, hover_gear]


def hover(img, ox, oy, draw):
    probe = Image.new("RGB", (HOVER_WIDTH * SCALE, 600 * SCALE), GROUND)
    height = draw(C(probe, 0, 0))

    c = C(img, ox, oy)
    c.rect(0, 0, HOVER_WIDTH, height, WINDOW)
    c.rect(0, 0, HOVER_WIDTH, 1, ACCENT)
    draw(c)

    return height


# --------------------------------------------------------------------------
# The page
# --------------------------------------------------------------------------

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    MARGIN = 40
    W = MARGIN * 2 + WIDTH + 360
    H = 1180

    img = Image.new("RGB", (int(W * SCALE), int(H * SCALE)), GROUND)
    page = C(img, 0, 0)

    G1 = over((0.97, 0.96, 1.00, 1), GROUND)
    G3 = over((0.64, 0.61, 0.78, 1), GROUND)
    GA = over((0.55, 0.85, 1.00, 1), GROUND)
    GW = over((0.95, 0.35, 0.32, 1), GROUND)

    page.text(MARGIN, 28, "The raid night pane, as built", 15, G1)
    page.text(MARGIN, 56,
              "Built and committed. Every note applied: 12-hour times with a "
              "zone, bosses over the raid's total, difficulty in the hover, "
              "\"pieces of loot\", mog excluded from \"went home with gear\", "
              "\"most pull attempts\", and names in class color.", 10, G3)

    y = 108

    page.text(MARGIN, y - 20, "TODAY  ·  08/18/2026", 11, GW)
    pane(img, MARGIN, y, 152, today_0818)

    fy = y + 6
    for title, why in TODAY_FAULTS:
        page.text(MARGIN + WIDTH + 20, fy, title, 10, GW)
        for n, line in enumerate(wrap(why, 10, 320)):
            page.text(MARGIN + WIDTH + 20, fy + 12 + n * 11, line, 10, G3)
        fy += 12 + len(wrap(why, 10, 320)) * 11 + 6

    y += 200

    page.text(MARGIN, y - 20, "PROPOSED  ·  08/18/2026, the same night", 11, GA)
    pane(img, MARGIN, y, 132, P_0818)

    y += 176

    page.text(MARGIN, y - 20,
              "PROPOSED  ·  08/20/2026 - two instances, two difficulties. "
              "The old panel read \"3/17 bosses killed\".", 11, GA)
    pane(img, MARGIN, y, 132, P_0820)

    y += 176

    page.text(MARGIN, y - 20,
              "PROPOSED  ·  08/22/2026 - a recorded raid that is not a guild "
              "night. Today this day shows nothing at all.", 11, GA)
    pane(img, MARGIN, y, 116, p_0822)

    y += 160

    page.text(MARGIN, y - 20,
              "THE CALENDAR - guild nights keep the accent edge; a recorded "
              "raid that is not one blends back", 11, GA)
    calendar_strip(img, MARGIN, y)

    y += 130

    page.text(MARGIN, y - 20, "THE HOVERS - names in class color", 11, GA)

    hx = MARGIN
    for draw in HOVERS:
        hover(img, hx, y, draw)
        hx += HOVER_WIDTH + 16

    y += 190

    for label, color, text in [
        ("MOG NOW EXCLUDED", GW,
         "This changes a number. On 08/20 Razortongue's only item was a mog, "
         "so that night goes from six people to five: \"5 of 13 went home "
         "with gear\". 08/18 is unchanged at 6 of 11 - nobody there got a mog "
         "and nothing else."),
        ("CAMCAR", GA,
         "You were right that Camcar got gear - on 08/20 (Ophidian Fangmail, "
         "Need), not 08/18. The 08/18 list is correct as drawn."),
        ("THE 6:30 GAP", G3,
         "A session opens at the FIRST PULL, not when you zone in. You were "
         "in at 6:30 and pulled at 6:42, so the pane can only honestly say "
         "6:42 unless the addon starts recording zone-in as well."),
        ("BOSSES NEVER PULLED", G3,
         "\"5 of 8\" needs the raid's total, which the addon does not store "
         "today - but Core/EncounterJournal.lua already walks every boss of "
         "every raid to build its loot-table bridge, so counting them per "
         "instance is one counter inside a loop that already runs."),
    ]:
        page.text(MARGIN, y, label, 10, color)
        for n, part in enumerate(wrap(text, 10, W - MARGIN * 2 - 190)):
            page.text(MARGIN + 190, y + n * 13, part, 10, G3)
        y += max(18, len(wrap(text, 10, W - MARGIN * 2 - 190)) * 13 + 8)

    out = (r"C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\screenshots"
           r"\night-pane-redesign.png")
    img.save(out)

    print("wrote night-pane-redesign.png", img.size)
