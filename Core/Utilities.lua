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

-- A link the chat box will accept.
--
-- Chat capture stored only the |Hitem:…|h[Name]|h part, dropping the |cff…
-- colour prefix and the |r that closes it. That renders fine in a font string,
-- which is why it went unnoticed, but shift-clicking such a row inserted a
-- broken link into chat: the recipient sees raw escape codes rather than an
-- item, which for an addon whose whole subject is items is not a small thing.
--
-- The client can rebuild it, since the item id inside the fragment is intact.
-- Uncached items have no answer yet and keep what they had, which is no worse
-- than before and fixes itself on the next hover.
function Utilities.NormalizeItemLink(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return itemLink
    end

    if itemLink:find("|c", 1, true) then
        return itemLink
    end

    local _, fullLink = C_Item.GetItemInfo(itemLink)

    return fullLink or itemLink
end

function Utilities.GetItemNameFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    return itemLink:match("%[(.-)%]")
end

-- The effective item level of a link, or nil when the client has not cached
-- the item yet.
--
-- Nothing recorded an item level, so every acquisition weighed the same: a
-- Champion piece out of a +7 and a Myth piece out of the vault both counted
-- as "they got something", and the due list ranked a raider who took one of
-- each below a raider who took two Veteran rings. This stores the number.
-- What the fairness maths does with it is a separate decision and has
-- deliberately not been made here — changing how the ranking is weighted is
-- not a bug fix, and it should not arrive as a side effect of one.
--
-- Crest upgrades stay invisible regardless. Spending crests fires no loot
-- event of any kind, so an item that goes from Champion 1 to Champion 8 is
-- unobservable from here; only its level at the moment it dropped is known.
function Utilities.GetItemLevel(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local success, level = pcall(function()
        return C_Item.GetDetailedItemLevelInfo(itemLink)
    end)

    if not success then
        return nil
    end

    return level
end

-- Bind on Equip, as far as the client will say.
--
-- Aimee's rule: a BoE does not reset a raid drought. Somebody who wins a BoE
-- has won something sellable, not the tier piece the drought is measuring, and
-- resetting their clock for it pushes a genuinely starved raider down the list.
--
-- THREE ANSWERS, NOT TWO. nil means the client has not cached the item yet and
-- genuinely does not know. Callers must not read that as "yes": treating an
-- uncached item as a BoE would silently stop counting real upgrades, and the
-- failure would look exactly like the drought maths being broken. Not-BoE is
-- the safe default because it is the answer that keeps counting.
--
-- bindType is field 14 of GetItemInfo, and 2 is Bind on Equip. Read from the
-- link at the time the question is asked rather than stored at capture, so
-- this works on the history already recorded instead of only on new drops.
local BIND_ON_EQUIP = 2

function Utilities.IsBindOnEquip(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local success, bindType = pcall(function()
        return select(14, C_Item.GetItemInfo(itemLink))
    end)

    if not success or type(bindType) ~= "number" then
        return nil
    end

    return bindType == BIND_ON_EQUIP
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
    [33] = "TW",
    [151] = "LFR TW",
    [205] = "Fol",
    [208] = "Delve",
    [220] = "Story",
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
    [18] = true,                -- Event, 40 player
    [33] = true,                -- Timewalking raid
    [151] = true,               -- Timewalking LFR
    [220] = true,               -- Story
}

local DUNGEON_DIFFICULTIES = {
    [1] = true, [2] = true,     -- Normal and Heroic
    [8] = true,                 -- Mythic Keystone
    [19] = true,                -- Event, 5 player
    [23] = true,                -- Mythic
    [24] = true,                -- Timewalking
    [205] = true,               -- Follower
}

-- Delves are the one that mattered. GetInstanceInfo reports them as
-- "scenario", which nothing here handled, so every delve drop was filed as
-- world loot alongside a quest reward picked up in Dornogal. A delve is
-- instanced content that awards gear on a track, and calling it "world" put
-- it in the one bucket the fairness maths ignores hardest.
--
-- Torghast and the Visions are in here for the same reason: instanced, not a
-- raid, not a dungeon, and previously answering "other".
local SCENARIO_DIFFICULTIES = {
    [11] = true, [12] = true,   -- Heroic and Normal scenario
    [20] = true,                -- Event scenario
    [152] = true,               -- Visions of N'Zoth
    [167] = true,               -- Torghast
    [208] = true,               -- Delves
}

-- Raid content that is not a raid team's night.
--
-- IsRaidContent decides whether a session opens, and instanceType wins over
-- the difficulty, so anything flagged "raid" by the client opened a night —
-- including a Story clear done alone on a Tuesday, which then sat in the
-- attendance history as a one-person raid and moved everybody's drought.
--
-- These are all scaled or off-schedule versions of a raid: real raid content
-- by instance type, but never the thing the roster is being measured on. They
-- still classify as "raid" for the loot list, because that is where the item
-- came from — only attendance excludes them.
local NOT_A_RAID_NIGHT = {
    [18] = true,                -- Event
    [33] = true,                -- Timewalking raid
    [151] = true,               -- Timewalking LFR
    [205] = true,               -- Follower
    [220] = true,               -- Story
}

function Utilities.GetContentType(instanceType, difficultyID)
    if instanceType == "raid" then
        return "raid"
    end

    if instanceType == "party" then
        return "dungeon"
    end

    if instanceType == "scenario" then
        return "scenario"
    end

    -- No instanceType stored, so fall back to the difficulty. Anything in
    -- none of the sets — arenas, an id this does not know yet — answers
    -- "other" rather than being guessed into one of them.
    if RAID_DIFFICULTIES[difficultyID] then
        return "raid"
    end

    if DUNGEON_DIFFICULTIES[difficultyID] then
        return "dungeon"
    end

    if SCENARIO_DIFFICULTIES[difficultyID] then
        return "scenario"
    end

    return "other"
end

-- Convenience for the places that only care whether something counts towards
-- raid attendance, which is the question the due list is really asking.
--
-- Deliberately narrower than GetContentType: see NOT_A_RAID_NIGHT above.
function Utilities.IsRaidContent(instanceType, difficultyID)
    if NOT_A_RAID_NIGHT[difficultyID] then
        return false
    end

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
