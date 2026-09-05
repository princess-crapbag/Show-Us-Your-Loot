-- UI/RosterSendWindow.lua
--
-- "Send my raid team." Three choices, and nothing happens until one is
-- pressed.
--
-- WHY IT IS A WINDOW NOW. The button used to broadcast to the whole guild on
-- the press, which was one of four ways a roster went out and the only
-- deliberate one. Aimee: "lets change this to have a button to share it with
-- individual players, all raid roster players (and their alts), or all guild.
-- let it be a button we press to send it rather than always happening on
-- login."
--
-- The other three are gone or behind the switch. See Core/Events.lua.
--
-- THE COST OF EACH CHOICE IS ON THE ROW. The guild is one message per raider;
-- a whisper is one message per raider PER PERSON, so eleven raiders to eleven
-- teammates is 121 messages and about half a minute of trickle. That is a
-- real difference and it belongs where the choice is made, not in a note
-- afterwards -- the same rule Core/HistorySync.lua follows for the four
-- minutes a season takes.
--
-- Send holds the whole job and touches no frame, for the reason
-- UI/ClearSeasonDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local RosterSendWindow = {}
SYL.RosterSendWindow = RosterSendWindow

local WINDOW_WIDTH = 320
local PAD = 16
local CONTENT = WINDOW_WIDTH - PAD * 2

local HEADER = 52
local BODY_LINE = 15
-- 38, NOT 34. The label is size 11 from the top at 5 (ending 19.85) and the
-- note is size 9 from the bottom at 5 (starting H - 17.15). They need
-- H >= 37 not to intersect; at 34 they overlapped by three pixels in every
-- row of the window.
local CHOICE_HEIGHT = 38
local CHOICE_GAP = 6
local FOOTER = 46

local frame
local bodyText
local choiceRows = {}

local target

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

RosterSendWindow.BODY =
    "Nothing is sent unless you press one of these. Your roster no longer "
    .. "goes out on its own at login or when you tick somebody."

-- The one-player target cycles through online guild members, the same way
-- the loot history window picks a name.
function RosterSendWindow.Targets()
    local names = {}
    local me = SYL.Utilities.GetPlayerFullName()

    for _, member in pairs(SYL.Guild.GetMembers()) do
        if member.isOnline
            and not SYL.Utilities.SameCharacter(member.name, me)
        then
            table.insert(names, member.name)
        end
    end

    table.sort(names)

    return names
end

