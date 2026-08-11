-- UI/RaidersRoster.lua
--
-- The roster half of the Raiders tab: everybody who could raid, who is on the
-- team, and what they play.
--
-- WHY IT IS A VIEW RATHER THAN A TAB. The board and the roster are the same
-- people asked two different questions — "who is owed loot" and "who is on the
-- team" — and the answer to the second decides who appears in the first. Two
-- tabs made that a navigation problem; a toggle makes it a glance.
--
-- TICKING TEAM HERE IS WHAT THE SCOPE BUTTON READS. That is the whole reason
-- this belongs on the same screen: the board says "only players marked as
-- being on the raid team" and, until now, marking them meant leaving the tab.
--
-- THE FULL ROSTER WINDOW STILL EXISTS and is one button away. Searching,
-- buff coverage and adding somebody who has not joined the guild yet all live
-- there, and none of them belong in a list whose job is a column of ticks.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersRoster = {}
SYL.RaidersRoster = RaidersRoster

local ROW_HEIGHT = 22

local COLUMNS = {
    tick = 4,
    name = 26,
    role = 190,
    nights = 280,
    note = 340,
}

RaidersRoster.ROW_HEIGHT = ROW_HEIGHT

local ROLE_LABELS = {
    TANK = "Tank",
    HEALER = "Healer",
    DPS = "DPS",
}

function RaidersRoster.Build()
    local roster = SYL.RosterData.Build()

    roster = SYL.Audience.Filter(roster, SYL.Audience.Get())

    -- Team first, then by name. An officer opening this is either checking who
    -- is marked or looking for somebody to mark, and both start at the top.
    table.sort(roster, function(left, right)
        local leftTeam = SYL.RaidTeam.IsMember(left.key)
        local rightTeam = SYL.RaidTeam.IsMember(right.key)

        if leftTeam ~= rightTeam then
            return leftTeam
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return roster
end

function RaidersRoster.CreateRow(parent, index, listTop, onChanged)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(listTop + (index - 1) * ROW_HEIGHT))
    row:SetWidth(600)

    local hover = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    hover:SetAllPoints()
    hover:Hide()

    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    -- The tick is its own button so clicking a name can select the person
    -- without also changing whether they are on the team. Those are different
    -- intentions and one row used to serve both.
    row.tick = CreateFrame("Button", nil, row)
    row.tick:SetSize(14, 14)
    row.tick:SetPoint("LEFT", COLUMNS.tick, 0)

    row.tickEdge = Theme.CreateSolidTexture(row.tick, "border", "BACKGROUND")
    row.tickEdge:SetAllPoints()

    row.tickFill = Theme.CreateSolidTexture(row.tick, "window", "ARTWORK")
    row.tickFill:SetPoint("TOPLEFT", 1, -1)
    row.tickFill:SetPoint("BOTTOMRIGHT", -1, 1)

    row.tickMark = Theme.CreateSolidTexture(row.tick, "accent", "OVERLAY")
    row.tickMark:SetSize(8, 8)
    row.tickMark:SetPoint("CENTER")
    row.tickMark:Hide()

    row.tick:SetScript("OnClick", function()
        if row.entryKey then
            SYL.RaidTeam.Toggle(row.entryKey)
            onChanged()
        end
    end)

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", COLUMNS.name, 0)
    row.name:SetWidth(COLUMNS.role - COLUMNS.name - 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Cycles rather than opening a menu: three values, and a menu for three
    -- values is two clicks where this is one.
    row.role = Theme.CreateButton(row, 62, 17, "", function()
        if row.entryKey then
            SYL.RaidTeam.CycleRole(row.entryKey)
            onChanged()
        end
    end)

    row.role:SetPoint("LEFT", COLUMNS.role, 0)

    row.nights = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.nights:SetPoint("LEFT", COLUMNS.nights, 0)
    row.nights:SetWidth(50)
    row.nights:SetJustifyH("RIGHT")

    row.note = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.note:SetPoint("LEFT", COLUMNS.note, 0)
    row.note:SetWidth(200)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)

    return row
end

function RaidersRoster.DrawRow(row, entry, isSelected)
    row.entryKey = entry.key

    row.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(
            row.name, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(row.name, "textPrimary")
    end

    if SYL.RaidTeam.IsMember(entry.key) then
        row.tickMark:Show()
    else
        row.tickMark:Hide()
    end

    -- A detected role is shown but reads muted, so "this is what they queued
    -- as" and "this is what an officer decided" are not the same thing on
    -- screen.
    local chosen = SYL.RaidTeam.GetChosenRole(entry.key)
    local role = chosen or SYL.RaidTeam.GetRole(entry.key)

    row.role.label:SetText(role and (ROLE_LABELS[role] or role) or "—")

    Theme.SetTextColor(
        row.role.label,
        chosen and "textPrimary" or "textMuted"
    )

    row.nights:SetText(entry.nights and entry.nights > 0 and entry.nights or "—")

    local note = ""

    if entry.isIncoming then
        note = "joining"
    elseif entry.isAlt then
        note = "alt of " .. tostring(entry.mainName or "?")
    elseif entry.daysOffline and entry.daysOffline >= 30 then
        note = entry.daysOffline .. " days offline"
    elseif entry.rank then
        note = tostring(entry.rank)
    end

    row.note:SetText(note)

    if isSelected then
        Theme.SetTextColor(row.note, "accent")
    else
        Theme.SetTextColor(row.note, "textMuted")
    end

    row:Show()
end

--------------------------------------------------------------------------
-- Drawing the view
--------------------------------------------------------------------------

-- Takes a context rather than reaching into the panel, so the panel keeps
-- ownership of its own state and this file stays a renderer. `selected` is the
-- score entry for whoever is highlighted, already resolved — the detail pane
-- answers about the same person in both views, so switching does not lose them.
function RaidersRoster.Refresh(ctx)
    local frame = ctx.frame
    local roster = RaidersRoster.Build()

    local offset = math.min(
        ctx.offset or 0, math.max(0, #roster - ctx.visibleRows)
    )

    for _, row in ipairs(ctx.boardRows) do
        row:Hide()
    end

    frame.average:Hide()

    if #roster == 0 then
        for _, row in ipairs(ctx.rosterRows) do
            row:Hide()
        end

        frame.empty:SetText(
            SYL.Audience.ExplainEmpty(SYL.Audience.Get(), 0)
            or "Nobody on the roster yet. It is built from your guild list."
        )
        frame.empty:Show()

        SYL.RaidersDetail.Render(frame.detail, nil)
        frame.caption:SetText("")

        return
    end

    frame.empty:Hide()

    for index = 1, ctx.visibleRows do
        local entry = roster[index + offset]
        local row = ctx.rosterRows[index]
            or RaidersRoster.CreateRow(frame, index, ctx.listTop, ctx.onChanged)

        ctx.rosterRows[index] = row

        if entry then
            RaidersRoster.DrawRow(row, entry, entry.key == ctx.selectedKey)
        else
            row:Hide()
        end
    end

    SYL.RaidersDetail.Render(frame.detail, ctx.selected)

    frame.caption:SetText(
        #roster .. " on the roster · " .. SYL.RaidTeam.Count()
        .. " marked as raiding · tick TEAM to add somebody"
    )
end
