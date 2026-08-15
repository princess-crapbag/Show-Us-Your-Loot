-- UI/Rows.lua
--
-- Row and column layout for the list views.
--
-- Column geometry lives in UI/Columns.lua and is shared by both
-- the header and the rows, so the two can never drift out of alignment.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Columns = SYL.Columns
local Widgets = SYL.Widgets

local Rows = {}
SYL.Rows = Rows

local ICON_SIZE = Theme.metrics.iconSize
local ICON_TEXT_GAP = 22

-- Width comes from the column definition, never from the caller.
--
-- It used to be a parameter, and every call site carried a literal that was
-- correct when it was written. The definitions were then retuned twice and
-- the literals were not, so the headers moved and the text under them did
-- not: the date column was widened while its text stayed clamped to an older
-- number and kept its ellipsis. Reading the width from one place is the only
-- version of this that cannot drift.
local function PlaceInColumn(element, setKey, key)
    element:SetPoint("LEFT", Columns.Offset(setKey, key), 0)

    local width = Columns.Width(setKey, key)

    if width then
        element:SetWidth(width)
    end
end

--------------------------------------------------------------------------
-- Item cell
--------------------------------------------------------------------------

local function AddItemCell(row, setKey)
    local left = Columns.Offset(setKey, "item")
    local width = Columns.Width(setKey, "item")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", left, 0)
    -- Trim the default icon border so it sits flat against the row.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:Hide()

    row.itemText = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.itemText:SetPoint("LEFT", left + ICON_TEXT_GAP, 0)
    row.itemText:SetWidth(width - ICON_TEXT_GAP)
end

-- Returns false when the item is not in the client cache yet, so the caller
-- can retry rather than leaving a wrongly colored name on screen.
function Rows.SetRowItem(row, itemLink, fallbackName)
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

    Theme.SetCustomTextColor(row.itemText, color[1], color[2], color[3])

    return true
end

--------------------------------------------------------------------------
-- Selection cell
--------------------------------------------------------------------------

-- The checkbox is a separate button so that shift-clicking the row body can
-- keep its normal meaning of linking the item into chat. Shift on the
-- checkbox extends a range instead.
local function AddSelectCell(row, setKey, onSelect)
    local box = CreateFrame("Button", nil, row)

    box:SetSize(14, 14)
    box:SetPoint("LEFT", Columns.Offset(setKey, "select"), 0)

    box.edge = Theme.CreateSolidTexture(box, "border", "BACKGROUND")
    box.edge:SetAllPoints()

    box.fill = Theme.CreateSolidTexture(box, "window", "ARTWORK")
    box.fill:SetPoint("TOPLEFT", 1, -1)
    box.fill:SetPoint("BOTTOMRIGHT", -1, 1)

    box.tick = Theme.CreateSolidTexture(box, "accent", "OVERLAY")
    box.tick:SetSize(8, 8)
    box.tick:SetPoint("CENTER")
    box.tick:Hide()

    box:SetScript("OnClick", function()
        onSelect(row, IsShiftKeyDown())
    end)

    Widgets.LinkHoverToRow(box, row)

    row.selectBox = box

    row.selectedTint = Theme.CreateSolidTexture(row, "accentMuted", "BORDER")
    row.selectedTint:SetAllPoints()
    row.selectedTint:Hide()
end

function Rows.SetRowSelected(row, selected)
    if not row.selectBox then
        return
    end

    if selected then
        row.selectBox.tick:Show()
        row.selectedTint:Show()
    else
        row.selectBox.tick:Hide()
        row.selectedTint:Hide()
    end
end

-- Hidden rows stay legible but visibly set aside, so "Show hidden" reads as a
-- different state rather than as a broken list.
function Rows.SetRowHidden(row, hidden)
    row:SetAlpha(hidden and 0.45 or 1)
end

