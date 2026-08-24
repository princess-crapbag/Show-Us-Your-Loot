-- UI/DropCredit.lua
--
-- The credit line on the drop detail window: who a drop counts for, what it
-- is worth, and where that came from.
--
-- IT LIVES WHERE THE DATA LIVES, not in a Settings tab of buttons. Under a
-- loot council the addon credits every drop to the master looter, because a
-- trade it never witnessed is a trade that never happened as far as it knows
-- — so the place to correct that is the screen already showing what the
-- client reported.
--
-- THE WEIGHT IS SHOWN BESIDE THE NAME because the two are separate mistakes.
-- On Aimee's 2026-08-18 raid six of eleven drops carried the wrong response as
-- well as the wrong person, and four of those were Transmog, which weighs
-- nothing — a line that showed only the name would have looked fixed while
-- half the board stayed wrong. See Core/DropRules.lua.
--
-- NOTHING HERE REWRITES HISTORY. "Won by Arcangila with 51" still says so
-- above it, because that is what the client reported. Only the credit moves.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local DropCredit = {}
SYL.DropCredit = DropCredit

-- Where the block sits inside the drop detail window. It costs 78, and
-- everything above and below it is where it always was.
DropCredit.LABEL_TOP = 150
DropCredit.NAME_TOP = 166
DropCredit.NOTE_TOP = 186
DropCredit.SEPARATOR_TOP = 206
DropCredit.HEIGHT = 78

--------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------

-- `handlers.onChange` opens the picker; `handlers.onUndo` clears the
-- override. Both are passed in rather than reached for, so this file never
-- has to know which window it is sitting in.
function DropCredit.Build(frame, handlers)
    -- Collected so the whole block can be hidden at once. A record whose
    -- credit cannot be moved must not show a credit line at all — see
    -- LootCredit.CanCorrect, and Update below.
    frame.creditParts = {}

    local function Part(region)
        table.insert(frame.creditParts, region)

        return region
    end

    local label = Part(
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    )

    label:SetPoint("TOPLEFT", 18, -DropCredit.LABEL_TOP)
    label:SetText("CREDITED TO")

    frame.creditName = Part(
        Theme.CreateText(frame, Theme.sizes.row, "textPrimary")
    )
    frame.creditName:SetPoint("TOPLEFT", 18, -DropCredit.NAME_TOP)

    frame.creditWeight = Part(
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    )

    frame.creditWeight:SetPoint("LEFT", frame.creditName, "RIGHT", 10, 1)

    frame.creditNote = Part(
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    )

    frame.creditNote:SetPoint("TOPLEFT", 18, -DropCredit.NOTE_TOP)

    -- MEASURED, both of them. Theme.MeasureText exists for exactly this, and a
    -- button sized by guess is either clipped or too wide — and too wide is a
    -- defect too.
    local changeLabel = "Change…"
    local changeWidth =
        Theme.MeasureText(Theme.sizes.rowSmall, changeLabel) + 26

    local change = Part(Theme.CreateButton(
        frame, changeWidth, 22, changeLabel, handlers.onChange
    ))

    change:SetPoint("TOPRIGHT", -16, -(DropCredit.NAME_TOP - 5))

    local undoLabel = "Undo"
    local undoWidth = Theme.MeasureText(Theme.sizes.rowSmall, undoLabel) + 26

    frame.undoButton = Part(Theme.CreateButton(
        frame, undoWidth, 22, undoLabel, handlers.onUndo
    ))

    frame.undoButton:SetPoint("RIGHT", change, "LEFT", -8, 0)
    frame.undoButton:Hide()

    -- MATCH TO RCLOOTCOUNCIL, shown only when there is something to match.
    --
    -- It pre-fills the picker rather than writing the credit, which is
    -- Aimee's own call: "make the 'match against RCLootCouncil history'
    -- button that pre-fills the credit picker for you to confirm."
    --
    -- Hidden by default and revealed in Update, because most drops will never
    -- have an award to match -- and a button that is always there and usually
    -- does nothing teaches people not to press it.
    local matchLabel = "Match to RCLC"
    local matchWidth = Theme.MeasureText(Theme.sizes.rowSmall, matchLabel) + 26

    frame.matchButton = Part(Theme.CreateButton(
        frame, matchWidth, 22, matchLabel, handlers.onMatch
    ))

    frame.matchButton:SetPoint("RIGHT", frame.undoButton, "LEFT", -8, 0)
    frame.matchButton:Hide()

    local separator = Part(Theme.CreateSeparator(frame))

    separator:SetPoint("TOPLEFT", 16, -DropCredit.SEPARATOR_TOP)
    separator:SetPoint("TOPRIGHT", -16, -DropCredit.SEPARATOR_TOP)
