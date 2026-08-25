"""Asking for what you lost: when the button appears, and what it types.

The fixture is a real drop, copied out of Aimee's Midnight Season 2 -- The
Venomous Abyss on Looking For Raid, 18 August, Scaleplate Strangulators,
Sleepadin took it with a 97 while she was on a Transmog roll. The item link
and the GUIDs are the real ones, which matters for two of these: the composed
whisper is measured against the real link's 109 characters of markup, and the
winner is on another realm, which is the ordinary case in LFR and the one
that breaks a naive whisper.

FOUR THINGS THIS EXISTS TO HOLD.

  THE ADDON NEVER SENDS. Not one file may call SendChatMessage. That is the
  rule UI/TradeAdvisorPanel.lua states and this feature is the first thing
  that goes anywhere near it, so the rule gets a test rather than a comment.

  THE ASK CANNOT BE A LIE. A transmog loss offers the button only when the
  collection confirms the appearance is missing, and a client that cannot
  answer is treated as no.

  GREED IS A ROLL LIKE ANY OTHER. It was left out of the first build on the
  reasoning that greed means indifference. Aimee: "sometimes LFR can be weird
  and not let you roll need (wrong armor type) or mog (for no known reason) so
  having the option is good." Greed is often the only button the client will
  give you, so the test now holds the opposite of what it first held.

  DISMISSED STAYS DISMISSED. Roll lists resolve over several passes, and every
  pass offers the same drop again -- so a waved-away entry that came back
  would come back repeatedly.

Needs `lupa`; see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import re
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

ROOT = Path(__file__).resolve().parent.parent

# Hers, and 109 characters of it are markup.
LINK = ("|cnIQ4:|Hitem:268220::::::::90:253::4:4:6652:13662:13332:12827:1:28:"
        "7359:::::|h[Scaleplate Strangulators]|h|r")

ME = "Player-60-0E67A81E"
WINNER = "Player-3725-05DA7FB1"

lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute("""
ShowUsYourLoot = {}
ShowUsYourLootDB = { settings = {} }

NOW = 1787094714
function time() return NOW end

FEATURE_ON = true

ShowUsYourLoot.Features = {
    IsEnabled = function(key) return FEATURE_ON end,
}

-- The numbers are Blizzard's, listed in Core/LootHistoryAPI.lua's own header:
-- NeedMainSpec=0 NeedOffSpec=1 Transmog=2 Greed=3 NoRoll=4 Pass=5.
ShowUsYourLoot.LootHistoryAPI = {
    ROLL_STATE = {
        NeedMainSpec = 0,
        NeedOffSpec = 1,
        Transmog = 2,
        Greed = 3,
        NoRoll = 4,
        Pass = 5,
    },
}

ShowUsYourLoot.LootScore = {
    LABELS = { [0] = "Need", [1] = "Offspec", [2] = "Transmog", [3] = "Greed" },
    MIN_NIGHTS = 2,
}

ShowUsYourLoot.Players = {
    ResolveToMain = function(key) return key end,
}

ShowUsYourLoot.Utilities = {
    NormalizeItemLink = function(link) return link end,
    GetPlayerFullName = function() return "Arcangila-Area52" end,
}

RECORDS = {}

ShowUsYourLoot.LootHistoryStore = {
    GetRecord = function(id) return RECORDS[id] end,
}

function UnitGUID(unit) return "%s" end

-- The client's answer about an appearance. nil is "cannot tell", which the
-- addon must read as no rather than as yes.
HAS_APPEARANCE = false

C_TransmogCollection = {
    PlayerHasTransmogByItemInfo = function(link)
        if HAS_APPEARANCE == nil then
            return nil
        end

        return HAS_APPEARANCE
    end,
}

-- Real GUID, real other realm. A bare "Sleepadin" whispers into nothing from
-- Area 52.
function GetPlayerInfoByGUID(guid)
    if guid == "%s" then
        return "Paladin", "PALADIN", "Human", "Human", 2,
            "Sleepadin", "Silvermoon"
    end

    return nil
