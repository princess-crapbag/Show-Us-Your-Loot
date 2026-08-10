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
DashboardWidgets.RENDERERS.readiness = function(tile)
    local roster = SYL.RaidTeam.Filter(SYL.RosterData.Build())

    if #roster == 0 then
        DashboardParts.Empty(tile,
            "Nobody is marked as being on the raid team. Open Raiders and tick "
            .. "the TEAM column.")

        return
    end

    local counts = SYL.RaidTeam.CountRoles(roster)

    DashboardParts.Headline(tile, #roster, "on the team")

    local index = 1

    if SYL.Features.IsEnabled("raidBuffs") then
        local coverage = SYL.RaidBuffs.BuildCoverage(roster)
        local covered, total = SYL.RaidBuffs.Summarise(coverage)
        local missing = SYL.RaidBuffs.Missing(coverage)

        for position = 1, math.min(2, #missing) do
            local buff = missing[position]

            DashboardParts.Row(tile, index + 1,
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

        DashboardParts.Row(tile, index + 1,
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
            "No links yet. Add your guild's Warcraft Logs, Raider.IO or Discord "
            .. "in Settings — clicking one opens a box to copy from, because "
            .. "an addon cannot open a browser.")

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

    local summary = SYL.Theme.CreateText(
        tile.body, SYL.Theme.sizes.rowSmall, "textPrimary"
    )
    summary:SetPoint("TOPLEFT", 2, -2)
    summary:SetText(table.concat(pieces, "   ·   "))

    -- The whole point of this widget: a date three weeks old says something
    -- is wrong far faster than a total that is merely lower than expected.
    DashboardParts.Caption(tile,
        #drops .. " drops, " .. #nights .. " nights this season"
        .. (latest > 0
            and (" · last captured " .. SYL.Utilities.FormatDateTime(latest))
            or " · nothing captured yet"),
        latest == 0 and "warning" or "textMuted")
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
        DashboardParts.Empty(tile, "This widget could not be drawn.")
        DashboardParts.Caption(tile, tostring(err), "warning")

        SYL:DebugPrint("Widget " .. tostring(widget.key) .. " failed: " .. tostring(err))
    end
end
