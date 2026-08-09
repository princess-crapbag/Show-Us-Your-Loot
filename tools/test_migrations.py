"""Saved-variable migrations, against every state a real install can be in.

A migration writes to somebody's saved settings once and is then invisible —
if it is wrong, the wrong value is what they keep. So each one is checked
against all of: a fresh install, an upgrade that needs it, an upgrade that
does not, and an install that already ran it and has since been changed back
by hand. That last case is the one worth having: a migration that fires twice
would overrule a decision the user made after it ran.

Lifted out of Core/Database.lua so this runs the shipped function. Needs
`lupa` — see tools/test_lootmessages.py for the setup.

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

ADDON = Path(__file__).resolve().parent.parent / "Core" / "Database.lua"
source = ADDON.read_text(encoding="utf-8")

version = re.search(r"local DATABASE_VERSION = (\d+)", source).group(1)

start = source.index("local function MigrateSettings(storedVersion)")
end = source.index("local function MigrateOldLootDatabase()")
block = source[start:end]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    f"local DATABASE_VERSION = {version}\n"
    + block.replace("local function MigrateSettings", "function MigrateSettings", 1)
)
migrate = lua.globals().MigrateSettings

CASES = [
    # label, stored databaseVersion, saved countPersonalLoot,
    #        expect migrated?, expect setting after
    ("fresh install (no stored version)", None, False, False, False),
    ("upgrade from 0.1.0-alpha, setting on", 3, True, True, False),
    ("upgrade from 0.1.0-alpha, setting already off", 3, False, False, False),
    ("already migrated, user turned it back on", 4, True, False, True),
    ("already migrated, left off", 4, False, False, False),

    # A later, unrelated schema bump must not re-run this migration. Written
    # against DATABASE_VERSION rather than its own boundary, it did.
    ("a later version bump does not re-fire it", 5, True, False, True),
]

failures = []

for label, stored, saved, want_migrated, want_after in CASES:
    lua.execute("ShowUsYourLootDB = { settings = {} }")
    lua.globals().ShowUsYourLootDB.settings.countPersonalLoot = saved

    got_migrated = bool(migrate(stored))
    got_after = bool(lua.globals().ShowUsYourLootDB.settings.countPersonalLoot)

    ok = (got_migrated == want_migrated) and (got_after == want_after)
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        print(f"       migrated: got {got_migrated}, wanted {want_migrated}")
        print(f"       setting:  got {got_after}, wanted {want_after}")
        failures.append(label)

print()
print("DATABASE_VERSION =", version)
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
