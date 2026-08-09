"""Non-overlapping window placement (F3).

Geometry is easy to get subtly wrong and impossible to eyeball from the code,
so the rules are checked directly: placed windows sit inside the screen, clear
of each other, and centred as a group.

The arithmetic that motivated this is worth keeping in view. The main window
is 900 wide on a 1920 screen; centred, it leaves 490 either side, and the due
window is 660. There is no gap to put it in. Placing each new window into a
hole around the existing ones therefore fails almost every time — which is
what F3 was raised about — and the fix is to lay the set out together.

The Lua is lifted out of UI/WindowLayout.lua with UIParent and the frames
stubbed, so this runs the shipped arithmetic rather than a restatement of it.

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

ADDON = Path(__file__).resolve().parent.parent / "UI" / "WindowLayout.lua"
source = ADDON.read_text(encoding="utf-8")

start = source.index("local function ScreenBounds()")
end = source.index("-- The public entry point.")
block = source[start:end]

SCREEN_W, SCREEN_H = 1920, 1080
MARGIN = 20
GAP = 8

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f"""
UIParent = {{
    GetWidth = function() return {SCREEN_W} end,
    GetHeight = function() return {SCREEN_H} end,
}}

local WINDOW_GAP = {GAP}
local SCREEN_MARGIN = {MARGIN}

{block}

_G.FindSpot = FindSpot
_G.Arrange = Arrange

-- A frame is only ever asked for its size and told where to go.
function _G.MakeFrame(width, height)
    return {{
        w = width, h = height,
        GetWidth = function(self) return self.w end,
        GetHeight = function(self) return self.h end,
        ClearAllPoints = function() end,
        SetPoint = function(self, _, _, _, left, top)
            self.left = left
            self.top = top
        end,
    }}
end
""")

Arrange = lua.globals().Arrange
FindSpot = lua.globals().FindSpot
MakeFrame = lua.globals().MakeFrame

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else "  " + detail))
    if not ok:
        failures.append(label)


def boxes(frames):
    """Placed frames as (left, bottom, width, height)."""
    out = []
    for f in frames:
        assert f.left is not None, "frame was never placed"
        out.append((f.left, f.top - f.h, f.w, f.h))
    return out


def overlaps(a, b):
    return (a[0] < b[0] + b[2] and a[0] + a[2] > b[0]
            and a[1] < b[1] + b[3] and a[1] + a[3] > b[1])


def arrange(*sizes):
    frames = [MakeFrame(w, h) for w, h in sizes]
    lua.execute("frames = {}")
    table = lua.globals().frames
    for i, f in enumerate(frames, 1):
        table[i] = f
    return bool(Arrange(table)), frames


def on_screen(box):
    return (box[0] >= MARGIN and box[1] >= MARGIN
            and box[0] + box[2] <= SCREEN_W - MARGIN
            and box[1] + box[3] <= SCREEN_H - MARGIN)


# One window is centred, as it should be.
ok, frames = arrange((900, 596))
placed = boxes(frames)
check("a lone window is laid out", ok)
check("and is centred",
      ok and abs(placed[0][0] - (SCREEN_W - 900) / 2) < 1,
      f"got {placed}")

# The case the whole thing exists for: main window plus due window.
ok, frames = arrange((900, 596), (660, 500))
placed = boxes(frames)
check("the main and due windows both get placed", ok)
check("and do not overlap",
      ok and not overlaps(placed[0], placed[1]), f"got {placed}")
check("and both are on screen",
      ok and all(on_screen(b) for b in placed), f"got {placed}")
check("and they sit side by side, not stacked",
      ok and abs(placed[0][1] - placed[1][1]) < placed[0][3],
      f"got {placed}")

# Three windows: wraps to a second row rather than giving up.
ok, frames = arrange((900, 596), (660, 400), (820, 400))
placed = boxes(frames)
check("three windows are laid out", ok)
if ok:
    clear = all(
        not overlaps(placed[i], placed[j])
        for i in range(len(placed)) for j in range(i + 1, len(placed))
    )
    check("and none of the three overlap", clear, f"got {placed}")
    check("and all three are on screen",
          all(on_screen(b) for b in placed), f"got {placed}")

# More than the screen can hold: refuses rather than placing badly, so the
# caller falls back to the cascade.
ok, _ = arrange((1800, 1000), (1800, 1000), (1800, 1000))
check("an impossible set is refused rather than forced", not ok)

# A window wider than the usable screen cannot be packed at all.
ok, _ = arrange((SCREEN_W, 400))
check("a window wider than the screen is refused", not ok)

# FindSpot is the fallback for when something has been dragged. With the
# centred main window there is genuinely no 660-wide gap, and saying so is
# the correct answer.
lua.execute("""
rects = { { left = 510, bottom = 242, right = 1410, top = 838 } }
""")
check("no gap beside a centred main window, and it says so",
      FindSpot(660, 500, lua.globals().rects) is None)

check("a small window does find a gap",
      FindSpot(300, 200, lua.globals().rects) is not None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
