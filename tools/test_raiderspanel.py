"""The Raiders board draws, and its detail pane adds up.

test_load proves the file loads. This calls the thing loading was for: builds
the panel, refreshes it against an empty database and a populated one, and
selects a raider so the detail pane renders too.

WHY THE DETAIL PANE IS TESTED AS ARITHMETIC AND NOT JUST AS "IT DREW". It is
the screen somebody stands at when they disagree with their number, so the one
thing it cannot do is disagree with the total beside it. LootScore.Breakdown
rows are checked to sum to the score LootScore.Attach put on the entry — if
those two ever drift, the pane explains a number the board is not showing.

The panel has never been drawn by the real client. This establishes that every
path runs and that the sum is right; it cannot establish that a bar is legible
or that the average line lands where the eye expects.

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
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


# --- a fresh install ------------------------------------------------------
#
# The empty state is the one a first user sees, and it is drawn by a different
# branch from the populated one — including the average line, which must not be
# shown when nobody is ranked.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

panel = None

try:
    panel = SYL.RaidersPanel.Create(lua.globals().UIParent)
    check("the panel builds", panel is not None)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the panel builds", False, err)

try:
    SYL.RaidersPanel.Refresh()
    check("it refreshes on an empty database", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes on an empty database", False, err)

# --- with data ------------------------------------------------------------
#
# Four nights so the two raiders clear MIN_NIGHTS and are ranked, plus a third
# who raided once and must be listed unranked rather than sorted to the top on
# a share of zero. Selunne takes a Need (100), Aimee a Greed (20).
lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason

    season.drops = {
        {
            id = 'd1',
            timestamp = 1700000000,
            itemName = 'Robes of the Voidbound',
            itemLink = 'item:1',
            instanceType = 'raid',
            difficultyID = 16,
            encounterName = 'Plexus Sentinel',
            winnerName = 'Selunne',
            winnerGUID = 'P1',
            winnerClass = 'PRIEST',
            winnerState = 0,
            rolls = { { isWinner = true, guid = 'P1', state = 0 } },
        },
        {
            id = 'd2',
            timestamp = 1700000100,
            itemName = 'Weight of Command',
            itemLink = 'item:2',
            instanceType = 'raid',
            difficultyID = 16,
            encounterName = "Loom'ithar",
            winnerName = 'Aimee',
            winnerGUID = 'P2',
            winnerClass = 'MAGE',
            winnerState = 3,
            rolls = { { isWinner = true, guid = 'P2', state = 3 } },
        },
        -- A transmog win, which is worth nothing and is still listed. Aimee's
        -- rule: transmog costs nothing and deducts nothing. The person with
        -- six of them is exactly who wants to see them named, because the
        -- score they are arguing with does not mention them.
        {
            id = 'd3',
            timestamp = 1700000200,
            itemName = 'Gilded Ceremonial Drape',
            itemLink = 'item:3',
            instanceType = 'raid',
            difficultyID = 16,
            encounterName = 'Plexus Sentinel',
            winnerName = 'Selunne',
            winnerGUID = 'P1',
            winnerClass = 'PRIEST',
            winnerState = 2,
            rolls = { { isWinner = true, guid = 'P1', state = 2 } },
        },
    }

    local roster = {
        P1 = { guid = 'P1', name = 'Selunne', class = 'PRIEST' },
        P2 = { guid = 'P2', name = 'Aimee', class = 'MAGE' },
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
            dateText = '2026-08-0' .. night,
            encounters = { { name = 'Plexus Sentinel', success = true } },
            roster = roster,
        })
    end

    -- The trial: one night, no loot. Ranked would put a share of zero first.
    table.insert(season.raids, {
        id = 'r9',
        startedAt = 1699900000 + 9 * 86400,
        instanceID = 1,
        instanceName = 'Manaforge Omega',
        instanceType = 'raid',
        difficultyID = 16,
        dateText = '2026-08-09',
        encounters = { { name = 'Plexus Sentinel', success = true } },
        roster = {
            P3 = { guid = 'P3', name = 'Trialist', class = 'ROGUE' },
        },
    })

    ShowUsYourLootDB.loot = season.loot

    -- Everyone, so the fixture is not filtered out by a scope with no team.
    ShowUsYourLootDB.settings.audienceScope = 'everyone'
    """
)

SYL.LootHistoryStore.RebuildIndex()

