-- UI/ScheduleWidgets.lua
--
-- The two dashboard tiles that were waiting on the calendar: the next raid
-- night, and who has said they will not be there.
--
-- Split from UI/DashboardWidgets.lua, which went over the size limit the
-- moment these landed. Same shape as every other renderer — given a tile,
-- fill it — and they are registered onto the same RENDERERS table, so
-- Core/Dashboard.lua does not know or care that they live in another file.
--
-- BOTH USED TO SAY "NOT BUILT YET". What unblocked them was not the calendar:
-- it was accepting that a schedule can be typed. See Core/RaidSchedule.lua —
-- "we raid Tuesday and Wednesday" is one line, answers this tile forever, and
-- needs neither the in-game calendar nor Discord, neither of which the addon
-- can rely on reaching.

local SYL = _G.ShowUsYourLoot
local DashboardParts = SYL.DashboardParts

local ScheduleWidgets = {}
SYL.ScheduleWidgets = ScheduleWidgets

-- How many days from today a key is, or nil if it is outside the horizon the
-- schedule looks at. Counted by stepping rather than by subtracting
-- timestamps, so a daylight saving change cannot make it 1.96 days.
local function DaysUntil(todayKey, dayKey)
    for days = 0, 28 do
        if SYL.RaidSchedule.Offset(todayKey, days) == dayKey then
            return days
        end
    end

    return nil
end

ScheduleWidgets.DaysUntil = DaysUntil

-- Next raid night ---------------------------------------------------------
SYL.DashboardWidgets.RENDERERS.nextNight = function(tile)
    if not SYL.RaidSchedule.IsConfigured() then
        DashboardParts.Empty(tile,
            "No raid schedule yet.\n\nSet the nights you raid with "
            .. "/syl schedule days tue wed, or import your guild calendar "
            .. "with /syl schedule import.")

        return
    end

    local today = SYL.RaidSchedule.TodayKey()
    local dayKey, reason = SYL.RaidSchedule.NextNight(today)

    if not dayKey then
        DashboardParts.Empty(tile,
            "Nothing scheduled in the next four weeks. /syl schedule says "
            .. "what this addon thinks your raid days are.")

        return
    end

    -- Days rather than a date as the headline: "in 2 days" is what is being
    -- asked, and the date is the supporting detail rather than the answer.
    local days = DaysUntil(today, dayKey) or 0

    DashboardParts.Headline(tile,
        days == 0 and "Tonight" or (days == 1 and "Tomorrow" or ("in " .. days)),
        days > 1 and "days" or nil)

    local out = SYL.Absences.WhoIsOut(dayKey)

    DashboardParts.Row(tile, 1, "Raiding", SYL.RaidSchedule.WeekdayName(dayKey))
    DashboardParts.Row(tile, 2, "Out that night", #out,
        "textPrimary", #out > 0 and "warning" or "textMuted")

    DashboardParts.Caption(tile,
        SYL.Utilities.FormatDateOnly(SYL.RaidSchedule.TimestampOf(dayKey))
        .. " · " .. (reason == "weekly" and "your usual raid days"
            or (reason == "calendar" and "from the guild calendar" or "typed in")))
end

-- Who is out --------------------------------------------------------------
--
-- Its own tile rather than a couple of rows under the next raid night. The two
-- are related, but this one is a list that grows with the guild and that one is
-- a date — folding them meant the names were the first thing squeezed out.
--
-- Absences are typed, and that is not a placeholder for something better. An
-- addon makes no HTTP requests, so the Discord channel where this guild
-- actually posts them cannot be read from in game by any route at all. The
-- empty state says so, because "nobody is out" and "nothing here can see your
-- Discord" are very different claims.
SYL.DashboardWidgets.RENDERERS.whoIsOut = function(tile)
    local today = SYL.RaidSchedule.TodayKey()
    local dayKey = SYL.RaidSchedule.NextNight(today) or today
    local out = SYL.Absences.WhoIsOut(dayKey)

    -- AND WHOEVER IS OUT AFTER THAT. Aimee: "can you show the next people who
    -- are marked as out even if its not the current week? so it would show
    -- syzzlac is out on xx date currently."
    --
    -- WhoIsOut answers about one night, which is right for the calendar and
    -- wrong here: an absence typed three weeks ahead -- the sort most worth
    -- typing early -- left this tile reading "Nobody has said they are out"
    -- until the week it mattered, with the absence sitting in the database
    -- the whole time. The one screen that exists to show it was the one
    -- screen not showing it.
    local capacity = DashboardParts.RowCapacity(tile)
    local later = SYL.Absences.Upcoming(dayKey, capacity)

    if #out == 0 and #later == 0 then
        DashboardParts.Empty(tile,
            "Nobody has said they are out.\n\nAdd one with "
            .. "/syl out <name> <days> — an addon cannot read your Discord, "
            .. "so absences are typed in.")

        return
    end

    -- The headline counts TONIGHT, because that is the number an officer is
    -- deciding on. Somebody out in three weeks is not a hole in this raid.
    if #out > 0 then
        DashboardParts.Headline(tile, #out,
            #out == 1 and "player out" or "players out")
    else
        DashboardParts.Headline(tile, 0, "out for the next night")
    end

    local index = 0

    local function Row(absence, when)
        index = index + 1

        -- PlayerRow, not Row. The two tiles either side of this one -- last
        -- night's winners and who is due -- both name players in class color
        -- through the class-colored version of this same call, and this one
        -- did not, for no reason but that it was written separately.
        --
        -- The class comes from the registry rather than from the absence:
        -- Core/Absences.lua stamps `key` with the player's GUID when the
        -- absence is written, which is exactly what Players.Get resolves.
        -- Nothing is stored twice and no schema changes.
        DashboardParts.PlayerRow(tile, index,
            absence.name,
            (SYL.Players.Get(absence.key) or {}).class,
            when,
            nil,
            "textMuted")
    end

    for position = 1, math.min(capacity, #out) do
        local absence = out[position]

        Row(absence, absence.multiDay
            and ("to " .. SYL.Utilities.FormatDateOnly(
                SYL.RaidSchedule.TimestampOf(absence.to)))
            or (absence.reason or "out"))
    end

    -- A heading between the two, so "out tonight" and "out later" are not
    -- read as one list. Skipped when there is nothing above it to separate.
    if #out > 0 and #later > 0 and index < capacity then
        index = index + 1

        DashboardParts.Row(tile, index, "LATER", "", "textMuted", "textMuted")
    end

    for _, absence in ipairs(later) do
        if index >= capacity then
            break
        end

        -- THE DATE, which is the whole point of showing these at all:
        -- "Syzzlac is out" is not actionable, "Syzzlac is out on 09/22" is.
        Row(absence, SYL.Utilities.FormatDateOnly(
            SYL.RaidSchedule.TimestampOf(absence.from)
        ))
    end

    DashboardParts.Caption(tile,
        "for " .. SYL.Utilities.FormatDateOnly(
            SYL.RaidSchedule.TimestampOf(dayKey)
        )
        .. (#later > 0 and " · and later" or ""))
end
