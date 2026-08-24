-- UI/RaidersBoardRows.lua
--
-- One row of the Raiders board: building it, and filling it in for whichever
-- raider is scrolled into it.
--
-- Separate from UI/RaidersBoard.lua because that file answers where everything
-- goes and this one answers what goes there, and together they were over the
-- size where either could be read. Every measurement is that file's -- see
-- RaidersBoard.Measure -- and is read from it rather than repeated here.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersBoard = SYL.RaidersBoard

local RaidersBoardRows = {}
SYL.RaidersBoardRows = RaidersBoardRows

local ROW_SIZE = Theme.sizes.rowSmall



-- The three steps of the average marker, widest first, so it tapers to a point
-- just above the bar.
local NOTCH_STEPS = { 7, 5, 3 }

local function PlaceNotch(row, x)
    for index, width in ipairs(NOTCH_STEPS) do
        local step = row.notch[index]

        step:ClearAllPoints()
        step:SetPoint(
            "BOTTOMLEFT", row.track, "TOPLEFT",
            x - width / 2, #NOTCH_STEPS - index + 1
        )
        step:SetSize(width, 1)
        step:Show()
    end
end

local function HideNotch(row)
    for _, step in ipairs(row.notch) do
        step:Hide()
    end
end

-- What the row says when it is pointed at. Read from row.entry on hover rather
-- than baked in when the row is built: sixteen frames serve however many
-- raiders are in the season, so whatever is captured at build time belongs to
-- whoever happened to be scrolled into that slot at the time.
local function TooltipTitle(row)
    return row.entry and tostring(row.entry.name or "Unknown") or nil
end

