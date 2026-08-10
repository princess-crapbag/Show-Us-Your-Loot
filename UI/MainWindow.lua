-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Rendering lives in
-- UI/LootListView.lua, scrolling in UI/ScrollArea.lua, and every colour and
-- size in UI/Theme.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
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
    mode = "feed",
    selectedArchiveIndex = nil,
    offset = 0,
    visibleRows = VISIBLE_ROWS,
    showHidden = false,
    allSeasons = false,

    -- Raid, dungeon or both. "all" so nothing already recorded vanishes on
    -- update; narrowing is the officer's choice, not one made for them.
    contentScope = "all",

    -- Narrowed to gear somebody actually received. Off for the same
    -- reason: hiding three hundred records without being asked is how an
    -- update looks like data loss.
    gearOnly = false,

    -- Newest first, which is what the list has always shown. Every other
    -- window in the addon has had a sortable header for a while; this one,
    -- the list people actually read, had a header that looked identical and
    -- did nothing when clicked.
    sortKey = "date",
    sortReversed = false,

    filters = Filters.CreateState(),
    selection = Selection.Create(),
    feedRows = {},
    archiveRows = {},
}

-- Two tabs, not four. Drops and Chat Loot described how a record was
-- captured rather than what it was, and every raid win appeared on both. The
-- merged list holds them together with the type on each row, and All-Time
-- became redundant the moment "All seasons" applied to one list instead of
-- to whichever tab you happened to be on.
local TABS = {
    { key = "feed", label = "Loot" },
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
    else
        buttons.back:Hide()
    end

    -- Archiving is offered from the archive browser, which is the list of
    -- things it creates, and nowhere else. It used to be the other way round:
    -- permanently on screen next to the loot list, and hidden on the one tab
    -- it is actually about.
    if view.mode == "archives" then
        buttons.archiveSeason:Show()
    else
        buttons.archiveSeason:Hide()
    end
end

local function UpdateRows()
    if not frame then
        return
    end

    -- Every path that changes what should be on screen ends up here: a tab,
    -- a filter, a scroll, a selection, a captured drop. So this is the one
    -- place the feed cache has to be dropped, and the list below is rebuilt
    -- once rather than once per thing that asks for it.
    ListSources.Invalidate()

    LootListView.HideAllRows(view)

    UpdateHeader()
    UpdateTabs()
    view.selectionBar:Update()

    view.feedHeader:Hide()

    -- Nothing on the archive list is filterable, so the bar would only be
    -- misleading there.
    if view.mode == "archives" then
        view.filterBar:Hide()

        LootListView.UpdateArchiveRows(view)

        return
    end

    view.filterBar:Show()

    view.feedHeader:Show()

    -- Keeps the arrow on the column actually being sorted by, including when
    -- the sort changed through something other than a click on it.
    view.feedHeader.UpdateLabels()

    LootListView.UpdateFeedRows(view)
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
    view.tabStrip, buttons = SYL.MainNav.Create(parent, {
        tabs = TABS,

        onTab = function(key)
            SetMode(key, nil)
        end,

        onArchive = function()
            SYL.ArchivePopup.Show(function()
                SetMode("feed", nil)
            end)
        end,

        onBack = function()
            SetMode("archives", nil)
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

        -- The toggles live on the view, not in the filter state, so the bar
        -- cannot reset them itself. See the note on the Clear button.
        onClear = function()
            view.contentScope = "all"
            view.gearOnly = false
            view.allSeasons = false

            -- A selection made under the old filters is not a selection the
            -- user would make under these ones, and leaving it ticked is how
            -- a bulk action reaches rows nobody could see when they chose.
            Selection.Clear(view.selection)
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

    -- Wrapped and bounded, because the empty message explains why the list is
    -- empty rather than only stating that it is, and that does not fit on one
    -- line. No initial text: every draw sets it, so anything written here
    -- could never be read.
    view.emptyText:SetWordWrap(true)
    view.emptyText:SetWidth(WINDOW_WIDTH - 120)
    view.emptyText:Hide()

    -- 6px below the action row, which ends at 148. SortHeader anchors itself
    -- 24px above the list top it is given, so 178 lands on the same -154.
    view.feedHeader = SYL.SortHeader.Create(parent, {
        columns = SYL.Columns.Get("feed"),
        offsets = SYL.Columns.offsets.feed,
        top = 178,

        getSort = function()
            return view.sortKey, view.sortReversed
        end,

        onSort = function(key, reversed)
            view.sortKey = key
            view.sortReversed = reversed
            view.offset = 0

            -- The list is about to be reordered underneath a selection that
            -- was made by position.
            Selection.Clear(view.selection)

            UpdateRows()
        end,
    })

    SYL.ScrollArea.Create(parent, view, {
        childWidth = WINDOW_WIDTH - 70,
        windowHeight = WINDOW_HEIGHT,

        onScrolled = UpdateRows,

        onSelect = function(row, isShift)
            view.selectionBar:OnRowSelect(row, isShift)
        end,

        onActivate = function(entry)
            SYL:OpenDropDetail(SYL.LootFeed.ToDetailRecord(entry))
        end,

        onArchiveView = function(archiveIndex)
            SetMode("archive", archiveIndex)
        end,
    })
end

local function CreateFooter(parent)
    SYL.MainFooter.Create(parent, {
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
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateMainWindow())
end

function SYL:RefreshMainWindow()
    if frame and frame:IsShown() then
        UpdateRows()
    end
end
