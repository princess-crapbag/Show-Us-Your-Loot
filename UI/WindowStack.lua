-- UI/WindowStack.lua
--
-- Opening, raising and placing this addon's windows.
--
-- Split out of UI/Widgets.lua, which is otherwise about the insides of a
-- window rather than about where one sits relative to the others.

local SYL = _G.ShowUsYourLoot

local WindowStack = {}
SYL.WindowStack = WindowStack

-- Every window did the same three lines: if shown, hide; else show. Two
-- things were wrong with that.
--
-- NOTHING EVER CALLED Raise(). Every window is created at the same strata and
-- opens dead center, so the second one lands exactly on top of the first. A
-- footer button then "toggled" a window that was already open but completely
-- covered — which hid it, changing nothing visible, so the button read as
-- broken. Pressing it again brought it back, still underneath. The fix is
-- that a buried window rises instead of hiding: toggling off is only what you
-- meant if you could actually see the thing you were closing.
--
-- THEY ALL OPENED IN THE SAME PLACE. Where a window goes is UI/WindowLayout.
-- This file only decides when to ask it, and what to do when it cannot find
-- anywhere: step off center so at least the title bars are distinguishable.

local CASCADE_STEP = 30
local CASCADE_WRAP = 6

local cascadeIndex = 0
local windows = {}

-- Insertion order is kept as well as membership, because the layout below
-- has to be stable: pairs() would rearrange every window each time one
-- opened.
local order = {}

--------------------------------------------------------------------------
-- Frame levels
--------------------------------------------------------------------------

-- WINDOWS ARE BANDED, AND Raise() ALONE WAS NOT ENOUGH.
--
-- Every window in this addon is created at DIALOG strata and none of them
-- ever set a frame level, so they all sat at the same one. Raise() had
-- nothing to order: a window opened from a button on another window landed
-- underneath it, IsTopmost answered true for everything at once because it
-- asks whether anything is at a *higher* level, and Frontmost picked whichever
-- happened to be first in `order` rather than whichever was actually on top —
-- so the front window was not painted solid either. One cause, three symptoms,
-- and the last of them is why two overlapping windows were both translucent.
--
-- So the stack is the authority and the levels are derived from it, rather
-- than the other way around. `stack` is every tracked window, bottom first;
-- raising moves one to the end and re-numbers them all.
--
-- THE BAND IS 40 BECAUSE POPUPS LIVE INSIDE IT. A window's own children take
-- its level plus an offset — UI/NameSuggest.lua uses +20, UI/CommandMenu.lua,
-- UI/FilterDropdown.lua, UI/AbsenceControls.lua and the resize grip use +10 —
-- so anything less than 40 would let one window's dropdown draw over the
-- window above it. Re-numbering every time also keeps the levels bounded:
-- a dozen windows never climb past a few hundred, which repeated Raise() calls
-- would not have promised.
local BASE_LEVEL = 40
local BAND = 40

local stack = {}

local function Restack()
    for index, frame in ipairs(stack) do
        frame:SetFrameLevel(BASE_LEVEL + index * BAND)
    end
end

local function MoveToTop(frame)
    for index, other in ipairs(stack) do
        if other == frame then
            table.remove(stack, index)

            break
        end
    end

    table.insert(stack, frame)

    Restack()
end

-- Registered so "is anything of ours on top of this" is answerable. Frames
-- are created once and kept, so this never needs cleaning up.
function WindowStack.TrackWindow(frame)
    if windows[frame] then
        return
    end

    windows[frame] = true

    table.insert(order, frame)

    -- Enters the stack at the bottom rather than the top. Tracking happens on
    -- the first show, and ShowWindow raises immediately afterwards — so a
    -- window that should be in front gets there by being raised, and one that
    -- is merely being registered does not steal the front from whatever the
    -- person was already looking at.
    table.insert(stack, 1, frame)

    Restack()

    -- Every window this file knows about gets click-to-raise, here rather than
    -- in whatever created it. Tracking runs once per frame, and a window that
    -- is not tracked is one this file has no opinion about anyway.
    WindowStack.RaiseOnClick(frame)
end

-- Once a window has been dragged, its position is the user's answer and the
-- layout stops having an opinion about it.
function WindowStack.NoteUserMoved(frame)
    frame.symlUserMoved = true
end

-- Everything currently open, oldest first, and whether any of them has been
-- put somewhere by hand.
local function OpenWindows(exclude)
    local open, userMoved = {}, false

    -- A DRAGGED WINDOW IS STILL AN OBSTACLE. These were one if/elseif, so a
    -- window the user had moved set the flag and was then left out of the
    -- list entirely — the layout was told "somebody has moved something" and
    -- handed nothing to avoid. WindowLayout tries center first, found an
    -- empty screen, and put the new window dead center: on top of the main
    -- window, which is the one people drag. Dragging any window at all
    -- brought back the exact overlap F3 was raised about.
    --
    -- The two facts are separate. Moved means "do not rearrange it"; shown
    -- means "do not cover it". WindowLayout.lua says as much — their layout,
    -- our best effort around it.
    for _, frame in ipairs(order) do
        if frame:IsShown() then
            if frame.symlUserMoved then
                userMoved = true
            end

            if frame ~= exclude then
                table.insert(open, frame)
            end
        end
    end

    return open, userMoved
