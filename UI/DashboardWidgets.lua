-- UI/DashboardWidgets.lua
--
-- What goes inside each dashboard tile.
--
-- One renderer per widget, all the same shape: given the tile frame, fill it
-- and return. Core/Dashboard.lua decides which ones exist and in what order;
-- UI/DashboardTab.lua builds the grid and the chrome. This file knows only
-- how to draw a body.
--
-- Every renderer has to survive an empty database. A dashboard is the first
-- thing a new install sees, and a widget that errors on zero drops takes the
-- whole screen with it — so each one leads with the "nothing yet" case rather
-- than treating it as an exception.

local SYL = _G.ShowUsYourLoot
local DashboardParts = SYL.DashboardParts

local DashboardWidgets = {}
SYL.DashboardWidgets = DashboardWidgets

--------------------------------------------------------------------------
-- The renderers
--------------------------------------------------------------------------

DashboardWidgets.RENDERERS = {}

-- Last raid night ---------------------------------------------------------
DashboardWidgets.RENDERERS.lastNight = function(tile)
    -- The guild's nights, not every raid this character walked into. A
    -- 49-person LFR run and a 12-person guild raid landed on the same evening
    -- and were added together into "60 raiders".
    local sessions = SYL.RaidSession.NightsOnly(SYL.GetActiveRaids())

    if #sessions == 0 then
        DashboardParts.Empty(tile,
            "No raid night recorded yet. Attendance is read from the group at "
            .. "each pull, so this fills in from the next boss you engage.")

        return
    end

    -- The most recent night, whatever order the season stored them in.
    local latest

    for _, session in ipairs(sessions) do
        if not latest or (session.startedAt or 0) > (latest.startedAt or 0) then
            latest = session
        end
    end

    -- Anything after the latest night started belongs to it: it is the
    -- latest, so nothing later exists. Cheaper and steadier than keying by
    -- night, which would need the drop to carry a session id it does not have.
    local since = latest.startedAt or 0
    local shown, upgrades, total = 0, 0, 0

    -- WHO IT WENT TO, NOT WHO ROLLED FOR IT. Aimee: "it only ever shows me
    -- because im masterlooter. maybe it doesnt show names?"
    --
    -- The names were never the problem. Under a loot council everybody passes
    -- and the master looter takes the item, so drop.winnerName is her on every
    -- line -- and this tile read that field and nothing else, ignoring the
    -- credit she types afterwards. Her 09/03 night held Hawt, Pringlescat,
    -- Rakahasa, Pringlescat and Arcangila all along; the tile had the answer
    -- and was not looking at it.
    --
    -- LootCredit.Describe is the same choke point the board and the due list
    -- already use, so all three now name the same person for the same item.
    -- It also carries the corrected RESPONSE, which matters twice over: three
    -- of those five were recorded Greed and credited Need, so the count of
    -- who went home with nothing was wrong as well as the names.
    for _, drop in ipairs(SYL.GetActiveDrops()) do
        if not drop.excludedFromAnalytics and (drop.timestamp or 0) >= since then
            total = total + 1

            local credit = SYL.LootCredit.Describe(drop)
            local name = (credit and credit.name) or drop.winnerName
            local state = credit and credit.state or drop.winnerState

            if SYL.LootHistoryAPI.IsUpgradeState(state) then
                upgrades = upgrades + 1
            end

            if shown < DashboardParts.RowCapacity(tile) then
                shown = shown + 1

                -- SHORT NAMES AND NO RESPONSE. Aimee: "the dashboard feed
                -- looks a little busy there. maybe we remove the need/greed
                -- words from that view alone. you could also just show the
                -- character names on that without server to make it fewer
                -- letters."
                --
                -- The response still does its work -- it is what corrects the
                -- count of who went home with nothing below -- it is just not
                -- drawn. A glance at a night wants who and what; which button
                -- they pressed is a question for the drop itself, one click
                -- away on the Feed tab this tile links to.
                DashboardParts.PlayerRow(
                    tile, shown,
                    SYL.Utilities.ShortName(
                        SYL.Utilities.NormalizePlayerName(name or "?")
                    ),
                    (credit and credit.class) or drop.winnerClass,
                    drop.itemName or "?"
                )
            end
        end
    end

    if total == 0 then
        DashboardParts.Empty(tile,
            "Nothing dropped on "
            .. SYL.Utilities.FormatDateOnly(latest.startedAt)
            .. ", or it was not captured.")

        return
    end

    local roster = 0

    for _ in pairs(latest.roster or {}) do
        roster = roster + 1
    end

    local emptyHanded = math.max(0, roster - upgrades)

    -- SAYS WHEN IT IS NOT SHOWING EVERYTHING. Aimee: "also want to confirm
    -- that if 10 items drop we will see them all? 11+ would probably not show
    -- given the space available."
    --
    -- She is right, and it depended on the tile height -- which she can change
    -- by dragging the window. What it must never do is stop at the bottom
    -- without saying so: the caption named a total the list did not contain,
    -- so a night of thirteen drops read as a night of however many happened
    -- to fit. Now the number that is missing is on screen beside the number
    -- that is not.
    local hidden = total - shown

    -- Measured to one line at the tile's width, including the day the list
    -- is cut short: the long form ran to two lines and climbed the rows.
    DashboardParts.Caption(tile,
        total .. " drops · " .. date("%m/%d", latest.startedAt)
        .. (hidden > 0 and (" · " .. hidden .. " more") or "")
        .. " · " .. emptyHanded .. " with nothing")
