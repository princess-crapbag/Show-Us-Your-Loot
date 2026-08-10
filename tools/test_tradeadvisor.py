"""The trade advisor works on install night, and only for the winner.

THE COLD START IS THE FEATURE, so it is the first thing asserted. Every other
screen in this addon needs a season of history before it says anything: the
score, the board and the calendar all read as empty on the first evening. This
one reads the roll list, which the game hands over complete at the moment an
item is awarded — so with zero raid nights and zero prior drops it must still
name everybody who rolled and lost. If that ever regresses, the reason five
reviewers put this top has gone with it.

The other half is that it must not fire for anybody but the winner. Only the
winner's client can act on a trade, and a panel that opened on twenty-five
screens at once would be the single most annoying thing the addon does.

Expiry is measured from the record's own timestamp rather than from when the
addon noticed, because Blizzard's two hours starts when the item is awarded.
An item won five minutes before a /reload has 1h55m left, not two hours.

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

# test_load stubs UnitGUID to this, so it is who "the player" is here.
ME = "Player-1-00000001"

# time() is stubbed to this for a non-table argument.
NOW = 1700000000
HOUR = 3600


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


lua.execute(
    """
    -- NeedMainSpec 0, NeedOffSpec 1, Transmog 2, Greed 3, NoRoll 4, Pass 5.
    function MakeRecord(id, winnerGUID, wonAt)
        return {
            id = id,
            timestamp = wonAt,
            itemName = 'Robes of the Voidbound',
            itemLink = 'item:1',
            instanceType = 'raid',
            difficultyID = 16,
            difficultyName = 'Mythic',
            instanceName = 'Manaforge Omega',
            encounterName = 'Plexus Sentinel',
            winnerGUID = winnerGUID,
            winnerName = 'Aimee',
            winnerState = 0,
            source = 'LOOT_HISTORY',
            rolls = {
                { guid = winnerGUID, name = 'Aimee', state = 0, isWinner = true },
                { guid = 'P2', name = 'Selunne', class = 'PRIEST', state = 0 },
                { guid = 'P3', name = 'Dravok', class = 'WARRIOR', state = 0 },
                { guid = 'P4', name = 'Offspeccer', class = 'DRUID', state = 1 },
                { guid = 'P5', name = 'Greeder', class = 'ROGUE', state = 3 },
                { guid = 'P6', name = 'Moggo', class = 'HUNTER', state = 2 },
                { guid = 'P7', name = 'Passer', class = 'MAGE', state = 5 },
            },
        }
    end

    function Names(record)
        local out = {}

        for _, candidate in ipairs(
            ShowUsYourLoot.TradeAdvisor.RankCandidates(record)
        ) do
            table.insert(out, candidate.name .. ':' .. candidate.stateLabel
                .. ':' .. ShowUsYourLoot.TradeAdvisor.DescribeCandidate(candidate))
        end

        return table.concat(out, ' ~ ')
    end

    -- Puts a record where the store's index can find it, which is where the
    -- advisor reads it back from rather than keeping a copy.
    function Publish(record)
        local season = ShowUsYourLootDB.activeSeason

        table.insert(season.drops, record)
        ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    end

    function ActiveCount()
        return #ShowUsYourLoot.TradeAdvisor.Active()
    end

    function ResetWindow()
        ShowUsYourLootDB.tradeWindow = {}
    end
    """
)

g = lua.globals()

# --- install night: no seasons of history at all --------------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

record = g.MakeRecord("d1", ME, NOW - 300)

check(
    "with no history at all, the losers are still listed",
    len(g.Names(record).split(" ~ ")) == 3,
    g.Names(record),
)
check(
    "and each says it has no history rather than showing a zero",
    g.Names(record).count("no history yet") == 3,
    g.Names(record),
)

# Greed, transmog and pass did not ask for it. Only Need and offspec did.
names = g.Names(record)

for absent in ("Greeder", "Moggo", "Passer"):
    check(f"{absent} is not on the list", absent not in names, names)

for present in ("Selunne", "Dravok", "Offspeccer"):
    check(f"{present} is on the list", present in names, names)

check("the winner is not on their own list", "Aimee" not in names, names)

# Need before offspec — Aimee's rule is that offspec is greed, so they are not
# equivalent and must not be interleaved.
check(
    "offspec sorts below every Need",
    names.index("Offspeccer") > names.index("Selunne")
    and names.index("Offspeccer") > names.index("Dravok"),
    names,
)

# --- only the winner sees it ----------------------------------------------
g.ResetWindow()

check(
    "a win by this player is remembered",
    SYL.TradeAdvisor.Consider(g.MakeRecord("d1", ME, NOW - 300)) is True,
)

g.ResetWindow()

check(
    "a win by somebody else is not",
    SYL.TradeAdvisor.Consider(g.MakeRecord("d2", "Player-1-99999999", NOW - 300)) is False,
)

# --- staged resolution is one entry, not three ----------------------------
g.ResetWindow()

staged = g.MakeRecord("d3", ME, NOW - 300)
g.Publish(staged)

SYL.TradeAdvisor.Consider(staged)
SYL.TradeAdvisor.Consider(staged)
SYL.TradeAdvisor.Consider(staged)

check("a drop resolving over three passes is one entry", g.ActiveCount() == 1, g.ActiveCount())

# --- the clock runs from the award, not from now --------------------------
g.ResetWindow()

# Won 1h55m ago, so five minutes remain rather than two hours.
recent = g.MakeRecord("d4", ME, NOW - (HOUR + 3300))
g.Publish(recent)
SYL.TradeAdvisor.Consider(recent)

active = SYL.TradeAdvisor.Active()
left = active[1]["secondsLeft"] if len(list(active.values())) else None

check(
    "an item won 1h55m ago has about 5 minutes left",
    left is not None and 290 <= left <= 310,
    left,
)
check(
    "and reads as minutes rather than a bare count",
    SYL.TradeAdvisor.FormatRemaining(300) == "5m 00s",
    SYL.TradeAdvisor.FormatRemaining(300),
)
check(
    "over an hour reads as hours and minutes",
    SYL.TradeAdvisor.FormatRemaining(HOUR + 240) == "1h 04m",
    SYL.TradeAdvisor.FormatRemaining(HOUR + 240),
)

# --- expiry ----------------------------------------------------------------
g.ResetWindow()

stale = g.MakeRecord("d5", ME, NOW - (3 * HOUR))
g.Publish(stale)
SYL.TradeAdvisor.Consider(stale)

check("an item outside its window is swept", g.ActiveCount() == 0, g.ActiveCount())

# --- dismissing ------------------------------------------------------------
g.ResetWindow()

live = g.MakeRecord("d6", ME, NOW - 60)
g.Publish(live)
SYL.TradeAdvisor.Consider(live)

check("a live item is active", g.ActiveCount() == 1, g.ActiveCount())
check("dismissing it removes it", SYL.TradeAdvisor.Dismiss("d6") is True)
check("and it stays gone", g.ActiveCount() == 0, g.ActiveCount())

# --- ranking once there IS history ----------------------------------------
#
# Selunne has taken a lot per night and Dravok nothing, so Dravok is the more
# owed of the two and has to lead — which is the whole judgement the panel
# exists to hand over.
lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason
    local roster = {
        P2 = { guid = 'P2', name = 'Selunne' },
        P3 = { guid = 'P3', name = 'Dravok' },
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

    -- Selunne wins a Need, worth 100. Dravok wins nothing.
    table.insert(season.drops, {
        id = 'history1',
        timestamp = 1699950000,
        itemName = 'Something',
        itemLink = 'item:9',
        instanceType = 'raid',
        difficultyID = 16,
        difficultyName = 'Mythic',
        winnerGUID = 'P2',
        winnerName = 'Selunne',
        winnerState = 0,
        rolls = { { isWinner = true, guid = 'P2', state = 0 } },
    })

    ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    """
)

ranked = g.Names(g.MakeRecord("d7", ME, NOW - 300))

check(
    "the raider who has taken nothing leads",
    ranked.index("Dravok") < ranked.index("Selunne"),
    ranked,
)
check(
    "and the one who has taken loot says so rather than 'no history'",
    "Selunne:Need:no history yet" not in ranked,
    ranked,
)

# --- the panel draws -------------------------------------------------------
g.ResetWindow()

shown = g.MakeRecord("d8", ME, NOW - 300)
g.Publish(shown)
SYL.TradeAdvisor.Consider(shown)

try:
    SYL.TradeAdvisorPanel.Show()
    SYL.TradeAdvisorPanel.Refresh()
    check("the panel draws", True)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the panel draws", False, err)

check("and knows it has something to show", SYL.TradeAdvisorPanel.HasAnything() is True)

# --- switched off means not built -----------------------------------------
g.ResetWindow()
SYL.Features.SetEnabled("tradeAdvisor", False)

check(
    "with the feature off, a win is not remembered",
    SYL.TradeAdvisor.Consider(g.MakeRecord("d9", ME, NOW - 300)) is False,
)

SYL.Features.SetEnabled("tradeAdvisor", True)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
