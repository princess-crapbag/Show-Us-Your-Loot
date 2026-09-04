-- UI/ShareWindow.lua
--
-- "Send loot history." Pick a name, press it once, watch it go.
--
-- WHY IT IS A WINDOW AND NOT A BUTTON ON THE LOOT TAB. That tab's bottom bar
-- already holds nine buttons and a summary sentence, and UI/SelectionBar.lua
-- says in its own header that there is no arrangement of nine buttons and a
-- sentence that fits -- it has collided with that summary twice. A tenth
-- button would be the third time.
--
-- A transfer also needs something the loot tab has nowhere to put: a target.
-- The roster broadcast has a button and no window because it goes to the
-- whole guild and there is nothing to choose. This one goes to one person, so
-- there is.
--
-- WHERE IT OPENS FROM: Settings -> Tools, beside "Export for Discord". That
-- is the row somebody already goes to when they want data out of this addon
-- and into somebody else's hands, and it is the only list in the addon whose
-- job is exactly that.
--
-- THE COUNTS ARE REAL AND MEASURED, not estimated. Core/HistorySync.lua
-- encodes every record to find out how many messages it actually becomes.
-- "About a minute" printed over something that takes four is how a progress
-- bar stops being believed, and this one runs long enough that somebody will
-- check it against a clock.
--
-- Send and Stop hold the whole job and touch no frame, for the reason
-- UI/ClearSeasonDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local ShareWindow = {}
SYL.ShareWindow = ShareWindow

local WINDOW_WIDTH = 460
-- MEASURED, NOT CHOSEN. The body is seven wrapped lines in its longest
-- state -- idle, which carries all three paragraphs including the one about
-- closing the window -- at 15 pixels a line from a 420-wide column. The
-- blocks below are anchored off that rather than off numbers that happened to
-- look right, because the sentence Aimee asked for is two lines long and
-- would have pushed WHAT GOES straight through the season name.
local BODY_TOP = 60
local BODY_HEIGHT = 7 * 15
local FACTS_TOP = BODY_TOP + BODY_HEIGHT + 22
local FACTS_HEIGHT = 4 * 15
local TARGET_TOP = FACTS_TOP + 18 + FACTS_HEIGHT + 14
local BAR_TOP = TARGET_TOP + 18 + 20 + 30

local WINDOW_HEIGHT = BAR_TOP + 14 + 60
local PAD = 20
local CONTENT = WINDOW_WIDTH - PAD * 2

local frame
local bodyText
local factsText
local targetButton
local targetNote
local barFill
local barText
local sendButton
local stopButton

local target
local ticker

--------------------------------------------------------------------------
-- Who can be sent to
--------------------------------------------------------------------------

-- Guild members who are online, minus ourselves. Online only, because a
-- whisper to somebody offline is not delivered and there is nothing to say
-- about it afterwards -- RCLootCouncil's own target list makes the same cut
-- for the same reason.
function ShareWindow.Targets()
    local names = {}
    local me = SYL.Utilities.GetPlayerFullName()

    for _, member in pairs(SYL.Guild.GetMembers()) do
        if member.isOnline and member.name ~= me then
            table.insert(names, member.name)
        end
    end

    table.sort(names)

    return names
end

-- Cycles rather than opening a menu, the same as every other chooser in this
-- addon. A dropdown for a list that is usually four names long is two clicks
-- where this is one, and the roster rows already taught the cycle.
function ShareWindow.NextTarget(current)
    local names = ShareWindow.Targets()

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

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

-- TWO STATES, and the sentence Aimee asked for by name is in both.
--
-- Four minutes is long enough that somebody watching a bar will wonder
-- whether they are stuck holding this window open, and the honest answer --
-- no, go and play -- is not a thing anybody should have to discover by
-- risking it. A window that LOOKS like it must stay open is one people sit in
-- front of; and the person who closes it anyway is then not sure whether they
-- broke the transfer. Neither of them should have to guess.
--
-- Said on the idle screen too, before the press, so it is read once when
-- nothing is happening rather than only while something is.
ShareWindow.KEEP_PLAYING =
    "Once the bar starts moving you can close this window and keep playing "
    .. "-- it keeps going. Stop cancels it."

