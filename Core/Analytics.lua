-- Core/Analytics.lua
--
-- Per-player numbers derived from drop records. Pure computation: no frames,
-- no saved state, recalculated on demand.
--
-- The roll list on every drop names everyone who was eligible, which is what
-- makes attendance answerable at all: a player who appears in roll lists but
-- never wins is exactly "was there and got nothing".
--
-- Need and offspec wins are counted apart from transmog and greed on purpose.
-- A transmog win is not an upgrade, and folding them together would make loot
-- look fairer than it was.

local SYL = _G.ShowUsYourLoot

local Analytics = {}
SYL.Analytics = Analytics

local STATE = SYL.LootHistoryAPI.ROLL_STATE

local SECONDS_PER_DAY = 86400

local function NewEntry(roll)
    return {
        key = roll.guid or roll.name,
        guid = roll.guid,
        name = roll.name,
        class = roll.class,

        eligible = 0,
        nights = 0,

        wins = 0,
        needWins = 0,
        offspecWins = 0,
        mogWins = 0,
        greedWins = 0,

        lastSeenAt = nil,
        lastWinAt = nil,

        nightsSeen = {},
    }
end

local function CountWin(entry, roll)
    entry.wins = entry.wins + 1

    if roll.state == STATE.NeedMainSpec then
        entry.needWins = entry.needWins + 1
    elseif roll.state == STATE.NeedOffSpec then
        entry.offspecWins = entry.offspecWins + 1
    elseif roll.state == STATE.Transmog then
        entry.mogWins = entry.mogWins + 1
    elseif roll.state == STATE.Greed then
        entry.greedWins = entry.greedWins + 1
    end
end

local function Later(current, candidate)
    if not candidate then
        return current
    end

    if not current or candidate > current then
        return candidate
    end

    return current
end

function Analytics.BuildPlayerStats(drops)
    local byKey = {}
    local order = {}

    for _, drop in ipairs(drops or {}) do
        -- hidden is a display state and still counts. excludedFromAnalytics
        -- is the flag that actually removes a drop from the maths.
        -- Synced records carry no roll list. Counting them would report
        -- zero eligible players rather than "we do not know".
        if not drop.excludedFromAnalytics and not drop.partial then
            for _, roll in ipairs(drop.rolls or {}) do
                -- Folded to the main, so a raider's alt runs do not read as
                -- a second person who never wins anything.
                local key = SYL.Players.ResolveToMain(roll.guid or roll.name)

                if key then
                    local entry = byKey[key]

                    if not entry then
                        entry = NewEntry(roll)
                        entry.key = key

                        local player = SYL.Players.Get(key)

                        if player then
                            entry.guid = player.guid or entry.guid
                            entry.name = player.name or entry.name
                            entry.class = player.class or entry.class
                        end

                        byKey[key] = entry

                        table.insert(order, entry)
                    end

                    entry.eligible = entry.eligible + 1
                    entry.lastSeenAt = Later(entry.lastSeenAt, drop.timestamp)

                    -- Distinct dates stand in for raid nights. Good enough to
                    -- answer "how often were they there" without a separate
                    -- attendance record.
                    if drop.dateText and not entry.nightsSeen[drop.dateText] then
                        entry.nightsSeen[drop.dateText] = true
                        entry.nights = entry.nights + 1
                    end

                    if roll.isWinner then
                        CountWin(entry, roll)

                        entry.lastWinAt = Later(entry.lastWinAt, drop.timestamp)
                    end
                end
            end
        end
    end

    -- Nights come from the raid roster, not from loot. Someone eligible for
    -- nothing all evening still raided, and only the roster knows that.
    local _, attendanceByKey =
        SYL.RaidSession.BuildAttendance(SYL.GetAllRaids())

    local now = time()

    for _, entry in ipairs(order) do
        local attendance =
            attendanceByKey[entry.guid or ""]
            or attendanceByKey[entry.key or ""]

        if attendance then
            entry.nights = attendance.nights
            entry.pulls = attendance.encounters
        end

        entry.upgradeWins = entry.needWins + entry.offspecWins

        -- Through the person rather than the character, so a raider who
        -- brought an alt is not reported at the alt's rank.
        local ranked = SYL.Guild.GetMemberForPlayer(
            entry.key, entry.guid, entry.name
        )

        entry.guildRank = ranked and ranked.rank or nil
        entry.guildRankIndex = ranked and ranked.rankIndex or nil
        entry.inGuild = entry.guildRank ~= nil

        -- Days since their last upgrade, or since first seen if they have
        -- never won one. nil would sort unpredictably, so never-won players
        -- carry their full time known instead.
        local since = entry.lastWinAt or entry.lastSeenAt

        entry.droughtDays = since
            and math.floor((now - since) / SECONDS_PER_DAY)
            or 0

        entry.hasEverWon = entry.wins > 0

        entry.nightsSeen = nil
    end

    -- Anyone who raided but never appeared in a single roll list is still a
    -- raider who got nothing, which is the whole question being asked.
    local attendance = SYL.RaidSession.BuildAttendance(SYL.GetAllRaids())

    for _, member in ipairs(attendance) do
        -- BuildAttendance already folds alts, so this key is a main's.
        local key = member.key or member.guid or member.name

        if key and not byKey[key] then
            local entry = NewEntry(member)

            entry.key = key
            entry.nights = member.nights
            entry.pulls = member.encounters
            entry.lastSeenAt = member.lastSeen
            entry.upgradeWins = 0
            entry.droughtDays = 0
            entry.hasEverWon = false
            local ranked = SYL.Guild.GetMemberForPlayer(
                key, member.guid, member.name
            )

            entry.guildRank = ranked and ranked.rank or nil
            entry.guildRankIndex = ranked and ranked.rankIndex or nil
            entry.inGuild = entry.guildRank ~= nil
            entry.nightsSeen = nil

            byKey[key] = entry

            table.insert(order, entry)
        end
    end

    return order
