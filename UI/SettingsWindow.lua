-- UI/SettingsWindow.lua
--
-- The settings window: the frame, the title, and the close button.
--
-- Everything inside it — the quality list, the behaviour toggles and the
-- layout maths that decide how tall the window has to be — lives in
-- UI/SettingsRows.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local SettingsRows = SYL.SettingsRows

local WINDOW_WIDTH = 420

local frame

local function CreateSettingsWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootSettingsFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, SettingsRows.WindowHeight())
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
    title:SetText("SETTINGS")

    local subtitle =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    subtitle:SetPoint("TOPLEFT", 27, -40)
    subtitle:SetText("What gets recorded, and what runs at all")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -66)
    separator:SetPoint("TOPRIGHT", -16, -66)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    SettingsRows.BuildQualitySection(frame)
    SettingsRows.BuildToggleSection(frame)
    SettingsRows.BuildFeatureSection(frame)

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:SetScript("OnShow", SettingsRows.Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenSettingsWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateSettingsWindow())
end
