-- UI/FilterDropdown.lua
--
-- A checkbox dropdown for multi-select filtering. The caller owns the values;
-- this only draws them and reports clicks back.
--
-- Only one dropdown is open at a time, and a full-screen catcher behind the
-- panel closes it when you click anywhere else.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local FilterDropdown = {}
SYL.FilterDropdown = FilterDropdown

local VISIBLE_OPTIONS = 12
local OPTION_HEIGHT = 20
local PANEL_HEADER = 26
local PANEL_PADDING = 6

local openPanel
local catcher

local function GetCatcher()
    if catcher then
        return catcher
    end

    catcher = CreateFrame("Button", nil, UIParent)

    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:EnableMouse(true)
    catcher:Hide()

    catcher:SetScript("OnClick", function()
        FilterDropdown.CloseAll()
    end)

    return catcher
end

function FilterDropdown.CloseAll()
    if openPanel then
        openPanel:Hide()
        openPanel = nil
    end

    if catcher then
        catcher:Hide()
    end
end

--------------------------------------------------------------------------
-- Option rows
--------------------------------------------------------------------------

local function CreateOptionRow(panel, index)
    local row = CreateFrame("Button", nil, panel)

    row:SetHeight(OPTION_HEIGHT)
    row:SetPoint("TOPLEFT", PANEL_PADDING, -(PANEL_HEADER + (index - 1) * OPTION_HEIGHT))
    row:SetPoint("TOPRIGHT", -PANEL_PADDING, -(PANEL_HEADER + (index - 1) * OPTION_HEIGHT))

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.box = Theme.CreateSolidTexture(row, "border", "ARTWORK")
    row.box:SetSize(11, 11)
    row.box:SetPoint("LEFT", 4, 0)

    row.tick = Theme.CreateSolidTexture(row, "accent", "OVERLAY")
    row.tick:SetSize(7, 7)
    row.tick:SetPoint("CENTER", row.box, "CENTER")
    row.tick:Hide()

    row.label = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.label:SetPoint("LEFT", row.box, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", -4, 0)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    return row
end

local function RefreshRows(panel)
    local options = panel.config.getOptions() or {}
    local total = #options

    local maxOffset = math.max(0, total - VISIBLE_OPTIONS)

    if panel.offset > maxOffset then
        panel.offset = maxOffset
    end

    for index = 1, VISIBLE_OPTIONS do
        local row = panel.rows[index]
        local value = options[index + panel.offset]

        if value then
            row.value = value
            row.label:SetText(value)

            if panel.config.isSelected(value) then
                row.tick:Show()
                Theme.SetTextColor(row.label, "textPrimary")
            else
                row.tick:Hide()
                Theme.SetTextColor(row.label, "textSecondary")
            end

            row:Show()
        else
            row.value = nil
            row:Hide()
        end
    end

    local count = panel.config.getCount()

    panel.headerText:SetText(
        total
        .. (total == 1 and " option" or " options")
        .. (count > 0 and ("  ·  " .. count .. " selected") or "")
    )

    if total == 0 then
        panel.emptyText:Show()
    else
        panel.emptyText:Hide()
    end
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local function CreatePanel(button, config)
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")

    panel:SetWidth(math.max(config.width, 190))
    panel:SetHeight(
        PANEL_HEADER + VISIBLE_OPTIONS * OPTION_HEIGHT + PANEL_PADDING * 2
    )

    panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    panel:Hide()

    Theme.StyleWindow(panel)

    panel.config = config
    panel.offset = 0
    panel.rows = {}

    panel.headerText =
        Theme.CreateText(panel, Theme.sizes.columnHeader, "textMuted")

    panel.headerText:SetPoint("TOPLEFT", PANEL_PADDING + 4, -8)

    panel.clearButton = Theme.CreateButton(panel, 46, 16, "Clear", function()
        config.onClear()
        RefreshRows(panel)
    end)

    panel.clearButton:SetPoint("TOPRIGHT", -PANEL_PADDING, -6)

    panel.emptyText =
        Theme.CreateText(panel, Theme.sizes.rowSmall, "textMuted")

    panel.emptyText:SetPoint("CENTER", 0, -8)
    panel.emptyText:SetText("Nothing to filter yet")
    panel.emptyText:Hide()

    for index = 1, VISIBLE_OPTIONS do
        local row = CreateOptionRow(panel, index)

        row:SetScript("OnClick", function(self)
            if not self.value then
                return
            end

            config.onToggle(self.value)

            RefreshRows(panel)
            button:UpdateLabel()
        end)

        panel.rows[index] = row
    end

    panel:EnableMouseWheel(true)

    panel:SetScript("OnMouseWheel", function(self, delta)
        local total = #(config.getOptions() or {})
        local maxOffset = math.max(0, total - VISIBLE_OPTIONS)

        self.offset = math.max(0, math.min(maxOffset, self.offset - delta))

        RefreshRows(self)
    end)

    return panel
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

function FilterDropdown.Create(parent, config)
    local button = Theme.CreateButton(parent, config.width, 22, config.label)

    button.UpdateLabel = function(self)
        local count = config.getCount()

        self.label:SetText(
            config.label .. (count > 0 and (" (" .. count .. ")") or "")
        )

        if count > 0 then
            Theme.SetTextColor(self.label, "accent")
        else
            Theme.SetTextColor(self.label, "textPrimary")
        end
    end

    button:SetScript("OnClick", function(self)
        if not self.panel then
            self.panel = CreatePanel(self, config)
        end

        local wasOpen = openPanel == self.panel

        FilterDropdown.CloseAll()

        if wasOpen then
            return
        end

        self.panel.offset = 0

        RefreshRows(self.panel)

        local catcherFrame = GetCatcher()

        catcherFrame:Show()

        self.panel:SetFrameLevel(catcherFrame:GetFrameLevel() + 10)
        self.panel:Show()

        openPanel = self.panel
    end)

    button:UpdateLabel()

    return button
end
