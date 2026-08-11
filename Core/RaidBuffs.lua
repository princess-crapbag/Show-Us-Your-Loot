-- Core/RaidBuffs.lua
--
-- Which classes bring which raid-wide buffs, and what a roster is missing.
--
-- THIS TABLE GOES STALE. Blizzard moves buffs between classes, removes them,
-- and adds new ones every expansion — and unlike almost everything else in
-- this addon there is no API to ask. Nothing in the client exposes "what does
-- a Mage bring to a raid", so it has to be written down and maintained.
--
-- So it is one table, at the top, with the date it was checked. When it is
-- wrong, this is the only file to edit.
--
-- Checked against Midnight (12.0.x) on 2026-08-08 from public class guides,
-- not from the client. Treat it as good rather than certain — if the roster
-- window claims a buff is missing that somebody in the raid clearly has,
-- this table is where the mistake will be.

local SYL = _G.ShowUsYourLoot

local RaidBuffs = {}
SYL.RaidBuffs = RaidBuffs

-- Grouped, because "we have no Bloodlust" and "we have no Mark of the Wild"
-- are not the same size of problem. A missing stat buff is a small loss; a
-- missing Bloodlust changes how a fight is planned.
RaidBuffs.STAT = "stat"
RaidBuffs.DEBUFF = "debuff"
RaidBuffs.UTILITY = "utility"

RaidBuffs.CATEGORY_LABELS = {
    [RaidBuffs.STAT] = "Raid buffs",
    [RaidBuffs.DEBUFF] = "Damage taken",
    [RaidBuffs.UTILITY] = "Utility",
}

RaidBuffs.CATEGORY_ORDER = {
    RaidBuffs.STAT, RaidBuffs.DEBUFF, RaidBuffs.UTILITY,
}

-- `classes` lists every class that can provide it. One is enough to cover it.
RaidBuffs.LIST = {
    {
        key = "intellect",
        name = "Arcane Intellect",
        category = RaidBuffs.STAT,
        classes = { "MAGE" },
    },
    {
        key = "stamina",
        name = "Power Word: Fortitude",
        category = RaidBuffs.STAT,
        classes = { "PRIEST" },
    },
    {
        key = "attackpower",
        name = "Battle Shout",
        category = RaidBuffs.STAT,
        classes = { "WARRIOR" },
    },
    {
        key = "versatility",
        name = "Mark of the Wild",
        category = RaidBuffs.STAT,
        classes = { "DRUID" },
    },
    {
        key = "skyfury",
        name = "Skyfury",
        category = RaidBuffs.STAT,
        classes = { "SHAMAN" },
    },

    {
        key = "magicdamage",
        name = "Chaos Brand",
        category = RaidBuffs.DEBUFF,
        classes = { "DEMONHUNTER" },
        note = "+5% magic damage taken",
    },
    {
        key = "physicaldamage",
        name = "Mystic Touch",
        category = RaidBuffs.DEBUFF,
        classes = { "MONK" },
        note = "+5% physical damage taken",
    },

    {
        key = "bloodlust",
        name = "Bloodlust / Heroism",
        category = RaidBuffs.UTILITY,
        classes = { "SHAMAN", "MAGE", "HUNTER", "EVOKER" },
    },
    {
        key = "battleres",
        name = "Battle resurrection",
        category = RaidBuffs.UTILITY,
        classes = { "DRUID", "DEATHKNIGHT", "WARLOCK", "PALADIN" },
    },
}

-- Counts who can bring what. `members` is any list carrying a `class` field,
-- which both the guild roster and a raid roster do.
--
-- Returns one entry per buff with the members who provide it, so the window
-- can answer "who do we ask" rather than only "is it covered".
function RaidBuffs.BuildCoverage(members)
    local byClass = {}

    for _, member in ipairs(members or {}) do
        local class = member.class

        if class then
            byClass[class] = byClass[class] or {}

            table.insert(byClass[class], member)
        end
    end

    local coverage = {}

    for _, buff in ipairs(RaidBuffs.LIST) do
        local providers = {}

        for _, class in ipairs(buff.classes) do
            for _, member in ipairs(byClass[class] or {}) do
                table.insert(providers, member)
            end
        end

        table.sort(providers, function(left, right)
            return tostring(left.name) < tostring(right.name)
        end)

        table.insert(coverage, {
            buff = buff,
            providers = providers,
            covered = #providers > 0,
        })
    end

    return coverage
end

-- Just the missing ones, which is the question actually being asked.
function RaidBuffs.Missing(coverage)
    local missing = {}

    for _, entry in ipairs(coverage or {}) do
        if not entry.covered then
            table.insert(missing, entry.buff)
        end
    end

    return missing
end

function RaidBuffs.Summarize(coverage)
    local covered = 0

    for _, entry in ipairs(coverage or {}) do
        if entry.covered then
            covered = covered + 1
        end
    end

    return covered, #coverage
end
