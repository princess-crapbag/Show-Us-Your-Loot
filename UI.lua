-- UI.lua

local SYL = _G.ShowUsYourLoot

local ROW_HEIGHT = 25
local VISIBLE_ROWS = 13
local WINDOW_WIDTH = 830
local WINDOW_HEIGHT = 520

local mainFrame
local scrollFrame
local scrollChild

local lootRows = {}
local archiveRows = {}

local titleText
local subtitleText
local countText
local emptyText

local activeButton
local allTimeButton
local archivesButton
local backButton
local archiveSeasonButton

local currentMode = "active"
local selectedArchiveIndex = nil
local currentOffset = 0

local function GetActiveSeason()
    if SYL.GetActiveSeason then
        return SYL.GetActiveSeason()
    end

    return nil
end

local function GetArchives()
    if SYL.GetArchives then
        return SYL.GetArchives()
    end

    return {}
end

local function GetAllLoot()
    if SYL.GetAllLoot then
        return SYL.GetAllLoot()
    end

    return {}
end

local function GetCurrentLootRecords()
    if currentMode == "active" then
        local season = GetActiveSeason()

        if season then
            return season.loot or {}
        end

        return {}
    end

    if currentMode == "all" then
        return GetAllLoot()
    end

    if currentMode == "archive" then
        local archives = GetArchives()
        local season = archives[selectedArchiveIndex]

        if season then
            return season.loot or {}
        end

        return {}
    end

    return {}
end

local function FormatLocation(record)
    local instanceName =
        record.instanceName
        or record.zoneName
        or "Unknown"

    local difficultyName =
        record.difficultyName

    if difficultyName
        and difficultyName ~= ""
        and difficultyName ~= "None"
    then
        return instanceName .. " - " .. difficultyName
    end

    return instanceName
end

local function FormatDate(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%y %I:%M %p", timestamp)
end

local function SetItemButtonLink(button, itemLink)
    button.itemLink = itemLink

    button:SetScript("OnEnter", function(self)
        if not self.itemLink then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if not self.itemLink then
            return
        end

        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)
end

local function SetNavigationButtonSelected(button, selected)
    if selected then
        button:Disable()
    else
        button:Enable()
    end
end

local function HideAllRows()
    for _, row in ipairs(lootRows) do
        row:Hide()
    end

    for _, row in ipairs(archiveRows) do
        row:Hide()
    end
end

local function CreateLootRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint(
        "TOPLEFT",
        0,
        -((index - 1) * ROW_HEIGHT)
    )
    row:SetPoint(
        "TOPRIGHT",
        -20,
        -((index - 1) * ROW_HEIGHT)
    )

    row.background =
        row:CreateTexture(nil, "BACKGROUND")

    row.background:SetAllPoints()

    if index % 2 == 0 then
        row.background:SetColorTexture(
            1,
            1,
            1,
            0.035
        )
    else
        row.background:SetColorTexture(
            0,
            0,
            0,
            0
        )
    end

    row.numberText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    row.numberText:SetPoint("LEFT", 6, 0)
    row.numberText:SetWidth(38)
    row.numberText:SetJustifyH("LEFT")

    row.playerText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    row.playerText:SetPoint(
        "LEFT",
        row.numberText,
        "RIGHT",
        4,
        0
    )

    row.playerText:SetWidth(155)
    row.playerText:SetJustifyH("LEFT")
    row.playerText:SetWordWrap(false)

    row.itemButton =
        CreateFrame("Button", nil, row)

    row.itemButton:SetPoint(
        "LEFT",
        row.playerText,
        "RIGHT",
        8,
        0
    )

    row.itemButton:SetSize(
        255,
        ROW_HEIGHT
    )

    row.itemText =
        row.itemButton:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    row.itemText:SetAllPoints()
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetWordWrap(false)

    row.locationText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisableSmall"
        )

    row.locationText:SetPoint(
        "LEFT",
        row.itemButton,
        "RIGHT",
        8,
        0
    )

    row.locationText:SetWidth(190)
    row.locationText:SetJustifyH("LEFT")
    row.locationText:SetWordWrap(false)

    row.dateText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisableSmall"
        )

    row.dateText:SetPoint(
        "LEFT",
        row.locationText,
        "RIGHT",
        8,
        0
    )

    row.dateText:SetWidth(125)
    row.dateText:SetJustifyH("LEFT")

    return row
