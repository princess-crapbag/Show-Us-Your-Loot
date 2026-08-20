-- Core/LootHistoryAPI.lua
--
-- Safe access to Blizzard's Loot History API, plus runtime discovery of what
-- the live client actually exposes.
--
-- This module is stateless. It never assumes a function, event or enum
-- exists; it asks the client and reports back. Core/LootHistory.lua owns the
-- capture state and calls into here.
--
-- Confirmed on a live 12.0.7 client (build 68974) via /syl api, and every line
-- below re-confirmed unchanged on 12.1.0 (build 69273) on patch day. Nothing
-- in this namespace moved across that patch: same five members, same enum keys
-- and same numbering, same twelve events. Worth re-running after any patch,
-- because the failure this file guards against is silent — a renamed enum key
-- falls through to the fallback numbering below and the scores quietly change.
--
-- This says nothing about the *shape* of what a kill returns. /syl api reads
-- the namespace, not a payload; Core/LootHistorySnapshot.lua records that, and
-- it still rests on the 12.0.7 Rotmire kill.
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

-- ItemBind is not a loot-history enum, and it is listed here because this is
-- the one report anybody runs against a live client. Core/Utilities.lua reads
-- it to decide whether a drop is warbound, and a warbound drop is excluded
-- from the score and the drought — so a renamed key would quietly start
-- counting account gear as somebody's upgrade, with nothing on screen wrong.
-- Printing it is how the fallback numbering gets checked rather than trusted.
LootHistoryAPI.CANDIDATE_ENUMS = {
    "ItemBind",
    "EncounterLootDropRollState",
    "LootHistoryFilter",
    "LootRollType",
    "LootSlotType",
}

local rollStateNames

-- The roll states, in one place.
--
-- Five files each declared their own `local NEED_MAIN = 0` next to a comment
-- explaining what it meant, while this file was already reverse-mapping the
-- live enum two directories away. Six copies of a number Blizzard owns is six
-- chances to disagree, and the disagreement would be silent: a due list that
-- counts state 1 as an upgrade and a type column that calls it Greed both
-- look fine on their own.
--
-- Read from the live Enum, with the observed 12.0.7 numbering — unchanged in
-- 12.1.0 — as the fallback
-- for a client that has not defined it yet. Named after Blizzard's own keys so
-- the mapping is checkable against `/syl api` output rather than against
-- memory.
local function EnumState(key, fallback)
    if type(Enum) == "table"
        and type(Enum.EncounterLootDropRollState) == "table"
        and type(Enum.EncounterLootDropRollState[key]) == "number"
    then
        return Enum.EncounterLootDropRollState[key]
    end

    return fallback
end

LootHistoryAPI.ROLL_STATE = {
    NeedMainSpec = EnumState("NeedMainSpec", 0),
    NeedOffSpec = EnumState("NeedOffSpec", 1),
    Transmog = EnumState("Transmog", 2),
    Greed = EnumState("Greed", 3),
    NoRoll = EnumState("NoRoll", 4),
    Pass = EnumState("Pass", 5),
}

-- Whether a win counts as gear for the fairness math.
--
-- This is DueList's judgement call — only Need and offspec reset a drought —
-- and it is exported rather than repeated so that the type column, the boss
-- stats and the night summary all answer it the same way. Changing the rule
-- means changing it here.
function LootHistoryAPI.IsUpgradeState(state)
    return state == LootHistoryAPI.ROLL_STATE.NeedMainSpec
        or state == LootHistoryAPI.ROLL_STATE.NeedOffSpec
end

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
    [LootHistoryAPI.ROLL_STATE.NeedMainSpec] = "Need",
    [LootHistoryAPI.ROLL_STATE.NeedOffSpec] = "Need OS",
    [LootHistoryAPI.ROLL_STATE.Transmog] = "Mog",
    [LootHistoryAPI.ROLL_STATE.Greed] = "Greed",
    [LootHistoryAPI.ROLL_STATE.NoRoll] = "No roll",
    [LootHistoryAPI.ROLL_STATE.Pass] = "Pass",
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
