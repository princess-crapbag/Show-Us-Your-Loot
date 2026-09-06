# -*- coding: utf-8 -*-
"""Two windows, drawn at their real size before either is built.

LEFT: THE KEY REQUEST ALERT. Today an incoming request writes one line into
chat -- "Pringlesbop-Illidan asked to run your key as DPS. /syl keys to
answer" -- and that is the whole of it. A line of chat on a raid night is a
line that scrolls, and the only way back to it is a slash command, which is
the one thing this addon has decided a feature may never require.

The durable list on the Keys tab is already built and is what makes a popup
safe to close: Dismiss hides the row from the badge and leaves it there until
the weekly reset. Core/KeystoneRequests.lua's header has said "Dismiss only
hides the popup" since before there was a popup to hide.

The shape is UI/HistoryPrompt.lua's, because that is the addon's answer to
"somebody has asked you something" and a second answer to the same question is
how two dialogs drift apart.

AND IT IS ADDRESSED TO A PERSON, NOT A CHARACTER. Aimee, 2026-09-06: "can i
ask pronglez for his key on pringlescat and it send to whichever character he
is online with and show which key im asking for?"

Both halves of that are one change, and the second half is what makes the
first one safe. If a request can be delivered to whichever character is
online, then "your key" is no longer a thing the message can say -- his three
known keys are three different keys, +14 and +13 on one dungeon and +15 on
another, and Core/Keystone.lua stores them per character on purpose: "alts
hold their own keys, and folding them onto the main would lose exactly the
detail being asked for." So the request carries the key it is about, and the
alert names it and the character it sits on.

BOTTOM LEFT: what she sees after pressing Ask. The row already carries the
dungeon and the level -- that half exists. What is new is the RESPONSE
tooltip, which is the only place with room to say the request went somewhere
other than where it was aimed.

RIGHT: THE SEND WINDOW, with the two things asked for on 2026-09-06.

A NAME YOU TYPE. The target was a cycle button over online guild members --
one click per name, which is fine at four names and not at forty. It is a
search box with the suggestion list UI/NameSuggest.lua already draws for the
"Alt of" field, and the error under it is the case Aimee named: a whisper
cannot reach somebody who is not logged in, so a name that is offline has to
say so rather than sit there looking sendable.

AND THE NIGHTS ON THE WHAT-GOES BLOCK, which is the fifth line and the reason
the whole transfer was wrong. See Core/HistoryPayload.lua.

EVERY NUMBER IS HERS, read out of
WTF/Account/ARCANGELA/SavedVariables/ShowUsYourLoot.lua this morning and run
through the shipped HistorySync.Describe rather than estimated: Midnight
Season 2, 135 drops of her own, 57 carrying credit she typed, 6 guild nights
out of 10 recorded sessions, 1,115 messages, 4.6 minutes.

THE PEOPLE AND THE KEYS ARE HERS. Her guildKeystones block holds Pronglez-
Illidan at +15 on map 585, Pringlescat-Illidan at +14 on 249 and Pringlesbop-
Illidan at +13 on 249. Her player registry has five of that person's eight
characters linked to Pringlescat by hand -- and NOT Pronglez, which is the one
she wants to ask. The drawing shows the feature working; the note under it is
the reason it would not work on her machine today.

Dungeon names are the one thing not in the file: Core/Keystone.lua stores
mapIDs and asks C_ChallengeMode for the name at runtime. Real names of the
right length are used here, and UI/KeyRows.lua's column note is the authority
on how wide that column has to be.

Writes screenshots/sync-and-keys.png.
"""
import sys

from PIL import Image

from mockup_settings_tabs import (
    ACCENT, BUTTON, C, GROUND, ROW_ALT, SCALE, SEP, TEXT_1, TEXT_2, TEXT_3,
    WARNING, WINDOW, check, measure, problems, wrap,
)

PAD = 20
LINE = 15
BUTTON_H = 22
BUTTON_PAD = 14
SMALL_H = 18

# --- her data -------------------------------------------------------------

SEASON = "Midnight Season 2"
DROPS = 135
CREDITED = 57
NIGHTS = 6
MESSAGES = 1115
MINUTES = 5

# What she is asking for, and who it reaches. The key is Pronglez's; Pronglez
# is offline; Pringlesbop is the character of his that is logged in.
ASKER_SHORT = "Aimee"
ROLE = "Healer"

