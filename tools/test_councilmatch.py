"""Matching a season's credit to RCLootCouncil, in one press and with a look.

Aimee: "after i give out loot i need to go into the loot window and select
each item and credit the loot to match what rclc said along with changing a
need roll to need when it sometimes says need but lists it in my drop detail
window as greed."

Both halves matter and the second is the one that gets forgotten. Under a
council everybody passes and the master looter takes the item, so the recorded
WINNER is her on every drop and the recorded RESPONSE is her roll rather than
the recipient's answer. Moving only the name would leave four Transmog wins
weighing nothing against a raider who actually needed the item --
Core/DropRules.lua measured exactly that on 2026-08-18.

What is worth guarding:

1. NOTHING CHANGES UNTIL IT IS APPLIED. Building the list must not touch a
   single drop. She chose review over automatic -- "i like review for matching
   the rclootcouncil" -- and a preview that quietly commits is worse than no
   preview.

2. A RESPONSE THIS ADDON CANNOT PLACE MUST NOT BE INVENTED. Guilds rewrite
   RCLootCouncil's buttons, so an unrecognized one moves the NAME and leaves
   the weight alone, and the row says so.

3. DROPS THAT ALREADY AGREE ARE NOT LISTED. A review naming things that will
   not change is a review nobody reads twice.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from lupa import LuaRuntime  # noqa: F401  (imported for the error message)
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

import test_load  # noqa: E402  — reuses its stubbed client and loaded addon

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

ROLL_STATE = SYL.LootHistoryAPI.ROLL_STATE

# --- 1. the words, not the numbers ----------------------------------------
#
# RCLootCouncil ships three buttons -- Mainspec/Need, Offspec/Greed, Minor
# Upgrade -- and every guild rewrites them. Aimee's has a Mog button their
# defaults do not include, which is why matching on their response NUMBER
# would score one guild's Mog as another guild's Minor Upgrade.
def state_for(text):
    return SYL.CouncilMatch.StateFor(lua.table_from({"response": text}))


check("Mainspec/Need is Need",
      state_for("Mainspec/Need") == ROLL_STATE.NeedMainSpec,
      state_for("Mainspec/Need"))
check("and so is a plain Need button",
      state_for("Need") == ROLL_STATE.NeedMainSpec)

check("OFFSPEC WINS OVER GREED in 'Offspec/Greed', which holds both words",
      state_for("Offspec/Greed") == ROLL_STATE.NeedOffSpec,
      state_for("Offspec/Greed"))
check("a plain Greed button is Greed",
      state_for("Greed") == ROLL_STATE.Greed)

check("Mog is Transmog", state_for("Mog") == ROLL_STATE.Transmog)
check("and so is Transmog", state_for("Transmog") == ROLL_STATE.Transmog)
check("Pass is Pass", state_for("Pass") == ROLL_STATE.Pass)
check("case does not matter", state_for("MAINSPEC/NEED")
      == ROLL_STATE.NeedMainSpec)

check("A BUTTON THIS ADDON CANNOT PLACE ANSWERS NOTHING, rather than guessing",
      state_for("Minor Upgrade") is None, state_for("Minor Upgrade"))
check("and neither does a missing response", state_for(None) is None)

# --- the sweep ------------------------------------------------------------
ARC = "Player-1-ARC00001"
RAK = "Player-1-RAK00001"
HAWT = "Player-1-HAWT0001"

for guid, name, klass in ((ARC, "Arcangila", "HUNTER"),
                          (RAK, "Rakahasa", "SHAMAN"),
                          (HAWT, "Hawt", "ROGUE")):
    SYL.Players.Ensure(lua.table_from({
        "guid": guid, "name": name, "fullName": name + "-Area52",
        "class": klass}))


def drop(record_id, item, timestamp):
    """A council night: the master looter wins everything, recorded Greed."""
    return lua.table_from({
        "id": record_id,
        "itemID": 180000,
        "itemName": item,
        "timestamp": timestamp,
        "dateText": "2026-09-03",
        "winnerName": "Arcangila",
        "winnerGUID": ARC,
        "winnerState": ROLL_STATE.Greed,
        "rolls": lua.table_from([
            lua.table_from({"name": "Arcangila", "guid": ARC,
                            "class": "HUNTER", "state": ROLL_STATE.Greed,
                            "roll": 90, "isWinner": True}),
        ]),
    })


season = SYL.GetActiveSeason()
season.drops[1] = drop("d1", "Venomcured Relic", 100)
season.drops[2] = drop("d2", "Ophidian Fangmail", 200)
season.drops[3] = drop("d3", "Idol of the Howling Nexus", 300)

# RCLootCouncil, stubbed at the seam Core/CouncilLoot.lua reads. Nothing here
# reaches into their addon: SuggestedCredit is the whole of the integration.
AWARDS = {
    "d1": ("Hawt", "Mainspec/Need"),
    "d2": ("Rakahasa", "Mainspec/Need"),
    "d3": ("Rakahasa", "Minor Upgrade"),
}

lua.execute("""
    local SYL = ShowUsYourLoot
    AWARDS = {}

    SYL.CouncilLoot.IsPresent = function() return true end

    SYL.CouncilLoot.SuggestedCredit = function(drop)
        local award = AWARDS[drop.id]

        if not award then
            return nil
        end

        -- The real one returns nil when the award names whoever is already
        -- credited, which is what keeps a matched night off the list.
        local current = SYL.LootCredit.Describe(drop)

        if current and current.name == award.name then
            return nil
        end

        return { name = award.name, response = award.response }
    end
