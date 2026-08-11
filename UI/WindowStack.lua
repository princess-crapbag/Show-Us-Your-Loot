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

-- Registered so "is anything of ours on top of this" is answerable. Frames
-- are created once and kept, so this never needs cleaning up.
function WindowStack.TrackWindow(frame)
    if windows[frame] then
        return
    end

    windows[frame] = true

    table.insert(order, frame)
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

    for _, frame in ipairs(order) do
        if frame:IsShown() then
            if frame.symlUserMoved then
                userMoved = true
            elseif frame ~= exclude then
                table.insert(open, frame)
            end
        end
    end

    return open, userMoved
end

local function IsTopmost(frame)
    local level = frame:GetFrameLevel()

    for other in pairs(windows) do
        if other ~= frame
            and other:IsShown()
            and other:GetFrameLevel() > level
        then
            return false
        end
    end

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
    local step = cascadeIndex % CASCADE_WRAP

    cascadeIndex = cascadeIndex + 1

    if step == 0 then
        return
    end

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

        frame:Raise()

        return true
    end

    -- Open, but underneath something. The click meant "show me this".
    if not IsTopmost(frame) then
        frame:Raise()

        return true
    end

    frame:Hide()

    return false
end

-- For a window opened with a subject rather than toggled — a drop, a player.
-- Pressing the same row twice should not close what you just asked to see.
function WindowStack.ShowWindow(frame)
    WindowStack.TrackWindow(frame)

    frame:Show()

    PlaceOnce(frame)

    frame:Raise()
end
