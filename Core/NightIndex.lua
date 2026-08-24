-- Core/NightIndex.lua
--
-- Raid nights arranged by calendar day, and the numbers for one day.
--
-- No frames. UI/NightsPanel.lua draws whatever this returns, so the grid and
-- the stat panel below it read the same index rather than each sweeping the
-- sessions with their own idea of what a night is.
--
-- THE DAY KEY IS session.dateText, not the timestamp. A raid that runs past
-- midnight already has a dateText, written when the session opened, and it
-- says the night it belongs to rather than the day the clock happened to
-- reach. Recomputing from startedAt would split a Tuesday raid across two
-- cells at 00:00 and put half its kills on Wednesday.
--
-- It is one of the two deliberate ISO strings in the addon. Dates are
-- MM-DD-YYYY everywhere they are shown; this is a key, and reformatting it
-- would re-key every night already recorded. Formatting happens at the point
-- of display and nowhere else.
--
-- A DAY IS NOT A SESSION. A Tuesday that cleared Heroic and then pulled Mythic
-- is two sessions and one night, which is the same rule RaidSession.CountNights
-- applies — so pulls, kills and duration sum across the day's sessions and the
-- roster is folded rather than added up.

local SYL = _G.ShowUsYourLoot

local NightIndex = {}
SYL.NightIndex = NightIndex

local function DayKeyFromTimestamp(timestamp)
    if not timestamp then
        return nil
    end

    return date("%Y-%m-%d", timestamp)
end

NightIndex.DayKeyFromTimestamp = DayKeyFromTimestamp

-- Only raid nights. The same exclusion the due list and the score already
-- make: Timewalking, Story, Event and Follower are real content and are not
-- what a raid team's attendance is measured on, so they do not shade a day.
local function DayKey(session)
    if not session then
        return nil
    end

    return session.dateText or DayKeyFromTimestamp(session.startedAt)
end

NightIndex.DayKey = DayKey

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function EnsureDay(byDay, order, key)
    local day = byDay[key]

    if not day then
        day = {
            key = key,
            sessions = {},
            instanceNames = {},
            difficultyNames = {},

            pulls = 0,
            kills = 0,
            minutes = 0,
            drops = 0,
            upgrades = 0,

            roster = {},
            rosterCount = 0,

            -- DISTINCT BOSSES KILLED, keyed by name, against what the
            -- instances hold. `kills` above counts kill EVENTS, so a boss
            -- killed on Normal and again on Heroic is two of those and one of
            -- these -- and it is these that "5 of 8 bosses down" is about.
            bossesKilled = {},
            bossCount = 0,

            -- Every boss engaged, killed or not, in the order they were
            -- pulled: { name, difficultyID, instanceName, pulls, killedAt }.
            --
            -- TWO TABLES, NOT ONE USED BOTH WAYS. The lookup was keyed into
            -- the same table the array lives in, which works in Lua -- ipairs
            -- walks only the array part -- and is a trap for anything that
            -- iterates with pairs, which is every test harness and every
            -- serializer. Six fights read as twelve the first time anything
            -- counted them.
            fights = {},
            fightsByKey = {},

            -- The people credited with something worth having, and the people
            -- who went home with nothing. Both are counts of PEOPLE.
            gotGear = {},
            gotGearCount = 0,

            startedAt = nil,
            enteredAt = nil,
            leftAt = nil,
        }

        byDay[key] = day
        table.insert(order, day)
    end

    return day
end

local function Remember(list, value)
    if not value or value == "" then
        return
    end

    for _, existing in ipairs(list) do
        if existing == value then
            return
        end
    end

    table.insert(list, value)
end

-- The rule for "did this evening give you anything" lives with the other
-- fairness rules, in Core/DropRules.lua: DropRules.WorthHaving.
local function CreditPerson(day, drop)
    local key = SYL.DropRules.WorthHaving(drop)

    if not key or day.gotGear[key] then
        return
    end

    day.gotGear[key] = true
    day.gotGearCount = day.gotGearCount + 1
end

