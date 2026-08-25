"""The minimap button sits ON the ring, drags anywhere, and is not the only door.

THE BUG THIS EXISTS FOR. The ring radius was the literal 80 -- half of a 160
pixel minimap, plus a little -- and the retail minimap has not been 160 pixels
wide for years. So the button was drawn a long way inside the circle, on top
of the map itself. It shipped that way and the first person outside the guild
to install it said so: "Its IN the map circle". Nothing in this repository
could have caught it, because nothing measured the minimap.

So the first check here is the one that matters: whatever the minimap's size,
the middle of the button is OUTSIDE it. A hardcoded number cannot pass that
twice with two different minimaps, which is the point.

The rest is what the same feedback asked for. The button drags anywhere on
the screen rather than orbiting the minimap, and comes back onto the ring when
it is dropped on it. And the two doors that are not ours -- the Data Broker
feed Titan Panel reads, and the game's own addon compartment -- exist, are
reachable, and do the same two things the button does.

Both real files are loaded unmodified, so these run the shipped path.

Needs `lupa`; see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import math
import re
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

ROOT = Path(__file__).resolve().parent.parent

SCREEN_W, SCREEN_H = 1920, 1080

# The retail minimap, which is nothing like the 160 the old code assumed, and
# is sitting near the top right corner of the screen where it always is.
MINIMAP = 198
MINIMAP_CX, MINIMAP_CY = 1740, 900

lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute("""
OPENED, TOGGLED, CLOSED = 0, 0, 0

ShowUsYourLoot = {
    CommandMenu = {
        Toggle = function(frame) TOGGLED = TOGGLED + 1; TOGGLED_ON = frame end,
        Close = function() CLOSED = CLOSED + 1 end,
    },
}

function ShowUsYourLoot:OpenMainWindow() OPENED = OPENED + 1 end
function ShowUsYourLoot:DebugPrint(message) DEBUG = message end

ShowUsYourLootDB = { settings = {} }

-- Frames record what was done to them rather than doing it. Points are kept
-- whole -- anchor, relative frame and both offsets -- because every question
-- below is about where the button ended up and what it ended up attached to.
function MakeFrame(width, height)
    local frame = {
        w = width or 31,
        h = height or 31,
        scripts = {},
        shown = true,
        scale = 1,
        tag = "frame",
    }

    function frame:SetSize(w, h) self.w, self.h = w, h end
    function frame:GetWidth() return self.w end
    function frame:GetHeight() return self.h end
    function frame:GetEffectiveScale() return self.scale end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetParent() return self.parent end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    function frame:ClearAllPoints() self.point = nil end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = point
        self.relativeTo = relativeTo
        self.x = x or 0
        self.y = y or 0
    end

    function frame:CreateTexture()
        local texture = MakeFrame()
        texture.SetTexture = function(self, path) self.path = path end
        texture.SetTexCoord = function() end
        return texture
    end

    -- Everything else the button calls on itself and never reads back.
    for _, name in ipairs({
        "SetFrameStrata", "SetFrameLevel", "RegisterForClicks",
        "RegisterForDrag", "SetMovable", "SetClampedToScreen", "EnableMouse",
        "SetTexture", "SetTexCoord", "SetOwner", "AddLine",
    }) do
        frame[name] = function() end
    end

    return frame
end

function CreateFrame(kind, name, parent)
    local frame = MakeFrame()
    frame.parent = parent
    return frame
end

UIParent = MakeFrame(%d, %d)
UIParent.tag = "screen"
function UIParent:GetCenter() return self.w / 2, self.h / 2 end

Minimap = MakeFrame(%d, %d)
Minimap.tag = "minimap"
function Minimap:GetCenter() return MINIMAP_CX, MINIMAP_CY end

MINIMAP_CX, MINIMAP_CY = %d, %d

CURSOR_X, CURSOR_Y = 0, 0
function GetCursorPosition() return CURSOR_X, CURSOR_Y end

-- THE GAME'S LUA HAS THIS AND THIS INTERPRETER DOES NOT. math.atan2 is Lua
-- 5.1, which is what WoW runs; lupa is built against a later one that dropped
-- it. Shimmed here rather than worked around in the addon, because the addon
-- is written for the client it ships to.
if not math.atan2 then
    math.atan2 = function(y, x) return math.atan(y, x) end
end

