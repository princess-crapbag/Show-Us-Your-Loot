"""The dashboard actually draws, for a fresh install and for one with data.

test_load proves every file loads. This goes one further and calls the thing
the loading was for: it builds the dashboard and refreshes it, which runs all
six renderers end to end.

TWO DATABASES, because they fail differently. A fresh install has no seasons,
no drops and no roster, and every renderer has to lead with its "nothing yet"
message rather than treating zero as an exception — that is the state the very
first user is in. A populated one exercises the arithmetic underneath.

Renderers run under pcall in the addon, so an error inside one would be caught
and drawn as "this widget could not be drawn" rather than raised. That would
make this test pass while the dashboard was broken, so the pcall is defeated
here: RENDERERS are called directly, and anything they throw fails the run.

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


# A tile is what DashboardTab hands a renderer: a body to draw into and a
# rows table. The stub frame answers anything, so this is the same shape.
lua.execute(
    """
    function MakeTile()
        return { body = StubFrame(), rows = {}, title = StubFrame() }
    end
    """
)


def render_all(label_prefix):
    for widget in SYL.Dashboard.WIDGETS.values():
        key = widget["key"]
        renderer = SYL.DashboardWidgets.RENDERERS[key]

        if renderer is None:
            check(f"{label_prefix}: {key} has a renderer", False)
            continue

        tile = lua.globals().MakeTile()

        try:
            renderer(tile)
            check(f"{label_prefix}: {key} draws", True)
        except Exception as err:  # noqa: BLE001 — any Lua error is the finding
            check(f"{label_prefix}: {key} draws", False, err)


# --- a fresh install ------------------------------------------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

check("a fresh database initializes", lua.globals().ShowUsYourLootDB is not None)
render_all("empty")

# The grid itself, not just the renderers.
try:
    dashboard = SYL.DashboardTab.Create(lua.globals().UIParent, lua.table())
    dashboard.Refresh(dashboard)
    check("the grid refreshes on an empty database", True)
except Exception as err:  # noqa: BLE001
    check("the grid refreshes on an empty database", False, err)

# --- with data ------------------------------------------------------------
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
            encounterName = 'Loom\\'ithar',
            winnerName = 'Aimee',
            winnerGUID = 'P2',
            winnerClass = 'MAGE',
            winnerState = 2,
            rolls = { { isWinner = true, guid = 'P2', state = 2 } },
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
            dateText = '2026-08-08',
            encounters = { { name = 'Plexus Sentinel', success = true } },
            roster = {
                P1 = { guid = 'P1', name = 'Selunne', class = 'PRIEST' },
                P2 = { guid = 'P2', name = 'Aimee', class = 'MAGE' },
            },
        },
    }

    ShowUsYourLootDB.loot = season.loot
    """
)

SYL.LootHistoryStore.RebuildIndex()
render_all("with data")

try:
    dashboard = SYL.DashboardTab.Create(lua.globals().UIParent, lua.table())
    dashboard.Refresh(dashboard)
    check("the grid refreshes with data", True)
except Exception as err:  # noqa: BLE001
    check("the grid refreshes with data", False, err)

# --- with every widget switched off --------------------------------------
for widget in SYL.Dashboard.WIDGETS.values():
    SYL.Dashboard.SetEnabled(widget["key"], False)

try:
    dashboard = SYL.DashboardTab.Create(lua.globals().UIParent, lua.table())
    dashboard.Refresh(dashboard)
    check("an all-off dashboard refreshes rather than throwing", True)
except Exception as err:  # noqa: BLE001
    check("an all-off dashboard refreshes rather than throwing", False, err)

# --- tile reuse -----------------------------------------------------------
#
# Tiles are pooled by grid position, and Headline sets tile.rowTop so its rows
# clear the big number. If ClearTile does not reset it, the next widget in that
# slot starts 24px low and loses its bottom row — reachable just by switching a
# widget off, which changes the widget-to-tile mapping.
tile = lua.globals().MakeTile()

SYL.DashboardParts.Headline(tile, 7, "on the team")
check("a headline records an offset", tile["rowTop"] == 24)

SYL.DashboardTab.ClearTile(tile)
check("clearing a tile drops the offset", tile["rowTop"] is None)
check("and drops the rows with it", len(list(tile["rows"].values())) == 0)

# A row on a cleared tile starts at the top again rather than 24px down.
SYL.DashboardParts.Row(tile, 1, "Something", "1")
check("a row on a cleared tile has no offset applied", tile["rowTop"] is None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
