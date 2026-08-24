# -*- coding: utf-8 -*-
"""Names in class color, and the one branch that must never be skipped.

Aimee: "everywhere a character name is listed in the addon can it be in their
class color? its easier visually to register who it is."

Nineteen call sites across seventeen files were already doing this, and all
nineteen hand-rolled the same six lines. They call SYL.ClassColor.Set now.

THE ASSERTION THAT MATTERS MOST is the fallback branch, and it is not about
tidiness. Theme.SetCustomTextColor DEREGISTERS a font string from the palette
repaint list -- deliberately, because a class color is not the palette's
business. Rows are POOLED. So a row that draws a class-colored raider and is
then reused for somebody whose class is unknown must call SetTextColor to put
itself back on that list. Skip it and two things happen at once:

  the new name keeps the PREVIOUS raider's color, and
  that row stops responding to a theme change for the rest of the session.

Neither looks like a crash. Both look like the addon being slightly wrong.

Also asserted here: that nothing still hand-rolls the block, because the way
this regresses is somebody adding a twentieth screen and copying the six lines
from the nineteenth.

Needs `lupa` - see tools/test_lootmessages.py for the setup.
"""
import glob
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import test_load  # noqa: E402

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s  %s" % (name, detail))
        failures.append(name)


ClassColor = SYL.ClassColor


# --------------------------------------------------------------------------
# A client with real class colors
# --------------------------------------------------------------------------

lua.execute("""
    RAID_CLASS_COLORS = {
        MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    }

    C_ClassColor = nil

    -- A font string that records what was done to it, which is the only way
    -- to see the fallback branch at all.
    PAINTED = {}

    function TRACKED()
        local fs = StubFrame()

        rawset(fs, "sylCalls", {})

        rawset(fs, "SetTextColor", function(self, r, g, b)
            table.insert(rawget(self, "sylCalls"),
                string.format("custom %.2f %.2f %.2f", r, g, b))
        end)

        return fs
    end

    function CALLS(fs) return rawget(fs, "sylCalls") end
""")

Tracked = lua.globals().TRACKED
Calls = lua.globals().CALLS


def calls(fs):
    return [str(v) for v in Calls(fs).values()]


check("a known class resolves to a color",
      ClassColor.Get("MAGE") is not None)

check("an unknown class resolves to nothing",
      ClassColor.Get("NOTACLASS") is None)

check("and so does an empty one", ClassColor.Get("") is None)
check("and nil", ClassColor.Get(None) is None)


# --------------------------------------------------------------------------
# Set, and the branch that must not be skipped
# --------------------------------------------------------------------------

painted = Tracked()

check("setting a known class reports that it painted",
      ClassColor.Set(painted, "MAGE") is True)

check("and it actually painted", len(calls(painted)) == 1,
      "%r" % calls(painted))

plain = Tracked()

check("setting an unknown class reports that it did not",
      ClassColor.Set(plain, "NOTACLASS") is False)

# THE ONE THAT PROTECTS POOLED ROWS. An unknown class must still touch the
# font string, because touching it is what re-registers it for theme changes.
check("but it still repaints, which is what re-registers the row",
      len(calls(plain)) == 1,
      "the fallback branch did nothing - pooled rows will keep the previous "
      "raider's color")

check("a nil font string is survivable", ClassColor.Set(None, "MAGE") is False)


# --------------------------------------------------------------------------
# Chat is a different mechanism
# --------------------------------------------------------------------------

code = ClassColor.Code("MAGE")

check("a known class has an escape code",
      isinstance(code, str) and code.startswith("|cff") and len(code) == 10,
      "%r" % code)

check("an unknown class has none - not an empty string",
      ClassColor.Code("NOTACLASS") is None)

named = ClassColor.Name("Misothelioma", "MAGE")

check("a chat name is wrapped and closed",
      named.startswith("|cff") and named.endswith("|r")
      and "Misothelioma" in named,
      "%r" % named)

# HALF AN ESCAPE SEQUENCE IS WORSE THAN NONE: it would swallow the rest of
# the line's formatting.
plainName = ClassColor.Name("Nobody", "NOTACLASS")

check("an unknown class gives a plain name with no stray codes",
      plainName == "Nobody", "%r" % plainName)

check("and a nil name does not crash the line",
      isinstance(ClassColor.Name(None, "MAGE"), str))


# --------------------------------------------------------------------------
# Nothing hand-rolls it any more
# --------------------------------------------------------------------------
#
# This is the regression guard. The way this comes back is somebody adding a
# twentieth screen and copying the six lines out of the nineteenth.

root = test_load.ROOT
handRolled = []

for path in sorted(glob.glob(str(root / "UI" / "*.lua"))
                   + glob.glob(str(root / "Core" / "*.lua"))):
    if os.path.basename(path) == "ClassColor.lua":
        continue

    source = open(path, encoding="utf-8").read()

    if "GetClassColor" in source and "-- " not in source.split(
            "GetClassColor")[0].splitlines()[-1]:
        handRolled.append(os.path.basename(path))

check("no file still calls GetClassColor outside UI/ClassColor.lua",
      not handRolled, "%r" % handRolled)

theme = (root / "UI" / "Theme.lua").read_text(encoding="utf-8")

check("Theme no longer defines it",
      "function Theme.GetClassColor" not in theme)

check("nor ClassLabel", "function Theme.ClassLabel" not in theme)


# --------------------------------------------------------------------------
# The three screens that were missing it
# --------------------------------------------------------------------------

def source(name):
    return (root / name).read_text(encoding="utf-8")

# The "who is out" dashboard tile called the uncolored Row when the two tiles
# either side of it called PlayerRow.
check("the who-is-out tile names people in class color",
      "DashboardParts.PlayerRow" in source("UI/ScheduleWidgets.lua"))

# Every chat-captured row in the loot list - personal loot, vault, crafted,
# world drops - had no class at all. Her database holds 193 of those against
# 38 group-loot records.
feed = source("Core/LootFeed.lua")

check("chat-captured loot rows carry a class",
      "creditedClass = displayClass" in feed)

check("and the class comes from the lookup that was already happening",
      "return player.name or name, player.class" in feed)

# /syl due prints a ranked list with entry.class in scope and no way to use it.
check("the due report colors names in chat",
      "ClassColor.Name(entry.name, entry.class)"
      in source("Core/CommandReports.lua"))

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
