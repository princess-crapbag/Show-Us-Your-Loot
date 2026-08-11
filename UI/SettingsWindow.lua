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

-- Wider than it was, because the content is now three columns across rather
-- than one down. 560 still leaves room beside a 900px main window on any
-- monitor the main window itself fits on.
local WINDOW_WIDTH = 560

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

    -- THE CONTENT SCROLLS, THE CHROME DOES NOT. Every feature added is another
    -- 38px of settings, and the window used to be sized to fit all of it — so
    -- it grew past the bottom of the screen and the last sections were simply
    -- unreachable. The window is capped to the screen now and this carries the
    -- overflow.
    local scroll = CreateFrame("ScrollFrame", nil, frame)

    scroll:SetPoint("TOPLEFT", 4, -72)
    scroll:SetPoint("BOTTOMRIGHT", -4, 52)

    local content = CreateFrame("Frame", nil, scroll)

    content:SetSize(WINDOW_WIDTH - 8, SettingsRows.ContentHeight())

    scroll:SetScrollChild(content)

    -- The wheel is the only way to reach the bottom, so it is not optional.
    -- Clamped rather than free: scrolling past the end leaves a blank window
    -- with no indication that anything is above it.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(
            0, content:GetHeight() - self:GetHeight()
        )

        local position = math.min(
            range, math.max(0, self:GetVerticalScroll() - delta * 28)
        )

        self:SetVerticalScroll(position)
    end)

    frame.scroll = scroll
    frame.content = content

    SettingsRows.BuildQualitySection(content)
    SettingsRows.BuildToggleSection(content)
    SettingsRows.BuildFeatureSection(content)

    SYL.SettingsWidgets.Build(
        content,
        SettingsRows.WidgetSectionTop(),
        SettingsRows.AddSection
    )

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
