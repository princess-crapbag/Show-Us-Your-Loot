-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Row rendering
-- lives in UI/LootListView.lua, frame building in UI/Widgets.lua and every
-- colour and size in UI/Theme.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Rows = SYL.Rows
local Filters = SYL.Filters
local FilterBar = SYL.FilterBar
local FilterDropdown = SYL.FilterDropdown
local ListSources = SYL.ListSources
local Selection = SYL.Selection
local LootListView = SYL.LootListView

local WINDOW_WIDTH = 830
local WINDOW_HEIGHT = 590
local VISIBLE_ROWS = 13

local frame
local buttons = {}
local tabs = {}

-- Shared with LootListView, which reads it but never owns it.
local view = {
    -- Drops are the primary record now, so the window opens on them.
    mode = "drops",
    selectedArchiveIndex = nil,
    offset = 0,
    visibleRows = VISIBLE_ROWS,
    showHidden = false,
    filters = Filters.CreateState(),
    selection = Selection.Create(),
    dropRows = {},
    lootRows = {},
    archiveRows = {},
}

local TABS = {
    { key = "drops", label = "Drops" },
    { key = "active", label = "Chat Loot" },
    { key = "all", label = "All-Time" },
    { key = "archives", label = "Archives" },
}

--------------------------------------------------------------------------
-- View state
--------------------------------------------------------------------------

local function UpdateHeader()
    if view.mode == "drops" then
        local season = SYL.GetActiveSeason()

        view.subtitleText:SetText(
            (season and season.name or "Active Season")
            .. " — group loot"
        )

        return
    end

    if view.mode == "active" then
        local season = SYL.GetActiveSeason()

        view.subtitleText:SetText(
            season and season.name or "Active Season"
        )

        return
    end

    if view.mode == "all" then
        view.subtitleText:SetText("All-Time Loot History")
        return
    end

    if view.mode == "archives" then
        view.subtitleText:SetText("Archived Seasons")
        return
    end

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        view.subtitleText:SetText(
            season and season.name or "Archived Season"
        )
    end
end

local function UpdateTabs()
    for _, tab in ipairs(tabs) do
        -- Viewing one archive keeps the Archives tab lit, since that is where
        -- the user came from.
        local isSelected =
            tab.key == view.mode
            or (tab.key == "archives" and view.mode == "archive")

        tab:SetSelected(isSelected)
    end

    if view.mode == "archive" then
        buttons.back:Show()
    else
        buttons.back:Hide()
    end

    -- Archiving acts on the whole season, so it is offered from either of the
    -- active-season views.
    if view.mode == "drops" or view.mode == "active" then
        buttons.archiveSeason:Show()
    else
        buttons.archiveSeason:Hide()
    end
end

local function UpdateRows()
    if not frame then
        return
    end

    LootListView.HideAllRows(view)

    UpdateHeader()
    UpdateTabs()
    view.selectionBar:Update()

    view.dropHeader:Hide()
    view.lootHeader:Hide()

    -- Nothing on the archive list is filterable, so the bar would only be
    -- misleading there.
    if view.mode == "archives" then
        view.filterBar:Hide()

        LootListView.UpdateArchiveRows(view)

        return
    end

    view.filterBar:Show()

    if view.mode == "drops" then
        view.dropHeader:Show()
        LootListView.UpdateDropRows(view)
        return
    end

    view.lootHeader:Show()
    LootListView.UpdateLootRows(view)
end

local function SetMode(mode, archiveIndex)
    -- Switching views changes what the dropdowns list, so an open one would
    -- be showing options for the view you just left.
    FilterDropdown.CloseAll()

    -- A selection belongs to the list it was made in.
    Selection.Clear(view.selection)

    view.mode = mode
    view.selectedArchiveIndex = archiveIndex
    view.offset = 0

    if view.filterBar then
        view.filterBar:Refresh()
    end

    UpdateRows()
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

local function CreateTitleBar(parent)
    local accentMark = Theme.CreateAccentMark(parent)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    view.titleText = Theme.CreateText(parent, Theme.sizes.title, "textPrimary")
    view.titleText:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    view.titleText:SetText("SHOW US YOUR LOOT")

    view.subtitleText =
        Theme.CreateText(parent, Theme.sizes.subtitle, "textSecondary")

    view.subtitleText:SetPoint("TOPLEFT", 27, -40)
    view.subtitleText:SetText("Active Season")

    local closeCorner =
        CreateFrame("Button", nil, parent, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)
end

