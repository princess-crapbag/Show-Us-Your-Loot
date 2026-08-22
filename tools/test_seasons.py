"""Archiving a season is a boundary, not a label.

THIS COVERS A PATH THAT HAD NEVER RUN. Until the first archive was taken there
was one season and zero archives, so GetAllDrops and GetActiveDrops returned
the identical list and nothing could tell them apart. Every board, due list,
attendance count and tier tile read the all-time accessor, and the first
archive ever taken changed nothing on screen: the tier tile still showed last
tier's bosses and the board still ranked people on last tier's loot.

So the assertion that matters here is the negative one — that a raider who won
in the archived season carries NO score into the new one. Reverting any single
call site from GetActiveDrops back to GetAllDrops fails that check, which is
the whole point of writing it this way.

The positive half matters too and is asserted alongside it: GetAllDrops must
still see the archive, because the item tooltip's "has this ever dropped", the
export and the loot list's all-seasons view are legitimately all-time. A fix
that made every accessor season-scoped would pass the negative assertions and
silently break those three.

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


# --- the fixture ----------------------------------------------------------
#
# Two raiders, both present all tier. Selunne wins the only upgrade, so after
# the archive she is the one whose number must NOT carry over. Borg never wins
# and is here so the board has somebody to rank her against — with a single
# ranked raider any two orderings agree by accident, which is exactly how the
# last ordering bug survived a live raid night.
#
# Five nights, because LootScore.MIN_NIGHTS is three and a fixture sitting on
# the boundary would stop testing the ranking the moment that constant moved.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    ROSTER = {
        P1 = { guid = 'P1', name = 'Selunne', class = 'PRIEST' },
        P2 = { guid = 'P2', name = 'Borg', class = 'WARRIOR' },
    }

    -- dateText is ISO on purpose. Dates read MM-DD-YYYY everywhere a person
    -- sees them, but the night key is one of the two deliberate exceptions —
    -- NightIndex parses it as YYYY-MM-DD, and a fixture written the display
    -- way resolves to year 11 and takes os.time out of range, which surfaces
    -- as an unrelated-looking crash inside the calendar.
    function MakeNight(id, startedAt, dateText, bossName, encounterID)
        return {
            id = id,
            startedAt = startedAt,
            endedAt = startedAt + 7200,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 16,
            difficultyName = 'Mythic',
            dateText = dateText,
            encounters = {
                {
                    name = bossName, encounterID = encounterID,
                    killed = true, at = startedAt + 600,
                },
            },
            roster = ROSTER,
        }
    end

    function MakeWin(id, timestamp, itemName, bossName, encounterID)
        return {
            id = id,
            timestamp = timestamp,
            itemName = itemName,
            itemLink = 'item:' .. id,
            instanceType = 'raid',
            difficultyID = 16,
            difficultyName = 'Mythic',
            instanceName = 'Manaforge Omega',
            encounterID = encounterID,
            encounterName = bossName,
            winnerName = 'Selunne',
            winnerGUID = 'P1',
            winnerState = 0,
            rolls = {
                { isWinner = true, guid = 'P1', name = 'Selunne', state = 0 },
                { isWinner = false, guid = 'P2', name = 'Borg', state = 0 },
            },
        }
    end

    -- Off the same calls the board and the tier tile make, so a call site
    -- reverting to the all-time accessor shows up here rather than only in
    -- the game.
    function ScoreFor(name)
        local drops = SYL.GetActiveDrops()
        local totals = SYL.LootScore.BuildTotals(drops)

        for _, entry in ipairs(
            SYL.DueList.Build(drops, SYL.GetActiveRaids())
        ) do
            if entry.name == name then
                local total = totals[entry.key]

                return total and total.score or 0
            end
        end

        return nil
    end

    function NightsFor(name)
        local attendance, byKey =
            SYL.RaidSession.BuildAttendance(SYL.GetActiveRaids())

        for _, member in ipairs(attendance) do
            if member.name == name then
                return member.nights or 0
            end
        end

        return 0
    end

    function BossNames(drops, raids)
        local bosses = SYL.BossStats.Build(drops, raids)
        local out = {}

        for _, boss in ipairs(bosses) do
            table.insert(out, boss.name)
        end

        table.sort(out)

        return table.concat(out, ',')
    end

    function ActiveBosses()
        return BossNames(SYL.GetActiveDrops(), SYL.GetActiveRaids())
    end

    function AllTimeBosses()
        return BossNames(SYL.GetAllDrops(), SYL.GetAllRaids())
    end
    """
)

