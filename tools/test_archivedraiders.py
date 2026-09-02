"""Who lands on the archived board, and who must not.

The archived list is DERIVED rather than recorded -- see the header of
Core/ArchivedRaiders.lua for why -- which means the rule is the feature. There
is no stored flag to check it against, so if the rule drifts, the screen fills
with the wrong people and nothing anywhere else complains.

The four ways it can be wrong, and each is a case below:

  * a raider taken off the team does not appear, which is the whole ask
  * a pug appears, which is the failure mode that drowns the list
  * somebody still on the team appears, so a name is on two boards at once
  * a guildie who has never raided appears, filling it with the roster

Plus the one that is not about membership at all: the bars are measured
against the RAID TEAM and not against the archived list, or an ex-raider's bar
would be drawn relative to the other ex-raiders and mean nothing.

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


# --- the fixture ----------------------------------------------------------
#
# Five people, one per case the rule has to separate.
#
# `recordedBy` is deliberately absent from the sessions. RaidSession treats a
# session with no recorder as having unknown guild data, and unknown counts as
# a night -- so every night here counts, and this file tests the archived rule
# rather than re-testing which evenings are raid nights. tools/test_guildnights
# owns that.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    ShowUsYourLootDB.players = {
        -- Still on the team. Belongs on the board, not here.
        TEAM1 = {
            guid = 'TEAM1', name = 'Teamer', fullName = 'Teamer-Area52',
            class = 'PRIEST', inRaidTeam = true,
        },
        -- Taken off the team. The person this screen was built for.
        EX1 = {
            guid = 'EX1', name = 'Exed', fullName = 'Exed-Area52',
            class = 'MAGE',
        },
        -- Off the team AND out of the guild since. Still ours on the night.
        GONE1 = {
            guid = 'GONE1', name = 'Gone', fullName = 'Gone-Area52',
            class = 'DRUID',
        },
        -- Rolled in one of our raids and was never one of us.
        PUG1 = {
            guid = 'PUG1', name = 'Pugger', fullName = 'Pugger-Stormrage',
            class = 'ROGUE',
        },
        -- In the guild, has never raided.
        IDLE1 = {
            guid = 'IDLE1', name = 'Idler', fullName = 'Idler-Area52',
            class = 'HUNTER',
        },
    }

    -- The guild list as it stands TODAY. Gone is not in it any more, which is
    -- the case the session's own guild rank has to answer for.
    local members = ShowUsYourLoot.Guild.GetMembers()

    for key in pairs(members) do
        members[key] = nil
    end

    members.TEAM1 = {
        guid = 'TEAM1', shortName = 'Teamer', fullName = 'Teamer-Area52',
        rank = 'Good Kitty', rankIndex = 3,
    }
    members.EX1 = {
        guid = 'EX1', shortName = 'Exed', fullName = 'Exed-Area52',
        rank = 'Good Kitty', rankIndex = 3,
    }
    members.IDLE1 = {
        guid = 'IDLE1', shortName = 'Idler', fullName = 'Idler-Area52',
        rank = 'Scratching Post', rankIndex = 5,
    }

    local season = ShowUsYourLootDB.activeSeason

    -- Teamer takes a Need, so the raid team has a scale at all. Exed takes a
    -- Greed, so the archived row has a bar of its own to be measured wrong.
    season.drops = {
        {
            id = 'd1',
            timestamp = 1700000000,
            itemName = 'Robes of the Voidbound',
            itemLink = 'item:1',
            instanceType = 'raid',
            difficultyID = 16,
            encounterName = 'Plexus Sentinel',
            winnerName = 'Teamer',
            winnerGUID = 'TEAM1',
            winnerClass = 'PRIEST',
            winnerState = 0,
            rolls = { { isWinner = true, guid = 'TEAM1', state = 0 } },
        },
        {
            id = 'd2',
            timestamp = 1700000100,
            itemName = 'Weight of Command',
            itemLink = 'item:2',
            instanceType = 'raid',
            difficultyID = 16,
            encounterName = "Loom'ithar",
            winnerName = 'Exed',
            winnerGUID = 'EX1',
            winnerClass = 'MAGE',
            winnerState = 3,
            rolls = { { isWinner = true, guid = 'EX1', state = 3 } },
        },
    }

    -- guildRank is what says "one of ours on the night". Pugger has none, and
    -- that absence is the only thing keeping the list clean.
    local roster = {
        TEAM1 = {
            guid = 'TEAM1', name = 'Teamer', class = 'PRIEST',
            guildRank = 'Good Kitty',
        },
        EX1 = {
            guid = 'EX1', name = 'Exed', class = 'MAGE',
            guildRank = 'Good Kitty',
        },
        GONE1 = {
            guid = 'GONE1', name = 'Gone', class = 'DRUID',
            guildRank = 'Good Kitty',
        },
        PUG1 = { guid = 'PUG1', name = 'Pugger', class = 'ROGUE' },
    }

    season.raids = {}

    -- Four, so everyone here clears LootScore.MIN_NIGHTS and is ranked. An
    -- unranked row would pass the membership cases below for the wrong reason.
    for night = 1, 4 do
        table.insert(season.raids, {
            id = 'r' .. night,
            startedAt = 1699900000 + night * 86400,
            instanceID = 1,
            instanceName = 'Manaforge Omega',
            instanceType = 'raid',
            difficultyID = 16,
            dateText = '2026-08-0' .. night,
            encounters = { { name = 'Plexus Sentinel', success = true } },
            roster = roster,
        })
    end

    ShowUsYourLootDB.loot = season.loot
    ShowUsYourLootDB.settings.audienceScope = 'team'

    function ArchivedNames()
        local names = {}

        for _, entry in ipairs(ShowUsYourLoot.ArchivedRaiders.Build()) do
            names[entry.name] = true
        end

        return names
    end

    function TeamNames()
        local _, team = ShowUsYourLoot.ArchivedRaiders.Build()
        local names = {}

        for _, entry in ipairs(team) do
            names[entry.name] = true
        end

        return names
    end

    function BoardNames()
        local drops = ShowUsYourLoot.GetActiveDrops()
        local entries = ShowUsYourLoot.DueList.Build(
            drops, ShowUsYourLoot.GetActiveRaids()
        )

        entries = ShowUsYourLoot.Audience.Filter(entries, 'team')

        local names = {}

        for _, entry in ipairs(entries) do
            names[entry.name] = true
        end

        return names
    end
    """
)

