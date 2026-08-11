-- UI/DueRows.lua
--
-- One row of the due list, and the header above it.
--
-- Split out of DueWindow the moment it crossed the size limit, the same way
-- RosterRows came out of RosterWindow. That file decides who is on the list
-- and how the scope narrows it; this one draws a person and owns the columns.
--
-- The columns live here rather than in the window because the widths and the
-- drawing are one decision: a cell is set to its column's width, and moving
-- one without the other is how a number ends up truncated. syl_check measures
-- them against the window width, so the window still states that width and
-- these still have to fit inside it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Utilities = SYL.Utilities

local DueRows = {}
SYL.DueRows = DueRows

-- 608 across, inside a 660 window less syl_check's 50px inset.
DueRows.COLUMNS = {
    { key = "name", label = "PLAYER", width = 140, gap = 10 },
    { key = "dry", label = "DRY NIGHTS", width = 84, gap = 8 },
    { key = "nights", label = "RAIDED", width = 60, gap = 8 },
    { key = "last", label = "LAST UPGRADE", width = 104, gap = 8 },
    { key = "status", label = "", width = 178, gap = 8 },
}

DueRows.OFFSETS = SYL.Widgets.ColumnOffsets(DueRows.COLUMNS)

function DueRows.CreateHeader(parent, listTop)
    local header = CreateFrame("Frame", nil, parent)

    header:SetHeight(22)
    header:SetPoint("TOPLEFT", 16, -(listTop - 24))
    header:SetPoint("TOPRIGHT", -34, -(listTop - 24))

    header.background =
        Theme.CreateSolidTexture(header, "headerBar", "BACKGROUND")

    header.background:SetAllPoints()

    local separator = Theme.CreateSeparator(header)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)

    for _, column in ipairs(DueRows.COLUMNS) do
        local label =
            Theme.CreateText(header, Theme.sizes.columnHeader, "textMuted")

        label:SetPoint("LEFT", DueRows.OFFSETS[column.key], 0)
        label:SetWidth(column.width)
        label:SetText(column.label)
    end

    return header
end

function DueRows.Create(parent, index, listTop, rowHeight)
    -- A Button so a row opens that player's full history, the same way the
    -- players window does. "Why are they top of this list" is the immediate
    -- next question and the answer already has a window.
    local row = CreateFrame("Button", nil, parent)
    local top = listTop + (index - 1) * rowHeight

    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 16, -top)
    row:SetPoint("TOPRIGHT", -34, -top)

    row:SetScript("OnClick", function(self)
        if self.entry then
            SYL:OpenPlayerDetail(self.entry)
        end
    end)

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.cells = {}

    for _, column in ipairs(DueRows.COLUMNS) do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

        text:SetPoint("LEFT", DueRows.OFFSETS[column.key], 0)
        text:SetWidth(column.width)

        row.cells[column.key] = text
    end

    return row
end

function DueRows.Fill(row, entry, rank)
    local cells = row.cells

    -- Read by the click handler. Rows are pooled, so this is set per refresh
    -- rather than captured when the row was built.
    row.entry = entry

    cells.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(
            cells.name, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(cells.name, "textPrimary")
    end

    cells.dry:SetText(entry.nightsSinceUpgrade)

    -- The top three are the answer to "who next", so they are the only ones
    -- worth coloring. Everything below is context.
    Theme.SetTextColor(
        cells.dry, rank <= 3 and "accent" or "textPrimary"
    )

    cells.nights:SetText(entry.nights)
    Theme.SetTextColor(cells.nights, "textMuted")

    if entry.lastUpgradeAt then
        cells.last:SetText(Utilities.FormatDateOnly(entry.lastUpgradeAt))
        Theme.SetTextColor(cells.last, "textSecondary")
    else
        cells.last:SetText("never")
        Theme.SetTextColor(cells.last, "textMuted")
    end

    -- The number the list is SORTED by, not a different one. The window ranks
    -- by share now, and a row showing a drought beside a share ordering is two
    -- claims at once — the reader has no way to tell which produced the order.
    cells.status:SetText(SYL.LootScore.Describe(entry))
    Theme.SetTextColor(cells.status, "textMuted")
end
