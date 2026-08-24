-- UI/SettingsRows.lua
--
-- The contents of the settings window: the row widget, the quality list, the
-- behavior toggles, and how tall all of that is.
--
-- Split from UI/SettingsWindow.lua, which crossed the size limit the same way
-- RosterWindow did before it — by holding the chrome, the content and the
-- layout math at once. That file now opens a window; this one decides what is
-- in it.
--
-- ROWS ARE OF TWO KINDS AND HAVE TO LOOK IT. Most are checkboxes bound to a
-- saved setting. Two are not settings at all: the color scheme and the output
-- window cycle through values when pressed, and drawing those as checkboxes
-- meant drawing a box that could never be ticked.
--
-- syl-check: size-exempt — this is the row factory, the section helper, the
-- note measurer and the layout constants that decide where a section starts,
-- and every settings file in UI/ is built out of them. Splitting THOSE apart
-- would put the layout math in a different file from the thing it measures.
--
-- WHAT THE EXEMPTION NO LONGER COVERS. It used to say "three sections of one
-- window", and that stopped being true: the item types, the scoring numbers
-- and the tools list are each their own file now, built through the two
-- exports below, and the eight toggle declarations moved to
-- UI/SettingsToggles.lua. Anything that is a LIST rather than a mechanism
-- belongs outside this file. An exemption is not a licence, and this one has
-- been used to hold things it was not written for.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local ItemQuality = SYL.ItemQuality

local SettingsRows = {}
SYL.SettingsRows = SettingsRows

local ROW_HEIGHT = 20

-- Layout is derived from the content rather than hardcoded, so adding a
-- quality or a toggle cannot silently push the last row through the footer.
-- The first section sits just inside the scrolling area rather than 104px
-- below the window's own top. The title, subtitle and separator are drawn on
-- the window and do not scroll, so the content no longer has to leave room for
-- them — everything else derives from this, so the whole stack moved with it.
local QUALITY_TOP = -8
local HEADING_HEIGHT = 18
local NOTE_HEIGHT = 30
local SECTION_GAP = 24
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

    -- rowSmall in a grid, row when it is the only thing on the line. A column
    -- is a third of the width and the label was set at the size used for a
    -- full-width row, so it filled its cell and read as oversized.
    row.label = Theme.CreateText(
        row,
        columns > 1 and Theme.sizes.rowSmall or Theme.sizes.row,
        "textPrimary"
    )
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

-- THE ROW FACTORY AND THE REGISTRY, exported.
--
-- Three sections now live in files of their own -- the item types, the
-- scoring numbers and the tools list -- for the reason the header gives: this
-- file is already size-exempt and growing it to hold them would mean trimming
-- comments to fit, which has happened twice. They are still the same rows,
-- built by the same factory and refreshed from the same list, so a row in
-- another file cannot drift from a row in here.
--
-- Two exports rather than five: the factory, and the registry it feeds.
function SettingsRows.CreateRow(parent, index, labelText, onClick, options)
    return CreateSettingRow(parent, index, labelText, onClick, options)
end

function SettingsRows.Register(row)
    table.insert(rows, row)

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

    -- ONE REFRESH PATH. A number row has neither a tick nor a cycling label,
    -- so it keeps its own list rather than being made to look like a
    -- checkbox -- but it is refreshed from here, so nothing has to remember
    -- to call two things after changing a setting.
    if SYL.SettingsNumberRow then
        SYL.SettingsNumberRow.Refresh()
    end

    -- The Tools tab's scope row carries its current value in its label, so it
    -- goes stale the moment anything else changes the audience.
    if SYL.SettingsTools then
        SYL.SettingsTools.Refresh()
    end

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

-- `rightLabel` is the small muted word at the far end of a heading rule --
-- "NEW", "EDITABLE". It marks a section that has changed rather than
-- decorating one, and it is a font string on the parent like the heading is,
-- so a section that tears itself down takes it along.
local function AddSection(parent, title, offsetY, rightLabel)
    local heading =
        Theme.CreateText(parent, Theme.sizes.columnHeader, "textMuted")

    heading:SetPoint("TOPLEFT", 20, offsetY)
    heading:SetText(title)

    local marker

    if rightLabel then
        marker =
            Theme.CreateText(parent, Theme.sizes.columnHeader, "textMuted")

        marker:SetPoint("TOPRIGHT", -20, offsetY)
        marker:SetJustifyH("RIGHT")
        marker:SetText(rightLabel)
    end

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
    container.marker = marker

    return container
end

