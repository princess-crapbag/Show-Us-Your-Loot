# -*- coding: utf-8 -*-
"""Three things that were correct today and wrong on the next ordinary edit.

None of these is a bug Aimee could hit right now. They are the three places
where a fact the code depends on is written down twice, or not at all, and the
copy that goes stale takes a screen with it.

  THE SHARED LISTENER. UI/LootListView.lua owned the one frame listening for
  GET_ITEM_INFO_RECEIVED and called UnregisterAllEvents on it whenever its own
  rows were all cached. The Bosses tab needs the same event -- a boss's loot
  table is mostly items this character has never seen, so it drew a column of
  blank squares that never filled in -- and wiring it to that frame would have
  meant one screen silently switching the other's listener off. Core/
  ItemCacheWatch.lua keys the wait, and the assertion below is that two
  screens can wait and stop waiting independently.

  ONE HEIGHT, TWO ANSWERS. UI/SettingsWidgets.lua SectionHeight() returned
  HEADING + rows + 24 while Build returned HEADING + rows + 26. The tab
  reserves scroll room with the first and draws with the second, so the
  section was two pixels taller than its room -- invisible at seven widgets,
  a clipped "Default order" button the moment an eighth pushes the grid to a
  fourth line. Compared by running both rather than reading them.

  A SECTION THAT MIGHT NOT EXIST. BuildToggleSection returns nil when no
  toggle claims the tab it was asked for, and UI/SettingsScoring.lua read
  container.heading off it without looking. One edit to which tab a toggle
  belongs to and the whole Scoring tab stops opening. Driven by actually
  taking the scoring toggles away.

AND THE SOURCE ASSERTIONS AT THE END, for the reason tools/test_filterbar.py
gives at length: the stub frame answers every key with a function and accepts
any arguments, so it cannot see a call made on the wrong object or with the
wrong shape. Where the guard has to be a source assertion, it says so.

Needs `lupa` -- see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from lupa import LuaRuntime  # noqa: F401  (imported for the error message)
except ImportError:
    sys.exit(
        "lupa is not installed - see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

import test_load  # noqa: E402  - reuses its stubbed client and loaded addon

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot
ROOT = Path(__file__).resolve().parent.parent
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

# --------------------------------------------------------------------------
# The shared listener
# --------------------------------------------------------------------------
watch = SYL.ItemCacheWatch

watch.Set("lootList", False)
watch.Set("bossLoot", False)

check("nothing is listening when nothing is waiting", watch.IsWatching() is False)

watch.Set("lootList", True)

check("one screen waiting is enough to listen", watch.IsWatching() is True)

watch.Set("bossLoot", False)

check("and another screen finishing does not switch it off",
      watch.IsWatching() is True,
      "this is the bug: UnregisterAllEvents on a shared frame")

watch.Set("bossLoot", True)
watch.Set("lootList", False)

check("the last screen still waiting holds it open",
      watch.IsWatching() is True)

watch.Set("bossLoot", False)

check("and it stops when the last one is done", watch.IsWatching() is False)

# --------------------------------------------------------------------------
# One height, two answers
# --------------------------------------------------------------------------
reserved = SYL.SettingsWidgets.SectionHeight()

built = lua.eval("""
    function()
        local page = StubFrame()

        local ok, container, height = pcall(
            ShowUsYourLoot.SettingsWidgets.Build, page, -20,
            ShowUsYourLoot.SettingsRows.AddSection
        )

        if not ok then
            return -1
        end

        return height
    end
""")()

check("the widget section is as tall as the room reserved for it",
      built == reserved, "reserved %r, drew %r" % (reserved, built))

# --------------------------------------------------------------------------
# A section that might not exist
# --------------------------------------------------------------------------
#
# Every scoring toggle taken away, which is what one edit to a toggle's `tab`
# field does. BuildToggleSection then answers nil and the tab has to cope.
ok, err = lua.eval("""
    function()
        local toggles = ShowUsYourLoot.SettingsToggles
        local real = toggles.LIST
        local without = {}

        for _, toggle in ipairs(real) do
            if toggle.tab ~= "scoring" then
                table.insert(without, toggle)
            end
        end

        toggles.LIST = without

        local ok, err = pcall(
            ShowUsYourLoot.SettingsScoring.Build, StubFrame(), -20
        )

        toggles.LIST = real

        return ok, tostring(err)
    end
""")()

check("the Scoring tab still builds with no toggles of its own",
      ok is True, err)

# And it is still right the ordinary way round.
ok, err = lua.eval("""
    function()
        local ok, err = pcall(
            ShowUsYourLoot.SettingsScoring.Build, StubFrame(), -20
        )

        return ok, tostring(err)
    end
""")()

check("and with them, which is how it actually ships", ok is True, err)

# --------------------------------------------------------------------------
# What the stub cannot see
# --------------------------------------------------------------------------
boss = source("UI/BossLoot.lua")

check("the boss list reports the wait once, after the draw",
      'SYL.ItemCacheWatch.Set("bossLoot", waitingOnCache)' in boss,
      "reporting inside Draw misses two of its three returns")

check("and a row with a link but no icon is what counts as waiting",
      "if link then\n                waitingOnCache = true" in boss)

check("while a hidden pane waits for nothing",
      'SYL.ItemCacheWatch.Set("bossLoot", false)' in boss,
      "otherwise the tab keeps redrawing the window after you leave it")

feed = source("UI/LootListView.lua")

check("and the loot list no longer owns a listener of its own",
      "cacheWatcher" not in feed and 'ItemCacheWatch.Set("lootList"' in feed,
      "two frames on one event is the thing this replaced")

widgets = source("UI/SettingsWidgets.lua")

check("the widget height is arrived at in one place",
      widgets.count("ContainerHeight(") == 4,
      "a second literal is how the two numbers drifted apart")

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
