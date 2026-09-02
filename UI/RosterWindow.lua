-- UI/RosterWindow.lua
--
-- Who could be brought, what they play, and which raid buffs nobody covers.
--
-- The players window answers questions about people who have already raided.
-- This one is about who *could* — the guild roster knows the class of every
-- member whether or not this addon has seen them loot anything, which makes
-- "we have no Mage" answerable before the raid rather than after.
--
-- Guild rank cannot say who raids. Officers who do not raid hold the highest
-- rank and trials who do hold the lowest, so team membership and role are
-- marked by hand and kept on the player registry. Drawing a row lives in
-- UI/RosterRows.lua; this file decides who is on the list.
--
-- Missing buffs are named rather than counted. "7 of 9 covered" is the wrong
-- shape of answer: the useful part is which two.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local WINDOW_WIDTH = 900
local ROW_HEIGHT = 22
local DEFAULT_ROWS = 14
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

-- Clear space between the bottom of the filter strip and the top of the column
-- header. This is the only number here anybody chose.
local HEADER_GAP = 12

-- DERIVED, NOT CHOSEN — see the note in UI/RosterControls.lua for what the
-- chosen version cost. The list begins below the strip, below the gap, and
-- below the header SortHeader draws for us; asking each of them how much room
-- they take is the only version of this that cannot silently overlap.
--
-- Widgets.CreateListWindow sizes the window as listTop + rows*rowHeight +
-- footer, so moving this down makes the window taller rather than costing a
-- row. Fourteen rows still fit.
local LIST_TOP = SYL.RosterControls.STRIP_BOTTOM
    + HEADER_GAP
    + SYL.SortHeader.HEIGHT
    + SYL.SortHeader.LIST_GAP

local visibleRows = DEFAULT_ROWS

-- SELECT is a checkbox, ROLE and TEAM are clicked rather than read, so each
-- gets a hit area of its own.
local COLUMNS = {
    -- Not sortable: it is a tickbox, it has no label to click, and there is
    -- nothing to order a roster by.
    { key = "select", label = "", width = 20, gap = 10, sortable = false },
    { key = "name", label = "NAME", width = 140, gap = 8 },
    { key = "class", label = "CLASS", width = 110, gap = 8 },
    { key = "role", label = "ROLE", width = 74, gap = 8 },
    { key = "team", label = "TEAM", width = 56, gap = 8 },
    { key = "main", label = "ALT OF", width = 100, gap = 8 },
    { key = "rank", label = "GUILD RANK", width = 96, gap = 8 },
    { key = "nights", label = "NIGHTS", width = 56, gap = 8 },
    { key = "score", label = "M+", width = 48, gap = 8 },
}

local frame
local rows = {}
local offset = 0
local header
-- Opens on the raid team. The window exists to plan a night, and a list of
-- four hundred guild members is the thing you widen to occasionally rather
-- than the thing you start from.
local teamOnly = true
-- Hides characters nobody has logged into for a month. On by default: a
-- roster is a list of people you could bring, and a name that has not been
-- seen since the last tier is not one. See RosterData.ActiveOnly.
local activeOnly = true
-- The size of the last list drawn, so the scrollbar knows its range without
-- rebuilding the roster every time it asks.
local lastTotal = 0
-- The whole roster before the team filter, the search and the sort — which is
-- what the bulk actions have to read. See SelectedEntries.
local lastFullRoster = {}

local sortKey = "name"
local sortReversed = false
local searchText = ""

local columnOffset = {}
local columnWidth = {}

do
    local x = 0

    for _, column in ipairs(COLUMNS) do
        x = x + column.gap
        columnOffset[column.key] = x
        columnWidth[column.key] = column.width
        x = x + column.width
    end
end

local Refresh

-- Refresh redraws from the cached roster, which is what makes typing in the
-- search box cheap. Rebuild is for the handful of actions that change what
-- the roster *is* — mapping an alt, or the guild roster arriving.
local function Rebuild()
    SYL.RosterData.Invalidate()

    Refresh()
end

-- Checked characters, keyed by GUID. Survives sorting and searching, so you
-- can find three people by name one at a time and act on all of them.
local selected = {}
local selectedCount = 0

local function SetSelected(entry, isSelected)
    local was = selected[entry.guid] and true or false

    if was == isSelected then
        return
    end

    selected[entry.guid] = isSelected or nil
    selectedCount = selectedCount + (isSelected and 1 or -1)

    Refresh()
end

