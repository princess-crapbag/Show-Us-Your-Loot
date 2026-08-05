-- Core/LootHistorySnapshot.lua
--
-- Turns the raw results of the Loot History API into a structured snapshot of
-- one encounter: its drops, and the per-player rolls under each drop.
--
-- Stateless by design. Core/LootHistory.lua owns the capture state and calls
-- Build() whenever the client tells it something changed.
--
-- Every entry keeps Blizzard's own table under `raw` next to the fields we
-- derive from it, because the derived names are still provisional.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local API = SYL.LootHistoryAPI

local LootHistorySnapshot = {}
SYL.LootHistorySnapshot = LootHistorySnapshot

-- The live client exposes no per-player accessor, so roll data has to arrive
-- nested inside the result of GetSortedInfoForDrop. We do not yet know which
-- field carries it: check the likely names first, then fall back to any array
-- of tables, and always report which key was used so the guess can be
-- confirmed or corrected from a real raid.
local PLAYER_LIST_KEYS = {
    "rollInfos",
    "players",
    "playerInfos",
    "rolls",
}

local function FindPlayerList(detail)
    for _, key in ipairs(PLAYER_LIST_KEYS) do
        local candidate = detail[key]

        if type(candidate) == "table" and #candidate > 0 then
            return candidate, key
        end
    end

    for key, value in pairs(detail) do
        if type(value) == "table"
            and #value > 0
            and type(value[1]) == "table"
        then
            return value, key
        end
    end

    return nil, nil
end

local function BuildPlayerEntry(index, rawPlayer)
    local copied = API.CopyValue(rawPlayer)

    return {
        index = index,
        raw = copied,

        name = copied.playerName or copied.name,
        class = copied.playerClass or copied.class,
        rollState = copied.state or copied.rollState,
        rollStateText = API.DescribeRollState(
            copied.state or copied.rollState
        ),
        roll = copied.roll or copied.rollValue,
        isWinner = copied.isWinner,
    }
end

-- Returns the raw detail table, the derived player entries, an error string
-- when players could not be found, and the key the players were found under.
local function BuildDropDetail(encounterID, lootListID)
    local results, reason =
        API.SafeCall("GetSortedInfoForDrop", encounterID, lootListID)

    if not results then
        return nil, {}, reason
    end

    local detail = results[1]

    if type(detail) ~= "table" then
        return nil, {}, "no drop detail returned"
    end

    local copied = API.CopyValue(detail)
    local rawPlayers, sourceKey = FindPlayerList(copied)

    if not rawPlayers then
        return copied, {}, "no player list found in drop detail"
    end

    local players = {}

    for index, rawPlayer in ipairs(rawPlayers) do
        table.insert(players, BuildPlayerEntry(index, rawPlayer))
    end

    return copied, players, nil, sourceKey
end

local function BuildDropEntry(encounterID, rawDrop)
    local copied = API.CopyValue(rawDrop)
    local lootListID = copied.lootListID

    -- playerListKey comes back separately rather than being written into the
    -- detail table, so the raw dump stays purely Blizzard's own data.
    local detail, players, playerError, playerListKey =
        BuildDropDetail(encounterID, lootListID)

    local winner = copied.winner or (detail and detail.winner)

    return {
        lootListID = lootListID,
        raw = copied,
        detail = detail,

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

        playerListKey = playerListKey,
        players = players,
        playerError = playerError,
    }
end

function LootHistorySnapshot.Build(encounterID, encounterName)
    if not encounterID then
        return nil
    end

    local snapshot = {
        encounterID = encounterID,
        encounterName = encounterName,
        capturedAt = time(),
        drops = {},
    }

    -- Encounter-level detail. Blizzard may well carry the boss name here,
    -- which would remove our reliance on ENCOUNTER_END for it.
    local infoResults, infoError =
        API.SafeCall("GetInfoForEncounter", encounterID)

    if infoResults then
        snapshot.encounterInfo = API.CopyValue(infoResults[1])
    else
        snapshot.encounterInfoError = infoError
    end

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

-- The two client-wide accessors, read at export time so a paste carries the
-- whole history the client holds rather than just the current encounter.
function LootHistorySnapshot.GetClientHistory()
    local encounters, encountersError =
        API.SafeCall("GetAllEncounterInfos")

    local historyTime = API.SafeCall("GetLootHistoryTime")

    return {
        allEncounters = encounters and API.CopyValue(encounters[1]) or nil,
        allEncountersError = encountersError,
        lootHistoryTime = historyTime and historyTime[1] or nil,
    }
end
