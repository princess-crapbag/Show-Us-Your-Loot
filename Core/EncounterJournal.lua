-- Core/EncounterJournal.lua
--
-- The bridge between the ids the game gives us and the ids the Encounter
-- Journal wants, and the tier walk that builds it.
--
-- Split out of Core/LootTable.lua, which was doing two jobs: finding a boss
-- in the journal, and reading what that boss can drop. This is the first.
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
-- READING THE JOURNAL MOVES IT. Selecting a tier changes what the player is
-- looking at, so the selection is put back afterwards.
--
-- Everything here is lazy and defensive. A journal that will not load, or an
-- API that has moved, produces nothing and a debug line rather than an error
-- in the middle of a raid.

local SYL = _G.ShowUsYourLoot

local Journal = {}
SYL.EncounterJournal = Journal

local JOURNAL_ADDON = "Blizzard_EncounterJournal"

-- dungeonEncounterID -> { journalEncounterID, journalInstanceID, name }
local bridge = {}

-- Counts down. nil means the walk has not started; 0 means every tier has
-- been read and anything still missing is genuinely not a raid boss.
local nextTier
local tierCount = 0
local journalFailed = false

-- dungeonEncounterIDs the journal does not have, once every tier has been
-- read and the answer cannot change.
--
-- WalkSelectedTier reads raid instances only, so a dungeon boss is not merely
-- absent from the tier being read — it can never be in any of them. Find had
-- no way to know that, so hovering a dungeon row walked all thirteen tiers,
-- failed, and walked them again on the next hover.
local notInJournal = {}

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

-- The bridge entry for a boss.
--
-- mayWalk decides whether a miss is allowed to read further tiers. Pressing a
-- button may; a mouseover may not, and gets whatever has already been read.
function Journal.Find(dungeonEncounterID, mayWalk)
    if not dungeonEncounterID or notInJournal[dungeonEncounterID] then
        return nil
    end

    if bridge[dungeonEncounterID] then
        return bridge[dungeonEncounterID]
    end

    if not mayWalk then
        return nil
    end

    while WalkNextTier() do
        if bridge[dungeonEncounterID] then
            return bridge[dungeonEncounterID]
        end
    end

    -- Every tier has now been read, so nothing further can turn this up.
    -- Remembered, or the next hover pays the whole walk again for the same
    -- answer.
    notInJournal[dungeonEncounterID] = true

    return nil
end

-- True once the journal has opened and the newest tier has produced bosses.
-- An empty result is a failure, not a success: the first version returned the
-- table either way and only checked for nil, so a walk that found nothing
-- reported itself as working and every row showed a dash with no explanation.
function Journal.IsAvailable()
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
function Journal.IsReady()
    return next(bridge) ~= nil
end

function Journal.Describe()
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