end

-- Is anything of ours drawn over this one?
--
-- Asked of the stack rather than of GetFrameLevel. The levels are derived from
-- the stack now, so the two cannot disagree — but the stack is the one that
-- stays right if a frame's level is ever changed by something outside this
-- file, which is exactly what a Blizzard template or a popup does.
local function IsTopmost(frame)
    for index = #stack, 1, -1 do
        local other = stack[index]

        if other:IsShown() then
            return other == frame
        end
    end

    return true
end

-- Whichever open window sits highest, or nil when none is open.
--
-- A window can be raised by a footer button, by a row opening a detail pane,
-- or by being clicked, and a separate note of "the selected one" would be
-- another thing to keep in step with what is actually drawn on top. The stack
-- is that one thing, and the frame levels are painted from it.
local function Frontmost()
    for index = #stack, 1, -1 do
        local frame = stack[index]

        if frame:IsShown() then
            return frame
        end
    end

    return nil
end

-- Called after anything that changes which window is on top: a raise, a show,
-- a hide. The front one is painted solid and the rest keep the palette's
-- alpha, because at 0.97 two overlapping windows show each other's text
-- through the body and neither is readable.
function WindowStack.RefreshFocus()
    if not SYL.Theme or not SYL.Theme.SetFocusedWindow then
        return false
    end

    return SYL.Theme.SetFocusedWindow(Frontmost())
end

-- CLICKING A WINDOW BRINGS IT TO THE FRONT, which is what makes "the selected
-- window" mean anything at all. Until now a window only ever rose when
-- something opened it, so two overlapping windows could not be swapped by
-- hand: the one underneath stayed underneath until you closed the other.
--
-- Alongside OnDragStart rather than instead of it. This fires on the press;
-- the drag script fires only once the cursor passes the threshold, so a window
-- can still be moved and now also rises when you take hold of it.
function WindowStack.RaiseOnClick(frame)
    frame:SetScript("OnMouseDown", function(self)
        WindowStack.Raise(self)
    end)
end

-- Raise and refocus in one step, so no caller can do one without the other.
--
-- MoveToTop rather than frame:Raise(). Raise() orders a frame against the rest
-- of its strata, which includes Blizzard's own frames and says nothing about
-- where this addon's windows sit relative to each other — and with every
-- window on the same level there was nothing for it to reorder anyway. The
-- band assignment above is the whole of it now.
function WindowStack.Raise(frame)
    if not frame or not frame:IsShown() then
        return false
    end

    MoveToTop(frame)

    WindowStack.RefreshFocus()

    return true
end

-- For a window that already knows where it wants to be.
--
-- The two detail windows are anchored off-center on purpose, so they sit
-- beside the list that opened them rather than on top of it. Cascading those
-- would replace a deliberate position with an arbitrary one.
function WindowStack.KeepPlacement(frame)
    frame.symlPlaced = true
end

-- Placed once. Re-applying on every show would drag a window the user had
-- moved back to where this decided it belonged.
local function PlaceOnce(frame)
    if frame.symlPlaced then
        return
    end

    frame.symlPlaced = true

    local open, userMoved = OpenWindows(frame)

    if SYL.WindowLayout.Place(frame, open, userMoved) then
        return
    end

    -- The screen is full, or the frame has no size yet. Step off center so at
    -- least the title bars are distinguishable.
    --
    -- STEPPING FROM 1, NOT FROM 0. This counted from zero and returned early
    -- on the first one, which left the frame wherever it was created — and
    -- every window in this addon is created with SetPoint("CENTER"), which is
    -- where the main window is. So the one branch that runs when placement has
    -- *failed* was the one that moved the window nowhere, and settings opened
    -- exactly on top of the dashboard. Reaching here means something is
    -- already in the way; there is no case where the answer is to sit still.
    cascadeIndex = cascadeIndex + 1

    local step = (cascadeIndex - 1) % CASCADE_WRAP + 1

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", step * CASCADE_STEP, -step * CASCADE_STEP)
end

-- Returns true when the window ended up open.
function WindowStack.ToggleWindow(frame)
    WindowStack.TrackWindow(frame)

    if not frame:IsShown() then
        -- SHOWN FIRST, THEN PLACED. A frame that has never been laid out
        -- answers nil to GetLeft and GetBottom, so placing it before showing
        -- meant the layout could not measure what it was placing and fell
        -- through to the cascade — a few pixels off center, which is to say
        -- on top of the main window. The one frame of movement is worth it.
        frame:Show()

        PlaceOnce(frame)

        WindowStack.Raise(frame)

        return true
    end

    -- Open, but underneath something. The click meant "show me this".
    if not IsTopmost(frame) then
        WindowStack.Raise(frame)

        return true
    end

    frame:Hide()

    -- Whatever was underneath is the front one now, and has to stop being
    -- translucent. Closing the top window and leaving the next one see-through
    -- would look exactly like the bug this fixes.
    WindowStack.RefreshFocus()

    return false
end

-- For a window opened with a subject rather than toggled — a drop, a player.
-- Pressing the same row twice should not close what you just asked to see.
function WindowStack.ShowWindow(frame)
    WindowStack.TrackWindow(frame)

    frame:Show()

    PlaceOnce(frame)

    WindowStack.Raise(frame)
end
