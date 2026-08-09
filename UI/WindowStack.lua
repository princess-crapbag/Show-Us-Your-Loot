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
-- opens dead centre, so the second one lands exactly on top of the first. A
-- footer button then "toggled" a window that was already open but completely
-- covered — which hid it, changing nothing visible, so the button read as
-- broken. Pressing it again brought it back, still underneath. The fix is
-- that a buried window rises instead of hiding: toggling off is only what you
-- meant if you could actually see the thing you were closing.
--
-- THEY ALL OPEN IN THE SAME PLACE. Dead centre, every one, so opening two
-- means dragging one off the other before either can be read. Cascading is
-- not a layout — the real answer is Aimee's F3, windows that do not overlap
-- at all — but it does mean two open windows are both visible without
-- touching the mouse.

local CASCADE_STEP = 30
local CASCADE_WRAP = 6

local cascadeIndex = 0
local windows = {}

-- Registered so "is anything of ours on top of this" is answerable. Frames
-- are created once and kept, so this never needs cleaning up.
function WindowStack.TrackWindow(frame)
    windows[frame] = true
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
-- The two detail windows are anchored off-centre on purpose, so they sit
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
        PlaceOnce(frame)

        frame:Show()
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
    PlaceOnce(frame)

    frame:Show()
    frame:Raise()
end
