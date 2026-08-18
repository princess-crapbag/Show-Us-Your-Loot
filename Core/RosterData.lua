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
        SYL.RaidSession.BuildAttendance(SYL.GetActiveRaids())

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

            -- "people who havent signed in in 30 days plus dont matter".
            -- nil means the client would not say, which is not the same as
            -- inactive and must not be filtered out as though it were.
            daysOffline = member.daysOffline,
            isOnline = member.isOnline,
        })
    end

    -- Recruits who have not joined yet, appended so they are counted for
    -- buff coverage and can be marked onto the team before they arrive. They
    -- carry no GUID and no attendance, and the rank column says why.
    for _, entry in ipairs(SYL.IncomingRoster.List()) do
        table.insert(roster, {
            key = entry.key,
            guid = nil,
            mainKey = entry.key,
            isAlt = false,
            mainName = nil,

            isIncoming = true,

            name = entry.name,
            class = entry.class,
            -- They have no guild rank because they are not in the guild.
            -- "N/A" rather than "Joining": this is the GUILD RANK column, and
            -- a status word in it reads as a rank somebody could hold.
            rank = "N/A",
            -- Below every real rank, so they sort to the bottom rather than
            -- into the middle of the officer ranks by accident.
            rankIndex = 98,
            nights = 0,
        })
    end

    -- And anybody named on a shared roster that this client cannot see for
    -- itself. The sender's recruits are the case that matters: a character who
    -- has not transferred yet is on their IncomingRoster and is in neither the
    -- receiver's guild list nor their own, so without this the roster arrives
    -- with some of the people it was sent to describe simply missing — and
    -- missing is the one failure that looks like a correct empty answer.
    --
    -- Appended, never merged over: an entry already built above is this
    -- client's own view of a character it can actually see, which is better
    -- than a copy of somebody else's.
    local known = {}

    for _, entry in ipairs(roster) do
        known[entry.key] = true
    end

    for key, member in pairs(
        SYL.SharedRoster and SYL.SharedRoster.Members() or {}
    ) do
        if not known[key] then
            table.insert(roster, {
                key = key,
                guid = nil,
                mainKey = key,
                isAlt = false,
                mainName = nil,

                isShared = true,

                name = member.name,
                class = member.class,
                -- Same reasoning as the recruits above: this is the guild rank
                -- column, and this client has no idea what rank they hold.
                rank = "N/A",
                rankIndex = 98,
                nights = 0,
            })
        end
    end

    if SYL.Features.IsEnabled("raiderIO") then
        SYL.RaiderIO.AttachScores(roster)
    end

    cached = roster

    return roster
end

-- Characters nobody has logged into for a while.
--
-- Aimee's cutoff, and the reason for it: a roster is a list of people you
-- could bring, and somebody who has not signed in for a month is not one of
-- them. Recruits who have not joined yet are always kept — they have no
-- last-online at all, and they are on the list precisely because they are
-- expected.
--
-- Unknown is kept too. GetGuildRosterLastOnline answers nothing for a member
-- the client has not filled in yet, and dropping those would empty the roster
-- for the first few seconds after login, which reads as the guild being gone.
RosterData.INACTIVE_DAYS = 30

function RosterData.ActiveOnly(roster, withinDays)
    withinDays = withinDays or RosterData.INACTIVE_DAYS

    local kept = {}

    for _, entry in ipairs(roster or {}) do
        local days = entry.daysOffline

        if entry.isIncoming or days == nil or days <= withinDays then
            table.insert(kept, entry)
        end
    end

    return kept
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
