# -*- coding: utf-8 -*-
"""Telling "I checked this and it is mine" from "nobody has looked at this".

Aimee: "since were using RClootcouncil, when loot drops can it be listed as
'MasterLooter Won' and only reassigned to me when i award it to me via rclc?
that way its clear what i received vs what i won as ml"

THE PREMISE WAS CHECKED AND IT DID NOT SURVIVE, which is why this is a marker
and not an auto-credit. Two of her drops looked like missed corrections --
Boots of the Reckless Wayfarer and Shellbound Bracers, both still credited to
her from a batch whose third item was reassigned. Both are in RCLootCouncil's
own award history under her name, with votes. They are real master-looter
wins, and an RCLootCouncil-driven auto-credit would have written exactly what
is already there.

So the credit is not wrong. What was missing is that "I reviewed this and kept
it" and "this has never been looked at" both rendered as source = "roll" and
drew the same six words.

WHY THE MATCH BUTTON DOES NOT WRITE. RCLootCouncil ships three responses and
every guild renames them: slot 3 is "Minor Upgrade" on a default install and
"Mog" on hers. The same numeric id means real gear on one machine and a
cosmetic on another, and this addon ships to strangers. There is no mapping
that is right for everybody, so it pre-fills the picker and a person confirms.

WHAT MUST NOT HAPPEN: an unreviewed drop being withheld from the fairness
math. That would put eighteen items in limbo instead of two, and
Core/CreditCandidates.lua explains why the roll list cannot supply a
replacement -- under a council everybody passes, so the only candidate the
client offers is the master looter. This marks; it does not withhold.

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


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

STATE = SYL.LootHistoryAPI.ROLL_STATE

# A master-looted session, shaped like hers: the looter is stored with a
# realm and the drops name her without one.
lua.execute("""
    ShowUsYourLootDB.seasons = ShowUsYourLootDB.seasons or {}

    RAIDS = ShowUsYourLoot.GetActiveRaids()

    table.insert(RAIDS, {
        id = "ml",
        instanceType = "raid",
        difficultyID = 14,
        startedAt = 1000,
        endedAt = 5000,
        dateText = "1970-01-01",
        recordedBy = "Arcangila-Area52",
        masterLooter = "Arcangila-Area52",
        lootMethod = "master",
        encounters = {},
        roster = {},
    })