try:
    SYL.RaidersPanel.Refresh()
    check("it refreshes with data", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes with data", False, err)

# --- the numbers the board is drawn from ----------------------------------
lua.execute(
    """
    function BuildEntries()
        local drops = ShowUsYourLoot.GetAllDrops()
        local entries = ShowUsYourLoot.DueList.Build(drops, ShowUsYourLoot.GetAllRaids())

        ShowUsYourLoot.LootScore.Attach(entries, drops)
        ShowUsYourLoot.LootScore.Sort(entries)

        return entries
    end

    function EntryFor(name)
        for _, entry in ipairs(BuildEntries()) do
            if entry.name == name then
                return entry
            end
        end

        return nil
    end

    -- What the pane prints, summed the way a reader would add the column up.
    function BreakdownTotal(entry)
        local total = 0

        for _, row in ipairs(ShowUsYourLoot.LootScore.Breakdown(entry)) do
            total = total + row.points
        end

        return total
    end
    """
)

g = lua.globals()

selunne = g.EntryFor("Selunne")
aimee = g.EntryFor("Aimee")
trialist = g.EntryFor("Trialist")

# 100 for the Need, 0 for the transmog beside it.
check(
    "a Need win plus a transmog scores 100",
    selunne is not None and selunne["lootScore"] == 100,
    selunne and selunne["lootScore"],
)
check(
    "a Greed win scores 20",
    aimee is not None and aimee["lootScore"] == 20,
    aimee and aimee["lootScore"],
)

# The transmog is on the list and contributes nothing. Both halves matter:
# dropping it would hide a win the raider knows they had, and weighting it
# would contradict the rule the whole score is built on.
selunne_rows = SYL.LootScore.Breakdown(selunne) if selunne is not None else None
labels = (
    [selunne_rows[i]["label"] for i in range(1, len(list(selunne_rows.values())) + 1)]
    if selunne_rows is not None
    else []
)

check("the transmog win is listed", "Transmog" in labels, labels)
check(
    "and is worth nothing",
    selunne is not None and g.BreakdownTotal(selunne) == 100,
    selunne and g.BreakdownTotal(selunne),
)

# The pane must not explain a different number from the one on the bar.
check(
    "the breakdown sums to the Need winner's score",
    selunne is not None and g.BreakdownTotal(selunne) == selunne["lootScore"],
    selunne and f"breakdown {g.BreakdownTotal(selunne)} vs score {selunne['lootScore']}",
)
check(
    "the breakdown sums to the Greed winner's score",
    aimee is not None and g.BreakdownTotal(aimee) == aimee["lootScore"],
    aimee and f"breakdown {g.BreakdownTotal(aimee)} vs score {aimee['lootScore']}",
)

# The labels are what an officer reads out loud, so they are asserted rather
# than assumed from the weight.
rows = SYL.LootScore.Breakdown(selunne) if selunne is not None else None
first = rows[1] if rows is not None else None

check("a Need win is labeled Need", first is not None and first["label"] == "Need")
check("and is counted once", first is not None and first["count"] == 1)

# Under MIN_NIGHTS nobody is ranked, and share must be nil rather than zero —
# a zero would sort the trial to the top of a list of people who are actually
# owed loot.
check("a one-night trial is not ranked", trialist is not None and not trialist["ranked"])
check("and has no share at all", trialist is not None and trialist["share"] is None)
check(
    "and says why",
    trialist is not None and "under" in str(trialist["notRankedReason"]),
    trialist and trialist["notRankedReason"],
)

# --- the roster is part of this tab now ------------------------------------
#
# Board and Roster are the same people asked two questions, and the answer to
# the second decides who appears in the first — ticking TEAM is what the scope
# button reads. They were two windows reached from two buttons; now they are a
# toggle, and the full roster window is still one button away for the things
# that do not belong in a column of ticks.
for name in ("viewButton", "rosterButton"):
    check(f"the panel offers {name}", panel[name] is not None)

for label, action in (
    ("switching to the roster", lambda: SYL.RaidersPanel.SetView("roster")),
    ("selecting nobody there", lambda: SYL.RaidersPanel.Refresh()),
    ("switching back to the board", lambda: SYL.RaidersPanel.SetView("board")),
    ("toggling straight from the board", lambda: SYL.RaidersPanel.ToggleView()),
):
    try:
        action()
        check(f"it refreshes {label}", True)
    except Exception as err:  # noqa: BLE001
        check(f"it refreshes {label}", False, err)

# The roster view is built from the same scope as the board, so a scope that
# hides everybody has to leave it empty rather than throwing.
lua.execute("ShowUsYourLootDB.settings.audienceScope = 'team'")

try:
    SYL.RaidersPanel.SetView("roster")
    check("the roster view survives a scope that hides everybody", True)
except Exception as err:  # noqa: BLE001
    check("the roster view survives a scope that hides everybody", False, err)

lua.execute("ShowUsYourLootDB.settings.audienceScope = 'everyone'")
SYL.RaidersPanel.SetView("board")

# --- the detail pane renders for each of those ----------------------------
for label, entry in (
    ("a ranked raider", selunne),
    ("an unranked trial", trialist),
    ("nobody selected", None),
):
    try:
        SYL.RaidersDetail.Render(panel["detail"], entry)
        check(f"the detail pane draws for {label}", True)
    except Exception as err:  # noqa: BLE001
        check(f"the detail pane draws for {label}", False, err)

# --- scope still applies --------------------------------------------------
#
# The board is a people-list like any other. With a team marked and nobody on
# it, it must fall to the empty state rather than drawing every pug.
lua.execute("ShowUsYourLootDB.settings.audienceScope = 'team'")

try:
    SYL.RaidersPanel.Refresh()
    check("it refreshes when the scope hides everybody", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes when the scope hides everybody", False, err)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
