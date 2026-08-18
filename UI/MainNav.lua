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

    -- Muted, and shown on the Archives tab rather than beside the loot list.
    --
    -- It was the most prominent control in the window: top right, opposite
    -- the tabs, in the same weight as everything else. It is also the one
    -- action a new user should never take — it closes the season, files
    -- everything into the archives and starts again empty. Prominence should
    -- follow how often something is wanted, and this is wanted once a tier.
    --
    -- Archives is where it belongs anyway: that tab is the list of archived
    -- seasons, and this is the button that makes one. Reaching it now means
    -- deliberately going there.
    buttons.archiveSeason =
        Theme.CreateButton(parent, 120, 24, "Archive Season", function()
            config.onArchive()
        end)

    buttons.archiveSeason:SetPoint("TOPRIGHT", -16, -66)
    Theme.SetTextColor(buttons.archiveSeason.label, "textMuted")

    -- Beside it, and shown on the same tab, because the two are one subject:
    -- that button ends a season and this one fixes what it was called. The
    -- name is typed once, into the archive dialog, at the moment a tier ends —
    -- getting it wrong there is ordinary, and until now the only way back was
    -- /syl rename, which is a command nobody has been told about.
    buttons.renameSeason =
        Theme.CreateButton(parent, 120, 24, "Rename Season", function()
            config.onRenameSeason()
        end)

    buttons.renameSeason:SetPoint("RIGHT", buttons.archiveSeason, "LEFT", -6, 0)
    Theme.SetTextColor(buttons.renameSeason.label, "textMuted")

    SYL.Tooltips.Attach(
        buttons.renameSeason,
        "Rename this season",
        "Changes what the season running now is called. Nothing recorded in "
        .. "it changes. An archived season is renamed from the list below "
        .. "instead: tick it, type a name, press Rename."
    )

    -- Shares its anchor with Archive Season. The two are never shown at the
    -- same time, since one belongs to the active season and the other to an
    -- archived one.
    buttons.back =
        Theme.CreateButton(parent, 130, 24, "Back to Archives", function()
            config.onBack()
        end)

    buttons.back:SetPoint("TOPRIGHT", -16, -66)

    -- Archive Season is the one control here that cannot be undone, so its
    -- tooltip says what it does rather than what it is for.
    SYL.Tooltips.Attach(
        buttons.archiveSeason,
        "Archive this season",
        "Files everything recorded so far into the archives and starts a new "
        .. "season, empty. Nothing is deleted, but the active list begins "
        .. "again. Once a tier, not once a night."
    )

    SYL.Tooltips.Attach(
        buttons.back,
        "Back to Archives",
        "Returns to the list of archived seasons."
    )

    return tabStrip, buttons
end
