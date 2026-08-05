-- Core/LootHistoryStore.lua
--
-- Permanent storage for group-loot drops captured from Blizzard's Loot
-- History API. This is the primary loot record; chat capture stays on as a
-- fallback for everything Loot History does not see.
--
-- Writes are idempotent. LOOT_HISTORY_UPDATE_DROP fires hundreds of times per
-- boss, so the same drop is offered over and over; each one upserts against a
-- stable id rather than appending a duplicate.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Store = {}
SYL.LootHistoryStore = Store

-- Rebuilt in memory at login rather than saved, so SavedVariables stays free
-- of derived data.
local dropIndex = {}

-- lootListID is unique per drop within one encounter, but repeats the next
-- time the same boss is pulled. runID pins a record to a single pull.
local function BuildRecordID(snapshot, drop)
    return table.concat({
        tostring(snapshot.runID or 0),
        tostring(snapshot.encounterID or 0),
        tostring(drop.lootListID or 0),
    }, "-")
end

-- A drop is only worth storing once its roll has resolved. Mid-roll the
-- winner is absent, and currentLeader cannot stand in for it: on a tie it
-- names a different player than the one who eventually wins.
local function IsComplete(drop)
    if drop.allPassed then
        return true
    end

    return drop.winnerGUID ~= nil or drop.winnerName ~= nil
end

-- false and nil both read as "no" later, so the falsey fields are left unset
-- to keep the saved file smaller. Twenty-five of these are stored per drop.
local function BuildRolls(players)
    local rolls = {}

    for _, player in ipairs(players or {}) do
        -- Rank index rather than the rank name: it is a number instead of a
        -- repeated string, and 25 of these are saved per drop. Non-members
        -- store nothing at all.
        local rankIndex = SYL.Guild.GetRankIndex(player.guid, player.name)

        table.insert(rolls, {
            name = player.name,
            guid = player.guid,
            class = player.class,
            guildRankIndex = rankIndex,

            state = player.rollState,
            stateText = player.rollStateText,

            -- Absent for Pass, Transmog and NoRoll: they never rolled.
            roll = player.roll,

            isWinner = player.isWinner or nil,
        })
    end

    return rolls
end

local function BuildRecord(recordID, snapshot, drop, season, location)
    local timestamp = time()

    -- GetInstanceInfo is authoritative for difficulty and gives a readable
    -- name; the encounter event args are only a fallback.
    local difficultyID = location.difficultyID

    if not difficultyID or difficultyID == 0 then
        difficultyID = snapshot.difficultyID
    end

    return {
        id = recordID,

        seasonID = season.id,
        seasonName = season.name,

        runID = snapshot.runID,
        encounterID = snapshot.encounterID,
        encounterName = snapshot.encounterName,

        difficultyID = difficultyID,
        difficultyName = location.difficultyName,
        groupSize = snapshot.groupSize or location.instanceGroupSize,

        instanceID = location.instanceID,
        instanceName = location.instanceName,
        zoneName = location.zoneName,

        lootListID = drop.lootListID,
        itemID = drop.itemID,
        itemName = drop.itemName,
        itemLink = drop.itemHyperlink,

        winnerName = drop.winnerName,
        winnerGUID = drop.winnerGUID,
        winnerClass = drop.winnerClass,
        winnerRoll = drop.winnerRoll,

        -- A transmog win is not an upgrade. Fairness maths has to be able to
        -- tell them apart, so the state is stored, not just the winner.
        winnerState = drop.winnerState,

        -- Captured now rather than looked up later, because ranks change and
        -- history should show what was true when the item dropped.
        winnerGuildRank = SYL.Guild.GetRank(drop.winnerGUID, drop.winnerName),
        winnerGuildRankIndex =
            SYL.Guild.GetRankIndex(drop.winnerGUID, drop.winnerName),
        guildName = SYL.Guild.GetGuildName(),

        allPassed = drop.allPassed or nil,

        rolls = BuildRolls(drop.players),
        eligibleCount = #(drop.players or {}),

        timestamp = timestamp,
        dateText = date("%Y-%m-%d", timestamp),
        timeText = date("%H:%M:%S", timestamp),

        recordedBy = Utilities.GetPlayerFullName(),
        source = "LOOT_HISTORY",

        -- Display state only, always reversible. Separate from
        -- excludedFromAnalytics, which affects fairness maths.
        hidden = false,
        excludedFromAnalytics = false,
    }
