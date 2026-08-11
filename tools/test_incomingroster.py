"""Recruits who are not in the guild yet, against the shipped IncomingRoster.

These are the only records in the addon keyed by name rather than by GUID,
because a character on another realm who has not transferred has no GUID the
client has ever seen. That makes two things worth pinning down: what counts as
a valid identity, and what happens the moment they do join and a real record
appears alongside the placeholder.

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

# The guild is empty unless a test says otherwise; Guilded holds the short
# names the client can currently see.
lua.execute(
    """
    Guilded = {}

    ShowUsYourLoot.Guild = {
        FindByShortName = function(name)
            return Guilded[name]
        end,
    }

    Registry = {}

    ShowUsYourLoot.Players = {
        Get = function(key) return Registry[key] end,
    }
    """
)

lua.execute((CORE / "IncomingRoster.lua").read_text(encoding="utf-8"))

incoming = lua.globals().ShowUsYourLoot.IncomingRoster
failures = []


def check(label, ok):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def reset():
    lua.execute("ShowUsYourLootDB = {} Guilded = {} Registry = {}")


# --- identity -------------------------------------------------------------
reset()

# Key returns the key plus the split name and realm, so take the first.
def key_of(text):
    result = incoming.Key(text)

    return result[0] if isinstance(result, tuple) else result


check("Name-Realm parses", key_of("Aimee-Silvermoon") == "aimee-silvermoon")
check("case is folded", key_of("AIMEE-Silvermoon") == "aimee-silvermoon")
check("the name and realm come back split", incoming.Key("Aimee-Silvermoon")[1:] == ("Aimee", "Silvermoon"))
check(
    "a realm written with spaces matches one without",
    key_of("Aimee-Argent Dawn") == key_of("Aimee-ArgentDawn"),
)
# A bare name is ambiguous across realms, and this exists precisely for
# characters who are not on yours.
check("a bare name is refused", key_of("Aimee") is None)
check("an empty realm is refused", key_of("Aimee-") is None)

# --- adding ---------------------------------------------------------------
reset()

entry, message = incoming.Add("Aimee-Silvermoon", "mage")
check("a valid recruit is added", entry is not None and entry["class"] == "MAGE")
check("the class is upper-cased for the color and buff tables", entry["class"] == "MAGE")

entry, message = incoming.Add("Aimee-Silvermoon", "wizard")
check("an invented class is refused", entry is None)

entry, message = incoming.Add("Aimee", "mage")
check("a bare name is refused when adding", entry is None)

# Somebody already in the guild is already on the roster; adding them again
# would draw them twice.
reset()
lua.execute("Guilded['Aimee'] = { guid = 'G1', name = 'Aimee' }")
entry, message = incoming.Add("Aimee-Silvermoon", "mage")
check("an existing guild member is refused", entry is None)

# --- editing --------------------------------------------------------------
reset()
incoming.Add("Aimee-Silvermoon", "mage")
lua.execute("ShowUsYourLootDB.incoming['aimee-silvermoon'].inRaidTeam = true")
lua.execute("ShowUsYourLootDB.incoming['aimee-silvermoon'].raidRole = 'HEALER'")

entry, _ = incoming.Add("Aimee-Silvermoon", "priest")
check("correcting the class keeps them on the team", bool(entry["inRaidTeam"]))
check("correcting the class keeps their role", entry["raidRole"] == "HEALER")
check("the class is actually corrected", entry["class"] == "PRIEST")

# --- counting and removing ------------------------------------------------
check("List returns them", len(list(incoming.List().values())) == 1)
check("Count agrees", incoming.Count() == 1)
check("Remove finds them by any casing", bool(incoming.Remove("aimee-SILVERMOON")))
check("and they are gone", incoming.Count() == 0)
check("removing an unknown recruit is not an error", not incoming.Remove("Nobody-Realm"))

# --- promotion ------------------------------------------------------------
reset()
incoming.Add("Aimee-Silvermoon", "mage")
lua.execute("ShowUsYourLootDB.incoming['aimee-silvermoon'].inRaidTeam = true")
lua.execute("ShowUsYourLootDB.incoming['aimee-silvermoon'].raidRole = 'HEALER'")

check("nobody is promoted while they are not in the guild", incoming.PromoteJoined() == 0)
check("and they are still on the joining list", incoming.Count() == 1)

lua.execute("Guilded['Aimee'] = { guid = 'G1', name = 'Aimee' }")
lua.execute("Registry['G1'] = {}")

check("they are promoted once the guild knows them", incoming.PromoteJoined() == 1)
check("the placeholder is gone", incoming.Count() == 0)
check(
    "the team flag moved onto the real record",
    bool(lua.globals().Registry["G1"].inRaidTeam),
)
check(
    "so did the role",
    lua.globals().Registry["G1"].raidRole == "HEALER",
)

# A role somebody set on the real character is a later decision about a
# character the client can see, and a fortnight-old placeholder must not
# overrule it.
reset()
incoming.Add("Aimee-Silvermoon", "mage")
lua.execute("ShowUsYourLootDB.incoming['aimee-silvermoon'].raidRole = 'HEALER'")
lua.execute("Guilded['Aimee'] = { guid = 'G1', name = 'Aimee' }")
lua.execute("Registry['G1'] = { raidRole = 'TANK' }")
incoming.PromoteJoined()

check(
    "an existing role is not overruled by the placeholder",
    lua.globals().Registry["G1"].raidRole == "TANK",
)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
