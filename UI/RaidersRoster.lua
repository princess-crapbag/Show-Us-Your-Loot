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

function RaidersRoster.CreateRow(parent, index, listTop, onChanged, onSelect)
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
            SYL.RosterSync.OnOwnRosterChanged()
            onChanged()
        end
    end)

    -- CLICKING A NAME SELECTS IT, which it never did here. The tick box had
    -- the only handler on the row, so the whole roster view was unclickable
    -- and the detail pane beside it could not be filled from this view at all
    -- — while RaidersRoster.Refresh took a selectedKey and compared every row
    -- against it, so the highlight was drawn for a selection nothing could
    -- make. The board view has had this since it was written.
    row:SetScript("OnClick", function()
        if row.entryKey and onSelect then
            onSelect(row.entryKey)
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
            SYL.RosterSync.OnOwnRosterChanged()
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

    -- Right-click to copy the name. Read on the click, not captured: rows are
    -- pooled and reused as the list scrolls.
    SYL.Widgets.AttachNameCopy(row, function()
        return row.entryName
    end)

    return row
end

function RaidersRoster.DrawRow(row, entry, isSelected)
    row.entryKey = entry.key
    -- Kept beside the key because the copy handler wants what is on screen,
    -- and the key is a GUID.
    row.entryName = entry.name

    row.name:SetText(tostring(entry.name or "Unknown"))

    SYL.ClassColor.Set(row.name, entry.class)

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
    -- BEFORE THE ALT TEST AND BEFORE THE RANK. Somebody who has left the guild
    -- is on this list only because they are still ticked onto the raid team,
    -- and that is the one thing the row has to say -- otherwise it is a name
    -- with a tick and no explanation for why it is above the guildies.
    elseif entry.isFormer then
        note = "not in the guild any more"
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
-- A roster somebody else sent
--------------------------------------------------------------------------

-- The undo, on the screen that shows the thing. Aimee's rule is that anything
-- which can be created has to be removable from the same place, and a shared
-- roster is the sharpest case of it: the person looking at these ticks never
-- made a single one, so without this there is no route at all from "why is
-- this list not mine" to it not being there.
--
-- Built lazily, so a client that has never received a roster never creates the
-- frame.
--
-- HELD HERE AND NOT ON THE FRAME. A stub frame in the test suite answers every
-- field with a function, so `frame.sharedClear` is truthy before it has ever
-- been created and the nil check that looks like a nil check is not one — it
-- returns the stub and the next call indexes a function. UI/KeysPanel.lua
-- keeps its view state in locals for exactly this reason, and this file cost
-- four assertions in test_raiderspanel learning it again.
local sharedClear

local function SharedControl(frame, onChanged)
    if sharedClear then
        return sharedClear
    end

    sharedClear =
        Theme.CreateButton(frame, 104, 18, "Clear shared", function()
            SYL.SharedRoster.Clear()

            -- Says what it did *not* touch. Clearing a list of ticks that
            -- includes your own would be the obvious fear, and the answer is
            -- in the message rather than in the documentation.
            SYL:Print(
                "Shared roster cleared. Anyone you marked yourself is untouched."
            )

            onChanged()
        end)

    sharedClear:SetPoint("BOTTOMRIGHT", -2, 1)

    return sharedClear
end

-- THE SEND BUTTON, and it is always there rather than appearing with a state.
--
-- Sharing used to be a switch in the settings panel and nothing else, which
-- put the only way to give somebody your roster three screens away from the
-- roster. Worse, the switch reads like the way to GET one -- Aimee's officer
-- read it exactly that way, turned it on, and became a second broadcaster
-- whose empty team wiped the guild's. Core/RosterSync.lua has the account.
--
-- A button on the screen that holds the thing being sent is the fix for both
-- halves: it is where somebody looks for it, and it cannot be mistaken for a
-- way to receive, because it says Send.
--
-- HELD IN A LOCAL for the reason the block above gives about stub frames.
local sharedSend

local function SendControl(frame)
    if sharedSend then
        return sharedSend
    end

    sharedSend =
        Theme.CreateButton(frame, 112, 18, "Send my roster", function()
            local sent, reason = SYL.RosterSync.SendNow()

            if not sent then
                SYL:Print("Nothing sent: " .. tostring(reason) .. ".")

                return
            end

            -- Says what it did and what it did not. Somebody who presses this
            -- expecting it to keep working needs to know it was one send, and
            -- where the switch that makes it continuous lives.
            local message = "Sent your raid team of " .. sent
                .. " to the guild."

            if not SYL.Features.IsEnabled("rosterSharing") then
                message = message
                    .. " That was once. Turn on Share roster in settings to "
                    .. "keep them up to date as you change it."
            end

            SYL:Print(message)
        end)

    return sharedSend
end

-- THE WAY BACK TO A QUESTION SOMEBODY CLOSED.
--
-- UI/SharedRosterPrompt.lua treats Escape as "not now" rather than as no --
-- dismissing a box is not an answer -- which leaves an offer sitting in the
-- database with nothing on screen pointing at it. This is that pointer, and
-- it only exists while there is something to point at.
local sharedOffer

local function OfferControl(frame)
    if sharedOffer then
        return sharedOffer
    end

    sharedOffer =
        Theme.CreateButton(frame, 108, 18, "Roster offered", function()
            SYL.SharedRosterPrompt.Show()
        end)

    return sharedOffer
end

-- Right to left, in the order the buttons are listed, skipping the ones that
-- are not showing. Anchored rather than chained off each other because the
-- one in the middle is the one that comes and goes, and a chain breaks at
-- exactly the link that disappears.
local GAP = 8

local function LayOutButtons(buttons)
    local offset = 2

    for _, button in ipairs(buttons) do
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", -offset, 1)
        button:Show()

        offset = offset + button:GetWidth() + GAP
    end

    -- What the caption has left. Returned rather than assumed, because a
    -- caption running under a button is the defect this file has already
    -- fixed once on the board above it.
    return offset
end

-- Two states, and the caption carries the difference: a roster of your own
-- says how to add to it, a shared one says who it came from. Somebody who does
-- not know the feature exists has to be able to work out why a list they never
-- filled in is full.
local function DrawSharedState(frame, onChanged)
    local source = SYL.SharedRoster.Source()
    local shared = SYL.SharedRoster.HasShared() and source
    local offer = SYL.SharedRoster.PendingOffer()

    -- Send is always here; the other two answer a state. Ordered right to
    -- left the way they are read: what is on screen now, then what you can
    -- do about it, then what is waiting.
    local showing = {}

    if shared then
        table.insert(showing, SharedControl(frame, onChanged))
    elseif sharedClear then
        sharedClear:Hide()
    end

    table.insert(showing, SendControl(frame))

    if offer then
        table.insert(showing, OfferControl(frame))
    elseif sharedOffer then
        sharedOffer:Hide()
    end

    -- The caption stops where the buttons start. Too wide is a defect the
    -- same as too narrow: a caption that runs under a button is unreadable
    -- in exactly the state that most needs reading.
    frame.caption:SetWidth(
        math.max(120, SYL.RaidersPanel.CAPTION_WIDTH - LayOutButtons(showing))
    )

    return shared or nil, offer
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
    local sharedBy, offer = DrawSharedState(frame, ctx.onChanged)

    -- Said in words as well as drawn as a button. Somebody who closed
    -- the dialog has to be able to find out from the screen that a
    -- roster is still waiting on them, rather than only from a control
    -- whose label they have to already understand.
    local waiting = offer and (
        SYL.SharedRosterPrompt.ShortName(offer.source)
        .. " is offering a raid team of " .. #(offer.members or {})
    ) or nil

    local offset = math.min(
        ctx.offset or 0, math.max(0, #roster - ctx.visibleRows)
    )

    for _, row in ipairs(ctx.boardRows) do
        row:Hide()
    end

    -- The board's raid-average marker used to be one line across the whole
    -- list and this hid it. It is drawn per row now, so hiding the board's
    -- rows above already takes it with them -- and the headings, which are the
    -- other thing that would sit over this list, are the panel's to hide
    -- before it hands over. See RaidersBoard.SetHeaderShown.

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

        -- Still says where a shared roster came from, even with nothing drawn.
        -- The two ways to arrive here are a guild list that has not loaded yet
        -- and a scope that hides everybody, and in both cases a "Clear shared"
        -- button sitting on an empty screen with no caption beside it is the
        -- one reading that makes no sense.
        frame.caption:SetText(
            waiting
            or (sharedBy
                and ("shared by " .. sharedBy .. " · nothing to show yet"))
            or ""
        )

        -- Explicit, because the caller uses this as its scroll ceiling and a
        -- bare return would hand it nil.
        return 0
    end

    frame.empty:Hide()

    for index = 1, ctx.visibleRows do
        local entry = roster[index + offset]
        local row = ctx.rosterRows[index]
            or RaidersRoster.CreateRow(
                frame, index, ctx.listTop, ctx.onChanged, ctx.onSelect
            )

        ctx.rosterRows[index] = row

        if entry then
            RaidersRoster.DrawRow(row, entry, entry.key == ctx.selectedKey)
        else
            row:Hide()
        end
    end

    SYL.RaidersDetail.Render(frame.detail, ctx.selected)

    frame.caption:SetText(
        SYL.Utilities.Count(#roster, "person", "people") .. " on the roster · "
        .. SYL.RaidTeam.Count() .. " marked as raiding · "
        .. (waiting
            or (sharedBy and ("shared by " .. sharedBy))
            -- Says where the control is. "tick TEAM" named a column heading
            -- that this view does not draw — the tick box here is the one at
            -- the start of the row, and the screen that HAS a TEAM heading is
            -- the roster window, where the heading is not a tick box.
            or "click a name, or tick the box beside it to add somebody")
    )

    -- Returned so the panel's mouse wheel has a ceiling without building this
    -- list a second time to count it.
    return #roster
end
