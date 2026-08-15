"""Renaming and merging archived seasons.

An archive is sealed so nothing can be added to or removed from its history —
that seal is the promise that makes archiving safe. A NAME IS NOT HISTORY, and
until now it was sealed along with everything else: RenameActiveSeason only
ever reached the active season, and archiving before renaming is the ordinary
order to do things in. Getting the name wrong was permanent.

MERGING EXISTS FOR A BOUNDARY TAKEN ON THE WRONG DAY. Archiving the day before
the tier actually turned over leaves a stub holding a few nights that belong to
the season before it, and no amount of renaming makes three archives read like
the two seasons that happened.

THE ASSERTION THAT MATTERS IS THAT NOTHING IS LOST. A merge concatenates three
lists across N seasons and then deletes N-1 of them; an off-by-one in the
removal takes a season nobody asked it to, and a records count that does not
add up afterwards is a year of loot history gone. Both are checked here, and
the removal walks backwards for exactly this reason — removing from the front
renumbers everything behind it.

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

# Three archives with distinguishable contents, so a merge that takes the
# wrong one is visible rather than merely a wrong total.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    function Seed(name, drops, loot, raids, startedAt)
        local season = ShowUsYourLootDB.activeSeason

        season.name = name
        season.startedAt = startedAt
        season.drops, season.loot, season.raids = {}, {}, {}

        for index = 1, drops do
            table.insert(season.drops,
                { id = name .. '-d' .. index, itemName = name })
        end

        for index = 1, loot do
            table.insert(season.loot,
                { id = name .. '-l' .. index, itemName = name })
        end

        for index = 1, raids do
            table.insert(season.raids,
                { id = name .. '-r' .. index, dateText = '2026-08-01' })
        end

        SYL.ArchiveCurrentSeason('next')
    end

    function ArchiveNames()
        local names = {}

        for _, season in ipairs(SYL.GetArchives()) do
            table.insert(names, season.name)
        end

        return table.concat(names, ' ~ ')
    end

    function Totals()
        local drops, loot, raids = 0, 0, 0

        for _, season in ipairs(SYL.GetArchives()) do
            drops = drops + #(season.drops or {})
            loot = loot + #(season.loot or {})
            raids = raids + #(season.raids or {})
        end

        return drops .. '/' .. loot .. '/' .. raids
    end

    function ContentsOf(index)
        local season = SYL.GetArchives()[index]
        local seen = {}

        for _, record in ipairs(season.drops or {}) do
            seen[record.itemName] = true
        end

        local names = {}

        for name in pairs(seen) do
            table.insert(names, name)
        end

        table.sort(names)

        return table.concat(names, ',')
    end
    """
)

lua.execute("Seed('Season One', 3, 2, 1, 1000)")
lua.execute("Seed('Tail', 2, 1, 1, 2000)")
lua.execute("Seed('Season Two', 4, 3, 2, 3000)")

check("three seasons are archived", len(SYL.GetArchives()) == 3,
      lua.globals().ArchiveNames())

before = lua.globals().Totals()

check("with nine drops, six items and four nights between them",
      before == "9/6/4", before)

# --- renaming -------------------------------------------------------------
ok, message = SYL.RenameArchive(2, "Season One tail")

check("AN ARCHIVE CAN BE RENAMED", ok is True, message)
check("and the right one changed",
      lua.globals().ArchiveNames()
      == "Season One ~ Season One tail ~ Season Two",
      lua.globals().ArchiveNames())

ok, message = SYL.RenameArchive(9, "Nowhere")

check("renaming one that is not there is refused",
      ok is False, message)

ok, message = SYL.RenameArchive(1, "   ")

check("and an empty name is refused with a reason",
      ok is False and message is not None, message)

# --- merging --------------------------------------------------------------
#
# The stub belongs with the season before it. Merging 1 and 2 must leave
# Season Two completely untouched.
ok, message = SYL.MergeArchives(lua.table_from([1, 2]), "Midnight Season 1")

check("two archives merge", ok is True, message)
check("into one fewer season", len(SYL.GetArchives()) == 2,
      lua.globals().ArchiveNames())
check("NOTHING IS LOST", lua.globals().Totals() == before,
      f"{before} -> {lua.globals().Totals()}")
check("the merged season carries both sets of records",
      lua.globals().ContentsOf(1) == "Season One,Tail",
      lua.globals().ContentsOf(1))
check("it takes the name it was given",
      lua.globals().ArchiveNames() == "Midnight Season 1 ~ Season Two",
      lua.globals().ArchiveNames())
check("and the earliest start date of the two",
      SYL.GetArchives()[1].startedAt == 1000,
      SYL.GetArchives()[1].startedAt)

# THE OFF-BY-ONE. Merging from the front renumbers everything behind it, so a
# removal that walks forwards deletes a season nobody named.
check("THE SEASON NOT MERGED IS UNTOUCHED",
      lua.globals().ContentsOf(2) == "Season Two",
      lua.globals().ContentsOf(2))

# --- refusals -------------------------------------------------------------
ok, message = SYL.MergeArchives(lua.table_from([1]), "One")