""")

for key, (name, response) in AWARDS.items():
    lua.globals().AWARDS[key] = lua.table_from(
        {"name": name, "response": response})

changes = SYL.CouncilMatch.Build(season)

check("EVERY MISMATCHED DROP IS FOUND", len(changes) == 3, len(changes))
check("oldest first, the order a night is read in",
      changes[1].itemName == "Venomcured Relic", changes[1].itemName)

check("the row carries WHO IT IS NOW as well as who it becomes",
      changes[1].fromName == "Arcangila" and changes[1].toName == "Hawt",
      (changes[1].fromName, changes[1].toName))

check("A RECOGNIZED RESPONSE MOVES THE WEIGHT TOO",
      changes[1].state == ROLL_STATE.NeedMainSpec, changes[1].state)
check("AND AN UNRECOGNIZED ONE MOVES ONLY THE NAME",
      changes[3].state is None and "name only"
      in SYL.CouncilMatch.Describe(changes[3]),
      SYL.CouncilMatch.Describe(changes[3]))

# --- 1. building must not change anything ---------------------------------
check("BUILDING THE REVIEW CHANGES NOTHING",
      season.drops[1].creditOverride is None
      and season.drops[2].creditOverride is None,
      "a drop was credited before anybody pressed Apply")

summary = SYL.CouncilMatch.Summarize(changes)

check("the summary counts drops and people, and says nothing has happened",
      "3 drops" in summary and "Nothing changes until" in summary, summary)

# --- applying -------------------------------------------------------------
applied, failed = SYL.CouncilMatch.ApplyAll(changes)

check("APPLYING CREDITS EVERY ONE", applied == 3 and failed == 0,
      (applied, failed))

first = SYL.LootCredit.Describe(season.drops[1])

check("the item is now the other person's",
      first.name == "Hawt", first.name)
check("AND THE RESPONSE IS CORRECTED, not left as the master looter's roll",
      first.state == ROLL_STATE.NeedMainSpec, first.state)

third = SYL.LootCredit.Describe(season.drops[3])

check("while an unplaceable response moves the name and not the weight",
      third.name == "Rakahasa" and third.state == ROLL_STATE.Greed,
      (third.name, third.state))

# --- 3. a matched night does not show up again ----------------------------
again = SYL.CouncilMatch.Build(season)

check("A SECOND SWEEP FINDS NOTHING", len(again) == 0, len(again))
check("and says so in words rather than showing an empty table",
      "already matches" in SYL.CouncilMatch.Summarize(again),
      SYL.CouncilMatch.Summarize(again))

# --- RCLootCouncil absent --------------------------------------------------
lua.execute("""
    ShowUsYourLoot.CouncilLoot.IsPresent = function() return false end
""")

empty, reason = SYL.CouncilMatch.Build(season)

check("WITHOUT RCLOOTCOUNCIL IT SAYS SO, rather than reporting nothing to do",
      len(empty) == 0 and reason and "not loaded" in reason, reason)

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