-- Sessions and drops are passed in rather than read here, so a caller can ask
-- about one season or about everything without this knowing which.
function NightIndex.Build(sessions, drops)
    local byDay, order = {}, {}

    -- The calendar shows the guild's raid nights. Aimee: "i dont need any
    -- data from lfr or pugs." One predicate, shared with the dashboard, so
    -- the two cannot report different numbers for the same evening.
    for _, session in ipairs(SYL.RaidSession.NightsOnly(sessions)) do
        local key = DayKey(session)

        if key then
            local day = EnsureDay(byDay, order, key)

            table.insert(day.sessions, session)

            Remember(day.instanceNames, session.instanceName)
            Remember(day.difficultyNames, session.difficultyName)

            day.pulls = day.pulls + #(session.encounters or {})
            day.kills = day.kills + SYL.RaidSession.GetKillCount(session)
            day.minutes = day.minutes + SYL.RaidSession.GetDurationMinutes(session)

            -- HOW MUCH OF THE NIGHT WAS ACTUALLY FIGHTING. Aimee: "how can we
            -- track the first pull time and the last wipe time to see how
            -- much of our 3 hours were fighting? vs afks?"
            --
            -- Summed per session and counted, because a night that is half
            -- old records must say so rather than reporting half the fighting
            -- it did as though that were all of it.
            local fighting, _idle, measured, pulls =
                SYL.RaidSession.FightingMinutes(session)

            if fighting then
                day.fightingMinutes = (day.fightingMinutes or 0) + fighting
            end

            day.pullsMeasured = (day.pullsMeasured or 0) + (measured or 0)
            day.pullsTotal = (day.pullsTotal or 0) + (pulls or 0)

            -- EVERY FIGHT OF THE NIGHT, and the bosses that actually died.
            --
            -- The panel used to say "5/10 bosses killed" where the ten was
            -- PULLS. Aimee: "5 of 10 bosses killed [...] there are 8 bosses in
            -- the venomous abyss but i realize we only pulled 6, 5 of which we
            -- killed." A pull count was never a boss count.
            --
            -- Fights are keyed by boss AND difficulty, because Nymrissa on
            -- Normal and Nymrissa on Heroic are two different evenings' work
            -- -- her 08-20 killed one and wiped three times on the other. The
            -- KILL count is keyed by name alone, because a boss you have
            -- killed is down however many difficulties you did it on.
            for _, encounter in ipairs(session.encounters or {}) do
                local fightKey = tostring(encounter.name) .. "|"
                    .. tostring(encounter.difficultyID)

                local fight = day.fightsByKey[fightKey]

                if not fight then
                    fight = {
                        name = encounter.name,

                        -- The journal is keyed on this, and it is the only
                        -- bridge between a night's records and how many
                        -- bosses the raid actually holds.
                        encounterID = encounter.encounterID,

                        difficultyID = encounter.difficultyID,
                        instanceName = session.instanceName,
                        pulls = 0,
                    }

                    day.fightsByKey[fightKey] = fight
                    table.insert(day.fights, fight)
                end

                fight.pulls = fight.pulls + 1

                if encounter.killed then
                    fight.killedAt = encounter.at

                    if encounter.name and not day.bossesKilled[encounter.name]
                    then
                        day.bossesKilled[encounter.name] = true
                        day.bossCount = day.bossCount + 1
                    end
                end
            end

            if not day.startedAt or (session.startedAt or 0) < day.startedAt then
                day.startedAt = session.startedAt
            end

            -- THE EVENING, as against the fighting part of it. Both are nil
            -- on every session recorded before they were kept, and a caller
            -- has to treat that as "not known" rather than as zero.
            if session.enteredAt
                and (not day.enteredAt or session.enteredAt < day.enteredAt)
            then
                day.enteredAt = session.enteredAt
            end

            local left = session.leftAt or session.endedAt

            if session.enteredAt and left
                and (not day.leftAt or left > day.leftAt)
            then
                day.leftAt = left
            end

            -- Folded, not summed. Somebody who brought a main to Heroic and an
            -- alt to Mythic is one person who turned up, and counting them
            -- twice would make a two-session night look better attended than
            -- it was.
            for rosterKey, member in pairs(session.roster or {}) do
                local resolved = SYL.Players.ResolveToMain(rosterKey) or rosterKey

                if not day.roster[resolved] then
                    day.roster[resolved] = member or true
                    day.rosterCount = day.rosterCount + 1
                end
            end
        end
    end

    -- A DROP BELONGS TO A SESSION, NOT TO A CALENDAR DATE.
    --
    -- This used to key a drop on date alone and ask nothing else, eleven lines
    -- below a loop that had already thrown away every session that is not a
    -- guild night. So on 2026-08-18 the panel excluded a Looking For Raid run
    -- for being 2% guild and then counted all eleven of its drops anyway:
    -- "22 drops" on a night that produced eleven.
    --
    -- Aimee: "is this 22 drops that count towards the fairness rules? its not
    -- including boes or warbound/personal loot right? it should not count
    -- those."
    --
    -- It was not, and now it does not. A drop has to fall inside one of the
    -- day's own qualifying sessions, and it has to pass the same
    -- DropRules.CountsAsUpgrade every fairness surface uses -- so bind-on-
    -- equip and warbound are out of this figure exactly as they are out of
    -- the board.
    local qualifying = {}

    for _, day in ipairs(order) do
        for _, session in ipairs(day.sessions) do
            qualifying[session] = day
        end
    end

    for _, drop in ipairs(drops or {}) do
        if not drop.excludedFromAnalytics then
            local session = SYL.RaidSession.SessionAt(sessions, drop.timestamp)
            local day = session and qualifying[session]

            -- A drop after midnight still belongs to the night that was
            -- running, because the session is what it is matched to. That is
            -- the whole reason this is not keyed on the date any more.
            if day and SYL.DropRules.CountsAsUpgrade(drop) then
                day.drops = day.drops + 1

                CreditPerson(day, drop)
            end
        end
    end

    -- Counted once at the end, because gotGear is a set of people and a set
    -- has no length until you have finished putting things in it.
    for _, day in ipairs(order) do
        day.upgrades = day.gotGearCount
        day.gotNothing = math.max(0, day.rosterCount - day.gotGearCount)
    end

    return order, byDay
