# -*- coding: utf-8 -*-
"""The "ask for it" prompt, drawn from her own LFR drops.

Razorokk, in the guild Discord: "I remember during remix, there was a button
you could hit with an addon someone made to be like 'Hey I need that for
tmog, do you need it?'". Aimee: useful "for things like LFR or any other time
the standard roll option is in place in a raid with people you dont know".

EVERY ITEM, NAME, ROLL AND NUMBER HERE IS REAL. Both drops are from her
Midnight Season 2, The Venomous Abyss on Looking For Raid, 2026-08-18: she
rolled Transmog on both and lost both. Her LFR drops carry full 25-player
roll lists, which is the thing that had to be checked before any of this was
worth drawing -- if LFR gave no roll data there would be nothing to hang a
button on.

THE WORDING IS AIMEE'S OWN, typed 2026-08-25, and so is the [item] token
syntax. The character count under the preview is computed from that wording
and the real item link, never typed, so changing the default here cannot
leave a stale number beneath it. The link is 109 characters of markup on its
own and the winner's realm is 11 more -- the whisper cannot be addressed
without it -- so 51 words of wording arrive as 178 characters. That gap is
why the preview counts rather than trusting the eye.

TWO THINGS IN THIS DRAWING ARE ARGUABLE AND ARE HERS TO SETTLE.

  A popup with a button that talks is the exact thing UI/TradeAdvisorPanel.lua
  refuses -- "a popup offering to talk for you erodes one button at a time".
  This one prefills and never sends, which is what UI/KeyRequestList.lua's
  Whisper button already does and what makes it the same rule rather than a
  hole in it. The footnote says so on the window itself.

  The wording lives behind the button on the prompt rather than in Settings,
  because that is where somebody is standing when they want to change it. It
  could be a settings row instead, or both.

Writes screenshots/ask-prompt.png.
"""
import os

from PIL import Image, ImageDraw, ImageFont

FONT = (r"C:\Program Files (x86)\World of Warcraft\_retail_"
        r"\Interface\AddOns\DialogueUI\Fonts\frizqt__.ttf")

SCALE = 2

# The trade advisor's own width, because these two are siblings: one arrives
# when you win something, this one when you lose something you can still use.
PANEL = 300
DIALOG = 320

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
FIELD = over((0, 0, 0, 0.28), WINDOW)
BUTTON = over((1, 1, 1, 0.12), WINDOW)
HEADER_BAR = over((0.220, 0.190, 0.340, 1), WINDOW)

EPIC = (163, 53, 238)

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
    for word in words:
        candidate = (cur + " " + word) if cur else word
        if measure(candidate, size) <= width or not cur:
            cur = candidate
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


CANVAS_W, CANVAS_H = 780, 350

image = Image.new("RGB", (CANVAS_W * SCALE, CANVAS_H * SCALE), GROUND)
draw = ImageDraw.Draw(image)


def text(x, y, string, size=11, color=TEXT_1, anchor="la"):
    draw.text((x * SCALE, y * SCALE), str(string), font=font(size),
              fill=color, anchor=anchor)


