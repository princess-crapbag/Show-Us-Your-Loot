"""Sharing who is out, and the three ways that goes wrong quietly.

Absences are the only thing this addon sends that is somebody's CLAIM rather
than something a client observed. A keystone is a fact about the sender's own
bags; a drop header is something the whole raid watched. "Talestra is out next
week" is one person's assertion about another, anyone running the addon can
make one, and Aimee's call was attribution rather than authorization: anybody
may set one, everybody sees who did.

THE THREE FAILURES WORTH TESTING, all of which look like nothing on screen:

1. A HALF-DELIVERED SET DELETING SOMEBODY'S ABSENCES. A broadcast arrives as
   several messages. Committing before all of them land replaces a person's
   list with a fragment, and the missing ones read as "they are available".

2. A REMOVAL NOT TRAVELLING. There are no tombstones — each client broadcasts
   the complete set it authored and a receiver replaces everything held from
   that author. That is the only reason a deletion propagates at all, so a
   merge that adds without removing leaves people marked out forever.

3. ONE AUTHOR CLOBBERING ANOTHER. Replacing by author is what keeps two
   officers from overwriting each other. The author is taken from the addon
   channel's sender, never from the payload, so a client cannot broadcast on
   somebody else's behalf.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from lupa import LuaRuntime  # noqa: F401  (imported for the error message)
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

import test_load  # noqa: E402  — reuses its stubbed client and loaded addon

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    local SYL = ShowUsYourLoot

    -- This client is Aimee. Everything it writes is authored by her, and
    -- everything from anyone else arrives over the channel.
    function UnitName() return 'Aimee' end
    function GetRealmName() return 'Area52' end

    function OutNames()
        local names = {}

        for _, absence in ipairs(SYL.RaidSchedule.AllAbsences()) do
            table.insert(names,
                absence.name .. '/' .. tostring(absence.setBy))
        end

        table.sort(names)

        return table.concat(names, ' ')
    end
    """
)

AIMEE = SYL.RaidSchedule.Author()
OFFICER = "Borg-Area52"
OTHER = "Dravok-Area52"

check("this client knows who it is", AIMEE == "Aimee-Area52", AIMEE)

# --- what we wrote is ours, and only ours, to broadcast -------------------
SYL.RaidSchedule.AddAbsence("Talestra", "2026-08-20", "2026-08-24",
                            lua.table_from({"reason": "holiday"}))

check("an absence records who set it",
      "Talestra/" + AIMEE in lua.globals().OutNames(),
      lua.globals().OutNames())
check("and it carries an id", len(SYL.AbsenceSync.Own()) == 1,
      len(SYL.AbsenceSync.Own()))

# Somebody else's absence must not go out from here — otherwise every client
# echoes every other one and nobody's set is authoritative.
SYL.RaidSchedule.ReplaceAbsencesFrom(OFFICER, lua.table_from([
    lua.table_from({"id": "b|1|1", "name": "Saebie", "from": "2026-08-20",
                    "to": "2026-08-20", "reason": "work"}),
]))

check("somebody else's absence is stored",
      "Saebie/" + OFFICER in lua.globals().OutNames(),
      lua.globals().OutNames())
check("BUT IS NOT REBROADCAST BY US",
      len(SYL.AbsenceSync.Own()) == 1,
      [dict(a) for a in []] or len(SYL.AbsenceSync.Own()))

# --- 2. a removal travels because the set is replaced ---------------------
SYL.RaidSchedule.ReplaceAbsencesFrom(OFFICER, lua.table_from([]))

check("AN EMPTY SET FROM AN AUTHOR CLEARS THEIR ABSENCES",
      "Saebie" not in lua.globals().OutNames(),
      lua.globals().OutNames())
check("and leaves everybody else's alone",
      "Talestra/" + AIMEE in lua.globals().OutNames(),
      lua.globals().OutNames())

# --- 3. one author cannot clobber another ---------------------------------
SYL.RaidSchedule.ReplaceAbsencesFrom(OFFICER, lua.table_from([
    lua.table_from({"id": "b|2|1", "name": "Saebie", "from": "2026-08-20",
                    "to": "2026-08-20"}),
]))
SYL.RaidSchedule.ReplaceAbsencesFrom(OTHER, lua.table_from([
    lua.table_from({"id": "d|1|1", "name": "Likestoflash",
                    "from": "2026-08-21", "to": "2026-08-21"}),
]))

names = lua.globals().OutNames()

check("three authors coexist",
      all(n in names for n in
          ("Talestra/" + AIMEE, "Saebie/" + OFFICER,
           "Likestoflash/" + OTHER)),
      names)

# Replacing one leaves the other two untouched.
SYL.RaidSchedule.ReplaceAbsencesFrom(OFFICER, lua.table_from([]))