KEY_HOLDER = "Pronglez"
KEY_DUNGEON = "Operation: Floodgate"
KEY_LEVEL = 15
REACHED = "Pringlesbop"

# The rows she is looking at, with the columns UI/KeyRows.lua declares. The
# first is the one she pressed Ask on a moment ago.
KEY_ROWS = [
    ("Pronglez", "Operation: Floodgate", "15", "Waiting"),
    ("Pringlescat", "Priory of the Sacred Flame", "14", "Ask"),
    ("Pringlesbop", "Priory of the Sacred Flame", "13", "Ask"),
]

BOX_W = 200

# UI/NameSuggest.lua caps at six, and this window has room for three.
#
# MEASURED, AFTER THIS DRAWING SAID FOUR. tools/test_layout.py does the
# arithmetic off the shipped constants and found four is 102 pixels tall and
# reaches eleven past the WHAT GOES heading; three is 82 and clears it by
# nine. The drawing was wrong and the test was right, which is the order those
# two are supposed to happen in.
SUGGEST_ROWS = 3

TYPED = "Nychar"
SUGGESTIONS = [
    ("Nychar", "Priest · raiding"),
    ("Nycharius", "Mage"),
]
OFFLINE_NAME = "Nychar"


def button(c, right_edge, y, label, height=BUTTON_H, muted=False):
    w = int(round(measure(label, 11) + BUTTON_PAD * 2))
    x = right_edge - w

    c.rect(x, y, w, height, BUTTON)
    c.text(x + (w - measure(label, 11)) / 2, y + (height - 13) / 2, label, 11,
           TEXT_3 if muted else TEXT_1)
    check("button '%s'" % label, measure(label, 11), w - 8)

    return x


def chrome(c, width, height, title):
    """The window every dialog in this addon draws: mark, title, rules."""
    c.rect(0, 0, width, height, WINDOW)
    c.rect(16, 18, 3, 14, ACCENT)
    c.text(29, 17, title, 15, TEXT_1)
    check("title '%s'" % title, measure(title, 15), width - 29 - 30)
    c.rect(16, 48, width - 32, 1, SEP)
    c.rect(16, height - 42, width - 32, 1, SEP)


def paragraphs(c, y, blocks, width, size=11, color=TEXT_2):
    for block in blocks:
        for line in wrap(block, size, width):
            c.text(PAD, y, line, size, color)
            y += LINE
        y += 8

    return y


# --------------------------------------------------------------------------
# LEFT: somebody wants your key
# --------------------------------------------------------------------------

KEY_W = 400
KEY_BODY = KEY_W - PAD * 2


