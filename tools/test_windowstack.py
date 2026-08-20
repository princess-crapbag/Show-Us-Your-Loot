"""A dragged window is still something the next window must avoid.

test_windowplacement covers the arithmetic in UI/WindowLayout.lua by lifting it
out and calling it directly. That is the half that was already right. This
covers the layer above it — UI/WindowStack.lua, which decides *what to hand*
the layout — and that layer had no test at all.

THE BUG THIS EXISTS FOR. OpenWindows collected the shown windows and, in the
same if/elseif, noticed whether any had been dragged. A dragged window set the
flag and fell out of the list, so the layout was told "somebody moved
something" and given nothing to avoid. It tries center first, found an empty
screen, and placed the new window dead center — on top of the main window,
which is the one people drag. Dragging any window at all brought back the
overlap the layout was written to prevent, and it looked like the layout had
failed rather than like it had been handed the wrong list.

Both real files are loaded here, unmodified, so the assertion runs the shipped
path from ShowWindow down to SetPoint rather than a restatement of it.

Needs `lupa`; see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

UI = Path(__file__).resolve().parent.parent / "UI"

SCREEN_W, SCREEN_H = 1920, 1080

# The real sizes. Main is 900x596 and Settings is 560 wide, which matters:
# they fit side by side with room to spare, so an overlap here is never the
# screen being too small.
MAIN_W, MAIN_H = 900, 596
SETTINGS_W, SETTINGS_H = 560, 900

lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute(f"""
ShowUsYourLoot = {{}}

UIParent = {{
    GetWidth = function() return {SCREEN_W} end,
    GetHeight = function() return {SCREEN_H} end,
}}

-- Geometry is real, because the whole question is whether two rectangles
-- overlap. SetPoint handles the three forms the addon actually uses: the
-- TOPLEFT anchor Arrange places with, the BOTTOMLEFT one FindSpot uses, and
-- the CENTER-plus-offset of the cascade fallback.
-- Created at dead center, because that is what every window in this addon
-- does in its constructor. Modelling it matters: the failure being guarded
-- against is placement quietly doing nothing and leaving the frame here.
ALL_FRAMES = {{}}

function MakeFrame(width, height, tag)
    local f = {{ w = width, h = height, shown = false, level = 1,
                tag = tag }}

    table.insert(ALL_FRAMES, f)

    f.left = ({SCREEN_W} - width) / 2
    f.bottom = ({SCREEN_H} - height) / 2

    function f:GetWidth() return self.w end
    function f:GetHeight() return self.h end
    function f:GetLeft() return self.left end
    function f:GetBottom() return self.bottom end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    -- Raise puts a frame above every other one, which is what the real
    -- API does. Incrementing its own level instead left two windows tied
    -- after both had been raised, and 'the front one' then came down to
    -- whichever the loop happened to reach first.
    --
    -- WindowStack no longer calls this — see SetFrameLevel below and the
    -- banding comment in UI/WindowStack.lua. Kept because the stub is meant
    -- to be the shape of a real frame, not the shape of one caller.
    function f:Raise()
        local top = 0

        for _, other in ipairs(ALL_FRAMES) do
            if other.level > top then top = other.level end
        end

        self.level = top + 1
    end
    function f:SetFrameLevel(level) self.level = level end
    function f:GetFrameLevel() return self.level end
    function f:ClearAllPoints() end

    -- Scripts are kept rather than swallowed, so a click can actually be
    -- delivered below. Click-to-raise is only reachable through the handler
    -- WindowStack attaches, and a stub that discarded it would leave the whole
    -- behaviour untestable while looking fine.
    function f:SetScript(event, handler)
        self.scripts = self.scripts or {{}}
        self.scripts[event] = handler
    end

    function f:Click()
        if self.scripts and self.scripts.OnMouseDown then
            self.scripts.OnMouseDown(self)
        end
    end

    function f:SetPoint(point, a, b, c, d)
        if point == 'TOPLEFT' then
            self.left, self.bottom = c, d - self.h
        elseif point == 'BOTTOMLEFT' then
            self.left, self.bottom = c, d
        elseif point == 'CENTER' then
            self.left = ({SCREEN_W} - self.w) / 2 + (a or 0)
            self.bottom = ({SCREEN_H} - self.h) / 2 + (b or 0)
        end
    end

    return f
