"""The keystone wire format, which parses input from other people's machines.

Everything decoded here arrived over an addon channel from a client this one
does not control, so every field is checked before it reaches a comparator or
a display string. The cases below are the ones a hostile or simply older
client can produce: a version that is not ours, a truncated line, a level that
is not a number, and the "no key" case that has to travel as a real message
rather than as silence.

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
lua.execute("function time() return 1700000000 end")
lua.execute("function IsInGuild() return true end")
lua.execute("function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end } end")

lua.execute((CORE / "KeystoneSync.lua").read_text(encoding="utf-8"))

sync = lua.globals().ShowUsYourLoot.KeystoneSync
failures = []


def check(label, ok):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def decode(payload):
    result = sync.Decode(payload)

    return result if isinstance(result, tuple) else (result,)


# --- round trip -----------------------------------------------------------
encoded = sync.Encode(375, 12, "MAGE")
check("a key encodes to one short line", encoded == "1|K|375|12|MAGE")

kind, map_id, level, klass = decode(encoded)
check("and decodes back", (kind, map_id, level, klass) == ("K", 375, 12, "MAGE"))

# --- no key ---------------------------------------------------------------
# Has to travel as a message: silence is indistinguishable from not running
# the addon, and last week's key would stand forever.
kind, map_id, level, klass = decode(sync.Encode(None, None, "PRIEST"))
check("no key still sends", kind == "K")
check("and arrives as no key rather than as a zero", map_id is None and level is None)

# --- requests -------------------------------------------------------------
check("a request decodes", decode("1|?|")[0] == "?")

# --- input that must not get through --------------------------------------
REJECTED = [
    ("a future version", "2|K|375|12|MAGE"),
    ("no version", "K|375|12|MAGE"),
    ("a truncated line", "1|K|375"),
    ("a level that is not a number", "1|K|375|twelve|MAGE"),
    ("a map id that is not a number", "1|K|abc|12|MAGE"),
    ("an empty string", ""),
    ("an unknown kind", "1|Z|375|12|MAGE"),
]

for label, payload in REJECTED:
    check("refused: " + label, decode(payload)[0] is None)

check("refused: a non-string", decode(None)[0] is None)

# --- storage and staleness ------------------------------------------------
sync.Remember("Aimee-Silvermoon", 375, 12, "MAGE")
sync.Remember("Someone-Else", 375, 20, "PRIEST")

listed = list(sync.List().values())
check("both are remembered", len(listed) == 2)
check("highest key sorts first", listed[0].level == 20)

# A key is worthless after the reset, and a stale one makes the list lie.
lua.execute(
    "ShowUsYourLootDB.guildKeystones['Someone-Else'].at = 1700000000 - (8 * 24 * 60 * 60)"
)

listed = list(sync.List().values())
check("a key older than a week is dropped", len(listed) == 1)
check(
    "and dropped from the store, not just the list",
    lua.globals().ShowUsYourLootDB.guildKeystones["Someone-Else"] is None,
)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
