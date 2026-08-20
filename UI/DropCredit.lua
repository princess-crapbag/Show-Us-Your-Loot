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
    local label = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    label:SetPoint("TOPLEFT", 18, -DropCredit.LABEL_TOP)
    label:SetText("CREDITED TO")

    frame.creditName = Theme.CreateText(frame, Theme.sizes.row, "textPrimary")
    frame.creditName:SetPoint("TOPLEFT", 18, -DropCredit.NAME_TOP)

    frame.creditWeight =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")

    frame.creditWeight:SetPoint("LEFT", frame.creditName, "RIGHT", 10, 1)

    frame.creditNote =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    frame.creditNote:SetPoint("TOPLEFT", 18, -DropCredit.NOTE_TOP)

    -- MEASURED, both of them. Theme.MeasureText exists for exactly this, and a
    -- button sized by guess is either clipped or too wide — and too wide is a
    -- defect too.
    local changeLabel = "Change…"
    local changeWidth =
        Theme.MeasureText(Theme.sizes.rowSmall, changeLabel) + 26

    local change = Theme.CreateButton(
        frame, changeWidth, 22, changeLabel, handlers.onChange
    )

    change:SetPoint("TOPRIGHT", -16, -(DropCredit.NAME_TOP - 5))

    local undoLabel = "Undo"
    local undoWidth = Theme.MeasureText(Theme.sizes.rowSmall, undoLabel) + 26

    frame.undoButton = Theme.CreateButton(
        frame, undoWidth, 22, undoLabel, handlers.onUndo
    )

    frame.undoButton:SetPoint("RIGHT", change, "LEFT", -8, 0)
    frame.undoButton:Hide()

    local separator = Theme.CreateSeparator(frame)

    separator:SetPoint("TOPLEFT", 16, -DropCredit.SEPARATOR_TOP)
    separator:SetPoint("TOPRIGHT", -16, -DropCredit.SEPARATOR_TOP)
end

--------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------

local function ColorFor(record, credit)
    if credit.source == "roll" then
        return Theme.GetClassColor(record.winnerClass)
    end

    for _, roll in ipairs(record.rolls or {}) do
        if roll.name == credit.name then
            return Theme.GetClassColor(roll.class)
        end
    end

    return nil
end

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

    return "won the roll, never traded"
end

function DropCredit.Update(frame, record)
    local credit = SYL.LootCredit.Describe(record)

    if not credit then
        return
    end

    frame.creditName:SetText(tostring(credit.name or "Nobody"))

    local classColor = ColorFor(record, credit)

    if classColor then
        Theme.SetCustomTextColor(
            frame.creditName, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(frame.creditName, "textPrimary")
    end

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
end