local function QualityBlockBottom()
    return QUALITY_TOP - HEADING_HEIGHT
        - SettingsRows.GridRows(#ItemQuality.ORDER, QUALITY_COLUMNS) * ROW_HEIGHT
end

local function ToggleSectionTop()
    return QualityBlockBottom() - NOTE_HEIGHT - SECTION_GAP
end

-- `top` overrides where the section starts.
--
-- Each builder used to derive its own top by stacking on the section above it,
-- which is right for one long page and wrong for tabs: on a tab, every section
-- starts from that tab's own top rather than from wherever the previous
-- section happened to end. Passing nothing keeps the old stacking, so the
-- change is invisible to anything that has not moved.
-- `options.suppressNote` leaves the closing paragraph off.
--
-- The Recording tab puts the item-type grid directly underneath this one and
-- says the same thing once for both -- "Unticked types and qualities are
-- never recorded" -- rather than printing two near-identical sentences a
-- section apart. Anything still building this section on its own keeps the
-- note it had.
function SettingsRows.BuildQualitySection(parent, top, options)
    options = options or {}

    top = top or QUALITY_TOP

    local container =
        AddSection(parent, "RECORD THESE ITEM QUALITIES", top)

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

    -- Heading and grid. A tab stacks the next section under this without
    -- measuring anything itself.
    local height = HEADING_HEIGHT
        + SettingsRows.GridRows(#ItemQuality.ORDER, QUALITY_COLUMNS)
        * ROW_HEIGHT

    if options.suppressNote then
        return container, height
    end

    -- DERIVED FROM `top`, NOT FROM QualityBlockBottom().
    --
    -- This used to be anchored at the constant, which is where the section
    -- sat on the old single scrolling column. It agreed with the Recording
    -- tab by two pixels of luck -- QUALITY_TOP is -8 and the tab's own top is
    -- -6 -- and it would have drifted the moment either moved. The toggle
    -- section had the same fault and was drawing its note 244px down every
    -- tab; see the note there.
    local note = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")
    local noteTop = top - height - 6

    note:SetPoint("TOPLEFT", 20, noteTop)
    note:SetPoint("TOPRIGHT", -20, noteTop)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetHeight(30)

    note:SetText(
        "Unticked qualities are never recorded. This does not remove records "
        .. "you already have."
    )

    return container, height + NOTE_HEIGHT
end

local function FeatureSectionTop()
    return ToggleSectionTop() - HEADING_HEIGHT
        - SettingsRows.GridRows(#SYL.SettingsToggles.LIST, TOGGLE_COLUMNS) * ROW_HEIGHT
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
function SettingsRows.AddSection(parent, title, offsetY, rightLabel)
    local container = AddSection(parent, title, offsetY, rightLabel)

    return container, container.heading
end

-- A paragraph under a section, and how tall it is.
--
-- MEASURED AND WRAPPED HERE RATHER THAN ASKED OF THE FRAME. A FontString
-- reports its own height as zero until a layout pass has run, and the test
-- client answers 100 to every getter, so a tab that sized itself off the
-- note it had just drawn would be wrong in the game and differently wrong in
-- the suite. Theme.MeasureText is the same ruler every column width in this
-- addon is measured with.
local NOTE_LINE = 14
local NOTE_PADDING = 8

-- The width a note has to wrap inside: the container's, which is the window
-- less the 20px inset on each side.
local function NoteWidth(parent)
    local width = parent and parent.GetWidth and parent:GetWidth()

    if type(width) ~= "number" or width <= 40 then
        return 512
    end

    return width - 40
end

function SettingsRows.NoteHeight(text, width)
    local size = Theme.sizes.rowSmall
    local lines, current = 1, ""

    for word in tostring(text):gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)

        if current ~= "" and Theme.MeasureText(size, candidate) > width then
            lines = lines + 1
            current = word
        else
            current = candidate
        end
    end

    return lines * NOTE_LINE + NOTE_PADDING
end

-- Returns the height it took, so a caller stacks the next thing under it
-- without measuring anything itself.
function SettingsRows.AddNote(parent, top, text, colorKey)
    local width = NoteWidth(parent)
    local height = SettingsRows.NoteHeight(text, width)

    local note =
        Theme.CreateText(parent, Theme.sizes.rowSmall, colorKey or "textMuted")

    note:SetPoint("TOPLEFT", 20, top)
    note:SetPoint("TOPRIGHT", -20, top)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetHeight(height - NOTE_PADDING)
    note:SetText(text)

    return height, note
end

-- The title, subtitle and separator above the scrolling area, and the rule and
-- Close button below it. Both are drawn on the window and neither scrolls.
local CHROME_HEIGHT = 124

-- How tall the CONTENT is — the part that scrolls, and nothing else.
--
-- This used to add FOOTER_HEIGHT, which is the footer drawn on the window
-- rather than inside the scroll frame. The scroll child was therefore 60px
-- taller than anything in it, so the window scrolled past the end of its own
-- content with no bar to explain why: a phantom scroll.
function SettingsRows.ContentHeight()
    return math.abs(SettingsRows.WidgetSectionTop())
        + SYL.SettingsWidgets.SectionHeight()
        + 8
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
    -- The content plus the chrome it sits between, so a window that fits shows
    -- everything and scrolls nowhere.
    local wanted = SettingsRows.ContentHeight() + CHROME_HEIGHT

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
    return SettingsRows.ContentHeight()
        > (SettingsRows.WindowHeight() - CHROME_HEIGHT) + 1
end

-- ONE TAB'S WORTH OF TOGGLES, not all eight.
--
-- The rows under BEHAVIOR were never one subject: the rank floor is scoring,
-- the color scheme and the minimap button are display, capture and announcing
-- are recording, and resetting window sizes is what you click when something
-- has gone wrong. They shared a heading because a single scrolling column had
-- nowhere else to put them.
--
-- Called with no tab it builds all eight under the old heading, so anything
-- that has not moved to a tab yet is unaffected.
-- `options` is { columns = n, extraRows = n }.
--
-- COLUMNS, because two across is right for a tab holding four short toggles
-- and wrong for the Scoring tab, where a row is a sentence with a number
-- beside it. extraRows reserves lines at the bottom of the container so a
-- caller can put its own rows there and still get one honest height back --
-- the alternative was returning the row count and making every caller redo
-- the same arithmetic, which is how two files come to disagree about how
-- tall a section is.
function SettingsRows.BuildToggleSection(parent, top, tab, title, options)
    options = options or {}

    local wanted = {}

    for _, toggle in ipairs(SYL.SettingsToggles.LIST) do
        if not tab or toggle.tab == tab then
            table.insert(wanted, toggle)
        end
    end

    if #wanted == 0 then
        return nil
    end

    local container = AddSection(
        parent, title or "BEHAVIOR", top or ToggleSectionTop()
    )

    local columns = options.columns or TOGGLE_COLUMNS
    local lines = SettingsRows.GridRows(#wanted, columns)
        + (options.extraRows or 0)

    container:SetHeight(lines * ROW_HEIGHT)

    for index, toggle in ipairs(wanted) do
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

            { isAction = isAction, columns = columns }
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

    -- THIS NOTE WAS BEING DRAWN ON EVERY TAB, at an offset computed for the
    -- single column that no longer exists.
    --
    -- ToggleSectionTop() is where the BEHAVIOR block sat on the old scrolling
    -- page, so noteTop came to -244 -- and each of the four tabs that build a
    -- toggle section drew its own copy of this sentence 244px down its own
    -- page, through whatever was there. It shipped in 7efaad7 with the tabs
    -- themselves, because the tabbed path was given a `top` and this was the
    -- one thing in the function that ignored it.
    --
    -- Only the untabbed path draws it now, and only the untabbed path adds
    -- NOTE_HEIGHT for it. The sentence itself is not lost: it is about what
    -- the client can and cannot see, so UI/SettingsItemTypes.lua says it
    -- under CAPTURE, which is where somebody reading about recording is.
    if not tab then
        local note =
            Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

        local noteTop = ToggleSectionTop() - HEADING_HEIGHT
            - SettingsRows.GridRows(#SYL.SettingsToggles.LIST, TOGGLE_COLUMNS) * ROW_HEIGHT - 6

        note:SetPoint("TOPLEFT", 20, noteTop)
        note:SetPoint("TOPRIGHT", -20, noteTop)
        note:SetWordWrap(true)
        note:SetJustifyH("LEFT")
        note:SetHeight(NOTE_HEIGHT)

        note:SetText(SYL.SettingsToggles.PERSONAL_LOOT_NOTE)
    end

    return container, HEADING_HEIGHT + lines * ROW_HEIGHT
        + (tab and 0 or NOTE_HEIGHT), #wanted
end

-- Whole features, switched on and off.
--
-- Taller rows than the toggles above, because each one carries a line saying
-- what it costs when it is on. A switch with no stated price is a guess, and
-- the point of this list is that somebody can decide rather than wonder.
function SettingsRows.BuildFeatureSection(parent, top)
    local container =
        AddSection(parent, "FEATURES", top or FeatureSectionTop())

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

    return container, HEADING_HEIGHT
        + SettingsRows.GridRows(#SYL.Features.LIST, FEATURE_COLUMNS)
        * ROW_HEIGHT
end
