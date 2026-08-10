-- UI/SettingsRows.lua
--
-- The contents of the settings window: the row widget, the quality list, the
-- behaviour toggles, and how tall all of that is.
--
-- Split from UI/SettingsWindow.lua, which crossed the size limit the same way
-- RosterWindow did before it — by holding the chrome, the content and the
-- layout maths at once. That file now opens a window; this one decides what is
-- in it.
--
-- ROWS ARE OF TWO KINDS AND HAVE TO LOOK IT. Most are checkboxes bound to a
-- saved setting. Two are not settings at all: the colour scheme and the output
-- window cycle through values when pressed, and drawing those as checkboxes
-- meant drawing a box that could never be ticked.
--
-- syl-check: size-exempt — three sections of one window, and they share the
-- row factory, the section helper, the row registry and the layout constants
-- that decide where each section starts. Splitting the last one out to save
-- ten lines would mean exporting five internals: more surface than it
-- removes, and the layout maths would then live apart from the thing it
-- measures.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local ItemQuality = SYL.ItemQuality

local SettingsRows = {}
SYL.SettingsRows = SettingsRows

local ROW_HEIGHT = 24

-- Layout is derived from the content rather than hardcoded, so adding a
-- quality or a toggle cannot silently push the last row through the footer.
local QUALITY_TOP = -104
local HEADING_HEIGHT = 18
local NOTE_HEIGHT = 30
local SECTION_GAP = 44
local FOOTER_HEIGHT = 60
local FEATURE_ROW_HEIGHT = 38

local rows = {}

-- Quality colours come from the client so they match the item names in the
-- list views rather than an approximation of them.
local GetItemQualityColor =
    C_Item and C_Item.GetItemQualityColor or _G.GetItemQualityColor

local function CreateSettingRow(parent, index, labelText, onClick, options)
    options = options or {}

    local row = CreateFrame("Button", nil, parent)
    local height = options.height or ROW_HEIGHT
    local isAction = options.isAction

    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * height))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * height))

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.label = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetText(labelText)

    if isAction then
        row.label:SetPoint("LEFT", 2, 0)

        row.chevron = Theme.CreateText(row, Theme.sizes.row, "textMuted")
        row.chevron:SetPoint("RIGHT", -4, 0)
        row.chevron:SetText(">")

        row.label:SetPoint("RIGHT", row.chevron, "LEFT", -6, 0)
    else
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

        row.label:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    end

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", onClick)

    row.SetChecked = function(self, checked)
        if not self.tick then
            return
        end

        if checked then
            self.tick:Show()
        else
            self.tick:Hide()
        end
    end

    return row
end

function SettingsRows.Refresh()
    for _, row in ipairs(rows) do
        if row.isChecked then
            row:SetChecked(row.isChecked())
        end

        if row.describe then
            row.label:SetText(row.describe())
        end
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

    -- Kept on the container so a section that tears itself down can take its
    -- heading with it. The heading is parented to the window, not to the
    -- container, so hiding the container alone leaves it behind.
    container.heading = heading

    local container = CreateFrame("Frame", nil, parent)

    container:SetPoint("TOPLEFT", 20, offsetY - 18)
    container:SetPoint("TOPRIGHT", -20, offsetY - 18)

    return container
end

local function QualityBlockBottom()
    return QUALITY_TOP - HEADING_HEIGHT - #ItemQuality.ORDER * ROW_HEIGHT
end

local function ToggleSectionTop()
    return QualityBlockBottom() - NOTE_HEIGHT - SECTION_GAP
end

function SettingsRows.BuildQualitySection(parent)
    local container =
        AddSection(parent, "RECORD THESE ITEM QUALITIES", QUALITY_TOP)

    container:SetHeight(#ItemQuality.ORDER * ROW_HEIGHT)

    for index, quality in ipairs(ItemQuality.ORDER) do
        local row = CreateSettingRow(
            container,
            index,
            ItemQuality.NAMES[quality],
            function()
                ItemQuality.SetTracked(
                    quality,
                    not ItemQuality.IsTracked(quality)
                )

                SettingsRows.Refresh()
            end
        )

        local red, green, blue = GetItemQualityColor(quality)

        -- The whole point of this row is that it is the colour it names, so
        -- it must survive a palette change rather than being repainted back
        -- to plain text.
        if red then
            Theme.SetCustomTextColor(row.label, red, green, blue)
        end

        row.isChecked = function()
            return ItemQuality.IsTracked(quality)
        end

        table.insert(rows, row)
    end

    local note = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

    note:SetPoint("TOPLEFT", 20, QualityBlockBottom() - 6)
    note:SetPoint("TOPRIGHT", -20, QualityBlockBottom() - 6)
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
        -- Cycles rather than opening a menu, and repaints immediately, so
        -- picking one is a matter of clicking until it looks right instead of
        -- reading colour names and guessing.
        label = "Colour scheme",
        action = function()
            local palette =
                SYL.Theme.Apply(SYL.Palettes.Next(SYL.Theme.paletteKey))

            SYL:Print(
                "Colour scheme: " .. palette.name .. " — " .. palette.note .. "."
            )
        end,
        describe = function()
            local palette = SYL.Theme.Current()

            return "Colour scheme: " .. (palette and palette.name or "unknown")
        end,
    },
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
        label = "Show the minimap button",
        key = "showMinimapButton",

        onChanged = function(enabled)
            SYL.MinimapButton.SetShown(enabled)
        end,
    },
    {
        -- Says gear, because that is now all it announces. Every quality is
        -- still recorded; announcing every quality was what doubled the
        -- user's loot chat with greys after a Mythic+ run.
        label = "Announce gear in chat when it is recorded",
        key = "announceCaptures",
    },
    {
        -- Not a checkbox: it cycles windows and reports where it landed.
        label = "Output window",
        action = function()
            local name = SYL.Output.CycleWindow()

            SYL:Print(
                "Messages now go to the \"" .. tostring(name) .. "\" window."
            )
        end,
        describe = function()
            return "Output window: " .. SYL.Output.GetWindowName()
        end,
    },
    {
        label = "Show debug messages",
        key = "debug",
    },
}

