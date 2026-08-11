-- UI/WindowLayout.lua
--
-- Where a window goes when it opens.
--
-- Split from UI/WindowStack.lua, which decides which window is on top. This
-- one decides where they sit, and the two are different questions with very
-- different amounts of arithmetic behind them.
--
-- Aimee's F3: windows should not overlap when they open.

local SYL = _G.ShowUsYourLoot

local WindowLayout = {}
SYL.WindowLayout = WindowLayout

-- Room left between a window and the one beside it, and the margin kept from
-- the screen edge.
local WINDOW_GAP = 8
local SCREEN_MARGIN = 20

--------------------------------------------------------------------------
-- Putting a window somewhere it can be read
--------------------------------------------------------------------------
--
-- Aimee's F3: windows should not overlap when they open. Cascading was the
-- half of it that fits in a line of code — it stops two windows landing
-- exactly on top of each other, and does nothing about the third one covering
-- the first. This is the rest.
--
-- Each window is a rectangle and the ones already open are obstacles. Try
-- center first, because a single window belongs in the middle of the screen;
-- then try beside, above and below each window already up, nearest first;
-- fall back to the cascade when the screen is genuinely full.
--
-- Deliberately not a tiling layout. Windows here are different sizes, get
-- dragged and resized, and are opened in any order — a layout that owns their
-- positions would have to move windows the user placed, which is worse than
-- an occasional overlap.

local function ScreenBounds()
    local width = UIParent:GetWidth() or 1920
    local height = UIParent:GetHeight() or 1080

    return width, height
end

-- Rectangles are in UIParent's coordinate space, origin bottom left.
local function RectOf(frame)
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()

    if not left or not bottom then
        return nil
    end

    return {
        left = left,
        bottom = bottom,
        right = left + frame:GetWidth(),
        top = bottom + frame:GetHeight(),
    }
end

local function Overlaps(a, b)
    return a.left < b.right
        and a.right > b.left
        and a.bottom < b.top
        and a.top > b.bottom
end

-- A candidate is given by its bottom-left corner. It has to sit inside the
-- screen and clear of everything already open.
local function Fits(left, bottom, width, height, rects)
    local screenWidth, screenHeight = ScreenBounds()

    if left < SCREEN_MARGIN or bottom < SCREEN_MARGIN then
        return false
    end

    if left + width > screenWidth - SCREEN_MARGIN then
        return false
    end

    if bottom + height > screenHeight - SCREEN_MARGIN then
        return false
    end

    local candidate = {
        left = left,
        bottom = bottom,
        right = left + width,
        top = bottom + height,
    }

    for _, rect in ipairs(rects) do
        if Overlaps(candidate, rect) then
            return false
        end
    end

    return true
end

