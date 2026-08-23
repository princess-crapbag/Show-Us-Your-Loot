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

function BUILDERS.recording(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildQualitySection(page, y)

    y = y - height - SECTION_GAP

    local _, toggles = SettingsRows.BuildToggleSection(
        page, y, "recording", "CAPTURE"
    )

    return -(y - (toggles or 0)) + TAB_BOTTOM
end

function BUILDERS.scoring(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildToggleSection(
        page, y, "scoring", "FAIRNESS"
    )

    return -(y - (height or 0)) + TAB_BOTTOM
end

function BUILDERS.features(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildFeatureSection(page, y)

    return -(y - height) + TAB_BOTTOM
end

function BUILDERS.display(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildToggleSection(
        page, y, "display", "APPEARANCE"
    )

    y = y - (height or 0) - SECTION_GAP

    local _widgets, widgets =
        SYL.SettingsWidgets.Build(page, y, SettingsRows.AddSection)

    return -(y - (widgets or 0)) + TAB_BOTTOM
end

function BUILDERS.tools(page)
    local y = TAB_TOP

    local _, height = SettingsRows.BuildToggleSection(
        page, y, "tools", "IF SOMETHING GOES WRONG"
    )

    return -(y - (height or 0)) + TAB_BOTTOM
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

    function tabs:Tallest()
        local most = 0

        for _, height in pairs(self.heights) do
            most = math.max(most, height)
        end

        return most
    end

    return tabs
end
