"""The Nights calendar draws, and a night lands on exactly one day.

Two things are being established, and the second is the one with teeth.

CALENDAR ARITHMETIC. The grid is laid out from DaysInMonth and FirstWeekday,
and both are computed from timestamps rather than from a table of lengths, so
they have to survive leap years and the month lengths that differ. A grid that
is one cell out puts every night in the month on the wrong weekday, and nothing
about the screen would look broken.

A NIGHT IS ONE DAY AND ONE NIGHT. A Tuesday that cleared Heroic and then pulled
Mythic is two sessions and one night, and a raid running past midnight belongs
to the night it started. Both are handled by keying on session.dateText rather
than recomputing from the timestamp, and both are asserted here — the roster is
folded across the day's sessions too, so somebody who brought a main and then
an alt counts once.

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


# --- calendar arithmetic --------------------------------------------------
#
# Every month length that differs, plus both halves of the leap year rule.
# 2000 is a leap year and 1900 was not; the century rule is the one a lookup
# table gets wrong.
MONTH_CASES = [
    ("January has 31", 2026, 1, 31),
    ("February 2026 has 28", 2026, 2, 28),
    ("February 2024 has 29", 2024, 2, 29),
    ("February 2000 has 29 — divisible by 400", 2000, 2, 29),
    ("April has 30", 2026, 4, 30),
    ("December has 31", 2026, 12, 31),
]

for label, y, m, want in MONTH_CASES:
    check(label, SYL.NightIndex.DaysInMonth(y, m) == want, SYL.NightIndex.DaysInMonth(y, m))

# 1 = Sunday, matching date("*t").wday. 2026-08-01 was a Saturday.
check(
    "the first of August 2026 is a Saturday",
    SYL.NightIndex.FirstWeekday(2026, 8) == 7,
    SYL.NightIndex.FirstWeekday(2026, 8),
)

check(
    "a day key is zero padded",
    SYL.NightIndex.DayKeyFor(2026, 8, 4) == "2026-08-04",
    SYL.NightIndex.DayKeyFor(2026, 8, 4),
)

# --- a fresh install ------------------------------------------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

panel = None

try:
    panel = SYL.NightsPanel.Create(lua.globals().UIParent)
    check("the panel builds", panel is not None)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the panel builds", False, err)

try:
    SYL.NightsPanel.Refresh()
    check("it refreshes on an empty database", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes on an empty database", False, err)

# --- with data ------------------------------------------------------------
#
# One night with two sessions, the second starting after midnight but carrying
# the night's own dateText, and an alt of the same person in the second.
lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason

    season.raids = {
        {
            id = 'r1',
            startedAt = 1786320000,          -- the night the addon calls 2026-08-10
            endedAt = 1786330800,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 15,
            difficultyName = 'Heroic',
            dateText = '2026-08-10',
            encounters = {
                { name = 'Plexus Sentinel', encounterID = 3129, killed = true },
                { name = "Loom'ithar", encounterID = 3130, killed = true },
            },
            roster = {
                P1 = { guid = 'P1', name = 'Selunne' },
                P2 = { guid = 'P2', name = 'Aimee' },
            },
        },
        {
            -- Past midnight by the clock, still the same raid night. The
            -- dateText is what says so.
            --
            -- A FULL 24 HOURS LATER, deliberately. A realistic four-hour gap
            -- lands on the same calendar day in some timezones and not in
            -- others, which would make this assertion pass or fail depending
            -- on the machine running it. A whole day apart is unambiguous
            -- everywhere, and the rule under test — dateText decides, not the
            -- clock — is the same rule either way.
            id = 'r2',
            startedAt = 1786406400,
            endedAt = 1786410000,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 16,
            difficultyName = 'Mythic',
            dateText = '2026-08-10',
            encounters = {
                { name = 'Plexus Sentinel', encounterID = 3129, killed = false },
            },
            roster = {
                P1 = { guid = 'P1', name = 'Selunne' },
                P3 = { guid = 'P3', name = 'Trialist' },
            },
        },
        -- A Timewalking raid, which is real content and is not a raid night.
        {
            id = 'r3',
            startedAt = 1786492800,
            endedAt = 1786496400,
            instanceID = 2,
            instanceName = 'Ulduar',
            instanceType = 'raid',
            difficultyID = 33,
            difficultyName = 'Timewalking',
            dateText = '2026-08-12',
            encounters = { { name = 'Flame Leviathan', killed = true } },
            roster = { P1 = { guid = 'P1', name = 'Selunne' } },
        },
    }

    ShowUsYourLootDB.loot = season.loot

    function DayByKey(key)
        local days, byDay = ShowUsYourLoot.NightIndex.Build(
            ShowUsYourLoot.GetActiveRaids(), ShowUsYourLoot.GetActiveDrops()
        )

        return byDay[key], #days
    end

    function OpeningMonth()
        local days = ShowUsYourLoot.NightIndex.Build(
            ShowUsYourLoot.GetActiveRaids(), ShowUsYourLoot.GetActiveDrops()
        )

        local year, month = ShowUsYourLoot.NightIndex.LatestMonth(days)

        return string.format('%04d-%02d', year, month)
    end
    """
)

SYL.LootHistoryStore.RebuildIndex()

g = lua.globals()