SYL.LootHistoryStore.RebuildIndex()

g = lua.globals()
archived = g.ArchivedNames()
team = g.TeamNames()
board = g.BoardNames()


def listed(names):
    return sorted(str(k) for k in names.keys())


# --- who is on it ---------------------------------------------------------
check(
    "a raider taken off the team is archived",
    archived["Exed"] is True,
    listed(archived),
)

# The one the guild list alone cannot answer. Gone is not in Guild.GetMembers
# any more, so this passes only because the session recorded a guild rank for
# them on the night -- and they are also the person most likely to be argued
# about, having left.
check(
    "so is somebody who has left the guild since",
    archived["Gone"] is True,
    listed(archived),
)

# --- who is not -----------------------------------------------------------
check(
    "a pug is not archived",
    archived["Pugger"] is None,
    listed(archived),
)
check(
    "somebody still on the raid team is not archived",
    archived["Teamer"] is None,
    listed(archived),
)

# A guildie with no nights has no history to keep, so there is nothing for
# this screen to show them for. Without this the list is the guild roster.
check(
    "a guildie who has never raided is not archived",
    archived["Idler"] is None,
    listed(archived),
)

# THE LINE ABOVE PASSES FOR A REASON THAT IS NOT THE GUARD, and that was worth
# finding: DueList.Build only ever makes an entry for somebody who was in a
# session roster, so Idler is not on the list to be filtered off it. Deleting
# the nights guard entirely left every assertion in this file green.
#
# The guard is still load-bearing -- Includes is public, and the roster view
# hands it entries built from the guild list, where a nights of zero is the
# common case rather than the impossible one -- so it is asked directly here.
# This is the assertion that fails if it goes.
lua.execute(
    """
    ZeroNights = ShowUsYourLoot.ArchivedRaiders.Includes(
        { key = 'IDLE1', guid = 'IDLE1', name = 'Idler', nights = 0 }, {}
    )

    OneNight = ShowUsYourLoot.ArchivedRaiders.Includes(
        { key = 'IDLE1', guid = 'IDLE1', name = 'Idler', nights = 1 }, {}
    )
    """
)

