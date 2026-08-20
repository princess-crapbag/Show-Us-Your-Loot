"""Recovery — noticing that a season's records have gone missing.

If WoW cannot parse the saved variables file it discards the whole thing and
hands the addon an empty table. Everything downstream then behaves correctly
for a database that has never been used, so a lost tier looks exactly like a
first run: a fresh season, the cheerful welcome line, and no error anywhere.
Blizzard keeps one .bak and replaces it at every logout, so it has to be
noticed in the session it happens in or not at all.

The stamp lives in SavedVariablesPerCharacter, a different file under a
different folder, because a stamp inside the file being watched would be lost
in the same accident.

THE CASES THAT MATTER MOST ARE THE FALSE POSITIVES. Archiving moves records
from the active season into an archive, and `/syl clear` empties one on
purpose. Either reported as data loss would train somebody to ignore the one
warning that means it.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

CORE = Path(__file__).resolve().parent.parent / "Core"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("ShowUsYourLoot = {}")
lua.execute("time = function() return 1000 end")

for name in ("Output.lua", "Utilities.lua", "Recovery.lua"):
    lua.execute((CORE / name).read_text(encoding="utf-8"))

Recovery = lua.globals().ShowUsYourLoot.Recovery

failures = []


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       got: " + repr(detail))

        failures.append(label)


def database(active_drops=0, active_loot=0, archives=()):
    """A database with the given record counts."""
    def season(drops, loot):
        return lua.table_from({
            "drops": lua.table_from([lua.table_from({})] * drops),
            "loot": lua.table_from([lua.table_from({})] * loot),
        })

    lua.globals().ShowUsYourLootDB = lua.table_from({
        "activeSeason": season(active_drops, active_loot),
        "archives": lua.table_from([season(d, l) for d, l in archives]),
    })


def forget_stamp():
    lua.execute("ShowUsYourLootCharDB = nil")


# --- the totals count across every season --------------------------------
database(active_drops=10, active_loot=5, archives=((30, 20), (7, 3)))
drops, loot = Recovery.Totals()

check("drops are counted across the active season and archives", drops == 47,
      drops)
check("and so are chat records", loot == 28, loot)

# --- a first run has nothing to compare against --------------------------
forget_stamp()
database(active_drops=0)

check("no stamp means nothing to report", Recovery.CheckForLoss() is None)

# --- the ordinary case ----------------------------------------------------
database(active_drops=51, active_loot=1384)
Recovery.Stamp()

check("stamping then reloading unchanged is quiet",
      Recovery.CheckForLoss() is None)

database(active_drops=63, active_loot=1400)
check("and a raid night since is quiet too", Recovery.CheckForLoss() is None)

# --- the case this exists for --------------------------------------------
database(active_drops=51, active_loot=1384)
Recovery.Stamp()

database(active_drops=0, active_loot=0)
stamp, now = Recovery.CheckForLoss()

check("an emptied database is reported", stamp is not None)
check("and the report knows what was there", stamp.drops == 51, stamp)
check("and what is there now", now.drops == 0, now)

# Losing only the chat records is still a loss.
database(active_drops=51, active_loot=1384)
Recovery.Stamp()
database(active_drops=51, active_loot=0)

check("losing only chat records still counts",
      Recovery.CheckForLoss() is not None)

# --- the false positives --------------------------------------------------
# Archiving moves records from the active season into an archive. The active
# season drops to zero and nothing has been lost.
database(active_drops=51, active_loot=1384)
Recovery.Stamp()

database(active_drops=0, active_loot=0, archives=((51, 1384),))
check("archiving a season is not data loss", Recovery.CheckForLoss() is None)

# /syl clear empties a season on purpose and re-stamps on the spot.
database(active_drops=51, active_loot=1384)
Recovery.Stamp()

database(active_drops=0, active_loot=0)
Recovery.Stamp()

check("clearing on purpose is quiet once it re-stamps",
      Recovery.CheckForLoss() is None)

# --- the stamp survives its own file being absent -------------------------
forget_stamp()
database(active_drops=5)

check("stamping builds the per-character table when it is missing",
      Recovery.Stamp() is not None)
check("and it records the totals",
      lua.globals().ShowUsYourLootCharDB.lastSeen.drops == 5)

# --- the alt that was not logged in when the season was cleared -----------
#
# The stamp is per character; the database it measures is per account. So
# clearing on the main and re-stamping there healed only the main, and every
# other character came back holding a stamp from before the clear and shouted
# RECORDS ARE MISSING — sending its owner to recover a backup of a file
# nothing had happened to.

lua.execute("ShowUsYourLootCharDB = nil")
database(active_drops=500, active_loot=300)
Recovery.Stamp()            # the alt, before anything happened

# Time moves on, then somebody clears the season on the main.
lua.execute("time = function() return 2000 end")
database(active_drops=0, active_loot=0)
Recovery.NoteDeliberateClear()

# Now the alt logs in. It still has ITS old stamp, not the main's.
lua.globals().ShowUsYourLootCharDB.lastSeen = lua.table_from(
    {"drops": 500, "loot": 300, "at": 1000}
)

check("an alt whose stamp predates a deliberate clear stays quiet",
      Recovery.CheckForLoss() is None)

check("and the clear is recorded account-wide, where every character sees it",
      lua.globals().ShowUsYourLootDB.lastDeliberateClear == 2000,
      lua.globals().ShowUsYourLootDB.lastDeliberateClear)

# But a real loss AFTER the clear must still be reported.
lua.globals().ShowUsYourLootCharDB.lastSeen = lua.table_from(
    {"drops": 40, "loot": 10, "at": 3000}
)
database(active_drops=0, active_loot=0)

check("a loss recorded after the clear is still reported",
      Recovery.CheckForLoss() is not None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
