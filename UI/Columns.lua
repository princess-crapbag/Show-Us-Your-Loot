-- UI/Columns.lua
--
-- Column geometry for the main window's lists: what each column is, how wide,
-- and where it starts. Split out of Rows.lua, which had reached the size
-- limit and was doing two jobs — deciding the layout and building the
-- widgets that sit in it.
--
-- Nothing here draws anything.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Columns = {}
SYL.Columns = Columns

-- Widths and gaps must total no more than 830: the scroll child is created as
-- WINDOW_WIDTH - 70 in MainWindow, and rows are laid out from its left edge.
-- tools/syl_check.py enforces the total, because getting it wrong truncates
-- silently — the text simply ends in an ellipsis, which reads as a styling
-- choice rather than as a column that was never given room.
--
-- Sizing is driven by the longest realistic value, not by the header:
-- "Leggings of the Devouring Advance" for an item, "Sagedin-Proudmoore" for a
-- name, "08/05/26 12:32" for a date. Two changes bought most of the room
-- back — difficulty is abbreviated, so locations read "The Voidspire - LFR",
-- and the date lost its " PM".
--
-- ITEM is the column that gets the surplus. It holds the longest values, and
-- it is also the one worth reading: a truncated player name is still
-- recognisable, a truncated item name often is not. The detail window is
-- where the full name always shows.
local COLUMN_SETS = {
    -- The merged list: everything anybody received, rolled or awarded. TYPE
    -- carries what the two old tabs used to say by being separate tabs, and
    -- says it per row instead — which is the only way a single list can hold
    -- both without losing the distinction.
    feed = {
        { key = "select", label = "", width = 16, gap = 8 },
        { key = "number", label = "#", width = 30, gap = 8 },
        { key = "player", label = "PLAYER", width = 130, gap = 8 },
        { key = "item", label = "ITEM", width = 250, gap = 10 },
        { key = "wintype", label = "TYPE", width = 76, gap = 8 },
        { key = "location", label = "WHERE", width = 150, gap = 10 },
        { key = "date", label = "DATE", width = 96, gap = 10 },
    },
}

-- The date has been cut off twice now, both times because its width was
-- reasoned about rather than measured. Estimating characters times pixels is
-- wrong by enough to matter, and by a different amount per font and locale.
--
-- So it is measured at load against the widest date that can appear, and any
-- shortfall is taken from ITEM, which is the column with room to give.
-- Totals stay exactly as they were, which keeps the layout inside the
-- budget tools/syl_check.py enforces.
local WIDEST_DATE = "00/00/00 00:00"
local DATE_PADDING = 10

local function FitDateColumn(columns)
    local needed = Theme.MeasureText(Theme.sizes.rowSmall, WIDEST_DATE)
        + DATE_PADDING

    local date, item

    for _, column in ipairs(columns) do
        if column.key == "date" then
            date = column
        elseif column.key == "item" then
            item = column
        end
    end

    if not date or not item or needed <= date.width then
        return
    end

    local shortfall = needed - date.width

    -- Never starve the item column to feed the date. If it cannot give the
    -- space, the date takes what there is and the rest stays as it was;
    -- a clipped date beats an item name clipped to nothing.
    local available = math.max(0, item.width - 120)
    local moved = math.min(shortfall, available)

    date.width = date.width + moved
    item.width = item.width - moved
end

for _, columns in pairs(COLUMN_SETS) do
    FitDateColumn(columns)
end

local offsets = {}

for setKey, columns in pairs(COLUMN_SETS) do
    local x = 0

    offsets[setKey] = {}

    for _, column in ipairs(columns) do
        x = x + column.gap
        offsets[setKey][column.key] = x
        x = x + column.width
    end
end

Columns.SETS = COLUMN_SETS
Columns.offsets = offsets

function Columns.Get(setKey)
    return COLUMN_SETS[setKey]
end

function Columns.Offset(setKey, key)
    return offsets[setKey][key]
end

function Columns.Width(setKey, key)
    for _, column in ipairs(COLUMN_SETS[setKey] or {}) do
        if column.key == key then
            return column.width
        end
    end

    return nil
end
