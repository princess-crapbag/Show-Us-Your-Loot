-- UI/NightsPanel.lua
--
-- The Nights tab: a month of days, the ones you raided shaded with what died,
-- and one dense stat panel underneath for whichever day is clicked.
--
-- A GRID BECAUSE THE QUESTION IS "WHEN". Attendance and cadence are shape
-- questions — three weeks with a hole in the middle is visible in a calendar
-- and has to be counted in a list. The table that used to sit under this was
-- deleted rather than moved down: it repeated the grid.
--
-- IT OPENS ON THE MONTH OF THE MOST RECENT NIGHT, not on today. Opening on
-- today shows an empty grid to anybody whose last raid was three weeks ago,
-- which reads as "nothing was recorded" rather than "look one month back".
--
-- THE NEXT RAID NIGHT IS NOT DRAWN, and that is the calendar blocker rather
-- than an oversight. Nothing here reads C_Calendar, so the addon does not know
-- when the guild next raids. The panel says so where the accent would be, in
-- the same way the dashboard tile does — an honest blank beats a guess.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local NightsPanel = {}
SYL.NightsPanel = NightsPanel

local COLUMNS = 7
local CELL_WIDTH = 122
local CELL_GAP = 2

local GRID_TOP = 56
local MONTH_ROWS = 6
local MONTH_CELL_HEIGHT = 38
local WEEK_CELL_HEIGHT = 96

local STATS_HEIGHT = 152

local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local frame
local cells = {}
local year, month
local weekOffset = 0
local view = "month"
local selectedKey
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

local function Build()
    return SYL.NightIndex.Build(SYL.GetAllRaids(), SYL.GetAllDrops())
end

local function StepMonth(by)
    month = month + by

    while month > 12 do
        month, year = month - 12, year + 1
    end

    while month < 1 do
        month, year = month + 12, year - 1
    end

    weekOffset = 0
end

--------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------

local function CellHeight()
    return view == "week" and WEEK_CELL_HEIGHT or MONTH_CELL_HEIGHT
end

local function CreateCell(index)
    local cell = CreateFrame("Button", nil, frame)

    local column = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)

    cell:SetPoint(
        "TOPLEFT",
        column * (CELL_WIDTH + CELL_GAP),
        -(GRID_TOP + row * (CellHeight() + CELL_GAP))
    )

    cell:SetSize(CELL_WIDTH, CellHeight())

    cell.back = Theme.CreateSolidTexture(cell, "rowAlt", "BACKGROUND")
    cell.back:SetAllPoints()

    cell.hover = Theme.CreateSolidTexture(cell, "rowHover", "BORDER")
    cell.hover:SetAllPoints()
    cell.hover:Hide()

    cell:SetScript("OnEnter", function() cell.hover:Show() end)
    cell:SetScript("OnLeave", function() cell.hover:Hide() end)

    cell.day = Theme.CreateText(cell, Theme.sizes.rowSmall, "textMuted")
    cell.day:SetPoint("TOPLEFT", 5, -4)

    cell.kills = Theme.CreateText(cell, Theme.sizes.rowSmall, "textPrimary")
    cell.kills:SetPoint("TOPRIGHT", -5, -4)
    cell.kills:SetJustifyH("RIGHT")

    cell.detail = Theme.CreateText(cell, Theme.sizes.rowSmall, "textSecondary")
    cell.detail:SetPoint("BOTTOMLEFT", 5, 4)
    cell.detail:SetPoint("BOTTOMRIGHT", -5, 4)
    cell.detail:SetJustifyH("LEFT")
    cell.detail:SetWordWrap(false)

    cell:SetScript("OnClick", function()
        if cell.dayKey then
            NightsPanel.Select(cell.dayKey)
        end
    end)

    cells[index] = cell

    return cell
end

local function PositionCell(cell, index)
    local column = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)

    cell:ClearAllPoints()
    cell:SetPoint(
        "TOPLEFT",
        column * (CELL_WIDTH + CELL_GAP),
        -(GRID_TOP + row * (CellHeight() + CELL_GAP))
    )

    cell:SetSize(CELL_WIDTH, CellHeight())
end

-- A day outside the month keeps its cell so the grid does not reflow; it just
-- says nothing. Blanking is not hiding: a hidden cell would let the row below
-- move up and the weekday columns would stop lining up.
local function DrawBlank(cell)
    cell.dayKey = nil
    cell.day:SetText("")
    cell.kills:SetText("")
    cell.detail:SetText("")
    cell.back:SetAlpha(0.25)
    cell:Show()
end

local function DrawDay(cell, dayNumber, dayKey, night, isSelected)
    cell.dayKey = dayKey
    cell.day:SetText(tostring(dayNumber))
    cell.back:SetAlpha(1)

    if not night then
        cell.kills:SetText("")
        cell.detail:SetText("")

        Theme.SetTextColor(cell.day, "textMuted")
        cell:Show()

        return
    end

    -- Shaded with the kill count, which is what makes a good night and a wipe
    -- night different at a glance rather than both just being "we raided".
    Theme.SetTextColor(cell.day, "textPrimary")

    cell.kills:SetText(night.kills .. "/" .. night.pulls)
    Theme.SetTextColor(cell.kills, night.kills > 0 and "accent" or "textMuted")

    cell.detail:SetText(
        night.rosterCount .. " raiders · " .. night.drops .. " drops"
    )

    if isSelected then
        cell.back:SetAlpha(1)
        Theme.SetTextColor(cell.detail, "textPrimary")
    else
        Theme.SetTextColor(cell.detail, "textSecondary")
    end

    cell:Show()
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

