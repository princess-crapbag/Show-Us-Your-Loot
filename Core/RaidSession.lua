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
--
-- syl-check: size-exempt — one night is a surprisingly contested idea, and
-- the reasons live next to the code that acts on them. Sessions, the roster
-- read, night identity and attendance are the same subject: split them and
-- the next person to fix a counting bug has to find three files to know what
-- a night is. The overage is comment.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local RaidSession = {}
SYL.RaidSession = RaidSession

local currentSessionID

-- One session per instance, difficulty and day. Re-entering the same raid the
-- same evening continues the night rather than starting a second one.
--
-- Difficulty stays in the key deliberately. A guild that clears Heroic and
-- then pushes Mythic has done two different things and the record should say
-- so — the encounters, the kills and the group size all differ. What must not
-- happen is that being there for both counts as two nights of attendance,
-- and that is fixed where nights are counted rather than by throwing the
-- distinction away here. See NightKey.
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

                    -- What the group has them queued as. Remembered as a
                    -- starting point for the roster window; a role chosen
                    -- by hand always wins.
                    role = UnitGroupRolesAssigned
                        and UnitGroupRolesAssigned(unit) or nil,
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

    -- And only inside a raid. inInstance is true for dungeons too, so every
    -- Mythic+ run was opening a raid night and putting its five people into
    -- the attendance roster. The due list ranks by nights attended, so a
    -- guild that runs keys together was being ranked partly on dungeons.
    if not Utilities.IsRaidContent(
        location.instanceType, location.difficultyID
    ) then
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
        instanceType = location.instanceType,
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
            SYL.RaidTeam.RememberDetectedRole(member.guid, member.role)

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

-- Sessions recorded before dungeons were excluded are still in the database,
-- and deleting history to fix a counting bug is the wrong trade. They are
-- filtered at read time instead, so the numbers correct themselves and the
-- record of what happened stays intact.
function RaidSession.IsRaidSession(session)
    if not session then
        return false
    end

    return Utilities.IsRaidContent(
        session.instanceType, session.difficultyID
    )
end

-- One evening in one raid, whatever difficulties it passed through.
--
-- Sessions are keyed by difficulty as well as date, so a night that cleared
-- Heroic and then pulled Mythic is two of them. Every count of "nights
-- attended" iterated sessions, so turning up to both halves of one Tuesday
-- registered as twice the attendance of somebody who came to one — and
-- nightsSinceUpgrade, the sole ranking key of the due list, moved twice as
-- fast for them. The people most likely to be there for both are the raiders
-- who never miss, so the error landed hardest on exactly the wrong people.
--
-- Fixed at read time rather than by merging the sessions, for the same reason
-- dungeon sessions are filtered rather than deleted: the record of what
-- happened stays intact and the numbers correct themselves on existing
-- history instead of only on nights recorded from now on.
--
-- dateText is preferred over recomputing from startedAt because a raid that
-- runs past midnight already has one, written when the session opened.
function RaidSession.NightKey(session)
    if not session then
        return nil
    end

    return table.concat({
        tostring(session.instanceID or 0),
        session.dateText or date("%Y-%m-%d", session.startedAt or 0),
    }, "-")
end

-- How many distinct nights a list of sessions represents.
function RaidSession.CountNights(sessions)
    local seen, total = {}, 0

    for _, session in ipairs(RaidSession.RaidsOnly(sessions)) do
        local key = RaidSession.NightKey(session)

        if key and not seen[key] then
            seen[key] = true
            total = total + 1
        end
    end

    return total
end

-- The raid nights out of a list that also holds dungeon ones.
--
-- STILL USED, AND ONLY BY THE FAIRNESS MATH — Core/DueList.lua, for attendance
-- and droughts. Everything a person looks at goes through NightsOnly below,
-- which is stricter. That split is deliberate and it is temporary.
--
-- The reason for it: narrowing the display to guild nights hides rows.
-- Narrowing the fairness math to guild nights *rewrites recorded attendance* —
-- an LFR night somebody turned up to stops counting, every share is divided by
-- a smaller number, and the drop side has to adopt the same test in the same
-- change or an LFR win resets a drought on a night the addon says never
-- happened. Aimee asked for the calendar and the dashboard. She did not ask
-- for her raiders' numbers to move, and that is not a side effect to deliver
-- as one.
--
-- Whoever closes this: the two must move together, and the answer wanted first
-- is whether it applies to history or only from that day on.
function RaidSession.RaidsOnly(sessions)
    local kept = {}

    for _, session in ipairs(sessions or {}) do
        if RaidSession.IsRaidSession(session) then
            table.insert(kept, session)
        end
    end

    return kept
