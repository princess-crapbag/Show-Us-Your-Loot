# -*- coding: utf-8 -*-
"""Read a real ShowUsYourLoot.lua saved-variables file and say what is in it.

WHAT THIS IS FOR. Two people running the same addon see different boards, and
neither screen can say why -- a transfer that did not arrive looks exactly
like a transfer that arrived empty, and a drop that never landed looks like
nothing at all, because nothing counts what should have been there.

The file answers it. `source = "SYNC_HISTORY"` is stamped on every record that
arrived over a bulk transfer and on no record a client watched itself, so one
number settles whether the send worked.

    python tools/inspect_database.py "<path to ShowUsYourLoot.lua>"

The path is usually:

    World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/
        ShowUsYourLoot.lua

WoW only writes that file on logout or /reload, so a file pulled while the
game is running is as old as the last one of those.

Reads only. Needs `lupa`, like the test suites.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import io
import sys
from collections import Counter

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is not installed - see tools/test_lootmessages.py.")


def rows(table):
    """A Lua array as a Python list, or [] for nil."""
    if table is None:
        return []

    return [table[i] for i in range(1, len(table) + 1)]


def line(label, value):
    print("  %-32s %s" % (label, value))


def main(path):
    lua = LuaRuntime(unpack_returned_tuples=True)

    # The file is one big assignment, and nothing else. Loading it is how the
    # game loads it.
    lua.execute(io.open(path, encoding="utf-8", errors="replace").read())

    db = lua.globals().ShowUsYourLootDB

    if db is None:
        sys.exit("no ShowUsYourLootDB in that file -- wrong file, or the "
                 "addon has never saved.")

    print("")
    print("THE INSTALL")
    # NOT the addon's release number -- the file does not carry one. These are
    # the two schema counters, and they are still worth reading: a database
    # version behind this repo's means the migrations have not run there yet.
    line("saved-variables schema", db.version or "?")
    line("database version", db.databaseVersion or "?")

    features = db.features
    if features:
        off = [k for k in features.keys() if not features[k]]
        line("features switched off", ", ".join(sorted(off)) or "none")

    season = db.activeSeason
    if season is None:
        print("\n  no active season -- nothing to compare.")
        return

    drops = rows(season["drops"])

    print("")
    print("THE ACTIVE SEASON")
    line("name", season["name"])
    line("id", season["id"])
    line("drops", len(drops))

    # THE ONE THAT ANSWERS THE QUESTION.
    arrived = [d for d in drops
               if str(d["source"] or "") == "SYNC_HISTORY"]
    credited = [d for d in drops if d["creditOverride"]]

    line("drops that ARRIVED in a transfer", len(arrived))
    line("drops this client watched itself", len(drops) - len(arrived))
    line("drops carrying a credit override", len(credited))

    if drops and not arrived:
        print("")
        print("  >> No drop in this season came from a transfer. Either one "
              "has never")
        print("     been accepted here, or it did not arrive.")

    # Who the board thinks won things. A receiver missing the credit overrides
    # shows every item on the master looter's name, which is the symptom that
    # started this.
    winners = Counter(str(d["winnerName"] or "?") for d in drops)

    print("")
    print("WHO THE BOARD CREDITS (top 8, before overrides)")
    for name, count in winners.most_common(8):
        line(name, count)

    # The season's raids, NOT db.encounterRuns -- that one is keyed by
    # encounter id and holds pull counts, not evenings. Getting this wrong
    # reported nought sessions for an account with eighteen.
    raids = rows(season["raids"])
    nights = {str(r["dateText"] or "") for r in raids if r["dateText"]}

    print("")
    print("RAID NIGHTS")
    line("raid sessions recorded", len(raids))
    line("distinct dates", len(nights))
    if nights:
        line("earliest", min(nights))
        line("latest", max(nights))
        line("dates", ", ".join(sorted(nights)))

    shared = db.sharedRoster

    print("")
    print("SHARED ROSTER")
    if shared is None:
        line("held", "none")
    else:
        members = shared["members"]
        line("from", shared["source"] or "?")
        line("accepted from", shared["acceptedFrom"] or "not accepted")
        line("names held", len(list(members.keys())) if members else 0)

    receipts = db.rosterReceipts
    count = len(list(receipts.keys())) if receipts else 0

    line("people known to hold YOUR roster", count)
    print("")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)

    main(sys.argv[1])
