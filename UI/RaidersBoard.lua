-- UI/RaidersBoard.lua
--
-- The Raiders board: what the columns are, how wide each one is, and how a
-- single row is drawn. Split out of UI/RaidersPanel.lua, which was carrying
-- two jobs at once -- the panel around the board (scope, scrolling, the detail
-- pane) and the board itself -- and had grown past the size where either could
-- be read without the other in the way.
--
-- STILL NOT A TABLE, AND THE HEADINGS DO NOT MAKE IT ONE. The header of
-- UI/RaidersPanel.lua is emphatic about why the bars are the point and it
-- stands. What the headings fix is a different complaint, in Aimee's words:
-- "the info is starting to get a little messy." Four numbers sat in a row with
-- nothing naming them, so you had to remember which was which. Naming a column
-- is not the same as asking somebody to read down it -- the bar still answers
-- the question, and the numbers are now checkable rather than cryptic.
--
-- EVERY WIDTH HERE IS MEASURED, NEVER ESTIMATED. Too wide is a defect as much
-- as too narrow: every pixel a number does not need is a pixel taken off the
-- bar, and the bar is what the screen exists for. See Theme.MeasureText and
-- UI/KeyRows.lua for the same rule applied to the same font.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersBoard = {}
SYL.RaidersBoard = RaidersBoard

RaidersBoard.ROW_HEIGHT = 22

-- Two heading lines and the rule under them. The lines are stacked rather than
-- set side by side because "POINTS PER NIGHT" on one line is 90px and the
-- column beneath it holds "4.2" -- the heading would have set the width of the
-- whole block, and four of those is the bar gone.
RaidersBoard.HEADER_HEIGHT = 33

local ROW_SIZE = Theme.sizes.rowSmall
local HEAD_SIZE = Theme.sizes.columnHeader

-- Aimee, choosing this from three samples: the gap she liked between RAID
-- NIGHTS and POINTS PER NIGHT, used between every column and again as the
-- inset before the first name so the names are not against the edge.
local GAP = 14
local LEFT_INSET = GAP

-- The widest name in her 595-player registry, which is also twelve characters
-- -- the most a WoW name can be. Given ten percent more, as she asked, so a
-- wider one still has somewhere to sit. Declared as the string rather than as
-- a number so it is re-measured if the font ever changes.
local WIDEST_NAME = "Shadowdancez"
local NAME_HEADROOM = 1.10

-- Nothing, half, all. Three marks is a scale; more is a grid, which is the
-- table this screen refuses to be.
local SCALE_MARKS = { 0, 0.5, 1 }

-- Published for UI/RaidersBoardRows.lua, which draws against them. Two
-- copies of a measurement is how two files come to disagree about where a bar
-- starts.
RaidersBoard.BAR_HEIGHT = 5
RaidersBoard.BAR_INSET = 9

-- WOW'S OWN QUALITY COLORS, not invented ones. A raider reading this board has
-- seen rare blue and epic purple on every item they have ever looted, so the
-- bar needs no legend to say which half of it was Heroic.
--
-- Set with SetColorTexture directly rather than through Theme.CreateSolidTexture,
-- for the same reason item quality and class colors go through
-- Theme.SetCustomTextColor: these are not the theme's to repaint. Nightfall or
-- daylight, epic is still purple.
-- BY DIFFICULTY ID. The name is for reading, never for matching -- see the
-- comment on byTrack in Core/LootScore.lua for what keying on the name cost.
RaidersBoard.TRACKS = {
    { id = 14, name = "Normal", color = { 0.000, 0.439, 0.867 } },
    { id = 15, name = "Heroic", color = { 0.639, 0.208, 0.933 } },
    { id = 16, name = "Mythic", color = { 1.000, 0.502, 0.000 } },
}

-- Anything the three tracks above do not account for -- Looking For Raid, a
-- timewalking id, an old ten or twenty-five player raid -- still has to be
-- drawn, or the bar would be shorter than the total printed beside it, which
-- is the one thing a bar must never be.
RaidersBoard.UNKNOWN_COLOR = { 0.55, 0.85, 1.00 }

RaidersBoard.EMPTY = "—"

-- The four right-hand columns, in Aimee's order and with her titles.
--
-- `widest` is what the column has to be able to hold, not what today's data
-- happens to contain: five figures of points, ninety-nine raid nights. A
-- column measured against live data is a column that changes width when
-- somebody has a good week.
RaidersBoard.COLUMNS = {
    {
        top = "# ITEMS",
        bottom = "RECEIVED",
        widest = "999",

        -- Need and greed only. Transmog is excluded on purpose -- see
        -- LootScore's scoringWins, and Aimee's "we should not include mogs in
        -- this number."
        value = function(entry)
            local taken = entry.scoringWins or 0

            return taken > 0 and string.format("%d", taken) or RaidersBoard.EMPTY
        end,
    },
    {
        top = "RAID",
        bottom = "NIGHTS",
        widest = "99 of 99",

        -- Attended of held, both counted the same way: guild nights only, one
        -- evening being one night however many bosses or difficulties it
        -- passed through. Hers reads 2 of 2, Saebie's 1 of 2.
        value = function(entry, view)
            return string.format(
                "%d of %d", entry.nights or 0, view.nightsHeld or 0
            )
        end,
    },
    {
        top = "POINTS",
        bottom = "PER NIGHT",
        widest = "9999.9",

        -- The number the bar is a picture of. A dash rather than a reason:
        -- the reason does not fit a 53px column and never did, so it moved to
        -- the row's tooltip where there is room to say it properly.
        value = function(entry)
            if not entry.ranked then
                return RaidersBoard.EMPTY
            end

            return string.format("%.1f", entry.share or 0)
        end,
    },
    {
        top = "TOTAL",
        bottom = "POINTS",
        widest = "99999",

        value = function(entry)
            local score = entry.lootScore or 0

            return score > 0 and string.format("%d", score) or RaidersBoard.EMPTY
        end,
    },
}

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