end

--------------------------------------------------------------------------
-- Whose night was it
--------------------------------------------------------------------------

-- Aimee's number, chosen after her first raid night rather than by me: a night
-- belongs to the guild when at least this share of the people there were in
-- it. She raised it from the 60% I suggested.
--
-- A threshold rather than unanimity, because a real Tuesday has a pug tank and
-- a trial in it, and a rule that eighty percent clears is one those nights
-- still pass.
RaidSession.GUILD_SHARE = 0.80

-- Whether the guild roster had actually loaded when this session was recorded.
--
-- THIS IS THE WHOLE DIFFICULTY. A member with no guildRank is either not in
-- the guild or was recorded before the client answered — and the second reads
-- exactly like a pug raid, so without a way to tell them apart the safe rule
-- would have to be "count everything" and the filter would do nothing.
--
-- The person who recorded the session settles it. They are running this addon,
-- they were standing there, and their own rank is the one the client answers
-- first. If theirs is missing the roster had not arrived and no count from
-- that session means anything; if theirs is present, so is everyone else's who
-- had one. Checked against Aimee's two recorded nights: the LFR run reports
-- 1 of 49 and the guild Normal 12 of 12, and the recorder carries a rank in
-- both — so the 2% is real information rather than an empty roster.
-- MIND THE NAME FORM. `recordedBy` carries the realm — "Arcangila-Area52",
-- from Utilities.GetPlayerFullName — and a roster member's `name` and
-- `fullName` are both the bare "Arcangila" for somebody on your own realm. The
-- first version of this compared them directly, found nobody, and reported the
-- guild share of every night as unknown, which quietly turned the whole filter
-- off. Caught against Aimee's real data rather than in review, and it is the
-- same class of mismatch the keystone code is suspected of.
local function SameCharacter(member, recordedBy)
    local short = recordedBy:match("^([^-]+)") or recordedBy

    return member.fullName == recordedBy
        or member.name == recordedBy
        or member.fullName == short
        or member.name == short
end

local function GuildDataIsTrustworthy(session)
    local recordedBy = session and session.recordedBy

    if type(recordedBy) ~= "string" or recordedBy == "" then
        return false
    end

    for _, member in pairs(session.roster or {}) do
        if SameCharacter(member, recordedBy) then
            return member.guildRank ~= nil
        end
    end

    return false
end

-- What share of the people there were in the guild, or nil when the client
-- never said. nil means "unknown", which is not the same as zero and must not
-- be read as one.
function RaidSession.GuildShare(session)
    if not GuildDataIsTrustworthy(session) then
        return nil
    end

    local total, guilded = 0, 0

    for _, member in pairs(session.roster or {}) do
        total = total + 1

        if member.guildRank then
            guilded = guilded + 1
        end
    end

    if total == 0 then
        return nil
    end

    return guilded / total
end

-- ONE PREDICATE, ASKED BY EVERY SURFACE THAT COUNTS NIGHTS.
--
-- Raid content, and the guild's own. The two used to be one test and the
-- calendar, the dashboard and the boss tiles each decided separately whether
-- to apply it — which is why a 49-person LFR run and a 12-person guild raid
-- on the same evening were added together into "60 raiders".
--
-- Unknown counts. A session recorded before the guild roster loaded is not
-- evidence of a pug, and the addon already treats missing bind and location
-- data the same way: the rule is that absent information never removes a
-- night somebody actually turned up to.
function RaidSession.CountsAsNight(session)
    if not RaidSession.IsRaidSession(session) then
        return false
    end

    local share = RaidSession.GuildShare(session)

    if share == nil then
        return true
    end

    return share >= RaidSession.GUILD_SHARE
end

function RaidSession.NightsOnly(sessions)
    local kept = {}

    for _, session in ipairs(sessions or {}) do
        if RaidSession.CountsAsNight(session) then
            table.insert(kept, session)
        end
    end

    return kept
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
-- reopening one already summarized.
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

    -- Keyed by night rather than reset per session, so a Heroic clear and the
    -- Mythic pulls after it on the same evening are one night present.
    local countedOn = {}

    for _, session in ipairs(RaidSession.RaidsOnly(sessions)) do
        local nightKey = RaidSession.NightKey(session)

        countedOn[nightKey] = countedOn[nightKey] or {}

        local countedTonight = countedOn[nightKey]

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