local function FeatureSectionTop()
    return ToggleSectionTop() - HEADING_HEIGHT
        - #TOGGLES * ROW_HEIGHT - NOTE_HEIGHT - SECTION_GAP
end

-- Where the dashboard widget section starts, and the shared section builder
-- it needs. Both are exported rather than duplicated: UI/SettingsWidgets.lua
-- owns that section, and this file still owns the geometry every section
-- shares. See the header there for why it is not a third block in here.
function SettingsRows.WidgetSectionTop()
    return FeatureSectionTop() - HEADING_HEIGHT
        - #SYL.Features.LIST * FEATURE_ROW_HEIGHT - SECTION_GAP
end

-- Returns the container and the heading. Callers that tear a section down
-- and build it again need both: the heading is a font string on the parent,
-- not a child of the container, so hiding the container alone left it behind
-- and every rebuild stacked another one in the same place.
function SettingsRows.AddSection(parent, title, offsetY)
    local container = AddSection(parent, title, offsetY)

    return container, container.heading
end

function SettingsRows.WindowHeight()
    local contentBottom =
        math.abs(SettingsRows.WidgetSectionTop())
        + SYL.SettingsWidgets.SectionHeight()

    return contentBottom + FOOTER_HEIGHT
end

function SettingsRows.BuildToggleSection(parent)
    local container = AddSection(parent, "BEHAVIOUR", ToggleSectionTop())

    container:SetHeight(#TOGGLES * ROW_HEIGHT)

    for index, toggle in ipairs(TOGGLES) do
        local isAction = toggle.action ~= nil

        local row = CreateSettingRow(
            container,
            index,

            -- An action row's label carries its current value, so it starts
            -- with that value rather than with a bare noun that changes into
            -- one the first time the window is drawn.
            toggle.describe and toggle.describe() or toggle.label,

            function()
                if toggle.action then
                    toggle.action()
                    SettingsRows.Refresh()

                    return
                end

                local settings = ShowUsYourLootDB.settings

                settings[toggle.key] = not settings[toggle.key]

                if toggle.onChanged then
                    toggle.onChanged(settings[toggle.key])
                end

                SettingsRows.Refresh()
            end,

            { isAction = isAction }
        )

        if not isAction then
            row.isChecked = function()
                return ShowUsYourLootDB.settings[toggle.key] and true or false
            end
        end

        if toggle.describe then
            row.describe = toggle.describe
        end

        table.insert(rows, row)
    end

    -- The one setting here that changes a number rather than a behaviour, and
    -- the only one whose default is a judgement call rather than an obvious
    -- choice. Saying why beats leaving an officer to discover it.
    local note = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

    local noteTop = ToggleSectionTop() - HEADING_HEIGHT
        - #TOGGLES * ROW_HEIGHT - 6

    note:SetPoint("TOPLEFT", 20, noteTop)
    note:SetPoint("TOPRIGHT", -20, noteTop)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetHeight(NOTE_HEIGHT)

    note:SetText(
        "Your client only sees other people's loot while you are grouped "
        .. "with them, so counting gear taken without a roll mostly counts "
        .. "yours."
    )
end

-- Whole features, switched on and off.
--
-- Taller rows than the toggles above, because each one carries a line saying
-- what it costs when it is on. A switch with no stated price is a guess, and
-- the point of this list is that somebody can decide rather than wonder.
function SettingsRows.BuildFeatureSection(parent)
    local container =
        AddSection(parent, "FEATURES", FeatureSectionTop())

    container:SetHeight(#SYL.Features.LIST * FEATURE_ROW_HEIGHT)

    for index, feature in ipairs(SYL.Features.LIST) do
        local row = CreateSettingRow(
            container,
            index,
            feature.label,
            function()
                local enabled = SYL.Features.Toggle(feature.key)

                SYL.Features.AnnounceReloadNeeded(feature, enabled)
                SettingsRows.Refresh()
            end,

            { height = FEATURE_ROW_HEIGHT }
        )

        -- Label to the top of a two-line row rather than centred on it.
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row.box, "TOPRIGHT", 8, 1)
        row.label:SetPoint("RIGHT", -4, 0)

        row.costText =
            Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")

        row.costText:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.costText:SetPoint("RIGHT", -4, 0)
        row.costText:SetJustifyH("LEFT")
        row.costText:SetWordWrap(true)
        row.costText:SetText(feature.cost or "")

        row.isChecked = function()
            return SYL.Features.IsEnabled(feature.key)
        end

        table.insert(rows, row)
    end
end
