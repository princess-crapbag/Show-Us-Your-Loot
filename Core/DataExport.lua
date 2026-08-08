-- Core/DataExport.lua
--
-- The machine-readable export: one JSON document describing everything the
-- addon has recorded.
--
-- Separate from Core/Export.lua, which writes prose for a Discord message.
-- This is for programs — the browser dashboard today, officer sync and a
-- hosted service later — so it is versioned, complete, and stable.
--
-- Identity is already sound and is what makes merging two exports safe:
-- drops carry runID-encounterID-lootListID, players are keyed by GUID, and
-- raid sessions by instance, difficulty and date.

local SYL = _G.ShowUsYourLoot

local DataExport = {}
SYL.DataExport = DataExport

-- Bump when the shape changes in a way a reader must know about. A page
-- written today can then refuse, or adapt to, a much later file.
DataExport.SCHEMA_VERSION = 1

local function CopyRolls(rolls)
    local copied = {}

    for _, roll in ipairs(rolls or {}) do
        table.insert(copied, {
            name = roll.name,
            guid = roll.guid,
            class = roll.class,
            state = roll.state,
            stateText = roll.stateText,
            roll = roll.roll,
            isWinner = roll.isWinner,
            guildRankIndex = roll.guildRankIndex,
        })
    end

    return copied
end

local function CopyDrop(record)
    return {
        id = record.id,
        runID = record.runID,

        encounterID = record.encounterID,
        encounterName = record.encounterName,
        difficultyID = record.difficultyID,
        difficultyName = record.difficultyName,
        groupSize = record.groupSize,

        instanceID = record.instanceID,
        instanceName = record.instanceName,

        lootListID = record.lootListID,
        itemID = record.itemID,
        itemName = record.itemName,
        itemLink = record.itemLink,
        itemLevel = record.itemLevel,

        winnerName = record.winnerName,
        winnerGUID = record.winnerGUID,
        winnerClass = record.winnerClass,
        winnerRoll = record.winnerRoll,
        winnerState = record.winnerState,
        winnerGuildRank = record.winnerGuildRank,

        allPassed = record.allPassed,
        eligibleCount = record.eligibleCount,

        timestamp = record.timestamp,
        dateText = record.dateText,
        timeText = record.timeText,

        recordedBy = record.recordedBy,
        source = record.source,

        hidden = record.hidden or nil,
        excludedFromAnalytics = record.excludedFromAnalytics or nil,

        rolls = CopyRolls(record.rolls),
    }
end

local function CopyChatRecord(record)
    return {
        id = record.id,
        recipient = record.recipient,
        itemID = record.itemID,
        itemName = record.itemName,
        itemLink = record.itemLink,
        quantity = record.quantity,
        timestamp = record.timestamp,
        dateText = record.dateText,
        instanceName = record.instanceName,
        difficultyName = record.difficultyName,
        zoneName = record.zoneName,
        recordedBy = record.recordedBy,
        source = record.source,
        hidden = record.hidden or nil,
    }
end

-- The roster is stored keyed by GUID, which JSON handles fine but which is
-- awkward to iterate in a reader. It goes out as a list.
local function CopyRaid(session)
    local roster = {}

    for key, member in pairs(session.roster or {}) do
        table.insert(roster, {
            key = key,
            guid = member.guid,
            name = member.name,
            fullName = member.fullName,
            class = member.class,
            guildRank = member.guildRank,
            firstSeen = member.firstSeen,
            lastSeen = member.lastSeen,
            encounters = member.encounters,
        })
    end

    local encounters = {}

    for _, encounter in ipairs(session.encounters or {}) do
        table.insert(encounters, {
            encounterID = encounter.encounterID,
            name = encounter.name,
            difficultyID = encounter.difficultyID,
            groupSize = encounter.groupSize,
            killed = encounter.killed,
            at = encounter.at,
        })
    end

    return {
        id = session.id,
        instanceID = session.instanceID,
        instanceName = session.instanceName,
        difficultyID = session.difficultyID,
        difficultyName = session.difficultyName,
        startedAt = session.startedAt,
        endedAt = session.endedAt,
        dateText = session.dateText,
        rosterCount = session.rosterCount,
        recordedBy = session.recordedBy,
        encounters = encounters,
        roster = roster,
    }
end

local function CopySeason(season, isActive)
    local drops = {}
    local loot = {}
    local raids = {}

    for _, record in ipairs(season.drops or {}) do
        table.insert(drops, CopyDrop(record))
    end

    for _, record in ipairs(season.loot or {}) do
        table.insert(loot, CopyChatRecord(record))
    end

    for _, session in ipairs(season.raids or {}) do
        table.insert(raids, CopyRaid(session))
    end

    return {
        id = season.id,
        name = season.name,
        active = isActive or nil,
        startedAt = season.startedAt,
        archivedAt = season.archivedAt,

        drops = drops,
        loot = loot,
        raids = raids,
    }
end

function DataExport.BuildTable()
    local seasons = {}

    local active = SYL.GetActiveSeason()

    if active then
        table.insert(seasons, CopySeason(active, true))
    end

    for _, season in ipairs(SYL.GetArchives()) do
        table.insert(seasons, CopySeason(season, false))
    end

    local exportedAt = time()

    return {
        schemaVersion = DataExport.SCHEMA_VERSION,
        addonVersion = SYL.version,

        exportedAt = exportedAt,
        exportedAtText = SYL.Utilities.FormatDateTime(exportedAt),
        exportedBy = SYL.Utilities.GetPlayerFullName(),

        guild = {
            name = SYL.Guild.GetGuildName(),
            memberCount = SYL.Guild.GetMemberCount(),
        },

        seasons = seasons,
    }
end

function DataExport.BuildJSON()
    return SYL.Serializer.ToJSON(DataExport.BuildTable())
end

-- Rough size, so the export window can warn before handing over something
-- too large to paste comfortably.
function DataExport.CountRecords()
    local drops, rolls, raids = 0, 0, 0

    for _, season in ipairs(SYL.GetArchives()) do
        drops = drops + #(season.drops or {})
        raids = raids + #(season.raids or {})
    end

    local active = SYL.GetActiveSeason()

    if active then
        drops = drops + #(active.drops or {})
        raids = raids + #(active.raids or {})
    end

    for _, record in ipairs(SYL.GetAllDrops()) do
        rolls = rolls + #(record.rolls or {})
    end

    return { drops = drops, rolls = rolls, raids = raids }
end
