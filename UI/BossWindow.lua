-- UI/BossWindow.lua
--
-- Every boss: how often it was pulled, how often it died, and what it gave up.
--
-- Pulls and kills come from raid sessions; drops come from loot records. The
-- two are not the same age, so a boss farmed before raid sessions existed
-- shows drops with no pulls. That is displayed as a dash rather than as a
-- zero, because "not recorded" and "never killed" are different answers.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local BossStats = SYL.BossStats

-- 840 rather than 776 to fit the ITEMS column; the old width had 12px spare.
local WINDOW_WIDTH = 840
local ROW_HEIGHT = 24
-- Rows the window opens with, the most it will ever build, and how many
-- are on screen right now. The pool has a ceiling because a window dragged
-- to the height of a tall monitor must not build rows without bound.
local DEFAULT_ROWS = 14
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
-- Pushed down from 116 to make room for the loot table toggle above the list.
local LIST_TOP = 148

local COLUMNS = {
    { key = "boss", label = "BOSS", width = 176, gap = 10 },
    { key = "instance", label = "INSTANCE", width = 168, gap = 8 },
    { key = "difficulty", label = "DIFF", width = 52, gap = 8 },
    { key = "kills", label = "KILLS", width = 60, gap = 8 },
    { key = "drops", label = "DROPS", width = 50, gap = 8 },
    { key = "upgrades", label = "UPGRADES", width = 66, gap = 8 },
    -- How much of the journal's loot table this guild has actually seen.
    { key = "items", label = "ITEMS", width = 62, gap = 8 },
    { key = "last", label = "LAST SEEN", width = 84, gap = 8 },
}

local frame
local rows = {}
local offset = 0

-- Off until asked for. Filling this column means walking every raid tier in
-- the Encounter Journal, which is a lot of work to do to a window somebody
-- opened to check last night's kills.
local showItems = false

local columnOffset = {}
local columnWidth = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        columnWidth[column.key] = column.width
        x = x + column.width
    end
end

local function Bosses()
    local bosses = BossStats.Build(SYL.GetAllDrops(), SYL.GetAllRaids())

    return BossStats.SortByRecent(bosses)
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

    -- Over the count, because the count on its own does not say which items.
    SYL.BossTooltip.Attach(
        row, columnOffset.items, columnWidth.items, ROW_HEIGHT
    )

    return row
end

local function FillRow(row, boss)
    local cells = row.cells

    -- Read by the tooltip. Rows are pooled, so this has to be set every
    -- refresh rather than captured when the row was built.
    row.boss = boss

    cells.boss:SetText(tostring(boss.name))
    cells.instance:SetText(tostring(boss.instanceName or "Unknown"))
    cells.difficulty:SetText(
        SYL.Utilities.ShortDifficulty(boss.difficultyID, boss.difficultyName)
        or ""
    )

    -- No pulls recorded is not zero kills. Sessions arrived later than loot
    -- capture, so older bosses genuinely have nothing to report here.
    if boss.pulls > 0 then
        cells.kills:SetText(boss.kills .. "/" .. boss.pulls)

        if boss.kills == 0 then
            Theme.SetTextColor(cells.kills, "textMuted")
        else
            Theme.SetTextColor(cells.kills, "accent")
        end
    else
        cells.kills:SetText("—")
        Theme.SetTextColor(cells.kills, "textMuted")
    end

    cells.drops:SetText(boss.drops)

    cells.upgrades:SetText(boss.upgrades)

    if boss.upgrades == 0 then
        Theme.SetTextColor(cells.upgrades, "textMuted")
    else
        Theme.SetTextColor(cells.upgrades, "textPrimary")
    end

    -- Three different blanks, deliberately not the same as a zero: the
    -- column is switched off, the journal has no table for this boss, or it
    -- has one and every item in it has dropped.
    if not showItems then
        cells.items:SetText("")
    else
        local missing, total, seen = SYL.LootTable.GetMissing(boss)

        if not missing then
            cells.items:SetText("—")
            Theme.SetTextColor(cells.items, "textMuted")
        else
            cells.items:SetText(seen .. "/" .. total)

            Theme.SetTextColor(
                cells.items,
                #missing > 0 and "textPrimary" or "accent"
            )
        end
    end

    local seenAt = boss.lastKilledAt or boss.lastDropAt

    if seenAt then
        cells.last:SetText(SYL.Utilities.FormatDateOnly(seenAt))
        Theme.SetTextColor(cells.last, "textSecondary")
    else
        cells.last:SetText("—")
        Theme.SetTextColor(cells.last, "textMuted")
    end
end

Refresh = function()
    if not frame then
        return
    end

    local bosses = Bosses()
    local total = #bosses
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    local kills, drops = 0, 0

    for _, boss in ipairs(bosses) do
        kills = kills + boss.kills
        drops = drops + boss.drops
    end

    frame.summaryText:SetText(
        total
        .. (total == 1 and " boss" or " bosses")
        .. "  ·  "
        .. kills
        .. " kills  ·  "
        .. drops
        .. " drops"
    )

    for index = 1, visibleRows do
        local boss = bosses[index + offset]
        local row = rows[index] or CreateRow(frame, index)

        rows[index] = row

        if boss then
            FillRow(row, boss)
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
        globalName = "ShowUsYourLootBossFrame",
        title = "BOSS HISTORY",
        key = "boss",

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
        "Upgrades counts Need and offspec wins only. A dash means pulls were "
        .. "not being recorded yet. ITEMS is how much of the journal's loot "
        .. "table has actually dropped."
    )

    -- Built only when the feature is on. Off, the ITEMS column stays dashed
    -- and there is no button offering to fill it.
    if SYL.Features.IsEnabled("lootTables") then
        frame.itemsButton =
            Theme.CreateButton(frame, 130, 20, "Loot tables", function()
                showItems = not showItems

                -- Built on the first press rather than at load. If the
                -- journal will not open, the column stays dashed and says so
                -- once.
                if showItems
                    and not SYL.EncounterJournal.IsAvailable()
                then
                    SYL:Print(
                        "The Encounter Journal is not available, so loot "
                        .. "tables cannot be read."
                    )

                    showItems = false
                end

                Theme.SetTextColor(
                    frame.itemsButton.label,
                    showItems and "accent" or "textPrimary"
                )

                Refresh()
            end)

        frame.itemsButton:SetPoint("TOPLEFT", 18, -106)
    end

    CreateHeader(frame)

    for index = 1, DEFAULT_ROWS do
        rows[index] = CreateRow(frame, index)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.title, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetText("No bosses recorded yet.")
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
        local total = #Bosses()
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenBossWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
