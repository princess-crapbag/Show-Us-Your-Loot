-- Core/NightCalendar.lua
--
-- Month and week arithmetic for the Nights calendar. What day of the week the
-- first of the month falls on, how many days it has, which month to open on.
--
-- SPLIT FROM Core/NightIndex.lua, which crossed the size limit when the night
-- figures were rebuilt. This is the honest seam: NightIndex is about sessions,
-- drops and who was there, and none of that appears below this line. Nothing
-- moved but the namespace -- the worked example for that is Core/Absences.lua
-- and HANDOFF.md's account of what it cost.
--
-- EVERY DATE HERE GOES THROUGH THE CLIENT'S OWN CLOCK, which is what makes a
-- weekday correct for the player rather than for UTC.

local SYL = _G.ShowUsYourLoot

local NightCalendar = {}
SYL.NightCalendar = NightCalendar

function NightCalendar.MonthKey(year, month)
    return string.format("%04d-%02d", year, month)
end

-- The 1st of the month as the client's own clock sees it, which is what makes
-- the weekday correct for the player rather than for UTC.
function NightCalendar.FirstOfMonth(year, month)
    return time({ year = year, month = month, day = 1, hour = 12 })
end

function NightCalendar.DaysInMonth(year, month)
    local nextMonth = month + 1
    local nextYear = year

    if nextMonth > 12 then
        nextMonth, nextYear = 1, year + 1
    end

    local first = NightCalendar.FirstOfMonth(year, month)
    local nextFirst = NightCalendar.FirstOfMonth(nextYear, nextMonth)

    -- Rounded rather than divided exactly: a daylight saving change inside
    -- the month makes the span 23 or 25 hours short of a whole number of
    -- days, and truncating there loses the last day of the month twice a year.
    return math.floor(((nextFirst - first) / 86400) + 0.5)
end

-- 1 = Sunday, matching the client's date("*t").wday.
function NightCalendar.FirstWeekday(year, month)
    local info = date("*t", NightCalendar.FirstOfMonth(year, month))

    return info.wday
end

function NightCalendar.Today()
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
function NightCalendar.LatestMonth(days)
    local latestKey

    for _, day in ipairs(days or {}) do
        if day.key and (not latestKey or day.key > latestKey) then
            latestKey = day.key
        end
    end

    if not latestKey then
        local year, month = NightCalendar.Today()

        return year, month
    end

    local year, month = latestKey:match("^(%d+)%-(%d+)")

    if not year then
        local todayYear, todayMonth = NightCalendar.Today()

        return todayYear, todayMonth
    end

    return tonumber(year), tonumber(month)
end

function NightCalendar.DayKeyFor(year, month, day)
    return string.format("%04d-%02d-%02d", year, month, day)
end
