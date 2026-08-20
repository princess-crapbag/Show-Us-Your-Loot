-- UI/TradeAdvisorPanel.lua
--
-- The small window that opens when you win something: what you won, who else
-- rolled Need on it, who among them is owed most, and the clock.
--
-- ITS OWN WINDOW RATHER THAN A TAB, and that is the whole design. Every other
-- screen in this addon is something you go and look at. This one has to arrive
-- during a boss fight, be read in about three seconds, and get out of the way —
-- a tab you have to open is a tab nobody opens with a two-hour clock running.
--
-- IT NEVER SENDS ANYTHING. No whisper button, no announce, no auto-trade.
-- Protected buttons cannot be clicked by an addon, so trading was never on the
-- table; whispering would be, and is deliberately left off, because "the addon
-- does not talk unless asked" is a rule that a popup offering to talk for you
-- erodes one button at a time. Copy the name if you want it.
--
-- It stacks entries rather than replacing them. Two items inside one two-hour
-- window is completely ordinary on a good night, and a panel that only ever
-- showed the newest would quietly drop the older one — which is precisely the
-- one about to expire.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local TradeAdvisorPanel = {}
SYL.TradeAdvisorPanel = TradeAdvisorPanel

local WIDTH = 300
local ROW_HEIGHT = 18
local MAX_CANDIDATES = 5
local TICK_SECONDS = 10

-- The footnote wraps to two lines and the chrome has to be told. It shipped on
-- one line with wrap off — Theme.CreateText turns wrap off for everything —
-- inside 276 pixels it does not fit, so it rendered as "This only tells y..."
-- and the sentence lost the half that matters. It is the only string in the
-- addon long enough to hit this, and it is on the window a stranger meets
-- first.
local FOOTNOTE_HEIGHT = 26
local CHROME_HEIGHT = 62 + (FOOTNOTE_HEIGHT - 12)

local frame
local Refresh

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

    block.item = Theme.CreateText(block, Theme.sizes.row, "textPrimary")
    block.item:SetPoint("TOPLEFT", 0, 0)
    block.item:SetWidth(WIDTH - 90)
    block.item:SetJustifyH("LEFT")
    block.item:SetWordWrap(false)

    -- The clock sits on the same line as the item and is the only thing on
    -- this panel that is allowed to be loud.
    block.clock = Theme.CreateText(block, Theme.sizes.row, "warning")
    block.clock:SetPoint("TOPRIGHT", 0, 0)
    block.clock:SetJustifyH("RIGHT")

    block.subtitle = Theme.CreateText(block, Theme.sizes.rowSmall, "textMuted")
    block.subtitle:SetPoint("TOPLEFT", 0, -18)
    block.subtitle:SetWidth(WIDTH - 24)
    block.subtitle:SetJustifyH("LEFT")

    block.rows = {}

    block.dismiss = Theme.CreateButton(block, 70, 18, "Dismiss", function()
        if block.entryID then
            SYL.TradeAdvisor.Dismiss(block.entryID)

            Refresh()
        end
    end)

    frame.blocks[index] = block

    return block
end

local function CandidateRow(block, index)
    local row = block.rows[index]

    if row then
        return row
    end

    row = CreateFrame("Frame", nil, block)

    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(WIDTH - 24)

    row.value = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    block.rows[index] = row

    return row
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function DrawEntry(block, entry, top)
    local record = entry.record

    block.entryID = entry.id

    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", 0, -top)

    block.item:SetText(tostring(record.itemLink or record.itemName or "Unknown item"))
    block.clock:SetText(SYL.TradeAdvisor.FormatRemaining(entry.secondsLeft))

    -- Under twenty minutes the clock stops being information and starts being
    -- the point of the window.
    Theme.SetTextColor(
        block.clock,
        entry.secondsLeft <= 1200 and "warning" or "textSecondary"
    )

    local candidates = SYL.TradeAdvisor.RankCandidates(record)
    local shown = math.min(MAX_CANDIDATES, #candidates)

    block.subtitle:SetText(
        #candidates .. (#candidates == 1 and " player" or " players")
        .. " rolled and lost · most owed first"
    )

    local rowTop = 38

    for index = 1, shown do
        local candidate = candidates[index]
        local row = CandidateRow(block, index)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -rowTop)

        row.name:SetText(
            tostring(candidate.name or "Unknown")
            .. "  " .. candidate.stateLabel
        )

        local classColor = Theme.GetClassColor(candidate.class)

        if classColor then
            Theme.SetCustomTextColor(row.name, classColor[1], classColor[2], classColor[3])
        else
            Theme.SetTextColor(row.name, "textPrimary")
        end

        row.value:SetText(SYL.TradeAdvisor.DescribeCandidate(candidate))

        -- The top row is the answer. Accented so the panel can be acted on
        -- without being read.
        Theme.SetTextColor(row.value, index == 1 and "accent" or "textMuted")

        row:Show()

        rowTop = rowTop + ROW_HEIGHT
    end

    for index = shown + 1, #block.rows do
        block.rows[index]:Hide()
    end

    if #candidates > shown then
        rowTop = rowTop + 2
    end

    block.dismiss:ClearAllPoints()
    block.dismiss:SetPoint("TOPRIGHT", 0, -rowTop)

    block:SetHeight(rowTop + 22)
    block:Show()

    return rowTop + 30
