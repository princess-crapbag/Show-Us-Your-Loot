"""The loot filter bar, and the one call every tab switch makes through it.

THE BUG THIS SUITE EXISTS FOR. Aimee, after the date picker shipped: "the top
main tabs dont work anymore."

They did not. UI/MainWindow.lua's SetMode -- which is what a tab click calls --
does this before it redraws anything:

    if view.filterBar then
        view.filterBar:Refresh()
    end

and Refresh calls UpdatePlaceholder on both date inputs. Adding the calendar
button changed CreateDateField to return the BUTTON rather than the input, so
that call landed on a Button, threw, and took SetMode down with it before
UpdateRows was reached. Every tab in the window stopped changing anything, and
nothing about the date picker itself looked wrong.

No test drove Refresh, which is why 61 green files said nothing.

AND THE RUNTIME CHECK BELOW WOULD NOT HAVE CAUGHT IT EITHER, which is worth
writing down rather than discovering twice. The stub frame answers every key
with a function, so a Button asked for UpdatePlaceholder returns one and the
call succeeds -- exactly the trap UI/RaidersRoster.lua's header describes.
Reintroducing the bug on purpose was tried: Refresh still passed.

So the guard that actually holds is the pair of source assertions further
down, which say what CreateDateField hands back and what the To field anchors
to. The runtime call is kept because it catches everything else Refresh could
throw, and because a stub that grows real frames later makes it the better
test of the two.

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
            print("       " + str(detail))
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

# A parent and the state a filter bar is built against, which is all
# FilterBar.Create asks for.
lua.execute(
    """
    CHANGES = 0

    function MakeBar()
        local parent = StubFrame()

        return ShowUsYourLoot.FilterBar.Create(parent, {
            state = {},
            onChange = function() CHANGES = CHANGES + 1 end,
        })
    end
    """
)

# pcall answers one value on success and two on failure, so both are always
# returned here -- lupa hands a lone `true` back as a bool and unpacking it
# fails in a way that reads like the addon broke rather than the test.
REFRESH = lua.eval("""
    function(bar)
        local ok, err = pcall(function() bar:Refresh() end)

        return ok, tostring(err)
    end
""")

built, bar = lua.eval("""
    function()
        local ok, result = pcall(MakeBar)

        return ok, result
    end
""")()

check("the filter bar builds at all", built is True, bar)

if not built:
    print("")
    print("FAILURES: " + str(failures))
    sys.exit(1)

# --- the call a tab switch makes ------------------------------------------
#
# This is the whole point of the file. UI/MainWindow.lua SetMode calls it on
# every tab click, before UpdateRows -- so anything that throws here stops the
# window changing tabs at all.
ok, err = REFRESH(bar)

check("Refresh survives, which is what every tab click goes through",
      ok is True, err)

# Twice, because the first call can pass on a half-built bar and the second
# is the one that runs against whatever the first left behind.
ok, err = REFRESH(bar)

check("and again on the next tab switch", ok is True, err)

# --- Clear, which touches the same two inputs -----------------------------
source = (Path(__file__).resolve().parent.parent
          / "UI" / "FilterBar.lua").read_text(encoding="utf-8")

check("Clear still empties the date boxes rather than the buttons",
      "fromInput.editBox:SetText" in source
      and "toInput.editBox:SetText" in source,
      "Clear reaching a Button instead of its edit box is the same bug")

check("and the field hands back the input as well as its button",
      "return input, input.calendar" in source,
      "returning only the button is what broke every tab")

check("while the To field anchors after that button, not the box",
      'CreateDateField(\n        bar, "To", state, "dateTo", true, onChange, '
      'fromCalendar\n    )' in source,
      "anchoring To to the box puts its label on top of the button")

# --- the picker itself ----------------------------------------------------
check("the picker writes a date the boxes can parse",
      SYL.DatePicker.Format(2026, 9, 8) == "09-08-2026",
      SYL.DatePicker.Format(2026, 9, 8))

year, month = SYL.DatePicker.MonthFor("09-08-2026")

check("and opens on the month already in the box",
      year == 2026 and month == 9, (year, month))

year, month = SYL.DatePicker.MonthFor("")

now = lua.eval("function() return date('*t') end")()

check("or on this month when the box is empty",
      year == now.year and month == now.month, (year, month))

check("rubbish in the box does not throw",
      SYL.DatePicker.MonthFor("not a date") is not None)

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
