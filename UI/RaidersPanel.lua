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

-- The caption runs the full width of the list under the board, and stops
-- short of the buttons under the roster. Named here because both views set
-- it: the roster view narrows it to whatever LayOutButtons left, and the
-- board has to put it back, or a caption sized for three buttons stays
-- wrapped after switching away from the view that had them.
local CAPTION_WIDTH = 868 - DETAIL_WIDTH - GUTTER

RaidersPanel.CAPTION_WIDTH = CAPTION_WIDTH

-- 868 usable inside the window, less the detail pane and the gutter. Every
-- column width inside it is measured rather than declared here -- see
-- UI/RaidersBoard.lua, which owns the layout, and UI/RaidersBoardRows.lua,
-- which draws against it.
local BOARD_WIDTH = 868 - DETAIL_WIDTH - GUTTER

local ROW_HEIGHT = SYL.RaidersBoard.ROW_HEIGHT
local LIST_TOP = 34

-- Where the rows begin, which is under the headings rather than at the top of
-- the board. The roster view has no headings of its own and still starts at
-- LIST_TOP, which is why the heading row hides when that view is showing.
local ROWS_TOP = LIST_TOP + SYL.RaidersBoard.HEADER_HEIGHT

local VISIBLE_ROWS = 16

local frame
local rows = {}
local rosterRows = {}
local offset = 0
local selectedKey
-- How many rows the last redraw had to show, per view. The mouse wheel needs a
-- ceiling and used to get one by calling Build() — the whole fairness
-- computation over every drop and session — once per notch, on top of the one
-- Refresh does immediately afterwards. Recorded while drawing instead.
local lastShown = { board = 0, roster = 0, archived = 0 }
local view = "board"

-- THE ARCHIVED BOARD IS A THIRD STATE AND NOT A THIRD STOP ON THE TOGGLE.
--
-- Board and Roster are one button because they are the same people asked two
-- questions. Adding a third stop to that cycle would have repeated the mistake
-- Audience.CYCLE was cut back for -- one stray press and getting back takes
-- two more, on a button whose label has changed underneath. So this is its
-- own button, and its own flag: whichever of the two views you were in is
-- still there when you press it again.
local archived = false

local function CurrentView()
    return archived and "archived" or view
end

-- WHICH COLUMN THE BOARD IS SORTED BY, and which way.
--
-- Kept here, in the panel, and applied as a DISPLAY PASS after ranking. It
-- must never be pushed into LootScore.Rank: that is the choke point /syl due,
-- the dashboard "who is due" tile and UI/DueWindow.lua all read, and the last
-- time two screens ranked by different rules it took days to notice -- see the
-- note above LootScore.Sort, which was written about exactly that.
--
-- Opens on the order the board has always used, which is LootScore.Sort's:
-- points per night, lowest first, because the board answers who is owed.
-- The sort state lives in UI/RaidersSort.lua.
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

-- The same three calls the due list and the dashboard tile make, in the same
-- order. Composed rather than copied: DueList owns which wins are real, and a
-- second opinion about that here is how two screens start disagreeing.
local function Build()
    local sessions = SYL.GetActiveRaids()
    local drops = SYL.GetActiveDrops()

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

-- The entry the detail pane should draw for a key picked in the roster view.
--
-- The board first, because a raider who has raided has a score attached and
-- that is the pane this detail was written to show. Most of a 399-member guild
-- is not on the board, though, and those people used to resolve to nil and
-- draw a blank — so a roster entry is the fallback, marked unranked outright
-- rather than left with nil fields, which would have LootScore.Describe say
-- "not ranked" where it can truthfully say why.
local function RosterSelection(key)
    if not key then
        return nil
    end

    local onBoard = FindByKey(Build(), key)

    if onBoard then
        return onBoard
    end

    local entry = FindByKey(SYL.RaidersRoster.Build(), key)

    if entry then
        entry.ranked = false
        entry.notRankedReason = (entry.nights or 0) > 0
            and "not on the raid team"
            or "has not raided yet"
    end

    return entry
end


--------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = SYL.RaidersBoardRows.Create(frame, index, ROWS_TOP, function(key)
        selectedKey = key

        Refresh()
    end)

    rows[index] = row

    return row
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

local function HideRows(list)
    for _, row in ipairs(list) do
        row:Hide()
    end
end

