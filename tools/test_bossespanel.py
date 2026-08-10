"""The Bosses board draws, and it does not walk the Adventure Guide to do it.

test_load proves the file loads. This calls the thing loading was for: builds
the panel, refreshes it empty and populated, switches modes, and renders the
loot pane for a boss, for no boss, and for a boss the journal knows nothing
about.

THE ASSERTION THAT MATTERS IS THE ONE ABOUT NOT READING. LootTable.GetMissing
walks every remaining raid tier and moves the player's own Adventure Guide
selection. Doing it per hover froze the game for seconds at a time, which is
why the walk is behind a button. A panel that quietly calls it on show puts
that back, and nothing about the screen would look wrong — so the call is
counted here rather than trusted.

LootTable is replaced with counting fakes. That is the seam on purpose: the
journal has its own concerns and its own id-space traps, and this file is
about what the panel asks for and when.

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


# The fakes. GetMissing is the expensive one; GetMissingIfKnown answers from
# what has already been read and is safe on show.
lua.execute(
    """
    WALKS, CHEAP_READS = 0, 0

    -- Two of the three journal items have dropped, so a correct pane shows
    -- one missing out of three rather than all of them or none.
    local function Answer()
        return {
            { itemID = 3, name = 'Voidglass Sabatons', slot = 'Feet' },
        }, 3, 2
    end

    ShowUsYourLoot.LootTable.GetMissing = function()
        WALKS = WALKS + 1

        return Answer()
    end

    ShowUsYourLoot.LootTable.GetMissingIfKnown = function()
        CHEAP_READS = CHEAP_READS + 1

        -- Nothing read yet: this is what the real one answers before the
        -- button has ever been pressed.
        return nil
    end
    """
)

g = lua.globals()

# --- a fresh install ------------------------------------------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

panel = None

try:
    panel = SYL.BossesPanel.Create(g.UIParent)
    check("the panel builds", panel is not None)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the panel builds", False, err)

try:
    SYL.BossesPanel.Refresh()
    check("it refreshes on an empty database", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes on an empty database", False, err)

# --- with data ------------------------------------------------------------
#
# Two difficulties of the same boss, which must stay two rows: folding them
# would average a farm kill with a progression wall.
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
            -- Required, and not decoration. BossStats keys a boss by encounter
            -- and difficulty *name*, so a drop without one lands in its own
            -- row with no pulls and no kills beside the session's row for the
            -- same boss. The real capture path always stores it — it comes
            -- from GetLocationInformation, which defaults it rather than
            -- leaving it nil.
            difficultyName = 'Mythic',
            instanceName = 'Manaforge Omega',
            encounterID = 3129,
            encounterName = 'Plexus Sentinel',
            winnerName = 'Selunne',
            winnerGUID = 'P1',
            winnerState = 0,
            rolls = { { isWinner = true, guid = 'P1', state = 0 } },
        },
    }

    season.raids = {
        {
            id = 'r1',
            startedAt = 1699900000,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 16,
            difficultyName = 'Mythic',
            dateText = '2026-08-08',
            -- `killed`, not `success`. BossStats counts a kill off that field
            -- and nothing else, so a fixture using the wrong name produces a
            -- boss with pulls and no kills and looks like a counting bug.
            encounters = {
                {
                    name = 'Plexus Sentinel', encounterID = 3129,
                    killed = true, at = 1699900500,
                },
                { name = "Loom'ithar", encounterID = 3130, killed = false },
            },
            roster = { P1 = { guid = 'P1', name = 'Selunne', class = 'PRIEST' } },
        },
        {
            id = 'r2',
            startedAt = 1699990000,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 15,
            difficultyName = 'Heroic',
            dateText = '2026-08-09',
            encounters = {
                {
                    name = 'Plexus Sentinel', encounterID = 3129,
                    killed = true, at = 1699990500,
                },
            },
            roster = { P1 = { guid = 'P1', name = 'Selunne', class = 'PRIEST' } },
        },
    }

    ShowUsYourLootDB.loot = season.loot
    """
)

SYL.LootHistoryStore.RebuildIndex()

