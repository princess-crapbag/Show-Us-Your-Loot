"""LootFeed.Sort: order, reversal, and not raising on ties.

The last case earns its keep. Lua's table.sort raises "invalid order
function" when a comparator reports two elements as equal inconsistently, and
a season of loot sorted by four-letter type labels is almost entirely ties —
so the tie-break is not tidiness, it is what stops the list throwing the
moment somebody clicks TYPE.

Needs `lupa`; see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
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

ADDON = Path(__file__).resolve().parent.parent / "Core" / "LootFeed.lua"
source = ADDON.read_text(encoding="utf-8")

start = source.index("local function Text(value)")
end = source.index("function LootFeed.ToDetailRecord")
block = source[start:end]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("LootFeed = {}\n" + block.replace("LootFeed.", "LootFeed."))
LootFeed = lua.globals().LootFeed

def build(rows):
    lua.execute("entries = {}")
    entries = lua.globals().entries
    for i, (player, item, where, label, ts) in enumerate(rows, 1):
        lua.execute(
            f'entries[{i}] = {{ player = "{player}", itemName = "{item}", '
            f'where = "{where}", typeLabel = "{label}", timestamp = {ts}, '
            f'sortID = "id{i:03d}" }}'
        )
    return entries

def order(entries, field="player"):
    return [entries[i][field] for i in range(1, len(entries) + 1)]

ROWS = [
    ("Aimee",  "Dawn Crystal", "Manaforge", "Need",   300),
    ("Thrall", "Dawn Crystal", "Manaforge", "Need",   100),
    ("Zoe",    "Ashen Ring",   "Delve",     "Mog",    200),
    ("aimee",  "Boots",        "Manaforge", "Need",   200),
    ("Bob",    "Ashen Ring",   "Manaforge", "Greed",  400),
]

failures = []

def check(label, got, want):
    ok = got == want
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        print(f"       got  {got}")
        print(f"       want {want}")
        failures.append(label)

# Default: newest first.
e = build(ROWS)
LootFeed.Sort(e, "date", False)
check("date, newest first", order(e), ["Bob", "Aimee", "Zoe", "aimee", "Thrall"])

e = build(ROWS)
LootFeed.Sort(e, "date", True)
check("date reversed, oldest first", order(e),
      ["Thrall", "Zoe", "aimee", "Aimee", "Bob"])

# Player, case-insensitive.
e = build(ROWS)
LootFeed.Sort(e, "player", False)
check("player ascending, case-insensitive", order(e),
      ["Aimee", "aimee", "Bob", "Thrall", "Zoe"])

e = build(ROWS)
LootFeed.Sort(e, "player", True)
check("player reversed", order(e),
      ["Zoe", "Thrall", "Bob", "Aimee", "aimee"])

# Heavy ties: every row the same location. Must not throw, must fall back to
# newest-first within the tie.
e = build(ROWS)
LootFeed.Sort(e, "location", False)
check("location, ties fall back to newest first", order(e),
      ["Zoe", "Bob", "Aimee", "aimee", "Thrall"])

# An unknown key falls back to date rather than erroring.
e = build(ROWS)
LootFeed.Sort(e, "nonsense", False)
check("unknown sort key falls back to date", order(e),
      ["Bob", "Aimee", "Zoe", "aimee", "Thrall"])

# Every row identical except the id: the case that makes table.sort raise
# "invalid order function" if the comparator is not a strict weak order.
same = [("Same", "Same", "Same", "Same", 1)] * 60
e = build(same)
try:
    LootFeed.Sort(e, "wintype", False)
    print("ok   sixty identical rows did not raise")
except Exception as exc:
    print(f"FAIL sixty identical rows raised: {exc}")
    failures.append("identical rows")

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
