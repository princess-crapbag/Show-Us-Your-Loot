-- Core/RaidSchedule.lua
--
-- When the guild raids next, and who has said they will not be there.
--
-- THREE SOURCES, ONE ORDER OF PRECEDENCE, and the order is the whole design:
--
--   1. An explicit night somebody typed in         (source "manual")
--   2. An explicit night read from the guild calendar (source "calendar")
--   3. The weekdays the guild normally raids       (the recurring pattern)
--
-- Manual always wins. An officer who cancels Wednesday has said something the
-- calendar has not caught up with, and an import that overruled them would
-- make the addon argue with the person maintaining it. So an import never
-- overwrites a manual entry, and a manual entry can cancel a recurring night.
--
-- WHY THE RECURRING PATTERN EXISTS AT ALL. Aimee's guild posts absences in
-- Discord, and nothing on Discord can reach an addon — WoW makes no HTTP
-- requests, which is the same wall that stopped Warcraft Logs and Droptimizer
-- import. That leaves typing, and typing every week is a chore nobody does
-- twice. "We raid Tuesday and Wednesday" is typed once and answers "when is
-- the next raid night" forever without Discord, without the in-game calendar,
-- and without anybody remembering to do anything.
--
-- ABSENCES ARE RANGES, NOT DAYS. People say "I'm out next week", not "I'm out
-- on the 12th, the 13th and the 14th". Storing what they meant is fewer rows
-- and survives the raid night moving.
--
-- Day keys are ISO, the same as Core/NightIndex.lua, and for the same reason:
-- they sort chronologically as strings. Every date on screen is MM-DD-YYYY.

local SYL = _G.ShowUsYourLoot

local RaidSchedule = {}
SYL.RaidSchedule = RaidSchedule

-- 1 = Sunday, matching date("*t").wday throughout the addon.
RaidSchedule.WEEKDAY_NAMES = {
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

-- How far ahead a recurring pattern is willing to answer. A guild that stops
-- raiding should see "no raid night scheduled" within a month rather than an
-- answer generated forever from a pattern nobody updated.
local HORIZON_DAYS = 28

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    local store = ShowUsYourLootDB.schedule or {}

    store.weekdays = store.weekdays or {}
    store.nights = store.nights or {}
    store.absences = store.absences or {}

    ShowUsYourLootDB.schedule = store

    return store
end

RaidSchedule.Store = Store

--------------------------------------------------------------------------
-- Days
--------------------------------------------------------------------------

local function TodayKey()
    local year, month, day = SYL.NightIndex.Today()

    return SYL.NightIndex.DayKeyFor(year, month, day)
end

RaidSchedule.TodayKey = TodayKey

-- A day key N days after another, done through the client's own clock rather
-- than by adding to a string. Midday, so a daylight saving shift moves the
-- hour and never the date.
function RaidSchedule.Offset(dayKey, days)
    local year, month, day = tostring(dayKey):match("^(%d+)%-(%d+)%-(%d+)$")

    if not year then
        return nil
    end

    local at = time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day) + days,
        hour = 12,
    })

    return date("%Y-%m-%d", at)
end

-- Midday, so nothing here can land on the wrong side of a daylight saving
-- shift. Used for display only; the key is what anything compares.
function RaidSchedule.TimestampOf(dayKey)
    local year, month, day = tostring(dayKey):match("^(%d+)%-(%d+)%-(%d+)$")

    if not year then
        return nil
    end

    return time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    })
end

function RaidSchedule.WeekdayName(dayKey)
    local weekday = RaidSchedule.WeekdayOf(dayKey)

    return weekday and RaidSchedule.WEEKDAY_NAMES[weekday] or "Unknown"
end

function RaidSchedule.WeekdayOf(dayKey)
    local year, month, day = tostring(dayKey):match("^(%d+)%-(%d+)%-(%d+)$")

    if not year then
        return nil
    end

    local info = date("*t", time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    }))

    return info.wday
end

--------------------------------------------------------------------------
-- The recurring pattern
--------------------------------------------------------------------------

function RaidSchedule.GetWeekdays()
    local store = Store()

    return (store and store.weekdays) or {}
end

function RaidSchedule.SetWeekday(weekday, on)
    local store = Store()

    if not store or type(weekday) ~= "number" or weekday < 1 or weekday > 7 then
        return false
    end

    store.weekdays[weekday] = on and true or nil

    return true
end

function RaidSchedule.ToggleWeekday(weekday)
    local weekdays = RaidSchedule.GetWeekdays()

    return RaidSchedule.SetWeekday(weekday, not weekdays[weekday])
end

function RaidSchedule.DescribeWeekdays()
    local weekdays = RaidSchedule.GetWeekdays()
    local names = {}

    for index = 1, 7 do
        if weekdays[index] then
            table.insert(names, RaidSchedule.WEEKDAY_NAMES[index])
        end
    end

    if #names == 0 then
        return nil
    end

    return table.concat(names, ", ")
