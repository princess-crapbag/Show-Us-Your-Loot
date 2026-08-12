"""A traded item counts for whoever received it, in both lists at once.

Until this existed, every traded item was two wrong numbers: the winner kept
credit for loot they gave away, and the person actually wearing it looked like
they had gone without. That is the assertion this file exists for, and it is
checked against DueList and LootScore together — those two are allowed to
disagree about nothing, and a fix applied to one of them is worse than no fix
at all, because then the officer has two lists and no way to tell which lies.

The event order is the other half. TRADE_ACCEPT_UPDATE fires while the slots
are still readable; by the time the trade has completed the frame is closed and
GetTradePlayerItemLink answers nothing. So the slots are captured at acceptance
and committed at LE_GAME_ERR_TRADE_COMPLETE, and a trade that is canceled in
between must record nothing at all.

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

ME = "Player-1-00000001"
NOW = 1700000000
TRADE_COMPLETE = 300


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

        -- Four nights so everybody clears MIN_NIGHTS and can be ranked.
        local roster = {
            [ '""" + ME + """' ] = { guid = '""" + ME + """', name = 'Aimee' },
            P2 = { guid = 'P2', name = 'Selunne' },
        }

        season.raids = {}

        for night = 1, 4 do
            table.insert(season.raids, {
                id = 'r' .. night,
                startedAt = 1699900000 + night * 86400,
                instanceID = 1,
                instanceName = 'Manaforge Omega',
                instanceType = 'raid',
                difficultyID = 16,
                difficultyName = 'Mythic',
                dateText = '2026-08-0' .. night,
                encounters = { { name = 'Plexus Sentinel', killed = true } },
                roster = roster,
            })
        end

        -- Aimee wins a Need worth 100 and it is inside its trade window.
        season.drops = {
            {
                id = 'won1',
                timestamp = """ + str(NOW - 300) + """,
                itemName = 'Robes of the Voidbound',
                itemLink = 'item:1:bonus',
                itemID = 1,
                instanceType = 'raid',
                difficultyID = 16,
                difficultyName = 'Mythic',
                instanceName = 'Manaforge Omega',
                encounterName = 'Plexus Sentinel',
                winnerGUID = '""" + ME + """',
                winnerName = 'Aimee',
                winnerState = 0,
                source = 'LOOT_HISTORY',
                rolls = {
                    {
                        guid = '""" + ME + """', name = 'Aimee',
                        state = 0, isWinner = true,
                    },
                    { guid = 'P2', name = 'Selunne', class = 'PRIEST', state = 0 },
                },
            },
        }

        ShowUsYourLootDB.tradeWindow = {}
        ShowUsYourLoot.LootHistoryStore.RebuildIndex()
        ShowUsYourLoot.TradeAdvisor.Consider(season.drops[1])

        TRADE_SLOT_LINKS = {}
        TRADE_RECIPIENT = nil
    end

    -- Score per person, off the same call the board makes.
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

    -- Whether the due list thinks this person has ever won an upgrade. The
    -- drought half of the same question the score answers.
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

    function DoTrade(recipient, links, complete)
        TRADE_RECIPIENT = recipient
        TRADE_SLOT_LINKS = links

        ShowUsYourLoot.TradeTracker.OnTradeShow()
        ShowUsYourLoot.TradeTracker.OnAcceptUpdate(true, true)

        if complete then
            ShowUsYourLoot.TradeTracker.OnInfoMessage(""" + str(TRADE_COMPLETE) + """)
        end
    end

    function TradedTo()
        local record = ShowUsYourLoot.LootHistoryStore.GetRecord('won1')

        return record and record.tradedTo or nil
    end
    """
)

g = lua.globals()

# --- before any trade -----------------------------------------------------
g.Setup()

check("the winner starts with the score", g.ScoreFor("Aimee") == 100, g.ScoreFor("Aimee"))
check("and the loser with none", g.ScoreFor("Selunne") == 0, g.ScoreFor("Selunne"))
check("the winner has won an upgrade", g.EverWon("Aimee") is True)
check("the loser has not", g.EverWon("Selunne") is False)

# --- the trade ------------------------------------------------------------
g.DoTrade("Selunne", lua.table("item:1:bonus"), True)

