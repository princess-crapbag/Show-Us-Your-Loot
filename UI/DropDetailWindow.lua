-- UI/DropDetailWindow.lua
--
-- Everything recorded about one drop: the item, the boss it came from, and
-- how every eligible player responded.
--
-- This is the transparency the addon exists for — not who won, which the list
-- already shows, but what everyone else rolled.
--
-- IT IS ALSO WHERE CREDIT IS CORRECTED, and that is on purpose rather than in
-- a Settings tab of buttons: the control belongs where the data lives. Under a
-- loot council the addon credits every drop to the master looter, because a
-- trade it never witnessed is a trade that never happened as far as it knows.
-- See Core/LootCredit.lua for why that is two wrong numbers per drop and not
-- one.
--
-- WHAT IT DOES NOT DO IS REWRITE HISTORY. "Won by Arcangila with 51" still
-- says so afterwards, because that is what the client reported. Only the
-- credit line moves.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Utilities = SYL.Utilities

local DropDetailWindow = {}
SYL.DropDetailWindow = DropDetailWindow

-- Wide enough for name, state, roll, guild rank and the winner marker.
local WINDOW_WIDTH = 500
local ROW_HEIGHT = 20
local VISIBLE_ROLLS = 14

-- The credit block sits between the outcome line and the roll list.
-- UI/DropCredit.lua owns its internals and states what it costs.
local LIST_TOP = 150 + SYL.DropCredit.HEIGHT

local frame
local rollRows = {}
local currentRecord
local offset = 0

-- Need first, then the softer claims, then everyone who stood aside. Within a
-- group the highest roll leads.
local STATE_ORDER = {
    [0] = 1, -- NeedMainSpec
    [1] = 2, -- NeedOffSpec
    [2] = 3, -- Transmog
    [3] = 4, -- Greed
    [4] = 5, -- NoRoll
    [5] = 6, -- Pass
}

