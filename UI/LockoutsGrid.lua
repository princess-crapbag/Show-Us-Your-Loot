-- UI/LockoutsGrid.lua
--
-- The Keys tab's second view: which character is saved to which Mythic 0
-- dungeon, as a grid.
--
-- A GRID RATHER THAN A LIST, and that is not the usual answer in this addon —
-- Raiders is a board because a table of rankings hid the comparison. This is
-- the opposite shape of data: saved or not saved, eight columns, a handful of
-- rows. There is nothing to rank and nothing to weigh, and the question people
-- actually ask is "who can still run Altar of Fangs", which is a column. A bar
-- chart of booleans would be worse than the table it replaced.
--
-- COLUMNS ARE ABBREVIATED, WITH THE FULL NAME ON HOVER. Eight dungeon names do
-- not fit across 628 pixels and never will. Initials are how the names are
-- said out loud anyway, and the tooltip is there for the one nobody recognises.
--
-- Its own file because UI/KeysPanel.lua is already over the size limit, and
-- because every panel here that grew past 400 lines split the same way: the
-- list in one file, the second view in the other. Assumed from the start this
-- time rather than discovered afterwards.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local LockoutsGrid = {}
SYL.LockoutsGrid = LockoutsGrid

-- A name-realm is the widest thing on this screen and the only one that can
-- not be abbreviated: "Likestoflash-Nordrassil" is who somebody is, and a
-- truncated one is unreadable rather than merely tight. So the name column
-- gets what it needs and the dungeon columns take a fixed narrow width instead
-- of spreading to fill the row.
local NAME_X, NAME_WIDTH = 4, 260
local GRID_LEFT = NAME_X + NAME_WIDTH + 12
local RESET_WIDTH = 84
local CONTENT_WIDTH = 868

local GRID_RIGHT = CONTENT_WIDTH - RESET_WIDTH - 8

-- Wide enough for a four-letter abbreviation and no wider. These used to
-- divide the whole row between them, which put nearly fifty pixels of nothing
-- around every three-letter label and pushed the names into an ellipsis.
local COLUMN_WIDTH = 46
local MIN_COLUMN_WIDTH = 34
local ROW_HEIGHT = 20
local HEADER_TOP = 34
local LIST_TOP = 58
local VISIBLE_ROWS = 14

-- "Altar of Fangs" -> "AOF". Four is enough to stay distinct across a rotation
-- and short enough that no column has to widen for it.
function LockoutsGrid.Abbreviate(name)
    if type(name) ~= "string" or name == "" then
        return "?"
    end

    local letters = {}

    for word in name:gmatch("[%a]+") do
        table.insert(letters, word:sub(1, 1):upper())
    end

    if #letters == 0 then
        return name:sub(1, 4):upper()
    end

    return table.concat(letters):sub(1, 4)
end

-- The preferred width unless the rotation is big enough not to fit, and never
-- below the floor: eight columns is this season, but the season list comes
-- from the client and a future one is free to be longer.
local function ColumnWidth(count)
    if count <= 0 then
        return COLUMN_WIDTH
    end

    local available = GRID_RIGHT - GRID_LEFT

    return math.max(
        MIN_COLUMN_WIDTH,
        math.min(COLUMN_WIDTH, math.floor(available / count))
    )
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- Module level, like UI/KeysPanel.lua's rows, rather than hung off the frame.
-- One view, one set of widgets, and nothing to look up. Keeping them on the
-- frame also meant reading a key that had never been set, which is fine in the
-- client and is a function under the test stub — the stub answers anything,
-- so `frame.headers or {}` took the function and the length of it blew up.
local frame
local headers = {}
local rows = {}
local cells = {}

local function HeaderAt(index)
    if headers[index] then
        return headers[index]
    end

    local button = CreateFrame("Button", nil, frame)

    button:SetSize(MIN_COLUMN_WIDTH, 18)

    button.label =
        Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

    button.label:SetAllPoints()
    button.label:SetJustifyH("CENTER")

    headers[index] = button

    return button
end

local function RowAt(index)
    if rows[index] then
        return rows[index]
    end

    local row = CreateFrame("Frame", nil, frame)

    row:SetPoint("TOPLEFT", NAME_X, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetSize(CONTENT_WIDTH - NAME_X, ROW_HEIGHT)

    row.name = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")

    row.reset = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.reset:SetPoint("LEFT", GRID_RIGHT + 8 - NAME_X, 0)
    row.reset:SetWidth(RESET_WIDTH)
    row.reset:SetJustifyH("RIGHT")

    rows[index] = row
    cells[index] = {}

    return row
end

local function CellAt(rowIndex, index)
    local rowCells = cells[rowIndex]

    if rowCells[index] then
        return rowCells[index]
    end

    local cell = Theme.CreateText(rows[rowIndex], Theme.sizes.row, "textMuted")

    cell:SetWidth(MIN_COLUMN_WIDTH)
    cell:SetJustifyH("CENTER")

    rowCells[index] = cell

    return cell
end

function LockoutsGrid.Create(parent)
    frame = CreateFrame("Frame", nil, parent)

    frame:SetAllPoints()
    frame:Hide()

    return frame
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function LockoutsGrid.Refresh()
    if not frame then
        return 0, 0
    end

    local columns, characters = SYL.Lockouts.Build()
    local width = ColumnWidth(#columns)

    -- Headers. Pooled, so anything left over from a wider rotation has to be
    -- hidden rather than left behind — a stale column header over a column of
    -- blanks reads as "nobody is saved here" rather than as a leftover.
    for index = 1, math.max(#columns, #headers) do
        local header = HeaderAt(index)
        local column = columns[index]

        if column then
            header:ClearAllPoints()
            header:SetPoint(
                "TOPLEFT", GRID_LEFT + (index - 1) * width, -HEADER_TOP
            )
            header:SetSize(width, 18)

            header.label:SetText(LockoutsGrid.Abbreviate(column.name))
            Theme.SetTextColor(
                header.label, column.seasonal and "textMuted" or "warning"
            )

            SYL.Tooltips.Attach(
                header,
                tostring(column.name),
                column.seasonal
                    and "In this season's Mythic+ rotation."
                    or "Not in the season's rotation, but somebody is saved to "
                        .. "it — shown so a lockout is never hidden."
            )

            header:Show()
        else
            header:Hide()
        end
    end

    for index = 1, VISIBLE_ROWS do
        local row = RowAt(index)
        local character = characters[index]

        if character then
            row.name:SetText(tostring(character.name))

            local classColor = Theme.GetClassColor(character.class)

            if classColor then
                Theme.SetCustomTextColor(
                    row.name, classColor[1], classColor[2], classColor[3]
                )
            else
                Theme.SetTextColor(row.name, "textPrimary")
            end

            for cellIndex = 1, math.max(#columns, #cells[index]) do
                local cell = CellAt(index, cellIndex)
                local column = columns[cellIndex]

                if column then
                    local saved = character.instances[column.key]

                    cell:ClearAllPoints()
                    cell:SetPoint(
                        "LEFT", GRID_LEFT - NAME_X + (cellIndex - 1) * width, 0
                    )
                    cell:SetWidth(width)

                    cell:SetText(saved and "X" or "·")
                    Theme.SetTextColor(cell, saved and "warning" or "textMuted")

                    cell:Show()
                else
                    cell:Hide()
                end
            end

            local remaining = SYL.Lockouts.NextReset(character)

            row.reset:SetText(
                remaining and SYL.Lockouts.FormatRemaining(remaining) or ""
            )

            row:Show()
        else
            row:Hide()
        end
    end

    return #columns, #characters
end
