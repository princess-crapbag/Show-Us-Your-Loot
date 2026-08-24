-- UI/RaidersSort.lua
--
-- Ordering the Raiders board, and the controls that do it.
--
-- Aimee: "id like to be able to sort by each column."
--
-- SPLIT OUT because both files it came from crossed the size limit carrying
-- it, and because it is genuinely one subject: what order the rows are in,
-- which column says so, and the arrow that marks it. UI/RaidersBoard.lua
-- measures and draws; UI/RaidersPanel.lua fetches and scrolls; this decides
-- the order.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersSort = {}
SYL.RaidersSort = RaidersSort

-- A DISPLAY PASS OVER AN ALREADY-RANKED LIST, and it must stay one.
--
-- LootScore.Rank is the choke point /syl due, the dashboard "who is due" tile
-- and UI/DueWindow.lua all read. The note above LootScore.Sort was written
-- about the last time two screens ranked by different rules -- "/syl due
-- sorted by drought for days after the board moved to share" -- so a sort key
-- pushed down there would silently reorder three other surfaces.
--
-- TIES ARE THE WHOLE DIFFICULTY, and they are not rare: in Aimee's own season
-- five of thirteen raiders sit at 0 items, 0 points and 0.00 per night, three
-- more tie at 120 points and two at 100. Ten of the thirteen are inside a tied
-- block on at least one column.
--
-- Lua's table.sort is NOT STABLE, and it is worse than that -- a comparator
-- that answers false both ways for two entries leaves their order undefined,
-- so the same data reshuffles between refreshes. Sorting her board by RAID
-- NIGHTS with no tiebreak reordered eleven of thirteen rows into an arbitrary
-- permutation, for no information at all, and it would land differently on
-- the next click.
--
-- So every comparison falls through to the name, which is unique and stable.
-- EXPORTED AND PURE, taking the key and the direction rather than reading the
-- module's own state.
--
-- The first version of this was a local, and the suite written for it copied
-- the comparator into the test rather than calling it -- so removing the
-- tiebreak from the addon changed nothing about whether the test passed. That
-- is the shape HANDOFF.md warns about: a test that has never failed proves
-- nothing, and this one could not have.
function RaidersSort.Entries(entries, key, reversed)
    local column

    for _, candidate in ipairs(SYL.RaidersBoard.COLUMNS) do
        if candidate.key == key then
            column = candidate
        end
    end

    local sorted = {}

    for index, entry in ipairs(entries) do
        sorted[index] = entry
    end

    table.sort(sorted, function(left, right)
        if column then
            local a = column.sortBy(left) or 0
            local b = column.sortBy(right) or 0

            if a ~= b then
                if reversed then
                    return a > b
                end

                return a < b
            end
        end

        local leftName = tostring(left.name or "")
        local rightName = tostring(right.name or "")

        -- The name column sorts A to Z on its first click, which is the
        -- direction somebody looking FOR a person expects. Every other column
        -- falls through to it only to break a tie, and a tie broken
        -- alphabetically should read the same whichever way the numbers run.
        if key == "name" and reversed then
            return leftName > rightName
        end

        return leftName < rightName
    end)

    return sorted
end

--------------------------------------------------------------------------
-- Which column, and which way
--------------------------------------------------------------------------

-- Opens on the order the board has always used, which is LootScore.Sort's:
-- points per night, lowest first, because the board answers who is owed.
local sortKey = "share"
local sortReversed = false

function RaidersSort.Key()
    return sortKey, sortReversed
end

-- Clicking the active column flips it; a new column starts in its natural
-- direction. Same convention as UI/SortHeader.lua, which three other screens
-- already use, so the board does not behave differently from the rest of the
-- addon.
function RaidersSort.OnClick(key, refresh)
    if sortKey == key then
        sortReversed = not sortReversed
    else
        sortKey = key

        -- NAMES READ A TO Z, NUMBERS READ SMALLEST FIRST. The board exists to
        -- answer who is owed, so the people with least are the ones it is
        -- about, and a first click that buried them under the top scorers
        -- would be a worse default than the one it had.
        sortReversed = false
    end

    if refresh then
        refresh()
    end
end

-- WHERE THE ARROW GOES, and why it is not appended to the label.
--
-- RaidersBoard.Measure sets one shared column width from the widest of the
-- two heading lines and the widest value, so the bottom line has EXACTLY zero
-- pixels of slack by construction -- "PER NIGHT" is what sets that width.
-- UI/SortHeader.lua marks its active column by appending "  v" to the label,
-- which here would push a heading 12px into the 14px gap Aimee chose from
-- three samples and leave 1.8px between columns.
--
-- So the arrow is its own font string, drawn in the gap that already exists
-- between one column and the next, and it takes none of the column's width.
local ARROW_UP, ARROW_DOWN = "^", "v"

-- The whole two-line heading is the button, not each line. Clicking "POINTS"
-- and clicking "PER NIGHT" are obviously the same act, and two buttons
-- stacked would make one of them a dead zone.
function RaidersSort.HeadingButton(parent, x, top, width, onClick)
    local button = CreateFrame("Button", nil, parent)

    button:SetPoint("TOPLEFT", x - 4, -(top - 2))
    button:SetSize(width + 8, 26)

    button.highlight = Theme.CreateSolidTexture(button, "rowHover", "BACKGROUND")
    button.highlight:SetAllPoints()
    button.highlight:Hide()

    button:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    button:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    button:SetScript("OnClick", onClick)

    return button
end

-- Which column is showing an arrow, and which way it points.
--
-- Called on every refresh rather than only on a click, because the board is
-- rebuilt whenever the scope or the season changes and an arrow left behind
-- on a column nothing is sorted by is a lie about what is on screen.
function RaidersSort.UpdateHeader(header, key, reversed)
    if not header then
        return
    end

    for name, arrow in pairs(header.arrows) do
        arrow:SetText(
            name == key and (reversed and ARROW_UP or ARROW_DOWN) or ""
        )
    end
end
