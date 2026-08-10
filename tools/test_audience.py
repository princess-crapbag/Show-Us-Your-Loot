"""The audience scope, run against the shipped Audience, Filters and RaidSummary.

Aimee's rule, in her words: everything except the keys screen should focus on
raid team, then guild, then pugs. Core/Audience.lua has expressed that since it
was written; what this covers is the surfaces that were not asking it.

Three of them, and each failed differently:

  * The Readiness tile called RaidTeam.Filter directly, so it was the one
    people-list in the addon that could not widen. With nobody ticked it drew
    an empty state while every neighbouring tile fell through to the guild.
    RaidTeam.Filter also tests entry.key alone, so an officer who ticked the
    alt somebody actually raids on had that person fail their own team test.
    Covered here as ALT_CASES.

  * The end of night summary counted everybody present who went home empty,
    then pointed at /syl due, which is scoped. The summary said nine and the
    ranked list showed three. Covered as SUMMARY_CASES.

  * The player filter dropdown was plain alphabetical, so a pug sat above the
    raiders. Covered as ORDER_CASES — and note it asserts nothing is dropped,
    because ordering rather than filtering is the deliberate call there. The
    loot list is a record of drops, so a pug's win is a row already on screen;
    removing the name would leave a visible row no filter could reach.

Audience.lua, Filters.lua and RaidSummary.lua are loaded for real. The
registry, the roster and the guild are stubbed — they are someone else's
behaviour, and stubbing them is what lets a fixture put one person's alt on the
team and nothing else.

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

CORE = Path(__file__).resolve().parent.parent / "Core"

lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute("ShowUsYourLoot = {}")
lua.execute("ShowUsYourLootDB = { settings = {} }")

# Only what LootHistoryAPI needs to load; the binding rules are tested by
# test_duelist and are not what this file is about.
lua.execute(
    """
    C_Item = {
        GetItemInfo = function(link)
            return 'name', link, 4, 600, 80, '', '', 1, '', '', 0, 4, 1, 1
        end,
    }
    """
)

for module in ("Utilities.lua", "LootHistoryAPI.lua"):
    lua.execute((CORE / module).read_text(encoding="utf-8"))

# The three stubs. TEAM, GUILD and ALTS are globals so a case can rewrite the
# world between assertions rather than reloading the module under test.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    TEAM, GUILD, ALTS, IN_GUILD = {}, {}, {}, true

    SYL.RaidTeam = {
        IsMember = function(key)
            return (key ~= nil and TEAM[key]) and true or false
        end,

        Count = function()
            local total = 0

            for _ in pairs(TEAM) do
                total = total + 1
            end

            return total
        end,
    }

    SYL.Guild = {
        IsInGuild = function() return IN_GUILD end,

        -- Mirrors the real one's shape: resolve through whichever identity the
        -- caller happened to hold, and answer nil for a stranger.
        GetMemberForPlayer = function(key, guid, name)
            if key ~= nil and GUILD[key] then return { name = key } end
            if guid ~= nil and GUILD[guid] then return { name = guid } end
            if name ~= nil and GUILD[name] then return { name = name } end

            return nil
        end,
    }

    SYL.Players = {
        GetAlts = function(key) return ALTS[key] or {} end,
        Get = function() return nil end,
    }
    """
)

lua.execute((CORE / "Audience.lua").read_text(encoding="utf-8"))
lua.execute((CORE / "Filters.lua").read_text(encoding="utf-8"))