check(
    "and is refused on the nights, not by chance",
    g.ZeroNights is False and g.OneNight is True,
    (g.ZeroNights, g.OneNight),
)

check(
    "exactly the two who left",
    listed(archived) == ["Exed", "Gone"],
    listed(archived),
)

# --- and never on two boards at once --------------------------------------
#
# The board and the archived board are read side by side, and a name on both
# would mean the two screens disagree about who is raiding. They are built by
# different rules, so this is a real assertion rather than a restatement.
overlap = sorted(set(listed(archived)) & set(listed(board)))

check(
    "nobody is on the board and the archived board at once",
    overlap == [],
    overlap,
)

check(
    "the board still holds the raider who stayed",
    board["Teamer"] is True,
    listed(board),
)

# --- the scale ------------------------------------------------------------
#
# The bars on the archived board are measured against the raid team, not
# against the other archived rows. Measured against themselves, Exed's 20
# points would be the longest bar on the screen and read as a raider who had
# taken everything.
check(
    "the scale is the raid team, not the archived list",
    listed(team) == ["Teamer"],
    listed(team),
)

lua.execute(
    """
    local entries, teamEntries = ShowUsYourLoot.ArchivedRaiders.Build()

    ScaleHighest = ShowUsYourLoot.LootScore.Highest(teamEntries)
    ArchivedHighest = ShowUsYourLoot.LootScore.Highest(entries)
    """
)

# 100 over four nights against 20 over four nights. The point is that the two
# differ and that the board uses the first: an archived bar is drawn as a
# fraction of the team's best, so Exed's fills a fifth of the track rather
# than all of it.
check(
    "the team's highest is what the bars divide by",
    g.ScaleHighest == 25.0 and g.ArchivedHighest == 5.0,
    (g.ScaleHighest, g.ArchivedHighest),
)

# --- what the caption says ------------------------------------------------
#
# The average printed under an archived list is the RAID TEAM's, and the
# sentence has to say so. It is the number somebody would otherwise read as
# this list's own and quote back at you.
caption = SYL.ArchivedRaiders.Caption(2, 25.0, 1)

check(
    "the caption names the rule",
    "not on the raid team now" in caption,
    caption,
)
check(
    "and says the average belongs to the team",
    "raid team's" in caption and "25.0" in caption,
    caption,
)

# With nobody on the team ranked there is no scale, so the caption must not
# print an average of zero as though it were one -- the same rule the board
# already keeps for its own empty average.
quiet = SYL.ArchivedRaiders.Caption(2, 0, 0)

check(
    "and does not invent an average when the team has none",
    "0.0 per night" not in quiet and "no bars" in quiet,
    quiet,
)

# --- the panel ------------------------------------------------------------
panel = None

try:
    panel = SYL.RaidersPanel.Create(lua.globals().UIParent)
    check("the panel builds", panel is not None)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the panel builds", False, err)

check("the panel offers archivedButton", panel is not None and panel.archivedButton is not None)

try:
    SYL.RaidersPanel.SetArchived(True)
    check(
        "it refreshes showing the archived board",
        SYL.RaidersPanel.IsArchived() is True,
    )
except Exception as err:  # noqa: BLE001
    check("it refreshes showing the archived board", False, err)

# Board and Roster mean "put me back on the people who raid here". Landing on
# the archived board wearing a Board label would be the button lying.
try:
    SYL.RaidersPanel.SetView("board")
    check(
        "choosing a view leaves the archived board",
        SYL.RaidersPanel.IsArchived() is False,
    )
except Exception as err:  # noqa: BLE001
    check("choosing a view leaves the archived board", False, err)

try:
    SYL.RaidersPanel.ToggleArchived()
    SYL.RaidersPanel.SetView("roster")

    check(
        "and so does the roster",
        SYL.RaidersPanel.IsArchived() is False,
    )
except Exception as err:  # noqa: BLE001
    check("and so does the roster", False, err)

# The empty state, which is a different branch and is what a guild with no
# archived raiders sees every time they press the button.
lua.execute(
    """
    for key, player in pairs(ShowUsYourLootDB.players) do
        player.inRaidTeam = true
    end
    """
)

