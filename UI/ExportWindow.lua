-- UI/ExportWindow.lua
--
-- A copyable text summary of a raid night or a whole season.
--
-- Nothing is sent anywhere. Addons have no network access, so this produces
-- a block to select and copy — which is what a Discord thread actually needs.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Export = SYL.Export

local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 520

local frame
local editBox
local subtitleText

local function Drops()
    return SYL.GetActiveDrops()
end

local function SetContent(text, label)
    if not editBox then
        return
    end

    editBox:SetText(text)
    editBox:SetCursorPosition(0)
    editBox:HighlightText()

    subtitleText:SetText(label .. "  —  Ctrl+A then Ctrl+C to copy")
end

local function ShowLatestNight()
    local nights = Export.GetNights(Drops())

    if #nights == 0 then
        SetContent(
            "No drops recorded yet.",
            "Latest raid night"
        )

        return
    end

    SetContent(
        Export.BuildNightSummary(nights[1]),
        "Raid night " .. tostring(nights[1].date)
    )
end

local function ShowSeason()
    SetContent(Export.BuildSeasonSummary(Drops()), "Full season")
end

local function ShowPlayers()
    SetContent(Export.BuildPlayerSummary(Drops()), "Player totals")
end

local function ShowEmptyHanded()
    SetContent(Export.BuildEmptyHandedSummary(Drops()), "No upgrade yet")
end

-- The machine-readable document. Fed to the browser dashboard, and the same
-- shape officer sync and any hosted service would use.
local function ShowData()
    local counts = SYL.DataExport.CountRecords()

    SetContent(
        SYL.DataExport.BuildJSON(),
        "Full data v"
        .. SYL.DataExport.SCHEMA_VERSION
        .. " — "
        .. counts.drops
        .. " drops, "
        .. counts.rolls
        .. " rolls, "
        .. counts.raids
        .. " nights"
    )
end

local function CreateTextArea(parent)
    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootExportScrollFrame",
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
    editBox:SetHeight(360)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)
end

local function CreateFooter(parent)
    local nightButton =
        Theme.CreateButton(parent, 110, 24, "Latest night", ShowLatestNight)

    nightButton:SetPoint("BOTTOMLEFT", 18, 14)

    local seasonButton =
        Theme.CreateButton(parent, 100, 24, "Season", ShowSeason)

    seasonButton:SetPoint("LEFT", nightButton, "RIGHT", 6, 0)

    local playersButton =
        Theme.CreateButton(parent, 100, 24, "Players", ShowPlayers)

    playersButton:SetPoint("LEFT", seasonButton, "RIGHT", 6, 0)

    local emptyButton =
        Theme.CreateButton(parent, 120, 24, "No upgrade", ShowEmptyHanded)

    emptyButton:SetPoint("LEFT", playersButton, "RIGHT", 6, 0)

    local dataButton =
        Theme.CreateButton(parent, 110, 24, "Full data", ShowData)

    dataButton:SetPoint("LEFT", emptyButton, "RIGHT", 6, 0)

    local closeButton = Theme.CreateButton(parent, 90, 24, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -18, 14)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootExportFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("EXPORT")

    subtitleText =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    subtitleText:SetPoint("TOPLEFT", 27, -40)
    subtitleText:SetText("Latest raid night")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -62)
    separator:SetPoint("TOPRIGHT", -16, -62)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    CreateTextArea(frame)
    CreateFooter(frame)

    frame:SetScript("OnShow", ShowLatestNight)
    frame:Hide()

    return frame
end

function SYL:OpenExportWindow()
    local window = CreateWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