names = lua.globals().OutNames()

check("replacing one author touches only their own",
      "Saebie" not in names
      and "Talestra/" + AIMEE in names
      and "Likestoflash/" + OTHER in names,
      names)

SYL.RaidSchedule.ReplaceAbsencesFrom(OTHER, lua.table_from([]))

# --- the wire -------------------------------------------------------------
encoded = SYL.AbsenceSync.Encode(7, 1, 2, lua.table_from({
    "id": "a|1|1", "name": "Talestra", "from": "2026-08-20",
    "to": "2026-08-24", "reason": "holiday",
}))

check("a message fits in an addon message", len(encoded) <= 255, len(encoded))

serial, index, count, absence = SYL.AbsenceSync.Decode(encoded)

check("what goes out comes back",
      serial == 7 and index == 1 and count == 2
      and absence.name == "Talestra" and absence.reason == "holiday",
      encoded)

# The empty-set marker is a real message and the one that clears a list.
serial, index, count, absence = SYL.AbsenceSync.Decode(
    SYL.AbsenceSync.Encode(8, 0, 0, None)
)

check("the empty set decodes to no absence",
      count == 0 and absence is None)

check("a payload from another version is ignored",
      SYL.AbsenceSync.Decode("9\t1\t1\t1\tx\ty\tz\tw\t") is None)
check("and so is rubbish", SYL.AbsenceSync.Decode("nonsense") is None)

# A tab in a typed reason would split the message into the wrong fields.
tabbed = SYL.AbsenceSync.Encode(1, 1, 1, lua.table_from({
    "id": "a|1|1", "name": "Talestra", "from": "2026-08-20",
    "to": "2026-08-20", "reason": "back\tsoon",
}))

_, _, _, absence = SYL.AbsenceSync.Decode(tabbed)

check("a tab typed into a reason cannot break the framing",
      absence is not None and absence.name == "Talestra",
      tabbed)

# --- 1. a half-delivered set must not commit ------------------------------
#
# Driven through Commit rather than the event handler, because what is being
# asserted is that a fragment never reaches the store.
SYL.RaidSchedule.ReplaceAbsencesFrom(OFFICER, lua.table_from([
    lua.table_from({"id": "b|3|1", "name": "Saebie", "from": "2026-08-20",
                    "to": "2026-08-20"}),
    lua.table_from({"id": "b|3|2", "name": "Arcangila", "from": "2026-08-20",
                    "to": "2026-08-20"}),
]))

before = lua.globals().OutNames()

check("two of theirs are held",
      "Saebie/" + OFFICER in before and "Arcangila/" + OFFICER in before,
      before)

def message(serial, index, count, **fields):
    return SYL.AbsenceSync.Encode(
        serial, index, count, lua.table_from(fields) if fields else None
    )


# One message of a two-message set. Nothing may change until the second
# arrives: committing here would drop Arcangila and read on the calendar as
# that person being available.
first = message(99, 1, 2, id="b|9|1", name="Saebie",
                **{"from": "2026-08-20", "to": "2026-08-20"})

SYL.AbsenceSync.Receive(OFFICER, first)

check("A HALF-DELIVERED SET CHANGES NOTHING",
      lua.globals().OutNames() == before, lua.globals().OutNames())

second = message(99, 2, 2, id="b|9|2", name="Nashri",
                 **{"from": "2026-08-21", "to": "2026-08-21"})

SYL.AbsenceSync.Receive(OFFICER, second)

after = lua.globals().OutNames()

check("and the whole set lands once the last message arrives",
      "Saebie/" + OFFICER in after and "Nashri/" + OFFICER in after,
      after)
check("replacing what that author had before",
      "Arcangila" not in after, after)

# A newer serial supersedes a set still being assembled, rather than mixing
# the two into one list that never existed.
SYL.AbsenceSync.Receive(OFFICER, message(
    100, 1, 2, id="b|10|1", name="Zugzug",
    **{"from": "2026-08-22", "to": "2026-08-22"}
))
SYL.AbsenceSync.Receive(OFFICER, message(
    101, 1, 1, id="b|11|1", name="Dravok",
    **{"from": "2026-08-23", "to": "2026-08-23"}
))

after = lua.globals().OutNames()

check("a newer broadcast supersedes a half-assembled older one",
      "Dravok/" + OFFICER in after and "Zugzug" not in after,
      after)

# Our own set coming back to us is dropped at the door.
check("we ignore our own broadcast",
      SYL.AbsenceSync.Receive(AIMEE, message(
          1, 1, 1, id="a|1|1", name="Nobody",
          **{"from": "2026-08-20", "to": "2026-08-20"}
      )) is None)
check("and Talestra is still ours",
      "Talestra/" + AIMEE in lua.globals().OutNames(),
      lua.globals().OutNames())

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