end

-- A drop can resolve in stages, so an existing record takes the newer roll
-- data while keeping the timestamp of when it was first seen.
local function UpdateRecord(record, drop)
    record.winnerName = drop.winnerName or record.winnerName
    record.winnerGUID = drop.winnerGUID or record.winnerGUID
    record.winnerClass = drop.winnerClass or record.winnerClass
    record.winnerRoll = drop.winnerRoll or record.winnerRoll
    record.winnerState = drop.winnerState or record.winnerState
    record.allPassed = drop.allPassed or record.allPassed

    if drop.winnerGUID or drop.winnerName then
        record.winnerGuildRank =
            SYL.Guild.GetRank(drop.winnerGUID, drop.winnerName)
            or record.winnerGuildRank
    end

    local rolls = BuildRolls(drop.players)

    -- Never trade a fuller roll list for an emptier one.
    if #rolls >= #(record.rolls or {}) then
        record.rolls = rolls
        record.eligibleCount = #rolls
    end

    record.updatedAt = time()
end

local function AnnounceDrop(record)
    if not ShowUsYourLootDB.settings.announceCaptures then
        return
    end

    local outcome

    if record.allPassed then
        outcome = "everyone passed"
    else
        outcome =
            SYL.colors.addon
            .. tostring(record.winnerName)
            .. SYL.colors.reset
            .. (record.winnerRoll and (" (" .. record.winnerRoll .. ")") or "")
    end

    print(
        SYL.colors.highlight
        .. "[SYL]"
        .. SYL.colors.reset
        .. " "
        .. tostring(record.encounterName or "Unknown boss")
        .. ": "
        .. tostring(record.itemLink or record.itemName or "Unknown item")
        .. " to "
        .. outcome
    )
end

function Store.RebuildIndex()
    dropIndex = {}

    for _, record in ipairs(SYL.GetActiveDrops()) do
        if record.id then
            dropIndex[record.id] = record
        end
    end
end

function Store.IsEnabled()
    return ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.lootHistoryCapture
        and true
        or false
end

-- Returns how many records were added and how many were refreshed.
function Store.RecordSnapshot(snapshot)
    if not snapshot or not snapshot.encounterID then
        return 0, 0
    end

    if not Store.IsEnabled() then
        return 0, 0
    end

    local season = SYL.GetActiveSeason()

    if not season then
        return 0, 0
    end

    local drops = SYL.GetActiveDrops()
    local location = Utilities.GetLocationInformation()

    local added, updated = 0, 0

    for _, drop in ipairs(snapshot.drops or {}) do
        if IsComplete(drop)
            and SYL.ItemQuality.ShouldTrackLink(drop.itemHyperlink)
        then
            local recordID = BuildRecordID(snapshot, drop)
            local existing = dropIndex[recordID]

            if existing then
                UpdateRecord(existing, drop)
                updated = updated + 1
            else
                local record =
                    BuildRecord(recordID, snapshot, drop, season, location)

                table.insert(drops, record)
                dropIndex[recordID] = record

                added = added + 1

                AnnounceDrop(record)
            end
        end
    end

    if added > 0 then
        SYL:DebugPrint(
            "Stored " .. added .. " drop(s) for encounter "
            .. tostring(snapshot.encounterID)
        )

        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end

    return added, updated
end

function Store.GetCounts()
    local drops = SYL.GetActiveDrops()
    local rolls, hidden = 0, 0

    for _, record in ipairs(drops) do
        rolls = rolls + #(record.rolls or {})

        if record.hidden then
            hidden = hidden + 1
        end
    end

    return {
        active = #drops,
        allTime = #SYL.GetAllDrops(),
        rolls = rolls,
        hidden = hidden,
    }
end