local function SortRolls(rolls)
    local sorted = {}

    for _, roll in ipairs(rolls or {}) do
        table.insert(sorted, roll)
    end

    table.sort(sorted, function(left, right)
        if left.isWinner ~= right.isWinner then
            return left.isWinner == true
        end

        local leftOrder = STATE_ORDER[left.state] or 99
        local rightOrder = STATE_ORDER[right.state] or 99

        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end

        if (left.roll or -1) ~= (right.roll or -1) then
            return (left.roll or -1) > (right.roll or -1)
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return sorted
end

local function CreateRollRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -16, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.nameText = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.nameText:SetPoint("LEFT", 6, 0)
    row.nameText:SetWidth(150)

    row.stateText = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.stateText:SetPoint("LEFT", row.nameText, "RIGHT", 6, 0)
    row.stateText:SetWidth(90)

    row.rollText = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.rollText:SetPoint("LEFT", row.stateText, "RIGHT", 6, 0)
    row.rollText:SetWidth(44)

    row.rankText = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.rankText:SetPoint("LEFT", row.rollText, "RIGHT", 6, 0)
    row.rankText:SetWidth(96)

    row.markerText = Theme.CreateText(row, Theme.sizes.rowSmall, "accent")
    row.markerText:SetPoint("LEFT", row.rankText, "RIGHT", 4, 0)
    row.markerText:SetWidth(38)

    return row
end

local function FillRollRow(row, roll)
    row.nameText:SetText(tostring(roll.name or "Unknown"))

    local classColor = Theme.GetClassColor(roll.class)

    if classColor then
        Theme.SetCustomTextColor(
            row.nameText, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(row.nameText, "textPrimary")
    end

    row.stateText:SetText(
        SYL.LootHistoryAPI.ShortRollState(roll.state)
        or roll.stateText
        or "unknown"
    )

    -- Players who passed or took transmog never rolled, so a number here
    -- would be invented.
    row.rollText:SetText(roll.roll and tostring(roll.roll) or "—")

    -- Rank is only shown for our own guild. Someone else's guild rank is
    -- not information this addon is for.
    local rank =
        SYL.Guild.GetRank(roll.guid, roll.name)
        or roll.guildRank

    row.rankText:SetText(rank or "")

    row.markerText:SetText(roll.isWinner and "WON" or "")
end

local function UpdateHeaderText()
    local record = currentRecord

    frame.itemText:SetText(
        tostring(record.itemLink or record.itemName or "Unknown item")
    )

    local icon = Theme.GetItemIcon(record.itemLink)

    if icon then
        frame.icon:SetTexture(icon)
        frame.icon:Show()
    else
        frame.icon:Hide()
    end

    -- Records written before item level was captured have none, and the
    -- client can usually answer for them now. Read rather than written back:
    -- what is shown is the level today, and only a stored one is the level it
    -- dropped at, so the saved record is left alone.
    local itemLevel = record.itemLevel
        or Utilities.GetItemLevel(record.itemLink)

    frame.bossText:SetText(
        tostring(record.encounterName or "Unknown boss")
        .. (record.difficultyName and (" · " .. record.difficultyName) or "")
        .. (record.instanceName and ("  ·  " .. record.instanceName) or "")
        .. (itemLevel and ("  ·  ilvl " .. itemLevel) or "")
    )

    frame.dateText:SetText(Utilities.FormatDateTime(record.timestamp))

    if record.allPassed then
        frame.outcomeText:SetText("Everyone passed")
        Theme.SetTextColor(frame.outcomeText, "textMuted")
    else
        frame.outcomeText:SetText(
            "Won by "
            .. tostring(record.winnerName or "Unknown")
            .. (record.winnerRoll and (" with " .. record.winnerRoll) or "")
        )

        local classColor = Theme.GetClassColor(record.winnerClass)

        if classColor then
            Theme.SetCustomTextColor(
                frame.outcomeText,
                classColor[1], classColor[2], classColor[3]
            )
        else
            Theme.SetTextColor(frame.outcomeText, "accent")
        end
    end
end

local function Refresh()
    if not frame or not currentRecord then
        return
    end

    UpdateHeaderText()
    SYL.DropCredit.Update(frame, currentRecord)

    local rolls = SortRolls(currentRecord.rolls)
    local total = #rolls

    local maxOffset = math.max(0, total - VISIBLE_ROLLS)

    if offset > maxOffset then
        offset = maxOffset
    end

    frame.countText:SetText(
        total .. (total == 1 and " eligible player" or " eligible players")
    )

    for index = 1, VISIBLE_ROLLS do
        local roll = rolls[index + offset]
        local row = rollRows[index]

        if roll then
            FillRollRow(row, roll)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootDropDetailFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, LIST_TOP + VISIBLE_ROLLS * ROW_HEIGHT + 56)
    frame:SetPoint("CENTER", 260, 0)

    -- Anchored beside the list that opens it, so the cascade must
    -- not move it.
    SYL.WindowStack.KeepPlacement(frame)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("DROP DETAIL")

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(22, 22)
    frame.icon:SetPoint("TOPLEFT", 18, -48)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.itemText = Theme.CreateText(frame, Theme.sizes.row, "textPrimary")
    frame.itemText:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.itemText:SetPoint("RIGHT", -16, 0)

    frame.bossText =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")

    frame.bossText:SetPoint("TOPLEFT", 18, -78)
    frame.bossText:SetPoint("TOPRIGHT", -16, -78)

    frame.dateText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.dateText:SetPoint("TOPLEFT", 18, -96)

    frame.outcomeText = Theme.CreateText(frame, Theme.sizes.row, "accent")
    frame.outcomeText:SetPoint("TOPLEFT", 18, -118)
    frame.outcomeText:SetPoint("TOPRIGHT", -16, -118)

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -140)
    separator:SetPoint("TOPRIGHT", -16, -140)

    SYL.DropCredit.Build(frame, {
        onChange = function()
            if currentRecord then
                SYL.CreditPicker.Open(currentRecord)
            end
        end,

        onUndo = function()
            if not currentRecord then
                return
            end

            SYL.LootCredit.Clear(currentRecord.id)

            Refresh()

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end
        end,
    })

    frame.countText =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    frame.countText:SetPoint("BOTTOMLEFT", 18, 18)

    for index = 1, VISIBLE_ROLLS do
        rollRows[index] = CreateRollRow(frame, index)
    end

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = #(currentRecord and currentRecord.rolls or {})
        local maxOffset = math.max(0, total - VISIBLE_ROLLS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:Hide()

    return frame
end

-- For the credit picker, which changes what this window is showing while it
-- is still open behind it.
function DropDetailWindow.Refresh()
    Refresh()
end

function SYL:OpenDropDetail(record)
    if not record then
        return
    end

    local window = CreateWindow()

    -- Clicking a different row swaps the contents rather than toggling the
    -- window shut, which is what happens if you compare two drops in a row.
    if window:IsShown() and currentRecord == record then
        window:Hide()

        return
    end

    currentRecord = record
    offset = 0

    Refresh()

    -- Shown rather than toggled: this window was opened by clicking
    -- a row, and it has to end up on top of the window that row is
    -- in. See WindowStack.
    SYL.WindowStack.ShowWindow(window)
end