function RosterSendWindow.NextTarget(current)
    local names = RosterSendWindow.Targets()

    if #names == 0 then
        return nil
    end

    for index, name in ipairs(names) do
        if name == current then
            return names[(index % #names) + 1]
        end
    end

    return names[1]
end

-- Each row: what it does, what it costs, and who it reaches.
function RosterSendWindow.Choices()
    local mine = #SYL.RosterSync.Own()
    local team = SYL.RosterSync.TeamTargets()
    local online = RosterSendWindow.Targets()

    local function Messages(count)
        if count == 0 then
            return "nothing to send"
        end

        return SYL.Utilities.Count(count, "message")
    end

    return {
        {
            scope = "player",
            label = "One player",
            value = target and SYL.Utilities.ShortName(target)
                or (#online > 0 and "pick a name" or "nobody online"),
            note = #online > 0
                and (SYL.Utilities.Count(#online, "guild member")
                    .. " online · " .. Messages(mine))
                or "no one in the guild is online",
            enabled = #online > 0,
        },
        {
            scope = "team",
            label = "The raid team",
            value = SYL.Utilities.Count(#team, "person", "people"),
            note = #team > 0
                and ("their alts included · " .. Messages(mine * #team))
                or "nobody on the team is online right now",
            enabled = #team > 0,
        },
        {
            scope = "guild",
            label = "The whole guild",
            value = "everyone",
            note = "one broadcast · " .. Messages(mine),
            enabled = mine > 0,
        },
    }
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function RosterSendWindow.Send(scope)
    local sent, reason, people = SYL.RosterSync.SendNow(scope, target)

    if not sent then
        return false, reason
    end

    local message = "Sent your raid team of " .. sent

    if scope == "guild" then
        message = message .. " to the guild."
    elseif people == 1 then
        message = message .. " to " .. SYL.Utilities.ShortName(target) .. "."
    else
        message = message .. " to "
            .. SYL.Utilities.Count(people, "person", "people") .. "."
    end

    -- Says what it did NOT do. Somebody pressing this expects it to keep
    -- working, and the switch that makes it continuous is on another screen.
    if not SYL.Features.IsEnabled("rosterSharing") then
        message = message
            .. " That was once — turn on Share roster in settings to keep "
            .. "them up to date as you change it."
    end

    SYL:Print(message)

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function CreateChoice(parent, index)
    local row = CreateFrame("Button", nil, parent)

    row:SetSize(CONTENT, CHOICE_HEIGHT)
    row:SetPoint("TOPLEFT", PAD,
        -(HEADER + BODY_LINE * 3 + (index - 1) * (CHOICE_HEIGHT + CHOICE_GAP)))

    row.background = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
    row.background:SetAllPoints()

    row.label = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.label:SetPoint("TOPLEFT", 10, -5)

    row.value = Theme.CreateText(row, Theme.sizes.rowSmall, "accent")
    row.value:SetPoint("TOPRIGHT", -10, -5)
    row.value:SetJustifyH("RIGHT")

    row.note = Theme.CreateText(row, Theme.sizes.tiny, "textMuted")
    row.note:SetPoint("BOTTOMLEFT", 10, 5)
    row.note:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self.background:SetColorTexture(unpack(Theme.colors.rowHover))
    end)

    row:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(unpack(Theme.colors.rowAlt))
    end)

    return row
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootRosterSendWindow", UIParent, "BackdropTemplate"
    )

    frame:SetSize(
        WINDOW_WIDTH,
        HEADER + BODY_LINE * 3 + (CHOICE_HEIGHT + CHOICE_GAP) * 3 + FOOTER
    )

    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local mark = Theme.CreateAccentMark(frame)
    mark:SetPoint("TOPLEFT", 14, -16)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    title:SetText("Send my raid team")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 14, -42)
    separator:SetPoint("TOPRIGHT", -14, -42)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -HEADER)
    bodyText:SetWidth(CONTENT)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)
    bodyText:SetText(RosterSendWindow.BODY)

    for index = 1, 3 do
        choiceRows[index] = CreateChoice(frame, index)
    end

    local close = Theme.CreateButton(frame, 80, 22, "Close", function()
        frame:Hide()
    end)

    close:SetPoint("BOTTOMRIGHT", -PAD, 14)

    local corner = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    corner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

function RosterSendWindow.Refresh()
    if not frame then
        return
    end

    for index, choice in ipairs(RosterSendWindow.Choices()) do
        local row = choiceRows[index]

        row.label:SetText(choice.label)
        row.value:SetText(choice.value)
        row.note:SetText(choice.note)

        Theme.SetTextColor(row.value, choice.enabled and "accent" or "textMuted")
        Theme.SetTextColor(row.label,
            choice.enabled and "textPrimary" or "textMuted")

        -- BOTH BUTTONS IN ONE HANDLER, and the version with two was a way to
        -- broadcast the roster by accident.
        --
        -- A Button registered for RightButtonUp fires OnMouseUp AND THEN
        -- OnClick. So right-clicking to change the name ran the cycle, set a
        -- target, and then fell straight through the "no target yet" guard in
        -- OnClick into Send -- sending the roster to whoever the cycle had
        -- just landed on, which is the opposite of what the control said it
        -- did. UI/Widgets.lua's row helper registers LeftButtonUp only, for
        -- exactly this reason.
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnMouseUp", nil)

        row:SetScript("OnClick", function(_, button)
            -- Right-click moves to the next name and stops there, so a wrong
            -- name is not something you have to send your way out of.
            if button == "RightButton" then
                if choice.scope == "player" then
                    target = RosterSendWindow.NextTarget(target)

                    RosterSendWindow.Refresh()
                end

                return
            end

            -- A choice that cannot do anything says so rather than being a
            -- button that swallows the press. Greyed and silent is how
            -- somebody decides the window is broken.
            if not choice.enabled then
                SYL:Print("Nothing sent: " .. choice.note .. ".")

                return
            end

            -- ONE PLAYER CYCLES BEFORE IT SENDS. The row is both the chooser
            -- and the trigger, so the first press picks a name and the press
            -- on a name that is already chosen is the one that sends. A
            -- separate picker for a list that is usually four names long
            -- would be two clicks where this is one.
            if choice.scope == "player" and not target then
                target = RosterSendWindow.NextTarget(nil)

                RosterSendWindow.Refresh()

                return
            end

            local ok, reason = RosterSendWindow.Send(choice.scope)

            if not ok then
                SYL:Print("Nothing sent: " .. tostring(reason) .. ".")
            end

            RosterSendWindow.Refresh()
        end)

    end
end

function RosterSendWindow.Show()
    local window = CreateWindow()

    RosterSendWindow.Refresh()

    SYL.WindowStack.ShowWindow(window)

    return window
end
