-- Core/LootHistory.lua
--
-- Capture layer for Blizzard's Loot History API.
--
-- This module deliberately stores NOTHING permanently. Its only job is to find
-- out exactly what the live client hands us, so that a later version can make
-- Loot History the primary loot source instead of CHAT_MSG_LOOT.
--
-- Safe API access and discovery live in Core/LootHistoryAPI.lua, and turning
-- API results into structured snapshots lives in Core/LootHistorySnapshot.lua.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local API = SYL.LootHistoryAPI
local Snapshot = SYL.LootHistorySnapshot

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

    -- encounterID -> { name, difficultyID, groupSize }
    encounterMeta = {},
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

-- Snapshot building lives in Core/LootHistorySnapshot.lua; this module only
-- decides when to take one and holds the result.
function LootHistory.GetEncounterSnapshot(encounterID)
    if not encounterID then
        return nil
    end

    return Snapshot.Build(
        encounterID,
        LootHistory.state.encounterMeta[encounterID]
    )
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

-- The loot history API carries encounterName itself, but not difficulty or
-- group size, so those are kept from ENCOUNTER_START/ENCOUNTER_END.
local function RememberEncounter(encounterID, name, difficultyID, groupSize)
    if not encounterID then
        return
    end

    local meta = LootHistory.state.encounterMeta[encounterID] or {}

    if name and name ~= "" then
        meta.name = name
    end

    meta.difficultyID = difficultyID or meta.difficultyID
    meta.groupSize = groupSize or meta.groupSize

    LootHistory.state.encounterMeta[encounterID] = meta
end

-- A single 25-player boss produced over 200 LOOT_HISTORY_UPDATE_DROP events
-- in about 50 seconds. Rebuilding every drop and re-rendering the developer
-- window on each one is wasted work during the busiest moment of a raid, so
-- bursts collapse into one refresh.
local REFRESH_DEBOUNCE_SECONDS = 0.5

local refreshPending = false
local pendingEncounterID

local function RunPendingRefresh()
    refreshPending = false

    local state = LootHistory.state

    if pendingEncounterID then
        state.currentEncounterID = pendingEncounterID
        state.currentSnapshot =
            LootHistory.GetEncounterSnapshot(pendingEncounterID)

        pendingEncounterID = nil
    end

    if SYL.RefreshDeveloperWindow then
        SYL:RefreshDeveloperWindow()
    end
end

local function ScheduleRefresh(encounterID)
    if encounterID then
        pendingEncounterID = encounterID
    end

    if refreshPending then
        return
    end

    refreshPending = true

    C_Timer.After(REFRESH_DEBOUNCE_SECONDS, RunPendingRefresh)
end

local EVENT_HANDLERS = {
    LOOT_HISTORY_UPDATE_ENCOUNTER = function(encounterID)
        ScheduleRefresh(encounterID)
    end,

    LOOT_HISTORY_UPDATE_DROP = function(encounterID, lootListID)
        LootHistory.state.currentLootListID = lootListID
        ScheduleRefresh(encounterID)
    end,

    LOOT_HISTORY_GO_TO_ENCOUNTER = function(encounterID)
        ScheduleRefresh(encounterID)
    end,

    ENCOUNTER_LOOT_RECEIVED = function(encounterID)
        ScheduleRefresh(encounterID)
    end,

    ENCOUNTER_START = function(encounterID, encounterName, difficultyID, groupSize)
        RememberEncounter(encounterID, encounterName, difficultyID, groupSize)
    end,

    ENCOUNTER_END = function(encounterID, encounterName, difficultyID, groupSize)
        RememberEncounter(encounterID, encounterName, difficultyID, groupSize)
        ScheduleRefresh(encounterID)
    end,

    BOSS_KILL = function(encounterID, name)
        RememberEncounter(encounterID, name)
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

    -- Handlers that touch an encounter schedule their own refresh. This one
    -- keeps the event log on screen current for everything else.
    ScheduleRefresh(nil)
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
        client = Snapshot.GetClientHistory(),

        currentEncounterID = state.currentEncounterID,
        currentLootListID = state.currentLootListID,
        currentSnapshot = state.currentSnapshot,

        eventLog = state.log,
    }
end
