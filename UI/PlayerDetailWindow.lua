-- UI/PlayerDetailWindow.lua
--
-- One player's history: every drop they could have had, in order, with what
-- they chose and what they got.
--
-- The players list gives totals. This gives the reason behind them — eleven
-- eligibles and no upgrades reads very differently depending on whether they
-- passed eleven times or lost eleven rolls, and only this window can tell you
-- which.
--
-- Opened by clicking a row in the players window. Clicking a different player
-- swaps the contents rather than closing, which is what comparing two raiders
-- actually looks like.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Utilities = SYL.Utilities

-- 680 rather than 660: syl_check measures a row as the window less a 50px
-- inset, and the columns total 618. The item column holds the longest values
-- and shaving it to fit would truncate exactly what the window is for.
local WINDOW_WIDTH = 680
local ROW_HEIGHT = 20
local VISIBLE_ROWS = 16
local LIST_TOP = 158

local frame
local rows = {}
local currentKey
local currentEntry
local offset = 0

local COLUMNS = {
    { key = "date", label = "DATE", width = 92, gap = 6 },
    { key = "item", label = "ITEM", width = 208, gap = 6 },
    { key = "boss", label = "BOSS", width = 132, gap = 6 },
    { key = "chose", label = "CHOSE", width = 74, gap = 6 },
    { key = "roll", label = "ROLL", width = 40, gap = 6 },
    { key = "won", label = "", width = 36, gap = 6 },
}

local columnOffset = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        x = x + column.width
    end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

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
    local drop = entry.drop
    local cells = row.cells

    cells.date:SetText(Utilities.FormatDateCompact(drop.timestamp))
    Theme.SetTextColor(cells.date, "textMuted")

    cells.item:SetText(
        tostring(drop.itemLink or drop.itemName or "Unknown item")
    )

    cells.boss:SetText(tostring(drop.encounterName or "Unknown"))
    Theme.SetTextColor(cells.boss, "textSecondary")

    -- What they asked for, which is the column this window exists for. A
    -- synced record has no roll list, so it can only report the win.
    if entry.partial then
        cells.chose:SetText("—")
        Theme.SetTextColor(cells.chose, "textMuted")
    else
        cells.chose:SetText(
            SYL.LootHistoryAPI.ShortRollState(entry.state) or "—"
        )

        Theme.SetTextColor(
            cells.chose,
            (entry.state == 0 or entry.state == 1)
                and "textPrimary" or "textMuted"
        )
    end

    cells.roll:SetText(entry.roll and tostring(entry.roll) or "—")
    Theme.SetTextColor(cells.roll, "textMuted")

    cells.won:SetText(entry.won and "WON" or "")
    Theme.SetTextColor(cells.won, "accent")
end

local function DescribeTotals(totals)
    return totals.eligible
        .. (totals.eligible == 1 and " eligible" or " eligible")
        .. "  ·  "
        .. totals.upgrades
        .. " upgrades  ·  "
        .. totals.mogWins
        .. " mog  ·  "
        .. totals.lost
        .. " lost  ·  "
        .. totals.passed
        .. " passed"
end

local function UpdateHeaderText(entry, totals)
    frame.nameText:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        frame.nameText:SetTextColor(
            classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(frame.nameText, "textPrimary")
    end

    local rankParts = {}

    if entry.guildRank then
        table.insert(rankParts, entry.guildRank)
    end

    if entry.mplusScore and entry.mplusScore > 0 then
        table.insert(rankParts, "M+ " .. math.floor(entry.mplusScore))
    end

    table.insert(
        rankParts,
        (entry.nights or 0) .. " nights"
    )

    frame.rankText:SetText(table.concat(rankParts, "  ·  "))

    -- Named rather than counted: an officer reading this wants to know which
    -- character, because "you won that on your alt" is a real dispute.
    if #totals.characterOrder > 1 then
        frame.altText:SetText(
            "Played as " .. table.concat(totals.characterOrder, ", ")
        )

        frame.altText:Show()
    else
        frame.altText:Hide()
    end

    frame.totalsText:SetText(DescribeTotals(totals))
end

local function Refresh()
    if not frame or not currentEntry then
        return
    end

    local entries = SYL.PlayerHistory.Build(currentKey, SYL.GetAllDrops())
    local totals = SYL.PlayerHistory.Summarise(entries)

    UpdateHeaderText(currentEntry, totals)

    local total = #entries
    local maxOffset = math.max(0, total - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    for index = 1, VISIBLE_ROWS do
        local entry = entries[index + offset]
        local row = rows[index]

        if entry then
            FillRow(row, entry)
            row:Show()
        else
            row:Hide()
        end
    end

    frame.emptyText:SetShown(total == 0)
end

local function CreateHeaderLabels()
    local header = CreateFrame("Frame", nil, frame)

    header:SetHeight(20)
    header:SetPoint("TOPLEFT", 16, -(LIST_TOP - 22))
    header:SetPoint("TOPRIGHT", -16, -(LIST_TOP - 22))

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

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootPlayerDetailFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, LIST_TOP + VISIBLE_ROWS * ROW_HEIGHT + 44)
    frame:SetPoint("CENTER", 280, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("PLAYER HISTORY")

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame.nameText = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    frame.nameText:SetPoint("TOPLEFT", 18, -52)

    frame.rankText =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")

    frame.rankText:SetPoint("TOPLEFT", 18, -76)

    frame.altText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.altText:SetPoint("TOPLEFT", 18, -94)

    frame.totalsText = Theme.CreateText(frame, Theme.sizes.row, "accent")
    frame.totalsText:SetPoint("TOPLEFT", 18, -118)
    frame.totalsText:SetPoint("TOPRIGHT", -16, -118)

    CreateHeaderLabels()

    for index = 1, VISIBLE_ROWS do
        rows[index] = CreateRow(frame, index)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetText("No drops recorded for this player yet.")
    frame.emptyText:Hide()

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local entries =
            SYL.PlayerHistory.Build(currentKey, SYL.GetAllDrops())

        local maxOffset = math.max(0, #entries - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:Hide()

    return frame
end

-- `entry` is a row from Analytics, which already carries the resolved key,
-- the display name and the score.
function SYL:OpenPlayerDetail(entry)
    if not entry or not entry.key then
        return
    end

    local window = CreateWindow()

    -- Clicking the same player again closes it; clicking a different one
    -- swaps, because comparing two raiders is the common case.
    if window:IsShown() and currentKey == entry.key then
        window:Hide()

        return
    end

    currentKey = entry.key
    currentEntry = entry
    offset = 0

    Refresh()

    window:Show()
end