end

-- Adds every guild member who is not already here, with zeroes for the loot
-- numbers they have not earned.
--
-- BuildPlayerStats answers "who has this addon seen", which is people who
-- rolled on something or turned up to a raid. That is the right default and
-- the wrong one for looking over a roster: a guild member who has never
-- raided is exactly who an officer is looking for.
--
-- Alts fold in the usual way, so somebody's second character does not appear
-- as a separate person with no history.
function Analytics.IncludeGuildRoster(stats)
    local present = {}

    for _, entry in ipairs(stats) do
        present[entry.key or ""] = true
    end

    -- Sorted rather than raw pairs(). Several of a person's characters fold
    -- onto one key here and the first one reached wins, so hash order decided
    -- which character's details the row showed — and hash order changes as
    -- the roster table is rebuilt. Sorting makes the choice repeatable; the
    -- rank lookup below makes it correct.
    local members = SYL.Guild.GetMembers()

    for _, guid in ipairs(SYL.Utilities.GetSortedKeys(members)) do
        local member = members[guid]
        local key = SYL.Players.ResolveToMain(guid)

        if not present[key] then
            present[key] = true

            local player = SYL.Players.Get(key)

            -- The person's rank, which is their main's, not whichever alt
            -- happened to be reached first.
            local ranked = SYL.Guild.GetMemberForPlayer(key, guid, member.name)
                or member

            table.insert(stats, {
                key = key,
                guid = guid,
                name = (player and player.name) or member.shortName,
                class = player and player.class,

                eligible = 0,
                nights = 0,
                pulls = 0,

                wins = 0,
                needWins = 0,
                offspecWins = 0,
                mogWins = 0,
                greedWins = 0,
                upgradeWins = 0,

                droughtDays = 0,
                hasEverWon = false,

                guildRank = ranked.rank,
                guildRankIndex = ranked.rankIndex,
                inGuild = true,
            })
        end
    end

    return stats
end

-- Players who turned up and left with nothing. Transmog and greed wins do not
-- rescue someone from this list, since neither is an upgrade.
function Analytics.FilterEmptyHanded(stats)
    local empty = {}

    for _, entry in ipairs(stats) do
        if entry.upgradeWins == 0 then
            table.insert(empty, entry)
        end
    end

    return empty
end

local COMPARATORS = {
    name = function(a, b) return tostring(a.name) < tostring(b.name) end,
    rank = function(a, b)
        return (a.guildRankIndex or 99) < (b.guildRankIndex or 99)
    end,
    nights = function(a, b) return a.nights > b.nights end,
    eligible = function(a, b) return a.eligible > b.eligible end,
    upgrades = function(a, b) return a.upgradeWins > b.upgradeWins end,
    mog = function(a, b) return a.mogWins > b.mogWins end,
    lastWin = function(a, b)
        return (a.lastWinAt or 0) > (b.lastWinAt or 0)
    end,
    drought = function(a, b) return a.droughtDays > b.droughtDays end,

    -- Nothing here computes mplusScore; the players window attaches it from
    -- Raider.IO before sorting. Without an entry the header would fall back
    -- to the default comparator and sort by something other than the column
    -- that was clicked, which looks like the sort is broken.
    score = function(a, b)
        return (a.mplusScore or -1) > (b.mplusScore or -1)
    end,
}

function Analytics.Sort(stats, key, reversed)
    local comparator = COMPARATORS[key] or COMPARATORS.upgrades

    table.sort(stats, function(a, b)
        local result = comparator(a, b)

        -- A tie on the chosen column falls back to name, so the order does
        -- not shuffle between refreshes.
        if not result and not comparator(b, a) then
            return tostring(a.name) < tostring(b.name)
        end

        if reversed then
            return comparator(b, a)
        end

        return result
    end)

    return stats
end

function Analytics.Summarise(stats)
    local totals = {
        players = #stats,
        guildMembers = 0,
        emptyHanded = 0,
        upgrades = 0,
        mog = 0,
    }

    for _, entry in ipairs(stats) do
        if entry.inGuild then
            totals.guildMembers = totals.guildMembers + 1
        end

        if entry.upgradeWins == 0 then
            totals.emptyHanded = totals.emptyHanded + 1
        end

        totals.upgrades = totals.upgrades + entry.upgradeWins
        totals.mog = totals.mog + entry.mogWins
    end

    return totals
end
