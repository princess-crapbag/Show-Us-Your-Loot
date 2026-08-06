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

local WINDOW_WIDTH = 776
local ROW_HEIGHT = 24
local VISIBLE_ROWS = 14
local LIST_TOP = 116

local COLUMNS = {
    { key = "boss", label = "BOSS", width = 176, gap = 10 },
    { key = "instance", label = "INSTANCE", width = 168, gap = 8 },
    { key = "difficulty", label = "DIFF", width = 52, gap = 8 },
    { key = "kills", label = "KILLS", width = 60, gap = 8 },
    { key = "drops", label = "DROPS", width = 50, gap = 8 },
    { key = "upgrades", label = "UPGRADES", width = 66, gap = 8 },
    { key = "last", label = "LAST SEEN", width = 84, gap = 8 },
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

    return row
end

local function FillRow(row, boss)
    local cells = row.cells

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

    local seenAt = boss.lastKilledAt or boss.lastDropAt

    if seenAt then
        cells.last:SetText(date("%Y-%m-%d", seenAt))
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
    local maxOffset = math.max(0, total - VISIBLE_ROWS)

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

    for index = 1, VISIBLE_ROWS do
        local boss = bosses[index + offset]
        local row = rows[index]

        if boss then
            FillRow(row, boss)
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

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootBossFrame",
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
    title:SetText("BOSS HISTORY")

    frame.summaryText =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    frame.summaryText:SetPoint("TOPLEFT", 27, -42)
    frame.summaryText:SetPoint("TOPRIGHT", -16, -42)

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -74)
    hint:SetText(
        "Upgrades counts Need and offspec wins only. A dash means pulls were "
        .. "not being recorded yet."
    )

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    CreateHeader(frame)

    for index = 1, VISIBLE_ROWS do
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
        local maxOffset = math.max(0, total - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenBossWindow()
    local window = CreateWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
