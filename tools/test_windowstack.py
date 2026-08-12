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
function MakeFrame(width, height)
    local f = {{ w = width, h = height, shown = false, level = 1 }}

    f.left = ({SCREEN_W} - width) / 2
    f.bottom = ({SCREEN_H} - height) / 2

    function f:GetWidth() return self.w end
    function f:GetHeight() return self.h end
    function f:GetLeft() return self.left end
    function f:GetBottom() return self.bottom end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:Raise() self.level = self.level + 1 end
    function f:GetFrameLevel() return self.level end
    function f:ClearAllPoints() end

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

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
