-- Core/ScheduleCommands.lua
--
-- /syl schedule, /syl out and /syl in.
--
-- Split from Core/SlashCommands.lua, which was already the largest file in the
-- addon before any of these existed.
--
-- TYPING IS THE WHOLE POINT HERE. Aimee's guild posts absences in Discord, and
-- nothing on Discord can reach an addon — so the fastest possible path from
-- "Dravok says he is out next week" to the addon knowing it is one line an
-- officer types while reading the message. That is what these are shaped
-- around: `/syl out Dravok 7` and nothing else to learn.

local SYL = _G.ShowUsYourLoot

local ScheduleCommands = {}
SYL.ScheduleCommands = ScheduleCommands

-- Every reasonable way somebody types a weekday, mapped to date("*t").wday.
local WEEKDAYS = {
    sun = 1, sunday = 1,
    mon = 2, monday = 2,
    tue = 3, tues = 3, tuesday = 3,
    wed = 4, weds = 4, wednesday = 4,
    thu = 5, thur = 5, thurs = 5, thursday = 5,
    fri = 6, friday = 6,
    sat = 7, saturday = 7,
}

local function Words(remainder)
    local words = {}

    for word in tostring(remainder or ""):gmatch("%S+") do
        table.insert(words, word)
    end

    return words
end

local function Report()
    local days = SYL.RaidSchedule.DescribeWeekdays()

    if days then
        SYL:Write("Raid days: " .. SYL.colors.addon .. days .. SYL.colors.reset)
    else
        SYL:Write(
            "No usual raid days set. " .. SYL.colors.highlight
            .. "/syl schedule days tue wed" .. SYL.colors.reset
            .. " sets them."
        )
    end

    local today = SYL.RaidSchedule.TodayKey()
    local dayKey, reason = SYL.RaidSchedule.NextNight(today)

    if not dayKey then
        SYL:Write("Nothing scheduled in the next four weeks.")

        return
    end

    local out = SYL.RaidSchedule.WhoIsOut(dayKey)

    SYL:Write(
        "Next raid night: " .. SYL.colors.addon
        .. SYL.RaidSchedule.WeekdayName(dayKey) .. " "
        .. SYL.Utilities.FormatDateOnly(SYL.RaidSchedule.TimestampOf(dayKey))
        .. SYL.colors.reset
        .. " (" .. tostring(reason) .. ")"
    )

    if #out == 0 then
        SYL:Write("Nobody has been marked out for it.")

        return
    end

    SYL:Write(#out .. " out that night:")

    for _, absence in ipairs(out) do
        SYL:Write(
            "  " .. absence.name
            .. (absence.reason and (" — " .. absence.reason) or "")
            .. (absence.multiDay
                and (" (to " .. SYL.Utilities.FormatDateOnly(
                    SYL.RaidSchedule.TimestampOf(absence.to)
                ) .. ")")
                or "")
        )
    end
end

--------------------------------------------------------------------------
-- /syl schedule
--------------------------------------------------------------------------

local function SetDays(words)
    local wanted = {}

    for index = 2, #words do
        local weekday = WEEKDAYS[words[index]:lower()]

        if not weekday then
            SYL:Write(
                "Not a day I recognise: " .. words[index]
                .. ". Try mon tue wed thu fri sat sun."
            )

            return
        end

        wanted[weekday] = true
    end

    -- Set as a whole rather than toggled one at a time: "these are our raid
    -- days" is what somebody means, and a toggle would leave last month's
    -- Thursday behind when the guild drops it.
    for weekday = 1, 7 do
        SYL.RaidSchedule.SetWeekday(weekday, wanted[weekday])
    end

    if not next(wanted) then
        SYL:Write("Raid days cleared.")

        return
    end

    Report()
end

function ScheduleCommands.Schedule(remainder)
    local words = Words(remainder)
    local action = (words[1] or ""):lower()

    if action == "" then
        Report()

        return
    end

    if action == "days" then
        SetDays(words)

        return
    end

    if action == "import" then
        if not SYL.GuildCalendar.IsAvailable() then
            SYL:Write("This client has no calendar API available.")

            return
        end

        local added, skipped, message = SYL.GuildCalendar.Import()

        SYL:Write(message or (added .. " added, " .. skipped .. " skipped."))

        return
    end

    if action == "clear" then
        SYL.RaidSchedule.ClearExpired()

        SYL:Write("Absences that have already passed were cleared.")

        return
    end

    SYL:Write("Usage: /syl schedule [days mon tue …] [import] [clear]")
end

--------------------------------------------------------------------------
-- /syl out and /syl in
--------------------------------------------------------------------------

-- `/syl out Dravok` is one night. `/syl out Dravok 7` is the next seven days,
-- which is what "out next week" means when somebody types it in Discord.
function ScheduleCommands.Out(remainder)
    local words = Words(remainder)
    local name = words[1]

    if not name then
        SYL:Write("Usage: /syl out <name> [days] [reason]")

        return
    end

    local days = tonumber(words[2])
    local reasonFrom = days and 3 or 2
    local reason

    if #words >= reasonFrom then
        reason = table.concat(words, " ", reasonFrom)
    end

    local from = SYL.RaidSchedule.TodayKey()
    local to = days and SYL.RaidSchedule.Offset(from, math.max(0, days - 1)) or from

    local absence = SYL.RaidSchedule.AddAbsence(name, from, to, {
        reason = reason,
    })

    if not absence then
        SYL:Write("Could not add that.")

        return
    end

    SYL:Write(
        SYL.colors.addon .. name .. SYL.colors.reset
        .. " is out"
        .. (absence.from == absence.to
            and (" on " .. SYL.Utilities.FormatDateOnly(
                SYL.RaidSchedule.TimestampOf(absence.from)))
            or (" until " .. SYL.Utilities.FormatDateOnly(
                SYL.RaidSchedule.TimestampOf(absence.to))))
        .. (reason and (" — " .. reason) or "")
        .. "."
    )
end

-- The undo. Named `in` because that is what somebody types after `out`, even
-- though it costs a quoted key in the command table.
function ScheduleCommands.Back(remainder)
    local words = Words(remainder)
    local name = words[1]

    if not name then
        SYL:Write("Usage: /syl in <name>")

        return
    end

    local wanted = name:lower()
    local absences = SYL.RaidSchedule.AllAbsences()
    local removed = 0

    -- Backwards, because removing by index while walking forwards skips the
    -- entry after every hit.
    for index = #absences, 1, -1 do
        if tostring(absences[index].name):lower() == wanted then
            SYL.RaidSchedule.RemoveAbsence(index)

            removed = removed + 1
        end
    end

    if removed == 0 then
        SYL:Write("Nothing recorded for " .. name .. ".")

        return
    end

    SYL:Write(
        name .. " is back — " .. removed
        .. (removed == 1 and " absence" or " absences") .. " removed."
    )
end
