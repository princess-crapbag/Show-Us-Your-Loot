-- UI/SettingsRows.lua
--
-- The contents of the settings window: the row widget, the quality list, the
-- behavior toggles, and how tall all of that is.
--
-- Split from UI/SettingsWindow.lua, which crossed the size limit the same way
-- RosterWindow did before it — by holding the chrome, the content and the
-- layout maths at once. That file now opens a window; this one decides what is
-- in it.
--
-- ROWS ARE OF TWO KINDS AND HAVE TO LOOK IT. Most are checkboxes bound to a
-- saved setting. Two are not settings at all: the color scheme and the output
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
-- The first section sits just inside the scrolling area rather than 104px
-- below the window's own top. The title, subtitle and separator are drawn on
-- the window and do not scroll, so the content no longer has to leave room for
-- them — everything else derives from this, so the whole stack moved with it.
local QUALITY_TOP = -8
local HEADING_HEIGHT = 18
local NOTE_HEIGHT = 30
local SECTION_GAP = 30
local FOOTER_HEIGHT = 60
-- Three across. Nine features one per line was 342px of a window that has to
-- fit on a monitor alongside everything else.
local FEATURE_COLUMNS = 3
local QUALITY_COLUMNS = 3

-- Two, not three: these labels are sentences rather than names, and an action
-- row carries its current value in the label as well.
local TOGGLE_COLUMNS = 2

local rows = {}

-- Quality colors come from the client so they match the item names in the
-- list views rather than an approximation of them.
--
-- RESOLVED AT CALL TIME, NOT AT LOAD. Read once into an upvalue, a client that
-- exposes neither spelling left this nil — and calling a nil threw on the
-- first quality row, which killed the whole section and left the settings
-- window showing one heading and nothing else. Two different faults produced
-- that same empty screen; this was the second.
--
-- Falls back to the color table and then to plain white, because a row whose
-- text is the wrong color is a cosmetic complaint and a settings window that
-- will not build is not.
local function QualityColor(quality)
    local lookup = (C_Item and C_Item.GetItemQualityColor)
        or _G.GetItemQualityColor

    if lookup then
        local ok, red, green, blue = pcall(lookup, quality)

        if ok and red then
            return red, green, blue
        end
    end

    local colors = _G.ITEM_QUALITY_COLORS

    if colors and colors[quality] then
        local color = colors[quality]

        return color.r, color.g, color.b
    end

    return nil
end

-- How many rows a list of `count` takes at `columns` across. Every section
-- that lays out in a grid measures its own height with this, so a section
-- cannot disagree with the window about how tall it is.
function SettingsRows.GridRows(count, columns)
    return math.ceil(count / math.max(1, columns or 1))
end

local function CreateSettingRow(parent, index, labelText, onClick, options)
    options = options or {}

    local row = CreateFrame("Button", nil, parent)
    local height = options.height or ROW_HEIGHT
    local isAction = options.isAction

    -- COLUMNS, because a settings screen that is taller than the monitor is
    -- one where the last section cannot be reached. Nine features stacked one
    -- per line is 342px of window; three across is 72. The width comes off the
    -- container rather than a constant so the two cannot drift.
    local columns = math.max(1, options.columns or 1)

    row:SetHeight(height)

    if columns == 1 then
        row:SetPoint("TOPLEFT", 0, -((index - 1) * height))
        row:SetPoint("TOPRIGHT", 0, -((index - 1) * height))
    else
        local column = (index - 1) % columns
        local line = math.floor((index - 1) / columns)
        local width = (parent:GetWidth() or 360) / columns

        row:SetWidth(width - 6)
        row:SetPoint("TOPLEFT", column * width, -(line * height))
    end

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

    local container = CreateFrame("Frame", nil, parent)

    container:SetPoint("TOPLEFT", 20, offsetY - 18)
    container:SetPoint("TOPRIGHT", -20, offsetY - 18)

    -- Kept on the container so a section that tears itself down can take its
    -- heading with it. The heading is parented to the window, not to the
    -- container, so hiding the container alone leaves it behind.
    --
    -- THIS LINE WAS ABOVE THE DECLARATION and `container` was therefore a nil
    -- global, so AddSection threw on its first call. The window drew its first
    -- heading and then nothing at all — no qualities, no toggles, no features —
    -- and looked like an empty settings screen rather than a crash.
    --
    -- It is the third time a local-used-before-declaration has shipped here.
    -- syl_check cannot see it: it is not an SYL.Module.Member reference and not
    -- a bare module global, so neither rule applies. luacheck is the tool that
    -- catches this class and it is still the open tooling item in HANDOFF.md.
    container.heading = heading

    return container
end

