-- Core/Sync.lua
--
-- Shares captured drops with other officers over addon comms.
--
-- This is the only part of the addon that sends anything to other players,
-- so it is deliberately narrow:
--
--   * OFF by default. Nothing is transmitted until it is switched on.
--   * RAID channel only. Never guild-wide, never whispered, never a chat
--     message a human sees.
--   * Only from senders in your own guild, and only while you are in a raid.
--   * One message per drop, sent once, when the drop resolves.
--
-- WHAT IS SENT, in full, and nothing more:
--
--   record id, encounter id and name, difficulty id, instance id,
--   item id, winner name, winner GUID, winner roll state, winning roll,
--   whether everyone passed, how many were eligible, and the timestamp.
--
-- WHAT IS NOT SENT: the per-player roll list, chat loot, guild ranks,
-- settings, anything about characters not involved in the drop, and any
-- free text a player typed.
--
-- Addon messages cap at 255 bytes, and a 25-player roll list does not come
-- close to fitting. Rather than chunk and reassemble, this sends the drop
-- header only. That is enough to answer "who got what" when you were not
-- online, which is the problem worth solving. Records arriving this way are
-- marked partial and never overwrite a full local record.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Sync = {}
SYL.Sync = Sync

local PREFIX = "SYLOOT"
local PROTOCOL = "1"
local SEPARATOR = "\t"

local frame
local registered = false

local function IsEnabled()
    return ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.syncEnabled
        and true
        or false
end

-- Tabs are the field separator, so anything containing one would corrupt the
-- message. Names cannot contain tabs, but this costs nothing.
local function Clean(value)
    if value == nil then
        return ""
    end

    return (tostring(value):gsub("[\t\n|]", " "))
end

local function Encode(record)
    return table.concat({
        PROTOCOL,
        Clean(record.id),
        Clean(record.encounterID),
        Clean(record.encounterName),
        Clean(record.difficultyID),
        Clean(record.instanceID),
        Clean(record.itemID),
        Clean(record.winnerName),
        Clean(record.winnerGUID),
        Clean(record.winnerState),
        Clean(record.winnerRoll),
        record.allPassed and "1" or "",
        Clean(record.eligibleCount),
        Clean(record.timestamp),
    }, SEPARATOR)
end

local function Decode(payload)
    local fields = {}

    for field in (payload .. SEPARATOR):gmatch("(.-)" .. SEPARATOR) do
        table.insert(fields, field)
    end

    if fields[1] ~= PROTOCOL then
        return nil
    end

    local function number(value)
        return tonumber(value)
    end

    return {
        id = fields[2],
        encounterID = number(fields[3]),
        encounterName = fields[4] ~= "" and fields[4] or nil,
        difficultyID = number(fields[5]),
        instanceID = number(fields[6]),
        itemID = number(fields[7]),
        winnerName = fields[8] ~= "" and fields[8] or nil,
        winnerGUID = fields[9] ~= "" and fields[9] or nil,
        winnerState = number(fields[10]),
        winnerRoll = number(fields[11]),
        allPassed = fields[12] == "1" or nil,
        eligibleCount = number(fields[13]),
        timestamp = number(fields[14]),
    }
end

function Sync.Send(record)
    if not IsEnabled() or not record or not record.id then
        return false
    end

    -- Raid only. Guild-wide would reach people who are not raiding and have
    -- no reason to receive it.
    if not IsInRaid() then
        return false
    end

    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false
    end

    local payload = Encode(record)

    if #payload > 250 then
        SYL:DebugPrint("Sync payload too long, skipped: " .. record.id)

        return false
    end

    C_ChatInfo.SendAddonMessage(PREFIX, payload, "RAID")

    return true
end

-- Only merges what is missing. A record captured locally is always richer,
-- because it carries the full roll list, so it is never replaced.
local function Merge(decoded, sender)
    local drops = SYL.GetActiveDrops()

    for _, existing in ipairs(drops) do
        if existing.id == decoded.id then
            return false
        end
    end

    local season = SYL.GetActiveSeason()

    if not season then
        return false
    end

    local record = {
        id = decoded.id,

        seasonID = season.id,
        seasonName = season.name,

        encounterID = decoded.encounterID,
        encounterName = decoded.encounterName,
        difficultyID = decoded.difficultyID,
        instanceID = decoded.instanceID,

        itemID = decoded.itemID,

        winnerName = decoded.winnerName,
        winnerGUID = decoded.winnerGUID,
        winnerState = decoded.winnerState,
        winnerRoll = decoded.winnerRoll,
        allPassed = decoded.allPassed,
        eligibleCount = decoded.eligibleCount,

        timestamp = decoded.timestamp or time(),
        dateText = date("%Y-%m-%d", decoded.timestamp or time()),

        recordedBy = sender,
        source = "SYNC",

        -- No roll list travelled with this, and analytics must not treat an
        -- absent list as "nobody rolled".
        partial = true,
        rolls = {},

        hidden = false,
        excludedFromAnalytics = false,
    }

    table.insert(drops, record)

    SYL.LootHistoryStore.RebuildIndex()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
end

local function OnAddonMessage(prefix, payload, channel, sender)
    if prefix ~= PREFIX or not IsEnabled() then
        return
    end

    -- Ignore our own broadcast coming back around.
    if sender and Utilities.GetPlayerFullName() == sender then
        return
    end

    -- Guild members only. Anyone else in the raid is not a source this addon
    -- has any reason to trust.
    local shortName = sender and sender:match("^([^-]+)") or nil

    if not SYL.Guild.IsMember(nil, shortName)
        and not SYL.Guild.IsMember(nil, sender)
    then
        return
    end

    local decoded = Decode(payload)

    if not decoded or not decoded.id then
        return
    end

    if Merge(decoded, sender) then
        SYL:DebugPrint("Sync received a drop from " .. tostring(sender))
    end
end

function Sync.Enable()
    if registered then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")

    frame:SetScript("OnEvent", function(_, _, ...)
        OnAddonMessage(...)
    end)

    registered = true

    return true
end

function Sync.IsEnabled()
    return IsEnabled()
end