def key_alert(img, ox, oy):
    body = "%s wants to run one of your keys as %s." % (ASKER_SHORT, ROLE)

    # WHICH KEY, NAMED. Without it the message can only say "your key", and
    # once it can arrive on any character of yours that is a question with
    # three different answers -- Core/Keystone.lua stores a key per character
    # on purpose, because "alts hold their own keys".
    key_line = "+%d %s" % (KEY_LEVEL, KEY_DUNGEON)
    on_line = "on %s" % KEY_HOLDER

    # AND WHY IT CAME HERE. It was aimed at Pronglez and landed on
    # Pringlesbop, and the person reading it needs that before they wonder
    # whether they have been asked about a key they do not hold.
    routed = ("Aimed at %s, who is offline. It reached you on %s because that "
              "is the character of yours that is logged in."
              % (KEY_HOLDER, REACHED))

    tail = ("Answering tells them either way. Hide takes it off the count "
            "without answering — it stays on the Keys tab until the "
            "weekly reset, so hiding it is never the same as losing it.")

    # Laid out by walking it rather than by a sum, because the sum was wrong
    # by fifty pixels of empty ground the first time and nothing on the
    # drawing says so -- an over-tall window just looks like a decision.
    end = 60
    end += len(wrap(body, 11, KEY_BODY)) * LINE + 8       # who is asking
    end += 18 + LINE + 14                                 # THE KEY block
    end += len(wrap(routed, 11, KEY_BODY)) * LINE + 8     # why it came here
    end += len(wrap(tail, 11, KEY_BODY)) * LINE           # what the buttons do

    # The footer rule sits 14 under the last line and the buttons 8 under
    # that, which is the spacing UI/HistoryPrompt.lua uses and the reason this
    # is a sum of named gaps rather than a round number that looked right.
    height = end + 14 + 42

    c = C(img, ox, oy)
    chrome(c, KEY_W, height, "%s wants a key of yours" % ASKER_SHORT)

    y = paragraphs(c, 60, [body], KEY_BODY)

    c.text(PAD, y, "THE KEY", 10, TEXT_3)
    y += 18
    c.text(PAD, y, key_line, 11, TEXT_1)
    c.text(PAD + measure(key_line, 11) + 8, y, on_line, 11, TEXT_3)
    check("the key and whose it is",
          measure(key_line, 11) + 8 + measure(on_line, 11), KEY_BODY)
    y += LINE + 14

    y = paragraphs(c, y, [routed], KEY_BODY, color=TEXT_2)
    paragraphs(c, y, [tail], KEY_BODY, color=TEXT_3)

    # The four answers, in the order the Keys tab already draws them. Whisper
    # prefills rather than sends, exactly as UI/KeyRequestList.lua does.
    bottom = height - 14 - BUTTON_H
    right = button(c, KEY_W - PAD, bottom, "No")
    right = button(c, right - 8, bottom, "Maybe")
    right = button(c, right - 8, bottom, "Yes")

    button(c, right - 8, bottom, "Whisper", muted=True)

    # Hide sits apart from the three answers, on the left, because it is not
    # one of them -- it is "not now", and the row stays on the Keys tab.
    c.rect(PAD, bottom, int(round(measure("Hide", 11) + BUTTON_PAD * 2)),
           BUTTON_H, BUTTON)
    c.text(PAD + BUTTON_PAD, bottom + (BUTTON_H - 13) / 2, "Hide", 11, TEXT_3)

    hide_right = PAD + measure("Hide", 11) + BUTTON_PAD * 2
    check("Hide does not reach the answers", hide_right + 8,
          right - 8 - int(round(measure("Whisper", 11) + BUTTON_PAD * 2)))

    return height


# --------------------------------------------------------------------------
# BOTTOM LEFT: what she sees after pressing Ask
# --------------------------------------------------------------------------
#
# The columns are UI/KeyRows.lua's, measured the way it measures them: the
# widest string each can ever hold, plus one padding number so no column ends
# up looser than its neighbors. Nothing here is new except the tooltip.

ROW_COLUMNS = [
    ("PLAYER", "Likestoflash-Nordrassil", "LEFT"),
    ("DUNGEON", "Operation: Mechagon - Workshop", "LEFT"),
    ("LVL", "30", "LEFT"),
    ("RESPONSE", "Not sent yet", "CENTER"),
]

COLUMN_PADDING = 12
COLUMN_START = 4

ROW_H = 22

TOOLTIP = (
    "Asked as Healer. Pronglez is offline, so it went to Pringlesbop — "
    "the same person. They answer once, for this key."
)