local function QualityBlockBottom()
    return QUALITY_TOP - HEADING_HEIGHT
        - SettingsRows.GridRows(#ItemQuality.ORDER, QUALITY_COLUMNS) * ROW_HEIGHT
end

local function ToggleSectionTop()
    return QualityBlockBottom() - NOTE_HEIGHT - SECTION_GAP
end

function SettingsRows.BuildQualitySection(parent)
    local container =
        AddSection(parent, "RECORD THESE ITEM QUALITIES", QUALITY_TOP)

    container:SetHeight(
        SettingsRows.GridRows(#ItemQuality.ORDER, QUALITY_COLUMNS) * ROW_HEIGHT
    )

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
            end,

            { columns = QUALITY_COLUMNS }
        )

        local red, green, blue = QualityColor(quality)

        -- The whole point of this row is that it is the color it names, so
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
        -- reading color names and guessing.
        label = "Color scheme",
        action = function()
            local palette =
                SYL.Theme.Apply(SYL.Palettes.Next(SYL.Theme.paletteKey))

            SYL:Print(
                "Color scheme: " .. palette.name .. " — " .. palette.note .. "."
            )
        end,
        describe = function()
            local palette = SYL.Theme.Current()

            return "Color scheme: " .. (palette and palette.name or "unknown")
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
        -- user's loot chat with grays after a Mythic+ run.
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
        - SettingsRows.GridRows(#TOGGLES, TOGGLE_COLUMNS) * ROW_HEIGHT
        - NOTE_HEIGHT - SECTION_GAP
end

-- Where the dashboard widget section starts, and the shared section builder
-- it needs. Both are exported rather than duplicated: UI/SettingsWidgets.lua
-- owns that section, and this file still owns the geometry every section
-- shares. See the header there for why it is not a third block in here.
function SettingsRows.WidgetSectionTop()
    return FeatureSectionTop() - HEADING_HEIGHT
        - SettingsRows.GridRows(#SYL.Features.LIST, FEATURE_COLUMNS) * ROW_HEIGHT
        - SECTION_GAP
end

-- Returns the container and the heading. Callers that tear a section down
-- and build it again need both: the heading is a font string on the parent,
-- not a child of the container, so hiding the container alone left it behind
-- and every rebuild stacked another one in the same place.
function SettingsRows.AddSection(parent, title, offsetY)
    local container = AddSection(parent, title, offsetY)

    return container, container.heading
end

-- How tall the content wants to be, which is not the same as how tall the
-- window may be.
function SettingsRows.ContentHeight()
    local contentBottom =
        math.abs(SettingsRows.WidgetSectionTop())
        + SYL.SettingsWidgets.SectionHeight()

    return contentBottom + FOOTER_HEIGHT
end

-- Never taller than the screen it has to fit on.
--
-- This used to return the content height and nothing else, which was fine
-- while the content was short. Every feature added since is another 38px, and
-- the window quietly grew past the bottom of a 1080p screen — the answer to
-- "why is settings cut off" was that it was 1300 pixels tall and honest about
-- it. The content scrolls now, so this is a window size rather than a total.
local MIN_HEIGHT = 320
local SCREEN_MARGIN = 80

function SettingsRows.WindowHeight()
    local wanted = SettingsRows.ContentHeight()

    local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()

    if not screen or screen <= 1 then
        return wanted
    end

    local allowed = math.max(MIN_HEIGHT, screen - SCREEN_MARGIN)

    return math.min(wanted, math.floor(allowed))
end

-- Whether the content is taller than the window can be, which is what decides
-- if a scroll bar is worth drawing at all.
function SettingsRows.NeedsScrolling()
    return SettingsRows.ContentHeight() > SettingsRows.WindowHeight() + 1
end

function SettingsRows.BuildToggleSection(parent)
    local container = AddSection(parent, "BEHAVIOR", ToggleSectionTop())

    container:SetHeight(
        SettingsRows.GridRows(#TOGGLES, TOGGLE_COLUMNS) * ROW_HEIGHT
    )

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

            { isAction = isAction, columns = TOGGLE_COLUMNS }
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

    -- The one setting here that changes a number rather than a behavior, and
    -- the only one whose default is a judgement call rather than an obvious
    -- choice. Saying why beats leaving an officer to discover it.
    local note = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

    local noteTop = ToggleSectionTop() - HEADING_HEIGHT
        - SettingsRows.GridRows(#TOGGLES, TOGGLE_COLUMNS) * ROW_HEIGHT - 6

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

    container:SetHeight(
        SettingsRows.GridRows(#SYL.Features.LIST, FEATURE_COLUMNS) * ROW_HEIGHT
    )

    for index, feature in ipairs(SYL.Features.LIST) do
        local row = CreateSettingRow(
            container,
            index,
            feature.short or feature.label,
            function()
                local enabled = SYL.Features.Toggle(feature.key)

                SYL.Features.AnnounceReloadNeeded(feature, enabled)
                SettingsRows.Refresh()
            end,

            { columns = FEATURE_COLUMNS }
        )

        -- THE COST MOVED TO A TOOLTIP. It used to be a second line under every
        -- feature, which is what made each row 38px and the section 342 — the
        -- single largest thing pushing the window off the bottom of the
        -- screen. It is still one hover away, and it is read once rather than
        -- every time somebody opens settings for a different reason.
        SYL.Tooltips.Attach(row, feature.label, feature.cost or "")

        row.isChecked = function()
            return SYL.Features.IsEnabled(feature.key)
        end

        table.insert(rows, row)
    end
end
