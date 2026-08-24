-- Core/GuildCalendar.lua
--
-- Reading the in-game guild calendar, which is the only source of a raid
-- schedule that an addon can reach at all.
--
-- WHY THIS IS THE ONLY AUTOMATIC OPTION. An addon makes no HTTP requests, so
-- Discord cannot reach it, the web dashboard cannot push to it, and Warcraft
-- Logs is out for the same reason it was out for attendance. C_Calendar runs
-- inside the client and needs no network of its own. Everything else has to be
-- typed — see Core/RaidSchedule.lua, which is where typed answers live and
-- which always wins over anything imported here.
--
-- READING THE CALENDAR MOVES IT. Same trap as the Encounter Journal: opening a
-- month and opening an event change what the player is looking at. So this
-- runs behind an explicit action, never on login and never on a redraw, and it
-- puts the month back when it is done.
--
-- IT NEEDS THE MONTH OPENED BEFORE IT RETURNS ANYTHING. A fresh client answers
-- zero events for a month it has not been asked about, which reads exactly
-- like an empty calendar. That is why SetAbsMonth comes first and why an empty
-- result says "nothing found" rather than "no raids scheduled".
--
-- ***NOT VERIFIED AGAINST A LIVE CLIENT.*** Every call here is guarded and the
-- whole module degrades to "no calendar available" if any of it is missing,
-- which is deliberate: the field names below are from the documented shape and
-- have not been watched returning real data. If this silently finds nothing in
-- game, that is the first thing to distrust — not Core/RaidSchedule.lua, which
-- is tested and does not depend on any of this.

local SYL = _G.ShowUsYourLoot

local GuildCalendar = {}
SYL.GuildCalendar = GuildCalendar

-- Guild events and events the player was invited to. Holidays, raid lockouts
-- and raid resets are also on the calendar and are emphatically not raid
-- nights — a lockout reset would otherwise schedule a raid every Tuesday for
-- a guild that raids at the weekend.
local WANTED_TYPES = {
    GUILD_EVENT = true,
    PLAYER = true,
}

-- Declined, and the two ways of saying "not coming but not flatly no". Read
-- off the enum when it exists rather than hardcoded, because these are exactly
-- the numbers that get renumbered between expansions.
local function DeclinedStatuses()
    local statuses = {}

    if Enum and Enum.CalendarStatus then
        statuses[Enum.CalendarStatus.Declined] = "declined"
        statuses[Enum.CalendarStatus.Out] = "out"
        statuses[Enum.CalendarStatus.Tentative] = "tentative"
    end

    return statuses
end

function GuildCalendar.IsAvailable()
    return (C_Calendar
        and C_Calendar.OpenCalendar
        and C_Calendar.GetMonthInfo
        and C_Calendar.GetNumDayEvents
        and C_Calendar.GetDayEvent) and true or false
end

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)

    if not ok then
        return nil
    end

    return result
end

-- Puts the calendar back where the player had it. Called on every exit path,
-- including the failures, because leaving somebody's calendar on a month they
-- did not choose is the sort of thing that gets an addon uninstalled.
local function Restore(previous)
    if previous and C_Calendar.SetAbsMonth then
        pcall(C_Calendar.SetAbsMonth, previous.month, previous.year)
        pcall(C_Calendar.OpenCalendar)
    end
end

-- Every guild event in one month, as { day, title, calendarType }.
function GuildCalendar.ReadMonth(year, month)
    if not GuildCalendar.IsAvailable() then
        return nil, "no calendar"
    end

    local previous = SafeCall(C_Calendar.GetMonthInfo, 0)

    if C_Calendar.SetAbsMonth then
        local set = pcall(C_Calendar.SetAbsMonth, month, year)

        if not set then
            return nil, "could not open that month"
        end
    end

    pcall(C_Calendar.OpenCalendar)

    local info = SafeCall(C_Calendar.GetMonthInfo, 0)

    if not info or not info.numDays then
        Restore(previous)

        return nil, "the calendar returned nothing"
    end

    local found = {}

    for day = 1, info.numDays do
        local count = SafeCall(C_Calendar.GetNumDayEvents, 0, day) or 0

        for index = 1, count do
            local event = SafeCall(C_Calendar.GetDayEvent, 0, day, index)

            if event and WANTED_TYPES[event.calendarType] then
                table.insert(found, {
                    day = day,
                    index = index,
                    title = event.title,
                    calendarType = event.calendarType,
                    inviteStatus = event.inviteStatus,
                })
            end
        end
    end

    Restore(previous)

    return found, nil, info
