# -*- coding: utf-8 -*-
"""The upgrade-track letter, and the tier tokens that had none.

WHY THIS EXISTS. The Raiders detail cards print V, C, H or M in the corner of
every item card, and tier tokens drew a blank. Aimee: "under raiders, when you
click a player who received loot i see that tier tokens do not show the track
like offset pieces do [...] i want to see that someone got champion tier vs
heroic tier."

The cause is not a bug in this addon. A tier token is
Enum.ItemClass.Miscellaneous rather than equipment, so
C_Item.GetItemUpgradeInfo has nothing to say about it - three addons installed
on this machine gate that same call behind an equipment test for exactly that
reason. The token carries no track at all.

Aimee settled it: "there is no track on the token. but champion drops from
normal and hero drops from heroic, mythic from mythic. veteran from lfr." So
the letter comes from the difficulty the item dropped on.

WHAT THE ASSERTIONS PROTECT:

  THE API STILL WINS WHEREVER IT SPEAKS. A Champion piece crested up to Hero
  still dropped on Normal, and the card must say what the item IS, not what it
  was when it fell. A difficulty fallback that overrode the client would be a
  wrong letter printed confidently on every upgraded item in the game.

  THE DIFFICULTY IS ONLY A FALLBACK, and only for raid difficulties. A
  Mythic+ dungeon drop, a world drop and a crafted item must all still answer
  nothing rather than being assigned a raid track.

  THE LETTER IS DECODABLE. GearTrack.NAMES and GearTrack.Describe were written
  for "the tooltip that explains a card" and that tooltip had never been
  built, so the letter has been on screen with nowhere to learn what it means
  since the cards shipped.

Needs `lupa` - see tools/test_lootmessages.py for the setup.
"""
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import test_load  # noqa: E402

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s  %s" % (name, detail))
        failures.append(name)


Track = SYL.GearTrack

# Her own tier tokens, from the saved variables. Real links, real ids.
TOKEN = ("|cnIQ4:|Hitem:270916::::::::90:253::3:3:13703:13692:13333:1:28:"
         "7359:::::|h[Venomcast Effigy]|h|r")
GEAR = ("|cnIQ4:|Hitem:268258::::::::90:253::3:3:12834:13333::::::"
        "|h[Boots of the Reckless Wayfarer]|h|r")

# Difficulty ids, the same ones Core/Utilities.lua's RAID_DIFFICULTIES uses.
LFR, NORMAL, HEROIC, MYTHIC = 17, 14, 15, 16
MYTHIC_PLUS, WORLD = 8, 250


# --------------------------------------------------------------------------
# With a client that answers nothing - which is a tier token
# --------------------------------------------------------------------------
#
# The test client's C_Item.GetItemUpgradeInfo returns nil already, so this is
# the token case without having to fake it.

for label, difficulty, expected in (
    ("Looking For Raid is Veteran", LFR, "V"),
    ("Normal is Champion", NORMAL, "C"),
    ("Heroic is Hero", HEROIC, "H"),
    ("Mythic is Myth", MYTHIC, "M"),
):
    got = Track.LetterFor(TOKEN, difficulty)
    check("a token from %s" % label, got == expected, "got %r" % got)

# THE NEGATIVE CASES. A track invented for content that has no raid track is
# worse than a blank corner, because a blank reads as "not known" and a letter
# reads as a fact.
check("a Mythic+ dungeon drop gets no letter",
      Track.LetterFor(TOKEN, MYTHIC_PLUS) is None,
      "got %r" % Track.LetterFor(TOKEN, MYTHIC_PLUS))

check("a world drop gets no letter",
      Track.LetterFor(TOKEN, WORLD) is None)

check("no difficulty at all gets no letter",
      Track.LetterFor(TOKEN, None) is None)

check("and neither does an empty link",
      Track.LetterFor("", NORMAL) is None)

check("nor a nil one", Track.LetterFor(None, NORMAL) is None)


# --------------------------------------------------------------------------
# With a client that DOES answer - which is ordinary gear
# --------------------------------------------------------------------------
#
# THE ORDER OF THESE TWO SOURCES IS THE WHOLE POINT. Reversing them is the
# fault this suite exists to catch: it would relabel every crested item in the
# game with the difficulty it originally dropped on.

lua.execute("""
    UPGRADE_ANSWER = nil

    C_Item.GetItemUpgradeInfo = function()
        return UPGRADE_ANSWER
    end

    function SET_TRACK(name, at, most)
        UPGRADE_ANSWER = {
            trackString = name, currentLevel = at, maxLevel = most,
        }
    end

    function CLEAR_TRACK() UPGRADE_ANSWER = nil end
""")

SetTrack = lua.globals().SET_TRACK
ClearTrack = lua.globals().CLEAR_TRACK

SetTrack("Champion", 3, 6)

check("the client's own answer is used",
      Track.LetterFor(GEAR, None) == "C")

# A Champion piece crested to Hero: it dropped on Normal, and the card must
# say Hero because that is what the item is now.
SetTrack("Hero", 1, 6)

check("and it OVERRIDES the difficulty rather than the other way round",
      Track.LetterFor(GEAR, NORMAL) == "H",
      "got %r" % Track.LetterFor(GEAR, NORMAL))

# A client that answers a track this addon does not know - a future one, or a
# locale with no entry - must fall through rather than swallow the item.
SetTrack("Ascendant", 1, 6)

check("an unknown track name falls through to the difficulty",
      Track.LetterFor(GEAR, HEROIC) == "H",
      "got %r" % Track.LetterFor(GEAR, HEROIC))


# --------------------------------------------------------------------------
# Describe, which is what makes the letter readable
# --------------------------------------------------------------------------

SetTrack("Champion", 3, 6)

check("gear describes its position on the track",
      Track.Describe(GEAR, None) == "Champion 3 of 6",
      "got %r" % Track.Describe(GEAR, None))

ClearTrack()

# A TOKEN STOPS AT THE NAME. There is no current level to report, and
# "Champion 1 of 6" would be a number invented to fill the shape of a
# sentence.
check("a token describes the track and stops",
      Track.Describe(TOKEN, NORMAL) == "Champion",
      "got %r" % Track.Describe(TOKEN, NORMAL))

check("and describes nothing when nothing is known",
      Track.Describe(TOKEN, MYTHIC_PLUS) is None)

check("every letter the board can draw has a name",
      all(Track.NAMES[letter] for letter in Track.ORDER.values()))

check("and every difficulty maps to a letter that has a name",
      all(Track.NAMES[letter] is not None
          for letter in dict(Track.BY_DIFFICULTY).values()))


# --------------------------------------------------------------------------
# The card actually asks the question, and shows the answer
# --------------------------------------------------------------------------
#
# Read out of the source: the fault this catches is the difficulty being
# dropped somewhere along the way from the record to the card, which leaves
# every token blank again with nothing failing.

cards = test_load.ROOT.joinpath("UI/RaidersDetailCards.lua").read_text(
    encoding="utf-8")

check("the card passes the difficulty to LetterFor",
      "LetterFor(item.itemLink, item.difficultyID)" in cards)

check("and puts the track name somewhere it can be read",
      "GearTrack.Describe" in cards and "trackNote" in cards)

score = test_load.ROOT.joinpath("Core/LootScore.lua").read_text(
    encoding="utf-8")

check("and ItemsFor carries the difficulty out to it",
      "difficultyID = drop.difficultyID" in score)

widgets = test_load.ROOT.joinpath("UI/Widgets.lua").read_text(encoding="utf-8")

check("the item hover can show a note at all",
      "getNote" in widgets)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
