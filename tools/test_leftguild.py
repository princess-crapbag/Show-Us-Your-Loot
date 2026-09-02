"""A raider who leaves the guild can still be taken off the raid team.

THE BUG THIS WAS WRITTEN FOR, in Aimee's words: "razor left guild and he still
shows there. i cant seem to remove him from the active raid team."

She could not, and neither could any screen in the addon. Team membership is
kept on the player registry -- account level, outliving seasons and guilds,
which Core/RaidTeam.lua does on purpose. The roster was built from the LIVE
GUILD LIST alone. So a raider who left the guild kept the flag and lost the
only row that could clear it: permanently on the Raiders board, absent from
every roster, with the roster window printing

    0 on the raid team  ·  2 marked as raiding

and neither number wrong. A state the addon could enter and could not leave.

The fixture below is her situation exactly: two characters ticked onto the
team, neither of them in the guild.

Needs `lupa` -- see tools/test_lootmessages.py for the setup.

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


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    ShowUsYourLootDB.players = {
        -- In the guild and on the team. The ordinary case, here so the
        -- assertions below are about who is EXTRA rather than about the list
        -- being empty.
        STAY = {
            guid = 'STAY', name = 'Stayer', fullName = 'Stayer-Area52',
            class = 'PRIEST', inRaidTeam = true,
        },
        -- Left the guild, still ticked. Razor.
        LEFT = {
            guid = 'LEFT', name = 'Lefter', fullName = 'Lefter-Thrall',
            class = 'WARRIOR', inRaidTeam = true,
        },
        -- Left the guild and was never on the team. Must NOT be dragged in --
        -- the registry holds every character the addon has ever seen, and
        -- appending all of them would put several hundred strangers on a
        -- roster that is meant to be who you could bring.
        STRANGER = {
            guid = 'STRANGER', name = 'Stranger', fullName = 'Stranger-Illidan',
            class = 'ROGUE',
        },
    }

    local members = ShowUsYourLoot.Guild.GetMembers()

    for key in pairs(members) do
        members[key] = nil
    end

    members.STAY = {
        guid = 'STAY', shortName = 'Stayer', fullName = 'Stayer-Area52',
        rank = 'Good Kitty', rankIndex = 3, class = 'PRIEST',
    }

    -- A guildie on no team, so "in the guild" and "on the team" are not the
    -- same set and the append cannot pass by accident.
    members.OTHER = {
        guid = 'OTHER', shortName = 'Otherton', fullName = 'Otherton-Area52',
        rank = 'Stray', rankIndex = 6, class = 'MAGE',
    }

    function GuildLoaded() return true end

    function RosterNames()
        ShowUsYourLoot.RosterData.Invalidate()

        local names = {}

        for _, entry in ipairs(ShowUsYourLoot.RosterData.Build()) do
            names[entry.name] = entry
        end

        return names
    end

    function TeamNames()
        ShowUsYourLoot.RosterData.Invalidate()

        local kept = ShowUsYourLoot.RaidTeam.Filter(
            ShowUsYourLoot.RosterData.Build()
        )

        local names = {}

        for _, entry in ipairs(kept) do
            names[entry.name] = entry
        end

        return names
    end
    """
)

g = lua.globals()
roster = g.RosterNames()
team = g.TeamNames()


def listed(names):
    return sorted(str(k) for k in names.keys())


# --- the bug --------------------------------------------------------------
check(
    "a raider who left the guild is still on the roster",
    roster["Lefter"] is not None,
    listed(roster),
)

# The one that matters. The TEAM column acts on this list, so a name absent
# from it cannot be unticked by any screen in the addon.
check(
    "and is reachable through the raid team filter, which is where you untick",
    team["Lefter"] is not None,
    listed(team),
)

check(
    "the guildie on the team is still there beside them",
    team["Stayer"] is not None,
    listed(team),
)

check(
    "and the team filter holds nobody else",
    listed(team) == ["Lefter", "Stayer"],
    listed(team),
)

# --- and what must NOT come with them -------------------------------------
#
# The registry is every character the addon has ever recorded -- 699 of them in
# Aimee's, most of them pugs. The append is keyed on the team flag, and if it
# ever stops being, this roster becomes a list of strangers.
check(
    "a stranger who was never on the team is not dragged in",
    roster["Stranger"] is None,
    listed(roster),
)

check(
    "the guild's own members are untouched",
    roster["Otherton"] is not None and roster["Stayer"] is not None,
    listed(roster),
)

# --- the row says why it is there -----------------------------------------
#
# A name with a tick and no explanation, sorted above the guildies, reads as a
# bug rather than as somebody you are about to tidy up.
lefter = roster["Lefter"]

check(
    "the row is marked as no longer in the guild",
    lefter["isFormer"] is True,
    lefter["isFormer"],
)
check(
    "and its guild rank column says so rather than going blank",
    str(lefter["rank"]) == "Not in guild",
    lefter["rank"],
)

# Below the recruits at 98, so the people most likely to be tidied sort to the
# very bottom rather than into the middle of the real ranks.
check(
    "and it sorts below every real rank and below recruits",
    lefter["rankIndex"] == 99,
    lefter["rankIndex"],
)

# --- unticking now works, and is the whole point --------------------------
lua.execute(
    """
    ShowUsYourLoot.RaidTeam.SetMember('LEFT', false)
    ShowUsYourLoot.RosterData.Invalidate()
    """
)

after = g.TeamNames()

check(
    "unticking them takes them off the team",
    SYL.RaidTeam.IsMember("LEFT") is False,
)
check(
    "and off the board's audience",
    SYL.Audience.Includes("team", "LEFT", "LEFT", "Lefter") is False,
)
check(
    "and off the roster, having no reason left to be on it",
    after["Lefter"] is None,
    listed(after),
)

# --- the loading guard ----------------------------------------------------
#
# GetMembers is empty for the first seconds after login. Without the guard
# every raider on the team is listed as having left the guild, in the one
# moment the window is most likely to be opened.
lua.execute(
    """
    ShowUsYourLoot.RaidTeam.SetMember('LEFT', true)

    local members = ShowUsYourLoot.Guild.GetMembers()

    for key in pairs(members) do
        members[key] = nil
    end

    -- In a guild, roster not arrived. IsInGuild is stubbed false by the test
    -- client, so it is overridden here -- the guard only bites when the addon
    -- believes there IS a guild whose list has not come.
    ShowUsYourLoot.Guild.IsInGuild = function() return true end
    """
)

loading = g.RosterNames()

check(
    "nobody is called a leaver while the guild list is still loading",
    loading["Stayer"] is None and loading["Lefter"] is None,
    listed(loading),
)

lua.execute(
    """
    ShowUsYourLoot.Guild.IsInGuild = function() return false end
    """
)

nogulid = g.RosterNames()

# Not in a guild at all is a different thing from a guild that has not
# answered yet: there is no list coming, so the team is all there is to show.
check(
    "but a player in no guild still sees their own team",
    nogulid["Lefter"] is not None and nogulid["Stayer"] is not None,
    listed(nogulid),
)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
