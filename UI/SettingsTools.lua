-- UI/SettingsTools.lua
--
-- The Tools tab: every /syl command as something you click, grouped by what
-- you came looking for rather than by the alphabet.
--
-- THIS IS A SECOND DOOR, NOT A NEW ONE, and it is worth building anyway.
-- UI/CommandMenu.lua already draws 30 of the 34 entries off the minimap
-- right-click -- but the minimap button is a checkbox in these very settings,
-- on by default, and turning it off strands about thirteen commands with no
-- click anywhere in the addon. An inventory of all 34 against the whole UI
-- tree found the set reachable by no click at all is exactly {dev, api}, both
-- developer-only, and that holds only while that checkbox is ticked.
--
-- FOUR TRAPS THIS TAB HAD TO BE BUILT AROUND. They are why the rows below
-- carry a `run` of their own instead of all going through CommandList.Run:
--
--   /syl bosses does NOT open the Bosses tab -- it opens the standalone
--   UI/BossWindow.lua. Same for roster, which opens RosterWindow rather than
--   the Raiders board. A row wired to the command string reopens a legacy
--   window in front of the tab somebody is already looking at.
--
--   /syl due prints to chat unless you append `window`.
--
--   /syl scope has no click door anywhere in the addon, and it is the
--   setting the due and players windows both read. Building this tab exactly
--   as drawn would still have left the house rule broken, so it is here and
--   it carries its current value in the label.
--
--   /syl clear destroys a season. It is NOT in this list -- see the danger
--   block at the bottom and UI/ClearSeasonDialog.lua.
--
-- CommandList.ENTRIES IS NOT THE WHOLE COMMAND SURFACE either: `archive
-- rename`, `archive merge`, `due window`, `sync backfill`, `help all` and
-- `archives <n>` all dispatch and are in none of the 34. That is why this
-- file holds its own list rather than walking that one.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SettingsTools = {}
SYL.SettingsTools = SettingsTools

-- The settings window is 560 and every section is inset 20 on each side.
local CONTENT_WIDTH = 520

local ROW_HEIGHT = 18
local HEADING_HEIGHT = 16
local GROUP_GAP = 10
local COLUMNS = 2

--------------------------------------------------------------------------
-- Drawing them
--------------------------------------------------------------------------

local rows = {}

function SettingsTools.Refresh()
    for _, row in ipairs(rows) do
        if type(row.entry.label) == "function" then
            row.label:SetText(row.entry.label())
        end
    end
end

local function CreateRow(parent, entry, x, y, width)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", x, y)
    row:SetWidth(width)

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.label = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.label:SetText(
        type(entry.label) == "function" and entry.label() or entry.label
    )

    -- The ellipsis says this one asks for something before it does anything,
    -- which is the difference between a row that acts on the press and a row
    -- that opens a box. Same convention as a menu item in any application.
    if entry.needsInput then
        row.ellipsis =
            Theme.CreateText(row, Theme.sizes.columnHeader, "textMuted")

        row.ellipsis:SetPoint("RIGHT", -8, 0)
        row.ellipsis:SetText("...")

        row.label:SetPoint("RIGHT", row.ellipsis, "LEFT", -6, 0)
    else
        row.label:SetPoint("RIGHT", -8, 0)
    end

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", function()
        entry.run()

        -- The scope row rewrites its own label, and anything that opened a
        -- window may have changed a setting this tab shows.
        SettingsTools.Refresh()
    end)

    if entry.note then
        SYL.Tooltips.Attach(
            row,
            type(entry.label) == "function" and entry.label() or entry.label,
            entry.note
        )
    end

    row.entry = entry
    table.insert(rows, row)

    return row
end

-- Two columns, each stacking independently -- which is the arrangement in the
-- approved drawing and the reason the Tools tab fits on a screen at all.
-- Twenty-four rows one per line is 430px before the danger block.
--
-- PACKED INTO THE SHORTER COLUMN, NOT ALTERNATED BY INDEX.
--
-- Alternating is what the drawing did and it is right only while the groups
-- are the same size. They are not: OPEN A SCREEN is nine rows and IF
-- SOMETHING GOES WRONG is one, and every odd-numbered group landing in the
-- same column put eighteen rows on the left against eight on the right --
-- ninety wasted pixels of window and a right-hand column that stopped
-- halfway, which reads as a list that failed to finish drawing.
--
-- The order within a column is still the order of the list, so nothing jumps
-- around; only which column a group lands in is decided by height.
local function BuildGroups(container, width)
    local columnWidth = width / COLUMNS
    local tops = { 0, 0 }
    local bottom = 0

    for _, group in ipairs(SYL.SettingsToolsList.GROUPS) do
        local column = tops[1] <= tops[2] and 0 or 1
        local x = column * columnWidth
        local y = tops[column + 1]

        local heading =
            Theme.CreateText(container, Theme.sizes.columnHeader, "textMuted")

        heading:SetPoint("TOPLEFT", x, -y)
        heading:SetText(group.title)

        y = y + HEADING_HEIGHT

        for _, entry in ipairs(group.entries) do
            CreateRow(container, entry, x, -y, columnWidth - 10)
            y = y + ROW_HEIGHT
        end

        tops[column + 1] = y + GROUP_GAP
        bottom = math.max(bottom, tops[column + 1])
    end

    return bottom