end

--------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------

-- THE CLASS WAS ALREADY IN HAND AND THIS WALKED THE ROLL LIST AGAIN TO FIND
-- IT. LootCredit.Describe sets `class` on every descriptor it returns -- for
-- all three sources, manual, traded and roll -- and this function existed
-- beside a variable that already held it. Deleted; `credit.class` is used
-- directly below.

-- The words describe what happened rather than naming a setting, because the
-- person reading this is trying to answer "why does it say that".
local function NoteFor(credit)
    if credit.source == "manual" then
        local wasState = SYL.LootScore.LABELS[credit.priorState]

        return "set by hand · was " .. tostring(credit.priorName or "nobody")
            .. (wasState
                and (", " .. wasState .. " "
                    .. SYL.LootScore.WeightOf(credit.priorState))
                or "")
    end

    if credit.source == "traded" then
        return "traded to them by "
            .. tostring(credit.priorName or "the winner")
    end

    -- THE TWO STATES THAT USED TO SHARE THESE WORDS. On a master-looted
    -- night every drop names the master looter, so "I checked, it is mine"
    -- and "nobody has looked at this" both read as "won the roll".
    if credit.source == "masterloot" then
        return "master looter -- not assigned to anybody yet"
    end

    return "won the roll, never traded"
end

local function HideBlock(frame)
    for _, part in ipairs(frame.creditParts or {}) do
        part:Hide()
    end
end

-- Returns whether the block was drawn, so the caller can close the gap it
-- would otherwise leave. Hiding the parts does not reclaim the space they
-- occupy: the roll list underneath is anchored at a constant that includes
-- this block's height, so a chat-captured item drew 78px of nothing between
-- the item details and the column headings and read as a half-drawn window.
function DropCredit.Update(frame, record)
    local credit = SYL.LootCredit.Describe(record)

    -- NOT EVERY ROW IN THE LOOT LIST IS A DROP. Personal loot, vault items,
    -- crafted gear and world drops are captured from chat into a different
    -- store, and Core/LootFeed.lua hands this window a built-to-fit copy of
    -- one — with an empty roll list and no winner state. Drawn anyway, the
    -- block read "CREDITED TO <name> · unknown · 0" and "won the roll, never
    -- traded" about an item nobody rolled on, and Change… could only ever
    -- answer "that drop is no longer in the database" about a row on screen.
    --
    -- Hidden rather than disabled, because there is no credit on personal
    -- loot to show: it is outside the fairness math by design.
    if not credit or not SYL.LootCredit.CanCorrect(record) then
        HideBlock(frame)

        return false
    end

    for _, part in ipairs(frame.creditParts or {}) do
        part:Show()
    end

    -- Only when RCLootCouncil actually has an award for this item that names
    -- somebody other than whoever is credited now.
    frame.suggested = SYL.CouncilLoot.SuggestedCredit(record)

    frame.matchButton:SetShown(frame.suggested ~= nil)

    if frame.suggested then
        SYL.Tooltips.Attach(
            frame.matchButton,
            "Match to RCLootCouncil",
            "RCLootCouncil awarded this to "
            .. tostring(frame.suggested.name)
            .. (frame.suggested.response
                and (" as \"" .. tostring(frame.suggested.response) .. "\"")
                or "")
            .. ". This opens the picker with that name chosen -- nothing "
            .. "changes until you confirm it."
        )
    end

    frame.creditName:SetText(tostring(credit.name or "Nobody"))

    SYL.ClassColor.Set(frame.creditName, credit.class)

    local stateLabel = SYL.LootScore.LABELS[credit.state]
        or SYL.LootHistoryAPI.ShortRollState(credit.state)
        or "unknown"

    frame.creditWeight:SetText(
        "·  " .. stateLabel .. " · " .. SYL.LootScore.WeightOf(credit.state)
    )

    frame.creditNote:SetText(NoteFor(credit))

    -- Offered only when there is something to undo. A permanently visible one
    -- that does nothing is worse than none at all.
    if credit.source == "manual" then
        frame.undoButton:Show()
    else
        frame.undoButton:Hide()
    end

    return true
end
