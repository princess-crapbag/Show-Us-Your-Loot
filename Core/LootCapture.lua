-- Core/LootCapture.lua
--
-- Fallback loot capture from CHAT_MSG_LOOT.
--
-- This is deliberately the *secondary* source of loot data. Blizzard's Loot
-- History API (see Core/LootHistory.lua) is the intended primary source,
-- because chat text is localised and carries no encounter, roll or winner
-- information. Chat capture stays in place so loot taken outside a tracked
-- encounter is never silently lost.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local LootCapture = {}
SYL.LootCapture = LootCapture

local DUPLICATE_WINDOW_SECONDS = 30
local DUPLICATE_TIME_BUCKET_SECONDS = 2

local function ExtractItemInformation(message)
    local itemLink =
        message:match("(|Hitem:.-|h%[.-%]|h)")

    if not itemLink then
        return nil
    end

    local quantity =
        tonumber(message:match("|h|r?x(%d+)"))
        or tonumber(message:match("|h x(%d+)"))
        or tonumber(message:match("x(%d+)%p?$"))
        or 1

    return {
        itemLink = itemLink,
        itemID = Utilities.GetItemIDFromLink(itemLink),
        itemName = Utilities.GetItemNameFromLink(itemLink),
        quantity = quantity,
    }
end

local function DetermineRecipient(message)
    if message:find("^You ") then
        return Utilities.GetPlayerFullName()
    end

    local recipient =
        message:match("^(.+) receives loot:")
        or message:match("^(.+) receives item:")
        or message:match("^(.+) receives bonus loot:")

    return Utilities.NormalizePlayerName(recipient)
end

-- Chat can deliver the same loot line more than once. Bucketing the timestamp
-- lets two deliveries a moment apart collapse onto the same identity.
local function CreateRecordID(recipient, itemID, timestamp, rawMessage)
    local timeBucket =
        math.floor(timestamp / DUPLICATE_TIME_BUCKET_SECONDS)

    return table.concat({
        tostring(recipient or "Unknown"),
        tostring(itemID or 0),
        tostring(timeBucket),
        tostring(rawMessage or ""),
    }, "|")
end

local function CleanRecentRecordIDs()
    ShowUsYourLootDB.recentRecordIDs =
        ShowUsYourLootDB.recentRecordIDs or {}

    local cutoff = time() - DUPLICATE_WINDOW_SECONDS

    for recordID, recordedAt in pairs(
        ShowUsYourLootDB.recentRecordIDs
    ) do
        if recordedAt < cutoff then
            ShowUsYourLootDB.recentRecordIDs[recordID] = nil
        end
    end
end

local function IsDuplicate(recordID)
    ShowUsYourLootDB.recentRecordIDs =
        ShowUsYourLootDB.recentRecordIDs or {}

    if ShowUsYourLootDB.recentRecordIDs[recordID] then
        return true
    end

    ShowUsYourLootDB.recentRecordIDs[recordID] = time()

    return false
end

local function BuildRecord(recordID, season, recipient, item, timestamp)
    local location = Utilities.GetLocationInformation()

    return {
        id = recordID,

        seasonID = season.id,
        seasonName = season.name,

        recipient = recipient,

        itemLink = item.itemLink,
        itemID = item.itemID,
        itemName = item.itemName,
        quantity = item.quantity,

        timestamp = timestamp,
        dateText = date("%Y-%m-%d", timestamp),
        timeText = date("%H:%M:%S", timestamp),

        recordedBy = Utilities.GetPlayerFullName(),

        zoneName = location.zoneName,
        instanceName = location.instanceName,
        instanceType = location.instanceType,
        instanceID = location.instanceID,
        difficultyID = location.difficultyID,
        difficultyName = location.difficultyName,
        maxPlayers = location.maxPlayers,
        instanceGroupSize = location.instanceGroupSize,
        inInstance = location.inInstance,
        inRaidGroup = location.inRaidGroup,
        inGroup = location.inGroup,

        -- Which pipeline produced this record. Loot History records will
        -- carry a different source once they become the primary path.
        source = "CHAT_MSG_LOOT",

        archived = false,
        excludedFromAnalytics = false,

        rawMessage = item.rawMessage,
    }
end

local function AnnounceCapture(record)
    if not ShowUsYourLootDB.settings.announceCaptures then
        return
    end

    print(
        SYL.colors.highlight
        .. "[SYL]"
        .. SYL.colors.reset
        .. " Recorded "
        .. tostring(record.itemLink)
        .. " for "
        .. SYL.colors.addon
        .. tostring(record.recipient)
        .. SYL.colors.reset
    )
end

function LootCapture.HandleChatMessage(message)
    if type(message) ~= "string" then
        return
    end

    local item = ExtractItemInformation(message)

    if not item then
        SYL:DebugPrint(
            "Ignored message without an item link: "
            .. tostring(message)
        )

        return
    end

    item.rawMessage = message

    local season = SYL.GetActiveSeason()

    if not season then
        SYL:Print(
            "Could not save loot because no active season exists."
        )

        return
    end

    local recipient = DetermineRecipient(message)
    local timestamp = time()

    local recordID =
        CreateRecordID(recipient, item.itemID, timestamp, message)

    CleanRecentRecordIDs()

    if IsDuplicate(recordID) then
        SYL:DebugPrint("Duplicate ignored: " .. tostring(message))

        return
    end

    local record =
        BuildRecord(recordID, season, recipient, item, timestamp)

    table.insert(season.loot, record)

    -- Keep the compatibility alias pointed at the live table.
    ShowUsYourLootDB.loot = season.loot

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    AnnounceCapture(record)
end
