-- UI/RaidWindow.lua
--
-- Every raid night: where it was, what was pulled, how long it ran and how
-- many people were there.
--
-- Attendance here comes from the group roster read at each pull, not from
-- loot data, so a night with no drops still counts as a night raided.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local RaidSession = SYL.RaidSession
local Utilities = SYL.Utilities

local WINDOW_WIDTH = 690
local ROW_HEIGHT = 24
-- Rows the window opens with, the most it will ever build, and how many
-- are on screen right now. The pool has a ceiling because a window dragged
-- to the height of a tall monitor must not build rows without bound.
local DEFAULT_ROWS = 14
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
local LIST_TOP = 116

local COLUMNS = {
    { key = "date", label = "DATE", width = 90, gap = 10 },
    { key = "instance", label = "INSTANCE", width = 214, gap = 8 },
    { key = "difficulty", label = "DIFF", width = 52, gap = 8 },
    { key = "pulls", label = "PULLS", width = 46, gap = 8 },
    { key = "kills", label = "KILLS", width = 46, gap = 8 },
    { key = "raiders", label = "RAIDERS", width = 58, gap = 8 },
    { key = "duration", label = "LENGTH", width = 58, gap = 8 },
}

local frame
local rows = {}
local offset = 0

local columnOffset = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        x = x + column.width
    end
end

local function Sessions()
    local sessions = {}

    for _, session in ipairs(SYL.GetAllRaids()) do
        table.insert(sessions, session)
    end

    -- Newest night first, which is the one anyone is asking about.
    table.sort(sessions, function(left, right)
        return (left.startedAt or 0) > (right.startedAt or 0)
    end)

    return sessions
end

local Refresh

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)

    header:SetHeight(22)
    header:SetPoint("TOPLEFT", 16, -(LIST_TOP - 24))
    header:SetPoint("TOPRIGHT", -34, -(LIST_TOP - 24))

    header.background =
        Theme.CreateSolidTexture(header, "headerBar", "BACKGROUND")

    header.background:SetAllPoints()

    local separator = Theme.CreateSeparator(header)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)

    for _, column in ipairs(COLUMNS) do
        local label =
            Theme.CreateText(header, Theme.sizes.columnHeader, "textMuted")

        label:SetPoint("LEFT", columnOffset[column.key], 0)
        label:SetWidth(column.width)
        label:SetText(column.label)
    end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -34, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.cells = {}

    for _, column in ipairs(COLUMNS) do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

        text:SetPoint("LEFT", columnOffset[column.key], 0)
        text:SetWidth(column.width)

        row.cells[column.key] = text
    end

    return row
end

local function FillRow(row, session)
    local cells = row.cells
    local pulls = #(session.encounters or {})
    local kills = RaidSession.GetKillCount(session)

    -- From the timestamp rather than the stored dateText, which is written
    -- as ISO and is data rather than something to show. Formatting it here
    -- means nights recorded before this read the same as nights recorded
    -- after it.
    cells.date:SetText(
        session.startedAt
            and SYL.Utilities.FormatDateOnly(session.startedAt)
            or tostring(session.dateText or "?")
    )
    cells.instance:SetText(tostring(session.instanceName or "Unknown"))
    cells.difficulty:SetText(
        Utilities.ShortDifficulty(session.difficultyID, session.difficultyName)
        or ""
    )
    cells.pulls:SetText(pulls)

    cells.kills:SetText(kills)

    -- A night where nothing died reads muted rather than as a bad number.
    if kills == 0 then
        Theme.SetTextColor(cells.kills, "textMuted")
    else
        Theme.SetTextColor(cells.kills, "accent")
    end

    cells.raiders:SetText(session.rosterCount or 0)
    cells.duration:SetText(RaidSession.GetDurationMinutes(session) .. "m")
end

Refresh = function()
    if not frame then
        return
    end

    local sessions = Sessions()
    local total = #sessions
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    local kills = 0

    for _, session in ipairs(sessions) do
        kills = kills + RaidSession.GetKillCount(session)
    end

    -- Rows are sessions and the count is nights, and those differ: a Tuesday
    -- that cleared Heroic and then pulled Mythic is two rows of one night.
    -- The rows stay split because they describe different runs; the number
    -- has to say nights, because that is the word next to it and the unit
    -- every attendance figure in the addon is measured in.
    local nights = RaidSession.CountNights(sessions)

    frame.summaryText:SetText(
        nights
        .. (nights == 1 and " raid night" or " raid nights")
        .. "  ·  "
        .. kills
        .. " boss kills"
    )

    for index = 1, visibleRows do
        local session = sessions[index + offset]
        local row = rows[index] or CreateRow(frame, index)

        rows[index] = row

        if session then
            FillRow(row, session)
            row:Show()
        else
            row:Hide()
        end
    end

    for index = visibleRows + 1, #rows do
        rows[index]:Hide()
    end

    if total == 0 then
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootRaidFrame",
        title = "RAID NIGHTS",
        key = "raids",

        width = WINDOW_WIDTH,
        listTop = LIST_TOP,
        rowHeight = ROW_HEIGHT,
        footer = FOOTER_HEIGHT,
        defaultRows = DEFAULT_ROWS,
        maxRows = MAX_ROWS,

        onRows = function(count)
            visibleRows = count
            Refresh()
        end,
    })

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -74)
    hint:SetText(
        "Raiders counts everyone in the group at any pull, not just winners."
    )

    CreateHeader(frame)

    for index = 1, DEFAULT_ROWS do
        rows[index] = CreateRow(frame, index)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.title, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetText("No raid nights recorded yet.")
    frame.emptyText:Hide()

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = #Sessions()
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenRaidWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
