-- Core/Guild.lua
--
-- Who is in the guild, and what rank they hold.
--
-- Read from the in-game guild roster. Addons have no network access, so
-- external sites like Raider.IO or WoWAudit are not reachable from here —
-- but none of them know guild rank anyway, and the client does.
--
-- Rank is recorded onto loot records at the time of the drop, because ranks
-- change and history should show what was true when the item dropped.

local SYL = _G.ShowUsYourLoot

local Guild = {}
SYL.Guild = Guild

-- GetGuildRosterInfo returns a long positional list. Only these are used, and
-- each is type-checked, so a signature change degrades to "not in guild"
-- rather than to corrupt records.
local NAME_INDEX = 1
local RANK_NAME_INDEX = 2
local RANK_INDEX_INDEX = 3
local GUID_INDEX = 17

local byGUID = {}
local byName = {}
local guildName
local lastRefresh = 0

local function ShortName(fullName)
    if type(fullName) ~= "string" then
        return nil
    end

    return (fullName:match("^([^-]+)")) or fullName
end

function Guild.GetGuildName()
    return guildName
end

function Guild.IsInGuild()
    return IsInGuild() and true or false
end

function Guild.Refresh()
    byGUID = {}
    byName = {}
    guildName = nil

    if not Guild.IsInGuild() then
        return 0
    end

    guildName = GetGuildInfo("player")

    local total = GetNumGuildMembers() or 0
    local added = 0

    for index = 1, total do
        local info = { GetGuildRosterInfo(index) }

        local fullName = info[NAME_INDEX]
        local rankName = info[RANK_NAME_INDEX]
        local rankIndex = info[RANK_INDEX_INDEX]
        local guid = info[GUID_INDEX]

        if type(fullName) == "string" then
            local member = {
                name = fullName,
                shortName = ShortName(fullName),
                rank = type(rankName) == "string" and rankName or nil,
                rankIndex = type(rankIndex) == "number" and rankIndex or nil,
                guid = type(guid) == "string" and guid or nil,
            }

            if member.guid then
                byGUID[member.guid] = member
            end

            -- Roll data carries names without a realm, so both spellings are
            -- indexed for the fallback path.
            byName[fullName] = member

            if member.shortName then
                byName[member.shortName] = member
            end

            added = added + 1
        end
    end

    lastRefresh = time()

    return added
end

-- GUID first: it is exact. Names are only a fallback, and an ambiguous one,
-- since roll data drops the realm and two realms can share a name.
function Guild.GetMember(guid, name)
    if guid and byGUID[guid] then
        return byGUID[guid]
    end

    if name and byName[name] then
        return byName[name]
    end

    return nil
end

function Guild.IsMember(guid, name)
    return Guild.GetMember(guid, name) ~= nil
end

function Guild.GetRank(guid, name)
    local member = Guild.GetMember(guid, name)

    return member and member.rank or nil
end

function Guild.GetRankIndex(guid, name)
    local member = Guild.GetMember(guid, name)

    return member and member.rankIndex or nil
end

function Guild.GetMemberCount()
    local count = 0

    for _ in pairs(byGUID) do
        count = count + 1
    end

    return count
end

function Guild.GetLastRefresh()
    return lastRefresh
end

-- Asks the server for a fresh roster. The reply arrives as
-- GUILD_ROSTER_UPDATE, which is where Refresh actually runs.
function Guild.Request()
    if not Guild.IsInGuild() then
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
        _G.GuildRoster()
    end
end
