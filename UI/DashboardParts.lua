-- UI/DashboardParts.lua
--
-- The pieces every dashboard tile is built from: a striped row, a
-- class-colored player row, the big number, the caption pinned to the bottom,
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

-- A line of "label ......... value". Returns the frame so a caller can color
-- either half without reaching back through the tile.
-- `noteText` is an optional third column, hard against the right edge, with
-- the value column giving way to it. Added for the loot feed, which needs to
-- say what somebody asked for as well as what they got -- three of five drops
-- on Aimee's 09/03 night were recorded Greed and credited Need, and a feed
-- that shows the item without the response cannot show that at all.
function DashboardParts.Row(tile, index, leftText, rightText, leftColor,
                            rightColor, noteText)
    local row = CreateFrame("Frame", nil, tile.body)

    row:SetHeight(ROW_HEIGHT)
    -- Rows start below whatever the tile put above them. A headline is a 15px
    -- font string whose descenders reach about 20px, and row 2 at -17 drew its
    -- stripe over the bottom of the big number — a child frame's BACKGROUND
    -- sits above the parent's OVERLAY, so the stripe won.
    local top = (tile.rowTop or 0) + (index - 1) * ROW_HEIGHT

    row:SetPoint("TOPLEFT", 0, -top)
    row:SetPoint("TOPRIGHT", 0, -top)

    if index % 2 == 0 then
        local stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        stripe:SetAllPoints()
    end

    local note

    if noteText and noteText ~= "" then
        note = Theme.CreateText(row, Theme.sizes.tiny, "textMuted")
        note:SetPoint("RIGHT", -3, 0)
        note:SetJustifyH("RIGHT")
        note:SetText(tostring(noteText))
    end

    local right = Theme.CreateText(row, Theme.sizes.rowSmall, rightColor or "textSecondary")

    if note then
        right:SetPoint("RIGHT", note, "LEFT", -6, 0)
    else
        right:SetPoint("RIGHT", -3, 0)
    end

    right:SetJustifyH("RIGHT")
    right:SetWordWrap(false)
    right:SetText(tostring(rightText or ""))

    local left = Theme.CreateText(row, Theme.sizes.rowSmall, leftColor or "textPrimary")
    left:SetPoint("LEFT", 3, 0)
    left:SetPoint("RIGHT", right, "LEFT", -6, 0)
    left:SetJustifyH("LEFT")
    left:SetWordWrap(false)
    left:SetText(tostring(leftText or ""))

    table.insert(tile.rows, row)

    return row, left, right, note
end

-- The class-colored version, for anything that names a player.
function DashboardParts.PlayerRow(tile, index, name, class, valueText,
                                 noteText, valueColor)
    local row, left = DashboardParts.Row(
        tile, index, name, valueText, "textPrimary", valueColor, noteText
    )

    -- THE ONE SITE WITH ITS OWN FALLBACK. Row above has already painted the
    -- name "textPrimary", so an unknown class must leave that standing rather
    -- than repaint it -- which is why ClassColor.Set returns whether it did
    -- anything, and why this is the only caller that looks at the answer.
    if not SYL.ClassColor.Get(class) then
        return row
    end

    SYL.ClassColor.Set(left, class)

    return row
end

-- The big number at the top of a tile.
function DashboardParts.Headline(tile, value, unit)
    local big = Theme.CreateText(tile.body, Theme.sizes.title, "textPrimary")
    big:SetPoint("TOPLEFT", 2, -2)
    big:SetText(tostring(value))

    -- Everything drawn after this starts below it, so callers can keep
    -- numbering their rows from one.
    tile.rowTop = 24

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

    -- ONE LINE, AND IT CANNOT GROW UPWARD.
    --
    -- This wrapped, and a caption pinned to the BOTTOM of a tile that wraps
    -- grows UP -- straight over the rows above it. RowCapacity holds back
    -- CAPTION_SPACE, which is one line, so a two- or three-line caption
    -- overlapped whatever was drawn last. Aimee found it on the due list:
    -- "only players marked as being on the raid team" is fifty characters in
    -- a tile 263 wide, so it took three lines and covered two raiders.
    --
    -- Wrapping off means a caption too long is cut rather than climbing.
    -- Neither is good and cut is far less bad -- it loses the tail of a
    -- sentence instead of hiding data behind it -- but the real defense is
    -- that every caption here is now measured in tools/test_layout.py.
    caption:SetWordWrap(false)
    caption:SetText(text)

    tile.caption = caption

    return caption
end

-- How many rows actually fit in this tile, right now.
--
-- Renderers used to draw a hardcoded six, which was right for the only tile
-- height that had ever existed. Row heights are computed from the space
-- available and shrink as soon as the grid needs another row, and a tile is
-- not a scroll frame — rows past the bottom are drawn outside the body rather
-- than clipped, so they land on whatever is underneath.
--
-- The caption is pinned to the bottom of the tile, so its space is held back
-- unless the caller says there will not be one.
local CAPTION_SPACE = 14

function DashboardParts.RowCapacity(tile, hasCaption)
    local height = tile.body and tile.body:GetHeight() or 0

    -- Before the first layout GetHeight is zero. Six is what the tall row fits
    -- and is what every renderer used to assume, so the first draw looks the
    -- same as it always did and the next one corrects it.
    if not height or height <= 1 then
        return 6
    end

    local usable = height
        - (tile.rowTop or 0)
        - (hasCaption == false and 0 or CAPTION_SPACE)

    return math.max(1, math.floor(usable / ROW_HEIGHT))
end

function DashboardParts.Empty(tile, text)
    local message = Theme.CreateText(tile.body, Theme.sizes.rowSmall, "textMuted")

    message:SetPoint("TOPLEFT", 2, -4)
    message:SetPoint("TOPRIGHT", -2, -4)
    message:SetJustifyH("LEFT")
    message:SetWordWrap(true)
    message:SetText(text)
end
