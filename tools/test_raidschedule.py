"""The raid schedule answers without a calendar, and manual always wins.

This is the feature that unblocked the two dashboard tiles that said "waiting
on the calendar" for two days, and it unblocked them by not needing one. Aimee's
guild posts absences in Discord, and nothing on Discord can reach an addon — WoW
makes no HTTP requests, which is the same wall that stopped Warcraft Logs and
Droptimizer import. So the schedule is typed, and the in-game calendar is an
optional import on top rather than the thing it all depends on.

TWO RULES CARRY THE DESIGN AND BOTH ARE ASSERTED HERE.

An import never overwrites something a person typed. An officer who canceled
Wednesday has said something the calendar has not caught up with, and an import
that overruled them would make the addon argue with whoever maintains it.

A cancellation is stored rather than deleted. Deleting a night that the weekly
pattern generates just lets the pattern put it straight back, so "not this week"
has to be a thing you can say and not merely the absence of a thing.

Date arithmetic goes through the client's clock at midday throughout, so the
month and year rollovers below are the real ones rather than string surgery.

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

TUESDAY = 3
WEDNESDAY = 4


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    function ResetSchedule()
        ShowUsYourLootDB.schedule = nil
        ShowUsYourLoot.RaidSchedule.Store()
    end

    function OutNames(dayKey)
        local names = {}

        for _, absence in ipairs(ShowUsYourLoot.Absences.WhoIsOut(dayKey)) do
            table.insert(names, absence.name)
        end

        return table.concat(names, ',')
    end
    """
)

g = lua.globals()
S = SYL.RaidSchedule

# Absences moved to their own module; the date helpers and the schedule
# itself stayed. Two handles rather than one, so this test says which half it
# is exercising on every line.
A = SYL.Absences

# --- day arithmetic --------------------------------------------------------
#
# Month end, month length and a year boundary, all through the client's clock
# rather than by adding to the string.
OFFSETS = [
    ("a day inside the month", "2026-08-10", 1, "2026-08-11"),
    ("over the end of a 31 day month", "2026-08-31", 1, "2026-09-01"),
    ("over the end of a 30 day month", "2026-09-30", 1, "2026-10-01"),
    ("over a year boundary", "2026-12-31", 1, "2027-01-01"),
    ("a whole week", "2026-08-10", 7, "2026-08-17"),
    ("February in a leap year", "2024-02-28", 1, "2024-02-29"),
    ("February in a common year", "2026-02-28", 1, "2026-03-01"),
]

for label, start, days, want in OFFSETS:
    check(label, S.Offset(start, days) == want, S.Offset(start, days))

# 2026-08-10 was a Monday. 1 = Sunday.
check("the weekday of a known date", S.WeekdayOf("2026-08-10") == 2, S.WeekdayOf("2026-08-10"))
check("and it is named", S.WeekdayName("2026-08-10") == "Monday", S.WeekdayName("2026-08-10"))

# --- nothing configured ----------------------------------------------------
g.ResetSchedule()

check("a fresh install has no schedule", S.IsConfigured() is False)
check("and no next night", S.NextNight("2026-08-10") is None)

# --- the recurring pattern -------------------------------------------------
g.ResetSchedule()
S.SetWeekday(TUESDAY, True)
S.SetWeekday(WEDNESDAY, True)

check("setting days configures it", S.IsConfigured() is True)
check("and describes them in order", S.DescribeWeekdays() == "Tuesday, Wednesday", S.DescribeWeekdays())

# From Monday 2026-08-10 the next raid night is Tuesday the 11th.
night, reason = S.NextNight("2026-08-10")

check("the next night comes from the pattern", night == "2026-08-11", night)
check("and says where it came from", reason == "weekly", reason)

# Asked on a raid day, the answer is today rather than next week.
check("asked on a raid day, tonight counts", S.NextNight("2026-08-11")[0] == "2026-08-11")

# --- manual beats the pattern ---------------------------------------------
#
# Canceling Wednesday must push the answer to the following Tuesday, not
# quietly leave Wednesday in place.
S.SetNight("2026-08-12", lua.table(source="manual", canceled=True))

check("a canceled night is not a raid night", S.IsRaidNight("2026-08-12")[0] is False)
check("and says it was canceled", S.IsRaidNight("2026-08-12")[1] == "canceled")
check(
    "the next night after Tuesday skips the canceled Wednesday",
    S.NextNight("2026-08-12")[0] == "2026-08-18",
    S.NextNight("2026-08-12")[0],
)

