-- UI/DashboardTab.lua
--
-- The dashboard: six tiles on a fixed grid, plus a full-width strip.
--
-- THE RATIO IS FIXED, THE HEIGHTS ARE NOT, and the difference matters.
--
-- Aimee asked for a top row 30% taller than the bottom one. Fixed pixels —
-- 286 and 220 — were the first attempt and they did not fit: with the strip
-- and the gaps that is 580px of content in a frame 444px tall inside a 596px
-- window, so the bottom row hung off the end of the screen.
--
-- So the rows are computed from the height actually available, holding tall =
-- 1.3 x short. That keeps her ratio exactly, fills the window rather than
-- guessing at it, and means a resized window lays out properly instead of
-- clipping. What must not happen is sizing to *content*, which would let the
-- two list tiles decide their own height — the very ratio being pinned.
--
-- Tiles are built once and refilled on every show. Rebuilding frames per
-- refresh leaks one set per refresh, and the dashboard refreshes whenever
-- anything is captured.
--
-- EVERY TILE IS A BUTTON. Clicking anywhere on one opens the tab it is about,
-- which is what the "›" in its header promises.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local DashboardTab = {}
SYL.DashboardTab = DashboardTab

local COLUMNS = 3
local GAP = 10
local STRIP_HEIGHT = 54

-- Aimee's number: the top row is 30% taller than the bottom one.
local TALL_RATIO = 1.3

-- Only used before the frame has been laid out once, which is the very first
-- draw. Proportioned the same way so the first frame is not visibly different.
local FALLBACK_SHORT = 160

-- The window is fixed at 900 wide and the frame insets 16 each side, so this
-- is the real column width rather than a round number. 300 was the guess, and
-- three of those plus two gaps is 920 in an 868 frame — the third column ran
-- off the window on the very first draw.
local FALLBACK_WIDTH = (900 - 32 - GAP * (COLUMNS - 1)) / COLUMNS

-- Returns the two row heights for the space there is. Solving
--
--   tall + (rows - 1) x short + gaps + strip = height,  tall = ratio x short
--
-- ROWS IS A PARAMETER AND USED TO BE ASSUMED. This solved for exactly two
-- rows, which was true of every dashboard that had ever existed — and then a
-- seventh tile was added, three rows were needed, and the arithmetic still
-- budgeted for two. The grid ran off the bottom of the window: the strip
-- landed below the frame's own backdrop, so the game world showed through it
-- and the whole thing read as transparent tiles rather than as a layout that
-- did not fit.
--
-- Anything that changes the tile count reaches this. Widgets can be switched
-- off, reordered and added, so the count is exactly the thing not to assume.
local function RowHeights(available, rows, hasStrip)
    rows = math.max(1, rows or 2)

    local spare = available
        - (GAP * math.max(0, rows - 1))
        - (hasStrip and (STRIP_HEIGHT + GAP) or 0)

    local short = spare / (TALL_RATIO + (rows - 1))

    -- A window dragged very small should clip gracefully rather than compute
    -- negative heights and throw.
    if not short or short < 60 then
        short = FALLBACK_SHORT
    end

    return math.floor(short * TALL_RATIO), math.floor(short)
end

-- How many rows of ordinary tiles the grid needs, and whether a full-width
-- strip follows them. Counted before anything is positioned, because the row
-- heights depend on it and the heights decide the positions.
local function CountRows(widgets)
    local tiles, hasStrip = 0, false

    for _, widget in ipairs(widgets) do
        if (widget.span or 1) >= COLUMNS then
            hasStrip = true
        else
            tiles = tiles + 1
        end
    end

    return math.max(1, math.ceil(tiles / COLUMNS)), hasStrip
end

local function CreateTile(parent)
    local tile = CreateFrame("Button", nil, parent)

    tile.background = Theme.CreateSolidTexture(tile, "rowAlt", "BACKGROUND")
    tile.background:SetAllPoints()

    tile.border = Theme.CreateSolidTexture(tile, "separator", "BORDER")
    tile.border:SetPoint("TOPLEFT", 0, 0)
    tile.border:SetPoint("TOPRIGHT", 0, 0)
    tile.border:SetHeight(1)

    tile.title = Theme.CreateText(tile, Theme.sizes.columnHeader, "textMuted")
    tile.title:SetPoint("TOPLEFT", 10, -8)

    tile.more = Theme.CreateText(tile, Theme.sizes.columnHeader, "accent")
    tile.more:SetPoint("TOPRIGHT", -10, -8)
    tile.more:SetJustifyH("RIGHT")

    tile.rule = Theme.CreateSeparator(tile)
    tile.rule:SetPoint("TOPLEFT", 10, -22)
    tile.rule:SetPoint("TOPRIGHT", -10, -22)

    -- Everything a renderer draws goes in here, so clearing a tile is
    -- clearing one child rather than hunting for what was added last time.
    tile.body = CreateFrame("Frame", nil, tile)
    tile.body:SetPoint("TOPLEFT", 10, -28)
    tile.body:SetPoint("BOTTOMRIGHT", -10, 8)

    tile.rows = {}

    tile:SetScript("OnEnter", function(self)
        self.background:SetColorTexture(unpack(Theme.colors.rowHover))
    end)

    tile:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(unpack(Theme.colors.rowAlt))
    end)

    return tile
