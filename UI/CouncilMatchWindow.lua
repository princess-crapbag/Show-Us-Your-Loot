-- UI/CouncilMatchWindow.lua
--
-- Every drop RCLootCouncil would move, shown before any of it moves.
--
-- WHY IT SHOWS ITS WORK. Aimee asked whether matching could just happen --
-- "shouldnt it by default match rclc and i change it if needed?" -- and then
-- chose the other way once both were on the table: "i like review for
-- matching the rclootcouncil."
--
-- She is right, and Core/CouncilMatch.lua's header has the reason: applying a
-- match rewrites who a scored item belongs to. It moves points between real
-- people on a board those people read. A sweep of a whole season doing that
-- silently is the one thing this addon should not do quietly, and the same
-- rule the erase dialog follows -- explain before asking.
--
-- SCROLLS, because a season is not five rows. Aimee's holds 130 drops and the
-- first sweep of a tier could name dozens of them.
--
-- Apply holds the whole job and touches no frame, for the reason
-- UI/ClearSeasonDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local CouncilMatchWindow = {}
SYL.CouncilMatchWindow = CouncilMatchWindow

local WINDOW_WIDTH = 520
local WINDOW_HEIGHT = 420
local PAD = 16
local CONTENT = WINDOW_WIDTH - PAD * 2

local HEADER = 52
local BODY_HEIGHT = 46
local LIST_TOP = HEADER + BODY_HEIGHT
local ROW_HEIGHT = 20
local FOOTER = 52

local COLUMN_ITEM = 0
local COLUMN_FROM = 210
local COLUMN_ARROW = 300
local COLUMN_TO = 316
local COLUMN_RESPONSE = 410

local frame
local bodyText
local rows = {}
local offset = 0
local changes = {}

local function VisibleRows()
    return math.floor(
        (WINDOW_HEIGHT - LIST_TOP - FOOTER) / ROW_HEIGHT
    )
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function CouncilMatchWindow.Apply()
    local applied, failed = SYL.CouncilMatch.ApplyAll(changes)

    if applied == 0 and failed == 0 then
        return false
    end

    local message = "Matched " .. SYL.Utilities.Count(applied, "drop")
        .. " to RCLootCouncil."

    if failed > 0 then
        message = message .. " " .. failed .. " could not be changed — those "
            .. "drops are no longer in the database."
    end

    SYL:Print(message)

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetWidth(CONTENT)

    if index % 2 == 0 then
        local stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        stripe:SetAllPoints()
    end

    row.item = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.item:SetPoint("LEFT", COLUMN_ITEM + 4, 0)
    row.item:SetWidth(COLUMN_FROM - COLUMN_ITEM - 10)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)

    row.from = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.from:SetPoint("LEFT", COLUMN_FROM, 0)
    row.from:SetWidth(COLUMN_ARROW - COLUMN_FROM - 6)
    row.from:SetJustifyH("LEFT")
    row.from:SetWordWrap(false)

    row.arrow = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.arrow:SetPoint("LEFT", COLUMN_ARROW, 0)
    row.arrow:SetText("→")

    row.to = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.to:SetPoint("LEFT", COLUMN_TO, 0)
    row.to:SetWidth(COLUMN_RESPONSE - COLUMN_TO - 6)
    row.to:SetJustifyH("LEFT")
    row.to:SetWordWrap(false)

    row.response = Theme.CreateText(row, Theme.sizes.tiny, "textMuted")
    row.response:SetPoint("RIGHT", -4, 0)
    row.response:SetJustifyH("RIGHT")

    return row
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootCouncilMatchWindow", UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local mark = Theme.CreateAccentMark(frame)
    mark:SetPoint("TOPLEFT", 14, -16)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    title:SetText("Match to RCLootCouncil")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 14, -42)
    separator:SetPoint("TOPRIGHT", -14, -42)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -HEADER)
    bodyText:SetWidth(CONTENT)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    for index = 1, VisibleRows() do
        rows[index] = CreateRow(frame, index)
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local ceiling = math.max(0, #changes - VisibleRows())

        offset = math.min(ceiling, math.max(0, offset - delta))

        CouncilMatchWindow.Draw()
    end)

    local footer = Theme.CreateSeparator(frame)
    footer:SetPoint("BOTTOMLEFT", 14, 42)
    footer:SetPoint("BOTTOMRIGHT", -14, 42)

    local close = Theme.CreateButton(frame, 80, 22, "Cancel", function()
        frame:Hide()
    end)

    close:SetPoint("BOTTOMRIGHT", -PAD, 14)

    frame.apply = Theme.CreateButton(frame, 130, 22, "Apply", function()
        CouncilMatchWindow.Apply()
        frame:Hide()
    end)

    frame.apply:SetPoint("RIGHT", close, "LEFT", -8, 0)

    frame.count = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.count:SetPoint("BOTTOMLEFT", PAD, 20)

    local corner = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    corner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

function CouncilMatchWindow.Draw()
    if not frame then
        return
    end

    local visible = VisibleRows()

    offset = math.min(offset, math.max(0, #changes - visible))

    for index = 1, visible do
        local row = rows[index]
        local change = changes[index + offset]

        if change then
            row.item:SetText(change.itemName)
            row.from:SetText(SYL.Utilities.ShortName(change.fromName or "?"))
            row.to:SetText(SYL.Utilities.ShortName(change.toName))

            -- "name only" where the guild's button is not one this addon can
            -- place. The item still moves; the weight does not, and the row
            -- says which rather than looking like both happened.
            row.response:SetText(
                change.state and (change.response or "")
                or (change.response and "name only" or "")
            )

            Theme.SetTextColor(row.response,
                change.state and "textMuted" or "warning")

            row:Show()
        else
            row:Hide()
        end
    end

    local shown = math.min(visible, #changes)

    frame.count:SetText(
        #changes > visible
            and (shown + offset) .. " of " .. #changes .. " · scroll for more"
            or ""
    )
end

function CouncilMatchWindow.Show()
    local window = CreateWindow()
    local reason

    changes, reason = SYL.CouncilMatch.Build(SYL.GetActiveSeason())
    offset = 0

    bodyText:SetText(SYL.CouncilMatch.Summarize(changes, reason))

    -- Dead when there is nothing to do, rather than an Apply that quietly
    -- does nothing. A button that looks pressable and is not reads as broken.
    if #changes == 0 then
        window.apply:Disable()
        Theme.SetTextColor(window.apply.label, "textMuted")
    else
        window.apply:Enable()
        Theme.SetTextColor(window.apply.label, "textPrimary")
        window.apply.label:SetText("Apply " .. #changes)
    end

    CouncilMatchWindow.Draw()

    SYL.WindowStack.ShowWindow(window)

    return window
end
