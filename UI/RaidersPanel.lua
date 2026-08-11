-- UI/RaidersPanel.lua
--
-- The Raiders tab: one bar per raider, length being what they have taken per
-- raid night, with the raid average drawn across it and a detail pane on the
-- right explaining whichever bar is selected.
--
-- A BOARD RATHER THAN A TABLE, and that is settled. Two table designs were put
-- up and both were rejected: a table of the same numbers makes you read every
-- row to find out whether one of them is unusual, and the question this screen
-- exists to answer — who is behind — is a shape question. The bars answer it
-- without being read. Do not turn this back into a table.
--
-- THE DETAIL PANE IS THE POINT OF THE SCREEN. It is where somebody stands when
-- they disagree with their number, so it shows the arithmetic rather than the
-- conclusion: every win that counted, what each was worth, and the total those
-- add to. A number somebody cannot take apart is a number they stop trusting.
--
-- Scoped like every other people-list: raid team, then guild, then everyone.
-- See Core/Audience.lua for why that order and why the default is computed.
--
-- Fixed pixel layout, matching the rest of the addon. The main window is 900
-- wide and does not resize, so a column that has to fit is measured once here
-- rather than recomputed against a width that never changes.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersPanel = {}
SYL.RaidersPanel = RaidersPanel

local DETAIL_WIDTH = 250
local GUTTER = 12

local NAME_WIDTH = 120
local VALUE_WIDTH = 64
local PAD = 8

-- 868 usable, less the detail pane and the gutter, less the two text columns.
local TRACK_WIDTH = 868 - DETAIL_WIDTH - GUTTER - NAME_WIDTH - VALUE_WIDTH - (PAD * 2)

local ROW_HEIGHT = 22
local LIST_TOP = 34
local VISIBLE_ROWS = 16

local frame
local rows = {}
local rosterRows = {}
local offset = 0
local selectedKey
local view = "board"
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

-- The same three calls the due list and the dashboard tile make, in the same
-- order. Composed rather than copied: DueList owns which wins are real, and a
-- second opinion about that here is how two screens start disagreeing.
local function Build()
    local sessions = SYL.GetAllRaids()
    local drops = SYL.GetAllDrops()

    local entries = SYL.DueList.Build(drops, sessions)
    local beforeScope = #entries

    entries = SYL.Audience.Filter(entries, SYL.Audience.Get())

    SYL.LootScore.Rank(entries, drops)

    return entries, beforeScope
end

local function FindByKey(entries, key)
    for _, entry in ipairs(entries) do
        if entry.key == key then
            return entry
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetWidth(NAME_WIDTH + PAD + TRACK_WIDTH + PAD + VALUE_WIDTH)

    local hover = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    hover:SetAllPoints()
    hover:Hide()

    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", 3, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- The track is the full width every bar is measured against, so an empty
    -- track reads as zero rather than as a missing row.
    row.track = CreateFrame("Frame", nil, row)
    row.track:SetSize(TRACK_WIDTH, 12)
    row.track:SetPoint("LEFT", row.name, "RIGHT", PAD, 0)

    local trackBase = Theme.CreateSolidTexture(row.track, "rowAlt", "BACKGROUND")
    trackBase:SetAllPoints()

    row.fill = Theme.CreateSolidTexture(row.track, "accent", "ARTWORK")
    row.fill:SetPoint("TOPLEFT")
    row.fill:SetPoint("BOTTOMLEFT")

    row.value = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.value:SetPoint("LEFT", row.track, "RIGHT", PAD, 0)
    row.value:SetWidth(VALUE_WIDTH)
    row.value:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function()
        selectedKey = row.entryKey

        Refresh()
    end)

    rows[index] = row

    return row
end

local function DrawRow(row, entry, highest, isSelected)
    row.entryKey = entry.key

    row.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(row.name, classColor[1], classColor[2], classColor[3])
    else
        Theme.SetTextColor(row.name, "textPrimary")
    end

    local fraction = SYL.LootScore.BarFraction(entry, highest)

    if fraction > 0 then
        row.fill:SetWidth(math.max(2, fraction * TRACK_WIDTH))
        row.fill:Show()
    else
        row.fill:Hide()
    end

    -- Selected reads as the accent on the number, not a border: a border on a
    -- 22px row competes with the bar it is drawn beside.
    row.value:SetText(SYL.LootScore.Describe(entry))
    Theme.SetTextColor(
        row.value,
        isSelected and "accent" or (entry.ranked and "textSecondary" or "textMuted")
    )

    row:Show()
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

local function HideRows(list)
    for _, row in ipairs(list) do
        row:Hide()
    end
end