end

-- THE EVENINGS THE CALENDAR THROWS AWAY.
--
-- NightsOnly keeps the guild's own raid nights and discards everything else,
-- which is right -- Aimee: "i dont need any data from lfr or pugs" -- but the
-- discarding was total. Her 2026-08-22 is seven wipes on Ula'tek with 33
-- people in the group, and clicking that day answers "Pick a shaded day". A
-- whole evening she remembers is invisible, with nothing to say why.
--
-- So they are indexed separately, and everything about them stays out of the
-- fairness math. Her own rule: "nothing ever counts to fairness or raid night
-- stuff on those off raids." Nothing here is added to a day in Build, no drop
-- is attributed to one, and no caller of Build can reach these by accident --
-- they have to ask for them by name.
function NightIndex.OtherNights(sessions)
    local byDay = {}

    for _, session in ipairs(sessions or {}) do
        -- A raid, recorded, that simply was not the guild's night. A dungeon
        -- or a scenario is not an "off raid", it is not a raid at all.
        if SYL.Utilities.IsRaidContent(
                session.instanceType, session.difficultyID)
            and not SYL.RaidSession.CountsAsNight(session)
        then
            local key = DayKey(session)

            if key then
                local day = byDay[key]

                if not day then
                    day = {
                        key = key,
                        sessions = {},
                        instanceNames = {},
                        difficultyNames = {},
                        pulls = 0,
                        kills = 0,
                        guilded = 0,
                        groupSize = 0,
                        startedAt = nil,
                        endedAt = nil,
                    }

                    byDay[key] = day
                end

                table.insert(day.sessions, session)

                Remember(day.instanceNames, session.instanceName)
                Remember(day.difficultyNames, session.difficultyName)

                day.pulls = day.pulls + #(session.encounters or {})
                day.kills = day.kills + SYL.RaidSession.GetKillCount(session)

                -- Counted by GuildShare rather than read off rosterCount,
                -- which is maintained separately and can disagree with the
                -- roster table the share is computed from.
                local guilded, total = SYL.RaidSession.GuildCounts(session)

                if total and total > day.groupSize then
                    day.groupSize = total
                    day.guilded = guilded or 0
                end

                if not day.startedAt
                    or (session.startedAt or 0) < day.startedAt
                then
                    day.startedAt = session.startedAt
                end

                if not day.endedAt or (session.endedAt or 0) > day.endedAt then
                    day.endedAt = session.endedAt
                end
            end
        end
    end

    return byDay
end

-- CALENDAR ARITHMETIC MOVED TO Core/NightCalendar.lua when this file crossed
-- the size limit. Month and week math has nothing to do with sessions, drops
-- or who was there, which is everything above this line.
