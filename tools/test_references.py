"""Every SYL.Module.Member call resolves to something that exists.

Lua finds out at the moment of the call, and only if the call happens. A
window that is opened rarely can carry a call to a function that was renamed
weeks ago and say nothing until somebody opens it — by which point the error
names a line, not the rename that caused it.

The specific accident this is for: splitting a file. Moving rows out of a
window into a module of its own means every call site has to move with them,
and the one that gets missed is always in a branch that does not run on the
happy path. UI/DueRows.lua and UI/PlayerRows.lua were both carved out that
way, and Core/Migrations.lua out of Core/Database.lua.

Static, so it cannot catch a member built at runtime, and it deliberately
ignores any `SYL.Foo` whose table it did not find being assigned — silence
about something unknown beats noise about something fine. What it does catch
is the call that was left pointing at the old name.

Comment and string stripping is imported from syl_check rather than
reimplemented, so `SYL.Thing.Name` written inside a comment is not read as a
call, and there is one copy of that logic rather than two.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from syl_check import strip_code  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

listed = [
    line.strip()
    for line in (ROOT / "ShowUsYourLoot.toc").read_text(encoding="utf-8").splitlines()
    if line.strip().lower().endswith(".lua")
]

code = {
    entry: strip_code((ROOT / entry.replace("\\", "/")).read_text(encoding="utf-8"))
    for entry in listed
}

everything = "\n".join(code.values())

# `SYL.Audience = Audience` — the public name and the local table behind it.
# Only this shape counts: it is how every module in this addon publishes
# itself, and anything else is not a module table.
exposed = dict(re.findall(r"\bSYL\.(\w+)\s*=\s*(\w+)\s*$", everything, re.MULTILINE))

# `function Audience.Filter(` and `Audience.SCOPES = {` both define a member.
defined = defaultdict(set)

for match in re.finditer(
    r"^\s*function\s+(\w+)[.:](\w+)\s*\(", everything, re.MULTILINE
):
    defined[match.group(1)].add(match.group(2))

for match in re.finditer(r"^\s*(\w+)\.(\w+)\s*=", everything, re.MULTILINE):
    defined[match.group(1)].add(match.group(2))

failures = []

for entry, text in code.items():
    for match in re.finditer(r"\bSYL\.(\w+)\.(\w+)", text):
        module, member = match.group(1), match.group(2)
        local = exposed.get(module)

        # Not a module table this understands. Say nothing.
        if local is None:
            continue

        if member in defined[local] or member in defined[module]:
            continue

        line = text[: match.start()].count("\n") + 1

        print(f"FAIL {entry}:{line} — SYL.{module}.{member} is never defined")
        failures.append(f"{entry}:{line} SYL.{module}.{member}")

print()
print(f"checked {len(listed)} files, {len(exposed)} module tables")
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
