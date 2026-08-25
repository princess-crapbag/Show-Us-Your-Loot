-- UI/LootAskPanel.lua
--
-- The small window that opens when somebody else wins something you rolled
-- on and can still hand over. One line saying why, and one button that puts
-- the message in your chat box.
--
-- THE SIBLING OF UI/TradeAdvisorPanel.lua, deliberately: same width, same
-- clock, same stacking, same corner of the screen. One arrives when you win,
-- this one when you lose. Somebody who has met either has met both.
--
-- THE BUTTON DOES NOT SEND. It opens the chat box with the whisper written
-- and stops, which is what UI/KeyRequestList.lua's Whisper button does. The
-- footnote says so on the window rather than in a tooltip, because the first
-- time this appears the question in the player's head is "wait, did that just
-- message a stranger for me".
--
-- WHY THE WORDING LIVES HERE rather than in Settings: this is where somebody
-- is standing when they decide they hate the phrasing. It writes to the same
-- saved setting either way, so a settings row can be added later without
-- moving anything.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local AskWording = SYL.AskWording

local LootAskPanel = {}
SYL.LootAskPanel = LootAskPanel

local WIDTH = 300
local BUTTON_HEIGHT = 20
local DISMISS_WIDTH = 70
local TICK_SECONDS = 10

-- Measured, not guessed. "You rolled Transmog, and you are missing this
-- appearance." is 306px of the 276 a block has, so the reason wraps to two
-- lines and the block is sized for two whether or not it uses them.
local REASON_HEIGHT = 26
local BLOCK_HEIGHT = 18 + REASON_HEIGHT + 4 + BUTTON_HEIGHT + 8

-- Two lines, measured: the sentence is 371px and the strip beside the Wording
-- button holds 214, so it wraps and the window is told to expect it. Getting
-- this wrong is how UI/TradeAdvisorPanel.lua's own footnote once rendered as
-- "This only tells y..." on the window a stranger meets first.
local FOOTNOTE_HEIGHT = 32
local CHROME_HEIGHT = 30 + FOOTNOTE_HEIGHT + 16

local frame
local Refresh

--------------------------------------------------------------------------
-- Asking
--------------------------------------------------------------------------

local function Ask(entry)
    if not entry or not entry.target then
        return
    end

    local line = AskWording.Line(entry.target, entry.record)

    if _G.ChatFrame_OpenChat then
        _G.ChatFrame_OpenChat(line)
    else
        -- Never seen in a real client. Printing it means the message is at
        -- least reachable rather than lost with no explanation.
        SYL:Print(line)
    end

    SYL.LootAsk.MarkAsked(entry.id)

    Refresh()
end

-- The live preview under the wording box. Composed against the item actually
-- on screen, and counted with the link in it, because the link is about 110
-- of the 255 a whisper allows and no one would guess that from looking.
local function PreviewFor(entry)
    return function(typed)
        local line, length = AskWording.Line(entry.target, entry.record, typed)
        local limit = AskWording.CHAT_LIMIT

        if length > limit then
            return line .. "\n" .. length .. " characters. Over the " .. limit
                .. " a whisper allows, so it will be cut off.", true
        end

        return line .. "\n" .. length .. " of the " .. limit
            .. " a whisper allows.", false
    end
end

local function EditWording(entry)
    if not entry then
        return
    end

    SYL.NamePromptDialog.Show({
        title = "The wording",
        body = "What the Ask button types for you. [item] becomes the item "
            .. "link and [player] becomes their name. Nothing is ever sent "
            .. "until you press Enter in the chat box.",
        accept = "Save",
        prefill = AskWording.Get(),
        empty = "Type the message first.",
        maxLetters = 240,
        preview = PreviewFor(entry),

        onAccept = function(typed)
            local ok, message = AskWording.Set(typed)

            if ok then
                return true, "That is what Ask will type from now on."
            end

            return false, message
        end,
    })
end

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local function EntryFrame(index)
    local block = frame.blocks[index]

    if block then
        return block
    end

    block = CreateFrame("Frame", nil, frame.body)

    block:SetWidth(WIDTH - 24)
    block:SetHeight(BLOCK_HEIGHT)

    block.item = Theme.CreateText(block, Theme.sizes.row, "textPrimary")
    block.item:SetPoint("TOPLEFT", 0, 0)
    block.item:SetWidth(WIDTH - 90)
    block.item:SetJustifyH("LEFT")
    block.item:SetWordWrap(false)

    block.clock = Theme.CreateText(block, Theme.sizes.row, "textSecondary")
    block.clock:SetPoint("TOPRIGHT", 0, 0)
    block.clock:SetJustifyH("RIGHT")

    block.reason = Theme.CreateText(block, Theme.sizes.rowSmall, "textMuted")
    block.reason:SetPoint("TOPLEFT", 0, -18)
    block.reason:SetWidth(WIDTH - 24)
    block.reason:SetHeight(REASON_HEIGHT)
    block.reason:SetJustifyH("LEFT")
    block.reason:SetJustifyV("TOP")
    block.reason:SetWordWrap(true)

    block.ask = Theme.CreateButton(
        block,
        WIDTH - 24 - DISMISS_WIDTH - 6,
        BUTTON_HEIGHT,
        "Ask",
        function()
            Ask(block.entry)
        end
    )

    block.ask:SetPoint("TOPLEFT", 0, -(18 + REASON_HEIGHT + 4))

    SYL.Tooltips.Attach(
        block.ask,
        "Ask for it",
        "Opens your chat box with the whisper already written. Nothing is "
        .. "sent until you press Enter, and you can change any of it first."
    )

    block.dismiss = Theme.CreateButton(
        block,
        DISMISS_WIDTH,
        BUTTON_HEIGHT,
        "Dismiss",
        function()
            if block.entry then
                SYL.LootAsk.Dismiss(block.entry.id)

                Refresh()
            end
        end
    )

    block.dismiss:SetPoint("TOPRIGHT", 0, -(18 + REASON_HEIGHT + 4))

    frame.blocks[index] = block

    return block
