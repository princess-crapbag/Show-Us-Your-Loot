-- UI/DueWindow.lua
--
-- Who is due, in a window.
--
-- The headline claim on the front of the README, and it was chat-only: ten
-- lines from `/syl due`, gone the moment anybody spoke, reachable only by
-- knowing the command existed. Bosses, raid nights and the guild roster all
-- had a footer button. The question the addon is *for* did not.
--
-- The maths is entirely Core/DueList.lua and none of it is repeated here. See
-- that file for what "due" is taken to mean — the judgement calls behind it
-- are opinions rather than facts, and they are stated there.
--
-- RECENT RAIDERS ONLY by default: somebody who has not raided in a month is
-- not due in a sense an officer can act on, and leaving them at the top is
-- how a list stops being read. The toggle widens it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Utilities = SYL.Utilities

-- 660, not 640: syl_check measures a row as the window less a 50px inset,
-- and the columns total 608. Shaving the status column to fit would truncate
-- the sentence that explains the number beside it.
local WINDOW_WIDTH = 660
local ROW_HEIGHT = 24
local DEFAULT_ROWS = 14
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
local LIST_TOP = 140

-- The same three nights `/syl due` uses, so the window and the command never
-- disagree about who is on the list.
local RECENT_NIGHTS = 3

local COLUMNS = {
    { key = "name", label = "PLAYER", width = 140, gap = 10 },
    { key = "dry", label = "DRY NIGHTS", width = 84, gap = 8 },
    { key = "nights", label = "RAIDED", width = 60, gap = 8 },
    { key = "last", label = "LAST UPGRADE", width = 104, gap = 8 },
    { key = "status", label = "", width = 178, gap = 8 },
}

local frame
local rows = {}
local offset = 0
local recentOnly = true

local columnOffset = Widgets.ColumnOffsets(COLUMNS)

local Refresh

local function Entries()
    local sessions = SYL.GetAllRaids()

    local entries = SYL.DueList.Build(
        SYL.GetAllDrops(), sessions, SYL.GetAllLoot()
    )

    if recentOnly then
        entries = SYL.DueList.FilterRecent(entries, sessions, RECENT_NIGHTS)
    end

    return SYL.DueList.Sort(entries)
end

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
    -- A Button so a row opens that player's full history, the same way the
    -- players window does. "Why are they top of this list" is the immediate
    -- next question and the answer already has a window.
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -34, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

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

    for _, column in ipairs(COLUMNS) do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

        text:SetPoint("LEFT", columnOffset[column.key], 0)
        text:SetWidth(column.width)

        row.cells[column.key] = text
    end

    return row
end

local function FillRow(row, entry, rank)
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
    -- worth colouring. Everything below is context.
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

    cells.status:SetText(SYL.DueList.Describe(entry))
    Theme.SetTextColor(cells.status, "textMuted")
end

-- What went into the numbers, said out loud, exactly as `/syl due` does. A
-- ranking that quietly changed what counts is one somebody will argue with
-- and be right to.
local function DescribeBasis(total)
    local parts = {
        total .. (total == 1 and " raider" or " raiders"),
    }

    if recentOnly then
        table.insert(parts, "last " .. RECENT_NIGHTS .. " nights")
    else
        table.insert(parts, "every raider recorded")
    end

    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings

    if settings and settings.countPersonalLoot then
        table.insert(parts, "gear taken without a roll counts")
    else
        table.insert(parts, "group-loot wins only")
    end

    return table.concat(parts, "  ·  ")
end

-- The two numbers that say how complete the answer is. Neither is a rounding
-- error and neither should be discovered later.
local function DescribeGaps()
    local pending = SYL.DueList.pendingItems or 0
    local unobserved = SYL.DueList.unobservedItems or 0

    if pending == 0 and unobserved == 0 then
        return nil
    end

    local parts = {}

    if pending > 0 then
        table.insert(parts, pending .. " item(s) not cached yet")
    end

    if unobserved > 0 then
        table.insert(
            parts, unobserved .. " received outside a group and left out"
        )
    end

    return table.concat(parts, "  ·  ")
end

Refresh = function()
    if not frame then
        return
    end

    local entries = Entries()
    local total = #entries
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    frame.summaryText:SetText(DescribeBasis(total))

    local gaps = DescribeGaps()

    frame.gapsText:SetText(gaps or "")
    frame.gapsText:SetShown(gaps ~= nil)

    frame.recentButton.label:SetText(
        recentOnly and "Recent raiders" or "Everyone"
    )

    Theme.SetTextColor(
        frame.recentButton.label, recentOnly and "accent" or "textPrimary"
    )

    for index = 1, visibleRows do
        local entry = entries[index + offset]
        local row = rows[index] or CreateRow(frame, index)

        rows[index] = row

        if entry then
            FillRow(row, entry, index + offset)
            row:Show()
        else
            row:Hide()
        end
    end

    for index = visibleRows + 1, #rows do
        rows[index]:Hide()
    end

    -- An empty list here has two very different causes and they need
    -- different answers: nothing recorded at all, or nobody recent enough.
    if total == 0 then
        if #SYL.GetAllRaids() == 0 then
            frame.emptyText:SetText(
                "No raid nights recorded yet. Attendance is read from the "
                .. "group at each pull, so this fills in from the next boss "
                .. "you engage."
            )
        else
            frame.emptyText:SetText(
                "Nobody has raided in the last "
                .. RECENT_NIGHTS
                .. " nights. Press Recent raiders to see everyone."
            )
        end
    end

    frame.emptyText:SetShown(total == 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootDueFrame",
        title = "WHO IS DUE",
        key = "due",

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

    frame.gapsText = Theme.CreateText(frame, Theme.sizes.rowSmall, "warning")
    frame.gapsText:SetPoint("TOPLEFT", 27, -62)
    frame.gapsText:SetPoint("TOPRIGHT", -16, -62)
    frame.gapsText:SetJustifyH("LEFT")
    frame.gapsText:Hide()

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -84)
    hint:SetPoint("TOPRIGHT", -16, -84)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Dry nights counts raid nights attended since their last Need or "
        .. "offspec win. Transmog and greed do not reset it. Click a row for "
        .. "that raider's whole history."
    )

    frame.recentButton =
        Theme.CreateButton(frame, 120, 20, "Recent raiders", function()
            recentOnly = not recentOnly
            offset = 0

            Refresh()
        end)

    frame.recentButton:SetPoint("TOPLEFT", 18, -110)

    SYL.Tooltips.Attach(
        frame.recentButton,
        "Recent raiders / Everyone",
        "Recent means anyone in the last " .. RECENT_NIGHTS .. " raid "
        .. "nights. Somebody who has not raided in a month is not due in a "
        .. "sense you can act on, but they are still counted — press this to "
        .. "see them."
    )

    CreateHeader(frame)

    for index = 1, DEFAULT_ROWS do
        rows[index] = CreateRow(frame, index)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetWordWrap(true)
    frame.emptyText:SetWidth(WINDOW_WIDTH - 120)
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
        local total = #Entries()
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenDueWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
