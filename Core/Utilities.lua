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
