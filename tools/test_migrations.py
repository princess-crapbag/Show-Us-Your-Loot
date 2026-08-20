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

# DedupeSyncedDrops asks whether two records are the same drop, and
# Core/DropIdentity.lua answers. It has no dependencies of its own —
# that is why it is a separate file rather than part of the store.
lua.execute((CORE / "DropIdentity.lua").read_text(encoding="utf-8"))

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
# MigrateAudienceScope — a string setting, so it cannot ride the table above,
# which reads every value through bool(). Checked by behavior instead: only
# "everyone" moves, only once, and a scope inside the rotation is left alone.
# ---------------------------------------------------------------------------

scope_migrate = lua.globals().ShowUsYourLoot.Migrations.MigrateAudienceScope

if scope_migrate is None:
    print("FAIL MigrateAudienceScope — not found in Core/Migrations.lua")
    failures.append("MigrateAudienceScope")
else:
    print("MigrateAudienceScope — audienceScope")

    # label, stored version, saved scope, expect migrated?, expect scope after
    scope_cases = [
        ("fresh install", None, None, False, None),
        ("upgrade from v6 parked on everyone", 6, "everyone", True, "team"),
        ("upgrade from v6 on guild is left alone", 6, "guild", False, "guild"),
        ("upgrade from v6 on team is left alone", 6, "team", False, "team"),
        ("upgrade from v6 with nothing saved", 6, None, False, None),
        ("already migrated", 7, "everyone", False, "everyone"),
        ("a later bump does not re-fire it", 8, "everyone", False, "everyone"),
    ]

    for label, stored, saved, want_migrated, want_after in scope_cases:
        lua.execute("ShowUsYourLootDB = { settings = {} }")

        if saved is not None:
            lua.globals().ShowUsYourLootDB.settings.audienceScope = saved

        got_migrated = bool(scope_migrate(stored))
        got_after = lua.globals().ShowUsYourLootDB.settings.audienceScope

        ok = (got_migrated == want_migrated) and (got_after == want_after)
        print(("  ok   " if ok else "  FAIL ") + label)

        if not ok:
            print(f"         migrated: got {got_migrated}, wanted {want_migrated}")
            print(f"         scope:    got {got_after!r}, wanted {want_after!r}")
            failures.append(f"MigrateAudienceScope: {label}")

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

# ---------------------------------------------------------------------------
# DedupeSyncedDrops — also unguarded, and the only repair here that DELETES.
#
# THE BUG IT EXISTS FOR, from Aimee's live data. A record id begins with the
# local session's start timestamp, and two people in the same raid start
# theirs a second or two apart. Core/Sync.lua deduped on the id alone, so
# every drop a guildmate broadcast was stored again under the sender's own id
# — eleven duplicates from one night, every one crediting the master looter,
# and none of them reachable by a correction made on the original. Her board
# read 560 where it should have read 200.
# ---------------------------------------------------------------------------

dedupe = lua.globals().ShowUsYourLoot.Migrations.DedupeSyncedDrops

lua.execute(
    """
    -- The real shape: same encounter, same loot index, same winner, same
    -- roll, two seconds apart, one captured here and one received.
    DupeFixture = {
        activeSeason = {
            id = 'season-1',
            drops = {
                {
                    id = '1787100146-3470-1', source = 'LOOT_HISTORY',
                    encounterID = 3470, lootListID = 1,
                    winnerGUID = 'P1', winnerRoll = 51, winnerState = 2,
                    timestamp = 1787100619, itemName = 'Hexing Spiritrender',
                },
                {
                    id = '1787100144-3470-1', source = 'SYNC',
                    encounterID = 3470,
                    winnerGUID = 'P1', winnerRoll = 51, winnerState = 2,
                    timestamp = 1787100617,
                },
                -- Same boss and loot index, different winner: a real second
                -- drop, not a copy.
                {
                    id = '1787100146-3470-2', source = 'LOOT_HISTORY',
                    encounterID = 3470, lootListID = 2,
                    winnerGUID = 'P2', winnerRoll = 53,
                    timestamp = 1787100619,
                },
                -- Same everything but a week later: the same boss pulled
                -- again reuses lootListID, so only the window tells them
                -- apart.
                {
                    id = '1787700146-3470-1', source = 'SYNC',
                    encounterID = 3470,
                    winnerGUID = 'P1', winnerRoll = 51,
                    timestamp = 1787100619 + 604800,
                },
                -- Received from two guildmates and never seen locally.
                -- Nothing here is richer than anything else, so both stay.
                {
                    id = '1000-99-1', source = 'SYNC', encounterID = 99,
                    winnerGUID = 'P3', winnerRoll = 7, timestamp = 500,
                },
                {
                    id = '1002-99-1', source = 'SYNC', encounterID = 99,
                    winnerGUID = 'P3', winnerRoll = 7, timestamp = 502,
                },
            },
        },
        archives = {
            {
                id = 'season-0',
                drops = {
                    {
                        id = '900-1-1', source = 'LOOT_HISTORY',
                        encounterID = 1, lootListID = 1,
                        winnerGUID = 'P9', winnerRoll = 4, timestamp = 900,
                    },
                    {
                        id = '898-1-1', source = 'SYNC', encounterID = 1,
                        winnerGUID = 'P9', winnerRoll = 4, timestamp = 898,
                    },
                },
            },
        },
    }

    -- Held before the run, to prove the stored table is rewritten in place
    -- rather than replaced. SYL.GetActiveDrops hands this table out by
    -- reference all over the addon.
    HeldDrops = DupeFixture.activeSeason.drops
    """
)

dupes = lua.globals().DupeFixture
held = lua.globals().HeldDrops

removed = dedupe(dupes)

season_drops = dupes.activeSeason.drops
ids = [season_drops[i].id for i in range(1, len(season_drops) + 1)]

checks = [
    ("removes the synced copy of a locally captured drop", removed == 2),
    ("the local record is the one kept", "1787100146-3470-1" in ids),
    ("the synced copy is gone", "1787100144-3470-1" not in ids),
    ("a different winner on the same boss is not a duplicate",
     "1787100146-3470-2" in ids),
    ("the same loot index a week later is not a duplicate",
     "1787700146-3470-1" in ids),
    # Deleting half of something this client never saw for itself is not a
    # repair, so both survive.
    ("two synced copies with no local original are both left alone",
     "1000-99-1" in ids and "1002-99-1" in ids),
    ("archived seasons are covered too",
     len(dupes.archives[1].drops) == 1),
    ("the stored table is rewritten in place, not replaced",
     len(held) == len(season_drops) and held[1].id == season_drops[1].id),
    ("a second run removes nothing", dedupe(dupes) == 0),
]

print("DedupeSyncedDrops")

for label, ok in checks:
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        failures.append(f"DedupeSyncedDrops: {label}")

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
