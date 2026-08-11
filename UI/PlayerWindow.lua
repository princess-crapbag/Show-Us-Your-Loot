-- UI/PlayerWindow.lua
--
-- Per-player loot numbers: how often someone was eligible, what they actually
-- won, and how long it has been.
--
-- Upgrades and transmog are separate columns rather than one "wins" total,
-- because treating them as the same thing is exactly how loot starts looking
-- fairer than it was.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Analytics = SYL.Analytics

-- 820 rather than 760: the Raider.IO column needs 54px and the old width had
-- 34 spare, so fitting it meant widening rather than truncating a name.
-- The columns themselves are in UI/PlayerRows.lua.
local WINDOW_WIDTH = 820
local ROW_HEIGHT = 24
-- Rows the window opens with, the most it will ever build, and how many are
-- on screen right now.
local DEFAULT_ROWS = 16
local MAX_ROWS = 40
local FOOTER_HEIGHT = 56

local visibleRows = DEFAULT_ROWS
local LIST_TOP = 150

local frame
local rows = {}
local header

local sortKey = "upgrades"
local sortReversed = false
local offset = 0
local emptyOnly = false
local wholeGuild = false

-- Returns the list, and how many people were on it before the audience scope
-- narrowed it, so an empty window can say which of the two happened.
local function CurrentStats()
    local stats = Analytics.BuildPlayerStats(SYL.GetActiveDrops())

    -- Before the filters, so the scope and "no upgrade yet" apply to the
    -- roster too rather than to the loot history alone.
    if wholeGuild then
        Analytics.IncludeGuildRoster(stats)
    end

    local beforeScope = #stats

    -- Replaces the old "Guild only" tickbox, which was the same question
    -- asked with one of its three answers missing. See Core/Audience.lua.
    stats = SYL.Audience.Filter(stats, SYL.Audience.Get())

    if emptyOnly then
        stats = Analytics.FilterEmptyHanded(stats)
    end

    -- Before the sort, so the M+ column sorts like any other.
    if SYL.Features.IsEnabled("raiderIO") then
        SYL.RaiderIO.AttachScores(stats)
    end

    return Analytics.Sort(stats, sortKey, sortReversed), beforeScope
end

local Refresh