end

--------------------------------------------------------------------------
-- Importing into the schedule
--------------------------------------------------------------------------

-- Returns added, skipped, and a message. Skipped counts nights that already
-- had a manual entry — those are never overwritten, and saying how many were
-- left alone is what stops "the import did nothing" reading as a failure.
function GuildCalendar.Import(year, month)
    if not GuildCalendar.IsAvailable() then
        return 0, 0, "This client has no calendar API available."
    end

    if not year or not month then
        year, month = SYL.NightCalendar.Today()
    end

    local events, err = GuildCalendar.ReadMonth(year, month)

    if not events then
        return 0, 0, "Could not read the calendar: " .. tostring(err) .. "."
    end

    local added, skipped = 0, 0

    for _, event in ipairs(events) do
        local dayKey = SYL.NightCalendar.DayKeyFor(year, month, event.day)

        local ok = SYL.RaidSchedule.SetNight(dayKey, {
            source = "calendar",
            title = event.title,
        })

        if ok then
            added = added + 1
        else
            skipped = skipped + 1
        end
    end

    if #events == 0 then
        return 0, 0,
            "No guild events found in that month. An empty month is also what "
            .. "an unopened one looks like, so try again if you know there are "
            .. "events there."
    end

    return added, skipped, string.format(
        "%d night%s from the calendar, %d left alone because they were typed in.",
        added, added == 1 and "" or "s", skipped
    )
end

--------------------------------------------------------------------------
-- Who declined
--------------------------------------------------------------------------

-- Opening an event is a heavier read than listing them and moves the player's
-- selection again, so this is separate and only ever runs for one day.
--
-- IT ONLY KNOWS WHAT PEOPLE CLICKED. A guild that posts absences in Discord and
-- never touches the in-game event will produce nothing here, correctly — which
-- is the case Aimee described, and the reason Core/RaidSchedule.lua accepts
-- typed absences at all.
function GuildCalendar.ReadDeclines(year, month, day)
    if not GuildCalendar.IsAvailable() or not C_Calendar.OpenEvent then
        return nil, "no calendar"
    end

    local declined = DeclinedStatuses()

    if not next(declined) then
        return nil, "this client does not expose invite statuses"
    end

    local previous = SafeCall(C_Calendar.GetMonthInfo, 0)

    pcall(C_Calendar.SetAbsMonth, month, year)
    pcall(C_Calendar.OpenCalendar)

    local count = SafeCall(C_Calendar.GetNumDayEvents, 0, day) or 0
    local out = {}

    for index = 1, count do
        local event = SafeCall(C_Calendar.GetDayEvent, 0, day, index)

        if event and WANTED_TYPES[event.calendarType] then
            local opened = pcall(C_Calendar.OpenEvent, 0, day, index)

            if opened and C_Calendar.GetNumInvites and C_Calendar.EventGetInvite then
                local invites = SafeCall(C_Calendar.GetNumInvites) or 0

                for position = 1, invites do
                    local invite = SafeCall(C_Calendar.EventGetInvite, position)

                    if invite and declined[invite.inviteStatus] then
                        table.insert(out, {
                            name = invite.name,
                            status = declined[invite.inviteStatus],
                        })
                    end
                end
            end

            if C_Calendar.CloseEvent then
                pcall(C_Calendar.CloseEvent)
            end
        end
    end

    Restore(previous)

    return out
end

-- Reads the declines for a day and writes them in as absences. Marked
-- `calendar` so a typed absence stays distinguishable from a clicked one.
function GuildCalendar.ImportDeclines(dayKey)
    local year, month, day = tostring(dayKey):match("^(%d+)%-(%d+)%-(%d+)$")

    if not year then
        return 0, "That is not a date this addon recognizes."
    end

    local declines, err = GuildCalendar.ReadDeclines(
        tonumber(year), tonumber(month), tonumber(day)
    )

    if not declines then
        return 0, "Could not read the calendar: " .. tostring(err) .. "."
    end

    local existing = {}

    for _, entry in ipairs(SYL.Absences.WhoIsOut(dayKey)) do
        existing[tostring(entry.name):lower()] = true
    end

    local added = 0

    for _, decline in ipairs(declines) do
        if decline.name and not existing[tostring(decline.name):lower()] then
            SYL.Absences.AddAbsence(decline.name, dayKey, dayKey, {
                reason = decline.status,
                source = "calendar",
            })

            added = added + 1
        end
    end

    return added, string.format(
        "%d absence%s read from the calendar for that day.",
        added, added == 1 and "" or "s"
    )
end
