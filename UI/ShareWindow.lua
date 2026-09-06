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

-- FIVE LINES, NOT FOUR. The raid nights joined the block when they started
-- travelling with the drops -- see Core/HistorySync.lua's Nights -- and the
-- block is anchored off this number rather than measuring itself, so a line
-- added without moving it would have drawn straight through SEND TO.
local FACTS_HEIGHT = 5 * 15

local TARGET_TOP = FACTS_TOP + 18 + FACTS_HEIGHT + 14

-- Heading, box, then one row for either the count of who is online or the
-- reason the typed name cannot be reached. ONE ROW FOR BOTH, so nothing below
-- moves when an error appears -- a window that grows as you type is a window
-- whose Send button is somewhere else by the time you reach for it.
local BOX_TOP = TARGET_TOP + 16
local NOTE_TOP = BOX_TOP + 20 + 8
local BAR_TOP = NOTE_TOP + 15 + 20

local WINDOW_HEIGHT = BAR_TOP + 14 + 60
local PAD = 20
local CONTENT = WINDOW_WIDTH - PAD * 2

local frame
local bodyText
local factsText
local targetBox
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

-- WHAT THE BOX SUGGESTS IS THE WHOLE GUILD, NOT ONLY WHO IS ONLINE.
--
-- Aimee, 2026-09-06: "search by typing in name to sync loot history and
-- autofill the name. show an error if the player is not online." Those are two
-- halves of one behavior and the second one is why the first list is wide.
--
-- A picker that offers only online names cannot answer "why is Nychar not
-- here" -- their absence is the error, delivered as nothing at all, which is
-- the failure mode this addon keeps finding. So every guild member is
-- offerable, the row says which ones are online, and a name that cannot be
-- reached is refused in words when it is picked.
function ShareWindow.Candidates()
    local entries = {}
    local me = SYL.Utilities.GetPlayerFullName()

    for _, member in pairs(SYL.Guild.GetMembers()) do
        if member.name ~= me then
            table.insert(entries, {
                name = member.name,
                class = member.class,
                isOnline = member.isOnline and true or false,
            })
        end
    end

    return entries
end

-- Online is the fact that decides whether the button will work, so it is the
-- one the row carries -- ahead of the class, which is decoration here.
function ShareWindow.Note(entry)
    if not entry.isOnline then
        return "offline"
    end

    return SYL.ClassColor and SYL.ClassColor.Label(entry.class) or "online"
end

