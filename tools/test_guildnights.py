"""RaidSession.CountsAsNight — which sessions are the guild's own raid nights.

Aimee's first raid night recorded two sessions on one evening: a 49-person LFR
run with one guildie in it, and the 12-person guild Normal. The calendar added
them together and reported "60 raiders · 43 went home with nothing", which is
the number that started this.

THE CASE THIS EXISTS FOR is the ambiguous one. A member with no guildRank is
either not in the guild or was recorded before the client answered, and the
second reads exactly like a pug. If unknown were treated as "not guilded", a
guild raid recorded before the roster loaded would vanish from the calendar
with nothing on screen to say why. So unknown counts, and the recorder's own
rank is what tells the two apart.

The name-form case is here because the first implementation failed it: the
recorder is stored as "Arcangila-Area52" and roster members as "Arcangila", so
an exact compare matched nobody, reported every night as unknown, and turned
the whole filter off while looking like it worked.

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

ROOT = Path(__file__).resolve().parent.parent

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("ShowUsYourLoot = {}")

for name in ("Core/Output.lua", "Core/Utilities.lua", "Core/RaidSession.lua"):
    lua.execute((ROOT / name).read_text(encoding="utf-8"))

RaidSession = lua.globals().ShowUsYourLoot.RaidSession

failures = []


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       got: " + repr(detail))

        failures.append(label)


def session(guilded, ungilded, recorder_ranked=True, difficulty=14,
            instance_type="raid"):
    """A raid session with a roster of the given shape.

    The recorder is always in the roster, because they were standing there.
    `recorder_ranked` is what decides whether the guild data can be trusted.
    """
    # Every member is converted individually. A plain Python dict left inside
    # a Lua table raises KeyError on a missing key instead of returning nil,
    # so a pug with no guildRank would blow up rather than read as unranked —
    # which is the exact case these tests are about.
    def member(name, rank=None):
        fields = {"name": name, "fullName": name}

        if rank is not None:
            fields["guildRank"] = rank

        return lua.table_from(fields)

    roster = {
        "rec": member("Arcangila", "Kennel Master" if recorder_ranked else None)
    }

    for index in range(guilded):
        roster["g%d" % index] = member("Guildie%d" % index, "Good Kitty")

    for index in range(ungilded):
        roster["p%d" % index] = member("Pug%d" % index)

    return lua.table_from({
        "instanceType": instance_type,
        "difficultyID": difficulty,
        "recordedBy": "Arcangila-Area52",
        "roster": lua.table_from(roster),
    })


print("threshold is %.0f%%\n" % (RaidSession.GUILD_SHARE * 100))

# --- the two nights that started this ------------------------------------
# Real shapes from Aimee's saved data: 1 of 49, and 12 of 12.
lfr = session(guilded=0, ungilded=48)
guild = session(guilded=11, ungilded=0)

check("the LFR run is not a guild night", RaidSession.CountsAsNight(lfr) is False)
check("the guild Normal is", RaidSession.CountsAsNight(guild) is True)
check(
    "and their shares are what the saved data says",
    abs(RaidSession.GuildShare(lfr) - 1 / 49) < 0.001
    and RaidSession.GuildShare(guild) == 1.0,
    (RaidSession.GuildShare(lfr), RaidSession.GuildShare(guild)),
)

# --- the threshold itself -------------------------------------------------
# A real Tuesday has a pug tank in it. 16 of 20 is exactly 80% and must pass;
# 15 of 20 is 75% and must not.
check("exactly 80% counts", RaidSession.CountsAsNight(session(15, 4)) is True)
check("75% does not", RaidSession.CountsAsNight(session(14, 5)) is False)

# --- unknown counts -------------------------------------------------------
# The case the filter would silently break on. An unranked recorder means the
# guild roster had not arrived, so nothing about this session's ranks means
# anything — and a night somebody turned up to must not vanish over it.
blind = session(guilded=0, ungilded=19, recorder_ranked=False)

check("an unloaded guild roster reads as unknown", RaidSession.GuildShare(blind) is None)
check("and an unknown night still counts", RaidSession.CountsAsNight(blind) is True)

# --- the name-form trap ---------------------------------------------------
# The recorder carries a realm and the roster does not. This is the exact bug
# the first implementation shipped with.
realmful = session(guilded=11, ungilded=0)
realmful["roster"]["rec"]["fullName"] = "Arcangila-Area52"
realmful["roster"]["rec"]["name"] = "Arcangila-Area52"

check(
    "the recorder is found whether or not the realm is on the name",
    RaidSession.GuildShare(realmful) == 1.0,
    RaidSession.GuildShare(realmful),
)

missing = session(guilded=11, ungilded=0)
missing["recordedBy"] = "Somebodyelse-Area52"

check(
    "a recorder who is not in the roster reads as unknown",
    RaidSession.GuildShare(missing) is None,
)
check("so that night counts too", RaidSession.CountsAsNight(missing) is True)

# --- content type still applies ------------------------------------------
# Guild share does not rescue a Mythic+ dungeon or a Timewalking raid.
dungeon = session(guilded=11, ungilded=0, instance_type="party", difficulty=8)

check("a full guild dungeon group is not a raid night",
      RaidSession.CountsAsNight(dungeon) is False)

# --- NightsOnly -----------------------------------------------------------
both = lua.table_from([lfr, guild])
kept = RaidSession.NightsOnly(both)

check("NightsOnly keeps one of the two", len(list(kept.values())) == 1)

check("and nothing at all survives an empty list",
      len(list(RaidSession.NightsOnly(lua.table_from([])).values())) == 0)

# --- which session a drop belongs to --------------------------------------
#
# Aimee, 2026-08-20: "why is LFR being counted? its not 80% + guild members so
# it doesnt matter in the fairness log." The drop side of that answer needs to
# know which session a drop came from, and the obvious test — does its
# timestamp fall between startedAt and endedAt — is the one her own data
# breaks. Her LFR session is recorded as ending at 17:32 and six of that run's
# drops are stamped after it, because endedAt is written when the client
# notices the raid finish and it does not always get the chance.
#
# So it is the last session that had STARTED, which is right for both.

lfr.startedAt = 1000
lfr.endedAt = 1600            # closed early, as hers did
guild.startedAt = 7000
guild.endedAt = 17000

sessions = lua.table_from([lfr, guild])


def session_at(at):
    found = RaidSession.SessionAt(sessions, at)
    return found and found.startedAt or None


checks = [
    ("a drop inside the LFR window belongs to it", session_at(1200) == 1000),
    # The case a startedAt..endedAt test gets wrong, and the reason for this
    # rule rather than that one.
    ("A DROP AFTER THE LFR SESSION CLOSED STILL BELONGS TO IT",
     session_at(2500) == 1000),
    ("a drop after the guild raid started belongs to that",
     session_at(9000) == 7000),
    ("a drop before any session belongs to none", session_at(10) is None),
    # lootListID and boss ids repeat, and so does everything else about a
    # raid. Twelve hours is the fence.
    ("a drop a day later belongs to none",
     session_at(7000 + 25 * 3600) is None),
]

for label, ok in checks:
    check(label, ok)

# --- and therefore which drops the fairness math counts -------------------
#
# The whole point. Everything above is machinery; this is the number she
# reported. IsGuildNightAt reads the active season, so the season is stubbed
# around the two sessions above.

lua.execute("ShowUsYourLoot.GetActiveRaids = function() return SESSIONS end")
lua.globals().SESSIONS = sessions

drop_checks = [
    ("a win on the LFR run is not on a guild night",
     RaidSession.IsGuildNightAt(1200) is False),
    ("nor is one stamped after that session closed",
     RaidSession.IsGuildNightAt(2500) is False),
    ("a win on the guild raid is", RaidSession.IsGuildNightAt(9000) is True),
    # Unknown counts, the same rule as everywhere else here: a drop older than
    # any recorded session is not evidence of a pug, and removing it would
    # erase history that was captured before sessions existed.
    ("a win older than every session counts",
     RaidSession.IsGuildNightAt(10) is True),
    ("and so does one with no timestamp at all",
     RaidSession.IsGuildNightAt(None) is True),
]

for label, ok in drop_checks:
    check(label, ok)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
