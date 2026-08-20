-- UI/DueWindow.lua
--
-- Who is due, in a window.
--
-- The headline claim on the front of the README, and it was chat-only: ten
-- lines from `/syl due`, gone the moment anybody spoke, reachable only by
-- knowing the command existed. Bosses, raid nights and the guild roster all
-- had a footer button. The question the addon is *for* did not.
--
-- The math is entirely Core/DueList.lua and none of it is repeated here. See
-- that file for what "due" is taken to mean — the judgement calls behind it
-- are opinions rather than facts, and they are stated there.
--
-- RECENT RAIDERS ONLY by default: somebody who has not raided in a month is
-- not due in a sense an officer can act on, and leaving them at the top is
-- how a list stops being read. The toggle widens it.
--
-- RAID TEAM ONLY by default, for the same reason one step further out. This
-- list is built from raid night rosters, and a raid night roster is whoever
-- was in the group — pugs included. A pug seen once and given nothing sorts
-- straight to the top, above raiders of two years, because the ranking is
-- nights-without-an-upgrade and one night without is still a drought. The
-- scope is shared with the players window and lives in Core/Audience.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

-- 660, not 640: syl_check measures a row as the window less a 50px inset,
-- and UI/DueRows.lua's columns total 608. Shaving the status column to fit
-- would truncate the sentence that explains the number beside it.
local WINDOW_WIDTH = 660
local ROW_HEIGHT = 24
local DEFAULT_ROWS = 14
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
local LIST_TOP = 140

-- The same three nights `/syl due` uses, so the window and the command never
-- disagree about who is on the list.
local RECENT_NIGHTS = 3

local frame
local rows = {}
local offset = 0
local recentOnly = true

local Refresh

-- Returns the list, and how many people were on it before the audience scope
-- narrowed it. The second number is what tells an empty window whether there
-- is no data or only nobody in scope, which need different sentences.
local function Entries()
    local sessions = SYL.GetActiveRaids()

    local entries = SYL.DueList.Build(SYL.GetActiveDrops(), sessions)

    if recentOnly then
        entries = SYL.DueList.FilterRecent(entries, sessions, RECENT_NIGHTS)
    end

    -- After the recency filter rather than before it, so widening the scope
    -- and widening the date range stay two separate presses that each do one
    -- thing.
    local beforeScope = #entries

    entries = SYL.Audience.Filter(entries, SYL.Audience.Get())

    -- Same ranking as /syl due and the Raiders board. This window is
    -- superseded by the board and still reachable with /syl due window, and a
    -- superseded screen that ranks by an older rule is worse than no screen.
    return SYL.LootScore.Rank(entries), beforeScope
end

-- What went into the numbers, said out loud, exactly as `/syl due` does. A
-- ranking that quietly changed what counts is one somebody will argue with
-- and be right to.
local function DescribeBasis(total)
    local parts = {
        total .. (total == 1 and " raider" or " raiders"),
        SYL.Audience.Note(),
    }

    if recentOnly then
        table.insert(parts, "last " .. RECENT_NIGHTS .. " nights")
    else
        table.insert(parts, "every raider recorded")
    end

    -- Stated every time, because it is the whole definition and somebody
    -- will argue with a number that quietly means something else.
    table.insert(parts, "group-loot wins only, no BoEs")

    return table.concat(parts, "  ·  ")
end

Refresh = function()
    if not frame then
        return
    end

    local entries, beforeScope = Entries()
    local total = #entries
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    frame.summaryText:SetText(DescribeBasis(total))

    frame.recentButton.label:SetText(
        recentOnly and "Recent raiders" or "All dates"
    )

    Theme.SetTextColor(
        frame.recentButton.label, recentOnly and "accent" or "textPrimary"
    )

    local scope = SYL.Audience.Get()

    frame.audienceButton.label:SetText(SYL.Audience.Label(scope))

    -- Accented while narrowed, plain at "Everyone", which is the same grammar
    -- the recency button uses: colored means something is being left out.
    Theme.SetTextColor(
        frame.audienceButton.label,
        scope == "everyone" and "textPrimary" or "accent"
    )

    for index = 1, visibleRows do
        local entry = entries[index + offset]
        local row = rows[index]
            or SYL.DueRows.Create(frame, index, LIST_TOP, ROW_HEIGHT)

        rows[index] = row

        if entry then
            SYL.DueRows.Fill(row, entry, index + offset)
            row:Show()
        else
            row:Hide()
        end
    end

    for index = visibleRows + 1, #rows do
        rows[index]:Hide()
    end

    if total == 0 then
        -- Three causes, three different fixes, and telling them apart is the
        -- whole job of this message: nothing recorded, nobody recent, or
        -- nobody in scope. Scope is checked first because it is the one the
        -- addon just did to itself.
        local scoped = SYL.Audience.ExplainEmpty(scope, beforeScope)

        if scoped then
            frame.emptyText:SetText(scoped)
        elseif #SYL.GetActiveRaids() == 0 then
            frame.emptyText:SetText(
                "No raid nights recorded yet. Attendance is read from the "
                .. "group at each pull, so this fills in from the next boss "
                .. "you engage."
            )
        else
            frame.emptyText:SetText(
                "Nobody has raided in the last "
                .. RECENT_NIGHTS
                .. " nights. Press Recent raiders to see every date."
            )
        end
    end

    frame.emptyText:SetShown(total == 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootDueFrame",
        title = "WHO IS DUE",
        key = "due",

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

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -84)
    hint:SetPoint("TOPRIGHT", -16, -84)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Dry nights counts raid nights attended since their last Need or "
        .. "offspec win. Transmog and greed do not reset it. Click a row for "
        .. "that raider's whole history."
    )

    frame.recentButton =
        Theme.CreateButton(frame, 120, 20, "Recent raiders", function()
            recentOnly = not recentOnly
            offset = 0

            Refresh()
        end)

    frame.recentButton:SetPoint("TOPLEFT", 18, -110)

    SYL.Tooltips.Attach(
        frame.recentButton,
        "Recent raiders / All dates",
        "Recent means anyone in the last " .. RECENT_NIGHTS .. " raid "
        .. "nights. Somebody who has not raided in a month is not due in a "
        .. "sense you can act on, but they are still counted — press this to "
        .. "see them."
    )

    frame.audienceButton =
        Theme.CreateButton(frame, 120, 20, "Raid team", function()
            SYL.Audience.Cycle()
            offset = 0

            Refresh()
        end)

    frame.audienceButton:SetPoint("LEFT", frame.recentButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.audienceButton,
        "Raid team / Guild / Everyone",
        "This list is built from who was in the group at each pull, which "
        .. "includes pugs. A pug seen once and given nothing ranks above a "
        .. "raider of two years, because one night without an upgrade is "
        .. "still a drought. Press to widen to the guild, then to everyone. "
        .. "Shared with the players window."
    )

    SYL.DueRows.CreateHeader(frame, LIST_TOP)

    for index = 1, DEFAULT_ROWS do
        rows[index] = SYL.DueRows.Create(frame, index, LIST_TOP, ROW_HEIGHT)
    end

    frame.emptyText = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetWordWrap(true)
    frame.emptyText:SetWidth(WINDOW_WIDTH - 120)
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
        local total = #Entries()
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenDueWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
