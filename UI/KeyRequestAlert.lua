-- UI/KeyRequestAlert.lua
--
-- "Somebody wants a key of yours." The question, on screen, at the moment it
-- is asked.
--
-- WHY IT EXISTS. An incoming request wrote one line into chat and stopped
-- there: "Pringlesbop-Illidan asked to run your key as DPS. /syl keys to
-- answer." On a raid night that line is gone in ten seconds, and the only way
-- back to it was a slash command -- which is the one thing this addon has
-- decided a feature may never require. The Keys tab has carried the durable
-- list all along; what was missing was anything that says so while somebody
-- is still standing at the summoning stone waiting for an answer.
--
-- WHY CLOSING IT IS SAFE, and this is the order the two were built in rather
-- than an accident. Core/KeystoneRequests.lua's header has said "a dismissed
-- request is not a lost request" since before there was a popup to dismiss:
-- Hide takes the row off the badge and leaves it on the Keys tab until the
-- weekly reset. A popup you can close is only acceptable on top of a list
-- that cannot lose anything, and the list was first.
--
-- THE SHAPE IS UI/HistoryPrompt.lua'S. That is this addon's answer to
-- "somebody has asked you something", and a second answer to the same
-- question is how two dialogs drift apart -- one growing a corner close
-- button, the other not; one escapable, the other not.
--
-- IT NAMES THE KEY, which is new and is not decoration. A request can now be
-- delivered to whichever character of a person is logged in, so "your key" is
-- a question with as many answers as they have characters -- on Aimee's
-- roster one guildie held +14 and +13 on one dungeon and +15 on another. The
-- key travels with the request and is named back here, along with the
-- character it sits on and, when they differ, the character it was aimed at.
--
-- ONE AT A TIME. Two requests arriving together are two questions, and a
-- dialog that stacked would put the second under the first where nobody sees
-- it. Answering or hiding one draws the next.
--
-- Answer and Hide hold the whole job and touch no frame, for the reason
-- UI/ClearSeasonDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local KeyRequestAlert = {}
SYL.KeyRequestAlert = KeyRequestAlert

local WINDOW_WIDTH = 400
local PAD = 20
local CONTENT = WINDOW_WIDTH - PAD * 2
local LINE = 15
local BUTTON_H = 22

local frame
local titleText
local bodyText
local keyHeading
local keyText
local ownerText
local routedText
local tailText
local hideButton

local showing

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

function KeyRequestAlert.Title(request)
    return SYL.Utilities.ShortName(request and request.sender)
        .. " wants a key of yours"
end

function KeyRequestAlert.Describe(request)
    if not request then
        return ""
    end

    local who = SYL.Utilities.ShortName(request.sender)
    local role = SYL.KeystoneRequests.ROLE_LABELS[request.role]
        or request.role or "DPS"

    -- "one of your keys" only once there is more than one to mean. A client on
    -- an older build sends no key at all, and the honest sentence then is the
    -- one this feature has always printed.
    if not request.mapID then
        return who .. " wants to run your key as " .. role .. "."
    end

    return who .. " wants to run one of your keys as " .. role .. "."
end

-- Which key, and whose. Returns nil for a request from a client that did not
-- send one, which is what makes the whole block disappear rather than draw a
-- heading over an empty line.
function KeyRequestAlert.Key(request)
    if not request or not request.mapID then
        return nil
    end

    return SYL.KeystoneRequests.DescribeKey({
        mapID = request.mapID, level = request.level,
    }, false)
end

function KeyRequestAlert.Owner(request)
    if not request or not request.keyOwner then
        return nil
    end

    return "on " .. SYL.Utilities.ShortName(request.keyOwner)
end

-- WHY IT ARRIVED HERE AND NOT THERE, said only when those are different
-- places.
--
-- A request aimed at Pronglez that reaches Pringlesbop is correct behavior
-- and looks like a bug: somebody reads "wants to run your +15 Operation:
-- Floodgate" on a character that does not hold it and reasonably concludes
-- the addon has muddled two people. It has not, and one sentence is the
-- difference.
function KeyRequestAlert.Routed(request)
    if not request or not request.keyOwner then
        return nil
    end

    local here = SYL.Keystone.CharacterKey()

    if SYL.Utilities.SameCharacter(request.keyOwner, here or "") then
        return nil
    end

    return "Aimed at " .. SYL.Utilities.ShortName(request.keyOwner)
        .. ", who is not logged in. It reached you on "
        .. SYL.Utilities.ShortName(here)
        .. " because that is the character of yours that is."
