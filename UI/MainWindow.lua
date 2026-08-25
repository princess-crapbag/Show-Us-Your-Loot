-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Rendering lives in
-- UI/LootListView.lua, scrolling in UI/ScrollArea.lua, and every color and
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
local VISIBLE_ROWS = 14

-- The scroll frame is inset by this much top and bottom, from ScrollArea, so
-- the rows that fit follow from the window height. MAX_ROWS caps the pool.
-- THE LIST STARTS 28px HIGHER than it did.
--
-- The stack above it used to be the title, the tabs, the filter bar, the
-- SELECTION BAR and the column header. The selection bar's buttons moved to
-- the footer line -- which was empty on its left, because UI/MainFooter.lua's
-- button list has been {} since all six of its buttons became tabs -- so a
-- whole 28px row came out of the top and none was added at the bottom.
--
-- 596 - 152 - 52 is 392, which is fourteen rows of 28. It was thirteen.
local LIST_TOP_INSET = 152
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

    -- RAIDS ONLY, which is Aimee's default: "default to gear only, raids
    -- only. still give the option to swap through others."
    --
    -- The note this replaces argued for "all" so nothing already recorded
    -- vanishes on update. That was the right caution when the scope button
    -- was new and nobody had met it; it is now a labelled control on the bar
    -- above the list, and the list this addon exists for is the raid's.
    contentScope = "raid",

    -- Narrowed to gear somebody actually received. On, hers -- the fairness
    -- boards only ever argue about gear, and the button beside the list says
    -- what it is doing and turns off in one click.
    gearOnly = true,

    -- Newest first, which is what the list has always shown. Every other
    -- window in the addon has had a sortable header for a while; this one,
    -- the list people actually read, had a header that looked identical and
    -- did nothing when clicked.
    sortKey = "date",
    sortReversed = false,

    -- Filters.CreateState leaves every field unconstrained; the difficulty
    -- is then set to whatever she last raided. See DefaultDifficulty below.
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
--
-- Six now, and the order is the order an officer wants them: the dashboard
-- first because it answers the question, guild screens next, and Keys last
-- because it is the one screen where half the names will not be in the guild.
--
-- Raiders is Players and Roster merged. The difference between those two
-- screens was always the audience — people with loot history versus people
-- who could raid — and that is a button, not a tab.
--
-- Archives stays at the end and out of the way. It is reached once a tier.
local TABS = {
    { key = "dashboard", label = "Dashboard" },
    { key = "feed", label = "Loot" },
    { key = "raiders", label = "Raiders" },
    { key = "nights", label = "Calendar" },
    { key = "bosses", label = "Bosses" },
    { key = "keys", label = "Keys" },
    { key = "archives", label = "Archives" },
}