Refresh = function()
    if not frame then
        return
    end

    local days, byDay = Build()

    if not year then
        year, month = SYL.NightIndex.LatestMonth(days)
    end

    frame.monthLabel:SetText((MONTHS[month] or "?") .. " " .. year)
    frame.viewButton.label:SetText(view == "month" and "Month" or "Week")

    local daysInMonth = SYL.NightIndex.DaysInMonth(year, month)
    local firstWeekday = SYL.NightIndex.FirstWeekday(year, month)

    local total, startDay

    if view == "week" then
        total = COLUMNS
        startDay = 1 + weekOffset * COLUMNS - (firstWeekday - 1)
    else
        total = COLUMNS * MONTH_ROWS
        startDay = 1 - (firstWeekday - 1)
    end

    local raidedThisMonth = 0

    for index = 1, total do
        local cell = cells[index] or CreateCell(index)

        PositionCell(cell, index)

        local dayNumber = startDay + index - 1

        if dayNumber < 1 or dayNumber > daysInMonth then
            DrawBlank(cell)
        else
            local dayKey = SYL.NightIndex.DayKeyFor(year, month, dayNumber)
            local night = byDay[dayKey]

            if night then
                raidedThisMonth = raidedThisMonth + 1
            end

            DrawDay(cell, dayNumber, dayKey, night, dayKey == selectedKey)
        end
    end

    for index = total + 1, #cells do
        cells[index]:Hide()
    end

    SYL.NightStats.Render(frame.stats, selectedKey and byDay[selectedKey] or nil)

    frame.caption:SetText(
        raidedThisMonth .. " nights this month · " .. #days
        .. " recorded in total · the next raid night needs the guild calendar, "
        .. "which nothing here reads yet"
    )
end

NightsPanel.Refresh = Refresh

function NightsPanel.Select(key)
    selectedKey = key

    Refresh()
end

function NightsPanel.SetView(next)
    view = (next == "week") and "week" or "month"
    weekOffset = 0

    Refresh()
end

function NightsPanel.ToggleView()
    NightsPanel.SetView(view == "month" and "week" or "month")
end

function NightsPanel.Step(by)
    if view == "week" then
        weekOffset = weekOffset + by

        local weeks = math.ceil(
            (SYL.NightIndex.DaysInMonth(year, month)
                + SYL.NightIndex.FirstWeekday(year, month) - 1) / COLUMNS
        )

        if weekOffset < 0 then
            StepMonth(-1)
            weekOffset = 0
        elseif weekOffset >= weeks then
            StepMonth(1)
        end
    else
        StepMonth(by)
    end

    Refresh()
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function NightsPanel.Create(parent)
    frame = CreateFrame("Frame", nil, parent)

    frame:SetPoint("TOPLEFT", 16, -100)
    frame:SetPoint("BOTTOMRIGHT", -16, 52)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText("NIGHTS")

    frame.prev = Theme.CreateButton(frame, 28, 20, "<", function()
        NightsPanel.Step(-1)
    end)
    frame.prev:SetPoint("TOPLEFT", title, "TOPRIGHT", 14, -2)

    frame.monthLabel = Theme.CreateText(frame, Theme.sizes.row, "textPrimary")
    frame.monthLabel:SetPoint("LEFT", frame.prev, "RIGHT", 10, 0)
    frame.monthLabel:SetWidth(150)
    frame.monthLabel:SetJustifyH("CENTER")

    frame.next = Theme.CreateButton(frame, 28, 20, ">", function()
        NightsPanel.Step(1)
    end)
    frame.next:SetPoint("LEFT", frame.monthLabel, "RIGHT", 10, 0)

    frame.viewButton = Theme.CreateButton(frame, 80, 20, "Month", function()
        NightsPanel.ToggleView()
    end)
    frame.viewButton:SetPoint("LEFT", frame.next, "RIGHT", 12, 0)

    SYL.Tooltips.Attach(
        frame.viewButton,
        "Month / Week",
        "Week shows one row at a time with room for more on each day. The "
        .. "arrows move a week at a time in that view and a month at a time "
        .. "in this one."
    )

    for column = 1, COLUMNS do
        local heading = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")

        heading:SetPoint("TOPLEFT", (column - 1) * (CELL_WIDTH + CELL_GAP) + 5, -40)
        heading:SetText(WEEKDAYS[column])
    end

    frame.stats = SYL.NightStats.Create(frame, STATS_HEIGHT)

    frame.caption = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 2, 2)
    frame.caption:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.caption:SetJustifyH("LEFT")
    frame.caption:SetWordWrap(false)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        NightsPanel.Step(delta > 0 and -1 or 1)
    end)

    frame:SetScript("OnShow", Refresh)

    frame:Hide()

    return frame
end
