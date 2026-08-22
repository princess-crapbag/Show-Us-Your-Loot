-- UI/CreditPicker.lua
--
-- Choosing who a drop is credited to, and what response it is scored on.
--
-- Core/CreditCandidates.lua decides who is offered and why the roll list is
-- not the answer; UI/CreditPickerRows.lua draws a row and the response
-- buttons. This file is the window and the decision it collects.
--
-- SETTING IT BACK IS A CLEAR, NOT A WRITE. Choosing the original winner and
-- their original response removes the override rather than storing one that
-- happens to agree — otherwise a drop reads "set by hand" forever for a
-- correction that corrected nothing. The button says so: it reads Clear
-- rather than Credit whenever that is what pressing it would do.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local CreditPicker = {}
SYL.CreditPicker = CreditPicker

local WINDOW_WIDTH = 320
local ROW_HEIGHT = 22
local VISIBLE_ROWS = 10
local LIST_TOP = 118
local FOOTER = 90

local LAYOUT = { listTop = LIST_TOP, rowHeight = ROW_HEIGHT }

local frame
local rows = {}
local weightButtons = {}

local currentRecord
local candidates = {}
local filtered = {}
local offset = 0
local search = ""

-- Three separate answers, and conflating any two of them is a bug.
--
--   chosen   — what the person is picking right now; mutates as they click.
--   original — the record with any override ignored: the roll winner and the
--              response the client reported. What Clear returns to.
--   holder   — where the credit sits at this moment, override included.
--
-- "credited now" marks HOLDER, not original. Those coincide until the first
-- correction and diverge immediately afterwards, so marking original looked
-- right on a first open and then told an officer the credit was still on the
-- master looter while the window behind said otherwise.
local chosen = {}
local original = {}
local holder = {}

local Refresh

--------------------------------------------------------------------------
-- The decision
--------------------------------------------------------------------------

local function SamePerson(candidate, who)
    if who.guid and candidate.guid then
        return candidate.guid == who.guid
    end

    return candidate.name == who.name
end

-- Whether the chosen answer is the one the record already carried. Turns
-- Credit into a clear, so that undoing by hand and pressing Undo agree.
local function MatchesOriginal()
    return SamePerson(chosen, original) and chosen.state == original.state
end

-- The detail window has moved on to a different drop, so this picker is asking
-- about something nobody is looking at any more. Closed rather than left open:
-- pressing Credit on it would silently correct a drop that is no longer on
-- screen, and there is nothing in the picker that names which drop it means
-- besides the item at the top.
function CreditPicker.NoteDropChanged(record)
    if frame and frame:IsShown() and currentRecord ~= record then
        frame:Hide()

        SYL.WindowStack.RefreshFocus()
    end
end

local function Apply()
    local record = currentRecord

    if not record then
        return
    end

    if MatchesOriginal() then
        SYL.LootCredit.Clear(record.id)
    else
        local ok, reason = SYL.LootCredit.Set(record.id, {
            guid = chosen.guid,
            name = chosen.name,
            state = chosen.state,
        })

        -- Said out loud rather than swallowed: "nothing happened" and "that
        -- drop is not in this database any more" look identical otherwise.
        if not ok then
            SYL:Write(
                SYL.colors.highlight .. "[SYL]" .. SYL.colors.reset
                .. " could not move the credit: " .. tostring(reason)
            )

            return
        end
    end

    frame:Hide()

    -- The window this was opened from is still up behind it, and every board
    -- that reads the score has just changed.
    if SYL.DropDetailWindow then
        SYL.DropDetailWindow.Refresh()
    end

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

