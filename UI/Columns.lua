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
        -- Neither of these two is a value. SELECT is a tickbox with no label
        -- to click, and # is the row's position on screen, which is the
        -- result of the sort rather than something to sort by.
        { key = "select", label = "", width = 16, gap = 8, sortable = false },
        { key = "number", label = "#", width = 30, gap = 8, sortable = false },
        { key = "player", label = "PLAYER", width = 130, gap = 8 },

        -- ITEM PAID FOR THE DIFFICULTY COLUMN and was then measured at the
        -- wrong size. This comment used to read "Skullguard of the Risen
        -- Sacrifice measures 166.5" -- which is its width at rowSmall (11),
        -- and UI/Rows.lua draws this cell at Theme.sizes.row (12), where the
        -- same string is 181. The column was budgeted 8px short of the one
        -- name it was budgeted from.
        --
        -- MEASURED AGAINST HER ACTUAL DATABASE this time, all 454 distinct
        -- item names, at size 12, with the |A:...|a quality-tier escapes
        -- stripped -- those render as an icon and only count as text to a
        -- measuring script:
        --
        --   Triumphant Satchel of Champion Dawncrests   254.5  <- the longest
        --   Tarnished Dawnlit Sentinel's Handguards     232.0
        --   Venomous Aspirant's Insignia of Alacrity    229.5
        --
        -- 240 gives a 199px text box after FitDateColumn and the icon, which
        -- clips 16 of 454 names -- 3.5%, all of them satchels and enchants
        -- rather than gear. Fitting the true longest needs 281, and the row
        -- does not have 41 spare pixels to give: WHERE is already 4.5 short
        -- of "Liberation of Undermine" and PLAYER is already short of
        -- "Whitemoonlight-Proudmoore". Hovering any row shows the full item
        -- tooltip, so the tail is one hover away rather than lost.
        --
        -- This is the same place FitDateColumn below takes its shortfall
        -- from, and for the same reason.
        --
        -- THE BUDGET IS 830, NOT 868. The drawing this was designed from
        -- measured against the window less its 16px insets; the scroll frame
        -- is WINDOW_WIDTH - 70, because the scrollbar takes the rest.
        -- tools/syl_check.py enforces it and caught the 16px overrun.
        { key = "item", label = "ITEM", width = 240, gap = 10 },

        -- 56, not 76. The widest value this column can hold is "Bonus roll"
        -- at 52, and the header's own caret and arrow end at 44.5, so the 20
        -- it gives up were never reachable. Not 52: exactly flush IS the
        -- truncation boundary.
        { key = "wintype", label = "TYPE", width = 56, gap = 8 },

        -- WHERE NEVER NEEDED 150. "The Tidebound Grotto" is the longest
        -- instance name in her seasons at 116.
        { key = "location", label = "WHERE", width = 122, gap = 6 },

        -- SPELLED OUT, which is Aimee's: "i wonder if we should put
        -- Difficulty and spell the raid difficulty out. LFR, Normal, Heroic,
        -- Mythic."
        --
        -- 72 is set by the HEADER, not by the values: "DIFFICULTY" measures
        -- 55 and the longest value, "Normal", only 38.5 -- and the filter
        -- caret sits after the name, so the column needs 55 + 4 + 8. Drawn at
        -- 58 first and the caret ran into DATE.
        --
        -- It used to be printed on the end of the WHERE cell, so the row is
        -- no wider than it was and the letter is now scannable down a column
        -- and filterable from a header of its own.
        { key = "difficulty", label = "DIFFICULTY", width = 72, gap = 10 },

        -- NO CARET ON THIS ONE, because it could never work. A filter
        -- dropdown is built from FilterOptions.Derive, which reads the field
        -- out of UI/ListSources.lua's FEED_FIELDS -- and that table has a
        -- `timestamp` reader and no `date` reader, so every record answers
        -- nil and the panel is always empty. Core/Filters.lua's LABELS has no
        -- `date` key either, so it opened untitled as well.
        --
        -- Date narrowing is the From and To boxes on the filter bar, which
        -- work. A caret here would have to be a RANGE control, not a list of
        -- ticks, and that is a feature rather than a flag.
        --
        -- filterable goes AFTER gap: tools/syl_check.py's column regex reads
        -- key, label, width, gap in that order and silently stops checking
        -- the whole set if something is spliced in ahead of it.
        { key = "date", label = "DATE", width = 96, gap = 10, filterable = false },
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
-- WIDENED FOR THE 12 HOUR CLOCK. " PM" is three characters the 24 hour
-- version did not need, and the column is measured from this string rather
-- than guessed -- see Theme.MeasureText and the note in
-- Utilities.FormatDateCompact.
local WIDEST_DATE = "00/00/00 00:00 PM"
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
