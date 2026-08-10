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
    local sessions = SYL.RaidSession.RaidsOnly(SYL.GetAllRaids())

    if #sessions == 0 then
        DashboardParts.Empty(tile,
            "No raid night recorded yet. Attendance is read from the group at "
            .. "each pull, so this fills in from the next boss you engage.")

        return
    end

    -- The most recent night, whatever order the seasons stored them in.
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

    for _, drop in ipairs(SYL.GetAllDrops()) do
        if not drop.excludedFromAnalytics and (drop.timestamp or 0) >= since then
            total = total + 1

            if SYL.LootHistoryAPI.IsUpgradeState(drop.winnerState) then
                upgrades = upgrades + 1
            end

            if shown < 6 then
                shown = shown + 1

                DashboardParts.PlayerRow(
                    tile, shown,
                    SYL.Utilities.NormalizePlayerName(drop.winnerName or "?"),
                    drop.winnerClass,
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

    DashboardParts.Caption(tile,
        total .. " drops · " .. SYL.Utilities.FormatDateOnly(latest.startedAt)
        .. " · " .. emptyHanded .. " went home with nothing")
end

-- Who is due --------------------------------------------------------------
DashboardWidgets.RENDERERS.due = function(tile)
    local sessions = SYL.GetAllRaids()
    local drops = SYL.GetAllDrops()

    local entries = SYL.DueList.Build(drops, sessions)

    entries = SYL.Audience.Filter(entries, SYL.Audience.Get())

    SYL.LootScore.Attach(entries, drops)
    SYL.LootScore.Sort(entries)

    if #entries == 0 then
        DashboardParts.Empty(tile,
            SYL.Audience.ExplainEmpty(SYL.Audience.Get(), 0)
            or "Nobody to rank yet. This fills in from your next raid night.")

        return
    end

    for index = 1, math.min(6, #entries) do
        local entry = entries[index]

        DashboardParts.PlayerRow(
            tile, index,
            entry.name or "Unknown",
            entry.class,
            SYL.LootScore.Describe(entry),
            (entry.ranked and index <= 2) and "warning" or "textSecondary"
        )
    end

    local average = SYL.LootScore.Average(entries)

    DashboardParts.Caption(tile,
        #entries .. " ranked · raid average "
        .. string.format("%.1f", average)
        .. " per night · " .. SYL.Audience.Note())
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
        local covered, total = SYL.RaidBuffs.Summarise(coverage)
        local missing = SYL.RaidBuffs.Missing(coverage)

        for position = 1, math.min(2, #missing) do
            local buff = missing[position]

            DashboardParts.Row(tile, index,
                type(buff) == "table" and (buff.name or buff.label or "?") or tostring(buff),
                "missing", "textPrimary", "warning")

            index = index + 1
        end

        DashboardParts.Caption(tile,
            counts.TANK .. " tanks · " .. counts.HEALER .. " healers · "
            .. counts.DPS .. " dps"
            .. (counts.unset > 0 and ("  ·  " .. counts.unset .. " unset") or "")
            .. "  ·  " .. covered .. " of " .. total .. " buffs")

        return
    end

    DashboardParts.Caption(tile,
        counts.TANK .. " tanks · " .. counts.HEALER .. " healers · "
        .. counts.DPS .. " dps"
        .. (counts.unset > 0 and ("  ·  " .. counts.unset .. " unset") or ""))
end

-- Tier progress -----------------------------------------------------------
DashboardWidgets.RENDERERS.tier = function(tile)
    local bosses = SYL.BossStats.Build(SYL.GetAllDrops(), SYL.GetAllRaids())

    if #bosses == 0 then
        DashboardParts.Empty(tile,
            "No bosses recorded yet. They are counted from the pulls this "
            .. "addon sees.")

        return
    end

    local killed, pulled, unkilled = 0, 0, {}

    for _, boss in ipairs(bosses) do
        pulled = pulled + 1

        if (boss.kills or 0) > 0 then
            killed = killed + 1
        else
            table.insert(unkilled, boss)
        end
    end

    DashboardParts.Headline(tile, killed, "of " .. pulled .. " killed")

    for index = 1, math.min(2, #unkilled) do
        local boss = unkilled[index]

        DashboardParts.Row(tile, index,
            boss.name or "Unknown",
            (boss.pulls or 0) .. " pulls, no kill",
            "textPrimary", "warning")
    end

    DashboardParts.Caption(tile, (SYL.GetAllDrops() and #SYL.GetAllDrops() or 0)
        .. " drops recorded across " .. pulled .. " bosses.")
end

-- Links -------------------------------------------------------------------
DashboardWidgets.RENDERERS.links = function(tile)
    local links = SYL.Links.List()

    if #links == 0 then
        DashboardParts.Empty(tile,
            "No links yet. /syl link add Logs https://… adds one. Clicking a "
            .. "link opens a box to copy from, because an addon cannot open a "
            .. "browser or write to your clipboard.")

        return
    end

    for index = 1, math.min(6, #links) do
        local link = links[index]
        local row = DashboardParts.Row(tile, index, link.label, "copy", "textPrimary", "accent")

        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function()
            SYL.Links.ShowCopyBox(link)
        end)
    end

    DashboardParts.Caption(tile, "Click one to copy it.")
end

-- Recording ---------------------------------------------------------------
DashboardWidgets.RENDERERS.recording = function(tile)
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings or {}

    local drops = SYL.GetAllDrops()
    local nights = SYL.RaidSession.RaidsOnly(SYL.GetAllRaids())

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

    local when = SYL.Theme.CreateText(
        tile.body, SYL.Theme.sizes.rowSmall, stale and "warning" or "textMuted"
    )

    when:SetPoint("RIGHT", -2, 0)
    when:SetJustifyH("RIGHT")
    when:SetText(
        #drops .. " drops, " .. #nights .. " nights"
        .. (stale
            and " · nothing captured yet"
            or (" · last captured " .. SYL.Utilities.FormatDateTime(latest)))
    )

    local summary = SYL.Theme.CreateText(
        tile.body, SYL.Theme.sizes.rowSmall, "textPrimary"
    )

    summary:SetPoint("LEFT", 2, 0)
    summary:SetPoint("RIGHT", when, "LEFT", -12, 0)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetText(table.concat(pieces, "   ·   "))
end

-- Waiting on the calendar -------------------------------------------------
--
-- Declared rather than omitted. A tile that says what it is waiting for is
-- honest; a missing tile reads as a bug, and a blank one reads as broken.
DashboardWidgets.RENDERERS.nextNight = function(tile)
    DashboardParts.Empty(tile,
        "Waiting on the calendar.\n\nThis will show the next raid night and "
        .. "who has signed up, read from your in-game guild calendar.")

    DashboardParts.Caption(tile, "Not built yet.")
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
