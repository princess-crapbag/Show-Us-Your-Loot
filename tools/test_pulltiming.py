# -*- coding: utf-8 -*-
"""When the raid arrived, when each pull started, and who was handing out loot.

THREE THINGS THE ADDON WAS NOT RECORDING, all asked for by Aimee after she
read the raid-night pane and did not believe it.

  WHEN THE PULL STARTED. Only the END of a pull was kept: a ten-minute pull
  begun at 9:10 is stamped 9:20. She asked directly -- "if we start a 10
  minute pull at 9:10 will it say we finished at 9:10 or 9:20?" -- and then
  "how much of our 3 hours were fighting? vs afks?", which the end alone
  cannot answer. OnEncounterStart had been writing startedAt onto
  pendingEncounter since sessions existed and it was thrown away on every
  ENCOUNTER_END.

  WHEN THE GROUP ZONED IN. A session is created by the first
  ENCOUNTER_START and by nothing else, so it opens at the first pull. Her raid
  starts at 6:30 and her 2026-08-18 session opens at 6:42, so "2h 42m in the
  instance" was never the evening. "can we record first zone in and last zone
  out?"

  WHO WAS MASTER LOOTER. The addon had no master-looter awareness at all --
  GetLootMethod, IsMasterLooter and masterLooter appeared nowhere in it --
  which is why every drop on her nights reads as her win and nothing can tell
  a drop she reviewed and kept from one nobody has looked at.

WHAT THE ASSERTIONS PROTECT. Every one of these is nil on the sessions
already in her database, because they predate the recording. So the dangerous
fault is not "the number is missing" - it is "the number is zero", which reads
as a fact rather than as an absence. A session that shows "0m in the instance"
or "0m fighting" is worse than one that shows nothing.

Needs `lupa` - see tools/test_lootmessages.py for the setup.
"""
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import test_load  # noqa: E402

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s  %s" % (name, detail))
        failures.append(name)


Session = SYL.RaidSession

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()


def session(**fields):
    """A session table built in Lua, so the accessors see a real one."""
    lua.execute("PROBE = { encounters = {} }")
    probe = lua.globals().PROBE

    for key, value in fields.items():
        if key != "encounters":
            probe[key] = value

    for index, pull in enumerate(fields.get("encounters", []), start=1):
        lua.execute("PROBE.encounters[%d] = {}" % index)
        row = probe.encounters[index]

        for key, value in pull.items():
            row[key] = value

    return probe


# 6:42 PM to 9:24 PM, her real 2026-08-18 guild session.
IN, FIRST, LAST, OUT = 1000, 1720, 11440, 12100


# --------------------------------------------------------------------------
# The pull span, which is what the pane has always shown
# --------------------------------------------------------------------------

night = session(startedAt=FIRST, endedAt=LAST)

