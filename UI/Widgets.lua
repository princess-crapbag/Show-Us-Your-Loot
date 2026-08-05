-- UI/Widgets.lua
--
-- Generic frame helpers that know nothing about loot. Row and column layout
-- lives in UI/Rows.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Widgets = {}
SYL.Widgets = Widgets

Widgets.ROW_HEIGHT = Theme.metrics.rowHeight
Widgets.ARCHIVE_ROW_HEIGHT = Theme.metrics.archiveRowHeight

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

function Widgets.AnchorRow(row, index, height)
    local offset = -((index - 1) * height)

    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", -20, offset)
end

-- Alternating row shading, kept subtle so it reads as banding rather than as
-- a selected row.
function Widgets.AddRowBackgrounds(row, index)
    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()
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
