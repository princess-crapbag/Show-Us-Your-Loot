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

            startedAt = nil,
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

            if not day.startedAt or (session.startedAt or 0) < day.startedAt then
                day.startedAt = session.startedAt
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

    -- Drops land on the day their timestamp falls in, which is the only thing
    -- they carry. A drop after midnight on a night that started Tuesday will
    -- therefore sit on Wednesday even though the night does not — accepted,
    -- because the alternative is guessing which session a drop belonged to,
    -- and the loot list already answers "what dropped" precisely.
    for _, drop in ipairs(drops or {}) do
        if not drop.excludedFromAnalytics then
            local key = DayKeyFromTimestamp(drop.timestamp)
            local day = key and byDay[key]

            if day then
                day.drops = day.drops + 1

                if SYL.LootHistoryAPI.IsUpgradeState(drop.winnerState) then
                    day.upgrades = day.upgrades + 1
                end
            end
        end
    end

    return order, byDay
end

--------------------------------------------------------------------------
-- Calendar arithmetic
--------------------------------------------------------------------------

function NightIndex.MonthKey(year, month)
    return string.format("%04d-%02d", year, month)
end

-- The 1st of the month as the client's own clock sees it, which is what makes
-- the weekday correct for the player rather than for UTC.
function NightIndex.FirstOfMonth(year, month)
    return time({ year = year, month = month, day = 1, hour = 12 })
end

function NightIndex.DaysInMonth(year, month)
    local nextMonth = month + 1
    local nextYear = year

    if nextMonth > 12 then
        nextMonth, nextYear = 1, year + 1
    end

    local first = NightIndex.FirstOfMonth(year, month)
    local nextFirst = NightIndex.FirstOfMonth(nextYear, nextMonth)

    -- Rounded rather than divided exactly: a daylight saving change inside
    -- the month makes the span 23 or 25 hours short of a whole number of
    -- days, and truncating there loses the last day of the month twice a year.
    return math.floor(((nextFirst - first) / 86400) + 0.5)
end

-- 1 = Sunday, matching the client's date("*t").wday.
function NightIndex.FirstWeekday(year, month)
    local info = date("*t", NightIndex.FirstOfMonth(year, month))

    return info.wday
end

function NightIndex.Today()
    local info = date("*t")

    return info.year, info.month, info.day
end

-- The month a calendar should open on: the one holding the most recent night,
-- falling back to the current month. Opening on today would show an empty grid
-- to anybody whose last raid was three weeks ago.
--
-- Read off the day KEY rather than off startedAt, so the month this returns
-- cannot disagree with the month the grid draws. The grid keys cells by
-- dateText; picking the month from a timestamp instead would open on a month
-- that does not contain the night whenever the two differ, and the screen
-- would be empty for a reason nothing on it explains.
--
-- ISO keys sort lexicographically in the same order they sort chronologically,
-- which is the whole reason the key is ISO while every date on screen is not.
function NightIndex.LatestMonth(days)
    local latestKey

    for _, day in ipairs(days or {}) do
        if day.key and (not latestKey or day.key > latestKey) then
            latestKey = day.key
        end
    end

    if not latestKey then
        local year, month = NightIndex.Today()

        return year, month
    end

    local year, month = latestKey:match("^(%d+)%-(%d+)")

    if not year then
        local todayYear, todayMonth = NightIndex.Today()

        return todayYear, todayMonth
    end

    return tonumber(year), tonumber(month)
end

function NightIndex.DayKeyFor(year, month, day)
    return string.format("%04d-%02d-%02d", year, month, day)
end