function ShareWindow.Describe()
    if SYL.HistorySync.IsSending() then
        local sent = SYL.HistorySync.Progress()

        if sent > 0 then
            return "Going out now, four messages a second -- the pace the "
                .. "client allows without throwing them away.\n\n"
                .. ShareWindow.KEEP_PLAYING
        end

        return "Waiting for them to answer. Nothing is sent until they say "
            .. "yes, and they are free to say no.\n\n"
            .. ShareWindow.KEEP_PLAYING
    end

    return "Sends this season's drops to one person, with the credit you set "
        .. "by hand on them. Their board then scores the same items the same "
        .. "way yours does.\n\n"
        .. "It goes to them and to nobody else, and they are asked before "
        .. "any of it arrives.\n\n"
        .. ShareWindow.KEEP_PLAYING
end

-- Three lines, and every number in them counted rather than guessed.
function ShareWindow.Facts()
    local summary = SYL.HistorySync.Describe(SYL.GetActiveSeason())

    if summary.drops == 0 then
        return "Nothing has been recorded in " .. summary.seasonName
            .. " yet, so there is nothing to send."
    end

    local minutes = math.max(1, math.floor((summary.seconds + 30) / 60))

    return summary.seasonName .. "\n"
        .. SYL.Utilities.Count(summary.drops, "drop")
        .. ", with who won each one and who rolled\n"
        .. summary.credited .. " of them carrying credit you set by hand\n"
        .. summary.messages .. " messages, about "
        .. SYL.Utilities.Count(minutes, "minute")
        .. " at the pace the client allows"
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function ShareWindow.Send()
    if not target then
        return false, "pick somebody to send to first"
    end

    local ok, result = SYL.HistorySync.Offer(target, SYL.GetActiveSeason())

    if not ok then
        return false, result
    end

    SYL:Print(
        "Asked " .. SYL.Utilities.ShortName(target) .. " to receive "
        .. result.drops .. " drops. Nothing is sent until they say yes."
    )

    return true
end

function ShareWindow.Stop()
    SYL.HistorySync.Stop()

    SYL:Print("Stopped sending. Whatever already arrived is theirs to keep.")

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function UpdateProgress()
    if not frame or not frame:IsShown() then
        return
    end

    local sent, total = SYL.HistorySync.Progress()

    if not SYL.HistorySync.IsSending() or total == 0 then
        barFill:SetWidth(1)
        barFill:Hide()
        barText:SetText("")
        stopButton:Hide()
        sendButton:Show()

        return
    end

    sendButton:Hide()
    stopButton:Show()
    barFill:Show()

    -- Redrawn here rather than only on open: the window is usually
    -- already open when the answer lands, and the sentence that
    -- matters is the one for the state it is actually in.
    bodyText:SetText(ShareWindow.Describe())

    local fraction = math.min(1, sent / total)

    -- A zero-width texture is an error in the client, so the bar starts at one
    -- pixel rather than at nothing.
    barFill:SetWidth(math.max(1, CONTENT * fraction))

    if sent == 0 then
        barText:SetText("waiting for them to answer")
    else
        local left = math.floor((total - sent) * SYL.HistorySync.INTERVAL)

        barText:SetText(
            math.floor(fraction * 100) .. "%  ·  " .. sent .. " of " .. total
            .. " messages  ·  about "
            .. SYL.Utilities.Count(math.max(1, left), "second") .. " left"
        )
    end
end

ShareWindow.UpdateProgress = UpdateProgress