end

--------------------------------------------------------------------------
-- The danger block
--------------------------------------------------------------------------

-- NOT A ROW IN THE LIST ABOVE, and that is the whole point.
--
-- Aimee: "dont make it a normal button. or make it harder to do. make sure
-- there is an explanation as to why someone should use this button and what
-- will happen if they do. maybe have a danger image near it."
--
-- So: below everything, under its own rule, beside the client's own alert
-- icon, in the warning color, with two sentences in the shortest words that
-- carry the meaning -- and it opens a dialog that will not act until the
-- season's name has been typed. UI/ClearSeasonDialog.lua holds the rest of
-- the reasoning and the other three guards.
local DANGER_ICON = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

local DANGER_NOTE =
    "This throws away everything the addon has written down for the season "
    .. "you are raiding now, and you cannot get it back. Use it only if it "
    .. "recorded a lot you did not want. If the season is just over, use "
    .. "Archive and start new above -- that keeps everything."

local function BuildDanger(page, top)
    local rule = Theme.CreateSeparator(page, "warning")
    rule:SetPoint("TOPLEFT", 20, top)
    rule:SetPoint("TOPRIGHT", -20, top)

    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DANGER_ICON)
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 20, top - 12)

    local heading = Theme.CreateText(page, Theme.sizes.columnHeader, "warning")
    heading:SetPoint("TOPLEFT", 52, top - 16)
    heading:SetText("ERASING A SEASON CANNOT BE UNDONE")

    local link = CreateFrame("Button", nil, page)

    link:SetPoint("TOPLEFT", 50, top - 30)
    link:SetSize(220, 20)

    link.highlight = Theme.CreateSolidTexture(link, "rowHover", "BACKGROUND")
    link.highlight:SetAllPoints()
    link.highlight:Hide()

    link.label = Theme.CreateText(link, Theme.sizes.rowSmall, "warning")
    link.label:SetPoint("LEFT", 4, 0)
    link.label:SetText("Erase this season's records...")

    link:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    link:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    link:SetScript("OnClick", function()
        SYL.ClearSeasonDialog.Show()
    end)

    SYL.Tooltips.Attach(
        link,
        "Erase this season's records",
        DANGER_NOTE
    )

    -- Inset past the icon on the left, so it wraps at 488 rather than 520.
    local noteHeight = SYL.SettingsRows.NoteHeight(DANGER_NOTE, 488)

    local note = Theme.CreateText(page, Theme.sizes.rowSmall, "textMuted")
    note:SetPoint("TOPLEFT", 52, top - 54)
    note:SetPoint("TOPRIGHT", -20, top - 54)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetHeight(noteHeight)
    note:SetText(DANGER_NOTE)

    return 54 + noteHeight + 8
end

--------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------

local INTRO =
    "Every one of these also has a slash command. The command is the "
    .. "shortcut; this is how anybody else finds it."

-- Returns the content height. UI/SettingsTabs.lua turns it into a window
-- height.
function SettingsTools.Build(page, top)
    rows = {}

    local y = top
    local introHeight = SYL.SettingsRows.AddNote(page, y, INTRO)

    y = y - introHeight

    local container = CreateFrame("Frame", nil, page)

    container:SetPoint("TOPLEFT", 20, y)
    container:SetPoint("TOPRIGHT", -20, y)

    -- The container is anchored at 20 and -20 inside a 560px window, so it is
    -- 520 wide. Taken as a constant rather than read off the frame because a
    -- frame answers 100 to GetWidth in the test client and nothing at all
    -- before its first layout pass -- the same reason every height on these
    -- tabs is computed rather than measured.
    local groupsHeight = BuildGroups(container, CONTENT_WIDTH)

    container:SetHeight(groupsHeight)

    y = y - groupsHeight - 8

    local dangerHeight = BuildDanger(page, y)

    return introHeight + groupsHeight + 8 + dangerHeight
end