local function CreateNavigationBar(parent)
    local previous

    for _, definition in ipairs(TABS) do
        local tab = Theme.CreateTab(parent, definition.label, function()
            SetMode(definition.key, nil)
        end)

        tab.key = definition.key

        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", 14, -66)
        end

        previous = tab

        table.insert(tabs, tab)
    end

    local separator = Theme.CreateSeparator(parent)
    separator:SetPoint("TOPLEFT", 16, -92)
    separator:SetPoint("TOPRIGHT", -16, -92)

    buttons.archiveSeason =
        Theme.CreateButton(parent, 120, 24, "Archive Season", function()
            SYL.ArchivePopup.Show(function()
                SetMode("active", nil)
            end)
        end)

    buttons.archiveSeason:SetPoint("TOPRIGHT", -16, -66)

    buttons.back =
        Theme.CreateButton(parent, 130, 24, "Back to Archives", function()
            SetMode("archives", nil)
        end)

    buttons.back:SetPoint("TOPRIGHT", -16, -66)
end

local function CreateFilterBar(parent)
    view.filterBar = FilterBar.Create(parent, {
        state = view.filters,

        getRecords = function()
            return ListSources.GetUnfiltered(view)
        end,

        getFields = function()
            return ListSources.GetFields(view)
        end,

        onChange = function()
            view.offset = 0

            UpdateRows()
        end,
    })

    view.filterBar:SetPoint("TOPLEFT", 16, -100)
    view.filterBar:SetPoint("TOPRIGHT", -16, -100)
end

local function CreateScrollArea(parent)
    view.countText =
        Theme.CreateText(parent, Theme.sizes.subtitle, "textMuted")

    view.countText:SetPoint("TOPLEFT", 18, -132)
    view.countText:SetText("0 items")

    view.emptyText =
        Theme.CreateText(parent, Theme.sizes.title, "textMuted")

    view.emptyText:SetPoint("CENTER", 0, -12)
    view.emptyText:SetJustifyH("CENTER")
    view.emptyText:SetText("No loot has been recorded.")
    view.emptyText:Hide()

    view.dropHeader = Rows.CreateColumnHeader(parent, "drops")
    view.dropHeader:SetPoint("TOPLEFT", 16, -150)
    view.dropHeader:SetPoint("TOPRIGHT", -34, -150)

    view.lootHeader = Rows.CreateColumnHeader(parent, "loot")
    view.lootHeader:SetPoint("TOPLEFT", 16, -150)
    view.lootHeader:SetPoint("TOPRIGHT", -34, -150)
    view.lootHeader:Hide()

    SYL.ScrollArea.Create(parent, view, {
        childWidth = WINDOW_WIDTH - 70,

        onScrolled = UpdateRows,
        onSelect = function(row, isShift)
            view.selectionBar:OnRowSelect(row, isShift)
        end,

        onArchiveView = function(archiveIndex)
            SetMode("archive", archiveIndex)
        end,
    })
end

local function CreateFooter(parent)
    local separator = Theme.CreateSeparator(parent)
    separator:SetPoint("BOTTOMLEFT", 16, 44)
    separator:SetPoint("BOTTOMRIGHT", -16, 44)

    local refreshButton =
        Theme.CreateButton(parent, 100, 26, "Refresh", function()
            view.offset = 0

            UpdateRows()
        end)

    refreshButton:SetPoint("BOTTOMLEFT", 16, 12)

    local settingsButton =
        Theme.CreateButton(parent, 100, 26, "Settings", function()
            SYL:OpenSettingsWindow()
        end)

    settingsButton:SetPoint("LEFT", refreshButton, "RIGHT", 6, 0)

    local closeButton =
        Theme.CreateButton(parent, 100, 26, "Close", function()
            frame:Hide()
        end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)
end

local function CreateMainWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootMainFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)

    CreateTitleBar(frame)
    CreateNavigationBar(frame)
    CreateFilterBar(frame)
    view.selectionBar = SYL.SelectionBar.Create(frame, view, {
        onChanged = UpdateRows,
    })
    CreateScrollArea(frame)
    CreateFooter(frame)

    frame:SetScript("OnShow", function()
        view.offset = 0

        view.filterBar:Refresh()

        UpdateRows()
    end)

    -- A dropdown is parented to UIParent, so it would outlive the window.
    frame:SetScript("OnHide", function()
        FilterDropdown.CloseAll()
    end)

    frame:Hide()

    return frame
end

--------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------

function SYL:OpenMainWindow()
    local window = CreateMainWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

function SYL:RefreshMainWindow()
    if frame and frame:IsShown() then
        UpdateRows()
    end
end
