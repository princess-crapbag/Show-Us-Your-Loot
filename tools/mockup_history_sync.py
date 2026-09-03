# -*- coding: utf-8 -*-
"""Sending a season of loot to one officer, drawn at its real size.

WHY IT IS A WINDOW AND NOT A BUTTON ON THE LOOT TAB. The loot tab's bottom bar
already holds nine buttons and a summary sentence, and UI/SelectionBar.lua
says in its own header that there is no arrangement of nine buttons and a
sentence that fits. A tenth would land on the summary for the third time.

So this is one small window with a name to pick and one thing to press, which
is the shape RCLootCouncil's own sync frame settled on for the same reason --
a history transfer needs a target, and a target needs somewhere to choose it.
It opens from Settings -> Tools, next to "Export for Discord", because that is
the row somebody already goes to when they want data out of this addon and
into somebody else's hands.

THE ROSTER BUTTON IS NOT MOVING IN HERE. A roster is nine names and goes to
the whole guild at once, so it stays where it was drawn: on the roster screen,
next to Clear shared. This window is for the thing that takes a minute.

ALL THREE NUMBERS ARE HERS. Read out of
WTF/Account/ARCANGELA/SavedVariables/ShowUsYourLoot.lua on 2026-09-02:
Midnight Season 2, 17 raid nights, 130 drops, 52 of them carrying a
creditOverride she set by hand. Pringlesbop-Illidan is the officer whose
roster is sitting in her sharedRoster block right now.

The message count is measured too, not guessed -- Core/HistoryPayload.lua's
own encoder run over all 130 records comes to 983 messages, four minutes at
the pace the client allows. An earlier draft of this drawing said 201, which
was a header-only estimate for a design that turned out to be wrong: headers
alone arrive marked partial and Analytics skips them.

Writes screenshots/history-sync.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, ACCENT_DIM, BUTTON, C, GROUND, SCALE, SEP, TEXT_1, TEXT_2,
    TEXT_3, WINDOW, check, measure, problems, wrap,
)

W = 460
PAD = 20
CONTENT = W - PAD * 2

BUTTON_H = 18
BUTTON_PAD = 14

SEASON = "Midnight Season 2"
NIGHTS = 17
DROPS = 130
CREDITED = 52
MESSAGES = 983                     # measured: the real encoder over her 130

TARGET = "Pringlesbop"


def button(c, right_edge, y, label, width=None, muted=False):
    w = width or int(round(measure(label, 11) + BUTTON_PAD * 2))
    x = right_edge - w

    c.rect(x, y, w, BUTTON_H, BUTTON)
    c.text(x + (w - measure(label, 11)) / 2, y + 3, label, 11,
           TEXT_3 if muted else TEXT_1)
    check("button '%s'" % label, measure(label, 11), w - 8)

    return x


def title(c, y, text):
    c.text(PAD, y, text, 15, TEXT_1)
    check("title '%s'" % text[:20], measure(text, 15), CONTENT)
    y += 26
    c.rect(PAD, y, CONTENT, 1, SEP)
    return y + 12


def paragraphs(c, y, lines, size=11, color=TEXT_2):
    for para in lines:
        for line in wrap(para, size, CONTENT):
            c.text(PAD, y, line, size, color)
            y += 15
        y += 8
    return y


def heading(c, y, text):
    c.text(PAD, y, text, 10, TEXT_3)
    return y + 16


def field(c, y, label, value, caret=False):
    """A picked value, drawn the way the addon draws a cycling control: a
    boxed value with its label above it, not a Blizzard dropdown."""
    c.text(PAD, y, label, 10, TEXT_3)
    y += 15

    width = 200
    c.rect(PAD, y, width, 20, BUTTON)
    c.text(PAD + 8, y + 4, value, 11, TEXT_1)

    if caret:
        c.right(PAD + width - 8, y + 4, "v", 11, TEXT_3)

    check("field value '%s'" % value, measure(value, 11), width - 28)

    return y + 20, PAD + width


def bar(c, y, fraction, text):
    c.rect(PAD, y, CONTENT, 14, BUTTON)
    c.rect(PAD, y, int(CONTENT * fraction), 14, ACCENT_DIM)
    c.text(PAD + (CONTENT - measure(text, 11)) / 2, y + 1, text, 11, TEXT_1)
    return y + 14


# --------------------------------------------------------------- panel one

IDLE_BODY = [
    "Sends this season's drops to one person, with the credit you set by "
    "hand on them. Their board then scores the same items the same way "
    "yours does.",
    "It goes to them and to nobody else, and they are asked before any of "
    "it arrives.",
]


def draw_idle(c):
    y = title(c, 16, "Send loot history")
    y = paragraphs(c, y, IDLE_BODY)

    y += 2
    y = heading(c, y, "WHAT GOES")

    for line in [
        SEASON + "  ·  " + str(NIGHTS) + " raid nights",
        str(DROPS) + " drops, with who won each one and who rolled",
        str(CREDITED) + " of them carrying credit you set by hand",
    ]:
        c.text(PAD, y, line, 11, TEXT_2)
        check("what-goes line", measure(line, 11), CONTENT)
        y += 17

    y += 4
    c.text(PAD, y, str(MESSAGES) + " messages, about four minutes at the "
           "pace the client allows", 11, TEXT_3)
    y += 22

    y, _ = field(c, y, "SEND TO", TARGET, caret=True)
    y += 6
    c.text(PAD, y, "guild members who are online right now", 10, TEXT_3)
    y += 24

    c.rect(PAD, y, CONTENT, 1, SEP)
    y += 14

    left = button(c, W - PAD, y, "Close")
    button(c, left - 8, y, "Send")

    return y + BUTTON_H + PAD


# --------------------------------------------------------------- panel two

def draw_sending(c):
    y = title(c, 16, "Send loot history")
    y = paragraphs(c, y, [
        "Going out to " + TARGET + " now. Four messages a second is the "
        "pace the client allows without throwing them away, so a season "
        "takes about four minutes.",
        "Closing this window does not stop it.",
    ])

    y += 6
    y = heading(c, y, "SENDING")

    y = bar(c, y, 0.48, "48%  ·  472 of " + str(MESSAGES) + " messages")
    y += 8
    c.text(PAD, y, "about 2 minutes left", 11, TEXT_3)
    y += 26

    c.rect(PAD, y, CONTENT, 1, SEP)
    y += 14

    left = button(c, W - PAD, y, "Close")
    button(c, left - 8, y, "Stop", muted=True)

    return y + BUTTON_H + PAD


# ------------------------------------------------------------- panel three

PROMPT_BODY = [
    "Arcangila is offering " + str(DROPS) + " drops from " + SEASON + ", "
    "with the credit marks she set by hand on 52 of them. Nothing has "
    "arrived yet.",
    "Say yes and it trickles in over about four minutes. Anything you "
    "already recorded is kept -- where you both hold the same drop, yours "
    "keeps its roll list and takes her credit mark, because that is the "
    "part she typed and you did not.",
    "Say no and she is told you declined, rather than left watching a bar "
    "that goes nowhere.",
]


def draw_prompt(c):
    y = title(c, 16, "Arcangila is sending loot history")
    y = paragraphs(c, y, PROMPT_BODY)

    y += 6
    c.rect(PAD, y, CONTENT, 1, SEP)
    y += 14

    left = button(c, W - PAD, y, "No thanks")
    button(c, left - 8, y, "Receive it")

    return y + BUTTON_H + PAD


# ------------------------------------------------------------------- page

GAP = 32
MARGIN = 24

scratch = Image.new("RGB", (2400, 2400), GROUND)
HEIGHTS = [
    int(draw_idle(C(scratch, 0, 0))),
    int(draw_sending(C(scratch, 600, 0))),
    int(draw_prompt(C(scratch, 1200, 0))),
]
BODY_H = max(HEIGHTS) + 4

problems.clear()

CAPTIONS = [
    "opened from Settings -> Tools",
    "while it is going",
    "what the other officer is asked",
]

page_w = MARGIN * 2 + W * 3 + GAP * 2
page_h = MARGIN * 2 + BODY_H + 56

img = Image.new("RGB", (int(page_w * SCALE), int(page_h * SCALE)), GROUND)

top = C(img, 0, 0)
top.text(MARGIN, 10, "Sending a season of loot to one officer", 11, TEXT_3)

for index, draw in enumerate([draw_idle, draw_sending, draw_prompt]):
    x = MARGIN + index * (W + GAP)

    panel = C(img, x, MARGIN + 14)
    panel.rect(0, 0, W, BODY_H, WINDOW)
    panel.rect(0, 0, 3, BODY_H, ACCENT_DIM)
    draw(panel)

    label = C(img, x, MARGIN + 14 + BODY_H + 12)
    label.text(0, 0, CAPTIONS[index], 10, TEXT_3)

out = (__file__.replace("\\", "/").rsplit("/", 1)[0]
       + "/../screenshots/history-sync.png")

img.save(out)

if problems:
    for problem in problems:
        sys.stderr.write(problem + "\n")
    sys.exit(1)

sys.stdout.write("wrote " + out + "\n")