end

KeyRequestAlert.TAIL =
    "Answering tells them either way. Hide takes it off the count without "
    .. "answering -- it stays on the Keys tab until the weekly reset, so "
    .. "hiding it is never the same as losing it."

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

-- The oldest question still unanswered and unhidden, which is the one to put
-- in front of somebody. Incoming already sorts unanswered first.
function KeyRequestAlert.Next()
    for _, request in ipairs(SYL.KeystoneRequests.Incoming()) do
        if request.status == SYL.KeystoneRequests.STATUS.PENDING
            and not request.dismissed
        then
            return request
        end
    end

    return nil
end

function KeyRequestAlert.Answer(status)
    if not showing then
        return false
    end

    local sender = showing.sender

    if not SYL.KeystoneRequests.Answer(sender, status) then
        return false
    end

    SYL:Print(
        "Told " .. SYL.Utilities.ShortName(sender) .. ": "
        .. (SYL.KeystoneRequests.STATUS_LABELS[status] or "?") .. "."
    )

    if SYL.KeysPanel and SYL.KeysPanel.Refresh then
        SYL.KeysPanel.Refresh()
    end

    return true
end

function KeyRequestAlert.Hide()
    if not showing then
        return false
    end

    SYL.KeystoneRequests.Dismiss(showing.sender)

    if SYL.KeysPanel and SYL.KeysPanel.Refresh then
        SYL.KeysPanel.Refresh()
    end

    return true
end

-- Prefills rather than sends, the same as the row on the Keys tab. The addon
-- does not talk unless asked, and "asked" means the person typed the message.
function KeyRequestAlert.Whisper()
    if not showing or not ChatFrame_OpenChat then
        return false
    end

    ChatFrame_OpenChat("/w " .. tostring(showing.sender) .. " ")

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- Answering closes this one and opens the next, if there is one. Written once
-- because all five buttons want it and four of them would have got it wrong.
local function Done()
    if frame then
        frame:Hide()
    end

    showing = nil

    KeyRequestAlert.Show()
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootKeyRequestAlert", UIParent, "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, 260)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local mark = Theme.CreateAccentMark(frame)
    mark:SetPoint("TOPLEFT", 16, -18)

    titleText = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    titleText:SetPoint("LEFT", mark, "RIGHT", 10, 0)

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -48)
    separator:SetPoint("TOPRIGHT", -16, -48)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -60)
    bodyText:SetWidth(CONTENT)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    keyHeading = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    keyHeading:SetText("THE KEY")

    keyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textPrimary")

    -- Anchored to the key rather than to the window, so the two read as one
    -- line however long the dungeon name turns out to be. The pool rotates
    -- and UI/KeyRows.lua's column note is the record of what that has cost.
    ownerText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")

    routedText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    routedText:SetWidth(CONTENT)
    routedText:SetJustifyH("LEFT")
    routedText:SetWordWrap(true)

    tailText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    tailText:SetWidth(CONTENT)
    tailText:SetJustifyH("LEFT")
    tailText:SetWordWrap(true)

    local footer = Theme.CreateSeparator(frame)
    footer:SetPoint("BOTTOMLEFT", 16, 42)
    footer:SetPoint("BOTTOMRIGHT", -16, 42)

    local STATUS = SYL.KeystoneRequests.STATUS

    local deny = Theme.CreateButton(frame, 56, BUTTON_H, "No", function()
        KeyRequestAlert.Answer(STATUS.DENIED)
        Done()
    end)

    deny:SetPoint("BOTTOMRIGHT", -PAD, 14)

    local maybe = Theme.CreateButton(frame, 60, BUTTON_H, "Maybe", function()
        KeyRequestAlert.Answer(STATUS.TENTATIVE)
        Done()
    end)

    maybe:SetPoint("RIGHT", deny, "LEFT", -8, 0)

    local yes = Theme.CreateButton(frame, 56, BUTTON_H, "Yes", function()
        KeyRequestAlert.Answer(STATUS.APPROVED)
        Done()
    end)

    yes:SetPoint("RIGHT", maybe, "LEFT", -8, 0)

    -- Does not close it. Somebody opening a whisper is answering in their own
    -- words and still has to press one of the three, or the asker's row sits
    -- on Waiting forever while they believe they replied.
    local whisper = Theme.CreateButton(
        frame, 72, BUTTON_H, "Whisper", KeyRequestAlert.Whisper
    )

    whisper:SetPoint("RIGHT", yes, "LEFT", -8, 0)

    -- Apart from the three answers, on the other end of the row, because it is
    -- not one of them: it is "not now", and the row stays on the Keys tab.
    hideButton = Theme.CreateButton(frame, 56, BUTTON_H, "Hide", function()
        KeyRequestAlert.Hide()
        Done()
    end)

    hideButton:SetPoint("BOTTOMLEFT", PAD, 14)

    SYL.Tooltips.Attach(
        hideButton,
        "Hide this",
        "Takes it off the count without answering. It stays on the Keys tab "
        .. "until the weekly reset, so hiding it is never the same as losing "
        .. "it."
    )

    frame:Hide()

    return frame
