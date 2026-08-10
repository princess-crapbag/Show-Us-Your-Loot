-- UI/DashboardParts.lua
--
-- The pieces every dashboard tile is built from: a striped row, a
-- class-coloured player row, the big number, the caption pinned to the bottom,
-- and the "nothing yet" message.
--
-- Split from UI/DashboardWidgets.lua, which holds one renderer per widget.
-- That file decides what a tile says; this one decides what a tile is made of,
-- so a new widget is a renderer rather than another copy of these five.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local DashboardParts = {}
SYL.DashboardParts = DashboardParts

local ROW_HEIGHT = 17

--------------------------------------------------------------------------
-- Small builders, shared by the renderers
--------------------------------------------------------------------------

-- A line of "label ......... value". Returns the frame so a caller can colour
-- either half without reaching back through the tile.
function DashboardParts.Row(tile, index, leftText, rightText, leftColor, rightColor)
    local row = CreateFrame("Frame", nil, tile.body)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    if index % 2 == 0 then
        local stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        stripe:SetAllPoints()
    end

    local right = Theme.CreateText(row, Theme.sizes.rowSmall, rightColor or "textSecondary")
    right:SetPoint("RIGHT", -3, 0)
    right:SetJustifyH("RIGHT")
    right:SetText(tostring(rightText or ""))

    local left = Theme.CreateText(row, Theme.sizes.rowSmall, leftColor or "textPrimary")
    left:SetPoint("LEFT", 3, 0)
    left:SetPoint("RIGHT", right, "LEFT", -6, 0)
    left:SetJustifyH("LEFT")
    left:SetWordWrap(false)
    left:SetText(tostring(leftText or ""))

    table.insert(tile.rows, row)

    return row, left, right
end

-- The class-coloured version, for anything that names a player.
function DashboardParts.PlayerRow(tile, index, name, class, valueText, valueColor)
    local row, left = DashboardParts.Row(tile, index, name, valueText, "textPrimary", valueColor)

    local color = Theme.GetClassColor(class)

    if color then
        Theme.SetCustomTextColor(left, color[1], color[2], color[3])
    end

    return row
end

-- The big number at the top of a tile.
function DashboardParts.Headline(tile, value, unit)
    local big = Theme.CreateText(tile.body, Theme.sizes.title, "textPrimary")
    big:SetPoint("TOPLEFT", 2, -2)
    big:SetText(tostring(value))

    if unit then
        local small = Theme.CreateText(tile.body, Theme.sizes.rowSmall, "textMuted")
        small:SetPoint("LEFT", big, "RIGHT", 5, -1)
        small:SetText(unit)
    end

    return big
end

-- The muted sentence pinned to the bottom of every tile. Always last, always
-- says what the numbers above it are counting.
function DashboardParts.Caption(tile, text, colorKey)
    local caption = Theme.CreateText(
        tile.body, Theme.sizes.rowSmall, colorKey or "textMuted"
    )

    caption:SetPoint("BOTTOMLEFT", 2, 1)
    caption:SetPoint("BOTTOMRIGHT", -2, 1)
    caption:SetJustifyH("LEFT")
    caption:SetWordWrap(true)
    caption:SetText(text)

    tile.caption = caption

    return caption
end

function DashboardParts.Empty(tile, text)
    local message = Theme.CreateText(tile.body, Theme.sizes.rowSmall, "textMuted")

    message:SetPoint("TOPLEFT", 2, -4)
    message:SetPoint("TOPRIGHT", -2, -4)
    message:SetJustifyH("LEFT")
    message:SetWordWrap(true)
    message:SetText(text)
end