end

local function DrawEntry(block, entry, top)
    block.entry = entry

    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", 0, -top)

    block.item:SetText(
        tostring(entry.record.itemLink or entry.record.itemName
            or "Unknown item")
    )

    block.clock:SetText(SYL.LootAsk.FormatRemaining(entry.secondsLeft))

    Theme.SetTextColor(
        block.clock,
        entry.secondsLeft <= 1200 and "warning" or "textSecondary"
    )

    local reason = entry.reason or ""

    if entry.record.winnerName then
        reason = tostring(entry.record.winnerName) .. " won it. " .. reason
    end

    block.reason:SetText(reason)

    -- Asked once already, so the button says so. It is not removed: pressing
    -- Ask only fills the chat box, and somebody who then pressed Escape has
    -- sent nothing and would have nothing to come back to.
    --
    -- The SHORT name, never the realm-qualified one the whisper is addressed
    -- to. "Ask Hardtofinish-Silvermoon" measures 150px against a 200px button
    -- with the word Ask still to fit, and cross-realm is the ordinary case in
    -- the place this window lives.
    local winner = tostring(entry.record.winnerName or "them")

    block.ask.label:SetText(
        entry.asked and ("Ask " .. winner .. " again") or ("Ask " .. winner)
    )

    block:Show()

    return BLOCK_HEIGHT
end

Refresh = function()
    if not frame then
        return
    end

    local active = SYL.LootAsk.Active()

    if #active == 0 then
        frame:Hide()

        return
    end

    local top = 0

    for index, entry in ipairs(active) do
        top = top + DrawEntry(EntryFrame(index), entry, top)
    end

    for index = #active + 1, #frame.blocks do
        frame.blocks[index]:Hide()
    end

    frame.title:SetText(
        #active == 1 and "YOU CAN ASK FOR THIS"
        or ("YOU CAN ASK FOR " .. #active .. " ITEMS")
    )

    -- The dialog previews against whatever is on top of the panel, so the
    -- button reads the current entry rather than being re-wired each refresh.
    frame.wordingEntry = active[1]

    frame:SetHeight(math.min(400, top + CHROME_HEIGHT))
    frame:Show()
end

LootAskPanel.Refresh = Refresh

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function Build()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "SYLLootAskPanel",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetWidth(WIDTH)
    frame:SetHeight(140)

    -- Below the trade advisor's corner rather than on top of it. Winning one
    -- item and losing another off the same boss is ordinary, and two windows
    -- opening into the same pixels would look like one window flickering.
    frame:SetPoint("CENTER", 260, -80)
    frame:SetFrameStrata("HIGH")

    Theme.StyleWindow(frame)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    SYL.Widgets.CloseOnEscape(frame)
    SYL.WindowStack.TrackWindow(frame)

    frame.title = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("YOU CAN ASK FOR THIS")

    frame.close = Theme.CreateButton(frame, 20, 18, "X", function()
        frame:Hide()
    end)
    frame.close:SetPoint("TOPRIGHT", -10, -8)

    SYL.Tooltips.Attach(
        frame.close,
        "Close",
        "Closes the window without forgetting anything. /syl ask reopens it. "
        .. "Dismiss on an item is the one that forgets."
    )

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 12, -30)
    frame.body:SetPoint("BOTTOMRIGHT", -12, 14 + FOOTNOTE_HEIGHT)

    frame.blocks = {}

    frame.wording = Theme.CreateButton(frame, 62, 18, "Wording", function()
        EditWording(frame.wordingEntry)
    end)
    frame.wording:SetPoint("BOTTOMRIGHT", -12, 8)

    SYL.Tooltips.Attach(
        frame.wording,
        "Change the wording",
        "The message the Ask button types. Yours is saved and used from then "
        .. "on, and the default can be put back at any time."
    )

    -- THE SENTENCE THAT HAS TO BE ON THE WINDOW rather than in a tooltip. The
    -- first time this appears, the question in the player's head is "wait, did
    -- that just message a stranger for me", and a tooltip is not an answer to
    -- a question somebody is already alarmed by.
    frame.footnote = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.footnote:SetPoint("BOTTOMLEFT", 12, 8)
    frame.footnote:SetPoint("BOTTOMRIGHT", frame.wording, "BOTTOMLEFT", -8, 0)
    frame.footnote:SetHeight(FOOTNOTE_HEIGHT)
    frame.footnote:SetJustifyH("LEFT")
    frame.footnote:SetJustifyV("BOTTOM")
    frame.footnote:SetWordWrap(true)
    frame.footnote:SetText(
        "Puts the wording in your chat box. Nothing is sent until you press "
        .. "Enter."
    )

    frame:Hide()

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(TICK_SECONDS, function()
            if frame and frame:IsShown() then
                Refresh()
            else
                SYL.LootAsk.Sweep()
            end
        end)
    end

    return frame
end

function LootAskPanel.Show()
    if not SYL.LootAsk.IsEnabled() then
        return
    end

    Build()
    Refresh()
end

function LootAskPanel.HasAnything()
    return #SYL.LootAsk.Active() > 0
end
