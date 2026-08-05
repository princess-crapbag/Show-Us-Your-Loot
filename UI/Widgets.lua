-- UI/Widgets.lua
--
-- Reusable frame builders. Nothing here knows which window it is being used
-- by, or what the current view mode is; callers pass in what they need.

local SYL = _G.ShowUsYourLoot

local Widgets = {}
SYL.Widgets = Widgets

Widgets.ROW_HEIGHT = 25
Widgets.ARCHIVE_ROW_HEIGHT = 36

local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",

    tile = true,
    tileSize = 32,
    edgeSize = 32,

    insets = {
        left = 11,
        right = 12,
        top = 12,
        bottom = 11,
    },
}

function Widgets.ApplyDialogBackdrop(frame)
    frame:SetBackdrop(DIALOG_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.95)
end

function Widgets.MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
end

function Widgets.SetButtonSelected(button, selected)
    if selected then
        button:Disable()
    else
        button:Enable()
    end
end

function Widgets.CreatePanelButton(parent, width, height, text, onClick)
    local button =
        CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")

    button:SetSize(width, height)
    button:SetText(text)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    return button
end

-- Alternating row shading. Kept subtle so it reads as banding rather than
-- as a selected row.
local function ApplyRowStriping(row, index)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()

    if index % 2 == 0 then
        row.background:SetColorTexture(1, 1, 1, 0.035)
    else
        row.background:SetColorTexture(0, 0, 0, 0)
    end
end

local function AnchorRow(row, index, height)
    local offset = -((index - 1) * height)

    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", -20, offset)
end

local function CreateRowText(row, template, width, anchorTo)
    local text = row:CreateFontString(nil, "OVERLAY", template)

    if anchorTo then
        text:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
    else
        text:SetPoint("LEFT", 6, 0)
    end

    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    return text
end

-- The item cell is a button so it can own a tooltip and shift-click linking.
-- Scripts are attached once here; refreshes only swap the stored link.
local function CreateItemButton(row, anchorTo, width)
    local button = CreateFrame("Button", nil, row)

    button:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
    button:SetSize(width, Widgets.ROW_HEIGHT)

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

    button.text =
        button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    button.text:SetAllPoints()
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)

    return button
end

function Widgets.SetItemLink(button, itemLink)
    button.itemLink = itemLink
end

function Widgets.CreateLootRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    AnchorRow(row, index, Widgets.ROW_HEIGHT)
    ApplyRowStriping(row, index)

    row.numberText =
        CreateRowText(row, "GameFontHighlightSmall", 38)

    -- The number column sits tight against the player column.
    row.playerText =
        row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    row.playerText:SetPoint("LEFT", row.numberText, "RIGHT", 4, 0)
    row.playerText:SetWidth(155)
    row.playerText:SetJustifyH("LEFT")
    row.playerText:SetWordWrap(false)

    row.itemButton = CreateItemButton(row, row.playerText, 255)
    row.itemText = row.itemButton.text

    row.locationText =
        CreateRowText(row, "GameFontDisableSmall", 190, row.itemButton)

    row.dateText =
        CreateRowText(row, "GameFontDisableSmall", 125, row.locationText)

    return row
end

function Widgets.CreateArchiveRow(parent, index, onView)
    local row = CreateFrame("Frame", nil, parent)

    AnchorRow(row, index, Widgets.ARCHIVE_ROW_HEIGHT)
    ApplyRowStriping(row, index)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetPoint("LEFT", 12, 0)
    row.nameText:SetWidth(310)
    row.nameText:SetJustifyH("LEFT")

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.countText:SetPoint("LEFT", row.nameText, "RIGHT", 12, 0)
    row.countText:SetWidth(120)
    row.countText:SetJustifyH("LEFT")

    row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.dateText:SetPoint("LEFT", row.countText, "RIGHT", 12, 0)
    row.dateText:SetWidth(170)
    row.dateText:SetJustifyH("LEFT")

    row.viewButton =
        Widgets.CreatePanelButton(row, 85, 22, "View", function(self)
            onView(self.archiveIndex)
        end)

    row.viewButton:SetPoint("RIGHT", -8, 0)

    return row
end

local LOOT_COLUMNS = {
    { text = "#", width = 38, gap = 6 },
    { text = "Player", width = 155, gap = 4 },
    { text = "Item", width = 255, gap = 8 },
    { text = "Location", width = 190, gap = 8 },
    { text = "Date", width = 125, gap = 8 },
}

function Widgets.CreateLootColumnHeader(parent)
    local header = CreateFrame("Frame", nil, parent)

    header:SetHeight(24)
    header:SetPoint("TOPLEFT", 18, -116)
    header:SetPoint("TOPRIGHT", -38, -116)

    local previous

    for _, column in ipairs(LOOT_COLUMNS) do
        local label =
            header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

        if previous then
            label:SetPoint("LEFT", previous, "RIGHT", column.gap, 0)
        else
            label:SetPoint("LEFT", column.gap, 0)
        end

        label:SetWidth(column.width)
        label:SetText(column.text)
        label:SetJustifyH("LEFT")

        previous = label
    end

    return header
end