g = lua.globals()

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason

    season.name = 'Midnight Season 1'

    season.raids = {
        MakeNight('r1', 1785542400, '2026-08-01', 'Plexus Sentinel', 3129),
        MakeNight('r2', 1785628800, '2026-08-02', 'Plexus Sentinel', 3129),
        MakeNight('r3', 1785715200, '2026-08-03', 'Plexus Sentinel', 3129),
        MakeNight('r4', 1785801600, '2026-08-04', 'Plexus Sentinel', 3129),
        MakeNight('r5', 1785888000, '2026-08-05', 'Plexus Sentinel', 3129),
    }

    season.drops = {
        MakeWin('d1', 1785543000, 'Robes of the Voidbound',
            'Plexus Sentinel', 3129),
    }

    ShowUsYourLootDB.loot = season.loot
    """
)

SYL.LootHistoryStore.RebuildIndex()

# --- before the archive, to prove the fixture is real ---------------------
check("the winner is scored before archiving", g.ScoreFor("Selunne") == 100,
      g.ScoreFor("Selunne"))
check("the raider who won nothing scores zero",
      g.ScoreFor("Borg") == 0, g.ScoreFor("Borg"))
check("five nights are counted", g.NightsFor("Selunne") == 5,
      g.NightsFor("Selunne"))
check("the tier shows last tier's boss",
      g.ActiveBosses() == "Plexus Sentinel", g.ActiveBosses())

# --- archive --------------------------------------------------------------
archived, new_season = SYL.ArchiveCurrentSeason("Midnight Season 2")

check("archiving returns the season it archived",
      archived is not None and archived.name == "Midnight Season 1",
      archived and archived.name)
check("and starts the new one in the same step",
      new_season is not None and new_season.name == "Midnight Season 2",
      new_season and new_season.name)
check("the archive is locked",
      archived is not None and archived.settings.locked is True)
check("there is exactly one archive", len(SYL.GetArchives()) == 1,
      len(SYL.GetArchives()))

# --- THE ASSERTIONS THIS FILE EXISTS FOR ----------------------------------
#
# A raider carrying her old score into the new tier is the symptom that sent
# somebody looking for a way to delete last night's raid — the data was
# correct and in the right place, and every screen was reading past it.
check("the new season starts with no drops",
      len(SYL.GetActiveDrops()) == 0, len(SYL.GetActiveDrops()))
check("and no raid nights",
      len(SYL.GetActiveRaids()) == 0, len(SYL.GetActiveRaids()))
check("THE WINNER CARRIES NO SCORE INTO THE NEW SEASON",
      g.ScoreFor("Selunne") in (0, None), g.ScoreFor("Selunne"))
check("attendance starts again from zero",
      g.NightsFor("Selunne") == 0, g.NightsFor("Selunne"))
check("TIER PROGRESS FORGETS LAST TIER'S BOSSES",
      g.ActiveBosses() == "", g.ActiveBosses())

# --- and the all-time half is still intact --------------------------------
#
# Scoping every accessor would pass everything above and quietly break the
# item tooltip, the export and the all-seasons view.
check("all-time drops still see the archive",
      len(SYL.GetAllDrops()) == 1, len(SYL.GetAllDrops()))
check("all-time nights still see the archive",
      len(SYL.GetAllRaids()) == 5, len(SYL.GetAllRaids()))
check("and all-time boss stats still name last tier's boss",
      g.AllTimeBosses() == "Plexus Sentinel", g.AllTimeBosses())

# --- the new season fills up on its own -----------------------------------
lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason

    -- A different raid three months later, so the new season cannot pass a
    -- check by accidentally overlapping the archived one's nights or bosses.
    season.raids = {
        MakeNight('n1', 1793491200, '2026-11-01', 'Dimensius', 3135),
        MakeNight('n2', 1793577600, '2026-11-02', 'Dimensius', 3135),
        MakeNight('n3', 1793664000, '2026-11-03', 'Dimensius', 3135),
    }

    season.drops = {
        MakeWin('n-d1', 1793491800, 'Crown of the Starless',
            'Dimensius', 3135),
    }

    ShowUsYourLootDB.loot = season.loot
    """
)

