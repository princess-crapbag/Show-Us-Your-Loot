"""The dashboard's widget registry: what is on, and in what order.

The order is a saved list of widget names and the whole design rests on it
staying dumb — a name this version does not know is skipped, and a widget the
saved list never mentions is appended. Both cases have to draw a working
dashboard rather than an empty one, because that is what makes an order saved
by an older version safe to read back.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

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

CORE = Path(__file__).resolve().parent.parent / "Core"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("ShowUsYourLoot = {}")
lua.execute("ShowUsYourLootDB = {}")
lua.execute((CORE / "Dashboard.lua").read_text(encoding="utf-8"))

dash = lua.globals().ShowUsYourLoot.Dashboard
failures = []


def check(label, ok):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def order():
    return list(dash.GetOrder().values())


def reset():
    lua.execute("ShowUsYourLootDB = {}")


declared = [w["key"] for w in dash.WIDGETS.values()]

# --- defaults -------------------------------------------------------------
reset()
check("every widget is on by default", all(dash.IsEnabled(k) for k in declared))
check("all of them count", dash.CountEnabled() == len(declared))
check("the default order holds every widget", sorted(order()) == sorted(declared))
check("and starts with last raid night", order()[0] == "lastNight")

# --- turning them off -----------------------------------------------------
dash.SetEnabled("tier", False)
check("one can be switched off", dash.IsEnabled("tier") is False)
check("the count follows", dash.CountEnabled() == len(declared) - 1)
check("it leaves the visible list", "tier" not in [w["key"] for w in dash.Visible().values()])
check("but stays in the order", "tier" in order())

dash.Toggle("tier")
check("toggle puts it back", dash.IsEnabled("tier") is True)
# nil rather than false, so a fresh install carries no disabled table at all.
check("on is stored as nothing", lua.globals().ShowUsYourLootDB.dashboard.disabled["tier"] is None)

# --- reordering -----------------------------------------------------------
reset()
first, second = order()[0], order()[1]
check("a widget moves down", dash.Move(first, 1) is True)
check("and the two swap", order()[0] == second and order()[1] == first)
check("the top cannot move up", dash.Move(order()[0], -1) is False)
check("the bottom cannot move down", dash.Move(order()[-1], 1) is False)

dash.ResetOrder()
check("reset restores the default", order()[0] == "lastNight")

# --- saved orders from other versions -------------------------------------
# A widget removed in a later version: the name must be skipped, not drawn.
reset()
lua.execute("""
    ShowUsYourLootDB.dashboard = {
        order = { 'due', 'somethingRemovedLater', 'lastNight' },
    }
""")
got = order()
check("an unknown name is skipped", "somethingRemovedLater" not in got)
check("the names it does know keep their order", got[:2] == ["due", "lastNight"])
# A widget added in a later version: absent from the saved list, must appear.
check("widgets missing from the saved order are appended", sorted(got) == sorted(declared))
check("nothing is lost", len(got) == len(declared))

# An empty saved order is the worst case — it must not blank the dashboard.
reset()
lua.execute("ShowUsYourLootDB.dashboard = { order = {} }")
check("an empty saved order still draws everything", sorted(order()) == sorted(declared))

# --- widget declarations --------------------------------------------------
reset()
for widget in dash.WIDGETS.values():
    key = widget["key"]
    check(f"{key} names a tab to open", isinstance(widget["tab"], str) and widget["tab"] != "")
    check(f"{key} explains itself", isinstance(widget["note"], str) and len(widget["note"]) > 10)

check("recording spans the full width", dash.Get("recording")["span"] == 3)
check("next raid night declares it needs the calendar", dash.Get("nextNight")["needs"] == "calendar")

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