lua.execute("WALKS, CHEAP_READS = 0, 0")

try:
    SYL.BossesPanel.Refresh()
    check("it refreshes with data", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes with data", False, err)

# --- the walk is not taken on its own -------------------------------------
check(
    "showing the tab never walks the journal",
    g.WALKS == 0,
    f"GetMissing called {g.WALKS} times",
)
check(
    "it asks the cheap question instead",
    g.CHEAP_READS > 0,
    f"GetMissingIfKnown called {g.CHEAP_READS} times",
)

# Switching view is free and must stay free.
lua.execute("WALKS = 0")
SYL.BossesPanel.SetMode("dropped")
SYL.BossesPanel.SetMode("missing")
check("switching modes never walks it either", g.WALKS == 0, g.WALKS)

# And the button does what the button is for.
SYL.BossesPanel.ReadJournal()
check("pressing read walks it", g.WALKS > 0, g.WALKS)

# Once read, it stays read rather than reverting to the unread message.
lua.execute("WALKS = 0")
SYL.BossesPanel.Refresh()
check("and it stays read afterwards", g.WALKS > 0, g.WALKS)

# --- the rail's own arithmetic --------------------------------------------
lua.execute(
    """
    function BossRows()
        local bosses = ShowUsYourLoot.BossStats.Build(
            ShowUsYourLoot.GetAllDrops(), ShowUsYourLoot.GetAllRaids()
        )

        ShowUsYourLoot.BossStats.SortByRecent(bosses)

        local out = {}

        for _, boss in ipairs(bosses) do
            table.insert(out, string.format(
                '%s|%s|%d/%d',
                boss.name, tostring(boss.difficultyName),
                boss.kills or 0, boss.pulls or 0
            ))
        end

        return table.concat(out, ' ~ ')
    end
    """
)

rail = g.BossRows()

check(
    "the same boss on two difficulties is two rows",
    rail.count("Plexus Sentinel") == 2,
    rail,
)
check(
    "a boss pulled and never killed still has a row",
    "Loom'ithar" in rail,
    rail,
)
check(
    "and reads as 0 of 1 rather than a bare zero",
    "Loom'ithar|Mythic|0/1" in rail,
    rail,
)
check(
    "a killed boss counts the kill",
    "Plexus Sentinel|Mythic|1/1" in rail,
    rail,
)
# Recent-first, so the Heroic kill from the later night leads. That is the
# default selection, and it is what makes the tab open on this week's boss.
check(
    "the most recently killed boss is first",
    rail.startswith("Plexus Sentinel|Heroic|1/1"),
    rail,
)

# --- the pane renders for each shape --------------------------------------
lua.execute(
    """
    function FirstBoss()
        local bosses = ShowUsYourLoot.BossStats.Build(
            ShowUsYourLoot.GetAllDrops(), ShowUsYourLoot.GetAllRaids()
        )

        ShowUsYourLoot.BossStats.SortByRecent(bosses)

        return bosses[1]
    end
    """
)

boss = g.FirstBoss()

for label, target, view, read in (
    ("a boss with a journal entry", boss, "missing", True),
    ("a boss in the dropped view", boss, "dropped", True),
    ("a boss before the journal is read", boss, "missing", False),
    ("no boss selected", None, "missing", True),
):
    try:
        SYL.BossLoot.Render(panel["pane"], target, view, read)
        check(f"the pane draws for {label}", True)
    except Exception as err:  # noqa: BLE001
        check(f"the pane draws for {label}", False, err)

# A boss the journal has nothing for must say so rather than drawing an empty
# list that reads as "this boss owes you nothing".
lua.execute(
    """
    ShowUsYourLoot.LootTable.GetMissing = function() return nil end
    ShowUsYourLoot.LootTable.GetMissingIfKnown = function() return nil end
    """
)

try:
    SYL.BossLoot.Render(panel["pane"], boss, "missing", True)
    check("the pane draws when the journal knows nothing", True)
except Exception as err:  # noqa: BLE001
    check("the pane draws when the journal knows nothing", False, err)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