SYL.LootHistoryStore.RebuildIndex()

check("the new season scores its own wins", g.ScoreFor("Selunne") == 100,
      g.ScoreFor("Selunne"))
check("counting only its own nights", g.NightsFor("Selunne") == 3,
      g.NightsFor("Selunne"))
check("and the tier tile shows only the new raid",
      g.ActiveBosses() == "Dimensius", g.ActiveBosses())
check("while all-time now holds both tiers",
      g.AllTimeBosses() == "Dimensius,Plexus Sentinel", g.AllTimeBosses())

# --- the screens are counted, not trusted ---------------------------------
#
# EVERYTHING ABOVE ASSERTS THE ACCESSORS, WHICH IS NOT THE BUG THAT HAPPENED.
# The accessors were always right; fifteen call sites asked the wrong one. A
# check that calls GetActiveDrops itself and compares numbers would pass
# happily while every panel on screen still read across the archives.
#
# So the all-time accessors are wrapped in counters and the real screens are
# driven. A season-scoped surface must never reach them. Same reasoning as
# test_bossespanel counting GetMissing: the call is the assertion, because a
# panel making it looks completely normal.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    ALL_TIME_CALLS, ALL_TIME_WHICH = 0, {}

    local realDrops, realRaids = SYL.GetAllDrops, SYL.GetAllRaids

    function CountAllTimeCalls()
        ALL_TIME_CALLS, ALL_TIME_WHICH = 0, {}

        SYL.GetAllDrops = function(...)
            ALL_TIME_CALLS = ALL_TIME_CALLS + 1
            table.insert(ALL_TIME_WHICH, 'GetAllDrops')

            return realDrops(...)
        end

        SYL.GetAllRaids = function(...)
            ALL_TIME_CALLS = ALL_TIME_CALLS + 1
            table.insert(ALL_TIME_WHICH, 'GetAllRaids')

            return realRaids(...)
        end
    end

    function StopCountingAllTimeCalls()
        SYL.GetAllDrops, SYL.GetAllRaids = realDrops, realRaids
    end

    function WhichAllTimeCalls()
        return table.concat(ALL_TIME_WHICH, ',')
    end

    function MakeTile()
        return { body = StubFrame(), rows = {}, title = StubFrame() }
    end

    -- The journal walk is expensive and behind a button; the Bosses panel is
    -- built here for its data call, not to test the walk. test_bossespanel
    -- owns that.
    SYL.LootTable.GetMissing = function() return {}, 0, 0 end
    SYL.LootTable.GetMissingIfKnown = function() return nil end
    """
)

g.CountAllTimeCalls()

for widget in SYL.Dashboard.WIDGETS.values():
    key = widget["key"]
    renderer = SYL.DashboardWidgets.RENDERERS[key]

    if renderer is not None:
        renderer(lua.globals().MakeTile())

check("no dashboard widget reads across the archives",
      g.ALL_TIME_CALLS == 0, g.WhichAllTimeCalls())

parent = lua.globals().UIParent

for label, panel_module in (
    ("the Raiders board", SYL.RaidersPanel),
    ("the Bosses board", SYL.BossesPanel),
    ("the Nights calendar", SYL.NightsPanel),
):
    g.CountAllTimeCalls()

    panel_module.Create(parent)
    panel_module.Refresh()

    check(f"{label} reads its own season only",
          g.ALL_TIME_CALLS == 0, g.WhichAllTimeCalls())

# /syl due and /syl bosses answer the same questions in chat, and a chat
# command quietly disagreeing with the board it points at is the exact shape
# of the last ordering bug.
for label, report in (
    ("/syl due", lambda: SYL.CommandReports.Due(10)),
    ("/syl bosses", lambda: SYL.CommandReports.Bosses(10)),
):
    g.CountAllTimeCalls()
    report()

    check(f"{label} reads its own season only",
          g.ALL_TIME_CALLS == 0, g.WhichAllTimeCalls())

g.StopCountingAllTimeCalls()

# --- renaming -------------------------------------------------------------
#
# The active season can be renamed; an archive cannot be reached by it. Worth
# asserting because an officer who archives before renaming has no route back
# to a mis-named archive, and a rename that silently hit the wrong season
# would be worse than the gap.
#
# Normalized in Lua rather than unpacked here: RenameActiveSeason returns a
# bare `true` on success and `false, message` on failure, and lupa only builds
# a tuple for the two-value case — so unpacking in Python raises on the happy
# path and reads as a broken test rather than a one-value return.
lua.execute(
    """
    function TryRename(name)
        local ok, message = ShowUsYourLoot.RenameActiveSeason(name)

        if ok then
            return 'ok'
        end

        return 'refused:' .. tostring(message)
    end
    """
)

check("the active season renames",
      g.TryRename("Midnight Season 2 (renamed)") == "ok")
check("the rename lands on the active season",
      SYL.GetActiveSeason().name == "Midnight Season 2 (renamed)",
      SYL.GetActiveSeason().name)
check("and leaves the archive's name alone",
      SYL.GetArchives()[1].name == "Midnight Season 1",
      SYL.GetArchives()[1].name)

refused = g.TryRename("   ")
check("an empty name is refused with a reason",
      refused.startswith("refused:") and refused != "refused:nil", refused)

# --- and the way back ------------------------------------------------------
#
# Aimee, after archiving a season she was still raiding: "i archived the
# 08/18-08/22. now how do i unarchive them?" There was no answer — Archive was
# a button and nothing in the addon undid it.
#
# The half worth guarding is what happens to the season that is active at the
# time. Archiving leaves a brand new empty one behind, and that is nearly
# always what is sitting there when somebody wants this, so an empty one is
# discarded rather than filed as history. One with records in it is archived
# properly, because throwing away a raid night to recover a different one is
# not a fix.

# A clean database: this file has already archived a season above, and these
# assertions count archives.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    function SeedSeason(name, dropID)
        local season = ShowUsYourLootDB.activeSeason

        season.name = name
        season.drops = { { id = dropID, timestamp = 1, itemName = 'Thing' } }
        season.loot = {}
    end

    function ActiveName() return ShowUsYourLootDB.activeSeason.name end
    function ActiveDrops() return #(ShowUsYourLootDB.activeSeason.drops or {}) end
    function ArchiveCount() return #ShowUsYourLootDB.archives end
    function ArchiveName(i) return ShowUsYourLootDB.archives[i].name end
    function ActiveLocked()
        return ShowUsYourLootDB.activeSeason.settings
            and ShowUsYourLootDB.activeSeason.settings.locked and true or false
    end
    """
)