local function TooltipBody(row)
    local entry = row.entry

    if not entry then
        return nil
    end

    -- The reason used to be printed in the row, in the column that now holds
    -- points per night. It never fitted, and with the column measured it
    -- plainly cannot -- so it says it here, where there is room for a
    -- sentence.
    if not entry.ranked then
        return entry.notRankedReason
            or "Not ranked yet. This fills in from the next raid night."
    end

    local byTrack = entry.byTrack or {}
    local parts, named = {}, 0

    for _, track in ipairs(RaidersBoard.TRACKS) do
        local points = byTrack[track.id] or 0

        if points > 0 then
            named = named + points
            parts[#parts + 1] = string.format("%s %d", track.name, points)
        end
    end

    local rest = (entry.lootScore or 0) - named

    if rest > 0 then
        parts[#parts + 1] = string.format("Other %d", rest)
    end

    if #parts == 0 then
        return "Nothing counted yet. Click for the arithmetic."
    end

    -- The legend for the bar's colors, on the bar itself, for the one raider
    -- being asked about. A key drawn across the top of the board would take a
    -- row from the sixteen to explain something most rows do not need.
    return "The bar, by difficulty: " .. table.concat(parts, ", ")
        .. ". Click for every item."
end

function RaidersBoardRows.Create(parent, index, top, onClick)
    local layout = RaidersBoard.layout

    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(RaidersBoard.ROW_HEIGHT)
    row:SetWidth(layout.width)
    row:SetPoint(
        "TOPLEFT", 0, -(top + (index - 1) * RaidersBoard.ROW_HEIGHT)
    )

    -- Banding, because four numbers and a bar is more than the eye tracks
    -- across 606px unaided. Below the hover color rather than beside it, or
    -- pointing at a banded row would do nothing visible.
    if index % 2 == 1 then
        local band = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        band:SetAllPoints()
    end

    local hover = Theme.CreateSolidTexture(row, "rowHover", "BORDER")
    hover:SetAllPoints()
    hover:Hide()

    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    row.name = Theme.CreateText(row, ROW_SIZE, "textPrimary")
    row.name:SetPoint("LEFT", layout.left, 0)
    row.name:SetWidth(layout.name)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- The track is the full width every bar is measured against, so an empty
    -- track reads as zero rather than as a missing row.
    row.track = CreateFrame("Frame", nil, row)
    row.track:SetSize(layout.barWidth, RaidersBoard.BAR_HEIGHT)
    row.track:SetPoint("TOPLEFT", layout.bar, -RaidersBoard.BAR_INSET)

    -- SEPARATOR AND NOT rowAlt, WHICH IS WHAT THE BANDING USES. An empty
    -- track has to read as zero rather than as a row that failed to draw, and
    -- a track the same color as the band it sits on disappears on every other
    -- row -- so exactly half the raiders who have taken nothing would look
    -- like a rendering fault instead of like the answer.
    local base = Theme.CreateSolidTexture(row.track, "separator", "BACKGROUND")
    base:SetAllPoints()

    row.fills = {}

    for fill = 1, #RaidersBoard.TRACKS + 1 do
        local texture = row.track:CreateTexture(nil, "ARTWORK")

        texture:Hide()

        row.fills[fill] = texture
    end

    row.notch = {}

    for step = 1, #NOTCH_STEPS do
        row.notch[step] = Theme.CreateSolidTexture(row, "warning", "OVERLAY")
        row.notch[step]:Hide()
    end

    row.values = {}

    for column = 1, #RaidersBoard.COLUMNS do
        local value = Theme.CreateText(row, ROW_SIZE, "textSecondary")

        value:SetPoint("LEFT", RaidersBoard.ColumnX(column), 0)
        value:SetWidth(layout.column)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)

        row.values[column] = value
    end

    row:SetScript("OnClick", function()
        onClick(row.entryKey)
    end)

    SYL.Tooltips.Attach(row, TooltipTitle, TooltipBody)

    return row
end

--------------------------------------------------------------------------
-- Filling one in
--------------------------------------------------------------------------

-- The bar, cut into difficulty segments in the order the tracks climb.
--
-- POINTS AND NOT ITEMS. The bar is a length in points, so splitting it by item
-- count would put boundaries where the eye cannot reconcile them with the
-- length they add to: three Heroic transmogs would color half a bar they
-- contributed nothing to.
--
-- Cut at cumulative positions rather than by adding up segment widths. Four
-- roundings in a row drift, and a bar that ends a pixel short of its own total
-- is a bar somebody will measure against the row above it and find wrong.
local function Segments(entry)
    local byTrack = entry.byTrack or {}
    local out, named = {}, 0

    for _, track in ipairs(RaidersBoard.TRACKS) do
        local points = byTrack[track.id] or 0

        if points > 0 then
            named = named + points
            out[#out + 1] = { points = points, color = track.color }
        end
    end

    -- Whatever the three tracks did not account for. It has to be drawn, or
    -- the bar would be shorter than the total printed beside it, which is the
    -- one thing a bar must never be.
    local rest = (entry.lootScore or 0) - named

    if rest > 0 then
        out[#out + 1] = { points = rest, color = RaidersBoard.UNKNOWN_COLOR }
    end

    return out
end

local function DrawBar(row, entry, highest)
    local layout = RaidersBoard.layout
    local full = SYL.LootScore.BarFraction(entry, highest) * layout.barWidth
    local total = entry.lootScore or 0
    local segments = (full > 0 and total > 0) and Segments(entry) or {}
    local at = 0

    for index, fill in ipairs(row.fills) do
        local segment = segments[index]

        if segment then
            local from = (at / total) * full

            at = at + segment.points

            local to = (at / total) * full
            local color = segment.color

            fill:SetColorTexture(color[1], color[2], color[3], 1)
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", from, 0)
            fill:SetPoint("BOTTOMLEFT", from, 0)
            fill:SetWidth(math.max(1, to - from))
            fill:Show()
        else
            fill:Hide()
        end
    end
end

function RaidersBoardRows.Draw(row, entry, view, isSelected)
    local layout = RaidersBoard.layout

    row.entry = entry
    row.entryKey = entry.key

    row.name:SetText(tostring(entry.name or "Unknown"))

    SYL.ClassColor.Set(row.name, entry.class)

    DrawBar(row, entry, view.highest)

    -- THE AVERAGE AS A MARK ABOVE THE BAR, not a line drawn through it. Through
    -- it, the line and the bar are the same object at a glance and you cannot
    -- tell a bar that stops at the average from one that crosses it. Above it,
    -- the two never touch and the comparison is the gap.
    if (view.highest or 0) > 0 and (view.average or 0) > 0 then
        PlaceNotch(
            row,
            math.min(1, view.average / view.highest) * layout.barWidth
        )
    else
        HideNotch(row)
    end

    for index, column in ipairs(RaidersBoard.COLUMNS) do
        local value = row.values[index]
        local text = column.value(entry, view)

        value:SetText(text)

        -- Selected reads as the accent on the numbers, not a border: a border
        -- on a 22px row competes with the bar drawn beside it.
        if isSelected then
            Theme.SetTextColor(value, "accent")
        elseif text == RaidersBoard.EMPTY or not entry.ranked then
            Theme.SetTextColor(value, "textMuted")
        else
            Theme.SetTextColor(value, "textSecondary")
        end
    end

    row:Show()
end