Refresh = function()
    if not frame or not currentRecord then
        return
    end

    filtered = SYL.CreditCandidates.Filter(candidates, search)

    local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    for index = 1, VISIBLE_ROWS do
        local candidate = filtered[index + offset]
        local row = rows[index]

        if candidate then
            SYL.CreditPickerRows.FillRow(row, candidate, {
                chosen = SamePerson(candidate, chosen),
                current = SamePerson(candidate, holder),
            })

            row:Show()
        else
            row.candidate = nil
            row:Hide()
        end
    end

    SYL.CreditPickerRows.MarkWeight(weightButtons, chosen.state)

    frame.countText:SetText(
        #filtered == #candidates
            and (#candidates .. " in this session")
            or (#filtered .. " of " .. #candidates)
    )

    frame.applyButton.label:SetText(MatchesOriginal() and "Clear" or "Credit")
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootCreditPickerFrame",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, LIST_TOP + VISIBLE_ROWS * ROW_HEIGHT + FOOTER)
    frame:SetPoint("CENTER", 420, 0)

    -- Placed against the drop detail window on every open. The cascade must
    -- not have an opinion about it as well.
    SYL.WindowStack.KeepPlacement(frame)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("CREDIT TO")

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame.itemText =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textPrimary")

    frame.itemText:SetPoint("TOPLEFT", 18, -48)
    frame.itemText:SetPoint("TOPRIGHT", -16, -48)

    -- The picker names the item it is about, so that name gets a tooltip too.
    local itemHover = Widgets.MakeItemHoverable(frame, function()
        return currentRecord and currentRecord.itemLink
    end)

    itemHover:SetPoint("TOPLEFT", 16, -47)
    itemHover:SetPoint("TOPRIGHT", -16, -47)
    itemHover:SetHeight(16)

    frame.countText =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    frame.countText:SetPoint("TOPLEFT", 18, -66)

    frame.search = SYL.SearchBox.Create(
        frame,
        WINDOW_WIDTH - 32,
        "Search…",
        function(value)
            search = value or ""
            offset = 0

            Refresh()
        end,
        { bordered = true }
    )

    frame.search:SetPoint("TOPLEFT", 16, -86)

    for index = 1, VISIBLE_ROWS do
        rows[index] = SYL.CreditPickerRows.CreateRow(
            frame, index, LAYOUT,
            function(candidate)
                chosen.guid = candidate.guid
                chosen.name = candidate.name

                Refresh()
            end
        )
    end

    local listBottom = LIST_TOP + VISIBLE_ROWS * ROW_HEIGHT

    local scoredLabel =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    scoredLabel:SetPoint("TOPLEFT", 18, -(listBottom + 10))
    scoredLabel:SetText("SCORED AS")

    weightButtons = SYL.CreditPickerRows.CreateWeightButtons(
        frame, listBottom + 28,
        function(state)
            chosen.state = state

            Refresh()
        end
    )

    local cancel = Theme.CreateButton(frame, 74, 22, "Cancel", function()
        frame:Hide()
    end)

    cancel:SetPoint("BOTTOMLEFT", 16, 16)

    frame.applyButton = Theme.CreateButton(frame, 90, 22, "Credit", Apply)
    frame.applyButton:SetPoint("BOTTOMRIGHT", -16, 16)

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:Hide()

    return frame
end

--------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------

-- The original is the record with any override ignored — the roll winner and
-- the response the client reported. That is what Clear returns to, so it is
-- what "credited now" has to mark and what MatchesOriginal has to compare
-- against.
local function ReadOriginal(record)
    local name, state

    for _, roll in ipairs(record.rolls or {}) do
        if roll.isWinner then
            name = roll.name
            state = roll.state
        end
    end

    return {
        guid = record.winnerGUID,
        name = name or record.winnerName,
        state = state == nil and record.winnerState or state,
    }
end

-- BESIDE THE DROP, NOT ACROSS IT. Both windows are anchored off center and
-- their spans overlapped by 250 of the picker's 320 — so even once the frame
-- levels were fixed it would have covered the roll list it is asking about.
-- Anchored to the window rather than to a screen position, so dragging the one
-- carries the other with it.
--
-- Skipped once the person has moved the picker by hand: their position is the
-- answer, and re-placing it on the next open would undo the drag. See
-- WindowStack.NoteUserMoved, which Widgets sets on every drag stop.
local function PlaceBeside(window)
    if window.symlUserMoved then
        return
    end

    local anchor = SYL.DropDetailWindow and SYL.DropDetailWindow.Frame()

    window:ClearAllPoints()

    if anchor and anchor:IsShown() then
        window:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        window:SetPoint("CENTER", 420, 0)
    end
end

function CreditPicker.Open(record)
    if not record then
        return
    end

    local window = CreateWindow()

    PlaceBeside(window)

    currentRecord = record
    candidates = SYL.CreditCandidates.Build(record)
    offset = 0
    search = ""

    if window.search and window.search.editBox then
        window.search.editBox:SetText("")
    end

    original = ReadOriginal(record)

    -- Opens on whatever the drop says today, so the picker explains the
    -- current state before it changes it.
    local override = SYL.LootCredit.Get(record)

    holder = {
        guid = override and override.guid or original.guid,
        name = override and override.name or original.name,
    }

    -- Opens on the current holder, so the first thing the list says is where
    -- the credit is rather than where it started. Copied rather than aliased:
    -- the row handler mutates `chosen`, and sharing the table would drag the
    -- "credited now" marker along with the selection.
    chosen = {
        guid = holder.guid,
        name = holder.name,
        state = (override and override.state ~= nil)
            and override.state
            or original.state,
    }

    window.itemText:SetText(
        tostring(record.itemLink or record.itemName or "Unknown item")
    )

    Refresh()

    SYL.WindowStack.ShowWindow(window)
end