# RaidSummary asks the session for its own shape. Kills and duration are
# RaidSession's job and are stubbed flat; only the roster arithmetic is under
# test here.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    SYL.RaidSession = {
        GetKillCount = function() return 2 end,
        GetDurationMinutes = function() return 125 end,
    }

    DROPS = {}

    SYL.GetAllDrops = function() return DROPS end
    """
)

lua.execute((CORE / "RaidSummary.lua").read_text(encoding="utf-8"))

lua.execute(
    """
    local SYL = ShowUsYourLoot

    -- Four people in the raid. Aimee and Borg are on the team, Dravok is in
    -- the guild but not on it, Zugzug is a pug. Aimee wins the only upgrade,
    -- so the empty-handed count differs at every scope: 1, 2 and 3.
    function ResetWorld()
        TEAM, GUILD, ALTS, IN_GUILD = {}, {}, {}, true

        TEAM['Aimee'], TEAM['Borg'] = true, true
        GUILD['Aimee'], GUILD['Borg'], GUILD['Dravok'] = true, true, true

        ShowUsYourLootDB.settings = {}
    end

    function SetScope(scope)
        ShowUsYourLootDB.settings.audienceScope = scope
    end

    function ScopedFilter(scope, names)
        local entries = {}

        for _, name in ipairs(names) do
            table.insert(entries, { key = name, guid = name, name = name })
        end

        local kept = SYL.Audience.Filter(entries, scope)
        local out = {}

        for _, entry in ipairs(kept) do
            table.insert(out, entry.name)
        end

        return table.concat(out, ',')
    end

    -- The dropdown's own call path: records in, ordered option list out.
    function PlayerOptions(names)
        local records = {}

        for _, name in ipairs(names) do
            table.insert(records, { winnerName = name, itemName = 'z' .. name })
        end

        local fields = {
            player = function(record) return record.winnerName end,
            item = function(record) return record.itemName end,
        }

        return table.concat(
            SYL.Filters.DeriveOptions(records, fields, 'player'), ','
        )
    end

    function ItemOptions(names)
        local records = {}

        for _, name in ipairs(names) do
            table.insert(records, { winnerName = name, itemName = name })
        end

        local fields = {
            player = function(record) return record.winnerName end,
            item = function(record) return record.itemName end,
        }

        return table.concat(
            SYL.Filters.DeriveOptions(records, fields, 'item'), ','
        )
    end

    function SummaryLine()
        local roster = {}

        for _, name in ipairs({ 'Aimee', 'Borg', 'Dravok', 'Zugzug' }) do
            roster[name] = { guid = name, name = name, fullName = name }
        end

        DROPS = {
            {
                timestamp = 50,
                winnerGUID = 'Aimee',
                winnerState =
                    SYL.LootHistoryAPI.ROLL_STATE.NeedMainSpec,
            },
        }

        local session = {
            startedAt = 0,
            endedAt = 100,
            rosterCount = 4,
            encounters = { {}, {}, {} },
            instanceName = 'Manaforge Omega',
            roster = roster,
        }

        local lines = SYL.RaidSummary.Build(session)

        for _, line in ipairs(lines) do
            if line:find('without an upgrade') then
                return line
            end
        end

        return ''
    end
    """
)

g = lua.globals()
failures = []


def check(label, got, want):
    ok = got == want
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        print(f"       got:    {got!r}")
        print(f"       wanted: {want!r}")
        failures.append(label)


# --------------------------------------------------------------------------
# The default falls through, narrowest scope that can still show somebody
# --------------------------------------------------------------------------

g.ResetWorld()
check("a marked team defaults to team", g.ShowUsYourLoot.Audience.Default(), "team")

g.ResetWorld()
lua.execute("TEAM = {}")
check(
    "no team but in a guild defaults to guild",
    g.ShowUsYourLoot.Audience.Default(),
    "guild",
)

g.ResetWorld()
lua.execute("TEAM = {}; IN_GUILD = false")
check(
    "no team and no guild defaults to everyone",
    g.ShowUsYourLoot.Audience.Default(),
    "everyone",
)

# --------------------------------------------------------------------------
# Filtering narrows, and never reorders
# --------------------------------------------------------------------------

EVERYONE = ["Aimee", "Borg", "Dravok", "Zugzug"]

FILTER_CASES = [
    ("team keeps only the ticked", "team", "Aimee,Borg"),
    ("guild keeps the guild, drops the pug", "guild", "Aimee,Borg,Dravok"),
    ("everyone keeps the pug too", "everyone", "Aimee,Borg,Dravok,Zugzug"),
]

for label, scope, want in FILTER_CASES:
    g.ResetWorld()
    check(label, g.ScopedFilter(scope, lua.table(*EVERYONE)), want)

# The case RaidTeam.Filter got wrong. Somebody whose main is not ticked but
# whose alt is raids on that alt, and must stay on the team's lists.
g.ResetWorld()
lua.execute("ALTS['Dravok'] = { { guid = 'DravokAlt' } }; TEAM['DravokAlt'] = true")
check(
    "an alt on the team puts the person on the team",
    g.ScopedFilter("team", lua.table("Aimee", "Dravok")),
    "Aimee,Dravok",
)

# --------------------------------------------------------------------------
# Subject — the noun after the count
# --------------------------------------------------------------------------

SUBJECT_CASES = [
    ("team", "on the team"),
    ("guild", "in your guild"),
    ("everyone", "recorded"),
]

for scope, want in SUBJECT_CASES:
    check(
        f"{scope} headline reads '{want}'",
        g.ShowUsYourLoot.Audience.Subject(scope),
        want,
    )

# --------------------------------------------------------------------------
# The player dropdown orders without dropping
# --------------------------------------------------------------------------

# Deliberately alphabetical-hostile: plain sort gives Aimee,Borg,Dravok,Zugzug
# and would pass the ordering assertion by accident. Renamed so the pug sorts
# first and a team member sorts last.
ORDER_NAMES = ["Aardvark", "Zena", "Mid"]

g.ResetWorld()
lua.execute(
    """
    TEAM, GUILD = {}, {}
    TEAM['Zena'] = true
    GUILD['Zena'], GUILD['Mid'] = true, true
    """
)

check(
    "player options put team first, then guild, then pugs",
    g.PlayerOptions(lua.table(*ORDER_NAMES)),
    "Zena,Mid,Aardvark",
)

check(
    "ordering drops nobody — the pug is last, not gone",
    len(g.PlayerOptions(lua.table(*ORDER_NAMES)).split(",")),
    3,
)

check(
    "a non-player field stays plain alphabetical",
    g.ItemOptions(lua.table(*ORDER_NAMES)),
    "Aardvark,Mid,Zena",
)

# --------------------------------------------------------------------------
# The end of night summary agrees with /syl due
# --------------------------------------------------------------------------

SUMMARY_CASES = [
    ("team", "1 on the team went home without an upgrade. /syl due ranks them."),
    ("guild", "2 in your guild went home without an upgrade. /syl due ranks them."),
    # Everyone is the one scope where the bare sentence already means what it
    # says, so it keeps the original wording.
    ("everyone", "3 went home without an upgrade. /syl due ranks them."),
]

for scope, want in SUMMARY_CASES:
    g.ResetWorld()
    g.SetScope(scope)
    check(f"summary at {scope} scope", g.SummaryLine(), want)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