check("the item records who received it", g.TradedTo() == "Selunne", g.TradedTo())

# The whole point, asserted on both lists.
check(
    "the score moves to the recipient",
    g.ScoreFor("Selunne") == 100,
    g.ScoreFor("Selunne"),
)
check(
    "and away from the winner who gave it up",
    g.ScoreFor("Aimee") == 0,
    g.ScoreFor("Aimee"),
)
check(
    "the drought resets for the recipient, not the winner",
    g.EverWon("Selunne") is True and g.EverWon("Aimee") is False,
    f"Selunne {g.EverWon('Selunne')}, Aimee {g.EverWon('Aimee')}",
)

# Handed over is not a decision waiting to be made.
check(
    "the advisor stops asking about it",
    len(list(SYL.TradeAdvisor.Active().values())) == 0,
    len(list(SYL.TradeAdvisor.Active().values())),
)

# --- a trade that never completed -----------------------------------------
g.Setup()
g.DoTrade("Selunne", lua.table("item:1:bonus"), False)

check("accepting alone credits nothing", g.TradedTo() is None, g.TradedTo())
check("and the score stays with the winner", g.ScoreFor("Aimee") == 100, g.ScoreFor("Aimee"))

# Canceled after both accepted: the slots were staged and must be dropped.
SYL.TradeTracker.OnTradeClosed()
SYL.TradeTracker.OnInfoMessage(TRADE_COMPLETE)

check("a canceled trade credits nothing", g.TradedTo() is None, g.TradedTo())

# --- one side accepting is not both ---------------------------------------
#
# The slots are only final once both sides have accepted. Snapshotting on a
# half-open trade would record whatever happened to be in the window at the
# moment one person clicked, which the other can still change.
g.Setup()

lua.execute("TRADE_RECIPIENT = 'Selunne'; TRADE_SLOT_LINKS = { 'item:1:bonus' }")

SYL.TradeTracker.OnTradeShow()
SYL.TradeTracker.OnAcceptUpdate(True, False)
SYL.TradeTracker.OnInfoMessage(TRADE_COMPLETE)

check(
    "only one side accepting stages nothing",
    g.TradedTo() is None,
    g.TradedTo(),
)

# --- an item this addon never recorded ------------------------------------
g.Setup()
g.DoTrade("Selunne", lua.table("item:999:other"), True)

check("trading something else changes nothing", g.TradedTo() is None, g.TradedTo())
check("and leaves the score alone", g.ScoreFor("Aimee") == 100, g.ScoreFor("Aimee"))

# --- matching ---------------------------------------------------------------
#
# The exact link wins over the item id, because two wins of the same item at
# different levels are different links and crediting the wrong one moves points
# between two real people.
g.Setup()
g.DoTrade("Selunne", lua.table("item:1:different-bonus"), True)

check(
    "a same-id link still matches when no exact link does",
    g.TradedTo() == "Selunne",
    g.TradedTo(),
)

# --- no recipient ----------------------------------------------------------
g.Setup()
g.DoTrade(None, lua.table("item:1:bonus"), True)

check("a trade with no readable name credits nothing", g.TradedTo() is None, g.TradedTo())

# --- switched off ----------------------------------------------------------
g.Setup()
SYL.Features.SetEnabled("tradeTracking", False)
g.DoTrade("Selunne", lua.table("item:1:bonus"), True)

check("with the feature off nothing is recorded", g.TradedTo() is None, g.TradedTo())

# And an already-recorded trade stops being applied, so turning it off puts the
# numbers back rather than freezing them wherever they had got to.
# Both fields, the way a real record carries them: the name is what is shown
# and the GUID is what the maths is keyed by.
lua.execute(
    """
    local record = ShowUsYourLoot.LootHistoryStore.GetRecord('won1')

    record.tradedTo = 'Selunne'
    record.tradedToGUID = 'P2'
    """
)

check(
    "and an existing record stops moving the score",
    g.ScoreFor("Aimee") == 100,
    g.ScoreFor("Aimee"),
)

SYL.Features.SetEnabled("tradeTracking", True)

check(
    "turning it back on moves it again",
    g.ScoreFor("Selunne") == 100,
    g.ScoreFor("Selunne"),
)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