-- Runs once, from the panel's Create, because Theme.MeasureText needs a live
-- client to measure against -- the same reason UI/KeyRows.lua and
-- UI/Columns.lua measure inside a function rather than at file scope.
function RaidersBoard.Measure(width)
    local shared = 0

    for _, column in ipairs(RaidersBoard.COLUMNS) do
        shared = math.max(
            shared,
            Theme.MeasureText(HEAD_SIZE, column.top),
            Theme.MeasureText(HEAD_SIZE, column.bottom),
            Theme.MeasureText(ROW_SIZE, column.widest)
        )
    end

    -- ONE WIDTH FOR ALL FOUR, which is what Aimee asked for and is also what
    -- makes them scannable: four columns of different widths read as four
    -- unrelated numbers, and the whole point of putting them side by side is
    -- that they are comparable.
    local count = #RaidersBoard.COLUMNS
    local block = count * shared + (count - 1) * GAP

    -- A full character space after the last number, measured in the row's own
    -- font so the padding matches the text rather than approximating it.
    local space = Theme.MeasureText(ROW_SIZE, " ")

    local layout = {
        width = width,
        gap = GAP,
        space = space,
        left = LEFT_INSET,
        column = shared,
        name = Theme.MeasureText(ROW_SIZE, WIDEST_NAME) * NAME_HEADROOM,
    }

    layout.numbers = width - space - block
    layout.bar = layout.left + layout.name + GAP

    -- The bar takes what is left. It is the only elastic thing on the row, so
    -- every measurement above is a claim on it and has to earn its pixels.
    layout.barWidth = layout.numbers - GAP - layout.bar

    RaidersBoard.layout = layout

    return layout
end

function RaidersBoard.ColumnX(index)
    local layout = RaidersBoard.layout

    return layout.numbers + (index - 1) * (layout.column + layout.gap)
end

--------------------------------------------------------------------------
-- The heading row
--------------------------------------------------------------------------

-- The bar is a column too and wants naming like the rest, but it is the one
-- thing on the row Aimee's list did not title -- it had never needed one,
-- being the only bar on screen. With four named columns beside it the unnamed
-- one starts to look like a decoration, so it says what it measures.
local BAR_HEADING = "PER NIGHT, AGAINST THE RAID AVERAGE"

function RaidersBoard.CreateHeader(parent, top)
    local layout = RaidersBoard.layout
    local header = { parts = {} }

    local function Heading(text, x, line)
        local fontString = Theme.CreateText(parent, HEAD_SIZE, "textMuted")

        fontString:SetPoint("TOPLEFT", x, -(top + line))
        fontString:SetJustifyH("LEFT")
        fontString:SetWordWrap(false)
        fontString:SetText(text)

        header.parts[#header.parts + 1] = fontString

        return fontString
    end

    -- RAIDER and the bar heading sit on the lower line, level with the second
    -- word of the stacked headings rather than floating above them.
    Heading("RAIDER", layout.left, 11)
    Heading(BAR_HEADING, layout.bar, 11)

    for index, column in ipairs(RaidersBoard.COLUMNS) do
        local x = RaidersBoard.ColumnX(index)

        Heading(column.top, x, 0)
        Heading(column.bottom, x, 11)
    end

    header.rule = Theme.CreateSolidTexture(parent, "separator", "ARTWORK")
    header.rule:SetPoint("TOPLEFT", 0, -(top + 26))
    header.rule:SetSize(layout.width, 1)

    -- Nothing, half, all -- so a bar can be read as a proportion without
    -- counting pixels against the one below it. Drawn once above the first
    -- row rather than repeated down the board, which is the difference
    -- between a scale and a grid.
    header.ticks = {}

    for index, mark in ipairs(SCALE_MARKS) do
        local tick = Theme.CreateSolidTexture(parent, "separator", "ARTWORK")

        tick:SetPoint("TOPLEFT", layout.bar + mark * layout.barWidth, -(top + 28))
        tick:SetSize(1, 3)

        header.ticks[index] = tick
    end

    return header
end

-- The roster view shares this strip of the panel and has no headings of its
-- own, so the board's have to stand down rather than sit over its first two
-- rows. Same when the board is empty: headings above nothing name columns that
-- are not there, which reads as a list that failed to load.
function RaidersBoard.SetHeaderShown(header, shown)
    if not header then
        return
    end

    for _, part in ipairs(header.parts) do
        part:SetShown(shown)
    end

    for _, tick in ipairs(header.ticks) do
        tick:SetShown(shown)
    end

    header.rule:SetShown(shown)
end
