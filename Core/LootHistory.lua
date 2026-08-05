-- Core/LootHistory.lua
--
-- Capture layer for Blizzard's Loot History API.
--
-- This module deliberately stores NOTHING permanently. Its only job is to find
-- out exactly what the live client hands us, so that a later version can make
-- Loot History the primary loot source instead of CHAT_MSG_LOOT.
--
-- Safe API access and discovery live in Core/LootHistoryAPI.lua.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local API = SYL.LootHistoryAPI

local LootHistory = {}
SYL.LootHistory = LootHistory

local MAX_LOG_ENTRIES = 250

LootHistory.state = {
    enabled = false,
    frame = nil,
    registeredEvents = {},
    unavailableEvents = {},

    log = {},
    logCounter = 0,
    lastEvent = nil,

    currentEncounterID = nil,
    currentLootListID = nil,
    currentSnapshot = nil,

    encounterNames = {},
}

-- Thin delegates so callers only ever need SYL.LootHistory.
function LootHistory.IsAvailable()
    return API.IsAvailable()
end

function LootHistory.DescribeRollState(value)
    return API.DescribeRollState(value)
end

function LootHistory.GetAPIReport()
    return API.BuildReport(
        LootHistory.state.registeredEvents,
        LootHistory.state.unavailableEvents
    )
end

--------------------------------------------------------------------------
-- Snapshots
--------------------------------------------------------------------------

local function BuildPlayerEntries(encounterID, lootListID)
    local players = {}

    local results, reason =
        API.SafeCall("GetPlayerInfoForDrop", encounterID, lootListID)

    if not results then
        return players, reason
    end

    local rawPlayers = results[1]

    if type(rawPlayers) ~= "table" then
        return players, "no player table returned"
    end

    for index, rawPlayer in ipairs(rawPlayers) do
        local copied = API.CopyValue(rawPlayer)

        table.insert(players, {
            index = index,
            raw = copied,

            -- Derived with fallbacks; the raw table above stays authoritative
            -- until the real field names are confirmed in game.
            name = copied.playerName or copied.name,
            class = copied.playerClass or copied.class,
            rollState = copied.state or copied.rollState,
            rollStateText = API.DescribeRollState(
                copied.state or copied.rollState
            ),
            roll = copied.roll or copied.rollValue,
            isWinner = copied.isWinner,
        })
    end

    return players, nil
end

local function BuildDropEntry(encounterID, rawDrop)
    local copied = API.CopyValue(rawDrop)
    local lootListID = copied.lootListID

    local players, playerError =
        BuildPlayerEntries(encounterID, lootListID)

    local winner = copied.winner

    return {
        lootListID = lootListID,
        raw = copied,

        itemHyperlink = copied.itemHyperlink or copied.itemLink,
        itemID = Utilities.GetItemIDFromLink(
            copied.itemHyperlink or copied.itemLink
        ),
        allPassed = copied.allPassed,
        isCurrentlyRolling = copied.isCurrentlyRolling,

        winnerName = type(winner) == "table"
            and (winner.playerName or winner.name)
            or winner,

        rollStateText = API.DescribeRollState(copied.playerRollState),

        players = players,
        playerError = playerError,
    }
end

function LootHistory.GetEncounterSnapshot(encounterID)
    if not encounterID then
        return nil
    end

    local snapshot = {
        encounterID = encounterID,
        encounterName = LootHistory.state.encounterNames[encounterID],
        capturedAt = time(),
        drops = {},
    }

    local results, reason =
        API.SafeCall("GetSortedDropsForEncounter", encounterID)

    if not results then
        snapshot.error = reason
        return snapshot
    end

    local drops = results[1]

    if type(drops) ~= "table" then
        snapshot.error = "no drop table returned"
        return snapshot
    end

    for _, rawDrop in ipairs(drops) do
        table.insert(snapshot.drops, BuildDropEntry(encounterID, rawDrop))
    end

    return snapshot
end

--------------------------------------------------------------------------
-- Event capture
--------------------------------------------------------------------------

local function TrimLog()
    local log = LootHistory.state.log

    while #log > MAX_LOG_ENTRIES do
        table.remove(log, 1)
    end
end

local function RecordEvent(event, ...)
    local state = LootHistory.state
    local argCount = select("#", ...)
    local capturedAt = time()

    local args = {}

    for index = 1, argCount do
        args[index] = (select(index, ...))
    end

    state.logCounter = state.logCounter + 1

    local entry = {
        index = state.logCounter,
        timestamp = capturedAt,
        clockText = Utilities.FormatClockTime(capturedAt),
        event = event,
        args = args,
        argCount = argCount,
    }

    table.insert(state.log, entry)
    state.lastEvent = entry

    TrimLog()

    return entry
