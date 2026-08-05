-- UI/PlayerWindow.lua
--
-- Per-player loot numbers: how often someone was eligible, what they actually
-- won, and how long it has been.
--
-- Upgrades and transmog are separate columns rather than one "wins" total,
-- because treating them as the same thing is exactly how loot starts looking
-- fairer than it was.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Analytics = SYL.Analytics
local Utilities = SYL.Utilities

local WINDOW_WIDTH = 760
local ROW_HEIGHT = 24
local VISIBLE_ROWS = 16
local LIST_TOP = 150

local COLUMNS = {
    { key = "name", label = "PLAYER", width = 130, gap = 10 },
    { key = "rank", label = "GUILD RANK", width = 110, gap = 8 },
    { key = "nights", label = "NIGHTS", width = 50, gap = 8 },
    { key = "eligible", label = "ROLLED ON", width = 66, gap = 8 },
    { key = "upgrades", label = "UPGRADES", width = 68, gap = 8 },
    { key = "mog", label = "MOG", width = 40, gap = 8 },
    { key = "lastWin", label = "LAST UPGRADE", width = 100, gap = 8 },
    { key = "drought", label = "DAYS", width = 46, gap = 8 },
}

local frame
local rows = {}
local headerLabels = {}

local sortKey = "upgrades"
local sortReversed = false
local offset = 0
local guildOnly = false
local emptyOnly = false

local columnOffset = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        x = x + column.width
    end
end

local function CurrentStats()
    local stats = Analytics.BuildPlayerStats(SYL.GetActiveDrops())

    if guildOnly then
        stats = Analytics.FilterGuildOnly(stats)
    end

    if emptyOnly then
        stats = Analytics.FilterEmptyHanded(stats)
    end

    return Analytics.Sort(stats, sortKey, sortReversed)
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
        local button = CreateFrame("Button", nil, header)

        button:SetPoint("LEFT", columnOffset[column.key], 0)
        button:SetSize(column.width, 22)

        local label =
            Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

        label:SetAllPoints()
        label:SetText(column.label)

        button:SetScript("OnClick", function()
            -- Clicking the active column flips it; a new column starts in its
            -- natural direction.
            if sortKey == column.key then
                sortReversed = not sortReversed
            else
                sortKey = column.key
                sortReversed = false
            end

            offset = 0

            Refresh()
        end)

        headerLabels[column.key] = label
    end

    return header
end

local function UpdateHeaderLabels()
    for _, column in ipairs(COLUMNS) do
        local label = headerLabels[column.key]

        if sortKey == column.key then
            label:SetText(column.label .. (sortReversed and "  ^" or "  v"))
            Theme.SetTextColor(label, "accent")
        else
            label:SetText(column.label)
            Theme.SetTextColor(label, "textMuted")
        end
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

local function FillRow(row, entry)
    local cells = row.cells

    cells.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        cells.name:SetTextColor(classColor[1], classColor[2], classColor[3])
    else
        Theme.SetTextColor(cells.name, "textPrimary")
    end

    -- Blank rather than "not in guild": most of a pug raid is not, and saying
    -- so on every row would be noise.
    cells.rank:SetText(entry.guildRank or "")

    cells.nights:SetText(entry.nights)
    cells.eligible:SetText(entry.eligible)

    cells.upgrades:SetText(entry.upgradeWins)

    if entry.upgradeWins == 0 then
        Theme.SetTextColor(cells.upgrades, "textMuted")
    else
        Theme.SetTextColor(cells.upgrades, "accent")
    end

    cells.mog:SetText(entry.mogWins > 0 and entry.mogWins or "")
    Theme.SetTextColor(cells.mog, "textMuted")

    if entry.lastWinAt then
        cells.lastWin:SetText(Utilities.FormatDateOnly(entry.lastWinAt))
        Theme.SetTextColor(cells.lastWin, "textSecondary")
    else
        cells.lastWin:SetText("never")
        Theme.SetTextColor(cells.lastWin, "textMuted")
    end

    cells.drought:SetText(entry.droughtDays)
end

Refresh = function()
    if not frame then
        return
    end

    UpdateHeaderLabels()

    local stats = CurrentStats()
    local total = #stats
    local maxOffset = math.max(0, total - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    local totals = Analytics.Summarise(stats)

    frame.summaryText:SetText(
        total
        .. (total == 1 and " player" or " players")
        .. "  ·  "
        .. totals.guildMembers
        .. " in guild"
        .. "  ·  "
        .. totals.emptyHanded
        .. " with no upgrade"
    )

    for index = 1, VISIBLE_ROWS do
        local entry = stats[index + offset]
        local row = rows[index]

        if entry then
            FillRow(row, entry)
            row:Show()
        else
            row:Hide()
        end
    end

    if total == 0 then
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end
end

local function CreateFilters(parent)
    frame.guildButton =
        Theme.CreateButton(parent, 110, 20, "Guild only", function()
            guildOnly = not guildOnly
            offset = 0

            Theme.SetTextColor(
                frame.guildButton.label,
                guildOnly and "accent" or "textPrimary"
            )

            Refresh()
        end)

    frame.guildButton:SetPoint("TOPLEFT", 18, -108)

    frame.emptyButton =
        Theme.CreateButton(parent, 140, 20, "No upgrade yet", function()
            emptyOnly = not emptyOnly
            offset = 0

            Theme.SetTextColor(
                frame.emptyButton.label,
                emptyOnly and "accent" or "textPrimary"
            )

            Refresh()
        end)

    frame.emptyButton:SetPoint("LEFT", frame.guildButton, "RIGHT", 6, 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootPlayerFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, LIST_TOP + VISIBLE_ROWS * ROW_HEIGHT + 56)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("PLAYERS")

    frame.summaryText =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    frame.summaryText:SetPoint("TOPLEFT", 27, -42)
    frame.summaryText:SetPoint("TOPRIGHT", -16, -42)

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -76)
    hint:SetText(
        "Upgrades counts Need and offspec wins only. Transmog is listed apart."
    )

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    CreateFilters(frame)
    CreateHeader(frame)

    for index = 1, VISIBLE_ROWS do
        rows[index] = CreateRow(frame, index)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.title, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetText("No drops recorded yet.")
    frame.emptyText:Hide()

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local exportButton =
        Theme.CreateButton(frame, 100, 26, "Export", function()
            SYL:OpenExportWindow()
        end)

    exportButton:SetPoint("BOTTOMLEFT", 16, 12)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = #CurrentStats()
        local maxOffset = math.max(0, total - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenPlayerWindow()
    local window = CreateWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
