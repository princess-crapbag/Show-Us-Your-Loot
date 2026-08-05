-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Row rendering
-- lives in UI/LootListView.lua, frame building in UI/Widgets.lua and every
-- colour and size in UI/Theme.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local LootListView = SYL.LootListView

local WINDOW_WIDTH = 830
local WINDOW_HEIGHT = 562
local VISIBLE_ROWS = 13

local frame
local buttons = {}
local tabs = {}

-- Shared with LootListView, which reads it but never owns it.
local view = {
    mode = "active",
    selectedArchiveIndex = nil,
    offset = 0,
    visibleRows = VISIBLE_ROWS,
    lootRows = {},
    archiveRows = {},
}

local TABS = {
    { key = "active", label = "Active Season" },
    { key = "all", label = "All-Time" },
    { key = "archives", label = "Archives" },
}

--------------------------------------------------------------------------
-- View state
--------------------------------------------------------------------------

local function UpdateHeader()
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

    if view.mode == "active" then
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

    if view.mode == "archives" then
        view.columnHeader:Hide()
        LootListView.UpdateArchiveRows(view)
    else
        view.columnHeader:Show()
        LootListView.UpdateLootRows(view)
    end
end

local function SetMode(mode, archiveIndex)
    view.mode = mode
    view.selectedArchiveIndex = archiveIndex
    view.offset = 0

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

local function CreateScrollArea(parent)
    view.countText =
        Theme.CreateText(parent, Theme.sizes.subtitle, "textMuted")

    view.countText:SetPoint("TOPLEFT", 18, -104)
    view.countText:SetText("0 items")

    view.emptyText =
        Theme.CreateText(parent, Theme.sizes.title, "textMuted")

    view.emptyText:SetPoint("CENTER", 0, -12)
    view.emptyText:SetJustifyH("CENTER")
    view.emptyText:SetText("No loot has been recorded.")
    view.emptyText:Hide()

    view.columnHeader = Widgets.CreateLootColumnHeader(parent)
    view.columnHeader:SetPoint("TOPLEFT", 16, -122)
    view.columnHeader:SetPoint("TOPRIGHT", -34, -122)

    view.scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )

    view.scrollFrame:SetPoint("TOPLEFT", 16, -146)
    view.scrollFrame:SetPoint("BOTTOMRIGHT", -34, 52)

    view.scrollChild = CreateFrame("Frame", nil, view.scrollFrame)
    view.scrollChild:SetWidth(WINDOW_WIDTH - 70)
    view.scrollChild:SetHeight(VISIBLE_ROWS * Widgets.ROW_HEIGHT)

    view.scrollFrame:SetScrollChild(view.scrollChild)

    for index = 1, VISIBLE_ROWS do
        view.lootRows[index] =
            Widgets.CreateLootRow(view.scrollChild, index)

        view.archiveRows[index] =
            Widgets.CreateArchiveRow(view.scrollChild, index, function(archiveIndex)
                SetMode("archive", archiveIndex)
            end)
    end

    view.scrollFrame:EnableMouseWheel(true)

    view.scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if view.mode == "archives" then
            return
        end

        local maxOffset = math.max(
            0,
            #LootListView.GetRecords(view) - VISIBLE_ROWS
        )

        view.offset = math.max(
            0,
            math.min(maxOffset, view.offset - delta)
        )

        UpdateRows()
    end)

    if view.scrollFrame.ScrollBar then
        view.scrollFrame.ScrollBar:SetScript("OnValueChanged", function(_, value)
            if view.mode == "archives" then
                return
            end

            local newOffset =
                math.floor((value / Widgets.ROW_HEIGHT) + 0.5)

            if newOffset ~= view.offset then
                view.offset = newOffset

                UpdateRows()
            end
        end)
    end
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
    CreateScrollArea(frame)
    CreateFooter(frame)

    frame:SetScript("OnShow", function()
        view.offset = 0

        UpdateRows()
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
