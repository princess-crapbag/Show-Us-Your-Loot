-- Core/RaidSession.lua
--
-- Raid nights: when they happened, which bosses were pulled, and who was
-- actually in the group.
--
-- This exists because eligibility is not attendance. Roll lists only name
-- players a specific item could drop for, so a healer who raided all night
-- without being eligible for one drop would look absent. The roster is read
-- from the group itself instead.
--
-- Sessions live in activeSeason.raids, a table the database has always
-- created and never used.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local RaidSession = {}
SYL.RaidSession = RaidSession

local currentSessionID

-- One session per instance, difficulty and day. Re-entering the same raid the
-- same evening continues the night rather than starting a second one.
local function BuildSessionID(location, timestamp)
    return table.concat({
        "raid",
        tostring(location.instanceID or 0),
        tostring(location.difficultyID or 0),
        date("%Y%m%d", timestamp),
    }, "-")
end

local function FindSession(sessionID)
    for _, session in ipairs(SYL.GetActiveRaids()) do
        if session.id == sessionID then
            return session
        end
    end

    return nil
end

-- Reads the live group rather than the loot data. GUID is the key, since
-- names repeat across realms.
local function ReadGroupRoster()
    local roster = {}
    local total = GetNumGroupMembers() or 0

    if total == 0 then
        return roster
    end

    local prefix = IsInRaid() and "raid" or "party"

    for index = 1, total do
        local unit = prefix .. index

        -- The party prefix omits the player, who is "player" instead.
        if prefix == "party" and index == total then
            unit = "player"
        end

        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            local _, classFile = UnitClass(unit)
            local guid = UnitGUID(unit)

            if name then
                local fullName = name

                if realm and realm ~= "" then
                    fullName = name .. "-" .. realm
                end

                table.insert(roster, {
                    guid = guid,
                    name = name,
                    fullName = fullName,
                    class = classFile,
                })
            end
        end
    end

    return roster
end

local function EnsureSession(timestamp)
    local location = Utilities.GetLocationInformation()

    -- Only inside an actual instance. Otherwise a world boss group or a city
    -- would open a raid night.
    if not location.inInstance then
        return nil
    end

    local sessionID = BuildSessionID(location, timestamp)
    local session = FindSession(sessionID)

    if session then
        currentSessionID = sessionID

        return session
    end

    session = {
        id = sessionID,

        seasonID = (SYL.GetActiveSeason() or {}).id,

        instanceID = location.instanceID,
        instanceName = location.instanceName,
        difficultyID = location.difficultyID,
        difficultyName = location.difficultyName,

        startedAt = timestamp,
        endedAt = timestamp,
        dateText = date("%Y-%m-%d", timestamp),

        encounters = {},
        roster = {},
        rosterCount = 0,

        recordedBy = Utilities.GetPlayerFullName(),
    }

    table.insert(SYL.GetActiveRaids(), session)

    currentSessionID = sessionID

    return session
end

-- Merged rather than replaced, so someone who was present early still counts
-- after they leave. Attendance is "were you here", not "are you here now".
local function MergeRoster(session, roster, timestamp)
    for _, member in ipairs(roster) do
        local key = member.guid or member.fullName

        if key then
            -- Every character seen in a raid enters the registry, which is
            -- what makes them available to map as an alt later. The session
            -- roster still stores the character that was actually here.
            SYL.Players.Touch(member)

            local existing = session.roster[key]

            if existing then
                existing.lastSeen = timestamp
            else
                session.roster[key] = {
                    guid = member.guid,
                    name = member.name,
                    fullName = member.fullName,
                    class = member.class,
                    guildRank = SYL.Guild.GetRank(member.guid, member.name),
                    firstSeen = timestamp,
                    lastSeen = timestamp,
                    encounters = 0,
                }

                session.rosterCount = session.rosterCount + 1
            end
        end
    end
end

local function CountEncounterForRoster(session, roster)
    for _, member in ipairs(roster) do
        local key = member.guid or member.fullName
        local entry = key and session.roster[key]

        if entry then
            entry.encounters = entry.encounters + 1
        end
    end
end

function RaidSession.OnEncounterStart(encounterID, encounterName, difficultyID)
    local timestamp = time()
    local session = EnsureSession(timestamp)

    if not session then
        return
    end

    session.endedAt = timestamp

    MergeRoster(session, ReadGroupRoster(), timestamp)

    session.pendingEncounter = {
        encounterID = encounterID,
        name = encounterName,
        difficultyID = difficultyID,
        startedAt = timestamp,
    }
end

-- The roster is read again here because this is the moment everyone who
-- fought is still grouped, and a wipe counts for attendance just as a kill
-- does.
function RaidSession.OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local timestamp = time()
    local session = EnsureSession(timestamp)

    if not session then
        return
    end

    local roster = ReadGroupRoster()

    MergeRoster(session, roster, timestamp)
    CountEncounterForRoster(session, roster)

    session.endedAt = timestamp

    table.insert(session.encounters, {
        encounterID = encounterID,
        name = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
        killed = success == 1 or success == true,
        at = timestamp,
    })

    session.pendingEncounter = nil
end

function RaidSession.GetCurrent()
    if not currentSessionID then
        return nil
    end

    return FindSession(currentSessionID)
end

function RaidSession.GetKillCount(session)
    local kills = 0

    for _, encounter in ipairs(session.encounters or {}) do
        if encounter.killed then
            kills = kills + 1
        end
    end

    return kills
end

function RaidSession.GetDurationMinutes(session)
    local seconds = (session.endedAt or 0) - (session.startedAt or 0)

    return math.max(0, math.floor(seconds / 60))
end

-- The summary lives in Core/RaidSummary.lua and needs to close the night off
-- once it has reported, so the next pull opens a fresh session rather than
-- reopening one already summarised.
function RaidSession.ClearCurrent()
    currentSessionID = nil
end

-- Every player seen in any session, with how many nights they were present.
-- This is the attendance the loot data on its own cannot answer.
--
-- Keys are folded to mains, so this counts people rather than characters.
-- Pulls still add up across every character they brought — someone who
-- swapped mid-night fought in all of those pulls — but the night itself
-- counts once, or turning up on an alt would inflate attendance.
function RaidSession.BuildAttendance(sessions)
    local byKey = {}
    local order = {}

    for _, session in ipairs(sessions or {}) do
        local countedTonight = {}

        for rawKey, member in pairs(session.roster or {}) do
            local key = SYL.Players.ResolveToMain(rawKey)
            local entry = byKey[key]

            if not entry then
                local player = SYL.Players.Get(key)

                entry = {
                    key = key,
                    guid = (player and player.guid) or member.guid,
                    name = (player and player.name) or member.name,
                    class = (player and player.class) or member.class,
                    nights = 0,
                    encounters = 0,
                    lastSeen = nil,
                }

                byKey[key] = entry

                table.insert(order, entry)
            end

            if not countedTonight[key] then
                countedTonight[key] = true

                entry.nights = entry.nights + 1
            end

            entry.encounters = entry.encounters + (member.encounters or 0)

            if not entry.lastSeen or (member.lastSeen or 0) > entry.lastSeen then
                entry.lastSeen = member.lastSeen
            end
        end
    end

    return order, byKey
end