end

local function CreateArchiveRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(36)
    row:SetPoint(
        "TOPLEFT",
        0,
        -((index - 1) * 36)
    )
    row:SetPoint(
        "TOPRIGHT",
        -20,
        -((index - 1) * 36)
    )

    row.background =
        row:CreateTexture(nil, "BACKGROUND")

    row.background:SetAllPoints()

    if index % 2 == 0 then
        row.background:SetColorTexture(
            1,
            1,
            1,
            0.035
        )
    else
        row.background:SetColorTexture(
            0,
            0,
            0,
            0
        )
    end

    row.nameText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    row.nameText:SetPoint("LEFT", 12, 0)
    row.nameText:SetWidth(310)
    row.nameText:SetJustifyH("LEFT")

    row.countText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisable"
        )

    row.countText:SetPoint(
        "LEFT",
        row.nameText,
        "RIGHT",
        12,
        0
    )

    row.countText:SetWidth(120)
    row.countText:SetJustifyH("LEFT")

    row.dateText =
        row:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisable"
        )

    row.dateText:SetPoint(
        "LEFT",
        row.countText,
        "RIGHT",
        12,
        0
    )

    row.dateText:SetWidth(170)
    row.dateText:SetJustifyH("LEFT")

    row.viewButton =
        CreateFrame(
            "Button",
            nil,
            row,
            "UIPanelButtonTemplate"
        )

    row.viewButton:SetSize(85, 22)
    row.viewButton:SetPoint("RIGHT", -8, 0)
    row.viewButton:SetText("View")

    row.viewButton:SetScript(
        "OnClick",
        function(self)
            selectedArchiveIndex =
                self.archiveIndex

            currentMode = "archive"
            currentOffset = 0

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end
        end
    )

    return row
end

local function UpdateNavigationButtons()
    SetNavigationButtonSelected(
        activeButton,
        currentMode == "active"
    )

    SetNavigationButtonSelected(
        allTimeButton,
        currentMode == "all"
    )

    SetNavigationButtonSelected(
        archivesButton,
        currentMode == "archives"
            or currentMode == "archive"
    )

    if currentMode == "archive" then
        backButton:Show()
    else
        backButton:Hide()
    end

    if currentMode == "active" then
        archiveSeasonButton:Show()
    else
        archiveSeasonButton:Hide()
    end
end

local function UpdateHeader()
    local activeSeason = GetActiveSeason()

    if currentMode == "active" then
        titleText:SetText("Show Us Your Loot")

        subtitleText:SetText(
            activeSeason
                and activeSeason.name
                or "Active Season"
        )

        return
    end

    if currentMode == "all" then
        titleText:SetText("Show Us Your Loot")
        subtitleText:SetText("All-Time Loot History")
        return
    end

    if currentMode == "archives" then
        titleText:SetText("Show Us Your Loot")
        subtitleText:SetText("Archived Seasons")
        return
    end

    if currentMode == "archive" then
        local archives = GetArchives()
        local season =
            archives[selectedArchiveIndex]

        titleText:SetText("Show Us Your Loot")

        subtitleText:SetText(
            season
                and season.name
                or "Archived Season"
        )
    end
end