end

-- HOW TALL A WRAPPED BLOCK IS, ASKED TWO WAYS AND THE LARGER ANSWER TAKEN.
--
-- GetStringHeight is the right answer and it is not always available: it
-- reports zero for a font string whose frame the client has not laid out yet,
-- and this window is measured before it is ever shown. A zero there collapses
-- every block below it onto the same line and the buttons land on the text.
--
-- So the fallback is a wrap the same way Theme.MeasureText measures anything
-- else: the whole string's width divided by the column, rounded up. That is a
-- LOWER bound on the lines a real wrap needs -- words cannot be split, so
-- breaking on them can only ever use more rows than packing by pixel would --
-- which is exactly what makes taking the larger of the two safe.
local function BlockHeight(fontString, text)
    local measured = fontString:GetStringHeight() or 0

    local packed = Theme.MeasureText(Theme.sizes.rowSmall, text or "")
    local rows = math.max(1, math.ceil(packed / CONTENT))

    return math.max(measured, rows * LINE)
end

-- LAID OUT BY WALKING IT, not by a table of constants, and the reason is that
-- three of the five blocks are optional: an older build sends no key, a
-- request that landed on the character it was aimed at has nothing to explain,
-- and the dungeon name is whatever the client returns in whatever language it
-- is running. A fixed height for that is a fixed height that is wrong.
local function Layout(request)
    local y = 60

    local body = KeyRequestAlert.Describe(request)

    bodyText:SetText(body)
    y = y + BlockHeight(bodyText, body) + 12

    local key = KeyRequestAlert.Key(request)

    if key then
        keyHeading:ClearAllPoints()
        keyHeading:SetPoint("TOPLEFT", PAD, -y)
        keyHeading:Show()

        y = y + 18

        keyText:ClearAllPoints()
        keyText:SetPoint("TOPLEFT", PAD, -y)
        keyText:SetText(key)
        keyText:Show()

        local owner = KeyRequestAlert.Owner(request)

        ownerText:ClearAllPoints()
        ownerText:SetPoint("LEFT", keyText, "RIGHT", 8, 0)
        ownerText:SetText(owner or "")

        if owner then
            ownerText:Show()
        else
            ownerText:Hide()
        end

        y = y + LINE + 14
    else
        keyHeading:Hide()
        keyText:Hide()
        ownerText:Hide()
    end

    local routed = KeyRequestAlert.Routed(request)

    routedText:ClearAllPoints()
    routedText:SetPoint("TOPLEFT", PAD, -y)

    if routed then
        routedText:SetText(routed)
        routedText:Show()

        y = y + BlockHeight(routedText, routed) + 12
    else
        routedText:Hide()
    end

    tailText:ClearAllPoints()
    tailText:SetPoint("TOPLEFT", PAD, -y)
    tailText:SetText(KeyRequestAlert.TAIL)

    y = y + BlockHeight(tailText, KeyRequestAlert.TAIL)

    -- The footer rule sits 14 under the last line and the buttons 8 under
    -- that, which is UI/HistoryPrompt.lua's spacing.
    frame:SetHeight(y + 14 + 42)
end

function KeyRequestAlert.Show()
    local request = KeyRequestAlert.Next()

    if not request then
        return nil
    end

    -- Only while the feature is on. A request cannot arrive with it off, but
    -- Show is public and the Keys tab calls it.
    if not SYL.Features.IsEnabled("keyRequests") then
        return nil
    end

    local window = CreateWindow()

    showing = request

    titleText:SetText(KeyRequestAlert.Title(request))

    Layout(request)

    SYL.WindowStack.ShowWindow(window)

    return window
end

-- What the popup is currently asking about, for a test and for the Keys tab.
function KeyRequestAlert.Showing()
    return showing
end