-- Whether a typed name can be sent to, and why not. Returns ok, reason.
--
-- MATCHED THE WAY THE WHISPER WILL BE ADDRESSED. The roster spells a name on
-- your own realm without one and the box may have either -- see
-- Utilities.SameCharacter, and the day this feature did nothing because
-- "Nychar" and "Nychar-Area52" were not the same string.
function ShareWindow.Check(name)
    if type(name) ~= "string" or name:gsub("%s+", "") == "" then
        return false, nil
    end

    local me = SYL.Utilities.GetPlayerFullName()

    if SYL.Utilities.SameCharacter(name, me or "") then
        return false, "That is you. Pick somebody else."
    end

    for _, member in pairs(SYL.Guild.GetMembers()) do
        if SYL.Utilities.SameCharacter(member.name, name) then
            if member.isOnline then
                return true, nil
            end

            return false, SYL.Utilities.ShortName(member.name)
                .. " is not online. A whisper cannot reach somebody who is "
                .. "not logged in."
        end
    end

    return false, SYL.Utilities.ShortName(name)
        .. " is not in the guild, or has not been seen from here yet."
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
        -- THE LINE THE WHOLE TRANSFER TURNED OUT TO NEED. Without the
        -- nights a receiver divides complete loot by their own
        -- attendance, which is how one officer's board read "of 4"
        -- against a season that had run nine. Core/HistoryPayload.lua
        -- has the measurement.
        .. SYL.Utilities.Count(summary.nights, "guild raid night")
        .. ", so their attendance matches yours\n"
        .. summary.messages .. " messages, about "
        .. SYL.Utilities.Count(minutes, "minute")
        .. " at the pace the client allows"
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function ShareWindow.Send()
    if not target or target == "" then
        return false, "type a name to send to first"
    end

    -- CHECKED AT THE PRESS, not only as it was typed. Somebody can log out in
    -- the seconds between their name being picked and Send being pressed, and
    -- the refusal that matters is the one for the state things are in now.
    local reachable, why = ShareWindow.Check(target)

    if not reachable then
        return false, why or "that name cannot be sent to"
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

        -- AND PUT THE WORDS BACK. This cleared the bar and left the prose,
        -- which on the sending path reads "Going out now, four messages a
        -- second". Two ways out of a transfer never call Refresh -- it
        -- finishing, and them declining -- so the window sat there describing
        -- a send that had already stopped, over an empty bar.
        bodyText:SetText(ShareWindow.Describe())

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

    -- A NAME YOU TYPE, NOT A NAME YOU CYCLE TO.
    --
    -- The button here pressed through the online guild members one at a time,
    -- which is one click at four names and forty at forty. Aimee asked for the
    -- box instead, and the box is also what makes an honest refusal possible:
    -- a cycle can only ever offer names it is willing to send to, so a name
    -- that is missing is an error delivered as silence.
    --
    -- Bordered, because UI/SearchBox.lua reserves the outline for a field that
    -- is a value rather than a filter, and this one is a value -- nothing
    -- happens to it until Send is pressed.
    targetBox = SYL.SearchBox.Create(
        frame, 200, "Type a name...",
        function(text)
            target = text

            ShareWindow.RefreshTarget()
        end,
        { bordered = true }
    )

    targetBox:SetPoint("TOPLEFT", PAD, -BOX_TOP)

    -- OPENS OVER THE HEADING, NOT OVER THE BOX. Two pixels above the box is
    -- where "SEND TO" is drawn, and the row below the box is where the offline
    -- error goes -- so the default anchor covered both the label of the
    -- control being used and the answer it was about to give.
    --
    -- THREE ROWS, AND THE NUMBER WAS MEASURED RATHER THAN CHOSEN. Four is 102
    -- pixels tall and reaches eleven past the WHAT GOES heading; three is 82
    -- and clears it by nine. tools/test_layout.py does that arithmetic off
    -- these constants, so a taller row or a fifth fact moves it and says so.
    -- Six -- NameSuggest's own cap -- would reach the third paragraph.
    SYL.NameSuggest.Attach(targetBox, {
        getCandidates = ShareWindow.Candidates,
        noteFor = ShareWindow.Note,
        above = toHeading,
        maxRows = 3,
        onAccept = function(name)
            target = name

            ShareWindow.RefreshTarget()
        end,
    })

    targetNote = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    targetNote:SetPoint("TOPLEFT", PAD, -NOTE_TOP)
    targetNote:SetWidth(CONTENT)
    targetNote:SetJustifyH("LEFT")
    targetNote:SetWordWrap(false)

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

-- ONE ROW, TWO JOBS, and it is deliberate that they share it.
--
-- Empty box: how many people could be sent to at all, which is the thing
-- somebody wants to know before they start typing. Typed name: whether that
-- one can, and why not. Neither pushes the other down the window, so the
-- Send button does not move while a name is being entered.
function ShareWindow.RefreshTarget()
    if not frame then
        return
    end

    local typed = target or ""

    if typed:gsub("%s+", "") == "" then
        local names = ShareWindow.Targets()

        Theme.SetTextColor(targetNote, "textMuted")

        targetNote:SetText(#names == 0
            and "nobody in the guild is online right now"
            or (SYL.Utilities.Count(#names, "guild member")
                .. " online · start typing a name"))

        return
    end

    local reachable, why = ShareWindow.Check(typed)

    if reachable then
        Theme.SetTextColor(targetNote, "textMuted")
        targetNote:SetText("online · ready to send")

        return
    end

    -- Said in the color the rest of the addon says refusals in, because a
    -- muted line here reads as a hint and this one is the reason the button
    -- will not work.
    Theme.SetTextColor(targetNote, "warning")
    targetNote:SetText(why or "")
end

function ShareWindow.Refresh()
    if not frame then
        return
    end

    bodyText:SetText(ShareWindow.Describe())
    factsText:SetText(ShareWindow.Facts())

    ShareWindow.RefreshTarget()

    UpdateProgress()
end

function ShareWindow.Show()
    local window = CreateWindow()

    -- NOT PREFILLED. The cycle button had to start somewhere and picked the
    -- first name online, which meant Send always had a target -- including the
    -- one time somebody pressed it without reading. A box that starts empty
    -- asks the question instead of answering it.
    target = targetBox and targetBox.editBox:GetText() or ""

    ShareWindow.Refresh()

    -- The bar has to move on its own while the send runs, and nothing else on
    -- screen changes to prompt a redraw. Started here and STOPPED ON HIDE --
    -- which is what the comment used to claim while no OnHide existed, so the
    -- ticker ran every half second for the rest of the session after the
    -- window was first opened.
    if C_Timer and C_Timer.NewTicker and not ticker then
        ticker = C_Timer.NewTicker(0.5, function()
            if frame and frame:IsShown() then
                UpdateProgress()
            end
        end)
    end

    window:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)

    SYL.WindowStack.ShowWindow(window)

    return window
end
