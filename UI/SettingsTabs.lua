-- UI/SettingsTabs.lua
--
-- The settings window's five tabs: which sections live on each, and how tall
-- each one is.
--
-- WHY TABS. Everything was one 656px column and the order in it was the order
-- things happened to be built in, so the rank floor -- the number that decides
-- who is ranked at all -- sat between "record group loot" and "show the
-- minimap button". Aimee, looking at a drawing of this: "i love it."
--
-- FIVE, AND WHAT DECIDES WHICH. Recording is what gets written down, Scoring
-- is the numbers the boards argue about, Features is what runs at all, Display
-- is look and noise, Tools is everything you go looking for rather than set
-- once. The eight rows that used to share a BEHAVIOR heading are spread across
-- four of those, because they were never one subject -- see the tab field on
-- each of them in UI/SettingsRows.lua.
--
-- THE WINDOW RESIZES PER TAB rather than standing at the tallest. Features is
-- 296 and Tools is 610; holding every tab at 610 would leave Features with
-- 300px of nothing under it, which reads as a screen that failed to load.
--
-- Heights are computed from what each section reports, never measured off a
-- frame: a frame asked for its height before a layout pass answers something
-- else entirely, and the test client answers 100 to everything.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SettingsTabs = {}
SYL.SettingsTabs = SettingsTabs

local SettingsRows = SYL.SettingsRows

local SECTION_GAP = 24

-- Where the first section starts inside a tab, and what the tab needs under
-- its last one before the footer rule.
local TAB_TOP = -6
local TAB_BOTTOM = 16

SettingsTabs.DEFINITIONS = {
    { key = "recording", label = "Recording" },
    { key = "scoring", label = "Scoring" },
    { key = "features", label = "Features" },
    { key = "display", label = "Display" },
    { key = "tools", label = "Tools" },
}

--------------------------------------------------------------------------
-- Building one tab
--------------------------------------------------------------------------

-- Each builder is handed the tab's own frame and returns how tall it made it.
-- They stack sections themselves rather than being told where to put them,
-- because only the builder knows what it drew.
local BUILDERS = {}

-- A tab's own top and bottom padding, applied once here so no builder has to
-- know them. Every builder returns the height of what it drew and nothing
-- else.
local function TabHeight(content)
    return -TAB_TOP + (content or 0) + TAB_BOTTOM
end

-- The gap between a paragraph and the heading under it. Smaller than
-- SECTION_GAP because SettingsRows.AddNote already carries its own padding,
-- and stacking both leaves a hole that reads as a missing section.
local NOTE_GAP = 6

function BUILDERS.recording(page)
    local y = TAB_TOP

    -- The quality grid keeps its note to itself only when nothing follows it.
    -- Here the item-type grid does, and one paragraph speaks for both: the
    -- two filters have exactly the same non-retroactive contract, and two
    -- near-identical sentences a section apart is how they come to disagree.
    local _, quality =
        SettingsRows.BuildQualitySection(page, y, { suppressNote = true })

    y = y - quality - SECTION_GAP

    local _types, types = SYL.SettingsItemTypes.Build(page, y)

    y = y - types - 4

    local shared =
        SettingsRows.AddNote(page, y, SYL.SettingsItemTypes.SHARED_NOTE)

    y = y - shared - NOTE_GAP

    local _capture, capture = SettingsRows.BuildToggleSection(
        page, y, "recording", "CAPTURE"
    )

    y = y - (capture or 0) - 4

    local personal =
        SettingsRows.AddNote(page, y, SYL.SettingsToggles.PERSONAL_LOOT_NOTE)

    -- TAB_TOP - y is everything stacked so far, because y walks down from
    -- TAB_TOP. Written that way rather than by keeping a running total,
    -- so the height cannot disagree with where the last thing was put.
    return TabHeight(TAB_TOP - y + personal)
end

function BUILDERS.scoring(page)
    return TabHeight(SYL.SettingsScoring.Build(page, TAB_TOP))
end

function BUILDERS.features(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildFeatureSection(page, y)

    y = y - height - 4

    local note = SettingsRows.AddNote(
        page,
        y,
        "Sharing switches send to your guild. Everything you receive can be "
        .. "cleared from the screen it arrived on. Most need a /reload."
    )

    return TabHeight(height + 4 + note)
end

function BUILDERS.display(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildToggleSection(
        page, y, "display", "APPEARANCE"
    )

    y = y - (height or 0) - 4

    -- THE ONE SENTENCE THAT HAD TO BE ON THIS TAB. The minimap button is a
    -- checkbox two rows above it, and turning it off is what strands about
    -- thirteen commands -- UI/SettingsTools.lua has the count. Somebody
    -- switching it off should meet that before they do, not afterwards.
    local note = SettingsRows.AddNote(
        page,
        y,
        "The minimap button is the door to the command menu. Turning it off "
        .. "leaves the Tools tab as the only way to click most of them."
    )

    y = y - note - NOTE_GAP

    local _widgets, widgets =
        SYL.SettingsWidgets.Build(page, y, SettingsRows.AddSection)

    return TabHeight(TAB_TOP - y + (widgets or 0))
end

function BUILDERS.tools(page)
    local y = TAB_TOP

    local height = SYL.SettingsTools.Build(page, y)

    y = y - height - SECTION_GAP

    -- The one toggle that belongs here rather than in the command list: it is
    -- a saved setting, not an act. UI/SettingsRows.lua owns its wording.
    local _, toggles = SettingsRows.BuildToggleSection(
        page, y, "tools", "IF SOMETHING GOES WRONG"
    )

    return TabHeight(height + SECTION_GAP + (toggles or 0))
end

--------------------------------------------------------------------------
-- The set of them
--------------------------------------------------------------------------

function SettingsTabs.Create(parent, width, top)
    local tabs = { pages = {}, heights = {}, width = width }

    for _, definition in ipairs(SettingsTabs.DEFINITIONS) do
        local page = CreateFrame("Frame", nil, parent)

        page:SetPoint("TOPLEFT", 0, -top)
        page:SetPoint("TOPRIGHT", 0, -top)
        page:SetHeight(1)
        page:Hide()

        tabs.heights[definition.key] = BUILDERS[definition.key](page)
        tabs.pages[definition.key] = page
    end

    -- SHOWN AND HIDDEN AS A WHOLE. A section's heading is parented to the page
    -- rather than to its container -- see AddSection -- so hiding a container
    -- alone would leave its heading floating over the next tab.
    function tabs:Select(key)
        for name, page in pairs(self.pages) do
            page:SetShown(name == key)
        end

        self.active = key
    end

    function tabs:HeightOf(key)
        return self.heights[key] or 0
    end

    -- THE SCORING TAB CHANGES HEIGHT WHILE IT IS OPEN. Breaking the offspec
    -- link adds a fourth weight row, so the tab is 20px taller with it -- and
    -- the window is sized from a number cached at build time. This is how
    -- that number gets corrected, and how the window is told to re-apply it.
    SYL.SettingsScoring.onHeightChanged = function(content)
        tabs.heights.scoring = TabHeight(content)

        if tabs.onResize then
            tabs.onResize()
        end
    end

    function tabs:Tallest()
        local most = 0

        for _, height in pairs(self.heights) do
            most = math.max(most, height)
        end

        return most
    end

    return tabs
end
