-- Core/LootTable.lua
--
-- What a boss *can* drop, read from the Encounter Journal, so the boss window
-- can answer "which items have we never seen".
--
-- NOTES.md listed this as blocked on needing a loot table to compare against.
-- The journal is that table, and it ships with the client.
--
-- Finding the boss in the journal at all is Core/EncounterJournal.lua, which
-- owns the two id spaces and the tier walk. This file takes it from there:
-- select the encounter, read its loot, and diff that against what the guild
-- has actually seen.
--
-- READING THE JOURNAL MOVES IT. Selecting an instance, difficulty or
-- encounter changes what the player is looking at, so the selection is put
-- back afterwards.
--
-- NOTHING HERE MAY BE SLOW ON A MOUSEOVER. GetMissingIfKnown answers from
-- what has already been read; GetMissing is allowed to go and read more, and
-- belongs to a button.

local SYL = _G.ShowUsYourLoot

local LootTable = {}
SYL.LootTable = LootTable

-- "journalEncounterID:difficultyID" -> list of items, or false for a read
-- that failed. false rather than nil so a failure is remembered instead of
-- being retried on every hover.
local lootCache = {}

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

        -- The journal lists an entry per armour type for shared tokens, and
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
local function GetItems(dungeonEncounterID, difficultyID, mayWalk)
    local entry = SYL.EncounterJournal.Find(dungeonEncounterID, mayWalk)

    if not entry then
        return nil
    end

    local key = CacheKey(entry.journalEncounterID, difficultyID)
    local cached = lootCache[key]

    if cached ~= nil then
        return cached or nil
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

        -- Remembered as a failure, so a journal that will not answer for this
        -- boss is asked once rather than on every hover.
        lootCache[key] = false

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
-- showing "2 of 6" needs all three.
local function GetMissing(boss, mayWalk)
    if not boss then
        return nil
    end

    local items = GetItems(boss.encounterID, boss.difficultyID, mayWalk)

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

-- For a button press: may read further tiers to answer.
function LootTable.GetMissing(boss)
    return GetMissing(boss, true)
end

-- For a mouseover: answers from what has already been read and never reads
-- more. IsReady was supposed to guarantee this and could not, because it only
-- checks whether *anything* has been read — after which a boss missing from
-- what was read still sent Find off through every remaining tier.
function LootTable.GetMissingIfKnown(boss)
    return GetMissing(boss, false)
end