""")


def drop(dropID, winner, override=None):
    fields = {
        "id": dropID,
        "timestamp": 2000,
        "winnerName": winner,
        "winnerGUID": winner,
        "winnerState": STATE.NeedMainSpec,
        "itemLink": "|Hitem:%s::::::::80:::::|h[Thing]|h" % dropID,
        "rolls": lua.table_from([]),
    }

    if override:
        fields["creditOverride"] = lua.table_from(override)

    return lua.table_from(fields)


Rules = SYL.DropRules

unreviewed = drop("1", "Arcangila")
reviewed = drop("2", "Arcangila",
                {"name": "Rakahasa-Stormrage", "guid": "Rakahasa-Stormrage"})
someoneElse = drop("3", "Phreestyle")


# --------------------------------------------------------------------------
# What needs a look
# --------------------------------------------------------------------------

check("a master looter's own uncorrected win needs review",
      Rules.NeedsReview(unreviewed) is True)

# THE NAME FORM. The looter is "Arcangila-Area52" and the drop says
# "Arcangila". Core/RaidSession.lua records what a direct compare cost the
# last time: it found nobody and quietly turned the guild filter off.
check("even though one carries a realm and the other does not",
      Rules.NeedsReview(unreviewed) is True)

check("a drop that has been corrected does not",
      Rules.NeedsReview(reviewed) is False)

check("nor does a drop somebody else won",
      Rules.NeedsReview(someoneElse) is False)

check("nor a nil drop", Rules.NeedsReview(None) is False)

# A NIGHT WITH NO MASTER LOOTER RECORDED - which is every night already in her
# database - must not mark everything. Absence of the field is "not known",
# not "everybody".
lua.execute("RAIDS[1].masterLooter = nil")

check("a session that never recorded a master looter marks nothing",
      Rules.NeedsReview(unreviewed) is False)

lua.execute('RAIDS[1].masterLooter = "Arcangila-Area52"')


# --------------------------------------------------------------------------
# It marks and does not withhold
# --------------------------------------------------------------------------
#
# The dangerous version of this feature takes an unreviewed drop out of the
# fairness math. That is eighteen items in limbo rather than two.

check("an unreviewed drop still counts toward fairness",
      Rules.CountsAsUpgrade(unreviewed) is True)

check("and still credits its winner",
      str(Rules.CreditedKey(unreviewed, "Arcangila")) == "Arcangila")

check("and still counts as going home with gear",
      Rules.WorthHaving(unreviewed) is not None)


# --------------------------------------------------------------------------
# The words on screen
# --------------------------------------------------------------------------

described = SYL.LootCredit.Describe(unreviewed)

check("an unreviewed drop describes itself as the master looter's",
      str(described.source) == "masterloot", "got %r" % described.source)

check("and still names the winner",
      str(described.name) == "Arcangila")

check("a corrected drop is still manual",
      str(SYL.LootCredit.Describe(reviewed).source) == "manual")

check("and somebody else's win is still a roll",
      str(SYL.LootCredit.Describe(someoneElse).source) == "roll")

credit_src = test_load.ROOT.joinpath("UI/DropCredit.lua").read_text(
    encoding="utf-8")

check("and the two states no longer share the same words",
      "master looter -- not assigned to anybody yet" in credit_src
      and "won the roll, never traded" in credit_src)


# --------------------------------------------------------------------------
# The RCLootCouncil match
# --------------------------------------------------------------------------

Council = SYL.CouncilLoot

check("with RCLootCouncil absent, nothing is suggested",
      Council.SuggestedCredit(unreviewed) is None)

lua.execute("""
    RCLootCouncil = {
        db = { profile = { sendSessionResponses = true } },
    }

    function RCLootCouncil:GetHistoryDB()
        return {
            ["Rakahasa-Stormrage"] = {
                {
                    lootWon = "|Hitem:1::::::::80:::::|h[Thing]|h",
                    date = date("!%Y/%m/%d", 2000),
                    response = "Mog",
                    responseID = 3,
                    id = "award-1",
                    owner = "Arcangila-Area52",
                },

                -- AN AWARD THAT AGREES WITH THE CREDIT ALREADY IN PLACE.
                -- Drop 2 is already corrected to Rakahasa, so there is
                -- nothing to offer and the button must stay hidden. Without
                -- this row the dedupe branch is never reached and the
                -- assertion below passes because AwardFor found nothing at
                -- all -- which proves nothing.
                {
                    lootWon = "|Hitem:2::::::::80:::::|h[Thing]|h",
                    date = date("!%Y/%m/%d", 2000),
                    response = "Need",
                    responseID = 1,
                    id = "award-2",
                    owner = "Arcangila-Area52",
                },
            },
        }
    end
""")

suggestion = Council.SuggestedCredit(unreviewed)

check("with it present, the award is offered",
      suggestion is not None
      and str(suggestion.name) == "Rakahasa-Stormrage",
      "got %r" % (suggestion and suggestion.name))

# RCLC'S OWN WORDS, NOT A MAPPING. Slot 3 is "Minor Upgrade" by default and
# "Mog" on hers - the same id, meaning gear on one install and a cosmetic on
# another. Shown, never translated.
check("with RCLootCouncil's own word for the response",
      str(suggestion.response) == "Mog")

check("and the award's own id, so two identical items can be told apart",
      str(suggestion.awardID) == "award-1")

# NOTHING TO OFFER when the award agrees with the credit already in place.
# The award for drop 2 names Rakahasa-Stormrage and drop 2 is already
# credited to Rakahasa-Stormrage, so the button has nothing to offer.
check("an award naming who is already credited suggests nothing",
      Council.SuggestedCredit(reviewed) is None,
      "got %r" % (Council.SuggestedCredit(reviewed)
                  and Council.SuggestedCredit(reviewed).name))


# --------------------------------------------------------------------------
# It pre-fills and does not write
# --------------------------------------------------------------------------

before = SYL.LootCredit.Get(unreviewed)

Council.SuggestedCredit(unreviewed)

check("asking for a suggestion writes no credit",
      SYL.LootCredit.Get(unreviewed) == before)

picker = test_load.ROOT.joinpath("UI/CreditPicker.lua").read_text(
    encoding="utf-8")

check("the picker can open on a suggested name",
      "function CreditPicker.Open(record, suggested)" in picker)

check("and the button opens the picker rather than setting the credit",
      "SYL.CreditPicker.Open(" in test_load.ROOT.joinpath(
          "UI/DropDetailWindow.lua").read_text(encoding="utf-8")
      and "LootCredit.Set" not in credit_src)

check("the button is hidden when there is nothing to match",
      "frame.matchButton:SetShown(frame.suggested ~= nil)" in credit_src)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
