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
-- WHO SET IT, ALWAYS. An absence is the one thing this addon records that is
-- somebody's claim about another person rather than something the client
-- observed. Once these travel between guildies, "Talestra is out" with no
-- author is unanswerable — the person who knows it is wrong cannot tell who to
-- ask. Anybody may set one; everybody can see who did.
function RaidSchedule.Author()
    return (SYL.Keystone and SYL.Keystone.CharacterKey()) or "unknown"
end

-- AUTHOR-SCOPED, BECAUSE THESE TRAVEL. Each client is authoritative for the
-- absences it wrote and broadcasts that whole set, so an id only has to be
-- unique within one author — and prefixing the author makes it unique across
-- the guild without anybody sharing a counter.
local function NewAbsenceID(setBy)
    local store = Store()

    if not store then
        return nil
    end

    store.absenceSerial = (store.absenceSerial or 0) + 1

    return table.concat({
        tostring(setBy or "?"),
        tostring(time()),
        tostring(store.absenceSerial),
    }, "|")
end

function RaidSchedule.AddAbsence(name, fromKey, toKey, options)
    local store = Store()

    if not store or not name or name == "" or not fromKey then
        return nil
    end

    options = options or {}

    local setBy = options.setBy or RaidSchedule.Author()

    local absence = {
        id = options.id or NewAbsenceID(setBy),
        name = name,
        key = SYL.Players.GUIDForName(name) or nil,
        from = fromKey,
        to = toKey or fromKey,
        reason = options.reason,
        source = options.source or "manual",
        setBy = setBy,
        addedAt = options.addedAt or time(),
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

-- BY ID, NOT BY POSITION. Positions do not survive a merge: two clients
-- reconciling their lists agree about what an absence *is* and never about
-- where it sits in an array. The same lesson the drop records learned, which
-- is why every record in this addon carries one.
function RaidSchedule.RemoveAbsenceByID(id)
    local store = Store()

    if not store or not id then
        return false
    end

    for index, absence in ipairs(store.absences) do
        if absence.id == id then
            table.remove(store.absences, index)

            return true
        end
    end

    return false
end

-- Everything one person wrote, replaced in one go.
--
-- THE AUTHOR IS THE UNIT OF TRUTH. A client broadcasts every absence it wrote
-- and nothing else, so what arrives is the whole of that person's list and
-- anything of theirs missing from it has been removed. Merging entry by entry
-- would mean a deletion could only travel as a message of its own, and a
-- missed one would leave somebody marked out forever.
--
-- Only ever called with a sender the addon channel reported, so nobody can
-- replace a set that is not theirs.
function RaidSchedule.ReplaceAbsencesFrom(author, absences)
    local store = Store()

    if not store or not author or author == "" then
        return 0
    end

    local kept = {}

    for _, absence in ipairs(store.absences or {}) do
        if absence.setBy ~= author then
            table.insert(kept, absence)
        end
    end

    for _, absence in ipairs(absences or {}) do
        if absence.id and absence.name and absence.from then
            table.insert(kept, {
                id = absence.id,
                name = absence.name,
                key = SYL.Players.GUIDForName(absence.name) or nil,
                from = absence.from,
                to = absence.to or absence.from,
                reason = absence.reason,

                -- Stamped from the sender rather than from the payload, so a
                -- client cannot broadcast on somebody else's behalf.
                setBy = author,
                source = "shared",
                addedAt = time(),
            })
        end
    end

    store.absences = kept

    return #absences
end

-- Run at login, unconditionally, because the guard is the nil itself. An
-- absence written before ids existed is otherwise unreachable by anything that
-- reconciles, and would be re-sent forever as a new one.
function RaidSchedule.BackfillAbsenceIDs()
    local store = Store()

    if not store then
        return 0
    end

    local assigned = 0

    for index, absence in ipairs(store.absences or {}) do
        if type(absence) == "table" and not absence.id then
            absence.setBy = absence.setBy or RaidSchedule.Author()

            absence.id = table.concat({
                "legacy",
                tostring(absence.setBy),
                tostring(absence.addedAt or 0),
                tostring(index),
            }, "|")

            assigned = assigned + 1
        end
    end

    return assigned
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

-- One person's absences covering one day, removed — but only the ones this
-- client wrote. Returns how many went and how many were left alone because
-- somebody else set them, so a caller can say which happened.
--
-- Somebody else's claim is theirs to retract: their client is authoritative
-- for it and would put it straight back on the next broadcast, so deleting it
-- here would look like it worked and then silently undo itself.
function RaidSchedule.RemoveAbsencesFor(name, dayKey)
    local store = Store()

    if not store or not name or name == "" or not dayKey then
        return 0, 0, nil
    end

    local wanted = tostring(name):lower()
    local author = RaidSchedule.Author()
    local removed, theirs, setByWhom = 0, 0, nil

    for index = #store.absences, 1, -1 do
        local absence = store.absences[index]

        if tostring(absence.name):lower() == wanted
            and absence.from <= dayKey and absence.to >= dayKey
        then
            if absence.setBy == author then
                table.remove(store.absences, index)

                removed = removed + 1
            else
                theirs = theirs + 1
                setByWhom = absence.setBy or setByWhom
            end
        end
    end

    return removed, theirs, setByWhom
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
                id = absence.id,
                name = absence.name,
                key = absence.key,
                reason = absence.reason,
                source = absence.source,

                -- Carried through so the calendar can name who said so. An
                -- absence somebody disagrees with is a conversation, and it
                -- needs a person on the other end of it.
                setBy = absence.setBy,

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
