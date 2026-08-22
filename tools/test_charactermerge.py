"""One character that the client started calling a new one.

A FACTION CHANGE GIVES A CHARACTER A NEW GUID. Aimee, working the test list:
"the character Hinokamii faction changed between raid nights 1 and 2 and now he
shows up on the list twice. he is only 1 character and the former doesnt exist
to mark as an alt or anything."

Her data has it exactly — Player-3676-0DF5E74E on the Tuesday and
Player-3676-0EEC1213 on the Thursday, same realm, same name, same class — and
the existing alt screen cannot reach it, because it walks the guild roster and
the pre-change character is not in the guild any more.

THE CASE THAT MUST NOT MATCH is two real people, and the fixtures below are
mostly that: the same name on two realms is two people, the same name in one
raid roster is two characters that existed at the same moment, and a name freed
and retaken by another class is somebody else. A wrong merge folds two people's
attendance and loot together and is not obviously wrong on screen afterwards,
so the bar is deliberately high.

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
lua.execute("ShowUsYourLootDB = { players = {} }")

lua.execute(
    """
    local SYL = ShowUsYourLoot

    SYL.Players = {
        MANUAL = "manual",
        GetRegistry = function() return ShowUsYourLootDB.players end,
        SetMain = function(alt, main)
            ShowUsYourLootDB.players[alt].mainGUID = main
            return true
        end,
    }

    SESSIONS = {}
    SYL.GetActiveRaids = function() return SESSIONS end
    """
)

lua.execute((CORE / "CharacterMerge.lua").read_text(encoding="utf-8"))

Merge = lua.globals().ShowUsYourLoot.CharacterMerge
failures = []


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       got: " + repr(detail))

        failures.append(label)


def registry(entries):
    """entries: list of (guid, name, class, lastSeen)."""
    lua.execute("ShowUsYourLootDB.players = {}")
    reg = lua.globals().ShowUsYourLootDB.players

    for guid, name, klass, seen in entries:
        lua.execute(
            "TMP = { guid = %r, name = %r, class = %r, lastSeen = %d }"
            % (guid, name, klass, seen)
        )
        reg[guid] = lua.globals().TMP


def sessions(rosters):
    """rosters: list of lists of guids that were in one raid together."""
    lua.execute("SESSIONS = {}")
    out = lua.globals().SESSIONS

    for index, guids in enumerate(rosters, 1):
        lua.execute("TMPS = { roster = {} }")
        s = lua.globals().TMPS
        for g in guids:
            lua.execute("TMPM = { guid = %r, name = %r }" % (g, g))
            s.roster[g] = lua.globals().TMPM
        out[index] = s


OLD = "Player-3676-0DF5E74E"
NEW = "Player-3676-0EEC1213"

# --- her case -------------------------------------------------------------
registry([
    (OLD, "Hinokamii", "MAGE", 100),
    (NEW, "Hinokamii", "MAGE", 200),
])
sessions([[OLD, "Player-3676-0AAAAAAA"], [NEW, "Player-3676-0AAAAAAA"]])

found = Merge.Scan()

check("the pair is proposed", len(found) == 1, len(found))

if len(found) == 1:
    p = found[1]
    # DIRECTION MATTERS. Folding the living character into the dead one would
    # make her current character an alt of one that cannot be logged into.
    check("the older one is folded into the newer", p.oldGUID == OLD
          and p.newGUID == NEW, (p.oldGUID, p.newGUID))
    check("and it explains itself in words",
          "faction" in Merge.Describe(p), Merge.Describe(p))

check("either half of the pair finds it",
      Merge.For(OLD) is not None and Merge.For(NEW) is not None)
check("and somebody uninvolved does not", Merge.For("Player-3676-0AAAAAAA")
      is None)

# Applying it folds old into new, and only that.
Merge.Apply(Merge.For(NEW))
reg = lua.globals().ShowUsYourLootDB.players

check("the merge maps old to new", reg[OLD].mainGUID == NEW, reg[OLD].mainGUID)
check("and leaves the living character alone", reg[NEW].mainGUID is None)
check("a merged pair stops being proposed", len(Merge.Scan()) == 0)

# --- everything that must NOT merge ---------------------------------------

# Two realms. Names are only unique within one.
registry([
    ("Player-3676-0DF5E74E", "Hinokamii", "MAGE", 100),
    ("Player-1234-0EEC1213", "Hinokamii", "MAGE", 200),
])
sessions([])
check("THE SAME NAME ON TWO REALMS IS TWO PEOPLE", len(Merge.Scan()) == 0,
      len(Merge.Scan()))

# In one raid together. Whatever else they share, both existed at once.
registry([
    (OLD, "Hinokamii", "MAGE", 100),
    (NEW, "Hinokamii", "MAGE", 200),
])
sessions([[OLD, NEW]])
check("TWO CHARACTERS IN ONE RAID ARE NOT ONE CHARACTER",
      len(Merge.Scan()) == 0, len(Merge.Scan()))

# A faction change cannot change class, so this is a retaken name.
registry([
    (OLD, "Hinokamii", "MAGE", 100),
    (NEW, "Hinokamii", "WARRIOR", 200),
])
sessions([])
check("a name retaken by another class is somebody else",
      len(Merge.Scan()) == 0, len(Merge.Scan()))

# Different names entirely.
registry([
    (OLD, "Hinokamii", "MAGE", 100),
    (NEW, "Razorshift", "MAGE", 200),
])
sessions([])
check("two different names are two people", len(Merge.Scan()) == 0)

# A registry entry old enough to have no GUID has no realm to compare.
lua.execute("ShowUsYourLootDB.players = {}")
lua.execute(
    """
    ShowUsYourLootDB.players['legacy'] =
        { name = 'Hinokamii', class = 'MAGE', lastSeen = 50 }
    ShowUsYourLootDB.players[%r] =
        { guid = %r, name = 'Hinokamii', class = 'MAGE', lastSeen = 200 }
    """ % (NEW, NEW)
)
sessions([])
check("an entry with no GUID is left alone rather than guessed at",
      len(Merge.Scan()) == 0, len(Merge.Scan()))

# --- a realm's worth of ordinary raiders ----------------------------------
registry([
    ("Player-60-0F67DB37", "Jtkurayami", "PRIEST", 100),
    ("Player-60-0FF95539", "Niwmn", "DEATHKNIGHT", 100),
    ("Player-3676-06F46D60", "Phreestyle", "SHAMAN", 100),
])
sessions([["Player-60-0F67DB37", "Player-60-0FF95539",
           "Player-3676-06F46D60"]])
check("a normal roster proposes nothing at all", len(Merge.Scan()) == 0)

# --- the name form is not the test ----------------------------------------
# Her two entries carry different name forms — one bare, one realm-qualified —
# because they were captured by different code paths. That must not stop the
# match, which is the trap HANDOFF records for recordedBy.
lua.execute("ShowUsYourLootDB.players = {}")
lua.execute(
    """
    ShowUsYourLootDB.players[%r] = {
        guid = %r, name = 'Hinokamii', fullName = 'Hinokamii-Area52',
        class = 'MAGE', lastSeen = 100,
    }
    ShowUsYourLootDB.players[%r] = {
        guid = %r, name = 'Hinokamii', fullName = 'Hinokamii',
        class = 'MAGE', lastSeen = 200,
    }
    """ % (OLD, OLD, NEW, NEW)
)
sessions([])
check("a realm on one name form and not the other still matches",
      len(Merge.Scan()) == 1, len(Merge.Scan()))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
