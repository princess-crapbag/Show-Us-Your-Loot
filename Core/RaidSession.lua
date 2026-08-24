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

-- When the group last zoned into a raid, and which one. See NoteArrival.
local arrival

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

        -- The moment the group zoned in, if that was seen. nil on a session
        -- that began before this was recorded, which is every session already
        -- in the database -- so anything reading it has to treat "unknown" as
        -- an ordinary answer rather than as zero.
        enteredAt = (arrival and arrival.instanceID == location.instanceID)
            and arrival.at or nil,

        -- WHO WAS HANDING OUT LOOT. Every drop on a master-looted night
        -- records the master looter as the winner, because that is what the
        -- client reports -- so without this there is no way to tell a drop
        -- somebody reviewed and kept from a drop nobody has looked at.
        lootMethod = location.lootMethod,
        masterLooter = location.masterLooter,

        encounters = {},
        roster = {},
        rosterCount = 0,

        recordedBy = Utilities.GetPlayerFullName(),
    }

    table.insert(SYL.GetActiveRaids(), session)

    currentSessionID = sessionID

    return session
end

--------------------------------------------------------------------------
-- Arriving and leaving
--------------------------------------------------------------------------

-- WHEN THE RAID ACTUALLY GOT THERE, which a session cannot know by itself.
--
-- A session is created by the first ENCOUNTER_START -- EnsureSession is
-- reachable from nowhere else -- so it opens at the first pull and can never
-- report the half hour before it. Aimee's raid is 6:30 to 9:30 and her
-- 2026-08-18 session opens at 6:42, so "2h 42m" was never the evening.
--
-- Her ask: "can we record first zone in and last zone out?"
--
-- The arrival is remembered rather than written to a session, because at the
-- moment it happens there is usually no session to write to. EnsureSession
-- claims it when it creates one, and only when the instance matches -- an
-- arrival at one raid must not stamp itself onto another.
--
-- `arrival` itself is declared at the top of the file, beside
-- currentSessionID, because EnsureSession reads it and EnsureSession is
-- above this. Declared here it was a nil global read from line 135, which
-- syl_check caught -- the same local-used-before-declaration fault this
-- repository has shipped three times.
function RaidSession.NoteArrival(timestamp, instanceID)
    if not instanceID then
        return
    end

    -- FIRST arrival, not the latest. Somebody who zones out to repair and
    -- comes back has not started the night again.
    if arrival and arrival.instanceID == instanceID then
        return
    end

    arrival = { at = timestamp, instanceID = instanceID }
end