check("first pull to last pull is still measured",
      int(Session.GetDurationMinutes(night)) == (LAST - FIRST) // 60)


# --------------------------------------------------------------------------
# Zoned in to zoned out, which is the evening
# --------------------------------------------------------------------------

whole = session(startedAt=FIRST, endedAt=LAST, enteredAt=IN, leftAt=OUT)

check("the evening is longer than the pulls",
      int(Session.PresentMinutes(whole)) == (OUT - IN) // 60)

check("and it is longer than the pull span",
      Session.PresentMinutes(whole) > Session.GetDurationMinutes(whole))

# THE ONE THAT MATTERS. Every session in her database predates this.
check("a session that never recorded an arrival answers nothing, not zero",
      Session.PresentMinutes(session(startedAt=FIRST, endedAt=LAST)) is None)

check("and one with an arrival but no departure falls back to the last pull",
      int(Session.PresentMinutes(
          session(startedAt=FIRST, endedAt=LAST, enteredAt=IN)))
      == (LAST - IN) // 60)

check("a departure before the arrival is refused rather than negated",
      Session.PresentMinutes(
          session(enteredAt=OUT, leftAt=IN, endedAt=OUT)) is None)

check("and a session with nothing at all is survivable",
      Session.PresentMinutes(None) is None)


# --------------------------------------------------------------------------
# Fighting versus between pulls
# --------------------------------------------------------------------------

fought = session(
    startedAt=FIRST,
    endedAt=LAST,
    encounters=[
        {"name": "Nek'zali", "startedAt": FIRST, "at": FIRST + 300,
         "killed": True},
        {"name": "Sszorak", "startedAt": FIRST + 3000, "at": FIRST + 3300,
         "killed": False},
        {"name": "Sszorak", "startedAt": FIRST + 6000, "at": FIRST + 6600,
         "killed": True},
    ],
)

fighting, between, measured, total = Session.FightingMinutes(fought)

check("fighting time is the sum of the pulls",
      int(fighting) == (300 + 300 + 600) // 60, "got %r" % fighting)

check("between-pull time is the rest of the pull span",
      int(between) == ((LAST - FIRST) - 1200) // 60, "got %r" % between)

check("and the two add up to the pull span",
      int(fighting) + int(between)
      == int(Session.GetDurationMinutes(fought)))

check("every pull was measurable", int(measured) == 3 and int(total) == 3)

# HALF-OLD RECORDS. A night part-recorded before this shipped must say how
# many pulls it could actually measure, or it reports half the fighting it did
# as if that were the whole.
mixed = session(
    startedAt=FIRST,
    endedAt=LAST,
    encounters=[
        {"name": "Old", "at": FIRST + 300},
        {"name": "New", "startedAt": FIRST + 3000, "at": FIRST + 3600},
    ],
)

fighting, between, measured, total = Session.FightingMinutes(mixed)

check("a half-recorded night says how many pulls it could measure",
      int(measured) == 1 and int(total) == 2,
      "measured %r of %r" % (measured, total))

# A night entirely of old records must answer nothing rather than zero.
old = session(
    startedAt=FIRST, endedAt=LAST,
    encounters=[{"name": "Old", "at": FIRST + 300}],
)

fighting, between, measured, total = Session.FightingMinutes(old)

check("a night with no pull starts answers nothing, not zero",
      fighting is None and between is None,
      "got %r and %r" % (fighting, between))

check("and still reports how many pulls there were", int(total) == 1)

# A pull that ended before it started is a clock going backwards, not a
# negative fight.
backwards = session(
    startedAt=FIRST, endedAt=LAST,
    encounters=[{"name": "Bad", "startedAt": FIRST + 600, "at": FIRST}],
)

fighting, between, measured, total = Session.FightingMinutes(backwards)

check("a backwards pull is ignored rather than subtracted",
      fighting is None and int(measured) == 0,
      "got %r fighting from %r measured" % (fighting, measured))


# WHERE THE NIGHT WENT used to be answered by RaidSession.HardestFight, which
# was deleted before it ever had a caller: Core/NightIndex.lua already builds
# the same per-boss pull counts across a whole night in day.fights, and the
# night is the unit every screen asks about. Those assertions live in
# tools/test_nightfigures.py now, against day.fights and NightFigures.MostPulls.


# --------------------------------------------------------------------------
# The wiring, read out of the source
# --------------------------------------------------------------------------
#
# These catch the field being dropped somewhere between the event and the
# record, which leaves every new night as blank as the old ones with nothing
# failing.

def source(name):
    return test_load.ROOT.joinpath(name).read_text(encoding="utf-8")

raid = source("Core/RaidSession.lua")

check("the encounter record carries the pull's start",
      "startedAt = startedAt," in raid)

# Guarded on the id, because ENCOUNTER_START and ENCOUNTER_END can interleave
# across a zone change and inheriting the previous boss's start would make one
# pull look like an hour.
check("and only when it belongs to this encounter",
      "pending.encounterID == encounterID" in raid)

check("the session claims the arrival only for its own instance",
      "arrival.instanceID == location.instanceID" in raid)

events = source("Core/Events.lua")

check("zoning in is noted", "RaidSession.NoteArrival" in events)
check("and zoning out", "RaidSession.NoteDeparture" in events)

util = source("Core/Utilities.lua")

check("the client is asked who the master looter is",
      "GetLootMethod" in util and "masterLooter" in util)

check("and the session records it",
      "masterLooter = location.masterLooter" in raid)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
