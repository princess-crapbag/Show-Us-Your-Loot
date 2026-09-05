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

-- SIZED FROM THE LABELS, not from typed widths -- and the typed ones put a
-- button underneath another button.
--
-- The five were 110, 100, 100, 120 and 110 with six-pixel gaps, which chains
-- to 582 before Close, and Close is anchored to the right edge at 512..602 in
-- a fixed 620 window. So "Full data" spanned 472..582 and sat 70 pixels
-- INSIDE Close -- and Close is created last, so it drew on top and took the
-- clicks. Pressing the visible words "Full data" closed the window.
--
-- Theme.SizeToLabels exists because of this exact failure on another row;
-- its own comment records "Hide all was drawn on top of All seasons and took
-- its clicks". Measured, the five come to 366 and leave 191 clear.
local function CreateFooter(parent)
    local previous

    local function Add(label, onClick)
        local button = Theme.CreateButton(parent, 100, 24, label, onClick)

        Theme.SizeToLabels(button, { label })

        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("BOTTOMLEFT", 18, 14)
        end

        previous = button

        return button
    end

    Add("Latest night", ShowLatestNight)
    Add("Season", ShowSeason)
    Add("Players", ShowPlayers)
    Add("No upgrade", ShowEmptyHanded)
    Add("Full data", ShowData)

    local closeButton = Theme.CreateButton(parent, 90, 24, "Close", function()
        frame:Hide()
    end)

    Theme.SizeToLabels(closeButton, { "Close" })

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
    Widgets.CloseOnEscape(frame)

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
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
