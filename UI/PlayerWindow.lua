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

-- 820 rather than 760: the Raider.IO column needs 54px and the old width had
-- 34 spare, so fitting it meant widening rather than truncating a name.
local WINDOW_WIDTH = 820
local ROW_HEIGHT = 24
-- Rows the window opens with, the most it will ever build, and how many are
-- on screen right now.
local DEFAULT_ROWS = 16
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
local LIST_TOP = 150

local COLUMNS = {
    { key = "name", label = "PLAYER", width = 130, gap = 10 },
    { key = "rank", label = "GUILD RANK", width = 110, gap = 8 },
    -- Blank without Raider.IO, and blank for anyone its bundle has not seen.
    -- Nothing in the fairness maths reads it: it is context, not an input.
    { key = "score", label = "M+", width = 46, gap = 8 },
    { key = "nights", label = "NIGHTS", width = 50, gap = 8 },
    -- ELIGIBLE, not ROLLED ON. The number is how many drops this player could
    -- have won — every roll list they appeared on — and a pass or a no-roll
    -- puts you on that list exactly as a Need does. Labelled "ROLLED ON" it
    -- is the number an officer quotes in a loot dispute, and it would be
    -- wrong in the direction that loses the argument for the quiet raider who
    -- passes on everything.
    { key = "eligible", label = "ELIGIBLE", width = 66, gap = 8 },
    { key = "upgrades", label = "UPGRADES", width = 68, gap = 8 },
    { key = "mog", label = "MOG", width = 40, gap = 8 },
    { key = "lastWin", label = "LAST UPGRADE", width = 100, gap = 8 },
    { key = "drought", label = "DAYS", width = 46, gap = 8 },
}

local frame
local rows = {}
local header

local sortKey = "upgrades"
local sortReversed = false
local offset = 0
local guildOnly = false
local emptyOnly = false
local wholeGuild = false

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

    -- Before the filters, so "guild only" and "no upgrade yet" apply to the
    -- roster too rather than to the loot history alone.
    if wholeGuild then
        Analytics.IncludeGuildRoster(stats)
    end

    if guildOnly then
        stats = Analytics.FilterGuildOnly(stats)
    end

    if emptyOnly then
        stats = Analytics.FilterEmptyHanded(stats)
    end

    -- Before the sort, so the M+ column sorts like any other.
    SYL.RaiderIO.AttachScores(stats)

    return Analytics.Sort(stats, sortKey, sortReversed)
end

local Refresh

local function CreateHeader(parent)
    header = SYL.SortHeader.Create(parent, {
        columns = COLUMNS,
        offsets = columnOffset,
        top = LIST_TOP,

        getSort = function()
            return sortKey, sortReversed
        end,

        onSort = function(key, reversed)
            sortKey = key
            sortReversed = reversed
            offset = 0

            Refresh()
        end,
    })

    return header
end

local function CreateRow(parent, index)
    -- A Button rather than a Frame so the row can be clicked through to the
    -- player's own history.
    local row = CreateFrame("Button", nil, parent)

    row:SetScript("OnClick", function(self)
        if self.entry then
            SYL:OpenPlayerDetail(self.entry)
        end
    end)

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

    -- Read by the click handler. Rows are pooled and reused, so this has to
    -- be set every refresh rather than captured when the row was built.
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

    -- Blank rather than "not in guild": most of a pug raid is not, and saying
    -- so on every row would be noise.
    cells.rank:SetText(entry.guildRank or "")

    -- Blank covers three different things — no Raider.IO, a character it has
    -- never seen, and a genuine zero — and none of them is worth a symbol
    -- that would read as a number.
    if entry.mplusScore and entry.mplusScore > 0 then
        cells.score:SetText(math.floor(entry.mplusScore))

        Theme.SetCustomTextColor(
            cells.score, SYL.RaiderIO.GetScoreColor(entry.mplusScore)
        )
    else
        cells.score:SetText("")
    end

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

    header.UpdateLabels()

    local stats = CurrentStats()
    local total = #stats
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    local totals = Analytics.Summarise(stats)

    -- Said out loud, because two characters counted as one person is the
    -- kind of thing an officer argues with a list about.
    local folded = SYL.Players.DescribeMappings()

    frame.summaryText:SetText(
        total
        .. (total == 1 and " player" or " players")
        .. "  ·  "
        .. totals.guildMembers
        .. " in guild"
        .. "  ·  "
        .. totals.emptyHanded
        .. " with no upgrade"
        .. (folded and ("  ·  " .. folded) or "")
    )

    for index = 1, visibleRows do
        local entry = stats[index + offset]
        local row = rows[index] or CreateRow(frame, index)

        rows[index] = row

        if entry then
            FillRow(row, entry)
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

local function CreateFilters(parent)
    local Toggles = SYL.Toggles

    frame.guildButton =
        Toggles.Create(parent, 110, "Guild only", function(on)
            guildOnly = on
            offset = 0
            Refresh()
        end)

    frame.guildButton:SetPoint("TOPLEFT", 18, -108)

    frame.emptyButton =
        Toggles.Create(parent, 140, "No upgrade yet", function(on)
            emptyOnly = on
            offset = 0
            Refresh()
        end)

    frame.emptyButton:SetPoint("LEFT", frame.guildButton, "RIGHT", 6, 0)

    -- Everyone in the guild, including those who have never raided, which is
    -- the only way to see a roster rather than a loot history.
    frame.rosterButton =
        Toggles.Create(parent, 120, "Whole guild", function(on)
            wholeGuild = on
            offset = 0

            if on then
                SYL.AltDetect.EnsureGuildMembers()
            end

            Refresh()
        end)

    frame.rosterButton:SetPoint("LEFT", frame.emptyButton, "RIGHT", 6, 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootPlayerFrame",
        title = "PLAYERS",
        key = "players",

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
    hint:SetPoint("TOPLEFT", 18, -76)
    hint:SetText(
        "Upgrades counts Need and offspec wins only. Transmog is listed apart."
    )

    CreateFilters(frame)
    CreateHeader(frame)

    for index = 1, DEFAULT_ROWS do
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
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenPlayerWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