end
""" % (ME, WINNER))

for name in ("Core/TradeAdvisor.lua", "Core/AskWording.lua", "Core/LootAsk.lua"):
    lua.execute((ROOT / name).read_text(encoding="utf-8"))

g = lua.globals()
SYL = g.ShowUsYourLoot
LootAsk = SYL.LootAsk
AskWording = SYL.AskWording

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def drop(my_state, winner=WINNER, when=None, drop_id="the-drop"):
    """The real drop, with my roll set to whichever state is being tested."""
    record = lua.eval("{}")

    record.id = drop_id
    record.itemLink = LINK
    record.itemName = "Scaleplate Strangulators"
    record.itemID = 268220
    record.winnerName = "Sleepadin"
    record.winnerGUID = winner
    record.winnerRoll = 97
    record.timestamp = when if when is not None else g.NOW

    record.rolls = lua.eval("""{
        { name = "Sleepadin", guid = "%s", class = "PALADIN",
          state = 0, roll = 97, isWinner = true },
        { name = "Arcangila", guid = "%s", class = "PRIEST", state = %d },
        { name = "Jortsnjoyer", guid = "Player-76-09BEB971", state = 2 },
    }""" % (winner, ME, my_state))

    g.RECORDS[drop_id] = record

    return record


def reset():
    g.ShowUsYourLootDB.lootAsk = lua.eval("{}")
    g.FEATURE_ON = True
    g.HAS_APPEARANCE = False


STATE = SYL.LootHistoryAPI.ROLL_STATE


# ------------------------------------------------------------- when it shows

reset()

check("a transmog loss on an appearance you are missing offers the button",
      LootAsk.Reason(drop(STATE.Transmog))
      == "You rolled Transmog, and you are missing this appearance.",
      LootAsk.Reason(drop(STATE.Transmog)))

g.HAS_APPEARANCE = True

check("THE SAME LOSS WITH THE APPEARANCE ALREADY COLLECTED OFFERS NOTHING",
      LootAsk.Reason(drop(STATE.Transmog)) is None,
      "the message would be a lie")

g.HAS_APPEARANCE = None

check("and a client that cannot answer is read as no, not as yes",
      LootAsk.Reason(drop(STATE.Transmog)) is None)

g.HAS_APPEARANCE = False

check("a Need loss offers it, and says which roll it was",
      LootAsk.Reason(drop(STATE.NeedMainSpec)) == "You rolled Need and lost.",
      LootAsk.Reason(drop(STATE.NeedMainSpec)))

check("so does an offspec loss",
      LootAsk.Reason(drop(STATE.NeedOffSpec))
      == "You rolled Offspec and lost.")

# GREED COUNTS. In LFR the client refuses Need on the wrong armor type and
# sometimes refuses Mog for no visible reason, so greed is regularly the only
# roll available rather than a statement about wanting it.
check("A GREED LOSS OFFERS THE BUTTON TOO",
      LootAsk.Reason(drop(STATE.Greed)) == "You rolled Greed and lost.",
      LootAsk.Reason(drop(STATE.Greed)))

# Passing stays out, and that is about noise rather than manners: a night of
# passing on everything would open the window on nearly every drop.
check("passing does not",
      LootAsk.Reason(drop(STATE.Pass)) is None)

check("nor does sitting the roll out",
      LootAsk.Reason(drop(STATE.NoRoll)) is None)

check("nor a drop you were not on the roll list for at all",
      LootAsk.Reason(lua.eval("{ id = 'x', rolls = {} }")) is None)

g.HAS_APPEARANCE = True

check("and a greed loss is not gated on an appearance it never claimed",
      LootAsk.Reason(drop(STATE.Greed)) == "You rolled Greed and lost.")

g.HAS_APPEARANCE = False

# The other side of the same drop belongs to the trade advisor.
mine = drop(STATE.Transmog, winner=ME)
mine.winnerName = "Arcangila"

check("winning it yourself offers nothing here",
      LootAsk.Consider(mine) is False)


# ------------------------------------------------------------- who to whisper

reset()

check("the whisper is addressed across realms, from the GUID",
      LootAsk.WhisperTarget(drop(STATE.Transmog)) == "Sleepadin-Silvermoon",
      LootAsk.WhisperTarget(drop(STATE.Transmog)))

unknown = drop(STATE.Transmog, winner="Player-60-DEADBEEF")

check("and falls back to the name on the roll list when the GUID is a stranger",
      LootAsk.WhisperTarget(unknown) == "Sleepadin")


# ------------------------------------------------------------- what it types

reset()

check("the default wording is the one Aimee wrote",
      AskWording.DEFAULT == "Hi there, could I have [item] if you don't need it?",
      AskWording.DEFAULT)

record = drop(STATE.Transmog)
line, length = AskWording.Line("Sleepadin-Silvermoon", record)

check("[item] becomes the real item link", LINK in line)

check("and the line is addressed to the realm-qualified name",
      line.startswith("/w Sleepadin-Silvermoon "), line[:40])

# 109 of these are the link and 11 more are the winner's realm, which the
# whisper cannot be addressed without. The words themselves are 51 of 178.
check("the composed length is the real one, link markup and all",
      length == 178, length)

check("and addressing it across realms is what the last 11 of those are",
      AskWording.Line("Sleepadin", record)[1] == length - len("-Silvermoon"))

check("which is inside what a whisper allows",
      length < AskWording.CHAT_LIMIT)

check("[player] becomes the short name, not the realm-qualified one",
      AskWording.Compose(record, "Hi [player], anything for [player]?")
      == "Hi Sleepadin, anything for Sleepadin?")

# gsub reads % in a replacement as a capture reference, and an item link
# arrives from the server. This is the crash that would happen inside a chat
# prefill rather than anywhere findable.
percent = drop(STATE.Transmog, drop_id="percent")
percent.itemLink = "|cff0070dd|Hitem:1::::|h[100%% Silk]|h|r"

check("an item link carrying a percent sign does not blow up the substitution",
      "Silk" in AskWording.Compose(percent))

ok, message = AskWording.Set("   ")

check("an empty wording is refused rather than saved", ok is False)
check("and it says what to do instead", message and "default" in message)

AskWording.Set("  Any chance on [item]?  ")

check("a saved wording is trimmed and used",
      AskWording.Get() == "Any chance on [item]?", AskWording.Get())

AskWording.Reset()

check("and the default can be put back", AskWording.Get() == AskWording.DEFAULT)


# ------------------------------------------------------------- the two hours

reset()

check("a loss inside the window is remembered",
      LootAsk.Consider(drop(STATE.Transmog)) is True)

check("and is offered once, not once per resolution pass",
      LootAsk.Consider(drop(STATE.Transmog)) is False)

active = LootAsk.Active()

check("it is active, with the clock and the target on it",
      len(active) == 1
      and active[1].target == "Sleepadin-Silvermoon"
      and active[1].secondsLeft == 7200,
      len(active))

LootAsk.MarkAsked("the-drop")
active = LootAsk.Active()

check("ASKING DOES NOT REMOVE IT — Escape instead of Enter sends nothing",
      len(active) == 1 and active[1].asked is True)

LootAsk.Dismiss("the-drop")

check("dismissing does remove it", len(LootAsk.Active()) == 0)

check("AND A LATER RESOLUTION PASS DOES NOT BRING IT BACK",
      LootAsk.Consider(drop(STATE.Transmog)) is False
      and len(LootAsk.Active()) == 0)

reset()

# Two hours and a second after the item was awarded.
LootAsk.Consider(drop(STATE.Transmog, when=g.NOW - 7201, drop_id="stale"))

check("a drop already outside its trade window is never offered",
      len(LootAsk.Active()) == 0)

reset()
LootAsk.Consider(drop(STATE.Transmog, drop_id="expiring"))
g.NOW = g.NOW + 7201

check("and one that ages out is swept",
      len(LootAsk.Active()) == 0 and LootAsk.Sweep() == 0,
      "swept on read, so nothing is left to sweep twice")

g.NOW = 1787094714

reset()
g.FEATURE_ON = False

check("with the feature off, nothing is watched at all",
      LootAsk.Consider(drop(STATE.Transmog, drop_id="off")) is False
      and len(LootAsk.Active()) == 0)


# --------------------------------------------------------- the standing rule

sends = []

for path in sorted(list((ROOT / "Core").glob("*.lua"))
                   + list((ROOT / "UI").glob("*.lua"))):
    body = path.read_text(encoding="utf-8")

    # Comments discuss it by name on purpose -- that is where the rule is
    # written down -- so only real calls count.
    for line in body.splitlines():
        stripped = line.strip()

        if stripped.startswith("--"):
            continue

        if re.search(r"\bSendChatMessage\s*\(", line):
            sends.append(path.name)

check("NO FILE IN THE ADDON SENDS A CHAT MESSAGE",
      not sends,
      "found in: " + ", ".join(sorted(set(sends))) if sends else "")

# And the door that does exist is a prefill, in both places that have one.
panel = (ROOT / "UI" / "LootAskPanel.lua").read_text(encoding="utf-8")

check("the Ask button opens the chat box rather than sending",
      "ChatFrame_OpenChat" in panel)

# Long strings in this codebase are written as concatenated literals, so the
# sentence is looked for after the joins are closed up rather than as one
# literal -- otherwise rewrapping a line silently disarms the check.
joined = re.sub(r'"\s*\.\.\s*"', "", panel)

check("the window says so on its own face, not only in a tooltip",
      "Nothing is sent until you press Enter." in joined)

# Off by default, like everything else here that goes anywhere near chat.
features = (ROOT / "Core" / "Features.lua").read_text(encoding="utf-8")

check("and the whole feature is off until somebody turns it on",
      re.search(r"^\s*lootAsk = false,", features, re.M) is not None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
