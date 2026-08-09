-- Core/RosterData.lua
--
-- Who is on the roster and in what order. No frames.
--
-- Split from RosterWindow, which was carrying the list, the sorting, the
-- drawing and the buff summary at once and had outgrown the size limit twice
-- in an afternoon.
--
-- THE REGISTRY HAS TO BE FILLED FIRST. Team membership and roles live on the
-- player registry, and a guild member who has never been in a raid is not in
-- it — so marking them silently did nothing at all. Nearly every member of a
-- large guild falls into that gap, which made the feature look broken for
-- everyone except the handful of people already recorded.

local SYL = _G.ShowUsYourLoot

local RosterData = {}
SYL.RosterData = RosterData

-- Called before building rather than on every refresh: it upserts a record
-- per guild member, and a five hundred member guild does not want that on
-- every keystroke of a search box.
function RosterData.EnsureRegistry()
    SYL.AltDetect.EnsureGuildMembers()
end

-- Built once and kept until something changes it.
--
-- The header above warns that filling the registry is too expensive to do on
-- every refresh, and then Build did the equally expensive half on every one:
-- a pass over every guild member, an alt resolution and a registry lookup
-- each, attendance folded across every raid night, and Raider.IO attached on
-- top. RosterWindow.Refresh runs on every keystroke in the search box, so
-- typing a six-letter name rebuilt a four-hundred-member roster six times.
--
-- Invalidated rather than time-limited, because the things that change it are
-- all events: the guild roster arriving, an alt being mapped, and opening the
-- window. Role and team are deliberately not cached here — the rows read
-- those live, so clicking one is already free.
local cached

function RosterData.Invalidate()
    cached = nil
end

function RosterData.Build()
    if cached then
        return cached
    end

    local _, attendance =
        SYL.RaidSession.BuildAttendance(SYL.GetAllRaids())

    local roster = {}

    for guid, member in pairs(SYL.Guild.GetMembers()) do
        -- Keyed by the character, not the person. Team membership, role and
        -- class all belong to a character; folding them to the main made
        -- marking one alt mark every character its owner had.
        local mainKey = SYL.Players.ResolveToMain(guid)
        local player = SYL.Players.Get(guid)

        -- Attendance is the one thing that is genuinely about the person, so
        -- it is still looked up by the main.
        local seen = attendance[mainKey]

        local main = mainKey ~= guid and SYL.Players.Get(mainKey) or nil

        table.insert(roster, {
            key = guid,
            guid = guid,
            mainKey = mainKey,
            isAlt = main ~= nil,
            mainName = main and (main.name or main.fullName) or nil,

            name = member.shortName,
            class = member.class or (player and player.class),
            rank = member.rank,
            rankIndex = member.rankIndex,
            nights = seen and seen.nights or 0,
        })
    end

    if SYL.Features.IsEnabled("raiderIO") then
        SYL.RaiderIO.AttachScores(roster)
    end

    cached = roster

    return roster
end

-- Substring, case-insensitive, on the name. Anything cleverer would be
-- guessing at what somebody half way through typing meant.
function RosterData.Search(roster, text)
    if not text or text == "" then
        return roster
    end

    local needle = text:lower()
    local kept = {}

    for _, entry in ipairs(roster) do
        local name = entry.name and entry.name:lower() or ""

        if name:find(needle, 1, true) then
            table.insert(kept, entry)
        end
    end

    return kept
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DPS = 3 }

RosterData.COMPARATORS = {
    name = function(a, b) return tostring(a.name) < tostring(b.name) end,
    class = function(a, b) return tostring(a.class) < tostring(b.class) end,
    rank = function(a, b)
        return (a.rankIndex or 99) < (b.rankIndex or 99)
    end,
    nights = function(a, b) return a.nights > b.nights end,

    -- ALT OF had no comparator at all, so clicking it sorted by name and put
    -- the arrow on the wrong column. Alts group under whoever they belong to;
    -- characters that are nobody's alt sort last, because an empty cell at
    -- the top of a list looks like missing data rather than an answer.
    main = function(a, b)
        local left = a.mainName or ""
        local right = b.mainName or ""

        if (left == "") ~= (right == "") then
            return right == ""
        end

        if left ~= right then
            return left < right
        end

        return tostring(a.name) < tostring(b.name)
    end,
    score = function(a, b)
        return (a.mplusScore or -1) > (b.mplusScore or -1)
    end,

    -- Tanks, healers, damage, then whoever nobody has decided on, which is
    -- the order a roster gets read in.
    role = function(a, b)
        local left = ROLE_ORDER[SYL.RaidTeam.GetRole(a.key) or ""] or 4
        local right = ROLE_ORDER[SYL.RaidTeam.GetRole(b.key) or ""] or 4

        if left ~= right then
            return left < right
        end

        return tostring(a.name) < tostring(b.name)
    end,

    team = function(a, b)
        local left = SYL.RaidTeam.IsMember(a.key)
        local right = SYL.RaidTeam.IsMember(b.key)

        if left ~= right then
            return left
        end

        return tostring(a.name) < tostring(b.name)
    end,
}

function RosterData.Sort(roster, sortKey, reversed)
    local comparator =
        RosterData.COMPARATORS[sortKey] or RosterData.COMPARATORS.name

    table.sort(roster, function(a, b)
        if reversed then
            return comparator(b, a)
        end

        return comparator(a, b)
    end)

    return roster
end