GameTooltip = MakeFrame()
function GameTooltip:AddLine(text) TOOLTIP_LINES = (TOOLTIP_LINES or 0) + 1 end
""" % (SCREEN_W, SCREEN_H, MINIMAP, MINIMAP, MINIMAP_CX, MINIMAP_CY))

lua.execute(
    (ROOT / "UI" / "MinimapButton.lua").read_text(encoding="utf-8")
)

g = lua.globals()
SYL = g.ShowUsYourLoot
settings = g.ShowUsYourLootDB.settings

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def anchored_to():
    """The tag of whatever the button is anchored to. Compared by name because
    the same Lua table comes back as a different Python object each time."""
    return button.relativeTo.tag if button.relativeTo else None


def offset():
    """Where the middle of the button is, from the middle of whatever it is on."""
    return button.x, button.y


def reach():
    x, y = offset()
    return math.sqrt(x * x + y * y)


def drag_to(screen_x, screen_y):
    """A real drag: press, move the cursor, let go."""
    button.scripts.OnDragStart(button)
    g.CURSOR_X, g.CURSOR_Y = screen_x, screen_y
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)


button = SYL.MinimapButton.Create()

# THE ONE THAT WOULD HAVE CAUGHT IT. 99 is the minimap's own radius, so
# anything at or under it is drawn on the map.
check("the button sits outside the minimap, not on top of it",
      reach() > MINIMAP / 2,
      f"{reach():.1f} from the middle of a {MINIMAP // 2} radius minimap")

check("and only just outside it, rather than floating off on its own",
      reach() < MINIMAP / 2 + 12, f"{reach():.1f}")

check("it is parented to the minimap, where button collectors look for it",
      button.parent.tag == "minimap", button.parent.tag)

on_default = reach()

# And the same button against a minimap of another size. Edit Mode resizes
# the real one, so this is not a hypothetical.
g.Minimap.w, g.Minimap.h = 140, 140
SYL.MinimapButton.ResetPosition()

check("a resized minimap moves it, because the radius is measured not typed",
      reach() > 70 and reach() < 82 and abs(reach() - on_default) > 20,
      f"{reach():.1f} on a 140 minimap, {on_default:.1f} on a {MINIMAP}")

g.Minimap.w, g.Minimap.h = MINIMAP, MINIMAP
SYL.MinimapButton.ResetPosition()

# DRAGGED SOMEWHERE ELSE ENTIRELY. The feedback in one line: it "needs to be
# able to be drug around freely". The bottom left of the screen is nowhere
# near the minimap, and the button has to simply be there.
drag_to(300, 200)

check("dragged across the screen, it goes where it was dragged",
      anchored_to() == "screen"
      and abs(button.x - (300 - SCREEN_W / 2)) < 1
      and abs(button.y - (200 - SCREEN_H / 2)) < 1,
      f"({button.x}, {button.y})")

check("and it is remembered, so a reload does not snatch it back",
      settings.minimapFreeX is not None and settings.minimapFreeY is not None,
      f"x={settings.minimapFreeX} y={settings.minimapFreeY}")

# Off the edge of the screen is the one place it must not go: the way back
# from a button that cannot be clicked is a command nobody has read yet.
drag_to(SCREEN_W + 400, SCREEN_H + 400)

check("a drag past the edge of the screen is clamped, never lost",
      abs(button.x - (SCREEN_W - 31) / 2) < 1
      and abs(button.y - (SCREEN_H - 31) / 2) < 1,
      f"({button.x}, {button.y})")

# Dropped back on the minimap it tidies itself onto the ring, which is the
# behavior everybody already expects from every other addon's button.
drag_to(MINIMAP_CX + 40, MINIMAP_CY + 40)

check("dropped on the minimap, it snaps back onto the ring",
      anchored_to() == "minimap" and reach() > MINIMAP / 2,
      f"{reach():.1f} onto {anchored_to()}")

check("and the free position is cleared, so there is one saved place at a time",
      settings.minimapFreeX is None and settings.minimapFreeY is None)

check("the angle it was dropped at is the one remembered",
      settings.minimapAngle is not None
      and abs(settings.minimapAngle - 45) < 1,
      settings.minimapAngle)

# Just outside the ring is still "on the minimap" -- close enough that
# somebody dropping it there meant the ring.
drag_to(MINIMAP_CX + 120, MINIMAP_CY)

check("a drop just outside the ring counts as the ring",
      anchored_to() == "minimap", anchored_to())

# And far enough out that it was clearly meant to be somewhere else does not.
drag_to(MINIMAP_CX - 400, MINIMAP_CY - 300)

check("a drop well clear of it does not",
      anchored_to() == "screen", anchored_to())

check("and Reset is the way back from there",
      (SYL.MinimapButton.ResetPosition() or True)
      and anchored_to() == "minimap"
      and settings.minimapFreeX is None)

# The clicks themselves, which the drag rewrite runs through.
before_opened, before_toggled = g.OPENED, g.TOGGLED

button.scripts.OnClick(button, "LeftButton")
button.scripts.OnClick(button, "RightButton")

check("left-click still opens the window and right-click still lists commands",
      g.OPENED == before_opened + 1 and g.TOGGLED == before_toggled + 1)


# ---------------------------------------------------------------- launchers

lua.execute(
    (ROOT / "UI" / "Launchers.lua").read_text(encoding="utf-8")
)

toc = (ROOT / "ShowUsYourLoot.toc").read_text(encoding="utf-8")

for field in (
    "AddonCompartmentFunc",
    "AddonCompartmentFuncOnEnter",
    "AddonCompartmentFuncOnLeave",
):
    named = re.search(r"^## %s: (\S+)" % field, toc, re.M)

    check("the .toc declares " + field, named is not None)

    if named:
        # Named as a string and called by name, so a rename in one place and
        # not the other is a silent nothing-happens rather than an error.
        check("and " + named.group(1) + " exists to be called",
              getattr(g, named.group(1), None) is not None,
              "the compartment would click into nothing")

check("the .toc gives the compartment an icon to show",
      re.search(r"^## IconTexture: \S+", toc, re.M) is not None)

before_opened, before_toggled = g.OPENED, g.TOGGLED
# A compartment row, which is a frame with a place on the screen -- that is
# all the handler needs to tell it apart from the addon name beside it.
row = lua.eval("""(function()
    local frame = MakeFrame()
    frame.tag = "row"
    function frame:GetCenter() return 300, 900 end
    return frame
end)()""")

g.ShowUsYourLoot_OnAddonCompartmentClick("ShowUsYourLoot", "LeftButton", row)

check("the compartment entry opens the window",
      g.OPENED == before_opened + 1)

# ARGUMENTS BY TYPE, NOT BY POSITION. The compartment has not always passed
# these in the same order, so both orders are asked for here.
g.ShowUsYourLoot_OnAddonCompartmentClick("RightButton", "ShowUsYourLoot", row)

check("and right-click lists the commands whichever order the game passes",
      g.TOGGLED == before_toggled + 1)

check("anchored to the row that was clicked, not to the minimap",
      g.TOGGLED_ON.tag == "row", g.TOGGLED_ON.tag)

# THE DATA BROKER FEED. Titan Panel, Bazooka and ChocolateBar all read this,
# and none of them could see this addon before it existed.
check("with no LibDataBroker present, registering is quietly nothing",
      (SYL.Launchers.Register() or True) and lua.eval("PUBLISHED") is None)

lua.execute("""
PUBLISHED = nil