-- The last time the group left the instance this session is in. Written
-- straight onto the session, because by now there certainly is one.
--
-- RaidSession.GetCurrent, NOT a second accessor of my own. Writing one was the
-- reflex and it is the exact trap HANDOFF.md records twice: GuildShare already
-- existed and answered a different question, and defining a second one simply
-- replaced it. GetCurrent is declared far below this line but is only called
-- at runtime, so the ordering is fine.
function RaidSession.NoteDeparture(timestamp)
    local session = RaidSession.GetCurrent()

    if not session then
        return
    end

    session.leftAt = timestamp
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

    -- WHEN THE PULL STARTED, which was already being collected and thrown
    -- away.
    --
    -- `at` is the moment the pull ENDED -- a ten-minute pull begun at 9:10
    -- is stamped 9:20 -- so a night's records could say when it finished and
    -- never how long any of it took. OnEncounterStart has been writing
    -- startedAt onto pendingEncounter since sessions existed; it was simply
    -- never carried across, so nothing could tell three minutes of fighting
    -- from three minutes of standing around.
    --
    -- Guarded on the id: ENCOUNTER_START and ENCOUNTER_END can interleave
    -- across a zone change or a disconnect, and inheriting the previous
    -- boss's start would make one pull look like an hour.
    local pending = session.pendingEncounter
    local startedAt

    if pending and pending.encounterID == encounterID then
        startedAt = pending.startedAt
    end

    table.insert(session.encounters, {
        encounterID = encounterID,
        name = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
        killed = success == 1 or success == true,
        startedAt = startedAt,
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
--
-- THE INSTANCE IS NOT PART OF THE KEY, and it used to be. Aimee, on finding
-- three guild nights where she had raided twice: "the nights showing should
-- only be showing my 80% + guild run raids. that has only happened on this
-- past tuesday and this past thursday. 2 total."
--
-- On the Thursday her guild cleared two different raids — instance 2987 and
-- instance 3004 — and with the instance in the key that one evening counted
-- as two nights. Everyone present got an extra night in the divisor and their
-- share fell for turning up, which is the same fault this key was written to
-- fix, one level further out: the comment above already says a night counts
-- once "however many difficulties the night passed through", and how many
-- raids it passed through is the same kind of detail.
--
-- A night is an evening. Two raids in one evening is one night; the same raid
-- on two evenings is two.
function RaidSession.NightKey(session)
    if not session then
        return nil
    end

    return session.dateText or date("%Y-%m-%d", session.startedAt or 0)
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
-- NO LONGER USED BY THE FAIRNESS MATH, and the split this note used to
-- describe is closed. Aimee, 2026-08-20, on finding an LFR run in her season
-- board: "why is LFR being counted? its not 80% + guild members so it doesnt
-- matter in the fairness log."
--
-- What that note asked for first was whether it applies to history or only
-- from that day on. It applies to history: her season holds exactly two
-- sessions, one LFR and one guild raid, so "from today on" would have left the
-- contamination in place until she archived — and a fairness measure that
-- knowingly carries wrong numbers forward is not one.
--
-- The two sides moved together, as that note required. Core/DueList.lua counts
-- nights through NightsOnly now, and Core/DropRules.lua drops any win from a
-- session that is not a guild night — so a night nobody is credited for cannot
-- also be a night somebody's drought was reset on.
--
-- Kept because it is still the honest answer to "which of these were raids
-- rather than dungeons", which is a different question from "which of these
-- were ours".
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
RaidSession.DEFAULT_GUILD_SHARE = 0.80

-- Kept under the old name for anything reading the default.
RaidSession.GUILD_SHARE = RaidSession.DEFAULT_GUILD_SHARE

-- HOW MUCH OF THE GROUP HAS TO BE GUILD FOR THE NIGHT TO COUNT.
--
-- Named Threshold and not Share because RaidSession.GuildShare
-- already exists and answers a different question -- what fraction of
-- one session was guild. Two functions of that name is one function:
-- the second definition wins and the first quietly stops existing.
--
-- A constant until Aimee asked for it: "a real setting. again other guilds may
-- have different expectations." Worth knowing before it is moved -- since
-- 0.4.0 this does not only decide attendance and the calendar, it gates
-- DropRules.CountsAsUpgrade, so raising it re-scores nights already raided the
-- same way changing a weight does. The settings screen says so.
--
-- Stored as a percentage because that is what the screen shows and what an
-- officer says out loud; a 0.8 in the saved variables is a number somebody
-- would eventually read as eighty.
function RaidSession.GuildThreshold()
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings
    local percent = settings and settings.guildSharePercent

    if type(percent) ~= "number" or percent < 0 or percent > 100 then
        return RaidSession.DEFAULT_GUILD_SHARE
    end

    return percent / 100
end

function RaidSession.SetGuildThreshold(percent)
    if type(percent) ~= "number" or percent < 0 or percent > 100 then
        return false
    end

    ShowUsYourLootDB = ShowUsYourLootDB or {}
    ShowUsYourLootDB.settings = ShowUsYourLootDB.settings or {}
    ShowUsYourLootDB.settings.guildSharePercent = math.floor(percent + 0.5)

    return true
end

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
-- THE TWO NUMBERS BEHIND THE SHARE: how many of the group were guilded, and
-- how many there were.
--
-- Its own function rather than two more return values on GuildShare, which
-- was the first attempt. In Lua that is harmless -- an expression adjusts a
-- call to one value -- but it is a footgun anywhere the call is not the last
-- thing in a list, and tools/test_guildnights.py subtracts directly from the
-- result and broke immediately. A function that answers a fraction should
-- answer a fraction.
--
-- Two screens were re-deriving this pair, one of them from session.rosterCount
-- -- which is maintained separately and can drift from the roster table the
-- share is computed over.
function RaidSession.GuildCounts(session)
    if not GuildDataIsTrustworthy(session) then
        return nil, nil
    end

    local total, guilded = 0, 0

    for _, member in pairs((session or {}).roster or {}) do
        total = total + 1

        if member.guildRank then
            guilded = guilded + 1
        end
    end

    if total == 0 then
        return nil, nil
    end

    return guilded, total
end

function RaidSession.GuildShare(session)
    local guilded, total = RaidSession.GuildCounts(session)

    if not total then
        return nil
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

    return share >= RaidSession.GuildThreshold()
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

--------------------------------------------------------------------------
-- Which session a drop belongs to
--------------------------------------------------------------------------

-- THE LAST SESSION THAT HAD STARTED, not the one whose window contains it.
--
-- A session's endedAt is written when the client notices the raid finish, and
-- it does not always get the chance. In Aimee's own data the LFR session is
-- recorded as ending at 17:32 and six of that run's drops are stamped after
-- it — so a startedAt..endedAt test left eleven LFR wins belonging to no
-- session at all, which is the answer that would have let them go on counting.
--
-- Matching on the difficulty the drop recorded would be simpler and wrong: the
-- rule is who was standing there, not what the instance was. A guild that runs
-- LFR together is a guild night; a Normal pug is not.
local SESSION_WINDOW = 12 * 60 * 60

function RaidSession.SessionAt(sessions, timestamp)
    if not timestamp then
        return nil
    end

    local best

    for _, session in ipairs(sessions or {}) do
        local startedAt = session.startedAt or 0

        if startedAt <= timestamp
            and timestamp - startedAt <= SESSION_WINDOW
            and (not best or startedAt > (best.startedAt or 0))
        then
            best = session
        end
    end

    return best
end

-- Was this moment part of a night the guild raided?
--
-- UNKNOWN COUNTS, the same as everywhere else here. A drop that matches no
-- session was captured before sessions were recorded, or synced from somebody
-- whose session this client never saw — neither is evidence of a pug, and the
-- rule in CountsAsNight above is that absent information never removes a night
-- somebody actually turned up to.
function RaidSession.IsGuildNightAt(timestamp)
    local session = RaidSession.SessionAt(SYL.GetActiveRaids(), timestamp)

    if not session then
        return true
    end

    return RaidSession.CountsAsNight(session)
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

-- FIRST PULL TO LAST PULL, and it is worth being clear that it is not the
-- evening. A session opens at the first ENCOUNTER_START, so this measures the
-- fighting part of the night and always has. Whatever draws it must not call
-- it time in the instance -- see PresentMinutes below for that.
function RaidSession.GetDurationMinutes(session)
    local seconds = (session.endedAt or 0) - (session.startedAt or 0)

    return math.max(0, math.floor(seconds / 60))
end

-- ZONED IN TO ZONED OUT, which is the evening as a person remembers it.
--
-- Returns nil rather than zero when either end was not recorded -- every
-- session already in the database predates this, and a zero would read as
-- "they were in and out instantly" rather than as "not known". Callers show
-- the pull span instead.
function RaidSession.PresentMinutes(session)
    local from = session and session.enteredAt
    local to = session and (session.leftAt or session.endedAt)

    if type(from) ~= "number" or type(to) ~= "number" or to < from then
        return nil
    end

    return math.floor((to - from) / 60)
end

-- HOW MUCH OF THE NIGHT WAS SPENT IN COMBAT, and how much between pulls.
--
-- Returns fighting minutes, between-pull minutes, and how many pulls could be
-- measured at all. The third number is the honest part: an encounter recorded
-- before pull starts were kept has no startedAt, so a night that is half old
-- records must say so rather than reporting half the fighting it did.
--
-- Between-pulls is measured against the PULL SPAN and not the evening,
-- because time spent outside the instance is not standing around in it.
function RaidSession.FightingMinutes(session)
    local fighting, measured, total = 0, 0, 0

    for _, encounter in ipairs((session or {}).encounters or {}) do
        total = total + 1

        local from = encounter.startedAt
        local to = encounter.at

        if type(from) == "number" and type(to) == "number" and to >= from then
            fighting = fighting + (to - from)
            measured = measured + 1
        end
    end

    if measured == 0 then
        return nil, nil, 0, total
    end

    local span = math.max(0, (session.endedAt or 0) - (session.startedAt or 0))

    return math.floor(fighting / 60),
        math.floor(math.max(0, span - fighting) / 60),
        measured,
        total
end

-- HardestFight WAS HERE AND WAS DELETED BEFORE IT EVER HAD A CALLER.
--
-- It counted pulls per boss per difficulty across one session, which is
-- exactly what Core/NightIndex.lua already builds across a whole night in
-- day.fights -- and the night is the unit every screen asks about. Two
-- functions counting the same thing over different spans is how two screens
-- come to disagree about which fight was the hard one.

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

    -- GUILD NIGHTS, not every raid. Aimee: "the board should only be tracking
    -- guild raid loot. no other loot should ever count as points ever." This
    -- read RaidsOnly, which drops dungeons and Timewalking and keeps anything
    -- else — so an LFR run and a thirty-person pug were adding nights to the
    -- roster's attendance column and putting forty strangers on it.
    --
    -- It is also the half that has to match Core/DueList.lua, which counts
    -- nights through NightsOnly. Two screens disagreeing about how many nights
    -- somebody raided is how an officer stops trusting both: before this the
    -- Roster window said Hinokamii had two and the board said one.
    for _, session in ipairs(RaidSession.NightsOnly(sessions)) do
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