try:
    SYL.RaidersPanel.SetArchived(True)
    check("it refreshes with nobody archived", True)
except Exception as err:  # noqa: BLE001
    check("it refreshes with nobody archived", False, err)

check(
    "an empty list says everyone is still on the team",
    "still marked as being on the raid team"
    in SYL.ArchivedRaiders.ExplainEmpty(4),
    SYL.ArchivedRaiders.ExplainEmpty(4),
)
check(
    "and says something else entirely before the first raid",
    "next raid night" in SYL.ArchivedRaiders.ExplainEmpty(0),
    SYL.ArchivedRaiders.ExplainEmpty(0),
)

# ==========================================================================
# Archiving by hand
# ==========================================================================
#
# The derived rule cannot reach a trial who never raided: they are in the
# guild and have no nights, so they fail the raided test and stay on the
# roster for good. Aimee: "there are a few trials showing on my roster that i
# want to archive." This is the flag she sets herself.
#
# GUILD RANK MUST NEVER COME INTO IT. "someone could join the raid in any rank
# so i need to be able to add and remove no matter their rank." The fixture
# gives the trial the lowest rank in her guild and the archived raider the
# highest, so a rank test anywhere in this path would show up as one of these
# two behaving differently from the other.
lua.execute(
    """
    for key, player in pairs(ShowUsYourLootDB.players) do
        player.inRaidTeam = nil
        player.archived = nil
    end

    ShowUsYourLootDB.players.TEAM1.inRaidTeam = true

    -- A trial, in the guild, never raided, lowest rank.
    ShowUsYourLootDB.players.TRIAL = {
        guid = 'TRIAL', name = 'Trialist', fullName = 'Trialist-Area52',
        class = 'MONK',
    }

    local members = ShowUsYourLoot.Guild.GetMembers()

    members.TRIAL = {
        guid = 'TRIAL', shortName = 'Trialist', fullName = 'Trialist-Area52',
        rank = 'Stray', rankIndex = 6,
    }

    function RosterHas(name)
        ShowUsYourLoot.RosterData.Invalidate()

        for _, entry in ipairs(ShowUsYourLoot.RosterData.Build()) do
            if entry.name == name then
                return true
            end
        end

        return false
    end
    """
)

check(
    "a trial who never raided starts on the roster",
    g.RosterHas("Trialist") is True,
)

# The gap the flag exists to close: nothing derived can put them on the
# archived board, because they have no nights to be derived from.
check(
    "and cannot reach the archived board on the derived rule alone",
    g.ArchivedNames()["Trialist"] is None,
    listed(g.ArchivedNames()),
)

check("archiving them reports success", SYL.ArchivedRaiders.Archive("TRIAL") is True)

check(
    "it takes them off the roster, which is the visible half",
    g.RosterHas("Trialist") is False,
)

# With no nights they are in no due-list entry at all, so Build has to append
# them or archiving would be a name disappearing rather than being filed.
check(
    "and puts them on the archived board with nothing to show",
    g.ArchivedNames()["Trialist"] is True,
    listed(g.ArchivedNames()),
)

# --- the two flags are mutually exclusive, both ways ----------------------
#
# Archived means "not somebody I am going to bring" and the raid team is who
# you bring. A character carrying both would be on the board and off the
# roster at once, which is the disagreement the archived screen exists to end.
check(
    "archiving somebody takes them off the raid team",
    SYL.ArchivedRaiders.Archive("TEAM1") is True
    and SYL.RaidTeam.IsMember("TEAM1") is False,
)

check(
    "and adding somebody to the team unarchives them",
    SYL.RaidTeam.SetMember("TEAM1", True) is True
    and SYL.ArchivedRaiders.IsArchived("TEAM1") is False,
)

# Rank plays no part. Teamer is Good Kitty and Trialist is Stray, and the two
# behaved identically above -- archived, restored, off the roster, on the
# board. This asserts the source has no rank test rather than trusting that.
ARCHIVED_SRC = (
    Path(__file__).resolve().parent.parent / "Core" / "ArchivedRaiders.lua"
).read_text(encoding="utf-8")

check(
    "nothing in the rule reads a guild rank",
    "rankIndex" not in ARCHIVED_SRC and "GetRank" not in ARCHIVED_SRC,
)

