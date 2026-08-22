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

# --- a night is an evening, not an instance -------------------------------
#
# Aimee, on finding three guild nights where she had raided twice: "that has
# only happened on this past tuesday and this past thursday. 2 total."
#
# On the Thursday her guild cleared two different raids in one evening —
# instance 2987 and instance 3004 — and the night key used to carry the
# instance id, so that evening counted as two nights. Everyone present got an
# extra night in the divisor and their share fell for turning up, which is the
# same fault the key was written to fix one level further out.

lua.execute(
    """
    -- NightKey falls back to formatting startedAt when a session has no
    -- dateText, which only old records do. Stubbed rather than skipped: the
    -- fallback is the branch that would go unnoticed if it broke.
    date = date or function(_, at) return 'from-' .. tostring(at) end

    function Night(instanceID, dateText)
        return { instanceID = instanceID, dateText = dateText,
                 startedAt = 1000, instanceType = 'raid', difficultyID = 14 }
    end
    """
)

Night = lua.globals().Night

check("two raids in one evening are one night",
      RaidSession.NightKey(Night(2987, "2026-08-20"))
      == RaidSession.NightKey(Night(3004, "2026-08-20")))

check("the same raid on two evenings is two nights",
      RaidSession.NightKey(Night(3004, "2026-08-20"))
      != RaidSession.NightKey(Night(3004, "2026-08-22")))

check("a session with no date still keys off something",
      RaidSession.NightKey(
          lua.eval("{ instanceID = 1, startedAt = 1755000000 }")) is not None)

check("and nothing at all keys off nothing", RaidSession.NightKey(None) is None)

# --- attendance counts guild nights, and only those -----------------------
#
# The Roster window's NIGHTS column and the board's divisor come from two
# different functions, and they disagreed: BuildAttendance filtered with
# RaidsOnly, which keeps anything that is not a dungeon, so an LFR run and a
# thirty-person pug were adding nights and putting strangers on the roster.
# The board counted through NightsOnly and did not.

lua.execute(
    """
    ShowUsYourLoot.Players = {
        ResolveToMain = function(key) return key end,
        Get = function() return nil end,
    }

    -- Her real shape: a guild Tuesday, a guild Thursday spread over two
    -- instances, an LFR run on the Tuesday, and a pug on the Friday.
    -- Arcangila is guilded in every session, because she always is. Without
    -- that GuildDataIsTrustworthy reads the whole session as unknown and it
    -- counts — which is the right rule, and would hide what is under test.
    local function Roster(guilded, strangers)
        local out = { Arcangila = {
            guid = 'Arcangila', name = 'Arcangila', guildRank = 'Master',
        } }

        for _, name in ipairs(guilded or {}) do
            out[name] = { guid = name, name = name, guildRank = 'Good Kitty' }
        end

        for _, name in ipairs(strangers or {}) do
            out[name] = { guid = name, name = name }
        end

        return out
    end

    local GUILD = { 'Camcar', 'Hinokamii' }
    local MANY = { 'S1','S2','S3','S4','S5','S6','S7','S8','S9','S10' }

    ATTEND_SESSIONS = {
        -- Tuesday: the guild raid.
        { dateText = '2026-08-18', instanceID = 3004, instanceType = 'raid',
          difficultyID = 14, startedAt = 1,
          roster = Roster(GUILD), recordedBy = 'Arcangila' },

        -- Tuesday: an LFR run she also did, one guildie among eleven.
        { dateText = '2026-08-18', instanceID = 3004, instanceType = 'raid',
          difficultyID = 17, startedAt = 2,
          roster = Roster(nil, MANY), recordedBy = 'Arcangila' },

        -- Thursday: one evening across two different raids.
        { dateText = '2026-08-20', instanceID = 2987, instanceType = 'raid',
          difficultyID = 14, startedAt = 3,
          roster = Roster(GUILD), recordedBy = 'Arcangila' },

        { dateText = '2026-08-20', instanceID = 3004, instanceType = 'raid',
          difficultyID = 15, startedAt = 4,
          roster = Roster(GUILD), recordedBy = 'Arcangila' },

        -- Friday: a pug.
        { dateText = '2026-08-22', instanceID = 3004, instanceType = 'raid',
          difficultyID = 14, startedAt = 5,
          roster = Roster(nil, MANY), recordedBy = 'Arcangila' },
    }
    """
)

# Two returns: the ordered list, and the same entries keyed for lookup.
attendance, _by_key = RaidSession.BuildAttendance(lua.globals().ATTEND_SESSIONS)
by_name = {}

for i in range(1, len(attendance) + 1):
    by_name[attendance[i].name] = attendance[i].nights

check("THE TWO GUILD NIGHTS ARE TWO, NOT FOUR",
      by_name.get("Camcar") == 2, by_name.get("Camcar"))

check("the Thursday's two instances counted once",
      by_name.get("Arcangila") == 2, by_name.get("Arcangila"))

check("nobody from the LFR run is on the list",
      "S1" not in by_name, sorted(by_name))

check("nor anybody from the pug", "S10" not in by_name, sorted(by_name))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