local function FindSpot(width, height, rects)
    local screenWidth, screenHeight = ScreenBounds()

    local centerLeft = (screenWidth - width) / 2
    local centerBottom = (screenHeight - height) / 2

    if Fits(centerLeft, centerBottom, width, height, rects) then
        return centerLeft, centerBottom
    end

    -- Beside first, then stacked, because screens are wider than they are
    -- tall and a window pushed sideways stays readable next to its neighbor.
    local candidates = {}

    for _, rect in ipairs(rects) do
        table.insert(candidates, { rect.right + WINDOW_GAP, rect.bottom })
        table.insert(candidates, { rect.left - WINDOW_GAP - width, rect.bottom })
        table.insert(candidates, { rect.left, rect.top + WINDOW_GAP })
        table.insert(candidates, { rect.left, rect.bottom - WINDOW_GAP - height })
    end

    -- Nearest the center wins, so windows cluster rather than scattering into
    -- the corners.
    table.sort(candidates, function(left, right)
        local leftDistance = math.abs(left[1] - centerLeft)
            + math.abs(left[2] - centerBottom)

        local rightDistance = math.abs(right[1] - centerLeft)
            + math.abs(right[2] - centerBottom)

        return leftDistance < rightDistance
    end)

    for _, candidate in ipairs(candidates) do
        if Fits(candidate[1], candidate[2], width, height, rects) then
            return candidate[1], candidate[2]
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- Laying the whole set out
--------------------------------------------------------------------------
--
-- Finding a gap for the newcomer is not enough, and the arithmetic says why.
-- The first window opens centered, 900 wide on a 1920 screen: that leaves 490
-- either side, and the next window is 660. There is no gap. Every window
-- after the first would fall through to the cascade, which is the behavior
-- F3 was raised about.
--
-- So the set gets laid out together rather than one at a time. Two windows
-- that do not fit around each other fit perfectly well beside each other once
-- both are allowed to move.
--
-- ONLY WINDOWS THIS FILE PLACED. Dragging a window is the user saying where
-- it goes, and rearranging it afterwards would be the addon overruling them.
-- One dragged window turns the whole thing off and the gap search takes over,
-- which is the honest trade: their layout, our best effort around it.
-- Rows of windows, packed left to right and wrapped when the row is full.
-- Returns nil when the set cannot be made to fit at all.
local function PackRows(frames, usableWidth)
    local rows = {}
    local current = { width = 0, height = 0, frames = {} }

    for _, frame in ipairs(frames) do
        local width = frame:GetWidth() or 0
        local height = frame:GetHeight() or 0

        if width <= 0 or height <= 0 or width > usableWidth then
            return nil
        end

        local extra = (#current.frames > 0) and WINDOW_GAP or 0

        if current.width + extra + width > usableWidth then
            if #current.frames > 0 then
                table.insert(rows, current)
            end

            current = { width = 0, height = 0, frames = {} }
            extra = 0
        end

        current.width = current.width + extra + width
        current.height = math.max(current.height, height)

        table.insert(current.frames, frame)
    end

    if #current.frames > 0 then
        table.insert(rows, current)
    end

    return rows
end

-- Returns true when it placed everything.
local function Arrange(frames)
    if #frames == 0 then
        return false
    end

    local screenWidth, screenHeight = ScreenBounds()
    local usableWidth = screenWidth - SCREEN_MARGIN * 2
    local usableHeight = screenHeight - SCREEN_MARGIN * 2

    local rows = PackRows(frames, usableWidth)

    if not rows then
        return false
    end

    local totalHeight = 0

    for index, row in ipairs(rows) do
        totalHeight = totalHeight + row.height

        if index > 1 then
            totalHeight = totalHeight + WINDOW_GAP
        end
    end

    if totalHeight > usableHeight then
        return false
    end

    -- The block is centered, so one window still lands in the middle of the
    -- screen and two land either side of it.
    local top = (screenHeight + totalHeight) / 2

    for _, row in ipairs(rows) do
        local left = (screenWidth - row.width) / 2

        for _, frame in ipairs(row.frames) do
            local height = frame:GetHeight()

            frame:ClearAllPoints()
            frame:SetPoint(
                "TOPLEFT", UIParent, "BOTTOMLEFT", left, top
            )

            frame.symlPlaced = true

            left = left + frame:GetWidth() + WINDOW_GAP
        end

        top = top - row.height - WINDOW_GAP
    end

    return true
end


-- The public entry point. `others` is every window already open, in the order
-- they were opened; `userMoved` says whether any of them has been dragged.
--
-- Returns true when it placed the frame.
function WindowLayout.Place(frame, others, userMoved)
    local width = frame:GetWidth()
    local height = frame:GetHeight()

    if not width or not height or width <= 0 or height <= 0 then
        return false
    end

    -- Lay the whole set out first, which is the only way two windows wider
    -- than half the screen between them both end up visible.
    if not userMoved then
        local frames = {}

        for _, other in ipairs(others) do
            table.insert(frames, other)
        end

        table.insert(frames, frame)

        if Arrange(frames) then
            return true
        end
    end

    -- Something has been dragged, or the set no longer fits. Find a gap
    -- around what is already there instead.
    local rects = {}

    for _, other in ipairs(others) do
        local rect = RectOf(other)

        if rect then
            table.insert(rects, rect)
        end
    end

    local left, bottom = FindSpot(width, height, rects)

    if not left then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)

    return true
end