-- Modes that draw their own content instead of the loot list. Everything the
-- list machinery does — filters, selection, the sort header — is hidden for
-- these, and each is responsible for its own frame.
local PANEL_MODES = {
    dashboard = true,
    raiders = true,
    nights = true,
    bosses = true,
    keys = true,
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
        buttons.renameSeason:Show()
    else
        buttons.archiveSeason:Hide()
        buttons.renameSeason:Hide()
    end
end

-- Shows the one panel that belongs to this mode and hides the rest, so a
-- panel can never be left on screen under another tab's content.
local function UpdatePanels()
    for mode, panel in pairs(view.panels or {}) do
        if mode == view.mode then
            panel:Show()

            if panel.Refresh then
                panel:Refresh()
            end
        else
            panel:Hide()
        end
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
    UpdatePanels()

    -- NOT HIDDEN UNCONDITIONALLY HERE ANY MORE.
    --
    -- Hiding a frame fires OnHide on its children, and every filter caret
    -- hooks OnHide to close its panel -- that is what stops a dropdown
    -- floating over the game when its window shuts. But this line ran on
    -- EVERY UpdateRows, and ticking a box in a dropdown calls onChange, which
    -- calls UpdateRows. So the panel closed on the first tick and multi-select
    -- was impossible: one value per open, every time.
    --
    -- It is hidden in the two branches below that actually leave the loot
    -- list, and shown again at the end of the feed branch.

    -- A panel owns the whole body, so every control belonging to the loot
    -- list goes away rather than sitting behind it.
    --
    -- HideAllRows only hides rows. The count line, the empty-state text and
    -- the scroll frame are separate and would otherwise sit on top of a
    -- dashboard tile — the count in particular lands at -130, right through
    -- the first row of widgets.
    if PANEL_MODES[view.mode] then
        view.feedHeader:Hide()
        view.filterBar:Hide()
        view.selectionBar:HideAll()

        if view.archiveBar then
            view.archiveBar:Hide()
        end

        view.countText:Hide()
        view.emptyText:Hide()

        if view.scrollFrame then
            view.scrollFrame:Hide()
        end

        return
    end

    view.countText:Show()

    if view.scrollFrame then
        view.scrollFrame:Show()
    end

    view.selectionBar:Update()

    -- Renaming and merging belong to the archive list and nowhere else, so
    -- the bar follows the tab rather than sitting there greyed out.
    if view.archiveBar then
        if view.mode == "archives" then
            view.archiveBar.Refresh()
            view.archiveBar:Show()
        else
            view.archiveBar:Hide()
        end
    end

    -- Nothing on the archive list is filterable, so the bar would only be
    -- misleading there.
    if view.mode == "archives" then
        view.feedHeader:Hide()
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

    -- Settings sat in the footer, in the row used every raid night, and is
    -- opened about once a month. A corner is where a thing like that belongs.
    view.settingsButton = Theme.CreateButton(parent, 26, 22, "", function()
        if SYL.OpenSettingsWindow then
            SYL:OpenSettingsWindow()
        end
    end)

    -- An actual cog rather than a character that looks a bit like one. This
    -- was "*", which is what a settings button looks like when nobody has
    -- drawn one — the shape people are hunting for in a corner is a gear, and
    -- an asterisk reads as a footnote marker.
    --
    -- The label is left in place and empty: Theme.CreateButton owns it, and
    -- removing it would mean the button no longer matches every other button.
    local gear = view.settingsButton:CreateTexture(nil, "ARTWORK")

    gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetSize(16, 16)
    gear:SetPoint("CENTER", 0, 0)

    view.settingsButton.icon = gear

    -- Clear of the close button, which is 32px wide at -6: that spans -38 to
    -- -6, so anything starting nearer than -44 sits underneath it.
    view.settingsButton:SetPoint("TOPRIGHT", -44, -14)

    SYL.Tooltips.Attach(
        view.settingsButton,
        "Settings",
        "Color scheme, what gets recorded, which dashboard widgets are on, "
        .. "and the features that can be switched off."
    )
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

        -- Stays on the Archives tab afterwards. Renaming is a correction, and
        -- being thrown to another screen for making one reads as something
        -- larger having happened.
        onRenameSeason = function()
            SYL.SeasonRenameDialog.Show(function()
                SetMode("archives", nil)
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
        Theme.CreateText(parent, Theme.sizes.control, "textMuted")

    -- OFF THE RIGHT EDGE, not at a fixed x.
    --
    -- At 200 this was printed straight through the From box (200..252), the
    -- To label and the To box (281..375) -- and under those boxes' own
    -- placeholder text, so "0 items" was glyphs on glyphs. x 200 was free
    -- space on the two-bar layout and is the middle of the date fields on
    -- this one.
    --
    -- Anchored to the right edge because Clear is too: the two keep their
    -- 10px gap at any window width, and the count grows leftward into the
    -- empty middle of the bar instead of rightward into whatever the row
    -- gains next. The widest string it can hold measures 361 and the To box
    -- ends at 375, so the worst case still clears by 83px.
    view.countText:SetPoint("TOPRIGHT", -80, -105)
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
        top = LIST_TOP_INSET - 2,

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

        -- THE FILTERS LIVE IN THE HEADERS NOW. The bar builds the dropdown
        -- and the header places it at the caret; neither has to know what the
        -- other does. See UI/SortHeader.lua.
        makeFilter = function(key, headerFrame)
            if not view.filterBar or not view.filterBar.MakeFilter then
                return nil
            end

            return view.filterBar:MakeFilter(key, headerFrame)
        end,

        -- What colors a column name accent: it is narrowing the list.
        isFiltered = function(key)
            return Filters.CountSelected(view.filters, key) > 0
                or (view.filters.touched and view.filters.touched[key])
                and true or false
        end,
    })

    SYL.ScrollArea.Create(parent, view, {
        childWidth = WINDOW_WIDTH - 70,
        windowHeight = WINDOW_HEIGHT,

        -- The same two numbers the row count is derived from. They were
        -- duplicated inside UI/ScrollArea.lua and drifted; see the note there.
        listTop = LIST_TOP_INSET,
        footer = LIST_BOTTOM_INSET,

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

        onArchiveSelect = function(archiveIndex)
            SYL.ArchiveControls.Toggle(view, archiveIndex)

            UpdateRows()
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

-- WHAT THE WINDOW OPENS ON, applied every time it is opened rather than once
-- at file scope.
--
-- Clear deliberately opens the list all the way up -- see the note on the
-- Clear handler, and the bulk Hide it cost her when it did not. But `view` is
-- a module local that only resets on /reload, so after one Clear she was on
-- all-content, no-gear-filter for the rest of the session rather than until
-- she reopened the window.
--
-- Her call, given the two: "do as you suggest" -- Clear still opens
-- everything, and reopening the window puts the defaults back. The count line
-- says "38 of 53 items · 18 hidden" either way, so neither state is silent.
local function ApplyDefaults()
    view.contentScope = "raid"
    view.gearOnly = true
    view.allSeasons = false

    SYL.Filters.ApplyDefaultDifficulty(view.filters, SYL.GetActiveRaids())
end

local function CreateMainWindow()
    if frame then
        return frame
    end

    ApplyDefaults()

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

    -- Title bar only. The tab strip sits at -66 and this used to cover it.
    Widgets.MakeMovable(frame, true)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    CreateTitleBar(frame)
    CreateNavigationBar(frame)
    CreateFilterBar(frame)

    -- After the nav so the tabs exist to be switched to, and before the
    -- first UpdateRows so a panel is never asked to draw before it is built.
    view.panels = SYL.TabPanels.CreateAll(frame, {
        onOpenTab = function(tab)
            -- A widget names the tab it is about; Settings is a window rather
            -- than a tab, so it is the one that does not switch.
            if tab == "settings" then
                if SYL.OpenSettingsWindow then
                    SYL:OpenSettingsWindow()
                end

                return
            end

            SetMode(tab, nil)
        end,
    })

    -- Opens on the dashboard. It is the screen that answers the question, and
    -- the loot list is one click away for anybody who wants the old landing.
    view.mode = "dashboard"

    view.selectionBar = SYL.SelectionBar.Create(frame, view, {
        onChanged = UpdateRows,
    })

    -- The archive list's own bar. Shown only on the Archives tab, because
    -- renaming and merging seasons has no meaning anywhere else.
    view.archiveBar = SYL.ArchiveControls.Create(frame, view, {
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
    ApplyDefaults()

    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateMainWindow())
end

-- Opens the window already showing one tab. Added for the key request
-- notification, which tells somebody a request arrived and then has to be able
-- to put them on the screen that answers it — "/syl keys to answer" printed in
-- chat is only useful if typing it lands somewhere.
function SYL:OpenMainWindowAt(mode)
    ApplyDefaults()

    local window = CreateMainWindow()

    SYL.WindowStack.ShowWindow(window)

    if mode then
        SetMode(mode, nil)
    end
end

function SYL:RefreshMainWindow()
    if frame and frame:IsShown() then
        UpdateRows()
    end
end