def key_rows(img, ox, oy):
    widths = []
    for label, widest, _ in ROW_COLUMNS:
        widths.append(max(measure(widest, 11), measure(label, 10))
                      + COLUMN_PADDING)

    # Rounded once, here, because every x below is derived from it and a
    # column boundary that lands on half a pixel draws one row's cell a pixel
    # left of the one above it.
    widths = [int(round(w)) for w in widths]

    table = COLUMN_START + sum(widths)
    width = table + PAD * 2

    tip_w = 300
    tip_lines = wrap(TOOLTIP, 10, tip_w - 20)
    tip_h = len(tip_lines) * 13 + 14

    height = 48 + 20 + len(KEY_ROWS) * ROW_H + 10 + tip_h + 16

    c = C(img, ox, oy)
    chrome(c, width, height, "Keys")

    def cell(x, w, y, text, size, color, justify):
        if justify == "CENTER":
            c.text(x + (w - measure(text, size)) / 2, y, text, size, color)
        else:
            c.text(x + 6, y, text, size, color)
        check("cell '%s'" % str(text)[:18], measure(text, size), w - 8)

    x = PAD + COLUMN_START
    for index, (label, _, justify) in enumerate(ROW_COLUMNS):
        cell(x, widths[index], 56, label, 10, TEXT_3, justify)
        x += widths[index]

    y = 76
    for row_index, row in enumerate(KEY_ROWS):
        if row_index % 2 == 1:
            c.rect(PAD, y - 4, table, ROW_H, ROW_ALT)

        x = PAD + COLUMN_START
        for index, value in enumerate(row):
            # The RESPONSE column holds either a button or an answer, never
            # both -- UI/KeyRows.lua's note on why they share the space.
            if index == 3 and value == "Ask":
                bw = int(round(measure("Ask", 11) + BUTTON_PAD * 2))
                bx = x + (widths[index] - bw) / 2
                c.rect(bx, y - 3, bw, SMALL_H, BUTTON)
                c.text(bx + (bw - measure("Ask", 11)) / 2, y, "Ask", 11, TEXT_1)
            else:
                color = TEXT_1 if index == 0 else TEXT_2
                if index == 3:
                    color = ACCENT
                cell(x, widths[index], y, value, 11, color,
                     ROW_COLUMNS[index][2])
            x += widths[index]

        y += ROW_H

    # THE TOOLTIP IS THE WHOLE ADDITION. RESPONSE is sized from "Not sent yet"
    # and cannot hold a sentence -- UI/KeyRows.lua widened it once for
    # "Waiting for them to log in" and had to take the words back instead.
    # So where a request actually went is said on hover, which is the only
    # surface here with room for it.
    tip_x = PAD + COLUMN_START + widths[0] + widths[1]
    tip_x = min(tip_x, width - PAD - tip_w)
    tip_y = 76 + len(KEY_ROWS) * ROW_H + 6

    c.rect(tip_x, tip_y, tip_w, tip_h, SEP)
    c.rect(tip_x + 1, tip_y + 1, tip_w - 2, tip_h - 2, GROUND)

    ty = tip_y + 7
    for line in tip_lines:
        c.text(tip_x + 10, ty, line, 10, TEXT_2)
        ty += 13

    check("the tooltip stays inside the window", tip_x + tip_w, width - PAD)

    return width, height


# --------------------------------------------------------------------------
# RIGHT: send loot history
# --------------------------------------------------------------------------

SEND_W = 460
SEND_BODY = SEND_W - PAD * 2


