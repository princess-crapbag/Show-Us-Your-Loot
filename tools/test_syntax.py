"""Every Lua file listed in the .toc parses.

The cheapest possible test and the one with the widest reach: a syntax error
in any of these is a file the game silently refuses to load, and the addon
then fails somewhere else entirely — a nil index in a window that never got
its module, three files away from the typo.

It also catches the .toc drifting from the tree, which is its own silent
failure: a file added but not listed simply never runs, and a file listed but
missing produces one line in the game's own error log that nobody reads.

Not a substitute for loading the addon. Parsing proves the syntax, never that
a function still exists or is still called — a block deleted cleanly parses
perfectly. Needs `lupa`; see tools/test_lootmessages.py for the setup.

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

ROOT = Path(__file__).resolve().parent.parent

lua = LuaRuntime()

# load() rather than loadstring(): lupa bundles a newer Lua than the game
# runs. The two agree on everything this addon's syntax uses, and the point
# here is to catch a stray `end`, not to certify 5.1 compatibility.
compiles = lua.eval(
    """
    function(source, name)
        local chunk, err = load(source, name)

        if chunk then
            return true, ''
        end

        return false, err
    end
    """
)

listed = [
    line.strip()
    for line in (ROOT / "ShowUsYourLoot.toc").read_text(encoding="utf-8").splitlines()
    if line.strip().lower().endswith(".lua")
]

failures = []

for entry in listed:
    path = ROOT / entry.replace("\\", "/")

    if not path.exists():
        print(f"FAIL {entry} — listed in the .toc but not on disk")
        failures.append(entry)
        continue

    ok, err = compiles(path.read_text(encoding="utf-8"), entry)

    if not ok:
        print(f"FAIL {entry}\n       {err}")
        failures.append(entry)

# The other direction: on disk, loaded by nothing.
listed_paths = {(ROOT / e.replace("\\", "/")).resolve() for e in listed}

for path in sorted(list(ROOT.glob("*.lua")) + list(ROOT.glob("Core/*.lua"))
                   + list(ROOT.glob("UI/*.lua"))):
    if path.resolve() not in listed_paths:
        rel = path.relative_to(ROOT)
        print(f"FAIL {rel} — on disk but not listed in the .toc, so it never loads")
        failures.append(str(rel))

print()
print(f"parsed {len(listed)} files listed in the .toc")
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