local function UpdateLootRows()
    local records = GetCurrentLootRecords()
    local totalRecords = #records

    countText:SetText(
        "Recorded items: " .. totalRecords
    )

    if totalRecords == 0 then
        emptyText:SetText(
            "No loot has been recorded in this view."
        )

        emptyText:Show()
    else
        emptyText:Hide()
    end

    local maxOffset =
        math.max(
            0,
            totalRecords - VISIBLE_ROWS
        )

    if currentOffset > maxOffset then
        currentOffset = maxOffset
    end

    for rowIndex = 1, VISIBLE_ROWS do
        local recordIndex =
            totalRecords
            - currentOffset
            - rowIndex
            + 1

        local row = lootRows[rowIndex]

        if recordIndex >= 1 then
            local record =
                records[recordIndex]

            row.numberText:SetText(
                recordIndex .. "."
            )

            row.playerText:SetText(
                record.recipient
                    or "Unknown"
            )

            row.itemText:SetText(
                record.itemLink
                    or record.itemName
                    or "Unknown item"
            )

            row.locationText:SetText(
                FormatLocation(record)
            )

            row.dateText:SetText(
                FormatDate(record.timestamp)
            )

            SetItemButtonLink(
                row.itemButton,
                record.itemLink
            )

            row:Show()
        else
            row.itemButton.itemLink = nil
            row:Hide()
        end
    end

    local scrollRange =
        maxOffset * ROW_HEIGHT

    scrollChild:SetHeight(
        math.max(
            VISIBLE_ROWS * ROW_HEIGHT,
            totalRecords * ROW_HEIGHT
        )
    )

    scrollFrame:SetVerticalScroll(
        currentOffset * ROW_HEIGHT
    )

    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetMinMaxValues(
            0,
            scrollRange
        )

        scrollFrame.ScrollBar:SetValue(
            currentOffset * ROW_HEIGHT
        )
    end
end

local function UpdateArchiveRows()
    local archives = GetArchives()
    local totalArchives = #archives

    countText:SetText(
        "Archived seasons: "
        .. totalArchives
    )

    if totalArchives == 0 then
        emptyText:SetText(
            "No seasons have been archived."
        )

        emptyText:Show()
    else
        emptyText:Hide()
    end

    for index = 1, VISIBLE_ROWS do
        local row = archiveRows[index]
        local season = archives[index]

        if season then
            row.nameText:SetText(
                season.name
                    or "Unnamed Season"
            )

            row.countText:SetText(
                #(season.loot or {})
                .. " items"
            )

            row.dateText:SetText(
                "Archived "
                .. date(
                    "%m/%d/%Y",
                    season.archivedAt
                        or season.startedAt
                        or time()
                )
            )

            row.viewButton.archiveIndex =
                index

            row:Show()
        else
            row:Hide()
        end
    end

    scrollChild:SetHeight(
        VISIBLE_ROWS * 36
    )

    scrollFrame:SetVerticalScroll(0)

    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetMinMaxValues(
            0,
            0
        )

        scrollFrame.ScrollBar:SetValue(0)
    end
end

local function UpdateRows()
    if not mainFrame then
        return
    end

    HideAllRows()
    UpdateHeader()
    UpdateNavigationButtons()

    if currentMode == "archives" then
        UpdateArchiveRows()
    else
        UpdateLootRows()
    end
end

local function CreateLootHeader(parent)
    local header =
        CreateFrame("Frame", nil, parent)

    header:SetHeight(24)
    header:SetPoint("TOPLEFT", 18, -116)
    header:SetPoint("TOPRIGHT", -38, -116)

    local numberHeader =
        header:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    numberHeader:SetPoint("LEFT", 6, 0)
    numberHeader:SetWidth(38)
    numberHeader:SetText("#")
    numberHeader:SetJustifyH("LEFT")

    local playerHeader =
        header:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    playerHeader:SetPoint(
        "LEFT",
        numberHeader,
        "RIGHT",
        4,
        0
    )

    playerHeader:SetWidth(155)
    playerHeader:SetText("Player")
    playerHeader:SetJustifyH("LEFT")

    local itemHeader =
        header:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    itemHeader:SetPoint(
        "LEFT",
        playerHeader,
        "RIGHT",
        8,
        0
    )

    itemHeader:SetWidth(255)
    itemHeader:SetText("Item")
    itemHeader:SetJustifyH("LEFT")

    local locationHeader =
        header:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    locationHeader:SetPoint(
        "LEFT",
        itemHeader,
        "RIGHT",
        8,
        0
    )

    locationHeader:SetWidth(190)
    locationHeader:SetText("Location")
    locationHeader:SetJustifyH("LEFT")

    local dateHeader =
        header:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalSmall"
        )

    dateHeader:SetPoint(
        "LEFT",
        locationHeader,
        "RIGHT",
        8,
        0
    )

    dateHeader:SetWidth(125)
    dateHeader:SetText("Date")
    dateHeader:SetJustifyH("LEFT")

    return header