-- Ignored rows stay in the list and stop counting, and have to look like it.
--
-- A flag that changes every number the addon reports and leaves no mark on
-- screen is the worst of both: the list and the maths disagree and nothing
-- says why. Dimming alone would not do — that is what hidden looks like, and
-- the two are different states. The type cell carries it, because that is the
-- column that already answers "what is this row".
function Rows.SetRowIgnored(row, ignored)
    if not row.typeText then
        return
    end

    if ignored then
        row:SetAlpha(0.55)
        Theme.SetTextColor(row.typeText, "warning")
        row.typeText:SetText("ignored")
    end
end

--------------------------------------------------------------------------
-- Shared row behavior
--------------------------------------------------------------------------

-- The whole row is a single button: one mouse-interactive frame means hover,
-- tooltip and shift-click linking all behave consistently.
local function AttachItemRowScripts(row)
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

    -- Shift-click keeps its usual meaning of linking the item. A plain click
    -- opens the row's detail, where a view provides one.
    row:SetScript("OnClick", function(self)
        if self.itemLink and IsModifiedClick("CHATLINK") then
            -- Normalized on the way out rather than on the way in, so
            -- records captured before the color wrapper was kept still
            -- paste a usable link.
            ChatEdit_InsertLink(
                SYL.Utilities.NormalizeItemLink(self.itemLink)
            )

            return
        end

        if self.onActivate and self.record then
            self.onActivate(self.record)
        end
    end)
end

--------------------------------------------------------------------------
-- Row builders
--------------------------------------------------------------------------

-- The merged list's row. Shaped like the drop row because it has to hold
-- both kinds of record: a rolled item shows its type and opens its roll
-- list, an awarded one shows how it arrived and opens a detail window that
-- says there was no roll.
function Rows.CreateFeedRow(parent, index, onSelect, onActivate)
    local row = CreateFrame("Button", nil, parent)

    row.onActivate = onActivate

    Widgets.AnchorRow(row, index, Widgets.ROW_HEIGHT)
    Widgets.AddRowBackgrounds(row, index)
    AddSelectCell(row, "feed", onSelect)

    row.numberText = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    PlaceInColumn(row.numberText, "feed", "number")

    row.playerText = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    PlaceInColumn(row.playerText, "feed", "player")

    AddItemCell(row, "feed")

    row.typeText = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    PlaceInColumn(row.typeText, "feed", "wintype")

    row.locationText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")

    PlaceInColumn(row.locationText, "feed", "location")

    row.dateText = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    PlaceInColumn(row.dateText, "feed", "date")

    AttachItemRowScripts(row)

    return row
end

function Rows.CreateArchiveRow(parent, index, onView, onSelect)
    local row = CreateFrame("Button", nil, parent)

    Widgets.AnchorRow(row, index, Widgets.ARCHIVE_ROW_HEIGHT)
    Widgets.AddRowBackgrounds(row, index)

    -- Its own button, for the same reason the loot rows' is: clicking the row
    -- body opens the season, and a tick that shared that click would mean
    -- selecting one always opened it too.
    local box = CreateFrame("Button", nil, row)

    box:SetSize(14, 14)
    box:SetPoint("LEFT", 12, 0)

    box.edge = Theme.CreateSolidTexture(box, "border", "BACKGROUND")
    box.edge:SetAllPoints()

    box.fill = Theme.CreateSolidTexture(box, "window", "ARTWORK")
    box.fill:SetPoint("TOPLEFT", 1, -1)
    box.fill:SetPoint("BOTTOMRIGHT", -1, 1)

    box.tick = Theme.CreateSolidTexture(box, "accent", "OVERLAY")
    box.tick:SetSize(8, 8)
    box.tick:SetPoint("CENTER")
    box.tick:Hide()

    box:SetScript("OnClick", function()
        if onSelect then
            onSelect(row.archiveIndex)
        end
    end)

    Widgets.LinkHoverToRow(box, row)

    row.selectBox = box

    row.nameText = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.nameText:SetPoint("LEFT", 34, 0)
    row.nameText:SetWidth(280)

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
