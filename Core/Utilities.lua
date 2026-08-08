-- Core/Utilities.lua
--
-- Small, dependency-free helpers shared across the addon.
-- Nothing in this file may touch the database or create frames.

local SYL = _G.ShowUsYourLoot

local Utilities = {}
SYL.Utilities = Utilities

function Utilities.Trim(text)
    if type(text) ~= "string" then
        return nil
    end

    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utilities.GetPlayerFullName()
    local name, realm = UnitFullName("player")

    if not name then
        return "Unknown"
    end

    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

-- Strips colour codes and trailing punctuation from a name pulled out of a
-- chat message, which is never guaranteed to be clean.
function Utilities.NormalizePlayerName(name)
    if not name or name == "" then
        return "Unknown"
    end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    name = name:gsub("[%.,:]+$", "")

    return name
end

function Utilities.GetLocationInformation()
    local zoneName =
        GetRealZoneText()
        or GetZoneText()
        or "Unknown"

    local instanceName,
        instanceType,
        difficultyID,
        difficultyName,
        maxPlayers,
        dynamicDifficulty,
        isDynamic,
        instanceID,
        instanceGroupSize =
        GetInstanceInfo()

    local inInstance =
        select(1, IsInInstance())

    return {
        zoneName = zoneName,
        instanceName = instanceName or zoneName,
        instanceType = instanceType or "none",
        difficultyID = difficultyID or 0,
        difficultyName = difficultyName or "None",
        maxPlayers = maxPlayers or 0,
        instanceID = instanceID or 0,
        instanceGroupSize = instanceGroupSize or 0,
        inInstance = inInstance or false,
        inRaidGroup = IsInRaid(),
        inGroup = IsInGroup(),
    }
end

function Utilities.GetItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    return tonumber(itemLink:match("|?H?item:(%d+)"))
end

function Utilities.GetItemNameFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    return itemLink:match("%[(.-)%]")
end

function Utilities.FormatDateTime(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%y %I:%M %p", timestamp)
end

-- The list columns' version. "08/05/26 12:32 PM" is seventeen characters
-- against a column that also has to share a row with an item name, and it was
-- the format, not the width, that made the date column impossible. Dropping
-- to a 24 hour clock loses the " PM" and three characters with it, and stays
-- unambiguous.
function Utilities.FormatDateCompact(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%y %H:%M", timestamp)
end

-- Difficulty names are long enough to break any column they land in:
-- "Looking For Raid" is sixteen characters against boss and player names
-- that are shorter. Every list shows the short form instead.
local DIFFICULTY_SHORT = {
    [1] = "5N",
    [2] = "5H",
    [8] = "M+",
    [14] = "N",
    [15] = "HC",
    [16] = "M",
    [17] = "LFR",
    [23] = "5M",
    [24] = "TW",
}

function Utilities.ShortDifficulty(difficultyID, difficultyName)
    local short = DIFFICULTY_SHORT[difficultyID]

    if short then
        return short
    end

    if difficultyName
        and difficultyName ~= ""
        and difficultyName ~= "None"
    then
        -- An id this does not know yet. Initials beat truncation: "Looking
        -- For Raid" becomes LFR rather than "Looking Fo…".
        local initials = ""

        for word in difficultyName:gmatch("%a+") do
            initials = initials .. word:sub(1, 1):upper()
        end

        if #initials >= 2 then
            return initials
        end

        return difficultyName
    end

    return nil
end

-- Raid or dungeon, which the addon had no way of telling apart.
--
-- This matters more than a filter: RaidSession opened a night for anything
-- inside an instance, so a Mythic+ run recorded a five person raid night and
-- inflated attendance and the drought numbers that rank the due list.
--
-- GetInstanceInfo's instanceType is the authority — "raid" or "party" — but
-- it was never stored, so records written before this cannot be asked. The
-- difficulty id answers for those: dungeon and raid difficulties come from
-- disjoint sets and every record has one.
local RAID_DIFFICULTIES = {
    [3] = true, [4] = true,     -- 10 and 25 player, legacy
    [5] = true, [6] = true,     -- 10 and 25 player heroic, legacy
    [7] = true,                 -- LFR, legacy
    [9] = true,                 -- 40 player
    [14] = true, [15] = true, [16] = true,
    [17] = true,                -- LFR
    [33] = true,                -- Timewalking raid
}

local DUNGEON_DIFFICULTIES = {
    [1] = true, [2] = true,     -- Normal and Heroic
    [8] = true,                 -- Mythic Keystone
    [23] = true,                -- Mythic
    [24] = true,                -- Timewalking
}

function Utilities.GetContentType(instanceType, difficultyID)
    if instanceType == "raid" then
        return "raid"
    end

    if instanceType == "party" then
        return "dungeon"
    end

    -- No instanceType stored, so fall back to the difficulty. Anything in
    -- neither set — scenarios, arenas, an id this does not know yet —
    -- answers "other" rather than being guessed into one of them.
    if RAID_DIFFICULTIES[difficultyID] then
        return "raid"
    end

    if DUNGEON_DIFFICULTIES[difficultyID] then
        return "dungeon"
    end

    return "other"
end

-- Convenience for the places that only care whether something counts towards
-- raid attendance, which is the question the due list is really asking.
function Utilities.IsRaidContent(instanceType, difficultyID)
    return Utilities.GetContentType(instanceType, difficultyID) == "raid"
end

function Utilities.FormatClockTime(timestamp)
    if not timestamp then
        return "--:--:--"
    end

    return date("%H:%M:%S", timestamp)
end

function Utilities.FormatDateOnly(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%Y", timestamp)
end

function Utilities.CountKeys(value)
    if type(value) ~= "table" then
        return 0
    end

    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    return count
end

-- Returns the keys of a table sorted into a stable order so that debug output
-- and exports do not shuffle between reads.
function Utilities.GetSortedKeys(value)
    local keys = {}

    if type(value) ~= "table" then
        return keys
    end

    for key in pairs(value) do
        table.insert(keys, key)
    end

    table.sort(keys, function(left, right)
        local leftIsNumber = type(left) == "number"
        local rightIsNumber = type(right) == "number"

        if leftIsNumber and rightIsNumber then
            return left < right
        end

        if leftIsNumber ~= rightIsNumber then
            return leftIsNumber
        end

        return tostring(left) < tostring(right)
    end)

    return keys
end
