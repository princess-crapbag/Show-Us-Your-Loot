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

-- Wide enough for name, response, roll and the columns beside them.
local WINDOW_WIDTH = 500
local FOOTER = 56

-- The credit block sits between the outcome line and the roll list.
-- UI/DropCredit.lua owns its internals and states what it costs.
local LIST_TOP = 150 + SYL.DropCredit.HEIGHT

local frame
local rollRows = {}
local currentRecord
local offset = 0

-- What UI/DropRolls.lua decided the list should be for the record on screen:
-- which source, which columns, and whether there is a notice above it. Held
-- because the mouse wheel needs the row count and rebuilding it per notch
-- would ask RCLootCouncil for its history on every scroll.
local view

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

-- Everything below the credit block: the notice when there is one, the column
-- headings, the rows, and the window's own height. Sized to the list, so a
-- guild night with eleven raiders no longer draws three empty rows.
local function LayoutList()
    local Rolls = SYL.DropRolls
    local top = LIST_TOP

    if view.notice then
        frame.noticeText:SetText(view.notice.text)
        frame.noticeText:Show()

        frame.noticeButton.label:SetText(view.notice.button)
        frame.noticeButton:SetWidth(
            Theme.MeasureText(Theme.sizes.rowSmall, view.notice.button) + 26
        )
        frame.noticeButton:Show()

        top = top + Rolls.NOTICE_HEIGHT
    else
        frame.noticeText:Hide()
        frame.noticeButton:Hide()
    end

    frame.header:ClearAllPoints()
    frame.header:SetPoint("TOPLEFT", 16, -top)
    frame.header:SetPoint("TOPRIGHT", -16, -top)

    Rolls.FillHeader(frame.header, view.columns)

    top = top + Rolls.HEADER_HEIGHT

    local shown = math.min(#view.rows, Rolls.MAX_ROWS)

    for index = 1, Rolls.MAX_ROWS do
        local row = rollRows[index]
        local entry = view.rows[index + offset]

        if index <= shown and entry then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, -(top + (index - 1) * Rolls.ROW_HEIGHT))
            row:SetPoint("TOPRIGHT", -16, -(top + (index - 1) * Rolls.ROW_HEIGHT))

            Rolls.FillRow(row, entry, view.columns)
            row:Show()
        else
            row:Hide()
        end
    end

    frame:SetHeight(LIST_TOP + Rolls.HeightFor(view) + FOOTER)
end

local function Refresh()
    if not frame or not currentRecord then
        return
    end

    UpdateHeaderText()
    SYL.DropCredit.Update(frame, currentRecord)

    view = SYL.DropRolls.Build(currentRecord)

    local total = #view.rows
    local maxOffset = math.max(0, total - SYL.DropRolls.MAX_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    frame.countText:SetText(
        SYL.Utilities.Count(total, "player") .. " " .. view.countLabel
    )

    LayoutList()
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

    -- A starting height only. Refresh sets the real one from what the list
    -- turns out to hold.
    frame:SetSize(
        WINDOW_WIDTH,
        LIST_TOP + SYL.DropRolls.MAX_ROWS * SYL.DropRolls.ROW_HEIGHT + FOOTER
    )
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

    -- The notice, when RCLootCouncil is installed and not recording who else
    -- responded. Built once and hidden, because most drops will not need it.
    frame.noticeText =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    frame.noticeText:SetPoint("TOPLEFT", 18, -(LIST_TOP + 2))
    frame.noticeText:SetPoint("TOPRIGHT", -140, -(LIST_TOP + 2))
    frame.noticeText:SetJustifyH("LEFT")
    frame.noticeText:SetWordWrap(true)
    frame.noticeText:Hide()

    frame.noticeButton = Theme.CreateButton(frame, 120, 22, "", function()
        if SYL.CouncilLoot.StartRecordingResponses() then
            SYL:Print(
                "RCLootCouncil will record everyone's response from the next "
                .. "session on. It cannot fill in nights already raided."
            )
        else
            SYL:Print(
                "Could not change that setting — it is in RCLootCouncil's own "
                .. "options, under \"" .. SYL.CouncilLoot.SETTING_LABEL .. "\"."
            )
        end

        Refresh()
    end)

    frame.noticeButton:SetPoint("TOPRIGHT", -16, -(LIST_TOP + 4))
    frame.noticeButton:Hide()

    frame.header = SYL.DropRolls.CreateHeader(frame)

    for index = 1, SYL.DropRolls.MAX_ROWS do
        rollRows[index] = SYL.DropRolls.CreateRow(frame, index)
    end

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = view and #view.rows or 0
        local maxOffset = math.max(0, total - SYL.DropRolls.MAX_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:Hide()

    return frame
end

-- For the credit picker, which changes what this window is showing while it
-- is still open beside it.
function DropDetailWindow.Refresh()
    Refresh()
end

-- So the picker can sit against this window's edge rather than across it.
-- nil until the window has been opened once.
function DropDetailWindow.Frame()
    return frame
end

-- Which drop the window is showing, so the picker can tell whether the answer
-- it collected is still about the drop on screen.
function DropDetailWindow.CurrentRecord()
    return currentRecord
end

function SYL:OpenDropDetail(record)
    if not record then
        return
    end

    local window = CreateWindow()

    -- Before the swap below, because it compares against what is on screen
    -- now. A picker left open across a change of drop would apply its answer
    -- to the one nobody is looking at.
    if SYL.CreditPicker then
        SYL.CreditPicker.NoteDropChanged(record)
    end

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