end

-- Keeps a friendly boss name for encounter IDs, which the loot history data
-- itself does not appear to carry.
local function RememberEncounterName(encounterID, name)
    if encounterID and name and name ~= "" then
        LootHistory.state.encounterNames[encounterID] = name
    end
end

local function RefreshSnapshotFor(encounterID)
    if not encounterID then
        return
    end

    local state = LootHistory.state

    state.currentEncounterID = encounterID
    state.currentSnapshot = LootHistory.GetEncounterSnapshot(encounterID)
end

local EVENT_HANDLERS = {
    LOOT_HISTORY_UPDATE_ENCOUNTER = function(encounterID)
        RefreshSnapshotFor(encounterID)
    end,

    LOOT_HISTORY_UPDATE_DROP = function(encounterID, lootListID)
        LootHistory.state.currentLootListID = lootListID
        RefreshSnapshotFor(encounterID)
    end,

    LOOT_HISTORY_GO_TO_ENCOUNTER = function(encounterID)
        RefreshSnapshotFor(encounterID)
    end,

    ENCOUNTER_LOOT_RECEIVED = function(encounterID)
        RefreshSnapshotFor(encounterID)
    end,

    ENCOUNTER_START = function(encounterID, encounterName)
        RememberEncounterName(encounterID, encounterName)
    end,

    ENCOUNTER_END = function(encounterID, encounterName)
        RememberEncounterName(encounterID, encounterName)
        RefreshSnapshotFor(encounterID)
    end,

    BOSS_KILL = function(encounterID, name)
        RememberEncounterName(encounterID, name)
    end,
}

local function OnEvent(_, event, ...)
    local entry = RecordEvent(event, ...)

    SYL:DebugPrint(
        "LootHistory event: "
        .. event
        .. " ("
        .. entry.argCount
        .. " args)"
    )

    local handler = EVENT_HANDLERS[event]

    if handler then
        -- A change in Blizzard's data must never break event capture, so a
        -- failing handler is contained rather than propagated.
        local success, errorMessage = pcall(handler, ...)

        if not success then
            SYL:DebugPrint(
                "LootHistory handler failed for "
                .. event
                .. ": "
                .. tostring(errorMessage)
            )
        end
    end

    if SYL.RefreshDeveloperWindow then
        SYL:RefreshDeveloperWindow()
    end
end

--------------------------------------------------------------------------
-- Enable / disable
--------------------------------------------------------------------------

function LootHistory.Enable()
    local state = LootHistory.state

    if state.enabled then
        return #state.registeredEvents
    end

    if not state.frame then
        state.frame = CreateFrame("Frame")
        state.frame:SetScript("OnEvent", OnEvent)
    end

    state.registeredEvents = {}
    state.unavailableEvents = {}

    -- Registering an event the client does not know raises a Lua error, so
    -- each one is probed individually.
    for _, event in ipairs(API.CANDIDATE_EVENTS) do
        local success, errorMessage =
            pcall(state.frame.RegisterEvent, state.frame, event)

        if success then
            table.insert(state.registeredEvents, event)
        else
            state.unavailableEvents[event] = tostring(errorMessage)
        end
    end

    state.enabled = true

    return #state.registeredEvents
end

function LootHistory.Disable()
    local state = LootHistory.state

    if not state.enabled then
        return
    end

    if state.frame then
        state.frame:UnregisterAllEvents()
    end

    state.enabled = false
end

function LootHistory.IsEnabled()
    return LootHistory.state.enabled
end

function LootHistory.ClearLog()
    local state = LootHistory.state

    state.log = {}
    state.logCounter = 0
    state.lastEvent = nil
    state.currentSnapshot = nil
    state.currentEncounterID = nil
    state.currentLootListID = nil
end

function LootHistory.GetLog()
    return LootHistory.state.log
end

-- Everything the developer window knows, in one table, for Copy JSON.
function LootHistory.BuildExportTable()
    local state = LootHistory.state
    local capturedAt = time()

    return {
        capturedAt = capturedAt,
        capturedAtText = Utilities.FormatDateTime(capturedAt),
        inspectorEnabled = state.enabled,

        api = LootHistory.GetAPIReport(),

        currentEncounterID = state.currentEncounterID,
        currentLootListID = state.currentLootListID,
        currentSnapshot = state.currentSnapshot,

        eventLog = state.log,
    }
end
