-- UI/SettingsWindow.lua
--
-- The settings window: the frame, the title, and the close button.
--
-- Everything inside it lives elsewhere: the rows in UI/SettingsRows.lua, the
-- dashboard widget list in UI/SettingsWidgets.lua, and which of them appears on
-- which tab in UI/SettingsTabs.lua.
--
-- IT SCROLLED BECAUSE IT WAS ONE COLUMN. Five tabs is the answer to the same
-- problem the scroll frame was: the tallest tab is shorter than the screen, so
-- nothing has to scroll and nothing is below the fold.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local SettingsRows = SYL.SettingsRows

-- Wider than it was, because the content is now three columns across rather
-- than one down. 560 still leaves room beside a 900px main window on any
-- monitor the main window itself fits on.
local WINDOW_WIDTH = 560

-- Chrome above the pages: the accent mark and title, the subtitle, the rule
-- under them, the tab strip, and the rule under that.
local PAGE_TOP = 110

-- The rule above the Close button, and the button itself.
local FOOTER_HEIGHT = 52

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

    frame:SetSize(WINDOW_WIDTH, 400)
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

    -- THE TABS, and the rule under them that separates the strip from
    -- whichever page it is pointing at.
    local tabs = SYL.SettingsTabs.Create(frame, WINDOW_WIDTH, PAGE_TOP)

    local strip

    -- THE WINDOW IS AS TALL AS THE TAB IS, not as tall as the tallest.
    -- Features needs 296 and Tools needs 610; standing at 610 for both leaves
    -- Features with 300px of empty window under it, which reads as a screen
    -- that failed to load rather than as a short one.
    local function Show(key)
        tabs:Select(key)
        strip:SetSelected(key)

        frame:SetHeight(PAGE_TOP + tabs:HeightOf(key) + FOOTER_HEIGHT)

        ShowUsYourLootDB.settings = ShowUsYourLootDB.settings or {}
        ShowUsYourLootDB.settings.settingsTab = key
    end

    strip = SYL.TabStrip.Create(
        frame, SYL.SettingsTabs.DEFINITIONS, Show, 18, -74
    )

    local tabRule = Theme.CreateSeparator(frame)
    tabRule:SetPoint("TOPLEFT", 16, -(PAGE_TOP - 8))
    tabRule:SetPoint("TOPRIGHT", -16, -(PAGE_TOP - 8))

    frame.tabs = tabs
    frame.strip = strip
    frame.ShowTab = Show

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    -- WHERE THEY LEFT OFF. Somebody who opens settings twice in a row is
    -- nearly always going back to the same tab, and the first one is a poor
    -- guess for anybody whose reason for opening it is on the fifth.
    local remembered = ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.settingsTab

    Show(tabs.pages[remembered] and remembered or "recording")

    frame:SetScript("OnShow", function()
        SettingsRows.Refresh()
        SYL.SettingsWidgets.Refresh()
    end)
    frame:Hide()

    return frame
end

function SYL:OpenSettingsWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateSettingsWindow())
end