BROKER = {
    NewDataObject = function(self, name, object)
        PUBLISHED = object
        PUBLISHED_AS = name
        return object
    end,
}

LibStub = {
    GetLibrary = function(self, name, silent)
        if name == "LibDataBroker-1.1" then return BROKER end
    end,
}
""")

SYL.Launchers.Register()
published = lua.eval("PUBLISHED")

check("with one present, a launcher is published", published is not None)

if published:
    check("as a launcher, which is the type the display addons look for",
          published.type == "launcher")

    check("under a name a human recognizes in a list of plugins",
          lua.eval("PUBLISHED_AS") == "Show Us Your Loot",
          lua.eval("PUBLISHED_AS"))

    check("with an icon, since that is all some bars draw",
          isinstance(published.icon, str) and published.icon != "")

    before_opened, before_toggled = g.OPENED, g.TOGGLED

    published.OnClick(row, "LeftButton")
    published.OnClick(row, "RightButton")

    check("and it opens and lists exactly as the minimap button does",
          g.OPENED == before_opened + 1 and g.TOGGLED == before_toggled + 1)

    g.TOOLTIP_LINES = 0
    published.OnTooltipShow(g.GameTooltip)

    check("its hover says what the two clicks do",
          (g.TOOLTIP_LINES or 0) >= 3, g.TOOLTIP_LINES)

# Registering twice is one plugin, not two: PLAYER_LOGIN can fire more than
# once in a session that uses a loading screen.
lua.execute("PUBLISHED = nil")
SYL.Launchers.Register()

check("registering again publishes nothing a second time",
      lua.eval("PUBLISHED") is None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
