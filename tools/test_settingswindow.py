"""The settings window builds every section, and fits on a screen.

WHY THIS EXISTS. `AddSection` set `container.heading` one line above the
`local container` that declares it, so `container` was a nil global and the
function threw on its first call. The window drew its title, its subtitle and
one section heading, then nothing — no qualities, no toggles, no features, no
widget list. On screen that read as "the settings screen is empty", not as a
crash, and it survived a clean `syl_check` run because the rule that catches a
local used before its declaration does not exist here. luacheck is the tool for
that class and is still the open tooling item.

Nothing in the suite opened this window, so nothing noticed. This does.

The second half is the size. Every feature added is another 38px of content,
and the window was sized to fit all of it — so it grew past the bottom of the
screen and the last sections became unreachable. It is capped now and the
content scrolls, which is the arrangement that does not need revisiting each
time a feature lands.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from lupa import LuaRuntime  # noqa: F401  (imported for the error message)
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

import test_load  # noqa: E402  — reuses its stubbed client and loaded addon

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

# --- the sections build ----------------------------------------------------
#
# Called directly rather than through the window, so a failure names the
# section that broke instead of "settings did not open".
lua.execute("SECTION_PARENT = StubFrame()")

parent = lua.globals().SECTION_PARENT

for label, builder in (
    ("the quality section", SYL.SettingsRows.BuildQualitySection),
    ("the behaviour section", SYL.SettingsRows.BuildToggleSection),
    ("the feature section", SYL.SettingsRows.BuildFeatureSection),
):
    try:
        builder(parent)
        check(f"{label} builds", True)
    except Exception as err:  # noqa: BLE001 — any Lua error is the finding
        check(f"{label} builds", False, err)

# AddSection hands back the heading as well as the container, and callers that
# rebuild a section need it — the heading is a font string on the parent, not a
# child of the container, so hiding the container alone leaves it behind and
# every rebuild stacks another one in the same place. This is also the exact
# field whose assignment was throwing.
try:
    container, heading = SYL.SettingsRows.AddSection(parent, "TEST", -8)

    check("a section hands back its container", container is not None)
    check("and its heading", heading is not None)
except Exception as err:  # noqa: BLE001
    check("a section hands back its container", False, err)
    check("and its heading", False, err)

# --- the whole window ------------------------------------------------------
try:
    SYL.OpenSettingsWindow(SYL)
    check("the window opens", True)
except Exception as err:  # noqa: BLE001
    check("the window opens", False, err)

# --- it fits ---------------------------------------------------------------
#
# The stubbed UIParent reports 100, so the cap is the floor rather than the
# screen — which is the branch worth checking anyway: a tiny screen must not
# produce a window shorter than its own chrome.
content = SYL.SettingsRows.ContentHeight()
window = SYL.SettingsRows.WindowHeight()

check("the content is taller than one screenful", content > 400, content)
check("the window is not", window <= content, f"{window} vs {content}")
check("and is still usable rather than collapsed", window >= 320, window)
check("so it has to scroll", SYL.SettingsRows.NeedsScrolling() is True)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
