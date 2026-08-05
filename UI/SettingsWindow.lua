-- UI/SettingsWindow.lua
--
-- Toggles that change what the addon records and how loudly it reports it.
--
-- Quality tracking gates capture rather than display, so the window says so
-- plainly: turning a quality off means those items are never written down.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local ItemQuality = SYL.ItemQuality

local WINDOW_WIDTH = 420

-- Tall enough to clear the footer: the toggle section ends 448px down, and
-- the footer rule sits 44px up from the bottom.
local WINDOW_HEIGHT = 512
local ROW_HEIGHT = 24

local frame
local rows = {}

-- Quality colours come from the client so they match the item names in the
-- list views rather than an approximation of them.
local GetItemQualityColor =
    C_Item and C_Item.GetItemQualityColor or _G.GetItemQualityColor

local function CreateCheckRow(parent, index, labelText, onClick)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(14, 14)
    row.box:SetPoint("LEFT", 2, 0)

    row.edge = Theme.CreateSolidTexture(row.box, "border", "BACKGROUND")
    row.edge:SetAllPoints()

    row.fill = Theme.CreateSolidTexture(row.box, "window", "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 1, -1)
    row.fill:SetPoint("BOTTOMRIGHT", -1, 1)

    row.tick = Theme.CreateSolidTexture(row.box, "accent", "OVERLAY")
    row.tick:SetSize(8, 8)
    row.tick:SetPoint("CENTER")
    row.tick:Hide()

    row.label = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.label:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetText(labelText)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", onClick)

    row.SetChecked = function(self, checked)
        if checked then
            self.tick:Show()
        else
            self.tick:Hide()
        end
    end

    return row
end

local function RefreshRows()
    for _, row in ipairs(rows) do
        row:SetChecked(row.isChecked())
    end

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

local function AddSection(parent, title, offsetY)
    local heading =
        Theme.CreateText(parent, Theme.sizes.columnHeader, "textMuted")

    heading:SetPoint("TOPLEFT", 20, offsetY)
    heading:SetText(title)

    local container = CreateFrame("Frame", nil, parent)

    container:SetPoint("TOPLEFT", 20, offsetY - 18)
    container:SetPoint("TOPRIGHT", -20, offsetY - 18)

    return container
end

local function BuildQualitySection(parent)
    local container = AddSection(parent, "RECORD THESE ITEM QUALITIES", -104)

    container:SetHeight(#ItemQuality.ORDER * ROW_HEIGHT)

    for index, quality in ipairs(ItemQuality.ORDER) do
        local row = CreateCheckRow(
            container,
            index,
            ItemQuality.NAMES[quality],
            function()
                ItemQuality.SetTracked(
                    quality,
                    not ItemQuality.IsTracked(quality)
                )

                RefreshRows()
            end
        )

        local red, green, blue = GetItemQualityColor(quality)

        if red then
            row.label:SetTextColor(red, green, blue)
        end

        row.isChecked = function()
            return ItemQuality.IsTracked(quality)
        end

        table.insert(rows, row)
    end

    local note = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

    note:SetPoint("TOPLEFT", 20, -104 - 18 - #ItemQuality.ORDER * ROW_HEIGHT - 6)
    note:SetPoint("TOPRIGHT", -20, -104 - 18 - #ItemQuality.ORDER * ROW_HEIGHT - 6)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetHeight(30)

    note:SetText(
        "Unticked qualities are never recorded. This does not remove records "
        .. "you already have."
    )
end

local TOGGLES = {
    {
        label = "Record group loot from Loot History",
        key = "lootHistoryCapture",

        onChanged = function(enabled)
            if enabled then
                SYL.LootHistory.Enable()
            else
                SYL.LootHistory.Disable()
            end
        end,
    },
    {
        label = "Announce captures in chat",
        key = "announceCaptures",
    },
    {
        label = "Show debug messages",
        key = "debug",
    },
}

local function BuildToggleSection(parent)
    local top = -104 - 18 - #ItemQuality.ORDER * ROW_HEIGHT - 44
    local container = AddSection(parent, "BEHAVIOUR", top)

    container:SetHeight(#TOGGLES * ROW_HEIGHT)

    for index, toggle in ipairs(TOGGLES) do
        local row = CreateCheckRow(
            container,
            index,
            toggle.label,
            function()
                local settings = ShowUsYourLootDB.settings

                settings[toggle.key] = not settings[toggle.key]

                if toggle.onChanged then
                    toggle.onChanged(settings[toggle.key])
                end

                RefreshRows()
            end
        )

        row.isChecked = function()
            return ShowUsYourLootDB.settings[toggle.key] and true or false
        end

        table.insert(rows, row)
    end
end

local function CreateSettingsWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootSettingsFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("SETTINGS")

    local subtitle =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    subtitle:SetPoint("TOPLEFT", 27, -40)
    subtitle:SetText("What gets recorded")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -66)
    separator:SetPoint("TOPRIGHT", -16, -66)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    BuildQualitySection(frame)
    BuildToggleSection(frame)

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:SetScript("OnShow", RefreshRows)
    frame:Hide()

    return frame
end

function SYL:OpenSettingsWindow()
    local window = CreateSettingsWindow()

    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