local function ClearSelection()
    selected = {}
    selectedCount = 0
end

-- The checked entries, rebuilt from the roster so callers get names and
-- classes rather than bare GUIDs.
--
-- FROM THE WHOLE ROSTER, NOT THE VISIBLE ONE. Ticks are kept by GUID
-- precisely so somebody can search three names one at a time and act on all
-- three, and this read them back out of the *filtered* list — so every tick
-- made under a search that no longer matches was quietly dropped on the way
-- to the action, and then cleared. The button reported how many it had done,
-- so the two people it skipped left no trace at all.
--
-- Searching narrows what you can see and tick. It does not un-tick anything,
-- and neither does switching between the team and the whole guild.
local function SelectedEntries()
    local kept = {}

    for _, entry in ipairs(lastFullRoster) do
        if selected[entry.guid] then
            table.insert(kept, entry)
        end
    end

    return kept
end

local rowConfig = {
    columns = COLUMNS,
    offsets = columnOffset,
    widths = columnWidth,
    rowHeight = ROW_HEIGHT,
    listTop = LIST_TOP,

    onChanged = function()
        Refresh()
    end,

    onSelect = SetSelected,
}

Refresh = function()
    if not frame then
        return
    end

    header.UpdateLabels()

    local roster = SYL.RosterData.Build()

    -- Kept before anything narrows it, so a tick made under one search is
    -- still there to act on under another.
    lastFullRoster = roster

    -- Coverage is about whoever is on screen. Once a team is marked, "what
    -- are we missing" is a question about the team — asking it of every alt
    -- and social in the guild reports everything covered and means nothing.
    if teamOnly then
        -- Recruits survive the team filter whether or not they are marked.
        --
        -- They are a short list somebody typed in on purpose, and the whole
        -- reason for typing them is to have them counted in the coverage this
        -- view shows. Filtering them out until they are marked also made them
        -- impossible to mark: the tick is on the row, and the row was not
        -- being drawn.
        local team = SYL.RaidTeam.Filter(roster)

        for _, entry in ipairs(roster) do
            if entry.isIncoming and not SYL.RaidTeam.IsMember(entry.key) then
                table.insert(team, entry)
            end
        end

        roster = team
    end

    -- Before the search, so a name typed into the box is looked for among the
    -- people this list is actually about.
    if activeOnly then
        roster = SYL.RosterData.ActiveOnly(roster)
    end

    roster = SYL.RosterData.Search(roster, searchText)
    roster = SYL.RosterData.Sort(roster, sortKey, sortReversed)

    local total = #roster

    lastTotal = total

    SYL.RosterControls.UpdateFilters(frame, teamOnly, activeOnly)
    SYL.RosterControls.UpdateCoverage(frame, roster)
    SYL.RosterControls.UpdateRoles(frame, roster)

    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    local joining = SYL.IncomingRoster.Count()
    local archivedCount = SYL.ArchivedRaiders.Count()

    frame.summaryText:SetText(
        total
        .. (teamOnly and " on the raid team" or
            (total == 1 and " guild member" or " guild members"))
        .. "  ·  " .. SYL.RaidTeam.Count() .. " marked as raiding"
        .. (joining > 0 and ("  ·  " .. joining .. " joining") or "")
        -- SAYS SO RATHER THAN LETTING THEM VANISH. Archiving takes people off
        -- this list, and a roster that quietly holds fewer names than the
        -- guild does is a roster somebody stops trusting. Named on the screen
        -- the names left, with the count, so the difference is accounted for.
        .. (archivedCount > 0
            and ("  ·  " .. archivedCount .. " archived") or "")
        .. (activeOnly
            and ("  ·  seen in the last "
                .. SYL.RosterData.INACTIVE_DAYS .. " days") or "")
        .. (selectedCount > 0
            and ("  ·  " .. selectedCount .. " ticked") or "")
    )

    for index = 1, visibleRows do
        local entry = roster[index + offset]
        local row = rows[index]
            or SYL.RosterRows.Create(frame, index, rowConfig)

        rows[index] = row

        if entry then
            SYL.RosterRows.Fill(row, entry, selected[entry.guid])
            row:Show()
        else
            row:Hide()
        end
    end

    for index = visibleRows + 1, #rows do
        rows[index]:Hide()
    end

    -- An empty team on first use is not an error, and saying so beats an
    -- empty window that looks like the roster failed to load.
    if total == 0 and teamOnly and SYL.RaidTeam.Count() > 0 then
        -- THIS USED TO SAY "NOBODY IS ON THE RAID TEAM YET" WHILE THE LINE
        -- ABOVE IT SAID TWO PEOPLE WERE, which is what Aimee was reading when
        -- she could not find the raiders she was trying to remove. They had
        -- left the guild, and this list was built from the guild alone, so
        -- there was no row to untick -- see the append in Core/RosterData.lua
        -- that now puts them here.
        --
        -- Kept as a distinct message rather than deleted with the cause. The
        -- two numbers come from different places and always will, and if they
        -- ever disagree again this says so instead of printing the sentence
        -- that sent somebody looking for a first-run problem they did not have.
        frame.emptyText:SetText(
            SYL.RaidTeam.Count()
            .. " are marked as raiding and none of them are on this list. "
            .. "Press Whole guild to see everybody the addon knows about."
        )
    elseif total == 0 and teamOnly then
        frame.emptyText:SetText(
            "Nobody is on the raid team yet. Press Whole guild, tick the "
            .. "people who raid, and Add to team."
        )
    else
        frame.emptyText:SetText(
            "Not in a guild, or the roster has not loaded."
        )
    end

    frame.emptyText:SetShown(total == 0)

    -- Guarded because a resize can drive a redraw while the window is still
    -- being built, before the bar exists.
    if frame.scrollBar then
        frame.scrollBar:Update()
    end
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootRosterFrame",
        title = "RAID ROSTER",
        key = "roster",

        width = WINDOW_WIDTH,
        listTop = LIST_TOP,
        rowHeight = ROW_HEIGHT,
        footer = FOOTER_HEIGHT,
        defaultRows = DEFAULT_ROWS,
        maxRows = MAX_ROWS,

        onRows = function(count)
            visibleRows = count
            Refresh()
        end,
    })

    SYL.RosterControls.Create(frame, {
        onTeamOnly = function()
            teamOnly = not teamOnly
            offset = 0
            Refresh()
        end,

        onActiveOnly = function()
            activeOnly = not activeOnly
            offset = 0
            Refresh()
        end,

        onSearch = function(text)
            searchText = text
            offset = 0
            Refresh()
        end,

        -- The whole roster before the team filter and the search, so the
        -- "Alt of" box can suggest a main who is not currently on screen.
        getAllEntries = function()
            return lastFullRoster or {}
        end,

        getSelected = SelectedEntries,

        onClearSelection = ClearSelection,

        -- The bulk actions include "Alt of", which changes mainKey, isAlt and
        -- mainName on the entries themselves, so this one has to rebuild.
        onChanged = Rebuild,
    })

    frame.scrollBar = SYL.ListScrollBar.Create(frame, {
        top = LIST_TOP,
        bottom = FOOTER_HEIGHT,

        getMax = function()
            return math.max(0, lastTotal - visibleRows)
        end,

        getOffset = function()
            return offset
        end,

        onScroll = function(value)
            offset = value

            Refresh()
        end,
    })

    header = SYL.SortHeader.Create(frame, {
        columns = COLUMNS,
        offsets = columnOffset,
        top = LIST_TOP,

        getSort = function()
            return sortKey, sortReversed
        end,

        onSort = function(key, reversed)
            sortKey = key
            sortReversed = reversed
            offset = 0

            Refresh()
        end,
    })

    for index = 1, DEFAULT_ROWS do
        rows[index] = SYL.RosterRows.Create(frame, index, rowConfig)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.title, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetText("Not in a guild, or the roster has not loaded.")
    frame.emptyText:SetWidth(WINDOW_WIDTH - 80)
    frame.emptyText:Hide()

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, lastTotal - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", function()
        -- The roster goes stale, and a window about who is in the guild
        -- should not be showing who was in it at login.
        SYL.Guild.Request()

        -- Team and role live on the player registry, and a guild member who
        -- has never raided is not in it — so marking them did nothing at
        -- all. In a large guild that is almost everybody.
        SYL.RosterData.EnsureRegistry()

        Rebuild()
    end)

    frame:Hide()

    return frame
end

-- Redraws the roster if it happens to be open, and does nothing if it is not.
--
-- Adding a recruit from chat has to show up in a window that is already on
-- screen, and the alternative — the caller reaching for the window's local
-- Refresh — is the seam every other window here already exposes.
function SYL:RefreshRosterWindow()
    if frame and frame:IsShown() then
        Rebuild()
    end
end

function SYL:OpenRosterWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
