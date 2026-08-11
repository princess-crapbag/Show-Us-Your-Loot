"""Saved-variable migrations, against every state a real install can be in.

A migration writes to somebody's saved settings once and is then invisible —
if it is wrong, the wrong value is what they keep. So each one is checked
against all of: a fresh install, an upgrade that needs it, an upgrade that
does not, and an install that already ran it and has since been changed back
by hand. That last case is the one worth having: a migration that fires twice
would overrule a decision the user made after it ran.

Every default-flip migration has the same shape and the same four ways to be
wrong, so they share one table of cases parametrised by their own boundary
version. Adding the next one is a row in MIGRATIONS, not another file.

Runs the shipped functions out of Core/Migrations.lua rather than a copy of
them. DATABASE_VERSION still comes from Core/Database.lua, which owns it.
Needs `lupa` — see tools/test_lootmessages.py for the setup.

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

CORE = Path(__file__).resolve().parent.parent / "Core"

version = re.search(
    r"local DATABASE_VERSION = (\d+)",
    (CORE / "Database.lua").read_text(encoding="utf-8"),
).group(1)

lua = LuaRuntime(unpack_returned_tuples=True)

# The whole file, not a slice of it: it declares its own table and nothing in
# it needs the game. SYL is stubbed because the addon table is built in
# Main.lua, which is not what is under test here.
lua.execute("ShowUsYourLoot = {}")
lua.execute((CORE / "Migrations.lua").read_text(encoding="utf-8"))

# name, setting it flips, the version at which it was introduced.
#
# `boundary` is the number the migration guards against, NOT DATABASE_VERSION.
# Written the second way a migration re-fires on every later bump and takes
# away a setting the user turned back on; the last case below is what catches
# that, and it only catches it while there IS a later version to test with.
MIGRATIONS = [
    ("MigrateAnnounceDefault", "announceCaptures", 6),
]

failures = []

for name, setting, boundary in MIGRATIONS:
    migrate = lua.globals().ShowUsYourLoot.Migrations[name]

    if migrate is None:
        print(f"FAIL {name} — not found in Core/Migrations.lua")
        failures.append(name)
        continue

    before = boundary - 1

    cases = [
        # label, stored databaseVersion, saved value,
        #        expect migrated?, expect value after
        ("fresh install (no stored version)", None, False, False, False),
        (f"upgrade from v{before}, setting on", before, True, True, False),
        (f"upgrade from v{before}, setting already off", before, False, False, False),
        ("already migrated, user turned it back on", boundary, True, False, True),
        ("already migrated, left off", boundary, False, False, False),
        (
            "a later version bump does not re-fire it",
            boundary + 1,
            True,
            False,
            True,
        ),
    ]

    print(f"{name} — {setting}")

    for label, stored, saved, want_migrated, want_after in cases:
        lua.execute("ShowUsYourLootDB = { settings = {} }")
        lua.globals().ShowUsYourLootDB.settings[setting] = saved

        got_migrated = bool(migrate(stored))
        got_after = bool(lua.globals().ShowUsYourLootDB.settings[setting])

        ok = (got_migrated == want_migrated) and (got_after == want_after)
        print(("  ok   " if ok else "  FAIL ") + label)

        if not ok:
            print(f"         migrated: got {got_migrated}, wanted {want_migrated}")
            print(f"         setting:  got {got_after}, wanted {want_after}")
            failures.append(f"{name}: {label}")

    print()

# ---------------------------------------------------------------------------
# BackfillRecordIDs — not version guarded, so it is checked by behavior
# rather than by boundary: a record with no id cannot be ticked by anything.
# ---------------------------------------------------------------------------

backfill = lua.globals().ShowUsYourLoot.Migrations.BackfillRecordIDs

lua.execute(
    """
    Fixture = {
        activeSeason = {
            id = 'season-1',
            loot = {
                { timestamp = 100 },
                { timestamp = 100 },
                { id = 'kept', timestamp = 100 },
            },
            drops = { { timestamp = 200 } },
        },
        archives = {
            { id = 'season-0', loot = { { timestamp = 50 } }, drops = {} },
        },
    }
    """
)

fixture = lua.globals().Fixture
assigned = backfill(fixture)

season = fixture.activeSeason
ids = [season.loot[i].id for i in (1, 2, 3)]

checks = [
    ("assigns one id per record missing one", assigned == 4),
    ("leaves an existing id alone", ids[2] == "kept"),
    ("every record now has an id", all(ids)),
    # Two records identical in every field must not collide, or ticking one
    # ticks the other.
    ("identical records get distinct ids", ids[0] != ids[1]),
    ("drops are covered too", season.drops[1].id is not None),
    ("archived seasons are covered too", fixture.archives[1].loot[1].id is not None),
    ("a second run assigns nothing", backfill(fixture) == 0),
]

print("BackfillRecordIDs")

for label, ok in checks:
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        failures.append(f"BackfillRecordIDs: {label}")

print()
# A migration guarding against a boundary above the current version would
# never run at all, which is silent and total. Cheap to rule out here.
for name, _setting, boundary in MIGRATIONS:
    if boundary > int(version):
        print(f"FAIL {name} guards v{boundary}, above DATABASE_VERSION {version}")
        failures.append(f"{name}: boundary above DATABASE_VERSION")

print("DATABASE_VERSION =", version)
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
