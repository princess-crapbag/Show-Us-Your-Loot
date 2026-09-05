"""Tier progress on one difficulty, and the week a boss first died.

Aimee: "right now it says 22 of 23 killed. there are 8 bosses in one raid and
1 boss in the other, plus there is LFR, Normal, Heroic, Mythic. different
guild prog on different difficulties. id like to be able to choose which
difficulty that section shows. for us it would be heroic. so were 1/1H in TG
and 6/8H in VA."

Her 22 is eight Normal plus six Heroic plus six LFR in The Venomous Abyss,
one Normal and one Heroic in The Tidebound Grotto. Every one is a real kill
and adding them together describes nothing anybody says out loud -- while the
tile's own note in Core/Dashboard.lua has always claimed "kills per boss, kept
separate by difficulty".

What is worth guarding:

1. DIFFICULTIES DO NOT LEAK INTO EACH OTHER. The whole bug. A Normal kill must
   never count toward a Heroic total, and the same boss killed on two
   difficulties is two different first kills on two different dates.

2. THE FIRST KILL IS THE EARLIEST, not the most recent. Raid nights are walked
   in whatever order the season stored them and a boss is killed most weeks
   after the first, so taking the last one seen would date every kill to the
   most recent clear.

3. WEEKS RESET ON TUESDAY, in the player's own time zone. A kill at 20:00
   local on Monday belongs to the week that began the Tuesday before, and a
   season anchored on its first raid night rather than on when the addon was
   installed.

4. THE BOSS COUNT IS A FLOOR AND MUST NOT READ HIGH. The client cannot be
   asked how many encounters a raid has, so the total is how many distinct
   bosses this guild has met in there on ANY difficulty.

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

HEROIC, NORMAL, LFR = 15, 14, 17

# Tuesday 2026-08-18 12:00 local, which is week one by Aimee's own reckoning.
WEEK1 = lua.eval(
    "function() return time({year=2026, month=8, day=18, hour=12}) end"
)()
DAY = 86400


def night(instance, difficulty, day_offset, kills, wipes=None):
    """One raid night: an instance, a difficulty, and what died."""
    encounters = []

    for name in kills:
        encounters.append(lua.table_from({
            "name": name,
            "encounterID": 3000 + kills.index(name),
            "difficultyID": difficulty,
            "killed": True,
            "at": WEEK1 + day_offset * DAY,
        }))

    for name in (wipes or []):
        encounters.append(lua.table_from({
            "name": name,
            "encounterID": 3900,
            "difficultyID": difficulty,
            "killed": False,
            "at": WEEK1 + day_offset * DAY,
        }))

    return lua.table_from({
        "instanceName": instance,
        "difficultyID": difficulty,
        "startedAt": WEEK1 + day_offset * DAY,
        "encounters": lua.table_from(encounters),
    })


VA = "The Venomous Abyss"
TG = "The Tidebound Grotto"

# Her season, in the shape her database actually holds it.
SESSIONS = lua.table_from([
    # Week 1: Normal clears.
    night(VA, NORMAL, 0, ["Nek'zali", "Sentinels", "Explorers", "Sszorak",
                          "Vashnik"]),
    night(VA, NORMAL, 2, ["Twin Fangs", "Coiled Altar"]),
    night(TG, NORMAL, 2, ["Nymrissa"]),
    night(VA, LFR, 0, ["Twin Fangs", "Nek'zali"]),
    # Week 2.
    night(VA, NORMAL, 7, ["Ula'tek"]),
    night(VA, HEROIC, 7, ["Nek'zali"]),
    night(VA, HEROIC, 9, ["Explorers"]),
    night(TG, HEROIC, 9, ["Nymrissa"]),
    # Week 3.
    night(VA, HEROIC, 14, ["Sentinels", "Vashnik"]),
    night(VA, HEROIC, 16, ["Sszorak", "Twin Fangs"], wipes=["Coiled Altar"]),
    # And the same bosses again, later, which must not move a first kill.
    night(VA, HEROIC, 21, ["Nek'zali", "Explorers", "Sentinels"]),
])

heroic = SYL.TierProgress.Build(SESSIONS, HEROIC)

by_name = {}
for index in range(1, len(heroic) + 1):
    by_name[heroic[index].name] = heroic[index]

check("BOTH RAIDS ARE LISTED SEPARATELY", len(heroic) == 2, len(heroic))

check("HER OWN NUMBER: 6 of 8 Heroic in The Venomous Abyss",
      SYL.TierProgress.Describe(by_name[VA]) == "6/8",
      SYL.TierProgress.Describe(by_name[VA]))
check("and 1 of 1 Heroic in The Tidebound Grotto",
      SYL.TierProgress.Describe(by_name[TG]) == "1/1",
      SYL.TierProgress.Describe(by_name[TG]))

check("THE UNFINISHED RAID LEADS, since that is the one being pushed",
      heroic[1].name == VA, heroic[1].name)

# --- 1. difficulties do not leak ------------------------------------------
normal = SYL.TierProgress.Build(SESSIONS, NORMAL)
normal_by = {}
for index in range(1, len(normal) + 1):
    normal_by[normal[index].name] = normal[index]

check("NORMAL IS A DIFFERENT ANSWER ENTIRELY",
      SYL.TierProgress.Describe(normal_by[VA]) == "8/8",
      SYL.TierProgress.Describe(normal_by[VA]))

lfr = SYL.TierProgress.Build(SESSIONS, LFR)

check("and so is LFR", SYL.TierProgress.Describe(lfr[1]) == "2/8",
      SYL.TierProgress.Describe(lfr[1]))

killed, seen = SYL.TierProgress.Totals(heroic)

check("NOTHING ADDS THE DIFFICULTIES TOGETHER any more",
      killed == 7 and seen == 9, (killed, seen))

# --- 2. the FIRST kill, not the latest ------------------------------------
va_kills = {}
for index in range(1, len(by_name[VA].kills) + 1):
    kill = by_name[VA].kills[index]
    va_kills[kill.name] = kill

check("A BOSS KILLED AGAIN LATER KEEPS ITS FIRST DATE",
      va_kills["Nek'zali"].week == 2, va_kills["Nek'zali"].week)
check("and is not listed twice for it",
      len(by_name[VA].kills) == 6, len(by_name[VA].kills))

check("kills are listed oldest first, the way progress is read",
      by_name[VA].kills[1].name == "Nek'zali",
      by_name[VA].kills[1].name)

# --- 3. weeks -------------------------------------------------------------
check("week one is the season's first raid night",
      va_kills["Nek'zali"].week == 2 and by_name[TG].kills[1].week == 2,
      (va_kills["Nek'zali"].week, by_name[TG].kills[1].week))
check("WEEK 3 IS WEEK 3, counting Tuesdays",
      va_kills["Sszorak"].week == 3 and va_kills["Sentinels"].week == 3,
      (va_kills["Sszorak"].week, va_kills["Sentinels"].week))

# A Monday night belongs to the week that began the Tuesday before, which is
# the case a naive divide-by-seven gets wrong.
monday = WEEK1 + 6 * DAY
check("A MONDAY KILL IS STILL IN THE WEEK THAT STARTED TUESDAY",
      SYL.TierProgress.WeekOf(monday, WEEK1) == 1,
      SYL.TierProgress.WeekOf(monday, WEEK1))
check("and the Tuesday after it starts week 2",
      SYL.TierProgress.WeekOf(WEEK1 + 7 * DAY, WEEK1) == 2,
      SYL.TierProgress.WeekOf(WEEK1 + 7 * DAY, WEEK1))

# --- 4. the boss count is a floor -----------------------------------------
#
# Eight comes from Normal, where they have cleared the whole raid. A guild
# that had only ever set foot in Heroic would read 6 of 6 and be right about
# everything it knows.
heroic_only = lua.table_from([
    night(VA, HEROIC, 7, ["Nek'zali"]),
    night(VA, HEROIC, 9, ["Explorers"]),
])

lonely = SYL.TierProgress.Build(heroic_only, HEROIC)

check("THE TOTAL NEVER READS HIGHER THAN WHAT THIS GUILD HAS MET",
      SYL.TierProgress.Describe(lonely[1]) == "2/2",
      SYL.TierProgress.Describe(lonely[1]))

# --- a wipe is not a kill -------------------------------------------------
check("a boss pulled and not killed is not counted",
      va_kills.get("Coiled Altar") is None,
      list(va_kills))

# --- a raid never entered on this difficulty is left out ------------------
mythic = SYL.TierProgress.Build(SESSIONS, 16)

check("A DIFFICULTY WITH NO KILLS IS EMPTY, not a list of zeroes",
      len(mythic) == 0, len(mythic))

# --- the chooser ----------------------------------------------------------
check("the difficulty defaults to Heroic",
      SYL.TierProgress.GetDifficulty() == HEROIC)

SYL.TierProgress.SetDifficulty(NORMAL)

check("and what is chosen is SAVED, not per-session",
      SYL.TierProgress.GetDifficulty() == NORMAL
      and lua.globals().ShowUsYourLootDB.settings.tierDifficulty == NORMAL,
      SYL.TierProgress.GetDifficulty())

check("a difficulty nobody offers is refused",
      SYL.TierProgress.SetDifficulty(99) is False
      and SYL.TierProgress.GetDifficulty() == NORMAL)

check("cycling walks all four and comes back round",
      [SYL.TierProgress.Label(entry.id)
       for entry in [SYL.TierProgress.DIFFICULTIES[i] for i in range(1, 5)]]
      == ["LFR", "Normal", "Heroic", "Mythic"])

SYL.TierProgress.SetDifficulty(HEROIC)

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