end

--------------------------------------------------------------------------
-- Explicit nights
--------------------------------------------------------------------------

-- `canceled` is a manual entry that says a night is NOT happening, which a
-- recurring pattern otherwise insists on. Stored rather than deleted, because
-- deleting would just let the pattern put it straight back.
function RaidSchedule.SetNight(dayKey, options)
    local store = Store()

    if not store or not dayKey then
        return false
    end

    options = options or {}

    local existing = store.nights[dayKey]

    -- An import must never overrule a person. See the header.
    if existing
        and existing.source == "manual"
        and options.source ~= "manual"
    then
        return false
    end

    store.nights[dayKey] = {
        source = options.source or "manual",
        title = options.title,
        canceled = options.canceled or nil,
        addedAt = time(),
    }

    return true
end

function RaidSchedule.ClearNight(dayKey)
    local store = Store()

    if not store or not dayKey then
        return false
    end

    local existed = store.nights[dayKey] ~= nil

    store.nights[dayKey] = nil

    return existed
end

function RaidSchedule.GetNight(dayKey)
    local store = Store()

    return store and store.nights[dayKey] or nil
end

-- Whether the guild is raiding on a given day, and why it thinks so. A
-- cancellation answers false with its reason intact, so a caller can say
-- "canceled" rather than "nothing scheduled" — those are different things and
-- only one of them means somebody should be asked.
function RaidSchedule.IsRaidNight(dayKey)
    local explicit = RaidSchedule.GetNight(dayKey)

    if explicit then
        if explicit.canceled then
            return false, "canceled"
        end

        return true, explicit.source
    end

    local weekday = RaidSchedule.WeekdayOf(dayKey)

    if weekday and RaidSchedule.GetWeekdays()[weekday] then
        return true, "weekly"
    end

    return false, nil
end

-- The next day the guild raids, today included. Returns the day key and the
-- reason, or nil when nothing is scheduled inside the horizon.
function RaidSchedule.NextNight(fromKey)
    local cursor = fromKey or TodayKey()

    for offset = 0, HORIZON_DAYS do
        local dayKey = offset == 0 and cursor or RaidSchedule.Offset(cursor, offset)

        if dayKey then
            local isNight, reason = RaidSchedule.IsRaidNight(dayKey)

            if isNight then
                return dayKey, reason
            end
        end
    end

    return nil
end

function RaidSchedule.IsConfigured()
    local store = Store()

    if not store then
        return false
    end

    if next(store.weekdays) then
        return true
    end

    return next(store.nights) ~= nil
end

--------------------------------------------------------------------------
-- Absences
--------------------------------------------------------------------------

-- from and to are inclusive day keys. A single day passes the same key twice,
-- which keeps every reader on one shape.
function RaidSchedule.AddAbsence(name, fromKey, toKey, options)
    local store = Store()

    if not store or not name or name == "" or not fromKey then
        return nil
    end

    options = options or {}

    local absence = {
        name = name,
        key = SYL.Players.GUIDForName(name) or nil,
        from = fromKey,
        to = toKey or fromKey,
        reason = options.reason,
        source = options.source or "manual",
        addedAt = time(),
    }

    table.insert(store.absences, absence)

    return absence
end

function RaidSchedule.RemoveAbsence(index)
    local store = Store()

    if not store or not store.absences[index] then
        return false
    end

    table.remove(store.absences, index)

    return true
end

function RaidSchedule.ClearExpired(beforeKey)
    local store = Store()

    if not store then
        return 0
    end

    beforeKey = beforeKey or TodayKey()

    local kept, dropped = {}, 0

    for _, absence in ipairs(store.absences) do
        if absence.to >= beforeKey then
            table.insert(kept, absence)
        else
            dropped = dropped + 1
        end
    end

    if dropped > 0 then
        store.absences = kept
    end

    return dropped
end

-- Everyone out on a given day. String comparison is safe because the keys are
-- ISO and fixed width, which is the reason they are stored that way.
function RaidSchedule.WhoIsOut(dayKey)
    local store = Store()
    local out = {}

    if not store or not dayKey then
        return out
    end

    for index, absence in ipairs(store.absences) do
        if absence.from <= dayKey and absence.to >= dayKey then
            table.insert(out, {
                index = index,
                name = absence.name,
                key = absence.key,
                reason = absence.reason,
                source = absence.source,
                from = absence.from,
                to = absence.to,
                multiDay = absence.from ~= absence.to,
            })
        end
    end

    table.sort(out, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return out
end

function RaidSchedule.AllAbsences()
    local store = Store()

    return (store and store.absences) or {}
end
