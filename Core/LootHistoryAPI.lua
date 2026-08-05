-- Core/LootHistoryAPI.lua
--
-- Safe access to Blizzard's Loot History API, plus runtime discovery of what
-- the live client actually exposes.
--
-- This module is stateless. It never assumes a function, event or enum
-- exists; it asks the client and reports back. Core/LootHistory.lua owns the
-- capture state and calls into here.
--
-- Confirmed on a live 12.0.7 client (build 68974) via /syl api:
--
--   C_LootHistory has exactly five members:
--     GetAllEncounterInfos, GetInfoForEncounter, GetLootHistoryTime,
--     GetSortedDropsForEncounter, GetSortedInfoForDrop
--   There is no per-player accessor, so roll data must arrive nested inside
--     the result of GetSortedInfoForDrop.
--   Enum.EncounterLootDropRollState:
--     NeedMainSpec=0 NeedOffSpec=1 Transmog=2 Greed=3 NoRoll=4 Pass=5
--   Enum.LootRollType and Enum.LootHistoryFilter do not exist, so roll type
--     comes from EncounterLootDropRollState.
--   12 of the 16 candidate events registered. The four rejected are the
--     pre-Dragonflight names: LOOT_HISTORY_AUTO_SHOW, _FULL_UPDATE,
--     _ROLL_CHANGED and _ROLL_COMPLETE. They stay in the list so a future
--     client re-adding them is detected rather than missed.

local SYL = _G.ShowUsYourLoot

local LootHistoryAPI = {}
SYL.LootHistoryAPI = LootHistoryAPI

local MAX_COPY_DEPTH = 6

-- Modern (Dragonflight and later) names first, then legacy and adjacent
-- encounter events. Anything the client rejects is recorded as unavailable,
-- which is itself useful information.
LootHistoryAPI.CANDIDATE_EVENTS = {
    "LOOT_HISTORY_UPDATE_ENCOUNTER",
    "LOOT_HISTORY_UPDATE_DROP",
    "LOOT_HISTORY_CLEAR_HISTORY",
    "LOOT_HISTORY_GO_TO_ENCOUNTER",
    "LOOT_HISTORY_AUTO_SHOW",
    "LOOT_HISTORY_FULL_UPDATE",
    "LOOT_HISTORY_ROLL_CHANGED",
    "LOOT_HISTORY_ROLL_COMPLETE",
    "LOOT_ROLLS_COMPLETE",
    "ENCOUNTER_LOOT_RECEIVED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "BOSS_KILL",
    "START_LOOT_ROLL",
    "CANCEL_LOOT_ROLL",
    "CONFIRM_LOOT_ROLL",
}

LootHistoryAPI.CANDIDATE_ENUMS = {
    "EncounterLootDropRollState",
    "LootHistoryFilter",
    "LootRollType",
    "LootSlotType",
}

local rollStateNames

function LootHistoryAPI.IsAvailable()
    return type(C_LootHistory) == "table"
end

-- Calls a C_LootHistory function without ever letting a missing or changed
-- API take the addon down. Returns an array of results, or nil plus a reason.
function LootHistoryAPI.SafeCall(functionName, ...)
    if not LootHistoryAPI.IsAvailable() then
        return nil, "C_LootHistory is not present"
    end

    local apiFunction = C_LootHistory[functionName]

    if type(apiFunction) ~= "function" then
        return nil, "not present in this client"
    end

    local results = { pcall(apiFunction, ...) }

    if not results[1] then
        return nil, tostring(results[2])
    end

    table.remove(results, 1)

    return results, nil
end

-- Blizzard reuses and mutates the tables it returns, so anything we intend to
-- display later has to be copied out immediately.
function LootHistoryAPI.CopyValue(value, depth)
    if type(value) ~= "table" then
        return value
    end

    depth = depth or 0

    if depth >= MAX_COPY_DEPTH then
        return "<max depth reached>"
    end

    local copy = {}

    for key, entry in pairs(value) do
        copy[key] = LootHistoryAPI.CopyValue(entry, depth + 1)
    end

    return copy
end

-- Reverse-mapped from the live Enum table rather than hardcoded, so the names
-- stay correct even if Blizzard renumbers the states.
local function GetRollStateNames()
    if rollStateNames then
        return rollStateNames
    end

    rollStateNames = {}

    if type(Enum) == "table"
        and type(Enum.EncounterLootDropRollState) == "table"
    then
        for key, value in pairs(Enum.EncounterLootDropRollState) do
            rollStateNames[value] = key
        end
    end

    return rollStateNames
end

-- Short labels for display. A transmog win is not the same as a main-spec
-- upgrade, so the distinction has to survive all the way to the UI.
local SHORT_STATE_NAMES = {
    [0] = "Need",
    [1] = "Need OS",
    [2] = "Mog",
    [3] = "Greed",
    [4] = "No roll",
    [5] = "Pass",
}

function LootHistoryAPI.ShortRollState(value)
    if value == nil then
        return nil
    end

    return SHORT_STATE_NAMES[value] or ("state " .. tostring(value))
end

function LootHistoryAPI.GetShortStateNames()
    return SHORT_STATE_NAMES
end

function LootHistoryAPI.DescribeRollState(value)
    if value == nil then
        return "unknown"
    end

    local names = GetRollStateNames()

    return (names[value] or "unmapped") .. " (" .. tostring(value) .. ")"
end

-- Enumerates whatever the live client actually exposes. This is the answer to
-- "what does Blizzard provide in this build", and it is generated, not guessed.
function LootHistoryAPI.BuildReport(registeredEvents, unavailableEvents)
    local versionName, buildNumber, buildDate, interfaceVersion =
        GetBuildInfo()

    local report = {
        clientVersion = versionName,
        clientBuild = buildNumber,
        clientBuildDate = buildDate,
        interfaceVersion = interfaceVersion,
        addonVersion = SYL.version,

        namespacePresent = LootHistoryAPI.IsAvailable(),
        functions = {},
        enums = {},
        events = {
            registered = {},
            unavailable = {},
        },
    }

    if LootHistoryAPI.IsAvailable() then
        local success = pcall(function()
            for key, value in pairs(C_LootHistory) do
                report.functions[key] = type(value)
            end
        end)

        if not success then
            report.functions = "<C_LootHistory could not be enumerated>"
        end
    end

    for _, enumName in ipairs(LootHistoryAPI.CANDIDATE_ENUMS) do
        if type(Enum) == "table" and type(Enum[enumName]) == "table" then
            local values = {}

            for key, value in pairs(Enum[enumName]) do
                values[key] = value
            end

            report.enums[enumName] = values
        else
            report.enums[enumName] = "<not present>"
        end
    end

    for _, event in ipairs(registeredEvents or {}) do
        table.insert(report.events.registered, event)
    end

    for event, reason in pairs(unavailableEvents or {}) do
        report.events.unavailable[event] = reason
    end

    return report
end
