-- UI/DatePicker.lua
--
-- A month you can click, for the two date boxes on the loot filter bar.
--
-- WHY. Aimee: "also add a clickable calendar on the date picker." The boxes
-- take MM-DD-YYYY typed by hand, which is fine once you know the format and
-- is a guess before then -- the placeholder is the only thing that ever said
-- so, and it disappears the moment you start typing. Picking a day off a
-- month cannot be typed wrong.
--
-- ONE POPUP, REUSED. Both boxes share it and it is built the first time
-- either is pressed, so a window nobody opens costs nothing. It remembers
-- nothing between openings except which month to show, which is worked out
-- from whatever is already in the box.
--
-- IT WRITES THE SAME STRING A PERSON WOULD TYPE, rather than reaching past
-- the box into the filter state. The box's own OnEnterPressed path parses,
-- validates, colors the text on a bad date and calls onChange -- so going
-- through it means the two routes cannot drift, and a picked date is exactly
-- a typed one that nobody could get wrong.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local DatePicker = {}
SYL.DatePicker = DatePicker

local COLUMNS = 7
local ROWS = 6

local CELL = 24
local CELL_GAP = 1
local PAD = 8
local HEADER = 44
local FOOTER = 26

local WIDTH = PAD * 2 + COLUMNS * CELL + (COLUMNS - 1) * CELL_GAP
local HEIGHT = HEADER + ROWS * (CELL + CELL_GAP) + FOOTER

local WEEKDAYS = { "S", "M", "T", "W", "T", "F", "S" }

local frame
local cells = {}
local year, month
local onPick

--------------------------------------------------------------------------
-- The date this addon writes
--------------------------------------------------------------------------

-- MM-DD-YYYY, which is what the boxes say and what Core/Filters.lua parses.
-- US order deliberately -- see the placeholder in UI/FilterBar.lua.
function DatePicker.Format(y, m, d)
    return string.format("%02d-%02d-%04d", m, d, y)
end

-- Which month to open on: the one already in the box if it holds a date, and
-- this month otherwise. Reading the box rather than remembering means opening
-- the To box after typing a From lands you where you were, not in January.
function DatePicker.MonthFor(text)
    if type(text) == "string" then
        local m, d, y = text:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")

        if m and y then
            return tonumber(y), tonumber(m)
        end
    end

    local today = date("*t")

    return today.year, today.month
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local function Step(delta)
    month = month + delta

    if month > 12 then
        month = 1
        year = year + 1
    elseif month < 1 then
        month = 12
        year = year - 1
    end

    DatePicker.Draw()
end

local function CreateCell(index)
    local cell = CreateFrame("Button", nil, frame)

    local column = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)

    cell:SetSize(CELL, CELL)
    cell:SetPoint(
        "TOPLEFT",
        PAD + column * (CELL + CELL_GAP),
        -(HEADER + row * (CELL + CELL_GAP))
    )

    cell.back = Theme.CreateSolidTexture(cell, "rowAlt", "BACKGROUND")
    cell.back:SetAllPoints()
    cell.back:Hide()

    cell.hover = Theme.CreateSolidTexture(cell, "rowHover", "BORDER")
    cell.hover:SetAllPoints()
    cell.hover:Hide()

    cell.label = Theme.CreateText(cell, Theme.sizes.rowSmall, "textPrimary")
    cell.label:SetPoint("CENTER")

    cell:SetScript("OnEnter", function(self)
        if self.day then
            self.hover:Show()
        end
    end)

    cell:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)

    cell:SetScript("OnClick", function(self)
        if not self.day then
            return
        end

        local picked = DatePicker.Format(year, month, self.day)

        frame:Hide()

        if onPick then
            onPick(picked)
        end
    end)

    return cell
end

function DatePicker.Draw()
    if not frame then
        return
    end

    frame.monthLabel:SetText((MONTHS[month] or "?") .. " " .. year)

    local days = SYL.NightCalendar.DaysInMonth(year, month)
    local first = SYL.NightCalendar.FirstWeekday(year, month)

    local today = date("*t")

    for index = 1, COLUMNS * ROWS do
        local cell = cells[index] or CreateCell(index)
        cells[index] = cell

        local day = index - first + 1

        if day >= 1 and day <= days then
            cell.day = day
            cell.label:SetText(day)

            local isToday = year == today.year
                and month == today.month
                and day == today.day

            Theme.SetTextColor(cell.label, isToday and "accent" or "textPrimary")

            cell.back:SetShown(isToday)
            cell:Show()
        else
            -- A day outside the month is drawn as nothing rather than as the
            -- neighbouring month's number: this picker returns one date and a
            -- greyed 31 from last month is a thing people click.
            cell.day = nil
            cell.label:SetText("")
            cell.back:Hide()
            cell:Hide()
        end
    end
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootDatePicker", UIParent, "BackdropTemplate"
    )

    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)

    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    frame.prev = Theme.CreateButton(frame, 20, 18, "<", function()
        Step(-1)
    end)

    frame.prev:SetPoint("TOPLEFT", PAD, -10)

    frame.next = Theme.CreateButton(frame, 20, 18, ">", function()
        Step(1)
    end)

    frame.next:SetPoint("TOPRIGHT", -PAD, -10)

    frame.monthLabel = Theme.CreateText(frame, Theme.sizes.rowSmall,
        "textPrimary")
    frame.monthLabel:SetPoint("TOP", 0, -12)

    for column = 1, COLUMNS do
        local heading = Theme.CreateText(
            frame, Theme.sizes.columnHeader, "textMuted"
        )

        heading:SetPoint(
            "TOPLEFT",
            PAD + (column - 1) * (CELL + CELL_GAP), -(HEADER - 14)
        )

        heading:SetWidth(CELL)
        heading:SetJustifyH("CENTER")
        heading:SetText(WEEKDAYS[column])
    end

    -- CLEAR IS AS IMPORTANT AS PICKING. A date box with something in it
    -- narrows the list, and the only other way out is selecting the text and
    -- deleting it -- which is the fiddly thing this window exists to replace.
    frame.clear = Theme.CreateButton(frame, 56, 18, "Clear", function()
        frame:Hide()

        if onPick then
            onPick("")
        end
    end)

    frame.clear:SetPoint("BOTTOMLEFT", PAD, 6)

    frame.today = Theme.CreateButton(frame, 56, 18, "Today", function()
        local now = date("*t")

        frame:Hide()

        if onPick then
            onPick(DatePicker.Format(now.year, now.month, now.day))
        end
    end)

    frame.today:SetPoint("BOTTOMRIGHT", -PAD, 6)

    frame:Hide()

    return frame
end

-- Opens under `anchor`, showing the month `text` names, and calls `callback`
-- with the date that gets picked -- or with "" for Clear.
--
-- Pressing the same button again closes it, which is what a person expects
-- from a thing that opened under a button.
function DatePicker.Toggle(anchor, text, callback)
    local window = CreateWindow()

    if window:IsShown() and window.anchor == anchor then
        window:Hide()

        return nil
    end

    window.anchor = anchor
    onPick = callback

    year, month = DatePicker.MonthFor(text)

    DatePicker.Draw()

    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    window:Show()
    window:Raise()

    return window
end

function DatePicker.IsShown()
    return frame ~= nil and frame:IsShown() and true or false
end