local function ClampOffset(total)
    local maxOffset = math.max(0, total - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end
end

-- What the bars and the average marker are measured against, worked out once
-- per draw rather than once per row. Returns the raw average and how many
-- entries were ranked as well, because the caption underneath has to say
-- something different when that is none.
local function Scale(entries)
    local highest = SYL.LootScore.Highest(entries)
    local average, ranked = SYL.LootScore.Average(entries)

    -- WHAT EVERY RAID NIGHTS CELL IS COUNTED AGAINST, so it is worked out once
    -- for the board rather than once per row. Guild nights only and the same
    -- ones the attendance figures come from -- see RaidSession.NightsOnly --
    -- because "2 of 2" has to mean two of the same two.
    --
    -- Deliberately not narrowed by the audience scope. How many nights the
    -- guild ran is a fact about the guild, and it would be an odd board where
    -- widening from the raid team to everyone changed the denominator.
    local held = SYL.RaidSession.CountNights(
        SYL.RaidSession.NightsOnly(SYL.GetActiveRaids())
    )

    local scale = {
        highest = highest,

        -- The average only means anything once somebody is ranked. Passed as
        -- zero otherwise, which is what makes the rows leave the marker off
        -- rather than park it at the left-hand end where it would read as an
        -- average of none.
        average = ranked > 0 and average or 0,
        nightsHeld = held,
    }

    return scale, average, ranked
end

-- ONE DRAWING PATH FOR BOTH BOARDS. The board and the archived board are the
-- same sixteen rows, the same headings and the same detail pane, and the only
-- thing that differs is which people are in the list -- so the second one is a
-- caller rather than a copy. Two copies of this is how one board would come to
-- sort by a column the other does not have.
--
-- `scale` is deliberately a parameter and not derived from `entries`: the
-- archived board measures its rows against the raid team rather than against
-- each other. See ArchivedRaiders.Build.
local function DrawBoard(entries, scale)
    frame.empty:Hide()

    SYL.RaidersBoard.SetHeaderShown(frame.header, true)

    local sortKey, sortReversed = SYL.RaidersSort.Key()

    SYL.RaidersSort.UpdateHeader(frame.header, sortKey, sortReversed)

    entries = SYL.RaidersSort.Entries(entries, sortKey, sortReversed)

    for index = 1, VISIBLE_ROWS do
        local entry = entries[index + offset]
        local row = rows[index] or CreateRow(index)

        if entry then
            SYL.RaidersBoardRows.Draw(
                row, entry, scale, entry.key == selectedKey
            )
        else
            row:Hide()
        end
    end

    -- Handed the same drops the board was built from, so naming a raider's
    -- items does not sweep the season again on every selection.
    -- The sessions too, not only the drops: the pane groups a raider's loot
    -- under the raid night it was taken on, and only a session can say which
    -- night a timestamp belongs to. Handed over rather than fetched, so
    -- naming a raider's items does not sweep the season again per selection.
    SYL.RaidersDetail.SetDrops(
        frame.detail, SYL.GetActiveDrops(), SYL.GetActiveRaids()
    )

    SYL.RaidersDetail.Render(
        frame.detail, selectedKey and FindByKey(entries, selectedKey) or nil
    )
end

-- An empty board says which of the two empty states it is and draws nothing
-- else -- no headings over nothing, which reads as a list that failed to load.
local function DrawEmptyBoard(message)
    HideRows(rows)

    SYL.RaidersBoard.SetHeaderShown(frame.header, false)

    frame.empty:SetText(message)
    frame.empty:Show()

    SYL.RaidersDetail.Render(frame.detail, nil)
    frame.caption:SetText("")
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

    -- THE SCOPE BUTTON STANDS DOWN ON THE ARCHIVED BOARD, the same way the
    -- headings do on the roster. Its audience is the rule in
    -- Core/ArchivedRaiders.lua rather than a choice, and at the scope this
    -- board opens on -- the raid team -- it would filter the list to nobody by
    -- definition. Leaving it there to be pressed would be a control that
    -- silently empties the screen it is sitting on.
    frame.audienceButton:SetShown(not archived)

    Theme.SetTextColor(
        frame.archivedButton.label, archived and "accent" or "textPrimary"
    )

    if archived then
        HideRows(rosterRows)

        local entries, team, everybody = SYL.ArchivedRaiders.Build()

        lastShown.archived = #entries

        ClampOffset(#entries)

        if #entries == 0 then
            DrawEmptyBoard(SYL.ArchivedRaiders.ExplainEmpty(everybody))
            SYL.RaidersActions.Update(frame.actions, nil)

            return
        end

        -- The team's scale, not this list's. See ArchivedRaiders.Build.
        local scale, average, ranked = Scale(team)

        DrawBoard(entries, scale)

        frame.caption:SetText(
            SYL.ArchivedRaiders.Caption(#entries, average, ranked)
        )

        local selected = selectedKey and FindByKey(entries, selectedKey) or nil

        SYL.RaidersActions.Update(
            frame.actions,
            selected and tostring(selected.name or "Unknown") or nil,
            archived, view, selectedKey
        )

        return
    end

    if view == "roster" then
        SYL.RaidersBoard.SetHeaderShown(frame.header, false)

        -- Resolved once and used twice: the detail pane draws it, and the
        -- footer button is named after it.
        local selected = RosterSelection(selectedKey)

        SYL.RaidersActions.Update(
            frame.actions,
            selected and tostring(selected.name or "Unknown") or nil,
            archived, view, selectedKey
        )

        lastShown.roster = SYL.RaidersRoster.Refresh({
            frame = frame,
            boardRows = rows,
            rosterRows = rosterRows,
            visibleRows = VISIBLE_ROWS,
            listTop = LIST_TOP,
            offset = offset,
            selectedKey = selectedKey,
            onChanged = Refresh,

            onSelect = function(key)
                selectedKey = key

                Refresh()
            end,

            -- FROM THE ROSTER, NOT THE BOARD. This looked the selection up in
            -- Build(), which is the ranked board — so anybody the roster shows
            -- and the board does not (most of a 399-member guild) resolved to
            -- nil and drew an empty detail pane. The same wrong-list mistake
            -- as the mouse wheel below, one screen along.
            selected = selected,
        })

        return
    end

    HideRows(rosterRows)

    -- Nothing to archive from the board itself. See RaidersActions.Update.
    SYL.RaidersActions.Update(frame.actions, nil)

    local entries, beforeScope = Build()

    lastShown.board = #entries

    ClampOffset(#entries)

    if #entries == 0 then
        DrawEmptyBoard(
            SYL.Audience.ExplainEmpty(scope, beforeScope)
            or "Nobody to rank yet. This fills in from your next raid night."
        )

        return
    end

    local scale, average, ranked = Scale(entries)

    DrawBoard(entries, scale)

    -- Put back to full width. The roster view narrows this to make room for
    -- its buttons, and a caption left narrow under the board wraps onto a
    -- second line that the window has no room for.
    frame.caption:SetWidth(CAPTION_WIDTH)

    -- "RAID AVERAGE 0.0 PER NIGHT" IS NOT AN AVERAGE, it is the absence of
    -- one, and it was printed as fact for the whole first stretch of a tier.
    -- With a rank floor set, nobody clears it until the guild's third or
    -- fourth night -- so every bar is empty, there is no average marker, and
    -- the caption underneath used to insist the average was zero.
    --
    -- Said once here rather than sixteen times on the rows. The floor is read
    -- live rather than from the constant, for the same reason
    -- UI/RaidersDetail.lua reads it live: this sentence states the rule as
    -- fact, and a stale number would be the addon explaining a rule it is no
    -- longer applying.
    if ranked == 0 then
        frame.caption:SetText(
            string.format(
                "%d shown · nobody has %s yet, so there is nothing to divide "
                .. "by — no bars and no average until then · %s",
                #entries,
                SYL.Utilities.Count(SYL.LootScore.MinNights(), "raid night"),
                SYL.Audience.Note(scope)
            )
        )
    else
        frame.caption:SetText(
            string.format(
                "%d shown · raid average %.1f per night · %s",
                #entries, average, SYL.Audience.Note(scope)
            )
        )
    end
end

RaidersPanel.Refresh = Refresh

-- Choosing a view leaves the archived board. Pressing Board or Roster while
-- it is showing means "put me back on the list of people who raid here", and
-- landing on the archived board wearing a Board label would be the button
-- lying about what it did.
function RaidersPanel.SetView(next)
    view = (next == "roster") and "roster" or "board"
    archived = false
    offset = 0

    Refresh()
end

function RaidersPanel.ToggleView()
    RaidersPanel.SetView(view == "board" and "roster" or "board")
end

function RaidersPanel.SetArchived(next)
    archived = next and true or false
    offset = 0

    Refresh()
end

function RaidersPanel.ToggleArchived()
    RaidersPanel.SetArchived(not archived)
end

function RaidersPanel.IsArchived()
    return archived
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

    -- WHERE A RAIDER'S SEASON GOES WHEN THEY COME OFF THE TEAM.
    --
    -- Aimee: "when i see the board it should only be active members of the
    -- raid team. but i dont want to lose the history from this screen either."
    -- The board already did the first, by being scoped to the team -- so the
    -- gap was never a filter, it was that nothing showed the people the filter
    -- had removed. Core/ArchivedRaiders.lua decides who that is.
    --
    -- Beside the view toggle rather than on it, for the reason written at the
    -- top of this file next to the `archived` flag.
    frame.archivedButton =
        Theme.CreateButton(frame, 110, 20, "Archived", function()
            RaidersPanel.ToggleArchived()
        end)

    frame.archivedButton:SetPoint("LEFT", frame.viewButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.archivedButton,
        "Archived raiders",
        "Everyone in your guild who has raided this season and is not on the "
        .. "raid team now. Nothing is deleted when you take somebody off the "
        .. "team -- their nights, their items and every roll are still here, "
        .. "they are just not on the board any more."
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

    frame.rosterButton:SetPoint("LEFT", frame.archivedButton, "RIGHT", 8, 0)

    -- THIS TOOLTIP USED TO SAY SOMETHING UNTRUE.
    --
    -- It sent people to the full roster window to add a recruit who is not in
    -- the guild yet. IncomingRoster.Add has never had a caller anywhere in
    -- UI/ -- the only way in was `/syl addraider`, a command nobody had been
    -- told about, which is the house rule broken in the place it is easiest
    -- to believe it is kept. Somebody following this sentence would have
    -- opened that window and hunted for a control that was not there.
    --
    -- There is a real screen for it now: Settings, Tools tab, "Add a
    -- recruit" -- UI/NamePromptDialog.lua. This says where.
    SYL.Tooltips.Attach(
        frame.rosterButton,
        "The full roster window",
        "Search and raid buff coverage. Adding a recruit who is not in the "
        .. "guild yet is under Settings, Tools. /syl players is still the "
        .. "per-player history."
    )

    -- The detail pane, on the right and always present. An empty pane that
    -- says what to do beats a pane that appears on first click, which reads
    -- as the window changing shape under you.
    frame.detail = SYL.RaidersDetail.Create(frame, DETAIL_WIDTH, LIST_TOP - 8)

    -- Measured before anything is anchored against it, and only now because
    -- Theme.MeasureText needs a live client to measure with.
    SYL.RaidersBoard.Measure(BOARD_WIDTH)

    frame.header = SYL.RaidersBoard.CreateHeader(
        frame, LIST_TOP,
        function(key)
            SYL.RaidersSort.OnClick(key, Refresh)
        end
    )

    frame.empty = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.empty:SetPoint("TOPLEFT", 2, -(LIST_TOP + 6))
    frame.empty:SetWidth(868 - DETAIL_WIDTH - GUTTER)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWordWrap(true)
    frame.empty:Hide()

    frame.caption = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 2, 2)
    frame.caption:SetWidth(CAPTION_WIDTH)
    frame.caption:SetJustifyH("LEFT")

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        -- ASK WHICHEVER VIEW IS SHOWING. This counted the board's entries
        -- whatever was on screen, so in roster view the ceiling came from a
        -- raid team of thirteen while the list underneath held all 399 guild
        -- members. Sixteen rows are visible, so that ceiling is zero and the
        -- wheel did nothing at all — the roster could not be scrolled past its
        -- first screen. RaidersRoster clamps its own draw, which is why the
        -- rows looked right and only the scrolling was dead.
        local total = lastShown[CurrentView()] or 0
        local maxOffset = math.max(0, total - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    -- The footer bar, on the window rather than in the panel -- see
    -- UI/RaidersActions.lua for why, and for what it offers on each view.
    frame.actions = SYL.RaidersActions.Create(parent, {
        getSelectedKey = function()
            return selectedKey
        end,

        isArchived = function()
            return archived
        end,

        onChanged = function()
            -- The list this row came from is about to change shape underneath
            -- the selection, so the selection goes with it.
            selectedKey = nil

            SYL.RosterData.Invalidate()
            SYL.RosterSync.OnOwnRosterChanged()

            Refresh()
        end,
    })

    frame:SetScript("OnShow", Refresh)

    -- The bar lives on the window rather than in the panel, so it has to be
    -- put away by hand or it would sit under the dashboard.
    frame:SetScript("OnHide", function()
        frame.actions:Hide()
    end)

    frame:Hide()

    return frame
end
