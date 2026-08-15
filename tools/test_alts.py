"""Alt mapping, and the way back out of it.

Nothing tested this. Mapping one character onto another is the most
retroactive thing this addon does — Core/Players.lua calls ResolveToMain the
choke point precisely because it rewrites who every past drop counted for —
and it had no coverage at all.

THE BUG THIS WAS WRITTEN FOR. The roster screen could create a mapping and had
nothing that removed one. "Alt of" wrote it; the button beside it said "Untick
all", which clears the ticks and reports nothing, so an officer looking for an
undo pressed it and watched the mapping stay exactly where it was. The only
route out was knowing that `/syl alts clear` exists. A character stuck as
somebody's alt drags the main onto every list, because the alt's raid nights
and loot are being counted against a person who was never there.

The round trip below is the assertion: whatever the screen can do to identity,
it must be able to undo. The wiring check at the end is the other half — no
behavioural test can see a button that was never built, so the call itself is
asserted to exist.

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

# The two characters from the report they were written about.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    SYL.Players.Ensure({ guid = 'S1', name = 'Saebie', class = 'ROGUE' })
    SYL.Players.Ensure({ guid = 'T1', name = 'Talestra', class = 'MAGE' })
    SYL.Players.Ensure({ guid = 'A1', name = 'Aimee', class = 'PRIEST' })
    """
)

check("an unmapped character resolves to itself",
      SYL.Players.ResolveToMain("S1") == "S1",
      SYL.Players.ResolveToMain("S1"))

# --- the mapping ----------------------------------------------------------
ok, message = SYL.Players.SetMain("S1", "T1", SYL.Players.MANUAL)

check("an alt can be mapped to a main", ok is True, message)
check("and its numbers then count against the main",
      SYL.Players.ResolveToMain("S1") == "T1",
      SYL.Players.ResolveToMain("S1"))
check("while the main still resolves to itself",
      SYL.Players.ResolveToMain("T1") == "T1")

# --- THE ROUND TRIP -------------------------------------------------------
#
# The half that did not exist on the roster screen.
ok, message = SYL.Players.ClearMain("S1")

check("A MAPPING CAN BE UNDONE", ok is True, message)
check("and the alt is counted as itself again",
      SYL.Players.ResolveToMain("S1") == "S1",
      SYL.Players.ResolveToMain("S1"))
check("the main is no longer dragged onto anything by it",
      len(SYL.Players.GetAlts("T1")) == 0,
      len(SYL.Players.GetAlts("T1")))

# Clearing twice is a refusal with a reason rather than a silent success,
# because "nothing happened" and "it was already like that" read identically
# on screen otherwise.
ok, message = SYL.Players.ClearMain("S1")

check("clearing an unmapped character says so",
      ok is False and message is not None, message)

# --- by name, which is what a person types --------------------------------
ok, _ = SYL.Players.SetMain("Saebie", "Talestra", SYL.Players.MANUAL)

check("the names work as well as the GUIDs", ok is True)
check("and resolve the same way",
      SYL.Players.ResolveToMain("S1") == "T1")

ok, _ = SYL.Players.ClearMain("Saebie")

check("clearing by name works too",
      ok is True and SYL.Players.ResolveToMain("S1") == "S1")

# --- a guess never overrules a person -------------------------------------
SYL.Players.SetMain("S1", "T1", SYL.Players.MANUAL)

ok, message = SYL.Players.SetMain("S1", "A1", SYL.Players.GUILD_NOTE)

check("a guild note cannot overwrite a mapping set by hand",
      ok is False and SYL.Players.ResolveToMain("S1") == "T1",
      message)

# After a clear it may map again — the clear removes the source as well as the
# mapping, so a note is no longer arguing with a decision that is gone. This is
# the behaviour, and it is worth pinning: it is what makes a guild note able to
# take effect at all once an officer has changed their mind.
SYL.Players.ClearMain("S1")

ok, _ = SYL.Players.SetMain("S1", "A1", SYL.Players.GUILD_NOTE)

check("but it may map a character nobody has ruled on",
      ok is True and SYL.Players.ResolveToMain("S1") == "A1")

SYL.Players.ClearMain("S1")

# --- loops ----------------------------------------------------------------
SYL.Players.SetMain("S1", "T1", SYL.Players.MANUAL)

ok, message = SYL.Players.SetMain("T1", "S1", SYL.Players.MANUAL)

check("two characters cannot point at each other",
      ok is False, message)
check("and the refusal says how to get out of it",
      message is not None and "clear" in str(message).lower(), message)

ok, message = SYL.Players.SetMain("S1", "S1", SYL.Players.MANUAL)

check("a character cannot be its own main", ok is False, message)

SYL.Players.ClearMain("S1")

# --- detection proposes, it does not apply --------------------------------
#
# The comment at the top of Core/AltDetect.lua is load-bearing: a mapping
# applied by a roster refresh would re-rank the due list because somebody
# edited a guild note.
check("a note that names a main is read",
      SYL.AltDetect.ParseNote("Alt of Talestra") is not None)
check("and a note that is just a word is not",
      SYL.AltDetect.ParseNote("bank") is None)
check("scanning changes nothing on its own",
      SYL.Players.ResolveToMain("S1") == "S1")

# --- the way out is printed where the problem is read ---------------------
#
# `/syl alts` is where somebody lands when a character is stuck as the wrong
# person's alt. It listed the mappings and stopped, which is how the only
# route out ended up being something you had to be told.
printed = []

lua.globals().ShowUsYourLoot.Write = lambda _self, line: printed.append(
    str(line)
)
lua.globals().ShowUsYourLoot.Print = lambda _self, line: printed.append(
    str(line)
)

SYL.Players.SetMain("S1", "T1", SYL.Players.MANUAL)
SYL.AltCommands.ReportCurrent()

report = " ".join(printed)

check("the mapping report names the mapping",
      "Talestra" in report and "Saebie" in report, report)
check("AND SAYS HOW TO UNDO IT",
      "alts clear" in report, report)
check("naming the button as well as the command",
      "Not an alt" in report, report)

SYL.Players.ClearMain("S1")

# --- the wiring -----------------------------------------------------------
#
# No behavioural test can see a button that was never built. The bug was the
# absence of this call, so its presence is the assertion.
source = (Path(__file__).resolve().parent.parent
          / "UI" / "RosterControls.lua").read_text(encoding="utf-8")

check("THE ROSTER SCREEN CAN UNDO WHAT IT CAN DO",
      "Players.ClearMain" in source,
      "UI/RosterControls.lua maps alts but never unmaps one")
check("and the undo is not the untick button",
      source.index("Players.ClearMain") != source.index("onClearSelection"))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