Refresh = function()
    if not frame then
        return
    end

    frame.viewButton.label:SetText(view == "board" and "Board" or "Roster")

    local scope = SYL.Audience.Get()

    frame.audienceButton.label:SetText(SYL.Audience.Label(scope))
    Theme.SetTextColor(
        frame.audienceButton.label,
        scope == "everyone" and "textPrimary" or "accent"
    )

    if view == "roster" then
        SYL.RaidersRoster.Refresh({
            frame = frame,
            boardRows = rows,
            rosterRows = rosterRows,
            visibleRows = VISIBLE_ROWS,
            listTop = LIST_TOP,
            offset = offset,
            selectedKey = selectedKey,
            onChanged = Refresh,
            selected = selectedKey and FindByKey(Build(), selectedKey) or nil,
        })

        return
    end

    HideRows(rosterRows)

    local entries, beforeScope = Build()
    local maxOffset = math.max(0, #entries - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    if #entries == 0 then
        HideRows(rows)

        frame.average:Hide()

        frame.empty:SetText(
            SYL.Audience.ExplainEmpty(scope, beforeScope)
            or "Nobody to rank yet. This fills in from your next raid night."
        )
        frame.empty:Show()

        SYL.RaidersDetail.Render(frame.detail, nil)
        frame.caption:SetText("")

        return
    end

    frame.empty:Hide()

    local highest = SYL.LootScore.Highest(entries)
    local average, ranked = SYL.LootScore.Average(entries)

    for index = 1, VISIBLE_ROWS do
        local entry = entries[index + offset]
        local row = rows[index] or CreateRow(index)

        if entry then
            DrawRow(row, entry, highest, entry.key == selectedKey)
        else
            row:Hide()
        end
    end

    -- The line only means anything once somebody is ranked, and it is drawn
    -- against the same highest the bars are, or it would sit at the wrong
    -- place on a board whose longest bar is not the maximum.
    if ranked > 0 and highest > 0 then
        local shown = math.min(VISIBLE_ROWS, #entries)

        frame.average:ClearAllPoints()
        frame.average:SetPoint(
            "TOPLEFT", frame, "TOPLEFT",
            NAME_WIDTH + PAD + 3 + math.min(1, average / highest) * TRACK_WIDTH,
            -(LIST_TOP - 4)
        )
        frame.average:SetSize(1, shown * ROW_HEIGHT + 4)
        frame.average:Show()
    else
        frame.average:Hide()
    end

    SYL.RaidersDetail.Render(
        frame.detail, selectedKey and FindByKey(entries, selectedKey) or nil
    )

    frame.caption:SetText(
        string.format(
            "%d shown · raid average %.1f per night · %s",
            #entries, average, SYL.Audience.Note(scope)
        )
    )
end

RaidersPanel.Refresh = Refresh

function RaidersPanel.SetView(next)
    view = (next == "roster") and "roster" or "board"
    offset = 0

    Refresh()
end

function RaidersPanel.ToggleView()
    RaidersPanel.SetView(view == "board" and "roster" or "board")
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function RaidersPanel.Create(parent)
    frame = CreateFrame("Frame", nil, parent)

    frame:SetPoint("TOPLEFT", 16, -100)
    frame:SetPoint("BOTTOMRIGHT", -16, 52)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText("RAIDERS")

    frame.audienceButton =
        Theme.CreateButton(frame, 120, 20, "Raid team", function()
            SYL.Audience.Cycle()
            offset = 0

            Refresh()
        end)

    frame.audienceButton:SetPoint("TOPLEFT", title, "TOPRIGHT", 14, -2)

    SYL.Tooltips.Attach(
        frame.audienceButton,
        "Raid team / Guild / Everyone",
        "This board is built from who was in the group at each pull, which "
        .. "includes pugs. Press to widen to the guild, then to everyone. "
        .. "Shared with every other list of people."
    )

    -- THE ROSTER AND PLAYERS WINDOWS ARE REACHED FROM HERE. This tab used to
    -- be a panel of three buttons that opened them, and turning it into a real
    -- board deleted all three — which left the roster behind /syl roster and
    -- nothing else, so it read as having been removed. It had not; there was
    -- simply no longer a door.
    --
    -- The intended end state is Players and Roster merged into this board,
    -- because the difference between those two screens was always the audience
    -- and that is the button above. Until that is built these open the windows
    -- that answer it today, which is what the tab did before.
    -- Board or Roster, which is the merge. The two used to be separate windows
    -- reached from separate buttons, and they are the same people asked two
    -- questions: who is owed loot, and who is on the team. The second decides
    -- who appears in the first, so making it a toggle rather than a trip to
    -- another window is most of the value.
    frame.viewButton = Theme.CreateButton(frame, 90, 20, "Board", function()
        RaidersPanel.ToggleView()
    end)

    frame.viewButton:SetPoint("LEFT", frame.audienceButton, "RIGHT", 10, 0)

    SYL.Tooltips.Attach(
        frame.viewButton,
        "Board / Roster",
        "The board ranks who is owed loot. The roster is who could raid, with "
        .. "a tick for the team and their role — and ticking TEAM there is "
        .. "what the scope button beside this reads."
    )

    -- Searching, buff coverage and adding somebody who has not joined the
    -- guild yet all still live in the full window. None of them belong in a
    -- list whose job is a column of ticks, and removing the last route to
    -- them once already made the roster look deleted.
    frame.rosterButton = Theme.CreateButton(frame, 110, 20, "Full roster", function()
        if SYL.OpenRosterWindow then
            SYL:OpenRosterWindow()
        end
    end)

    frame.rosterButton:SetPoint("LEFT", frame.viewButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.rosterButton,
        "The full roster window",
        "Search, raid buff coverage, and adding a recruit who is not in the "
        .. "guild yet. /syl players is still the per-player history."
    )

    -- The detail pane, on the right and always present. An empty pane that
    -- says what to do beats a pane that appears on first click, which reads
    -- as the window changing shape under you.
    frame.detail = SYL.RaidersDetail.Create(frame, DETAIL_WIDTH, LIST_TOP - 8)

    frame.average = Theme.CreateSolidTexture(frame, "warning", "OVERLAY")
    frame.average:Hide()

    frame.empty = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.empty:SetPoint("TOPLEFT", 2, -(LIST_TOP + 6))
    frame.empty:SetWidth(868 - DETAIL_WIDTH - GUTTER)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWordWrap(true)
    frame.empty:Hide()

    frame.caption = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 2, 2)
    frame.caption:SetWidth(868 - DETAIL_WIDTH - GUTTER)
    frame.caption:SetJustifyH("LEFT")

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = #(Build())
        local maxOffset = math.max(0, total - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)

    frame:Hide()

    return frame
end