end

Refresh = function()
    if not frame then
        return
    end

    local active = SYL.TradeAdvisor.Active()

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
        #active == 1 and "YOU WON THIS" or ("YOU WON " .. #active .. " ITEMS")
    )

    frame:SetHeight(math.min(400, top + CHROME_HEIGHT))
    frame:Show()
end

TradeAdvisorPanel.Refresh = Refresh

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function Build()
    if frame then
        return frame
    end

    -- BackdropTemplate, because Theme.StyleWindow calls SetBackdrop and that
    -- lives on the mixin rather than on a plain frame. One CreateFrame that
    -- did not pass it was a crash on first click and leaked a frame per try.
    frame = CreateFrame("Frame", "SYLTradeAdvisorPanel", UIParent, "BackdropTemplate")

    frame:SetWidth(WIDTH)
    frame:SetHeight(140)
    frame:SetPoint("CENTER", 260, 80)
    frame:SetFrameStrata("HIGH")

    Theme.StyleWindow(frame)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- THE THREE THINGS EVERY OTHER WINDOW HERE ALREADY DOES. This one opens by
    -- itself, mid-pull, over whatever the player was looking at — so it is the
    -- worst window in the addon to have been the only one that swallowed
    -- Escape, the only one that could be dragged off the edge of the screen
    -- and left there, and the only one WindowStack had never been told about.
    --
    -- The last of those is why it was permanently see-through: focus is what
    -- lifts a window to full opacity, an untracked window can never be
    -- focused, so it sat at the unfocused alpha forever and read as a bug in
    -- the theme rather than a gap in the registry.
    frame:SetClampedToScreen(true)

    SYL.Widgets.CloseOnEscape(frame)
    SYL.WindowStack.TrackWindow(frame)

    frame.title = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("YOU WON THIS")

    frame.close = Theme.CreateButton(frame, 20, 18, "X", function()
        frame:Hide()
    end)
    frame.close:SetPoint("TOPRIGHT", -10, -8)

    SYL.Tooltips.Attach(
        frame.close,
        "Close",
        "Closes the window without forgetting the item. It comes back on the "
        .. "next win, and /syl trade reopens it. Dismiss on an item is the one "
        .. "that forgets."
    )

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 12, -30)
    frame.body:SetPoint("BOTTOMRIGHT", -12, 14 + FOOTNOTE_HEIGHT)

    frame.blocks = {}

    frame.footnote = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.footnote:SetPoint("BOTTOMLEFT", 12, 8)
    frame.footnote:SetPoint("BOTTOMRIGHT", -12, 8)
    frame.footnote:SetHeight(FOOTNOTE_HEIGHT)
    frame.footnote:SetJustifyH("LEFT")
    frame.footnote:SetJustifyV("BOTTOM")
    frame.footnote:SetWordWrap(true)
    frame.footnote:SetText(
        "An addon cannot trade for you. This only tells you who asked."
    )

    frame:Hide()

    -- Ten seconds is enough for a clock that reads in minutes, and cheap
    -- enough that it can run while the panel is up rather than being started
    -- and stopped. Sweeping here too means an entry cannot outlive its window
    -- just because nobody looked.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(TICK_SECONDS, function()
            if frame and frame:IsShown() then
                Refresh()
            else
                SYL.TradeAdvisor.Sweep()
            end
        end)
    end

    return frame
end

function TradeAdvisorPanel.Show()
    if not SYL.TradeAdvisor.IsEnabled() then
        return
    end

    Build()
    Refresh()
end

-- For /syl trade, and for anything that wants to know whether there is
-- something to show without building a frame to find out.
function TradeAdvisorPanel.HasAnything()
    return #SYL.TradeAdvisor.Active() > 0
end
