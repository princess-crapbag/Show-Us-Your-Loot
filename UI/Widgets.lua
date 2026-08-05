-- UI/Widgets.lua
--
-- Reusable frame builders. Nothing here knows which window it is being used
-- by, or what the current view mode is; callers pass in what they need.
--
-- Column geometry is defined once in COLUMNS and shared by both the header
-- and the rows, so the two can never drift out of alignment.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Widgets = {}
SYL.Widgets = Widgets

Widgets.ROW_HEIGHT = Theme.metrics.rowHeight
Widgets.ARCHIVE_ROW_HEIGHT = Theme.metrics.archiveRowHeight

local ICON_SIZE = Theme.metrics.iconSize
local ICON_TEXT_GAP = 22

local COLUMNS = {
    { key = "number", label = "#", width = 30, gap = 10 },
    { key = "player", label = "PLAYER", width = 140, gap = 8 },
    { key = "item", label = "ITEM", width = 250, gap = 10 },
    { key = "location", label = "LOCATION", width = 170, gap = 10 },
    { key = "date", label = "DATE", width = 110, gap = 10 },
}

local columnOffset = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        x = x + column.width
    end
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

function Widgets.CreatePanelButton(parent, width, height, text, onClick)
    return Theme.CreateButton(parent, width, height, text, onClick)
end

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local function AnchorRow(row, index, height)
    local offset = -((index - 1) * height)

    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", -20, offset)
end

local function AddRowBackgrounds(row, index)
    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()
end

local function PlaceInColumn(element, key, width)
    element:SetPoint("LEFT", columnOffset[key], 0)

    if width then
        element:SetWidth(width)
    end
end

-- Keeps the row highlight lit while the pointer is over a child control, so
-- moving onto an inner button does not flicker the row off.
function Widgets.LinkHoverToRow(child, row)
    child:HookScript("OnEnter", function()
        row.highlight:Show()
    end)

    child:HookScript("OnLeave", function()
        row.highlight:Hide()
    end)
end

-- The whole row is a single button: one mouse-interactive frame means hover,
-- tooltip and shift-click linking all behave consistently.
function Widgets.CreateLootRow(parent, index)
    local row = CreateFrame("Button", nil, parent)

    AnchorRow(row, index, Widgets.ROW_HEIGHT)
    AddRowBackgrounds(row, index)

    row.numberText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")

    PlaceInColumn(row.numberText, "number", COLUMNS[1].width)

    row.playerText =
        Theme.CreateText(row, Theme.sizes.row, "textPrimary")

    PlaceInColumn(row.playerText, "player", COLUMNS[2].width)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", columnOffset.item, 0)
    -- Trim the default icon border so it sits flat against the row.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:Hide()

    row.itemText = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.itemText:SetPoint("LEFT", columnOffset.item + ICON_TEXT_GAP, 0)
    row.itemText:SetWidth(COLUMNS[3].width - ICON_TEXT_GAP)

    row.locationText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")

    PlaceInColumn(row.locationText, "location", COLUMNS[4].width)

    row.dateText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")

    PlaceInColumn(row.dateText, "date", COLUMNS[5].width)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()

        if not self.itemLink then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self)
        if not self.itemLink then
            return
        end

        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)

    return row
end

-- Returns false when the item is not in the client cache yet, so the caller
-- can retry rather than leaving a wrongly coloured name on screen.
function Widgets.SetRowItem(row, itemLink, fallbackName)
    row.itemLink = itemLink

    if not itemLink then
        row.icon:Hide()
        row.itemText:SetText(fallbackName or "Unknown item")
        Theme.SetTextColor(row.itemText, "textSecondary")

        return true
    end

    local icon = Theme.GetItemIcon(itemLink)

    if icon then
        row.icon:SetTexture(icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end

    row.itemText:SetText(
        itemLink:match("%[(.-)%]") or fallbackName or itemLink
    )

    local color = Theme.GetItemQualityColor(itemLink)

    if not color then
        Theme.SetTextColor(row.itemText, "textPrimary")

        return false
    end

    row.itemText:SetTextColor(color[1], color[2], color[3])

    return true
end

function Widgets.CreateArchiveRow(parent, index, onView)
    local row = CreateFrame("Button", nil, parent)

    AnchorRow(row, index, Widgets.ARCHIVE_ROW_HEIGHT)
    AddRowBackgrounds(row, index)

    row.nameText = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.nameText:SetPoint("LEFT", 12, 0)
    row.nameText:SetWidth(300)

    row.countText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")

    row.countText:SetPoint("LEFT", row.nameText, "RIGHT", 12, 0)
    row.countText:SetWidth(110)

    row.dateText = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.dateText:SetPoint("LEFT", row.countText, "RIGHT", 12, 0)
    row.dateText:SetWidth(160)

    row.viewButton = Theme.CreateButton(row, 74, 22, "View", function(self)
        onView(self:GetParent().archiveIndex)
    end)

    row.viewButton:SetPoint("RIGHT", -10, 0)

    Widgets.LinkHoverToRow(row.viewButton, row)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", function(self)
        onView(self.archiveIndex)
    end)

    return row
end

--------------------------------------------------------------------------
-- Column header
--------------------------------------------------------------------------

function Widgets.CreateLootColumnHeader(parent)
    local header = CreateFrame("Frame", nil, parent)

    header:SetHeight(22)

    header.background =
        Theme.CreateSolidTexture(header, "headerBar", "BACKGROUND")

    header.background:SetAllPoints()

    local separator = Theme.CreateSeparator(header)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)

    for _, column in ipairs(COLUMNS) do
        local label =
            Theme.CreateText(header, Theme.sizes.columnHeader, "textMuted")

        label:SetPoint("LEFT", columnOffset[column.key], 0)
        label:SetWidth(column.width)
        label:SetText(column.label)
    end

    return header
end
