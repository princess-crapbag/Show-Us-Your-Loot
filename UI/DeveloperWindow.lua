-- UI/DeveloperWindow.lua
--
-- Debugging window for the Loot History inspector. This is not an end-user
-- feature: it exists so the shape of Blizzard's data can be confirmed before
-- any of it is stored permanently.
--
-- Report text is built in UI/DeveloperReport.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Serializer = SYL.Serializer
local LootHistory = SYL.LootHistory
local DeveloperReport = SYL.DeveloperReport

local WINDOW_WIDTH = 820
local WINDOW_HEIGHT = 600

local frame
local editBox
local subtitleText

-- "report" re-renders on every captured event. The JSON views deliberately do
-- not, so a selection being copied is never pulled out from under you.
local displayMode = "report"

local function SetContent(text, modeLabel)
    if not editBox then
        return
    end

    editBox:SetText(text)
    editBox:SetCursorPosition(0)

    subtitleText:SetText(
        modeLabel
        .. "  —  "
        .. LootHistory.state.logCounter
        .. " events captured  —  inspector "
        .. (LootHistory.IsEnabled() and "ON" or "OFF")
    )
end

local function ShowReport()
    displayMode = "report"

    SetContent(DeveloperReport.Build(), "Live report")
end

local function ShowSnapshotJSON()
    displayMode = "json"

    local state = LootHistory.state

    SetContent(
        Serializer.ToJSON({
            currentEncounterID = state.currentEncounterID,
            currentLootListID = state.currentLootListID,
            currentSnapshot = state.currentSnapshot,
            lastEvent = state.lastEvent,
        }),
        "Snapshot JSON — Ctrl+A then Ctrl+C to copy"
    )
end

local function ShowFullExport()
    displayMode = "export"

    SetContent(
        Serializer.ToJSON(LootHistory.BuildExportTable()),
        "Full export — Ctrl+A then Ctrl+C to copy"
    )
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

local function CreateTextArea(parent)
    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootDeveloperScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )

    scrollFrame:SetPoint("TOPLEFT", 18, -80)
    scrollFrame:SetPoint("BOTTOMRIGHT", -38, 58)

    editBox = CreateFrame("EditBox", nil, scrollFrame)

    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFont(Theme.GetFontPath(), Theme.sizes.rowSmall, "")
    editBox:SetTextColor(unpack(Theme.colors.textPrimary))
    editBox:SetWidth(WINDOW_WIDTH - 76)
    editBox:SetHeight(400)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)

    return scrollFrame
end

local function CreateFooter(parent)
    local copyButton = Widgets.CreatePanelButton(
        parent, 110, 24, "Copy JSON", ShowSnapshotJSON
    )

    copyButton:SetPoint("BOTTOMLEFT", 20, 22)

    local exportButton = Widgets.CreatePanelButton(
        parent, 110, 24, "Export", ShowFullExport
    )

    exportButton:SetPoint("LEFT", copyButton, "RIGHT", 6, 0)

    local reportButton = Widgets.CreatePanelButton(
        parent, 110, 24, "Live Report", ShowReport
    )

    reportButton:SetPoint("LEFT", exportButton, "RIGHT", 6, 0)

    local clearButton = Widgets.CreatePanelButton(
        parent, 110, 24, "Clear", function()
            LootHistory.ClearLog()
            ShowReport()
        end
    )

    clearButton:SetPoint("LEFT", reportButton, "RIGHT", 6, 0)

    local closeButton = Widgets.CreatePanelButton(
        parent, 110, 24, "Close", function()
            frame:Hide()
        end
    )

    closeButton:SetPoint("BOTTOMRIGHT", -20, 22)
end

local function CreateDeveloperWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootDeveloperFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("LOOT HISTORY INSPECTOR")

    subtitleText =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    subtitleText:SetPoint("TOPLEFT", 27, -40)
    subtitleText:SetText("Live report")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -62)
    separator:SetPoint("TOPRIGHT", -16, -62)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    CreateTextArea(frame)
    CreateFooter(frame)

    frame:SetScript("OnShow", ShowReport)

    frame:Hide()

    return frame
end

--------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------

function SYL:OpenDeveloperWindow()
    local window = CreateDeveloperWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

function SYL:RefreshDeveloperWindow()
    if not frame or not frame:IsShown() then
        return
    end

    -- Never clobber a JSON view the user may be mid-copy on.
    if displayMode ~= "report" then
        return
    end

    ShowReport()
end
