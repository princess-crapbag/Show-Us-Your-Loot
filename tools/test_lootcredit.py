"""Credit moved by hand, and put back.

THE SHAPE THIS TESTS IS AIMEE'S GUILD, not a made-up one. Under a loot council
the master looter wins every group-loot roll and hands the item over through an
addon SYL cannot see, so every drop is recorded as hers — and on most of them
every other raider passed and she took it on a Transmog roll. That is two wrong
numbers per drop, not one: the person is wrong, and so is the response the drop
is scored on, because the recorded state is her roll and not theirs.

So the assertions come in pairs. Moving the name alone is checked to move
nothing when the recorded response was Transmog, because that is exactly the
half-fix that would look right on screen and leave the board wrong.

UNDO IS TESTED BEFORE THE CHANGE IS. Nothing on any screen could show or
reverse a credit before this feature, so the reversal is the part that has to
work — a wrong correction with no way back is worse than no correction.

DueList and LootScore are asserted together throughout. Those two are allowed
to disagree about nothing: a fix applied to one is worse than no fix at all,
because then the officer has two lists and no way to tell which lies.

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

ML = "Player-1-0000ML"       # the master looter, who wins everything
RECIPIENT = "Player-1-0000R1"  # who the item actually went to
BYSTANDER = "Player-1-0000R2"

NEED = 0
TRANSMOG = 2
GREED = 3

NOW = 1700000000


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


lua.execute(
    """
    function Setup()
        ShowUsYourLootDB = nil
        ShowUsYourLoot.DatabaseInitialize()

        local season = ShowUsYourLootDB.activeSeason

        local roster = {
            [ '""" + ML + """' ] = {
                guid = '""" + ML + """', name = 'Arcangila', class = 'HUNTER',
            },
            [ '""" + RECIPIENT + """' ] = {
                guid = '""" + RECIPIENT + """', name = 'Phreestyle',
                class = 'SHAMAN',
            },
            [ '""" + BYSTANDER + """' ] = {
                guid = '""" + BYSTANDER + """', name = 'Rakahasa',
                class = 'SHAMAN',
            },
        }

        season.raids = {}

        -- Four nights so everybody clears MIN_NIGHTS and can be ranked.
        for night = 1, 4 do
            table.insert(season.raids, {
                id = 'r' .. night,
                startedAt = """ + str(NOW) + """ - (5 - night) * 86400,
                instanceID = 1,
                instanceName = 'The Venomous Abyss',
                instanceType = 'raid',
                difficultyID = 14,
                difficultyName = 'Normal',
                dateText = '2026-08-1' .. night,
                encounters = {
                    { name = "Nek'zali the Soulcoiler", killed = true },
                },
                roster = roster,
            })
        end

        -- The master-looter shape: she wins on a Transmog roll and every other
        -- raider passed. Worth nothing to anybody as recorded.
        season.drops = {
            {
                id = 'drop1',
                timestamp = """ + str(NOW) + """,
                itemName = 'Hexing Spiritrender',
                itemLink = 'item:268203',
                itemID = 268203,
                instanceType = 'raid',
                difficultyID = 14,
                difficultyName = 'Normal',
                instanceName = 'The Venomous Abyss',
                encounterName = "Nek'zali the Soulcoiler",
                winnerGUID = '""" + ML + """',
                winnerName = 'Arcangila',
                winnerClass = 'HUNTER',
                winnerState = """ + str(TRANSMOG) + """,
                winnerRoll = 51,
                source = 'LOOT_HISTORY',
                rolls = {
                    {
                        guid = '""" + ML + """', name = 'Arcangila',
                        class = 'HUNTER',
                        state = """ + str(TRANSMOG) + """,
                        roll = 51, isWinner = true,
                    },
                    {
                        guid = '""" + RECIPIENT + """', name = 'Phreestyle',
                        class = 'SHAMAN', state = 5,
                    },
                    {
                        guid = '""" + BYSTANDER + """', name = 'Rakahasa',
                        class = 'SHAMAN', state = 5,
                    },
                },
            },
        }

        ShowUsYourLootDB.tradeWindow = {}
        ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    end

    -- Score per person, off the same call the Raiders board makes.
    function ScoreFor(name)
        local drops = ShowUsYourLoot.GetActiveDrops()
        local totals = ShowUsYourLoot.LootScore.BuildTotals(drops)

        for _, entry in ipairs(
            ShowUsYourLoot.DueList.Build(drops, ShowUsYourLoot.GetActiveRaids())
        ) do
            if entry.name == name then
                local total = totals[entry.key]

                return total and total.score or 0
            end
        end

        return nil
    end

    -- The drought half of the same question. Allowed to disagree with the
    -- score about nothing.
    function EverWon(name)
        local drops = ShowUsYourLoot.GetActiveDrops()

        for _, entry in ipairs(
            ShowUsYourLoot.DueList.Build(drops, ShowUsYourLoot.GetActiveRaids())
        ) do
            if entry.name == name then
                return entry.everWon and true or false
            end
        end

        return nil
    end

    function Credit(guid, name, state)
        return ShowUsYourLoot.LootCredit.Set('drop1', {
            guid = guid, name = name, state = state,
        })
    end

    function ClearCredit()
        return ShowUsYourLoot.LootCredit.Clear('drop1')
    end

    function Record()
        return ShowUsYourLoot.LootHistoryStore.GetRecord('drop1')
    end

    function DescribeCredit()
        return ShowUsYourLoot.LootCredit.Describe(Record())
    end

    -- The Players window's columns and the block that gets pasted into
    -- Discord. A different code path from the board, and the one that has
    -- disagreed with it before. Keyed by GUID rather than name because a
    -- credited key the registry has never seen carries the key as its name.
    function AnalyticsCounts(key)
        for _, entry in ipairs(
            ShowUsYourLoot.Analytics.BuildPlayerStats(
                ShowUsYourLoot.GetActiveDrops()
            )
        ) do
            if entry.key == key then
                return entry.wins, entry.mogWins, entry.greedWins,
                    entry.needWins, entry.upgradeWins
            end
        end

        return nil
    end

    function CandidateNames()
        local names = {}

        for _, candidate in ipairs(
            ShowUsYourLoot.CreditCandidates.Build(Record())
        ) do
            table.insert(names, candidate.name)
        end

        table.sort(names)

        return table.concat(names, ',')
    end
    """
)

g = lua.globals()

# --- as recorded ----------------------------------------------------------
g.Setup()

check("the master looter is credited with the win", g.ScoreFor("Arcangila") == 0,
      g.ScoreFor("Arcangila"))
check("and it is worth nothing, because she rolled Transmog",
      g.ScoreFor("Phreestyle") == 0, g.ScoreFor("Phreestyle"))
check("nobody has had an upgrade",
      g.EverWon("Arcangila") is False and g.EverWon("Phreestyle") is False)

describe = g.DescribeCredit()
check("the credit line says the roll decided it", describe.source == "roll",
      describe.source)
check("and names the winner", describe.name == "Arcangila", describe.name)

# --- the half-fix that would have looked right ----------------------------
# Moving only the person, leaving the response as recorded. This is the whole
# reason CreditedState exists beside CreditedKey.
g.Credit(RECIPIENT, "Phreestyle", None)

check(
    "moving only the name moves the credit",
    g.DescribeCredit().name == "Phreestyle",
    g.DescribeCredit().name,
)
check(
    "but moves no points at all, because Transmog weighs nothing",
    g.ScoreFor("Phreestyle") == 0,
    g.ScoreFor("Phreestyle"),
)

# --- the whole fix --------------------------------------------------------
g.ClearCredit()
g.Credit(RECIPIENT, "Phreestyle", GREED)

check("the recipient is credited", g.ScoreFor("Phreestyle") == 20,
      g.ScoreFor("Phreestyle"))
check("the master looter keeps none of it", g.ScoreFor("Arcangila") == 0,
      g.ScoreFor("Arcangila"))
check("and nobody else is touched", g.ScoreFor("Rakahasa") == 0,
      g.ScoreFor("Rakahasa"))

describe = g.DescribeCredit()
check("the line says a person did this", describe.source == "manual",
      describe.source)
check("and remembers who it was taken from", describe.priorName == "Arcangila",
      describe.priorName)
check("and what it used to be worth", describe.priorState == TRANSMOG,
      describe.priorState)

# HISTORY IS NOT REWRITTEN. "Won by Arcangila with 51" has to still read that
# way, because that is what the client reported.
record = g.Record()
check("the roll winner is untouched", record.winnerName == "Arcangila",
      record.winnerName)
check("and so is the winning roll", record.winnerRoll == 51, record.winnerRoll)
check("and so is the roll list", record.rolls[1].isWinner is True)

# --- UNDO, which is the point --------------------------------------------
g.ClearCredit()

check("undo puts the score back", g.ScoreFor("Phreestyle") == 0,
      g.ScoreFor("Phreestyle"))
check("undo puts the credit back", g.DescribeCredit().name == "Arcangila",
      g.DescribeCredit().name)
check("and the line stops claiming a person did it",
      g.DescribeCredit().source == "roll", g.DescribeCredit().source)
check("undo leaves nothing behind on the record",
      g.Record().creditOverride is None)

# Undoing something that was never set is a no-op rather than an error.
g.ClearCredit()
check("undoing twice is harmless", g.ScoreFor("Arcangila") == 0,
      g.ScoreFor("Arcangila"))

# --- a correction to Need resets a drought -------------------------------
g.Credit(RECIPIENT, "Phreestyle", NEED)

check("a Need correction is worth the full 100", g.ScoreFor("Phreestyle") == 100,
      g.ScoreFor("Phreestyle"))
check(
    "the drought resets for the recipient, not the winner",
    g.EverWon("Phreestyle") is True and g.EverWon("Arcangila") is False,
    (g.EverWon("Phreestyle"), g.EverWon("Arcangila")),
)

g.ClearCredit()
check("and undo puts the drought back too", g.EverWon("Phreestyle") is False)

# --- it is not a trade, and the trade switch must not touch it -----------
# A trade is an observation, and turning observation off puts the numbers back
# where the client last saw them. A hand-made correction is a statement about
# what really happened, and a setting nobody remembers touching must not
# silently revert it.
g.Credit(RECIPIENT, "Phreestyle", GREED)
SYL.Features.SetEnabled("tradeTracking", False)

check(
    "turning trade tracking off leaves a hand-made credit alone",
    g.ScoreFor("Phreestyle") == 20,
    g.ScoreFor("Phreestyle"),
)

SYL.Features.SetEnabled("tradeTracking", True)

check(
    "and turning it back on changes nothing either",
    g.ScoreFor("Phreestyle") == 20,
    g.ScoreFor("Phreestyle"),
)

# --- a correction beats a witnessed trade --------------------------------
# If the addon watched a trade and was told otherwise afterwards, the person
# doing the telling was in the raid and the addon was not.
lua.execute(
    """
    local record = ShowUsYourLoot.LootHistoryStore.GetRecord('drop1')

    record.tradedTo = 'Rakahasa'
    record.tradedToGUID = '""" + BYSTANDER + """'
    """
)

check(
    "a correction outranks a trade the addon saw",
    g.ScoreFor("Phreestyle") == 20 and g.ScoreFor("Rakahasa") == 0,
    (g.ScoreFor("Phreestyle"), g.ScoreFor("Rakahasa")),
)

g.ClearCredit()

check(
    "and removing the correction hands the drop back to the trade",
    g.DescribeCredit().name == "Rakahasa",
    g.DescribeCredit().name,
)

check(
    "the trade is what the line reports once the correction is gone",
    g.DescribeCredit().source == "traded",
    g.DescribeCredit().source,
)

# The scores agree with that, and this is the assertion worth having: the
# points follow the trade only because the correction stopped holding them.
# Checked on a Need drop, so that a zero-weight state cannot make both sides
# look equal and pass by accident.
lua.execute(
    """
    local record = ShowUsYourLoot.LootHistoryStore.GetRecord('drop1')

    record.rolls[1].state = """ + str(NEED) + """
    record.winnerState = """ + str(NEED) + """
    """
)

check(
    "the traded-to player holds the points with no correction in place",
    g.ScoreFor("Rakahasa") == 100 and g.ScoreFor("Phreestyle") == 0,
    (g.ScoreFor("Rakahasa"), g.ScoreFor("Phreestyle")),
)

g.Credit(RECIPIENT, "Phreestyle", NEED)

check(
    "and a correction takes them off the trade recipient",
    g.ScoreFor("Phreestyle") == 100 and g.ScoreFor("Rakahasa") == 0,
    (g.ScoreFor("Phreestyle"), g.ScoreFor("Rakahasa")),
)

# --- the Players window and the export agree with the board ---------------
# Analytics is a separate sweep feeding the UPGRADES column and the block that
# gets pasted into Discord, and it is the screen that has disagreed with the
# board before. Its own header says why that is the expensive kind of wrong:
# the exported number is the one other people read.
g.Setup()

wins, mog, greed, need, upgrades = g.AnalyticsCounts(ML)
check(
    "as recorded, the master looter holds the mog win",
    (wins, mog, greed, need, upgrades) == (1, 1, 0, 0, 0),
    (wins, mog, greed, need, upgrades),
)

g.Credit(RECIPIENT, "Phreestyle", GREED)

# She stays on the list with nothing on it, which is right: eligibility is not
# credit, and she was standing there and rolled. Only the win moves.
wins, mog, greed, need, upgrades = g.AnalyticsCounts(ML)
check(
    "the corrected win leaves the master looter holding none of it",
    (wins, mog, greed, need, upgrades) == (0, 0, 0, 0, 0),
    (wins, mog, greed, need, upgrades),
)

wins, mog, greed, need, upgrades = g.AnalyticsCounts(RECIPIENT)
check(
    "and lands on the recipient in the greed column, not the mog one",
    (wins, mog, greed, need, upgrades) == (1, 0, 1, 0, 0),
    (wins, mog, greed, need, upgrades),
)

g.Credit(RECIPIENT, "Phreestyle", NEED)
wins, mog, greed, need, upgrades = g.AnalyticsCounts(RECIPIENT)
check(
    "a Need correction reaches the UPGRADES column too",
    (wins, need, upgrades) == (1, 1, 1),
    (wins, need, upgrades),
)

g.ClearCredit()
wins, mog, greed, need, upgrades = g.AnalyticsCounts(ML)
check(
    "and undo puts the Players window back as well",
    (wins, mog, greed, need, upgrades) == (1, 1, 0, 0, 0),
    (wins, mog, greed, need, upgrades),
)

# --- a leftover override credits nobody ----------------------------------
# A table with neither a GUID nor a name is not an override, it is a leftover.
# Honoring it would move the points to a key nothing reads — they leave the
# winner and arrive nowhere, which is worse than not moving them.
g.Setup()

lua.execute(
    """
    ShowUsYourLoot.LootHistoryStore.GetRecord('drop1').creditOverride = {
        state = 0,
    }
    """
)

check("an override naming nobody is ignored",
      g.DescribeCredit().name == "Arcangila", g.DescribeCredit().name)
check("and does not silently apply its weight",
      g.ScoreFor("Arcangila") == 0, g.ScoreFor("Arcangila"))

# --- who the picker offers ------------------------------------------------
# THE ROLL LIST CANNOT BE THE CANDIDATE LIST. Everyone passed here, which is
# the ordinary shape under a loot council — a picker built from the people who
# actually rolled would offer exactly one name.
g.Setup()

check(
    "the picker offers the whole session roster, not just the winner",
    g.CandidateNames() == "Arcangila,Phreestyle,Rakahasa",
    g.CandidateNames(),
)

# --- a drop that is not in the database ----------------------------------
ok, reason = SYL.LootCredit.Set("no-such-drop", lua.eval("{ name = 'Nobody' }"))
check("crediting a drop that is not there says so", ok is None and reason,
      reason)

ok, reason = SYL.LootCredit.Set("drop1", lua.eval("{ }"))
check("crediting nobody says so too", ok is None and reason, reason)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
