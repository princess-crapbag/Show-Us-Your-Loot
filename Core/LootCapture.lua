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
    -- The color wrapper first. A link without its |cff… prefix and closing
    -- |r displays correctly but cannot be pasted into chat, and that is the
    -- form that was being stored. The bare fragment stays as a fallback for
    -- any line that genuinely arrives without color codes.
    local itemLink =
        message:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        or message:match("(|Hitem:.-|h%[.-%]|h)")

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

-- Reading the sentence is its own problem and lives in Core/LootMessages.lua,
-- which builds its patterns from the client's own format strings so the
-- parser is right in every locale.
local DetermineRecipient = SYL.LootMessages.DetermineRecipient
local WasCreated = SYL.LootMessages.WasCreated

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

--------------------------------------------------------------------------
-- Encounter loot, as a second opinion
--------------------------------------------------------------------------
--
-- ENCOUNTER_LOOT_RECEIVED carries the recipient as a name argument rather
-- than inside a sentence, so it needs no parsing and cannot be wrong about
-- who got something. It only fires for boss loot, so it cannot replace chat
-- capture — the vault, world drops and crafting all arrive without it.
--
-- It is used as a backstop rather than as a second writer. Recording from
-- both would mean two records for every boss drop unless the two were
-- reconciled, and a duplicate in the fairness maths is a worse failure than
-- the one being fixed. So chat stays the only thing that writes, and this
-- supplies the name when the sentence could not be read, plus the encounter
-- id, which chat never carries at all.
local HINT_WINDOW_SECONDS = 15

local encounterLootHints = {}

local function ForgetStaleHints(now)
    for itemID, hint in pairs(encounterLootHints) do
        if now - hint.at > HINT_WINDOW_SECONDS then
            encounterLootHints[itemID] = nil
        end
    end
end

function LootCapture.NoteEncounterLoot(
    encounterID, itemID, itemLink, quantity, playerName
)
    if not itemID then
        return
    end

    local now = time()

    ForgetStaleHints(now)

    encounterLootHints[itemID] = {
        encounterID = encounterID,
        playerName = playerName,
        at = now,
    }
end

local function HintFor(itemID, timestamp)
    if not itemID then
        return nil
    end

    local hint = encounterLootHints[itemID]

    if not hint then
        return nil
    end

    if math.abs(timestamp - hint.at) > HINT_WINDOW_SECONDS then
        return nil
    end

    return hint
end

local function BuildRecord(recordID, season, recipient, item, timestamp, hint)
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

        -- nil when the client had not cached the item yet. Recorded rather
        -- than derived later because an item level is a fact about the moment
        -- it dropped, and a piece upgraded with crests afterwards would read
        -- back higher than it was won at.
        itemLevel = Utilities.GetItemLevel(item.itemLink),

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

        -- Chat says nothing about which boss dropped it. When the encounter
        -- event named the same item moments ago, that is the boss.
        encounterID = hint and hint.encounterID or nil,

        -- Recorded at capture time in the locale that produced the line, so
        -- nothing downstream has to re-read English out of the raw message.
        created = item.created or nil,

        -- Vault rewards arrive through the same chat channel as everything
        -- else and look identical afterwards, so the one moment they can be
        -- told apart is while the frame that handed them over is still open.
        -- Guarded because the frame only exists once its addon has loaded.
        fromVault = (_G.WeeklyRewardsFrame
            and _G.WeeklyRewardsFrame:IsShown()) or nil,

        archived = false,
        excludedFromAnalytics = false,

        rawMessage = item.rawMessage,
    }
end

-- Gear only, whatever the quality filter is set to record.
--
-- The filter defaults to recording every quality, which is right — a fresh
-- install should never quietly miss loot — and announcing every quality is
-- not the same decision. With both on, one Mythic+ run doubled the user's
-- loot chat by repeating every gray and every reagent back at them, prefixed.
-- A reviewer named this specifically as the thing that gets an addon
-- uninstalled, and they are right: it is the only part of this that talks
-- unprompted, in the channel people actually read.
--
-- So the record is still written, and the line is only printed for something
-- worth telling somebody about. IsTrackableGear returns nil for an item the
-- client has not cached, which is treated as "not yet" — announcing it a
-- second later would be worse than not announcing it.
local function WorthAnnouncing(record)
    return SYL.PersonalLoot.IsTrackableGear(record) == true
end

local function AnnounceCapture(record)
    if not ShowUsYourLootDB.settings.announceCaptures then
        return
    end

    if not WorthAnnouncing(record) then
        return
    end

    SYL:Write(
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

    if not SYL.ItemQuality.ShouldTrackLink(item.itemLink) then
        SYL:DebugPrint(
            "Skipped by quality filter: " .. tostring(item.itemLink)
        )

        return
    end

    local season = SYL.GetActiveSeason()

    if not season then
        SYL:Print(
            "Could not save loot because no active season exists."
        )

        return
    end

    local timestamp = time()

    item.created = WasCreated(message)

    local hint = HintFor(item.itemID, timestamp)
    local recipient = DetermineRecipient(message)

    -- The encounter event names the recipient outright, so it settles any
    -- line the sentence patterns could not read.
    if not recipient and hint then
        recipient = Utilities.NormalizePlayerName(hint.playerName)
    end

    -- Dropping the record is the lesser error. Filing it under a fabricated
    -- name puts a player in the due list who does not exist, and every real
    -- raider's share is measured against them.
    if not recipient or recipient == "" then
        SYL:DebugPrint(
            "No recipient could be read from: " .. tostring(message)
        )

        return
    end

    local recordID =
        CreateRecordID(recipient, item.itemID, timestamp, message)

    CleanRecentRecordIDs()

    if IsDuplicate(recordID) then
        SYL:DebugPrint("Duplicate ignored: " .. tostring(message))

        return
    end

    local record =
        BuildRecord(recordID, season, recipient, item, timestamp, hint)

    table.insert(season.loot, record)

    -- Keep the compatibility alias pointed at the live table.
    ShowUsYourLootDB.loot = season.loot

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    AnnounceCapture(record)
end
