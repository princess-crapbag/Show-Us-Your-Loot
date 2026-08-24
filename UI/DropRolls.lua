-- UI/DropRolls.lua
--
-- The list under a drop: who was eligible, what they answered, and what they
-- rolled.
--
-- TWO SOURCES, ONE LIST, AND THE HEADING SAYS WHICH. The client reports the
-- group-loot roll; RCLootCouncil knows who actually wanted the item. Under a
-- council those two disagree completely — the group-loot list reads "everybody
-- passed, the master looter took it" on every single drop, which is true and
-- useless. So when the council's answers are available they are what is shown,
-- and the heading names the source rather than leaving somebody to work out
-- why the same raid reads two different ways on two nights.
--
-- Showing both at once was the other option and it is worse: the same eleven
-- names twice, once saying Pass and once saying Need, with nothing on screen
-- explaining that they are answers to different questions.
--
-- THE LIST IS SIZED TO WHAT IS IN IT. It used to reserve fourteen rows
-- whatever the drop held, so a guild night with eleven raiders drew three
-- empty rows above the count. Aimee approved dropping them along with the
-- column headings, which the window never had.
--
-- Split from UI/DropDetailWindow.lua at the point it would have gone over the
-- size limit, which is the shape HANDOFF asks for.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local DropRolls = {}
SYL.DropRolls = DropRolls

DropRolls.ROW_HEIGHT = 20
DropRolls.HEADER_HEIGHT = 20
DropRolls.MAX_ROWS = 14

-- The line naming which of the two sources the list came from.
DropRolls.HEADING_HEIGHT = 18

-- The room a "not recording" notice needs, when there is one.
DropRolls.NOTICE_HEIGHT = 46

-- Columns are declared with the widest string each can ever hold and measured
-- against it, which is the rule UI/Columns.lua wrote down after the DATE
-- column shipped truncated twice. Too wide is a defect as well: this window is
-- 500 across and every pixel a column does not need is one the names get.
local GROUP_COLUMNS = {
    { key = "name", label = "PLAYER", width = 150 },
    { key = "response", label = "RESPONSE", width = 90 },
    { key = "roll", label = "ROLL", width = 44 },
    { key = "rank", label = "GUILD RANK", width = 96 },
    { key = "marker", label = "", width = 38 },
}

local COUNCIL_COLUMNS = {
    { key = "name", label = "PLAYER", width = 150 },
    { key = "response", label = "RESPONSE", width = 90 },
    { key = "roll", label = "ROLL", width = 44 },
    { key = "ilvl", label = "ILVL", width = 44 },
    { key = "votes", label = "VOTES", width = 52 },
    { key = "marker", label = "", width = 38 },
}

--------------------------------------------------------------------------
-- Turning either source into rows
--------------------------------------------------------------------------

-- Need first, then the softer claims, then everyone who stood aside. Within a
-- group the highest roll leads.
local STATE_ORDER = {
    [0] = 1, -- NeedMainSpec
    [1] = 2, -- NeedOffSpec
    [2] = 3, -- Transmog
    [3] = 4, -- Greed
    [4] = 5, -- NoRoll
    [5] = 6, -- Pass
}