night, total = g.DayByKey("2026-08-10")

check("the two sessions are one night", total == 1, f"{total} nights indexed")
check("both sessions are on it", night is not None and len(list(night["sessions"].values())) == 2)
check("pulls sum across the night", night is not None and night["pulls"] == 3, night and night["pulls"])
check("kills sum across the night", night is not None and night["kills"] == 2, night and night["kills"])

# Three distinct people across two sessions, one of whom was in both.
check(
    "the roster folds rather than adding up",
    night is not None and night["rosterCount"] == 3,
    night and night["rosterCount"],
)

check(
    "both difficulties are named",
    night is not None and len(list(night["difficultyNames"].values())) == 2,
    night and list(night["difficultyNames"].values()),
)

# Timewalking is real content and is not a raid team's night. Excluding it
# from nights but not from wins is what let one wipe a two-month drought.
timewalking, _ = g.DayByKey("2026-08-12")
check("a Timewalking raid does not shade a day", timewalking is None, timewalking)

# --- the panel draws in both views ----------------------------------------
# Off the day key, not off a timestamp — so the month it opens on always
# contains the night it opened for.
check(
    "it opens on the month of the most recent night",
    g.OpeningMonth() == "2026-08",
    g.OpeningMonth(),
)

for label, action in (
    ("with data", lambda: SYL.NightsPanel.Refresh()),
    ("a day selected", lambda: SYL.NightsPanel.Select("2026-08-10")),
    ("in week view", lambda: SYL.NightsPanel.SetView("week")),
    ("stepping forward a week", lambda: SYL.NightsPanel.Step(1)),
    ("stepping back a week", lambda: SYL.NightsPanel.Step(-1)),
    ("back in month view", lambda: SYL.NightsPanel.SetView("month")),
    ("stepping forward a month", lambda: SYL.NightsPanel.Step(1)),
    ("stepping back over a year boundary", lambda: SYL.NightsPanel.Step(-13)),
):
    try:
        action()
        check(f"it refreshes {label}", True)
    except Exception as err:  # noqa: BLE001
        check(f"it refreshes {label}", False, err)

# --- the stat panel -------------------------------------------------------
for label, day in (("a night", night), ("no selection", None)):
    try:
        SYL.NightStats.Render(panel["stats"], day)
        check(f"the stat panel draws for {label}", True)
    except Exception as err:  # noqa: BLE001
        check(f"the stat panel draws for {label}", False, err)

# --- Today, and the schedule marker -------------------------------------
#
# Three months of arrows is a long way to walk back, so there is a button.
lua.execute("ShowUsYourLoot.NightsPanel.Step(-4)")

today = SYL.NightsPanel.Today()

check("Today returns to the current day",
      today == SYL.RaidSchedule.TodayKey(), today)

# THE SCHEDULE IS FORWARD ONLY. IsRaidNight answers "is this one of our
# weekdays", which is true of every Tuesday since the calendar began. Drawing
# that on a past day claims a raid the addon has no record of — which is what
# put raid nights on the calendar before the season had started.
lua.execute(
    """
    ShowUsYourLoot.RaidSchedule.SetWeekday(3, true)   -- Tuesday
    ShowUsYourLoot.RaidSchedule.SetWeekday(5, true)   -- Thursday

    function ScheduledOn(key)
        return ShowUsYourLoot.RaidSchedule.IsRaidNight(key)
            and key >= ShowUsYourLoot.RaidSchedule.TodayKey()
    end
    """
)

todayKey = SYL.RaidSchedule.TodayKey()
past = SYL.RaidSchedule.Offset(todayKey, -70)
ahead = SYL.RaidSchedule.Offset(todayKey, 70)

scheduledAhead = any(
    lua.globals().ScheduledOn(SYL.RaidSchedule.Offset(ahead, day))
    for day in range(0, 7)
)
scheduledBehind = any(
    lua.globals().ScheduledOn(SYL.RaidSchedule.Offset(past, day))
    for day in range(0, 7)
)

check("a raid night ahead of today is marked", scheduledAhead)
check("A PAST WEEK IS NEVER MARKED AS A RAID NIGHT", not scheduledBehind,
      f"{past} was drawn as scheduled")

# --- the name box suggests roster names ----------------------------------
#
# Typing a whole name-realm to mark somebody out is what a slash command
# already made people do.
lua.execute(
    """
    ShowUsYourLoot.RosterData.Build = function()
        return {
            { name = 'Talestra' },
            { name = 'Talenor' },
            { name = 'Saebie' },
        }
    end
    """
)

check("a prefix offers every roster name under it",
      list(SYL.AbsenceControls.Match("tal", 5).values())
      == ["Talenor", "Talestra"],
      list(SYL.AbsenceControls.Match("tal", 5).values()))
check("matching ignores case",
      len(SYL.AbsenceControls.Match("TAL", 5)) == 2)
check("a name nobody has is no suggestion",
      len(SYL.AbsenceControls.Match("zzz", 5)) == 0)
check("an empty box suggests nothing rather than everybody",
      len(SYL.AbsenceControls.Match("", 5)) == 0)
check("and the list is capped",
      len(SYL.AbsenceControls.Match("", 1)) == 0
      and len(SYL.AbsenceControls.Match("s", 1)) == 1)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
