-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Rendering lives in
-- UI/LootListView.lua, scrolling in UI/ScrollArea.lua, and every colour and
-- size in UI/Theme.lua.

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

local WINDOW_WIDTH = 900
local WINDOW_HEIGHT = 596
local VISIBLE_ROWS = 13

-- The scroll frame is inset by this much top and bottom, from ScrollArea, so
-- the rows that fit follow from the window height. MAX_ROWS caps the pool.
local LIST_TOP_INSET = 180
local LIST_BOTTOM_INSET = 52
local MAX_ROWS = 60

local frame
local buttons = {}

-- Shared with LootListView, which reads it but never owns it.
local view = {
    -- Drops are the primary record now, so the window opens on them.
    mode = "drops",
    selectedArchiveIndex = nil,
    offset = 0,
    visibleRows = VISIBLE_ROWS,
    showHidden = false,
    allSeasons = false,

    -- Which of an archived season's two record tables is on screen. Drops
    -- are the primary record, so they are the default, but a season archived
    -- before drop capture existed has none and opens on its chat loot.
    archiveShowsLoot = false,

    -- Raid, dungeon or both. "all" so nothing already recorded vanishes on
    -- update; narrowing is the officer's choice, not one made for them.
    contentScope = "all",
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
    view.subtitleText:SetText(ListSources.DescribeView(view))
end

local function UpdateTabs()
    -- Viewing one archive keeps the Archives tab lit, since that is where the
    -- user came from.
    view.tabStrip:SetSelected(
        view.mode == "archive" and "archives" or view.mode
    )

    if view.mode == "archive" then
        buttons.back:Show()
        buttons.archiveRecords:Show()

        -- Labelled with what it will switch to, so the button says what
        -- pressing it does rather than where you already are.
        buttons.archiveRecords.label:SetText(
            view.archiveShowsLoot and "Show drops" or "Show chat loot"
        )
    else
        buttons.back:Hide()
        buttons.archiveRecords:Hide()
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

    if view.mode == "drops" or ListSources.ArchiveShowsDrops(view) then
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

    if mode == "archive" then
        view.archiveShowsLoot =
            ListSources.DefaultArchiveShowsLoot(archiveIndex)
    end

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
    view.tabStrip, buttons = SYL.MainNav.Create(parent, {
        tabs = TABS,

        onTab = function(key)
            SetMode(key, nil)
        end,

        onArchive = function()
            SYL.ArchivePopup.Show(function()
                SetMode("active", nil)
            end)
        end,

        onBack = function()
            SetMode("archives", nil)
        end,

        onSwapRecords = function()
            view.archiveShowsLoot = not view.archiveShowsLoot
            view.offset = 0

            -- The two lists are different records, so a selection made in
            -- one means nothing in the other.
            Selection.Clear(view.selection)

            if view.filterBar then
                view.filterBar:Refresh()
            end

            UpdateRows()
        end,
    })
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

    view.countText:SetPoint("TOPLEFT", 18, -130)
    view.countText:SetText("0 items")

    view.emptyText =
        Theme.CreateText(parent, Theme.sizes.title, "textMuted")

    view.emptyText:SetPoint("CENTER", 0, -12)
    view.emptyText:SetJustifyH("CENTER")
    view.emptyText:SetText("No loot has been recorded.")
    view.emptyText:Hide()

    -- 6px below the action row, which ends at 148.
    view.dropHeader = Rows.CreateColumnHeader(parent, "drops")
    view.dropHeader:SetPoint("TOPLEFT", 16, -154)
    view.dropHeader:SetPoint("TOPRIGHT", -34, -154)

    view.lootHeader = Rows.CreateColumnHeader(parent, "loot")
    view.lootHeader:SetPoint("TOPLEFT", 16, -154)
    view.lootHeader:SetPoint("TOPRIGHT", -34, -154)
    view.lootHeader:Hide()

    SYL.ScrollArea.Create(parent, view, {
        childWidth = WINDOW_WIDTH - 70,
        windowHeight = WINDOW_HEIGHT,

        onScrolled = UpdateRows,

        onSelect = function(row, isShift)
            view.selectionBar:OnRowSelect(row, isShift)
        end,

        onActivate = function(record)
            SYL:OpenDropDetail(record)
        end,

        onArchiveView = function(archiveIndex)
            SetMode("archive", archiveIndex)
        end,
    })
end

local function CreateFooter(parent)
    SYL.MainFooter.Create(parent, {
        onRefresh = function()
            view.offset = 0

            UpdateRows()
        end,

        onClose = function()
            frame:Hide()
        end,
    })
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
    Widgets.CloseOnEscape(frame)

    CreateTitleBar(frame)
    CreateNavigationBar(frame)
    CreateFilterBar(frame)
    view.selectionBar = SYL.SelectionBar.Create(frame, view, {
        onChanged = UpdateRows,
    })
    CreateScrollArea(frame)
    CreateFooter(frame)

    -- Added after the scroll area, because growing the list means building
    -- rows that belong to it.
    Widgets.MakeResizableList(frame, {
        key = "main",
        minWidth = WINDOW_WIDTH,
        listTop = LIST_TOP_INSET,
        rowHeight = Widgets.ROW_HEIGHT,
        footer = LIST_BOTTOM_INSET,
        maxRows = MAX_ROWS,

        onRows = function(count)
            view.visibleRows = count

            SYL.ScrollArea.EnsureRows(view, count)

            -- Everything is hidden first: shrinking the window leaves rows
            -- on screen that UpdateRows will not revisit, since it only ever
            -- walks as far as the new count.
            SYL.LootListView.HideAllRows(view)

            UpdateRows()
        end,
    })

    Widgets.RestoreSize(frame, "main")

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