def box(x, y, w, h, fill=None, outline=None):
    draw.rectangle([x * SCALE, y * SCALE, (x + w) * SCALE, (y + h) * SCALE],
                   fill=fill, outline=outline, width=max(1, SCALE // 2))


def line(x, y, w, color=SEP):
    draw.rectangle([x * SCALE, y * SCALE, (x + w) * SCALE, y * SCALE + 1],
                   fill=color)


def window(x, y, w, h, title):
    box(x, y, w, h, fill=WINDOW, outline=SEP)
    box(x, y, w, 22, fill=HEADER_BAR)
    text(x + 10, y + 6, title, 11, TEXT_1)
    text(x + w - 14, y + 6, "x", 11, TEXT_3)


def button(x, y, w, label, h=20, fill=BUTTON, color=TEXT_1, size=11):
    box(x, y, w, h, fill=fill, outline=SEP)
    text(x + w / 2, y + (h - size) / 2 + 1, label, size, color, anchor="ma")


# --------------------------------------------------------------- the prompt

PX, PY = 24, 56

text(PX, 22, "WHEN YOU LOSE ONE YOU COULD HAVE USED", 12, TEXT_2)
text(PX, 38, "Real drops. Venomous Abyss LFR, 18 August, Transmog on both.",
     10, TEXT_3)

DROPS = [
    ("Scaleplate Strangulators", "Sleepadin", 97, "1:58", "The Twin Fangs"),
    ("Initiate's Sacrificial Tights", "Barbieelf", 9, "1:38",
     "Nek'zali the Soulcoiler"),
]

ENTRY_H = 78
PANEL_H = 22 + 10 + ENTRY_H * len(DROPS) + 62

window(PX, PY, PANEL, PANEL_H, "SHOW US YOUR LOOT")

y = PY + 32

for index, (item, winner, roll, clock, boss) in enumerate(DROPS):
    if index:
        line(PX + 12, y - 8, PANEL - 24)

    text(PX + 12, y, item, 11, EPIC)
    text(PX + PANEL - 12, y, clock, 11, TEXT_3, anchor="ra")

    text(PX + 12, y + 16,
         "%s won it with %d" % (winner, roll), 10, TEXT_2)

    # THE LINE THAT MAKES THE ASK HONEST. The collection API is asked whether
    # the appearance is known, and the button does not appear when it is. So
    # the message cannot be a lie, which is the difference between this and
    # begging.
    text(PX + 12, y + 30, "You rolled Transmog, and you are missing this "
                          "appearance.", 10, TEXT_3)

    button(PX + 12, y + 46, PANEL - 24, "Ask %s" % winner)

    y += ENTRY_H

line(PX + 12, y - 6, PANEL - 24)

for offset, part in enumerate(wrap(
        "Puts the wording in your chat box. Nothing is sent until you press "
        "Enter.", 10, PANEL - 24)):
    text(PX + 12, y + 2 + offset * 12, part, 10, TEXT_3)

button(PX + PANEL - 12 - 62, y + 30, 62, "Wording", h=18, size=10,
       color=ACCENT)


# --------------------------------------------------------------- the wording

DX, DY = 400, 56

text(DX, 22, "AND THE WORDING IS YOURS", 12, TEXT_2)
text(DX, 38, "Prefilled, editable, saved. Opened from the button above.",
     10, TEXT_3)

DIALOG_H = 270

window(DX, DY, DIALOG, DIALOG_H, "THE WORDING")

text(DX + 12, DY + 32, "What Ask types for you.", 10, TEXT_2)

# AIMEE'S WORDING, chosen 2026-08-25 and typed by her. Square brackets rather
# than braces are hers too, and they are the better call: [item] is what an
# item link already looks like in chat.
#
# It does not say transmog, which settles a question the first draft left
# open -- the same sentence works for a Need roll you lost, so the prompt is
# not transmog-only.
TEMPLATE = "Hi there, could I have [item] if you don't need it?"

# The real link off the real drop, so the count below is the true one.
LINK = ("|cnIQ4:|Hitem:268220::::::::90:253::4:4:6652:13662:13332:12827:1:28:"
        "7359:::::|h[Scaleplate Strangulators]|h|r")
# REALM-QUALIFIED, because that is what actually gets typed. A bare first
# name does not whisper across realms, and in LFR the winner is on another
# realm nearly every time -- so the shorter version of this line was a
# drawing of a message that would not have arrived. It also costs 11 of the
# 255, which is exactly the sort of thing the count is here to catch.
WHISPER_TO = "/w Sleepadin-Silvermoon "

COMPOSED = len(WHISPER_TO + TEMPLATE.replace("[item]", LINK))

field_lines = wrap(TEMPLATE, 11, DIALOG - 40)
FIELD_H = 12 + len(field_lines) * 15

box(DX + 12, DY + 50, DIALOG - 24, FIELD_H, fill=FIELD, outline=ACCENT_DIM)

for offset, part in enumerate(field_lines):
    text(DX + 20, DY + 56 + offset * 15, part, 11, TEXT_1)

y = DY + 50 + FIELD_H + 10

text(DX + 12, y, "[item] becomes the item link.", 10, TEXT_3)
text(DX + 12, y + 13, "[player] becomes their name.", 10, TEXT_3)

y += 34

text(DX + 12, y, "PREVIEW", 10, TEXT_2)

y += 16

PREVIEW_H = 62
box(DX + 12, y, DIALOG - 24, PREVIEW_H, fill=FIELD, outline=SEP)

# Drawn in two colors because that is how it arrives in the chat box: the
# item is a link, not words.
text(DX + 20, y + 8, "/w Sleepadin-Silvermoon Hi there, could I", 10,
     TEXT_2)
text(DX + 20, y + 22, "have", 10, TEXT_2)
text(DX + 20 + measure("have ", 10), y + 22,
     "[Scaleplate Strangulators]", 10, EPIC)
text(DX + 20 + measure("have [Scaleplate Strangulators] ", 10), y + 22,
     "if you", 10, TEXT_2)

text(DX + 20, y + 36, "don't need it?", 10, TEXT_2)

text(DX + 20, y + 48, "%d of the 255 a whisper allows." % COMPOSED, 10,
     TEXT_3)

y += PREVIEW_H + 8

# The number nobody would guess: the link is more than half the message.
for offset, part in enumerate(wrap(
        "109 of those are the link and 11 are the realm it cannot be sent "
        "without. That gap is why this counts.", 10, DIALOG - 24)):
    text(DX + 12, y + offset * 12, part, 10, TEXT_3)

y += 32

button(DX + 12, y, 118, "Put the default back", h=20, size=10, color=TEXT_2)
button(DX + DIALOG - 12 - 70, y, 70, "Save", h=20, size=10, color=ACCENT)


OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "screenshots", "ask-prompt.png")

image.save(OUT)
print("wrote", os.path.normpath(OUT))