def send_window(img, ox, oy):
    c = C(img, ox, oy)

    intro = ("Sends this season's drops and the raid nights they were won on "
             "to one person. Their board then scores the same items the same "
             "way yours does, over the same number of nights.")
    second = ("It goes to them and to nobody else, and they are asked before "
              "any of it arrives.")
    third = ("Once the bar starts moving you can close this window and keep "
             "playing — it keeps going. Stop cancels it.")

    facts = [
        SEASON,
        "%d drops, with who won each one and who rolled" % DROPS,
        "%d of them carrying credit you set by hand" % CREDITED,
        # THE NEW LINE. Without it a receiver divides a complete numerator by
        # their own attendance -- Pringlescat's board read "of 4" against a
        # season that had run nine.
        "%d guild raid nights, so their attendance matches yours" % NIGHTS,
        "%d messages, about %d minutes at the pace the client allows"
        % (MESSAGES, MINUTES),
    ]

    body_lines = sum(len(wrap(t, 11, SEND_BODY)) for t in (intro, second, third))
    body_h = body_lines * LINE + 16

    facts_top = 60 + body_h + 22
    facts_h = len(facts) * LINE
    target_top = facts_top + 18 + facts_h + 14
    bar_top = target_top + 16 + 20 + 8 + LINE + 20
    height = bar_top + 14 + 60

    chrome(c, SEND_W, height, "Send loot history")

    paragraphs(c, 60, [intro, second, third], SEND_BODY)

    c.text(PAD, facts_top, "WHAT GOES", 10, TEXT_3)

    y = facts_top + 18
    for index, line in enumerate(facts):
        c.text(PAD, y, line, 11, TEXT_1 if index == 0 else TEXT_2)
        check("fact %d" % index, measure(line, 11), SEND_BODY)
        y += LINE

    c.text(PAD, target_top, "SEND TO", 10, TEXT_3)

    # THE BOX. Bordered, because UI/SearchBox.lua reserves the outline for a
    # field that is a value rather than a filter -- and this one is a value:
    # nothing happens until Send is pressed.
    box_y = target_top + 16
    c.rect(PAD, box_y, BOX_W, 20, SEP)
    c.rect(PAD + 1, box_y + 1, BOX_W - 2, 18, GROUND)
    c.text(PAD + 6, box_y + 3, TYPED, 11, TEXT_1)
    c.rect(PAD + 6 + measure(TYPED, 11) + 1, box_y + 4, 1, 12, TEXT_1)
    check("typed name fits its box", measure(TYPED, 11), BOX_W - 12)

    # THE LIST OPENS UPWARD, which is what UI/NameSuggest.lua already does and
    # is right here for the reason it is right there: what sits below the box
    # is the progress bar and the footer, and a list over those would cover the
    # Send button somebody is about to press.
    #
    # ANCHORED TO THE HEADING, NOT TO THE BOX, and that is the whole of the
    # change. Two pixels above the box puts the list on top of "SEND TO" -- the
    # heading of the control being used -- and on the error line's own row a
    # moment later. Two pixels above the HEADING clears both and covers only
    # the WHAT GOES block, which is static reference text that is still there
    # when the list closes.
    rows = min(len(SUGGESTIONS), SUGGEST_ROWS)
    pop_h = 16 + rows * 20 + 6
    pop_w = 220
    pop_y = target_top - 4 - pop_h

    c.rect(PAD, pop_y, pop_w, pop_h, SEP)
    c.rect(PAD + 1, pop_y + 1, pop_w - 2, pop_h - 2, WINDOW)
    c.text(PAD + 10, pop_y + 5, 'MATCHING "%s"' % TYPED.upper(), 10, TEXT_3)

    for index, (name, note) in enumerate(SUGGESTIONS[:rows]):
        ry = pop_y + 16 + index * 20
        if index == 0:
            c.rect(PAD + 4, ry, pop_w - 8, 20, BUTTON)
        c.text(PAD + 10, ry + 4, name, 11, TEXT_1)
        c.right(PAD + pop_w - 10, ry + 5, note, 10, TEXT_3)
        check("suggestion %d" % index,
              measure(name, 11) + measure(note, 10) + 12, pop_w - 20)

    # The two things the list must not land on, measured rather than eyeballed.
    check("the list clears the SEND TO heading", pop_y + pop_h, target_top - 2)
    check("and the box below it", pop_y + pop_h, box_y)

    # THE ERROR, which is the thing asked for by name. One line, in the slot
    # the "N online · click to change" note used to have, so nothing below it
    # moves when it appears.
    error = ("%s is not online. A whisper cannot reach somebody who is not "
             "logged in." % OFFLINE_NAME)

    c.text(PAD, box_y + 28, error, 10, WARNING)
    check("offline error", measure(error, 10), SEND_BODY)

    back_y = bar_top
    c.rect(PAD, back_y, SEND_BODY, 14, BUTTON)

    bottom = height - 14 - BUTTON_H
    right = button(c, SEND_W - PAD, bottom, "Close")
    button(c, right - 8, bottom, "Send")

    return height


# --------------------------------------------------------------------------

GAP = 40
MARGIN = 30

OUT = __file__.rsplit(chr(92), 1)[0] + chr(92) + "..%sscreenshots%ssync-and-keys.png" % (chr(92), chr(92))


def main():
    blank = Image.new("RGB", (1, 1))

    alert_h = key_alert(blank, 0, 0)
    rows_w, rows_h = key_rows(blank, 0, 0)
    send_h = send_window(blank, 0, 0)

    left_w = max(KEY_W, rows_w)
    left_h = alert_h + GAP + rows_h

    width = MARGIN * 2 + left_w + GAP + SEND_W
    height = MARGIN * 2 + max(left_h, send_h)

    img = Image.new("RGB", (width * SCALE, height * SCALE), GROUND)

    key_alert(img, MARGIN, MARGIN)
    key_rows(img, MARGIN, MARGIN + alert_h + GAP)
    send_window(img, MARGIN + left_w + GAP, MARGIN)

    out = OUT
    img.save(out)

    print("wrote " + out)
    print("key alert   %d x %d" % (KEY_W, alert_h))
    print("keys rows   %d x %d" % (rows_w, rows_h))
    print("send window %d x %d" % (SEND_W, send_h))

    if problems:
        print("")
        print("OVERLAPS:")
        for line in problems:
            print("  " + line)
        return 1

    print("no overlaps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