g = lua.globals()

g.SeedSeason("Raided In", "keep-me")
SYL.ArchiveCurrentSeason("Fresh And Empty")

check("archiving leaves an empty season behind", g.ActiveDrops() == 0)
check("and the raided one is on the archive list", g.ArchiveCount() == 1)

season, displaced = SYL.UnarchiveSeason(1)

check("BRINGING IT BACK MAKES IT ACTIVE AGAIN",
      g.ActiveName() == "Raided In", g.ActiveName())
check("with its records", g.ActiveDrops() == 1, g.ActiveDrops())
check("the empty season it displaced is discarded, not filed",
      g.ArchiveCount() == 0, g.ArchiveCount())
check("nothing is reported as displaced", displaced is None)
check("and the lock comes off, or the night's drops have nowhere to go",
      g.ActiveLocked() is False)

# A season with records in it must not be thrown away to recover another.
g.SeedSeason("Raided In", "keep-me")
SYL.ArchiveCurrentSeason("Also Raided In")
g.SeedSeason("Also Raided In", "keep-me-too")

season, displaced = SYL.UnarchiveSeason(1)

check("a season with records is archived rather than discarded",
      g.ArchiveCount() == 1 and g.ArchiveName(1) == "Also Raided In",
      (g.ArchiveCount(), g.ArchiveCount() and g.ArchiveName(1)))
check("and it is named back, since only one of the two was ticked",
      displaced is not None and displaced.name == "Also Raided In")
check("the one asked for is active", g.ActiveName() == "Raided In")

# Refusals name a reason rather than failing quietly.
missing, why = SYL.UnarchiveSeason(99)

check("an index that is not there is refused with a reason",
      missing is None and type(why) is str and len(why) > 0, why)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