end

-- A tile is refilled rather than rebuilt, so everything the last renderer
-- created has to go.
--
-- HIDDEN, NOT REPARENTED. The first version called region:SetParent(nil),
-- which is not a thing to rely on for a texture or a font string — and it
-- leaked either way, because Theme keeps a strong reference to every region
-- it has colored. Hiding is enough: a hidden region draws nothing, and
-- DashboardParts reuses what is already there rather than making more.
function DashboardTab.ClearTile(tile)
    for _, region in ipairs({ tile.body:GetRegions() }) do
        region:Hide()
    end

    for _, child in ipairs({ tile.body:GetChildren() }) do
        child:Hide()
    end

    tile.rows = {}
    tile.caption = nil

    -- Set by Headline, read by Row. Tiles are reused by grid position, so a
    -- leftover value pushed the next widget in that slot 24px down and its
    -- last row out of the body — reachable just by toggling a widget off.
    tile.rowTop = nil
end

--------------------------------------------------------------------------

function DashboardTab.Create(parent, config)
    local dashboard = CreateFrame("Frame", nil, parent)

    dashboard:SetPoint("TOPLEFT", 16, -100)
    dashboard:SetPoint("BOTTOMRIGHT", -16, 52)

    dashboard.tiles = {}
    dashboard.onOpenTab = config.onOpenTab

    dashboard.empty = Theme.CreateText(dashboard, Theme.sizes.row, "textMuted")
    dashboard.empty:SetPoint("CENTER", 0, 0)
    dashboard.empty:SetJustifyH("CENTER")
    dashboard.empty:SetWordWrap(true)
    dashboard.empty:SetWidth(420)
    dashboard.empty:SetText(
        "Every widget is switched off. Turn some back on in Settings."
    )

    dashboard.empty:Hide()

    function dashboard:Refresh()
        local widgets = SYL.Dashboard.Visible()

        self.empty:SetShown(#widgets == 0)

        -- Laid out in reading order, wrapping every three, with any
        -- full-width widget taking a strip of its own below the grid.
        local column, row = 0, 0
        local width = (self:GetWidth() - GAP * (COLUMNS - 1)) / COLUMNS

        -- GetWidth and GetHeight are zero before the frame has been laid out
        -- once, which happens on the very first show. Sane fallbacks keep the
        -- first draw from collapsing to nothing.
        if not width or width <= 1 then
            width = FALLBACK_WIDTH
        end

        local gridRows, hasStrip = CountRows(widgets)

        local available = self:GetHeight()

        if not available or available <= 1 then
            available = FALLBACK_SHORT * (TALL_RATIO + gridRows - 1)
                + GAP * math.max(0, gridRows - 1)
                + (hasStrip and (STRIP_HEIGHT + GAP) or 0)
        end

        local tallRow, shortRow = RowHeights(available, gridRows, hasStrip)

        for index, widget in ipairs(widgets) do
            local tile = self.tiles[index] or CreateTile(self)
            self.tiles[index] = tile

            DashboardTab.ClearTile(tile)

            tile.title:SetText(string.upper(widget.label))
            tile.more:SetText(widget.tab and (widget.tab:gsub("^%l", string.upper) .. " ›") or "")

            tile:SetScript("OnClick", function()
                if self.onOpenTab and widget.tab then
                    self.onOpenTab(widget.tab)
                end
            end)

            local isStrip = (widget.span or 1) >= COLUMNS

            if isStrip then
                -- Strips always start a fresh line and take the whole width.
                if column > 0 then
                    column = 0
                    row = row + 1
                end

                -- Spanned from the column width rather than read off the
                -- frame: GetWidth is the value the guard above exists to
                -- replace, and using it here gave the strip zero on the very
                -- first draw while its siblings got a real width.
                tile:SetWidth(width * COLUMNS + GAP * (COLUMNS - 1))
                tile:SetHeight(STRIP_HEIGHT)
            else
                tile:SetWidth(width)
                tile:SetHeight(row == 0 and tallRow or shortRow)
            end

            local x = column * (width + GAP)
            local y = 0

            -- Rows above this one, at whichever height each of them was.
            for above = 0, row - 1 do
                y = y + (above == 0 and tallRow or shortRow) + GAP
            end

            tile:SetPoint("TOPLEFT", x, -y)
            tile:Show()

            SYL.DashboardWidgets.Render(tile, widget)

            if isStrip then
                column = 0
                row = row + 1
            else
                column = column + 1

                if column >= COLUMNS then
                    column = 0
                    row = row + 1
                end
            end
        end

        for index = #widgets + 1, #self.tiles do
            self.tiles[index]:Hide()
        end
    end

    dashboard:Hide()

    return dashboard
end
