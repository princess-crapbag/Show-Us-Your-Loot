-- UI/DashboardTab.lua
--
-- The dashboard: six tiles on a fixed grid, plus a full-width strip.
--
-- THE GRID IS HARD-CODED, and that is the point. Three equal columns, a top
-- row 30% taller than the bottom one — 286 against 220. Sizing to content
-- would let the two list tiles decide their own height, which is the very
-- ratio being pinned, and the layout would shift every time a number changed.
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
local TALL_ROW = 286
local SHORT_ROW = 220
local STRIP_HEIGHT = 54

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
-- created has to go. Regions and children are separate lists in this API and
-- forgetting either leaves ghosts stacked on the new content.
local function ClearTile(tile)
    for _, region in ipairs({ tile.body:GetRegions() }) do
        region:Hide()
        region:SetParent(nil)
    end

    for _, child in ipairs({ tile.body:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    tile.rows = {}
    tile.caption = nil
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

        -- GetWidth is zero before the frame has been laid out once, which
        -- happens on the very first show. A sane fallback keeps the first
        -- draw from collapsing to nothing.
        if not width or width <= 1 then
            width = 300
        end

        for index, widget in ipairs(widgets) do
            local tile = self.tiles[index] or CreateTile(self)
            self.tiles[index] = tile

            ClearTile(tile)

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

                tile:SetWidth(self:GetWidth())
                tile:SetHeight(STRIP_HEIGHT)
            else
                tile:SetWidth(width)
                tile:SetHeight(row == 0 and TALL_ROW or SHORT_ROW)
            end

            local x = column * (width + GAP)
            local y = 0

            -- Rows above this one, at whichever height each of them was.
            for above = 0, row - 1 do
                y = y + (above == 0 and TALL_ROW or SHORT_ROW) + GAP
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
