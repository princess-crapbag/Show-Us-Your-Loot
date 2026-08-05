-- UI/MainWindow.lua
--
-- The main loot window: chrome, navigation and view state. Row rendering
-- lives in UI/LootListView.lua and frame building in UI/Widgets.lua.

local SYL = _G.ShowUsYourLoot
local Widgets = SYL.Widgets
local LootListView = SYL.LootListView

local WINDOW_WIDTH = 830
local WINDOW_HEIGHT = 520
local VISIBLE_ROWS = 13

local frame
local buttons = {}

-- Shared with LootListView, which reads it but never owns it.
local view = {
    mode = "active",
    selectedArchiveIndex = nil,
    offset = 0,
    visibleRows = VISIBLE_ROWS,
    lootRows = {},
    archiveRows = {},
}

--------------------------------------------------------------------------
-- View state
--------------------------------------------------------------------------

local function UpdateHeader()
    view.titleText:SetText("Show Us Your Loot")

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

local function UpdateNavigationButtons()
    Widgets.SetButtonSelected(buttons.active, view.mode == "active")
    Widgets.SetButtonSelected(buttons.allTime, view.mode == "all")

    Widgets.SetButtonSelected(
        buttons.archives,
        view.mode == "archives" or view.mode == "archive"
    )

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
    UpdateNavigationButtons()

    if view.mode == "archives" then
        LootListView.UpdateArchiveRows(view)
    else
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
-- Archive confirmation
--------------------------------------------------------------------------

StaticPopupDialogs["SHOWUSYOURLOOT_ARCHIVE_SEASON"] = {
    text = "Archive the current season and enter the name of the new active season.",

    button1 = "Archive",
    button2 = "Cancel",

    hasEditBox = true,
    editBoxWidth = 240,

    OnShow = function(self)
        self.EditBox:SetText("New Season")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,

    OnAccept = function(self)
        local newSeasonName = self.EditBox:GetText()

        if not newSeasonName or newSeasonName == "" then
            newSeasonName = "New Season"
        end

        local archivedSeason, newSeason =
            SYL.ArchiveCurrentSeason(newSeasonName)

        if not archivedSeason then
            return
        end

        SYL:Print(
            "Archived "
            .. archivedSeason.name
            .. " with "
            .. #(archivedSeason.loot or {})
            .. " records."
        )

        SYL:Print("New active season: " .. newSeason.name)

        SetMode("active", nil)
    end,

    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,

    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,

    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

local function CreateHeaderText(parent)
    view.titleText =
        parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

    view.titleText:SetPoint("TOP", 0, -16)
    view.titleText:SetText("Show Us Your Loot")

    view.subtitleText =
        parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    view.subtitleText:SetPoint("TOP", 0, -40)
    view.subtitleText:SetText("Active Season")

    view.countText =
        parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    view.countText:SetPoint("TOPLEFT", 22, -90)
    view.countText:SetText("Recorded items: 0")

    view.emptyText =
        parent:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")

    view.emptyText:SetPoint("CENTER", 0, -12)
    view.emptyText:SetText("No loot has been recorded.")
    view.emptyText:Hide()
end

local function CreateNavigationBar(parent)
    local closeCorner =
        CreateFrame("Button", nil, parent, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -5, -5)

    buttons.active =
        Widgets.CreatePanelButton(parent, 120, 24, "Active Season", function()
            SetMode("active", nil)
        end)

    buttons.active:SetPoint("TOPLEFT", 20, -58)

    buttons.allTime =
        Widgets.CreatePanelButton(parent, 100, 24, "All-Time", function()
            SetMode("all", nil)
        end)

    buttons.allTime:SetPoint("LEFT", buttons.active, "RIGHT", 6, 0)

    buttons.archives =
        Widgets.CreatePanelButton(parent, 100, 24, "Archives", function()
            SetMode("archives", nil)
        end)

    buttons.archives:SetPoint("LEFT", buttons.allTime, "RIGHT", 6, 0)

    buttons.back =
        Widgets.CreatePanelButton(parent, 115, 24, "Back to Archives", function()
            SetMode("archives", nil)
        end)

    buttons.back:SetPoint("TOPRIGHT", -20, -58)

    buttons.archiveSeason =
        Widgets.CreatePanelButton(parent, 125, 24, "Archive Season", function()
            StaticPopup_Show("SHOWUSYOURLOOT_ARCHIVE_SEASON")
        end)

    buttons.archiveSeason:SetPoint("TOPRIGHT", -20, -86)
end

local function CreateScrollArea(parent)
    view.scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )

    view.scrollFrame:SetPoint("TOPLEFT", 18, -142)
    view.scrollFrame:SetPoint("BOTTOMRIGHT", -38, 58)

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
    local refreshButton =
        Widgets.CreatePanelButton(parent, 110, 24, "Refresh", function()
            view.offset = 0

            UpdateRows()
        end)

    refreshButton:SetPoint("BOTTOMLEFT", 20, 22)

    local closeButton =
        Widgets.CreatePanelButton(parent, 110, 24, "Close", function()
            frame:Hide()
        end)

    closeButton:SetPoint("BOTTOMRIGHT", -20, 22)
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
    Widgets.ApplyDialogBackdrop(frame)

    CreateHeaderText(frame)
    CreateNavigationBar(frame)
    Widgets.CreateLootColumnHeader(frame)
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