end

-- Who is due --------------------------------------------------------------
DashboardWidgets.RENDERERS.due = function(tile)
    local sessions = SYL.GetActiveRaids()
    local drops = SYL.GetActiveDrops()

    local entries = SYL.DueList.Build(drops, sessions)

    entries = SYL.Audience.Filter(entries, SYL.Audience.Get())

    SYL.LootScore.Rank(entries, drops)

    if #entries == 0 then
        DashboardParts.Empty(tile,
            SYL.Audience.ExplainEmpty(SYL.Audience.Get(), 0)
            or "Nobody to rank yet. This fills in from your next raid night.")

        return
    end

    for index = 1, math.min(DashboardParts.RowCapacity(tile), #entries) do
        local entry = entries[index]

        DashboardParts.PlayerRow(
            tile, index,
            entry.name or "Unknown",
            entry.class,
            SYL.LootScore.Describe(entry),
            nil,
            (entry.ranked and index <= 2) and "warning" or "textSecondary"
        )
    end

    local average = SYL.LootScore.Average(entries)

    -- THE SHORT SCOPE, not the sentence. Audience.Note is written for a
    -- footer under a full-width list -- "only players marked as being on the
    -- raid team" -- and in a 263-wide tile it took three lines and climbed
    -- over two raiders. Label says the same thing in two words.
    DashboardParts.Caption(tile,
        #entries .. " shown · "
        .. string.format("%.1f", average)
        .. " per night · " .. SYL.Audience.Label())
end

-- Readiness ---------------------------------------------------------------
--
-- This read RaidTeam.Filter directly and so was the one people-list that could
-- not widen: with nobody ticked it drew an empty state, on a dashboard whose
-- every other tile falls through to the guild. Audience.Filter is the same
-- narrowing one step up, and it folds alts — an officer who ticks the alt
-- somebody actually raids on used to have them fail their own team test here.
DashboardWidgets.RENDERERS.readiness = function(tile)
    local scope = SYL.Audience.Get()
    local roster = SYL.RosterData.Build()
    local beforeScope = #roster

    roster = SYL.Audience.Filter(roster, scope)

    if #roster == 0 then
        DashboardParts.Empty(tile,
            SYL.Audience.ExplainEmpty(scope, beforeScope)
            or "Nobody on the roster yet. This fills in from your guild list.")

        return
    end

    local counts = SYL.RaidTeam.CountRoles(roster)

    DashboardParts.Headline(tile, #roster, SYL.Audience.Subject(scope))

    local index = 1

    if SYL.Features.IsEnabled("raidBuffs") then
        local coverage = SYL.RaidBuffs.BuildCoverage(roster)
        local covered, total = SYL.RaidBuffs.Summarize(coverage)
        local missing = SYL.RaidBuffs.Missing(coverage)

        for position = 1, math.min(2, #missing) do
            local buff = missing[position]

            DashboardParts.Row(tile, index,
                type(buff) == "table" and (buff.name or buff.label or "?") or tostring(buff),
                "missing", "textPrimary", "warning")

            index = index + 1
        end

        DashboardParts.Caption(tile,
            SYL.RaidTeam.DescribeRoles(counts)
            .. "  ·  " .. covered .. " of " .. total .. " buffs")

        return
    end

    DashboardParts.Caption(tile,
        SYL.RaidTeam.DescribeRoles(counts))
end

-- Tier progress -----------------------------------------------------------
--
-- ONE DIFFICULTY AT A TIME. This tile used to count every boss on every
-- difficulty into a single number, so Aimee's guild read "22 of 23 killed"
-- while being 6/8 Heroic in one raid and 1/1 Heroic in the other.
--
-- THE TOP LINE IS THE HEADER LINE, which is Aimee's own edit of her
-- screenshot: "TG 1/1   VA 6/8   [Heroic]" beside the Bosses link, rather
-- than two body rows and a button below them. That is how she says it out
-- loud, and it buys back three rows -- two for the raids and one for the
-- chooser -- in a tile that only has six. The whole body is first kills now.
local function DifficultyButton(tile, onChanged)
    if not tile.tierDifficulty then
        -- Sized to the widest label it will ever hold, so cycling does not
        -- make the button jump: LFR, Normal, Heroic, Mythic.
        local widest = 0

        for _, entry in ipairs(SYL.TierProgress.DIFFICULTIES) do
            widest = math.max(widest, SYL.Theme.MeasureText(
                SYL.Theme.sizes.columnHeader, entry.short
            ))
        end

        tile.tierDifficulty = SYL.Theme.CreateButton(
            tile, math.ceil(widest) + 16, 15, "", function()
                SYL.TierProgress.SetDifficulty(
                    SYL.TierProgress.NextDifficulty()
                )

                onChanged()
            end
        )

        -- On the tile rather than in the body: the body is the list now, and
        -- the header is where a control that describes the whole tile
        -- belongs. Anchored off `more` so it sits beside "Bosses ›" however
        -- wide that happens to be.
        tile.tierDifficulty:SetPoint("RIGHT", tile.more, "LEFT", -8, 0)

        SYL.Tooltips.Attach(
            tile.tierDifficulty,
            "Which difficulty this counts",
            "LFR, Normal, Heroic, Mythic. Guilds progress at different rates "
            .. "on each, so adding them together describes nothing. Saved, "
            .. "not per-session."
        )
    end

    tile.tierDifficulty.label:SetText(SYL.TierProgress.Label())
    tile.tierDifficulty:Show()

    return tile.tierDifficulty
end

-- The raids on the header line, left of the difficulty button.
--
-- MEASURED AGAINST THE ROOM THERE ACTUALLY IS, and drawn with as many raids
-- as fit. Two is what Aimee's tier has and two is what fits: the title, both
-- totals, the chooser and the Bosses link come to almost exactly the 263 a
-- tile has to give. A third raid does not fit at any size worth reading, and
-- a tier with three will happen -- so the ones that do not fit are dropped
-- here and counted in the caption rather than drawn under the link.
--
-- This is the rule UI/Columns.lua wrote down after the DATE column shipped
-- truncated twice: measure against the widest thing it can hold.
local function HeadlineText(tile, instances)
    if not tile.tierHeadline then
        tile.tierHeadline = SYL.Theme.CreateText(
            tile, SYL.Theme.sizes.tiny, "textSecondary"
        )

        tile.tierHeadline:SetJustifyH("RIGHT")
        tile.tierHeadline:SetWordWrap(false)
    end

    tile.tierHeadline:ClearAllPoints()
    tile.tierHeadline:SetPoint(
        "RIGHT", tile.tierDifficulty or tile.more, "LEFT", -8, 0
    )

    local size = SYL.Theme.sizes.tiny

    -- What is left after the title on one side and the chooser and the link
    -- on the other, all of which are already placed. The link is measured off
    -- the font string itself rather than rebuilt from its text, because the
    -- arrow in it is not a character worth spelling twice.
    local linkWidth = 40

    if tile.more and tile.more.GetStringWidth then
        linkWidth = tile.more:GetStringWidth() or linkWidth
    end

    local room = (tile.body and tile.body:GetWidth() or 263)
        - SYL.Theme.MeasureText(SYL.Theme.sizes.columnHeader, "TIER PROGRESS")
        - (tile.tierDifficulty and tile.tierDifficulty:GetWidth() or 48)
        - linkWidth
        - 24

    local parts = {}
    local shown = 0

    for _, instance in ipairs(instances or {}) do
        table.insert(parts, SYL.TierProgress.Initials(instance.name)
            .. " " .. SYL.TierProgress.Describe(instance))

        if SYL.Theme.MeasureText(size, table.concat(parts, "  ")) > room then
            table.remove(parts)

            break
        end

        shown = shown + 1
    end

    tile.tierHeadline:SetText(table.concat(parts, "  "))
    tile.tierHeadline:Show()

    return shown
end

DashboardWidgets.RENDERERS.tier = function(tile)
    local difficulty = SYL.TierProgress.GetDifficulty()

    DifficultyButton(tile, function()
        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end)

    local instances = SYL.TierProgress.Build(SYL.GetActiveRaids(), difficulty)

    local headlined = HeadlineText(tile, instances)

    if #instances == 0 then
        DashboardParts.Empty(tile,
            "Nothing killed on " .. SYL.TierProgress.Label(difficulty)
            .. " yet. Press the button beside the heading to look at another "
            .. "difficulty.")

        return
    end

    -- FIRST KILLS, NEWEST FIRST, with the week and what it cost. Aimee: "i
    -- think it would be nice to see later what week we first killed which
    -- boss", and then "could the pull count for the boss also show there?"
    --
    -- A date says when; the week says how long it took, and the pulls say
    -- what it cost. Those last two are the parts anybody retells.
    local recent = SYL.TierProgress.Recent(instances)
    local capacity = DashboardParts.RowCapacity(tile)

    DashboardParts.Row(tile, 1, "FIRST KILLED", "newest first",
        "textMuted", "textMuted")

    local shown = 0

    for _, kill in ipairs(recent) do
        if shown + 1 >= capacity then
            break
        end

        shown = shown + 1

        DashboardParts.Row(tile, shown + 1,
            kill.name,
            date("%m/%d", kill.at)
                .. (kill.week and (" · wk " .. kill.week) or ""),
            "textSecondary", "textMuted",
            kill.pulls and (kill.pulls
                .. (kill.pulls == 1 and " pull" or " pulls")) or nil)
    end

    local left = #recent - shown

    -- Any raid that would not fit on the header line is named here rather
    -- than being silently missing from the totals.
    local unlisted = #instances - headlined

    DashboardParts.Caption(tile,
        (left > 0 and (left .. " more on Bosses · ") or "")
        .. SYL.Utilities.Count(#recent, "boss", "bosses") .. " killed on "
        .. SYL.TierProgress.Label(difficulty)
        .. (unlisted > 0
            and (" · " .. unlisted .. " more raid"
                .. (unlisted == 1 and "" or "s"))
            or ""))
end

-- Recording ---------------------------------------------------------------
DashboardWidgets.RENDERERS.recording = function(tile)
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings or {}

    local drops = SYL.GetActiveDrops()
    local nights = SYL.RaidSession.NightsOnly(SYL.GetActiveRaids())

    local latest = 0

    for _, drop in ipairs(drops) do
        if (drop.timestamp or 0) > latest then
            latest = drop.timestamp
        end
    end

    local states = {
        { "Capture", settings.lootHistoryCapture ~= false },
        { "Attendance", true },
        { "Key sharing", SYL.Features.IsEnabled("keystoneSharing") },
        { "Officer sync", SYL.Features.IsEnabled("sync") },
    }

    local pieces = {}

    for _, state in ipairs(states) do
        table.insert(pieces, state[1] .. " " .. (state[2] and "on" or "off"))
    end

    -- ONE LINE, BOTH HALVES. The strip is 54px tall, which leaves its body 18
    -- — room for a single row of text. A stacked summary and caption, which is
    -- what every other tile uses, would draw on top of each other here.
    local stale = latest == 0

    -- The counts moved onto the title, because the body line is now shared
    -- with the links and there is exactly one line. Nothing was dropped to
    -- make room; it reads as a subtitle on the strip's own heading.
    tile.title:SetText(
        "RECORDING   ·   " .. #drops .. " drops, " .. #nights .. " nights"
        .. (stale
            and "   ·   nothing captured yet"
            or ("   ·   last captured "
                .. SYL.Utilities.FormatDateTime(latest)))
    )

    -- LINKS LIVE HERE NOW. They had a tile of their own and did not need one —
    -- three lines of text in a space sized for six — and giving it up is what
    -- made room for Who is out without pushing the grid onto a third row.
    --
    -- Laid out right to left so the row stays anchored to the right edge
    -- however many links there are, and so adding one never pushes the last
    -- one off the end.
    local links = SYL.Links.List()
    local anchor, rightmost = nil, nil

    for index = #links, 1, -1 do
        local link = links[index]

        local button = CreateFrame("Button", nil, tile.body)

        local label = SYL.Theme.CreateText(
            button, SYL.Theme.sizes.rowSmall, "accent"
        )

        label:SetAllPoints()
        label:SetJustifyH("RIGHT")
        label:SetText(link.label)

        button:SetHeight(16)
        button:SetWidth(SYL.Theme.MeasureText(SYL.Theme.sizes.rowSmall, link.label) + 6)

        if anchor then
            button:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
        else
            button:SetPoint("RIGHT", -2, 0)
            rightmost = button
        end

        anchor = button

        button:SetScript("OnEnter", function()
            SYL.Theme.SetTextColor(label, "textPrimary")
        end)

        button:SetScript("OnLeave", function()
            SYL.Theme.SetTextColor(label, "accent")
        end)

        -- An addon cannot open a browser or write to the clipboard, so this
        -- is a box to copy from rather than a link that goes anywhere.
        button:SetScript("OnClick", function()
            SYL.Links.ShowCopyBox(link)
        end)
    end

    local summary = SYL.Theme.CreateText(
        tile.body, SYL.Theme.sizes.rowSmall, "textPrimary"
    )

    summary:SetPoint("LEFT", 2, 0)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetText(table.concat(pieces, "   ·   "))

    if anchor then
        summary:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
    else
        summary:SetPoint("RIGHT", -2, 0)
    end

    tile.linksAnchor = rightmost
end

--------------------------------------------------------------------------

function DashboardWidgets.Render(tile, widget)
    local renderer = DashboardWidgets.RENDERERS[widget.key]

    if not renderer then
        DashboardParts.Empty(tile, "No renderer for " .. tostring(widget.key) .. ".")

        return
    end

    -- A widget that errors must not take the dashboard with it. Every tile is
    -- independent, so one bad renderer costs one tile and says so.
    local ok, err = pcall(renderer, tile)

    if not ok then
        -- One call, not Empty plus Caption: the Recording strip has 18px of
        -- body and two stacked lines would draw through each other exactly
        -- when something has already gone wrong.
        DashboardParts.Empty(tile, "This widget could not be drawn.")

        SYL:DebugPrint(
            "Widget " .. tostring(widget.key) .. " failed: " .. tostring(err)
        )
    end
end
