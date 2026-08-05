-- Core/LootHistorySnapshot.lua
--
-- Turns the raw results of the Loot History API into a structured snapshot of
-- one encounter: its drops, and the per-player rolls under each drop.
--
-- Stateless by design. Core/LootHistory.lua owns the capture state and calls
-- Build() whenever the client tells it something changed.
--
-- CONFIRMED SHAPES (live 12.0.7, build 68974, Rotmire kill)
--
-- GetSortedDropsForEncounter(encounterID) -> array of drop tables. Each drop
-- already carries its full roll list, so GetSortedInfoForDrop returns an
-- identical table and is only used as a fallback:
--   allPassed        boolean
--   currentLeader    roll info captured mid-roll -- NOT the winner, see below
--   duration         milliseconds the roll ran (330000)
--   isTied           unreliable; observed true on drops with no tie at all
--   itemHyperlink    full |cff..|Hitem:..|h[Name]|h|r link
--   lootListID       number, unique per drop within the encounter
--   playerRollState  the viewing player's own state, not the winner's
--   rollInfos        array of per-player roll info
--   startTime        unix seconds
--   winner           roll info for the actual winner
--
-- Each entry in rollInfos:
--   playerName   name WITHOUT realm ("Dravok") -- ambiguous across realms
--   playerGUID   "Player-160-0C155216" -- the only safe identity key
--   playerClass  class file name ("HUNTER"), usable for class colouring
--   state        Enum.EncounterLootDropRollState
--   roll         1-100, ABSENT unless the player actually rolled
--   isWinner     boolean
--   isSelf       boolean
--
-- GetInfoForEncounter / GetAllEncounterInfos:
--   { encounterID, encounterName, startTime, duration }
--   encounterName is present, so boss names do not depend on ENCOUNTER_END.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local API = SYL.LootHistoryAPI

local LootHistorySnapshot = {}
SYL.LootHistorySnapshot = LootHistorySnapshot

local function BuildPlayerEntry(index, rawPlayer)
    local copied = API.CopyValue(rawPlayer)

    return {
        index = index,
        raw = copied,

        name = copied.playerName,
        guid = copied.playerGUID,
        class = copied.playerClass,

        rollState = copied.state,
        rollStateText = API.DescribeRollState(copied.state),

        -- Absent for Pass, Transmog and NoRoll: those players never rolled.
        roll = copied.roll,

        isWinner = copied.isWinner,
        isSelf = copied.isSelf,
    }
end

local function BuildPlayerEntries(rollInfos)
    local players = {}

    if type(rollInfos) ~= "table" then
        return players
    end

    for index, rawPlayer in ipairs(rollInfos) do
        table.insert(players, BuildPlayerEntry(index, rawPlayer))
    end

    return players
end

-- Only called when a drop somehow arrives without its roll list.
local function FetchDropDetail(encounterID, lootListID)
    local results = API.SafeCall(
        "GetSortedInfoForDrop", encounterID, lootListID
    )

    if not results or type(results[1]) ~= "table" then
        return nil
    end

    return API.CopyValue(results[1])
end

local function BuildDropEntry(encounterID, rawDrop)
    local copied = API.CopyValue(rawDrop)
    local rollInfos = copied.rollInfos

    if type(rollInfos) ~= "table" then
        local detail = FetchDropDetail(encounterID, copied.lootListID)

        rollInfos = detail and detail.rollInfos
        copied.recoveredFromDetail = detail ~= nil
    end

    local winner = copied.winner

    return {
        lootListID = copied.lootListID,
        raw = copied,

        itemHyperlink = copied.itemHyperlink,
        itemID = Utilities.GetItemIDFromLink(copied.itemHyperlink),
        itemName = Utilities.GetItemNameFromLink(copied.itemHyperlink),

        allPassed = copied.allPassed,
        startTime = copied.startTime,
        duration = copied.duration,

        -- winner is authoritative. currentLeader is a mid-roll snapshot and
        -- has been observed naming a different player than the eventual
        -- winner when two players tie on the same roll.
        winnerName = winner and winner.playerName,
        winnerGUID = winner and winner.playerGUID,
        winnerClass = winner and winner.playerClass,
        winnerRoll = winner and winner.roll,

        -- The viewing player's own choice on this drop, not the winner's.
        ownRollStateText = API.DescribeRollState(copied.playerRollState),

        players = BuildPlayerEntries(rollInfos),
    }
end

function LootHistorySnapshot.Build(encounterID, encounterMeta)
    if not encounterID then
        return nil
    end

    local snapshot = {
        encounterID = encounterID,
        capturedAt = time(),
        drops = {},
    }

    if encounterMeta then
        snapshot.encounterName = encounterMeta.name
        snapshot.difficultyID = encounterMeta.difficultyID
        snapshot.groupSize = encounterMeta.groupSize
    end

    local infoResults, infoError =
        API.SafeCall("GetInfoForEncounter", encounterID)

    if infoResults and type(infoResults[1]) == "table" then
        snapshot.encounterInfo = API.CopyValue(infoResults[1])

        -- The API's own name wins over anything we cached from an event.
        snapshot.encounterName =
            snapshot.encounterInfo.encounterName
            or snapshot.encounterName
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