end
""")

# A Theme that records who was told to be the front window rather than
# painting one. What is being asserted here is which frame WindowStack picks;
# that the pick is drawn as full alpha is Theme's own business.
lua.execute("""
FOCUSED = 'unset'

ShowUsYourLoot.Theme = {
    -- Recorded by tag rather than by frame: a Lua table does not keep its
    -- identity across the Python boundary, so comparing the frames
    -- themselves would fail on two windows that are genuinely different.
    SetFocusedWindow = function(frame)
        FOCUSED = frame and frame.tag or nil
        return true
    end,
}
""")

for name in ("WindowLayout.lua", "WindowStack.lua"):
    lua.execute((UI / name).read_text(encoding="utf-8"))

SYL = lua.globals().ShowUsYourLoot
MakeFrame = lua.globals().MakeFrame
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def box(frame):
    return (frame.left, frame.bottom, frame.w, frame.h)


def overlaps(a, b):
    return (a[0] < b[0] + b[2] and a[0] + a[2] > b[0]
            and a[1] < b[1] + b[3] and a[1] + a[3] > b[1])


def fresh_stack():
    """A new runtime state — WindowStack keeps module-level order and membership."""
    lua.execute((UI / "WindowStack.lua").read_text(encoding="utf-8"))

    return lua.globals().ShowUsYourLoot.WindowStack


# --- nothing dragged: the set is laid out together ------------------------
stack = fresh_stack()

main = MakeFrame(MAIN_W, MAIN_H)
settings = MakeFrame(SETTINGS_W, SETTINGS_H)

stack.ToggleWindow(main)
stack.ToggleWindow(settings)

check("both windows are open", main.shown and settings.shown)
check("and they do not overlap when nothing has been dragged",
      not overlaps(box(main), box(settings)),
      f"main={box(main)} settings={box(settings)}")

# --- THE ONE THIS FILE EXISTS FOR -----------------------------------------
#
# The main window is dragged, then Settings is opened. The drag must not turn
# the main window into empty space.
stack = fresh_stack()

main = MakeFrame(MAIN_W, MAIN_H)
settings = MakeFrame(SETTINGS_W, SETTINGS_H)

stack.ToggleWindow(main)

# Dragged, and left near the middle of the screen — which is where it starts
# and where a nudge leaves it. Anywhere else and center might happen to be
# free, so the test would pass with the bug still in.
stack.NoteUserMoved(main)
main.SetPoint(main, "CENTER", 0, 0)

centered = ((SCREEN_W - SETTINGS_W) / 2, (SCREEN_H - SETTINGS_H) / 2)

stack.ToggleWindow(settings)

# THE ASSERTION. Not "they do not overlap" — with the main window dragged the
# layout may not move it, and a 560-wide panel does not fit in the 490 either
# side of a centered 900-wide window. There is no clear spot, and a test
# demanding one could only be made to pass by overruling the drag.
#
# What must hold is that placement did *something*. Landing on the creation
# position is the single answer guaranteed to sit exactly on the dashboard,
# and it was what shipped.
check("SETTINGS DOES NOT OPEN EXACTLY ON THE DASHBOARD",
      (settings.left, settings.bottom) != centered,
      f"settings sat at its creation point {centered}")
check("and the dragged window was not moved to make room",
      main.left == (SCREEN_W - MAIN_W) / 2
      and main.bottom == (SCREEN_H - MAIN_H) / 2,
      box(main))
check("settings is still on screen", settings.left >= 0
      and settings.left + settings.w <= SCREEN_W, box(settings))

# --- a dragged window that is closed is not an obstacle -------------------
#
# The list is of windows that are *shown*. A hidden one taking up space would
# push the next window off center for no visible reason.
stack = fresh_stack()

main = MakeFrame(MAIN_W, MAIN_H)
settings = MakeFrame(SETTINGS_W, SETTINGS_H)

stack.ToggleWindow(main)
stack.NoteUserMoved(main)
stack.ToggleWindow(main)

check("the main window is closed", not main.shown)

stack.ToggleWindow(settings)

check("a closed window does not push the next one off center",
      settings.left == (SCREEN_W - SETTINGS_W) / 2, box(settings))

# --- placed once, not on every show ---------------------------------------
#
# Re-placing on each show would drag a window the user had moved back to where
# the layout thought it belonged.
stack = fresh_stack()

main = MakeFrame(MAIN_W, MAIN_H)

stack.ToggleWindow(main)
placed = box(main)

stack.ToggleWindow(main)
stack.ToggleWindow(main)

check("reopening a window leaves it where it was", box(main) == placed,
      f"{placed} -> {box(main)}")

# --- which window is the front one ----------------------------------------
#
# Every palette paints a window at 0.97 alpha, which reads as depth on one
# window and as a mess on two: overlap them and the back one's text shows
# through the front one's body. The front window is drawn solid instead, and
# the question this layer answers is *which* one that is.
#
# Derived from frame levels rather than remembered, so it cannot disagree with
# what is actually drawn on top — which is the failure a separate "selected"
# note would eventually produce.
stack = fresh_stack()
G = lua.globals()

main = MakeFrame(MAIN_W, MAIN_H, "main")
settings = MakeFrame(SETTINGS_W, SETTINGS_H, "settings")

stack.ToggleWindow(main)

check("the only open window is the front one", G.FOCUSED == "main", G.FOCUSED)

stack.ToggleWindow(settings)

check("OPENING A SECOND WINDOW MOVES THE FRONT TO IT",
      G.FOCUSED == "settings", G.FOCUSED)

# --- clicking a buried window brings it forward ---------------------------
#
# The behaviour that makes "selected" mean anything. Before this, a window only
# rose when something opened it, so the one underneath stayed underneath until
# you closed the other.
main.Click(main)

check("CLICKING A BURIED WINDOW RAISES IT", main.level > settings.level,
      (main.level, settings.level))
check("and it becomes the front one", G.FOCUSED == "main", G.FOCUSED)

settings.Click(settings)

check("and clicking back swaps them again", G.FOCUSED == "settings",
      G.FOCUSED)

# --- the levels are banded, not merely different --------------------------
#
# THE BUG THIS HALF EXISTS FOR, reported from the client: the credit picker
# opened from a button on the drop detail window and appeared *behind* it.
# Every window is DIALOG strata and none of them ever set a frame level, so
# they all sat on the same one — Raise() had nothing to reorder, IsTopmost
# answered true for all of them at once because it asks whether anything is
# higher, and the front window was not painted solid either. One cause, three
# symptoms.
#
# A GAP OF ONE IS NOT ENOUGH. A window's own popups take its level plus an
# offset: UI/NameSuggest.lua uses +20, and the resize grip, the command menu,
# the filter dropdown and the absence suggestions all use +10. So two windows
# one level apart would let the lower one's dropdown draw over the upper
# window. The gap has to clear the largest of those offsets.
check("two open windows are never on the same frame level",
      main.level != settings.level, (main.level, settings.level))

check("AND THE GAP CLEARS THE +20 A POPUP TAKES",
      abs(main.level - settings.level) > 20,
      (main.level, settings.level))

check("the front window is the higher one",
      settings.level > main.level, (main.level, settings.level))

# Bounded, not climbing. Re-numbering from the stack means a hundred raises
# cost nothing; incrementing a counter would have walked toward the ceiling.
for _ in range(50):
    main.Click(main)
    settings.Click(settings)

check("raising repeatedly does not walk the levels upward",
      max(main.level, settings.level) < 1000,
      (main.level, settings.level))

# --- closing hands the front to whatever is underneath --------------------
#
# Closing the top window and leaving the next one translucent would look
# exactly like the bug this fixes.
stack.ToggleWindow(settings)

check("CLOSING THE FRONT WINDOW PROMOTES THE ONE BELOW",
      G.FOCUSED == "main", G.FOCUSED)

stack.ToggleWindow(main)

check("and closing the last one leaves nothing in front",
      G.FOCUSED is None, G.FOCUSED)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