end

local function ShowArchivePopup()
    StaticPopup_Show(
        "SHOWUSYOURLOOT_ARCHIVE_SEASON"
    )
end

StaticPopupDialogs[
    "SHOWUSYOURLOOT_ARCHIVE_SEASON"
] = {
    text =
        "Archive the current season and enter the name of the new active season.",

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
        local newSeasonName =
            self.EditBox:GetText()

        if not newSeasonName
            or newSeasonName == ""
        then
            newSeasonName = "New Season"
        end

        local archivedSeason,
            newSeason =
            SYL.ArchiveCurrentSeason(
                newSeasonName
            )

        if archivedSeason then
            SYL:Print(
                "Archived "
                .. archivedSeason.name
                .. " with "
                .. #(archivedSeason.loot or {})
                .. " records."
            )

            SYL:Print(
                "New active season: "
                .. newSeason.name
            )

            currentMode = "active"
            selectedArchiveIndex = nil
            currentOffset = 0

            UpdateRows()
        end
    end,

    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()

        parent.button1:Click()
    end,

    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,

    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateMainWindow()
    if mainFrame then
        return mainFrame
    end

    mainFrame =
        CreateFrame(
            "Frame",
            "ShowUsYourLootMainFrame",
            UIParent,
            "BackdropTemplate"
        )

    mainFrame:SetSize(
        WINDOW_WIDTH,
        WINDOW_HEIGHT
    )

    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    mainFrame:SetScript(
        "OnDragStart",
        function(self)
            self:StartMoving()
        end
    )

    mainFrame:SetScript(
        "OnDragStop",
        function(self)
            self:StopMovingOrSizing()
        end
    )

    mainFrame:SetBackdrop({
        bgFile =
            "Interface\\DialogFrame\\UI-DialogBox-Background",

        edgeFile =
            "Interface\\DialogFrame\\UI-DialogBox-Border",

        tile = true,
        tileSize = 32,
        edgeSize = 32,

        insets = {
            left = 11,
            right = 12,
            top = 12,
            bottom = 11,
        },
    })

    mainFrame:SetBackdropColor(
        0,
        0,
        0,
        0.95
    )

    titleText =
        mainFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    titleText:SetPoint("TOP", 0, -16)
    titleText:SetText("Show Us Your Loot")

    subtitleText =
        mainFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    subtitleText:SetPoint("TOP", 0, -40)
    subtitleText:SetText("Active Season")

    countText =
        mainFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    countText:SetPoint(
        "TOPLEFT",
        22,
        -90
    )

    countText:SetText(
        "Recorded items: 0"
    )

    local closeButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelCloseButton"
        )

    closeButton:SetPoint(
        "TOPRIGHT",
        -5,
        -5
    )

    activeButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    activeButton:SetSize(120, 24)
    activeButton:SetPoint(
        "TOPLEFT",
        20,
        -58
    )

    activeButton:SetText("Active Season")

    activeButton:SetScript(
        "OnClick",
        function()
            currentMode = "active"
            selectedArchiveIndex = nil
            currentOffset = 0
            UpdateRows()
        end
    )

    allTimeButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    allTimeButton:SetSize(100, 24)
    allTimeButton:SetPoint(
        "LEFT",
        activeButton,
        "RIGHT",
        6,
        0
    )

    allTimeButton:SetText("All-Time")

    allTimeButton:SetScript(
        "OnClick",
        function()
            currentMode = "all"
            selectedArchiveIndex = nil
            currentOffset = 0
            UpdateRows()
        end
    )

    archivesButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    archivesButton:SetSize(100, 24)
    archivesButton:SetPoint(
        "LEFT",
        allTimeButton,
        "RIGHT",
        6,
        0
    )

    archivesButton:SetText("Archives")

    archivesButton:SetScript(
        "OnClick",
        function()
            currentMode = "archives"
            selectedArchiveIndex = nil
            currentOffset = 0
            UpdateRows()
        end
    )

    backButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    backButton:SetSize(115, 24)
    backButton:SetPoint(
        "TOPRIGHT",
        -20,
        -58
    )

    backButton:SetText("Back to Archives")

    backButton:SetScript(
        "OnClick",
        function()
            currentMode = "archives"
            selectedArchiveIndex = nil
            currentOffset = 0
            UpdateRows()
        end
    )

    archiveSeasonButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    archiveSeasonButton:SetSize(125, 24)
    archiveSeasonButton:SetPoint(
        "TOPRIGHT",
        -20,
        -86
    )

    archiveSeasonButton:SetText(
        "Archive Season"
    )

    archiveSeasonButton:SetScript(
        "OnClick",
        ShowArchivePopup
    )

    CreateLootHeader(mainFrame)

    scrollFrame =
        CreateFrame(
            "ScrollFrame",
            "ShowUsYourLootScrollFrame",
            mainFrame,
            "UIPanelScrollFrameTemplate"
        )

    scrollFrame:SetPoint(
        "TOPLEFT",
        18,
        -142
    )

    scrollFrame:SetPoint(
        "BOTTOMRIGHT",
        -38,
        58
    )

    scrollChild =
        CreateFrame(
            "Frame",
            nil,
            scrollFrame
        )

    scrollChild:SetWidth(
        WINDOW_WIDTH - 70
    )

    scrollChild:SetHeight(
        VISIBLE_ROWS * ROW_HEIGHT
    )

    scrollFrame:SetScrollChild(scrollChild)

    for index = 1, VISIBLE_ROWS do
        lootRows[index] =
            CreateLootRow(
                scrollChild,
                index
            )

        archiveRows[index] =
            CreateArchiveRow(
                scrollChild,
                index
            )
    end

    scrollFrame:EnableMouseWheel(true)

    scrollFrame:SetScript(
        "OnMouseWheel",
        function(self, delta)
            if currentMode == "archives" then
                return
            end

            local records =
                GetCurrentLootRecords()

            local maxOffset =
                math.max(
                    0,
                    #records - VISIBLE_ROWS
                )

            currentOffset =
                math.max(
                    0,
                    math.min(
                        maxOffset,
                        currentOffset - delta
                    )
                )

            UpdateRows()
        end
    )

    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetScript(
            "OnValueChanged",
            function(self, value)
                if currentMode
                    == "archives"
                then
                    return
                end

                local newOffset =
                    math.floor(
                        (
                            value
                            / ROW_HEIGHT
                        )
                        + 0.5
                    )

                if newOffset
                    ~= currentOffset
                then
                    currentOffset =
                        newOffset

                    UpdateRows()
                end
            end
        )
    end

    emptyText =
        mainFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontDisableLarge"
        )

    emptyText:SetPoint(
        "CENTER",
        0,
        -12
    )

    emptyText:SetText(
        "No loot has been recorded."
    )

    emptyText:Hide()

    local refreshButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    refreshButton:SetSize(110, 24)
    refreshButton:SetPoint(
        "BOTTOMLEFT",
        20,
        22
    )

    refreshButton:SetText("Refresh")

    refreshButton:SetScript(
        "OnClick",
        function()
            currentOffset = 0
            UpdateRows()
        end
    )

    local closeBottomButton =
        CreateFrame(
            "Button",
            nil,
            mainFrame,
            "UIPanelButtonTemplate"
        )

    closeBottomButton:SetSize(110, 24)
    closeBottomButton:SetPoint(
        "BOTTOMRIGHT",
        -20,
        22
    )

    closeBottomButton:SetText("Close")

    closeBottomButton:SetScript(
        "OnClick",
        function()
            mainFrame:Hide()
        end
    )

    mainFrame:SetScript(
        "OnShow",
        function()
            currentOffset = 0
            UpdateRows()
        end
    )

    mainFrame:Hide()

    return mainFrame
end

function SYL:OpenMainWindow()
    local frame = CreateMainWindow()

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function SYL:RefreshMainWindow()
    if mainFrame
        and mainFrame:IsShown()
    then
        UpdateRows()
    end
end

SYL:Print("UI ready.")