check("merging needs two seasons", ok is False, message)

ok, message = SYL.MergeArchives(lua.table_from([1, 99]), "Missing")

check("a season that is not there is refused",
      ok is False, message)
check("and nothing was merged before noticing",
      len(SYL.GetArchives()) == 2, lua.globals().ArchiveNames())

ok, message = SYL.MergeArchives(lua.table_from([2, 2]), "Twice")

check("the same season twice is not two seasons",
      ok is False, message)

# --- order does not matter -------------------------------------------------
#
# Somebody ticking boxes bottom to top passes them descending.
lua.execute("Seed('Third', 1, 1, 1, 4000)")

total = lua.globals().Totals()

ok, message = SYL.MergeArchives(lua.table_from([3, 1]), "Everything")

check("indexes given backwards still merge", ok is True, message)
check("and still lose nothing", lua.globals().Totals() == total,
      f"{total} -> {lua.globals().Totals()}")
check("leaving the untouched season alone",
      "Season Two" in lua.globals().ArchiveNames(),
      lua.globals().ArchiveNames())

# --- a merged name is optional --------------------------------------------
lua.execute("Seed('Spare', 1, 0, 0, 5000)")

names = lua.globals().ArchiveNames()

ok, _ = SYL.MergeArchives(lua.table_from([1, len(SYL.GetArchives())]), "")

check("no name keeps the older season's own",
      ok is True and lua.globals().ArchiveNames().startswith("Everything"),
      lua.globals().ArchiveNames())

# --- THREE AT ONCE, WHICH IS THE ONLY CASE THAT CATCHES THE OFF-BY-ONE ------
#
# Merging two removes exactly one season, and removing one index is the same
# job whichever end you start from — so a two-season merge cannot tell a
# forwards removal from a backwards one. It takes three before the renumbering
# bites: remove index 2 and the season that was at 3 is now at 2, so removing 3
# next takes whatever was at 4. That is a season nobody named, deleted silently.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute("Seed('Alpha', 1, 0, 0, 1000)")
lua.execute("Seed('Beta', 2, 0, 0, 2000)")
lua.execute("Seed('Gamma', 3, 0, 0, 3000)")
lua.execute("Seed('Bystander', 4, 0, 0, 4000)")

before = lua.globals().Totals()

check("four archives, ten drops between them",
      len(SYL.GetArchives()) == 4 and before == "10/0/0",
      f"{len(SYL.GetArchives())} {before}")

ok, message = SYL.MergeArchives(lua.table_from([1, 2, 3]), "Merged three")

check("three archives merge in one go", ok is True, message)
check("leaving two seasons", len(SYL.GetArchives()) == 2,
      lua.globals().ArchiveNames())
check("NOTHING IS LOST MERGING THREE", lua.globals().Totals() == before,
      f"{before} -> {lua.globals().Totals()}")
check("all three sets of records are in the survivor",
      lua.globals().ContentsOf(1) == "Alpha,Beta,Gamma",
      lua.globals().ContentsOf(1))
check("AND THE BYSTANDER IS STILL THERE",
      lua.globals().ContentsOf(2) == "Bystander",
      lua.globals().ArchiveNames())

# --- selection survives its own operation ---------------------------------
#
# SELECTION IS KEYED BY SEASON ID, NOT ROW NUMBER. Merging removes seasons and
# renumbers everything below them, so a tick held as an index would point at a
# different season the instant the merge it described finished — and the next
# action would run on whatever slid into that slot.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

for name, drops in (("First", 1), ("Second", 2), ("Third", 3), ("Fourth", 4)):
    lua.execute(f"Seed('{name}', {drops}, 0, 0, {1000 + drops})")

view = lua.table_from({"archiveSelection": lua.table_from({})})

SYL.ArchiveControls.Toggle(view, 1)
SYL.ArchiveControls.Toggle(view, 2)

indexes, names = SYL.ArchiveControls.Selected(view)

check("ticking two seasons selects them",
      list(indexes.values()) == [1, 2]
      and list(names.values()) == ["First", "Second"],
      list(names.values()))

check("and a ticked row reports itself ticked",
      SYL.ArchiveControls.IsSelected(view, 1) is True
      and SYL.ArchiveControls.IsSelected(view, 3) is False)

# Untick one by ticking it again.
SYL.ArchiveControls.Toggle(view, 1)

indexes, names = SYL.ArchiveControls.Selected(view)

check("ticking again unticks", list(names.values()) == ["Second"],
      list(names.values()))

# Now the case that matters: something below the selection is removed, so
# every row number shifts.
SYL.MergeArchives(lua.table_from([3, 4]), "Merged")

indexes, names = SYL.ArchiveControls.Selected(view)

check("A TICK STILL POINTS AT THE SAME SEASON AFTER A MERGE",
      list(names.values()) == ["Second"], list(names.values()))
check("even though its row number moved or its neighbours went",
      len(SYL.GetArchives()) == 3, lua.globals().ArchiveNames())

SYL.ArchiveControls.Clear(view)

indexes, _ = SYL.ArchiveControls.Selected(view)

check("Untick all clears everything", len(indexes) == 0, len(indexes))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