local function SortGroupRolls(rolls)
    local sorted = {}

    for _, roll in ipairs(rolls or {}) do
        table.insert(sorted, roll)
    end

    table.sort(sorted, function(left, right)
        if left.isWinner ~= right.isWinner then
            return left.isWinner == true
        end

        local leftOrder = STATE_ORDER[left.state] or 99
        local rightOrder = STATE_ORDER[right.state] or 99

        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end

        if (left.roll or -1) ~= (right.roll or -1) then
            return (left.roll or -1) > (right.roll or -1)
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return sorted
end

local function FromGroupLoot(record)
    local rows = {}

    for _, roll in ipairs(SortGroupRolls(record.rolls)) do
        table.insert(rows, {
            name = roll.name,
            class = roll.class,

            response = SYL.LootHistoryAPI.ShortRollState(roll.state)
                or roll.stateText
                or "unknown",

            -- Players who passed or took transmog never rolled, so a number
            -- here would be invented.
            roll = roll.roll and tostring(roll.roll) or "—",

            rank = SYL.Guild.GetRank(roll.guid, roll.name)
                or roll.guildRank
                or "",

            marker = roll.isWinner and "WON" or "",
        })
    end

    return rows
end

local function FromCouncil(responses)
    local rows = {}

    for _, entry in ipairs(responses) do
        table.insert(rows, {
            name = entry.name,
            class = entry.class,
            response = entry.response or "—",
            roll = entry.roll and tostring(entry.roll) or "—",
            ilvl = entry.ilvl and tostring(entry.ilvl) or "—",
            votes = entry.votes and tostring(entry.votes) or "—",
            marker = entry.isWinner and "GOT IT" or "",
        })
    end

    return rows
end

-- What the list should be, and what to say above it. Returns columns, rows, a
-- heading, and the notice when there is one to draw.
function DropRolls.Build(record)
    local council = SYL.CouncilLoot.Describe(record)

    if council.state == "responses" then
        return {
            columns = COUNCIL_COLUMNS,
            rows = FromCouncil(council.responses),
            heading = "WHAT THE COUNCIL WAS TOLD",
            countLabel = "answered",
        }
    end

    local rows = FromGroupLoot(record)

    -- OFFERED ONLY WHERE IT WOULD HELP. On a drop nobody rolled on there is
    -- no council session to have recorded anything, and telling somebody to
    -- change a setting that would not have helped is worse than saying
    -- nothing.
    local notice

    if council.state == "off" and #rows > 0 then
        notice = {
            text = "RCLootCouncil is not recording who else responded, so "
                .. "this is the group-loot roll rather than the council's."
                .. " Nothing kept it — its own history cannot show it either.",
            button = "Turn on " .. SYL.CouncilLoot.SETTING_LABEL,
        }
    end

    -- NAMED WHENEVER THERE ARE TWO ANSWERS TO CHOOSE BETWEEN. With
    -- RCLootCouncil installed the same eleven raiders read Pass here and Need
    -- on the council's list, and without a line saying which one this is only
    -- the changed columns tell them apart. With no RCLootCouncil there is only
    -- ever one list and the heading would be noise.
    return {
        columns = GROUP_COLUMNS,
        rows = rows,

        heading = (council.state ~= "absent" and #rows > 0)
            and "WHAT THE GROUP-LOOT ROLL SAID"
            or nil,

        countLabel = "eligible",
        notice = notice,
    }
end

-- How tall the window has to be to hold it, in the units the caller anchors
-- with. Sized to the list rather than to a fixed fourteen.
function DropRolls.HeightFor(view)
    local shown = math.min(#view.rows, DropRolls.MAX_ROWS)

    return DropRolls.HEADER_HEIGHT
        + shown * DropRolls.ROW_HEIGHT
        + (view.notice and DropRolls.NOTICE_HEIGHT or 0)
        + (view.heading and DropRolls.HEADING_HEIGHT or 0)
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function DropRolls.CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(DropRolls.ROW_HEIGHT)

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    -- One font string per column position, positioned when the columns are
    -- known: the two sources do not have the same columns, and rows are
    -- reused across drops.
    row.cells = {}

    for cell = 1, 6 do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")

        text:SetJustifyH("LEFT")
        text:Hide()

        row.cells[cell] = text
    end

    return row
end

local function PlaceCells(cells, columns)
    local left = 6

    for index, column in ipairs(columns) do
        local cell = cells[index]

        cell:ClearAllPoints()
        cell:SetPoint("LEFT", left, 0)
        cell:SetWidth(column.width)
        cell:Show()

        left = left + column.width + 6
    end

    for index = #columns + 1, #cells do
        cells[index]:Hide()
    end
end

function DropRolls.FillRow(row, entry, columns)
    PlaceCells(row.cells, columns)

    for index, column in ipairs(columns) do
        local cell = row.cells[index]

        cell:SetText(tostring(entry[column.key] or ""))

        if column.key == "name" then
            SYL.ClassColor.Set(cell, entry.class)
        elseif column.key == "marker" then
            Theme.SetTextColor(cell, "accent")
        elseif column.key == "response" then
            Theme.SetTextColor(cell, "textSecondary")
        else
            Theme.SetTextColor(cell, "textMuted")
        end
    end
end

-- A frame rather than loose font strings, so PlaceCells can anchor its cells
-- the same way it anchors a row's — LEFT of their own container. Anchored to
-- the window they would have sat against its left edge at its vertical middle.
function DropRolls.CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)

    header:SetHeight(DropRolls.HEADER_HEIGHT)

    header.cells = {}

    for cell = 1, 6 do
        local text = Theme.CreateText(
            header, Theme.sizes.columnHeader, "textMuted"
        )

        text:SetJustifyH("LEFT")
        text:Hide()

        header.cells[cell] = text
    end

    return header
end

function DropRolls.FillHeader(header, columns)
    PlaceCells(header.cells, columns)

    for index, column in ipairs(columns) do
        header.cells[index]:SetText(column.label)
    end
end
