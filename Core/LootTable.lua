-- Core/LootTable.lua
--
-- What a boss *can* drop, read from the Encounter Journal, so the boss window
-- can answer "which items have we never seen".
--
-- NOTES.md listed this as blocked on needing a loot table to compare against.
-- The journal is that table, and it ships with the client.
--
-- TWO ID SPACES, AND THEY ARE NOT THE SAME NUMBER:
--
--   * ENCOUNTER_START and the loot history give a *dungeonEncounterID*, which
--     is what BossStats keys on.
--   * EJ_SelectEncounter takes a *journalEncounterID*.
--
-- Passing one where the other belongs silently returns another boss's loot,
-- which is worse than returning nothing. EJ_GetEncounterInfoByIndex returns
-- both, so the bridge is built once by walking the journal and kept in
-- memory.
--
-- READING THE JOURNAL MOVES IT. EJ_SelectInstance, EJ_SelectEncounter and
-- EJ_SetDifficulty change what the player is looking at. If their journal is
-- open when this runs, it would jump to whatever was queried last, so the
-- selection is saved and put back.
--
-- Everything here is lazy and defensive. A journal that will not load, or an
-- API that has moved, produces an empty table and a debug line rather than an
-- error in the middle of a raid.

local SYL = _G.ShowUsYourLoot

local LootTable = {}
SYL.LootTable = LootTable

local JOURNAL_ADDON = "Blizzard_EncounterJournal"

-- dungeonEncounterID -> { journalEncounterID, journalInstanceID, name }
local bridge
local bridgeFailed = false

-- "journalEncounterID:difficultyID" -> list of items
local lootCache = {}

local function Loaded()
    if _G.EncounterJournal then
        return true
    end

    local load = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn

    if not load then
        return false
    end

    local ok = pcall(load, JOURNAL_ADDON)

    return ok and _G.EncounterJournal ~= nil
end

-- Raids only. Dungeon and delve tables are large, change every season, and
-- nothing in this addon asks about them: drops are recorded per raid night.
local function WalkTier(map)
    local index = 1

    while true do
        local journalInstanceID = EJ_GetInstanceByIndex(index, true)

        if not journalInstanceID then
            break
        end

        local encounterIndex = 1

        while true do
            local name, _, journalEncounterID, _, _, _, dungeonEncounterID =
                EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)

            if not journalEncounterID then
                break
            end

            -- Older journal entries predate dungeonEncounterID and return
            -- nil for it. Those bosses simply have no bridge, which reads
            -- downstream as "no loot table known" rather than as a wrong one.
            if dungeonEncounterID then
                map[dungeonEncounterID] = {
                    journalEncounterID = journalEncounterID,
                    journalInstanceID = journalInstanceID,
                    name = name,
                }
            end

            encounterIndex = encounterIndex + 1
        end

        index = index + 1
    end
end

-- Built once per session and held in memory, never saved: it is derived from
-- client data that changes with every patch, and a stale copy on disk would
-- outlive the patch that made it wrong.
function LootTable.BuildBridge()
    if bridge or bridgeFailed then
        return bridge
    end

    if not Loaded() then
        bridgeFailed = true

        SYL:DebugPrint(
            "The Encounter Journal would not load, so loot tables are off."
        )

        return nil
    end

    local map = {}

    local ok = pcall(function()
        local tiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
        local currentTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil

        for tier = 1, tiers do
            EJ_SelectTier(tier)
            WalkTier(map)
        end

        if currentTier then
            EJ_SelectTier(currentTier)
        end
    end)

    if not ok then
        bridgeFailed = true

        SYL:DebugPrint("Walking the Encounter Journal failed.")

        return nil
    end

    bridge = map

    return bridge
end

function LootTable.IsAvailable()
    return LootTable.BuildBridge() ~= nil
end

-- The journal shows one difficulty at a time and its loot changes with it,
-- so the difficulty is part of the cache key.
local function CacheKey(journalEncounterID, difficultyID)
    return tostring(journalEncounterID) .. ":" .. tostring(difficultyID or 0)
end

-- Reads whatever the journal is currently showing, so the caller is
-- responsible for having selected the instance, difficulty and encounter.
local function ReadLoot()
    local items = {}

    local count = EJ_GetNumLoot and EJ_GetNumLoot() or 0

    for index = 1, count do
        local info = C_EncounterJournal.GetLootInfoByIndex(index)

        -- The journal lists an item per armour type for shared tokens, and
        -- only entries carrying an itemID are usable here.
        if info and info.itemID then
            table.insert(items, {
                itemID = info.itemID,
                name = info.name,
                link = info.link,
                slot = info.slot,
                armorType = info.armorType,
            })
        end
    end

    return items
end

-- Returns a list of { itemID, name, link, slot, armorType }, or nil when the
-- boss is not in the journal.
function LootTable.GetItems(dungeonEncounterID, difficultyID)
    local map = LootTable.BuildBridge()

    if not map or not dungeonEncounterID then
        return nil
    end

    local entry = map[dungeonEncounterID]

    if not entry then
        return nil
    end

    local key = CacheKey(entry.journalEncounterID, difficultyID)

    if lootCache[key] then
        return lootCache[key]
    end

    local items

    -- Saved and restored because these calls move what the player is looking
    -- at, and this can run while their journal is open.
    local ok = pcall(function()
        local previousInstance = EJ_GetCurrentInstance and
            EJ_GetCurrentInstance() or nil
        local previousDifficulty = EJ_GetDifficulty and
            EJ_GetDifficulty() or nil

        EJ_SelectInstance(entry.journalInstanceID)

        if difficultyID and EJ_SetDifficulty then
            EJ_SetDifficulty(difficultyID)
        end

        EJ_SelectEncounter(entry.journalEncounterID)

        items = ReadLoot()

        if previousInstance then
            EJ_SelectInstance(previousInstance)
        end

        if previousDifficulty and EJ_SetDifficulty then
            EJ_SetDifficulty(previousDifficulty)
        end
    end)

    if not ok or not items then
        SYL:DebugPrint(
            "Could not read the loot table for encounter "
            .. tostring(dungeonEncounterID)
        )

        return nil
    end

    lootCache[key] = items

    return items
end

-- What the journal lists that this guild has never seen drop.
--
-- Matching is by item name, because that is what drop records store
-- alongside the id and what BossStats already counts by. Returns the missing
-- items, how many the table holds, and how many have been seen — a caller
-- showing "3 of 11 never dropped" needs all three.
function LootTable.GetMissing(boss)
    if not boss then
        return nil
    end

    local items = LootTable.GetItems(boss.encounterID, boss.difficultyID)

    if not items or #items == 0 then
        return nil
    end

    local seen = {}

    for name in pairs(boss.itemCounts or {}) do
        seen[name] = true
    end

    local missing = {}

    for _, item in ipairs(items) do
        -- The journal decorates names with colour codes; drop records do not.
        local plain = item.name
            and item.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            or nil

        if plain and not seen[plain] then
            table.insert(missing, {
                itemID = item.itemID,
                name = plain,
                link = item.link,
                slot = item.slot,
            })
        end
    end

    table.sort(missing, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return missing, #items, #items - #missing
end