local function CreateBar(parent, top)
    local back = Theme.CreateSolidTexture(parent, "button", "BACKGROUND")

    back:SetPoint("TOPLEFT", PAD, top)
    back:SetSize(CONTENT, 14)

    barFill = Theme.CreateSolidTexture(parent, "accent", "ARTWORK")
    barFill:SetPoint("TOPLEFT", back, "TOPLEFT", 0, 0)
    barFill:SetHeight(14)
    barFill:SetWidth(1)
    barFill:Hide()

    barText = Theme.CreateText(parent, Theme.sizes.rowSmall, "textPrimary")
    barText:SetPoint("CENTER", back, "CENTER", 0, 0)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootShareWindow", UIParent, "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local mark = Theme.CreateAccentMark(frame)
    mark:SetPoint("TOPLEFT", 16, -18)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    title:SetText("Send loot history")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -48)
    separator:SetPoint("TOPRIGHT", -16, -48)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -BODY_TOP)
    bodyText:SetWidth(CONTENT)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    local goesHeading =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    goesHeading:SetPoint("TOPLEFT", PAD, -FACTS_TOP)
    goesHeading:SetText("WHAT GOES")

    factsText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    factsText:SetPoint("TOPLEFT", PAD, -(FACTS_TOP + 18))
    factsText:SetWidth(CONTENT)
    factsText:SetJustifyH("LEFT")
    factsText:SetWordWrap(true)

    local toHeading =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    toHeading:SetPoint("TOPLEFT", PAD, -TARGET_TOP)
    toHeading:SetText("SEND TO")

    targetButton = Theme.CreateButton(frame, 200, 20, "-", function()
        target = ShareWindow.NextTarget(target)

        ShareWindow.Refresh()
    end)

    targetButton:SetPoint("TOPLEFT", PAD, -(TARGET_TOP + 16))

    targetNote = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    targetNote:SetPoint("TOPLEFT", PAD, -(TARGET_TOP + 42))

    CreateBar(frame, -BAR_TOP)

    local footer = Theme.CreateSeparator(frame)
    footer:SetPoint("BOTTOMLEFT", 16, 42)
    footer:SetPoint("BOTTOMRIGHT", -16, 42)

    local close = Theme.CreateButton(frame, 80, 22, "Close", function()
        frame:Hide()
    end)

    close:SetPoint("BOTTOMRIGHT", -PAD, 14)

    sendButton = Theme.CreateButton(frame, 80, 22, "Send", function()
        local ok, reason = ShareWindow.Send()

        if not ok then
            SYL:Print("Nothing sent: " .. tostring(reason) .. ".")
        end

        ShareWindow.Refresh()
    end)

    sendButton:SetPoint("RIGHT", close, "LEFT", -8, 0)

    stopButton = Theme.CreateButton(frame, 80, 22, "Stop", function()
        ShareWindow.Stop()
        ShareWindow.Refresh()
    end)

    stopButton:SetPoint("RIGHT", close, "LEFT", -8, 0)
    stopButton:Hide()

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

function ShareWindow.Refresh()
    if not frame then
        return
    end

    bodyText:SetText(ShareWindow.Describe())
    factsText:SetText(ShareWindow.Facts())

    local names = ShareWindow.Targets()

    if #names == 0 then
        targetButton.label:SetText("nobody online")
        targetNote:SetText("guild members who are online right now")
    else
        targetButton.label:SetText(
            SYL.Utilities.ShortName(target) ~= "Somebody" and target
            or names[1]
        )
        targetNote:SetText(
            SYL.Utilities.Count(#names, "guild member")
            .. " online · click to change"
        )
    end

    UpdateProgress()
end

function ShareWindow.Show()
    local window = CreateWindow()

    target = target or ShareWindow.Targets()[1]

    ShareWindow.Refresh()

    -- The bar has to move on its own while the send runs, and nothing else on
    -- screen changes to prompt a redraw. Started here and stopped on hide, so
    -- a window nobody has opened costs nothing.
    if C_Timer and C_Timer.NewTicker and not ticker then
        ticker = C_Timer.NewTicker(0.5, function()
            if frame and frame:IsShown() then
                UpdateProgress()
            end
        end)
    end

    SYL.WindowStack.ShowWindow(window)

    return window
end
