"""The scope checker finds a local used too early, and nothing else.

tools/syl_scope.py exists because three of these have shipped and no check here
could see any of them. The two halves of it matter equally:

  FINDS THE REAL ONES. Both faults that actually shipped are in here as
  fixtures — `container.heading` above `local container`, and a closure calling
  `HideTarget` before the `local function` that defines it. If either stops
  being reported the tool has no reason to exist.

  AND CRIES WOLF AT NOTHING. The first draft reported ten findings on a clean
  codebase: parameters, loop variables and `if` branches were not scopes yet,
  and a field name looked like a variable. All ten were noise. A checker that
  is usually wrong trains you to skim its output, which is worse than not
  having one — so every legal shape that was mistaken for a bug is a fixture
  too, and they are the majority of this file.

Needs `luaparser`, which is a dev dependency:

    python -m pip install luaparser

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import syl_scope  # noqa: E402

if not syl_scope.AVAILABLE:
    sys.exit(
        "luaparser is not installed — python -m pip install luaparser. "
        "It is a dev dependency and the addon does not use it."
    )

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def findings(source):
    return syl_scope.check_source(source, "fixture.lua")


# --- the two that shipped --------------------------------------------------

CONTAINER = """
local function AddSection(parent, title, offsetY)
    local heading = Theme.CreateText(parent)

    container.heading = heading

    local container = CreateFrame("Frame", nil, parent)

    return container
end
"""

found = findings(CONTAINER)

check("the settings crash is found", len(found) == 1, found)
check(
    "and it names the right local",
    found and found[0][2] == "container",
    found,
)
check(
    "and points at the use, not the declaration",
    found and found[0][1] < found[0][3],
    found,
)

# A closure captures what is in scope when it is CREATED. This one is made
# above the local, so it captured the global — nil — and threw at the call,
# somewhere else entirely.
CLOSURE = """
local function Apply()
    HideTarget()
end

local function HideTarget()
    return 1
end
"""

check("a closure over a later local is found", len(findings(CLOSURE)) == 1, findings(CLOSURE))

ANON = """
local handlers = { onClick = function() return Later end }

local Later = 1
"""

check("so is an anonymous one", len(findings(ANON)) == 1, findings(ANON))

# --- everything legal that used to be reported -----------------------------

LEGAL = [
    (
        "a declaration does not use itself",
        "local function A(p)\n    local c = {}\n    c.h = 1\n    return c\nend\n",
    ),
    (
        "recursion",
        "local function C(n)\n    if n > 0 then return C(n - 1) end\n    return 0\nend\n",
    ),
    (
        "a forward declaration assigned later",
        "local Refresh\n\nlocal function B()\n    Refresh()\nend\n\n"
        "Refresh = function() return 1 end\n",
    ),
    (
        "a parameter that shares a name with a later local",
        "local function F(drops)\n    return #drops\nend\n\nlocal drops = {}\n",
    ),
    (
        "a generic for variable",
        "for _, x in ipairs(t) do print(x) end\n\nlocal x = 1\n",
    ),
    (
        "a numeric for variable",
        "for i = 1, 5 do print(i) end\n\nlocal i = 1\n",
    ),
    (
        "locals in both branches of an if",
        "local function G(n)\n    if n then\n        local a = 1\n        return a\n"
        "    else\n        local a = 2\n        return a\n    end\nend\n",
    ),
    (
        "a field name is not a variable",
        "local function F(roll)\n    return roll.guid\nend\n\nlocal guid = 1\n",
    ),
    (
        "a table key is not a variable",
        "local s = { drops = {} }\n\nlocal drops = 1\n",
    ),
    (
        "local x = x means the outer x",
        "local time = time\n\nreturn time\n",
    ),
    (
        "a do block has its own scope",
        "do local a = 1 print(a) end\n\nlocal a = 2\n",
    ),
    (
        "a while body has its own scope",
        "while true do local a = 1 print(a) end\n\nlocal a = 2\n",
    ),
]

for label, source in LEGAL:
    got = findings(source)

    check(f"clean: {label}", got == [], got)

# --- the bracket forms, which ARE reads ------------------------------------
#
# t[k] reads k, and { [k] = 1 } reads k. Only the dotted forms name a field,
# and getting that backwards would blind the checker to a real class of bug.
check(
    "a bracket index is a read",
    len(findings("local function F(t)\n    return t[k]\nend\n\nlocal k = 1\n")) == 1,
)
check(
    "a bracket table key is a read",
    len(findings("local s = { [k] = 1 }\n\nlocal k = 2\n")) == 1,
)

# --- the addon itself ------------------------------------------------------
#
# Zero, and it has to stay zero: this is the check that runs on every commit,
# and one accepted false positive is the end of anybody reading its output.
root = Path(__file__).resolve().parent.parent
toc = (root / "ShowUsYourLoot.toc").read_text(encoding="utf-8")

shipped = []

for line in toc.splitlines():
    name = line.strip().replace("\\", "/")

    if not name.lower().endswith(".lua"):
        continue

    path = root / name

    if not path.exists():
        continue

    found = syl_scope.check_source(path.read_text(encoding="utf-8"), name)

    check(f"{name} parses", found is not None)

    shipped.extend(found or [])

check("the addon has none of these", shipped == [], shipped)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
