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
-- Lu'ashal is 3454 as an encounter and 2827 in the journal. Passing one where
-- the other belongs does not fail, it silently returns a different boss's
-- loot. EJ_GetEncounterInfoByIndex returns both, which is the only bridge
-- between them.
--
-- THE INSTANCE HAS TO BE SELECTED, NOT JUST NAMED. EJ_GetEncounterInfoByIndex
-- takes a journalInstanceID as an optional second argument, but the encounter
-- list is built from the current selection and passing the id alone returns
-- nothing. That cost an afternoon: the walk completed, found zero bosses, and
-- reported success.
--
-- TIERS ARE WALKED NEWEST FIRST, AND ONLY AS FAR AS NEEDED. Walking all
-- thirteen stutters the game for several seconds, and a guild raiding current
-- content needs exactly one of them. A boss that is not found pulls in the
-- next tier back, so older seasons still resolve — they just pay for it.
--
-- READING THE JOURNAL MOVES IT. Selecting a tier, instance, difficulty or
-- encounter changes what the player is looking at, so the selection is put
-- back afterwards.
--
-- Everything here is lazy and defensive. A journal that will not load, or an
-- API that has moved, produces nothing and a debug line rather than an error
-- in the middle of a raid.

local SYL = _G.ShowUsYourLoot

local LootTable = {}
SYL.LootTable = LootTable

local JOURNAL_ADDON = "Blizzard_EncounterJournal"

-- dungeonEncounterID -> { journalEncounterID, journalInstanceID, name }
local bridge = {}

-- Counts down. nil means the walk has not started; 0 means every tier has
-- been read and anything still missing is genuinely not a raid boss.
local nextTier
local tierCount = 0
local journalFailed = false

-- "journalEncounterID:difficultyID" -> list of items
local lootCache = {}

local function Loaded()
    if journalFailed then
        return false
    end

    if _G.EncounterJournal then
        return true
    end

    local load = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn

    if not load then
        journalFailed = true

        return false
    end

    local ok = pcall(load, JOURNAL_ADDON)

    if not ok or not _G.EncounterJournal then
        journalFailed = true

        SYL:DebugPrint("The Encounter Journal would not load.")

        return false
    end

    return true
end

-- Raids only. Dungeon and delve tables are large, change every season, and
-- nothing here asks about them: drops are recorded per raid night.
local function WalkSelectedTier()
    local found = 0
    local index = 1

    while true do
        local journalInstanceID = EJ_GetInstanceByIndex(index, true)

        if not journalInstanceID then
            break
        end

        EJ_SelectInstance(journalInstanceID)

        local encounterIndex = 1

        while true do
            local name, _, journalEncounterID, _, _, _, dungeonEncounterID =
                EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)

            if not journalEncounterID then
                break
            end

            -- Older journal entries predate dungeonEncounterID and return
            -- nil. Those bosses get no bridge, which reads downstream as "no
            -- loot table known" rather than as a wrong one.
            if dungeonEncounterID and not bridge[dungeonEncounterID] then
                bridge[dungeonEncounterID] = {
                    journalEncounterID = journalEncounterID,
                    journalInstanceID = journalInstanceID,
                    name = name,
                }

                found = found + 1
            end

            encounterIndex = encounterIndex + 1
        end

        index = index + 1
    end

    return found
end

-- Reads one more tier, newest first. Returns false when there are none left.
local function WalkNextTier()
    if not Loaded() then
        return false
    end

    if not nextTier then
        tierCount = EJ_GetNumTiers and EJ_GetNumTiers() or 0
        nextTier = tierCount
    end

    if nextTier < 1 then
        return false
    end

    local tier = nextTier
    nextTier = nextTier - 1

    local ok, err = pcall(function()
        local previousTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil

        EJ_SelectTier(tier)
        WalkSelectedTier()

        if previousTier then
            EJ_SelectTier(previousTier)
        end
    end)

    if not ok then
        SYL:DebugPrint("Journal walk error on tier " .. tier .. ": "
            .. tostring(err))
    end

    return true
end

-- The bridge entry for a boss, reading further back through the tiers until
-- it turns up or they run out.
local function Find(dungeonEncounterID)
    if not dungeonEncounterID then
        return nil
    end

    if bridge[dungeonEncounterID] then
        return bridge[dungeonEncounterID]
    end

    while WalkNextTier() do
        if bridge[dungeonEncounterID] then
            return bridge[dungeonEncounterID]
        end
    end

    return nil
end

-- True once the journal has opened and the newest tier has produced bosses.
-- An empty result is a failure, not a success: the first version returned the
-- table either way and only checked for nil, so a walk that found nothing
-- reported itself as working and every row showed a dash with no explanation.
function LootTable.IsAvailable()
    if not Loaded() then
        return false
    end

    if not next(bridge) then
        WalkNextTier()
    end

    return next(bridge) ~= nil
end

-- Whether anything has been read already, without reading any more.
--
-- IsAvailable walks a tier when it finds nothing, which is the right
-- behaviour for a button press and the wrong one for a mouseover: hovering a
-- row must never cost several seconds.
function LootTable.IsReady()
    return next(bridge) ~= nil
end

function LootTable.Describe()
    if journalFailed then
        return "the Encounter Journal would not load"
    end

    local count = 0

    for _ in pairs(bridge) do
        count = count + 1
    end

    if count == 0 then
        return "no bosses read yet"
    end

    local walked = tierCount - (nextTier or tierCount)

    return count .. " bosses from " .. walked
        .. (walked == 1 and " tier" or " tiers")
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
function LootTable.GetItems(dungeonEncounterID, difficultyID)
    local entry = Find(dungeonEncounterID)

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
-- showing "2 of 6" needs all three.
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