# --- an import never overrules a person ------------------------------------
g.ResetSchedule()

S.SetNight("2026-08-20", lua.table(source="manual", title="Typed in"))

check(
    "an import is refused over a manual night",
    S.SetNight("2026-08-20", lua.table(source="calendar", title="From calendar")) is False,
)
check(
    "and the typed one survives",
    S.GetNight("2026-08-20")["title"] == "Typed in",
    S.GetNight("2026-08-20")["title"],
)

# The other direction is allowed: a person may always overrule an import.
S.SetNight("2026-08-21", lua.table(source="calendar", title="From calendar"))

check(
    "a person may overrule an import",
    S.SetNight("2026-08-21", lua.table(source="manual", title="Corrected")) is True,
)
check(
    "and the correction sticks",
    S.GetNight("2026-08-21")["title"] == "Corrected",
    S.GetNight("2026-08-21")["title"],
)

# --- absences are ranges ---------------------------------------------------
g.ResetSchedule()

A.AddAbsence("Dravok", "2026-08-10", "2026-08-16", lua.table(reason="holiday"))
A.AddAbsence("Selunne", "2026-08-12", "2026-08-12", None)

check("somebody out all week is out mid week", g.OutNames("2026-08-13") == "Dravok", g.OutNames("2026-08-13"))
check("both are out on the overlapping day", g.OutNames("2026-08-12") == "Dravok,Selunne", g.OutNames("2026-08-12"))
check("nobody is out before the range", g.OutNames("2026-08-09") == "", g.OutNames("2026-08-09"))
check("nor after it", g.OutNames("2026-08-17") == "", g.OutNames("2026-08-17"))

# Inclusive at both ends — "out from the 10th to the 16th" includes both.
check("the first day of a range counts", "Dravok" in g.OutNames("2026-08-10"))
check("and the last day counts", "Dravok" in g.OutNames("2026-08-16"))

# A range knows it is one, so the tile can print an end date instead of a
# reason and not read as though somebody is out for a single evening.
out = A.WhoIsOut("2026-08-13")

check("a range is marked as one", out[1]["multiDay"] is True)
check("a single day is not", A.WhoIsOut("2026-08-12")[2]["multiDay"] is False)

# --- clearing --------------------------------------------------------------
check("expired absences are dropped", A.ClearExpired("2026-08-17") == 2, A.ClearExpired("2026-08-17"))
check("and nothing is left out", g.OutNames("2026-08-13") == "", g.OutNames("2026-08-13"))

# --- the calendar degrades rather than erroring ----------------------------
#
# test_load stubs no C_Calendar, which is exactly the shape of a client that
# does not expose it. Every entry point has to answer rather than throw.
check("the calendar reports itself unavailable", SYL.GuildCalendar.IsAvailable() is False)

added, skipped, message = SYL.GuildCalendar.Import(2026, 8)

check("importing says why it cannot", added == 0 and "calendar API" in message, message)

read, err = SYL.GuildCalendar.ReadMonth(2026, 8)

check("reading a month answers nil and a reason", read is None and err == "no calendar", err)

count, note = SYL.GuildCalendar.ImportDeclines("2026-08-12")

check("importing declines does the same", count == 0, note)
check(
    "and a malformed date is rejected before any of that",
    SYL.GuildCalendar.ImportDeclines("not-a-date")[0] == 0,
)

# --- the tiles draw --------------------------------------------------------
g.ResetSchedule()

lua.execute("function MakeTile() return { body = StubFrame(), rows = {}, title = StubFrame() } end")

# One tile, not two. "Who is out" had a tile of its own for about a day, and a
# seventh tile forces the dashboard grid onto a third row inside a window that
# cannot grow — every tile shrank to two usable lines and the full-width strip
# fell off the bottom of the frame. Absences live in the next-raid-night tile
# now, which answers the same question anyway.
for label in ("nextNight",):
    for state in ("empty", "configured"):
        if state == "configured":
            S.SetWeekday(TUESDAY, True)
            A.AddAbsence("Dravok", S.TodayKey(), S.Offset(S.TodayKey(), 6), None)

        try:
            SYL.DashboardWidgets.RENDERERS[label](g.MakeTile())
            check(f"the {label} tile draws when {state}", True)
        except Exception as err:  # noqa: BLE001 — any Lua error is the finding
            check(f"the {label} tile draws when {state}", False, err)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
