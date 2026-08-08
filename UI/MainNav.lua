-- UI/MainNav.lua
--
-- The main window's navigation row: the tab strip, and the buttons that sit
-- opposite it and change with the view — archive this season, back out of an
-- archive, switch which of an archived season's two record tables is shown.
--
-- Lifted out of MainWindow, which had crossed the project's size limit three
-- times in a session and was being kept under it by trimming comments. That
-- stops being a real fix somewhere around the second time. This is
-- construction and nothing else: it builds the controls and hands them back,
-- and every decision they trigger stays with the window through callbacks.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local MainNav = {}
SYL.MainNav = MainNav

-- config carries the callbacks rather than the state, so this file never
-- learns what a mode is:
--   tabs          the tab definitions
--   onTab(key)    a tab was chosen
--   onArchive()   archive the active season
--   onBack()      leave an archived season
--   onSwapRecords() switch between an archive's drops and its chat loot
--
-- Returns the tab strip and a table of the buttons, which the window shows
-- and hides as the view changes.
function MainNav.Create(parent, config)
    local tabStrip = SYL.TabStrip.Create(parent, config.tabs, function(key)
        config.onTab(key)
    end, 14, -66)

    local separator = Theme.CreateSeparator(parent)
    separator:SetPoint("TOPLEFT", 16, -92)
    separator:SetPoint("TOPRIGHT", -16, -92)

    local buttons = {}

    buttons.archiveSeason =
        Theme.CreateButton(parent, 120, 24, "Archive Season", function()
            config.onArchive()
        end)

    buttons.archiveSeason:SetPoint("TOPRIGHT", -16, -66)

    -- Shares its anchor with Archive Season. The two are never shown at the
    -- same time, since one belongs to the active season and the other to an
    -- archived one.
    buttons.back =
        Theme.CreateButton(parent, 130, 24, "Back to Archives", function()
            config.onBack()
        end)

    buttons.back:SetPoint("TOPRIGHT", -16, -66)

    buttons.archiveRecords =
        Theme.CreateButton(parent, 124, 24, "Show chat loot", function()
            config.onSwapRecords()
        end)

    buttons.archiveRecords:SetPoint("RIGHT", buttons.back, "LEFT", -6, 0)

    return tabStrip, buttons
end