local function CreateHeader(parent)
    header = SYL.SortHeader.Create(parent, {
        columns = SYL.PlayerRows.COLUMNS,
        offsets = SYL.PlayerRows.OFFSETS,
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

    return header
end

Refresh = function()
    if not frame then
        return
    end

    header.UpdateLabels()

    local stats, beforeScope = CurrentStats()
    local total = #stats
    local maxOffset = math.max(0, total - visibleRows)

    if offset > maxOffset then
        offset = maxOffset
    end

    local totals = Analytics.Summarize(stats)

    -- Said out loud, because two characters counted as one person is the
    -- kind of thing an officer argues with a list about.
    local folded = SYL.Players.DescribeMappings()

    local scope = SYL.Audience.Get()

    local parts = {
        total .. (total == 1 and " player" or " players"),
        SYL.Audience.Note(scope),
        totals.emptyHanded .. " with no upgrade",
    }

    -- Only worth saying when the list is not already narrowed to the guild or
    -- to the team, where it would just repeat the count beside it.
    if scope == "everyone" then
        table.insert(parts, 2, totals.guildMembers .. " in guild")
    end

    if folded then
        table.insert(parts, folded)
    end

    frame.summaryText:SetText(table.concat(parts, "  ·  "))

    frame.audienceButton.label:SetText(SYL.Audience.Label(scope))

    Theme.SetTextColor(
        frame.audienceButton.label,
        scope == "everyone" and "textPrimary" or "accent"
    )

    -- An empty list has two causes that need different sentences: nothing
    -- recorded, or nobody in scope.
    local scoped = SYL.Audience.ExplainEmpty(scope, beforeScope)

    frame.emptyText:SetText(scoped or "No drops recorded yet.")

    for index = 1, visibleRows do
        local entry = stats[index + offset]
        local row = rows[index]
            or SYL.PlayerRows.Create(frame, index, LIST_TOP, ROW_HEIGHT)

        rows[index] = row

        if entry then
            SYL.PlayerRows.Fill(row, entry)
            row:Show()
        else
            row:Hide()
        end
    end

    for index = visibleRows + 1, #rows do
        rows[index]:Hide()
    end

    if total == 0 then
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end
end

local function CreateFilters(parent)
    local Toggles = SYL.Toggles

    -- A cycle rather than a tickbox, and it replaces "Guild only", which was
    -- this same question with one of its three answers missing: it could
    -- narrow to the guild but never to the raid team, which is the one an
    -- officer wants by default. Shared with the due window.
    frame.audienceButton =
        Theme.CreateButton(parent, 110, 20, "Raid team", function()
            SYL.Audience.Cycle()
            offset = 0

            Refresh()
        end)

    frame.audienceButton:SetPoint("TOPLEFT", 18, -108)

    SYL.Tooltips.Attach(
        frame.audienceButton,
        "Raid team / Guild / Everyone",
        "Who this list is about. Everyone includes people seen in a pug or a "
        .. "key, which is rarely the question. Shared with the due window."
    )

    frame.emptyButton =
        Toggles.Create(parent, 140, "No upgrade yet", function(on)
            emptyOnly = on
            offset = 0
            Refresh()
        end)

    frame.emptyButton:SetPoint("LEFT", frame.audienceButton, "RIGHT", 6, 0)

    -- Everyone in the guild, including those who have never raided, which is
    -- the only way to see a roster rather than a loot history.
    --
    -- Named for what it adds rather than for the guild, so it does not read
    -- as a third answer to the scope button sitting beside it. It is a
    -- different axis: the scope says whose names belong here, this says
    -- whether names with no history at all are among them.
    frame.rosterButton =
        Toggles.Create(parent, 150, "Include non-raiders", function(on)
            wholeGuild = on
            offset = 0

            if on then
                SYL.AltDetect.EnsureGuildMembers()
            end

            Refresh()
        end)

    frame.rosterButton:SetPoint("LEFT", frame.emptyButton, "RIGHT", 6, 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = Widgets.CreateListWindow({
        globalName = "ShowUsYourLootPlayerFrame",
        title = "PLAYERS",
        key = "players",

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
    hint:SetPoint("TOPLEFT", 18, -76)
    hint:SetText(
        "Upgrades counts Need and offspec wins only. Transmog is listed apart."
    )

    CreateFilters(frame)
    CreateHeader(frame)

    for index = 1, DEFAULT_ROWS do
        rows[index] =
            SYL.PlayerRows.Create(frame, index, LIST_TOP, ROW_HEIGHT)
    end

    -- Wraps, because the scope can put a whole sentence here rather than the
    -- four words this started as. See Audience.ExplainEmpty.
    frame.emptyText = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.emptyText:SetPoint("CENTER", 0, -20)
    frame.emptyText:SetJustifyH("CENTER")
    frame.emptyText:SetWordWrap(true)
    frame.emptyText:SetWidth(WINDOW_WIDTH - 160)
    frame.emptyText:SetText("No drops recorded yet.")
    frame.emptyText:Hide()

    local footerRule = Theme.CreateSeparator(frame)
    footerRule:SetPoint("BOTTOMLEFT", 16, 44)
    footerRule:SetPoint("BOTTOMRIGHT", -16, 44)

    local exportButton =
        Theme.CreateButton(frame, 100, 26, "Export", function()
            SYL:OpenExportWindow()
        end)

    exportButton:SetPoint("BOTTOMLEFT", 16, 12)

    local closeButton = Theme.CreateButton(frame, 100, 26, "Close", function()
        frame:Hide()
    end)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local total = #CurrentStats()
        local maxOffset = math.max(0, total - visibleRows)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)
    frame:Hide()

    return frame
end

function SYL:OpenPlayerWindow()
    -- Raises a buried window rather than hiding it; see
    -- WindowStack.ToggleWindow.
    SYL.WindowStack.ToggleWindow(CreateWindow())
end