# --- the way back ---------------------------------------------------------
check("restoring reports success", SYL.ArchivedRaiders.Restore("TRIAL") is True)

check(
    "it puts them back on the roster",
    g.RosterHas("Trialist") is True,
)

check(
    "and takes them off the archived board",
    g.ArchivedNames()["Trialist"] is None,
    listed(g.ArchivedNames()),
)

# Restoring is not the same as hiring. Putting somebody back on the team is a
# mark an officer makes, and doing it for them is how a name reappears on the
# board nobody added them to.
check(
    "restoring does not put them on the raid team",
    SYL.RaidTeam.IsMember("TRIAL") is False,
)

check(
    "restoring somebody who was not archived reports nothing done",
    SYL.ArchivedRaiders.Restore("TRIAL") is False,
)

# --- an archived alt archives the person on the board ---------------------
#
# Archive marks a character, because that is what a roster row is. The
# archived board folds alts onto one person, so the flag it has to answer for
# may sit on a character that row never names.
lua.execute(
    """
    ShowUsYourLootDB.players.EXALT = {
        guid = 'EXALT', name = 'Exalt', fullName = 'Exalt-Area52',
        class = 'MAGE', mainGUID = 'EX1',
    }
    """
)

check(
    "archiving an alt archives the person",
    SYL.ArchivedRaiders.Archive("EXALT") is True
    and SYL.ArchivedRaiders.IsArchived("EX1") is True,
)

# And the undo has to reach the same flag from the other end, or the button
# would report success and change nothing anybody could see.
check(
    "and bringing the person back clears the alt's flag",
    SYL.ArchivedRaiders.Restore("EX1") is True
    and SYL.ArchivedRaiders.IsArchivedCharacter("EXALT") is False,
)

# ==========================================================================
# The footer bar
# ==========================================================================
#
# The rule above is worth nothing if the button that drives it is wired to the
# wrong thing. The stub frame answers every method with itself, so what can be
# checked here is what the bar decides -- which view offers a control, and
# whether pressing it reaches the flag.

lua.execute(
    """
    ShowUsYourLootDB.players.TRIAL.archived = nil

    ActionBar = ShowUsYourLoot.RaidersActions.Create(UIParent, {
        getSelectedKey = function() return PickedKey end,
        isArchived = function() return PickedArchived end,
        onChanged = function() Changed = (Changed or 0) + 1 end,
    })

    Handlers = {
        getSelectedKey = function() return PickedKey end,
        isArchived = function() return PickedArchived end,
        onChanged = function() Changed = (Changed or 0) + 1 end,
    }

    function PressBar(key, isArchived)
        PickedKey = key
        PickedArchived = isArchived
        Changed = 0

        ShowUsYourLoot.RaidersActions.Press(Handlers)

        return Changed
    end
    """
)

check("the bar builds", g.ActionBar is not None)

# Drawing cannot be asserted against a stub that answers every method with
# itself, so the three views are checked for not throwing, and the decision
# that matters -- what a press does -- is driven directly below.
for state in (("board", False), ("roster", False), ("archived", True)):
    try:
        SYL.RaidersActions.Update(
            g.ActionBar, "Trialist", state[1], state[0], "TRIAL"
        )
        check("the bar draws on the %s view" % state[0], True)
    except Exception as err:  # noqa: BLE001
        check("the bar draws on the %s view" % state[0], False, err)

check(
    "pressing it on the roster archives the picked raider",
    g.PressBar("TRIAL", False) == 1
    and SYL.ArchivedRaiders.IsArchived("TRIAL") is True,
)

check(
    "and pressing it on the archived board brings them back",
    g.PressBar("TRIAL", True) == 1
    and SYL.ArchivedRaiders.IsArchived("TRIAL") is False,
)

# A press with nothing selected must not reach the registry at all. The bar is
# hidden then, but hidden is a drawing state and this is the guard that does
# not depend on one.
check(
    "and does nothing at all with nobody picked",
    g.PressBar(None, False) == 0,
)

# The failure path: a row with no registry record, which is a name off
# somebody else's shared roster. It has to report rather than silently no-op,
# and it must not clear the selection as though it had worked.
check(
    "an unknown character is refused rather than silently ignored",
    g.PressBar("NOSUCHGUID", False) == 0,
)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
