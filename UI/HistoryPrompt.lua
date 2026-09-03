-- UI/HistoryPrompt.lua
--
-- "Somebody is sending you a season of loot." The question before the minutes.
--
-- WHY IT ASKS. Three and a half minutes of addon traffic and a few hundred
-- rows written into somebody's database is not a thing to do to a person
-- because you clicked their name on your own screen. RCLootCouncil reached
-- the same conclusion and their Modules/Sync.lua is where the shape of this
-- came from: request, then answer, then data.
--
-- WHY IT SHOWS THE COUNTS. "Receive loot history?" is unanswerable -- the
-- question is really "is this worth three minutes and does it belong in my
-- database", and the drop count, the season name and how many carry somebody
-- else's credit corrections are what answer it.
--
-- WHY NO IS SENT RATHER THAN JUST NOT ANSWERING. A decline that looks like
-- silence leaves the sender watching a bar that never moves, and they press
-- send again. RCLootCouncil names that failure in its own decline reasons and
-- so does Core/HistorySync.lua.
--
-- Accept and Decline hold the whole job and touch no frame, for the reason
-- UI/ClearSeasonDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local HistoryPrompt = {}
SYL.HistoryPrompt = HistoryPrompt

local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 268
local PAD = 20

local frame
local titleText
local bodyText

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

function HistoryPrompt.Title(offer)
    return SYL.Utilities.ShortName(offer and offer.source)
        .. " is sending loot history"
end

function HistoryPrompt.Describe(offer)
    if not offer then
        return ""
    end

    local who = SYL.Utilities.ShortName(offer.source)
    local minutes = math.max(
        1,
        math.floor(((offer.messages or 0) * 0.25 + 30) / 60)
    )

    local text = who .. " is offering "
        .. SYL.Utilities.Count(offer.drops or 0, "drop")
        .. " from " .. tostring(offer.seasonName) .. ", with the credit "
        .. "marks they set by hand on " .. tostring(offer.credited or 0)
        .. " of them. Nothing has arrived yet.\n\n"
        .. "Say yes and it trickles in over about "
        .. SYL.Utilities.Count(minutes, "minute") .. ". "

    -- THE MERGE RULE, said before the press rather than discovered after it.
    -- The fear anybody sensible has here is that accepting somebody else's
    -- history overwrites their own, and the answer is that it cannot.
    text = text
        .. "Anything you already recorded is kept -- where you both hold the "
        .. "same drop, yours keeps its roll list and takes their credit "
        .. "mark, because that is the part somebody typed.\n\n"
        .. "Say no and they are told you declined, rather than left watching "
        .. "a bar that goes nowhere."

    return text
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function HistoryPrompt.Accept()
    local offer = SYL.HistorySync.PendingOffer()

    if not offer or not SYL.HistorySync.AcceptOffer() then
        return false
    end

    SYL:Print(
        "Receiving loot history from "
        .. SYL.Utilities.ShortName(offer.source)
        .. ". It arrives a few messages a second; you can keep playing."
    )

    return true
end

function HistoryPrompt.Decline()
    local ok, source = SYL.HistorySync.DeclineOffer()

    if not ok then
        return false
    end

    SYL:Print(
        "Declined the loot history from " .. SYL.Utilities.ShortName(source)
        .. ". They have been told."
    )

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame", "ShowUsYourLootHistoryPrompt", UIParent, "BackdropTemplate"
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

    titleText = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    titleText:SetPoint("LEFT", mark, "RIGHT", 10, 0)

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -48)
    separator:SetPoint("TOPRIGHT", -16, -48)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -60)
    bodyText:SetWidth(WINDOW_WIDTH - PAD * 2)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    local footer = Theme.CreateSeparator(frame)
    footer:SetPoint("BOTTOMLEFT", 16, 42)
    footer:SetPoint("BOTTOMRIGHT", -16, 42)

    local decline = Theme.CreateButton(frame, 96, 22, "No thanks", function()
        HistoryPrompt.Decline()
        frame:Hide()
    end)

    decline:SetPoint("BOTTOMRIGHT", -PAD, 14)

    local accept = Theme.CreateButton(frame, 96, 22, "Receive it", function()
        HistoryPrompt.Accept()
        frame:Hide()
    end)

    accept:SetPoint("RIGHT", decline, "LEFT", -8, 0)

    frame:Hide()

    return frame
end

function HistoryPrompt.Show()
    local offer = SYL.HistorySync.PendingOffer()

    if not offer then
        return nil
    end

    local window = CreateWindow()

    titleText:SetText(HistoryPrompt.Title(offer))
    bodyText:SetText(HistoryPrompt.Describe(offer))

    SYL.WindowStack.ShowWindow(window)

    return window
end
