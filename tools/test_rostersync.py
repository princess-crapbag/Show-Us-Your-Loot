"""Sharing the raid team, and the ways it would go wrong without saying so.

One broadcaster, everybody else receives. Aimee's call, and it removes the
whole class of merge failures that AbsenceSync has to defend against — there
is no per-author set here, so nothing can clobber anything. What is left is a
different and smaller list, and every item on it is silent:

1. A HALF-DELIVERED SET SHOWING A ROSTER WITH PEOPLE MISSING. A broadcast
   arrives as one message per raider. Committing before the last one lands
   draws a team with names absent, and absent reads as "dropped from the
   team" rather than as "still arriving".

2. THE SWITCH GATING THE WRONG DIRECTION. Every other sharing feature here
   registers its prefix inside Enable, so a client with the switch off is deaf
   as well as silent. This one is asymmetric on purpose: sending is gated,
   receiving is not, because the guildies it exists for are precisely the
   people who will never open the settings panel. If a future change makes
   receiving conditional again, the feature stops working for everyone except
   the person who already had it working — and their own screen would look
   completely normal.

3. A RECEIVED ROSTER WRITING INTO THE PLAYER REGISTRY. The registry is this
   account's own record and every RaidTeam setter writes to it. Somebody
   else's opinion landing in it would survive clearing the share, would be
   rebroadcast as though it were ours, and could not be told apart from a
   choice the user made. Same rule Sync.lua reaches by marking arriving drops
   partial.

4. THE FALLBACK ANSWERING FOR SOMEBODY THIS CLIENT HAS NEVER SEEN. A recruit
   who has not transferred is on the sender's roster and in neither the
   receiver's guild list nor their registry. An early return on the missing
   local record would answer nil for exactly the people the roster was sent
   to describe.

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

    -- This client is Aimee, and it is in a guild — the stub says otherwise,
    -- and CanSend refuses outside one.
    function UnitName() return 'Aimee' end
    function GetRealmName() return 'Area52' end
    function IsInGuild() return true end

    SENT = {}

    C_ChatInfo.SendAddonMessage = function(prefix, payload, channel)
        table.insert(SENT, {
            prefix = prefix, payload = payload, channel = channel,
        })
    end

    function ClearSent() SENT = {} end
    function SentCount() return #SENT end
    function SentChannel(i) return SENT[i] and SENT[i].channel end
    function SentPrefix(i) return SENT[i] and SENT[i].prefix end

    -- The shared roster as a sorted string, so an assertion can name exactly
    -- who is on it rather than counting.
    function SharedNames()
        local names = {}

        for key, member in pairs(SYL.SharedRoster.Members()) do
            table.insert(names,
                member.name .. '/' .. tostring(member.raidRole or '-'))
        end

        table.sort(names)

        return table.concat(names, ' ')
    end
    """
)

G = lua.globals()

AIMEE = "Aimee-Area52"
OFFICER = "Borg-Area52"
OTHER = "Dravok-Area52"

# Registry keys. Real ones are GUIDs; the recruit has only a name, which is
# the case the fallback has to survive.
TALESTRA = "Player-1-AAAA001"
SAEBIE = "Player-1-AAAA002"
NASHRI = "Player-1-AAAA003"
RECRUIT = "hawt-area52"


def ensure(guid, name, klass):
    SYL.Players.Ensure(lua.table_from({
        "guid": guid, "name": name, "fullName": name + "-Area52",
        "class": klass,
    }))


ensure(TALESTRA, "Talestra", "MAGE")
ensure(SAEBIE, "Saebie", "PRIEST")
ensure(NASHRI, "Nashri", "WARRIOR")


def message(serial, index, count, **fields):
    return SYL.RosterSync.Encode(
        serial, index, count, lua.table_from(fields) if fields else None
    )


def member(key, name, team=True, role=None, klass="MAGE"):
    return lua.table_from({
        "key": key, "name": name, "class": klass,
        "inRaidTeam": team, "raidRole": role,
    })


# --- the wire -------------------------------------------------------------
encoded = SYL.RosterSync.Encode(
    7, 1, 2, member(TALESTRA, "Talestra", True, "HEALER")
)

check("a message fits in an addon message", len(encoded) <= 255, len(encoded))

serial, index, count, decoded = SYL.RosterSync.Decode(encoded)

check("what goes out comes back",
      serial == 7 and index == 1 and count == 2
      and decoded.key == TALESTRA and decoded.name == "Talestra"
      and decoded.inRaidTeam is True and decoded.raidRole == "HEALER",
      encoded)

serial, index, count, decoded = SYL.RosterSync.Decode(
    SYL.RosterSync.Encode(8, 0, 0, None)
)

check("the empty set decodes to no member", count == 0 and decoded is None)

# Somebody on the roster for their role alone, with no team tick.
_, _, _, decoded = SYL.RosterSync.Decode(
    SYL.RosterSync.Encode(9, 1, 1, member(SAEBIE, "Saebie", False, "TANK"))
)

check("a role without a team tick survives the wire",
      decoded.inRaidTeam is False and decoded.raidRole == "TANK",
      decoded.raidRole)

check("a payload from another version is ignored",
      SYL.RosterSync.Decode("9\t1\t1\t1\tx\ty\tz\tw\t") is None)
check("and so is rubbish", SYL.RosterSync.Decode("nonsense") is None)

tabbed = SYL.RosterSync.Encode(
    1, 1, 1, member(TALESTRA, "Tal\testra", True, "DPS")
)

_, _, _, decoded = SYL.RosterSync.Decode(tabbed)

check("a tab in a name cannot break the framing",
      decoded is not None and decoded.key == TALESTRA,
      tabbed)

# --- what this client would send ------------------------------------------
SYL.RaidTeam.SetMember(TALESTRA, True)
SYL.RaidTeam.SetRole(TALESTRA, "HEALER")
SYL.RaidTeam.SetRole(SAEBIE, "TANK")

own = SYL.RosterSync.Own()

check("everyone marked or given a role travels", len(own) == 2, len(own))
check("and nobody else does",
      all(entry.key != NASHRI for entry in own.values()),
      [entry.key for entry in own.values()])
check("sorted, so the same roster encodes the same way twice",
      [e.key for e in own.values()] == sorted(e.key for e in own.values()),
      [e.key for e in own.values()])

# --- 2. the switch gates sending, and only sending ------------------------
SYL.Features.SetEnabled("rosterSharing", False)
G.ClearSent()

check("WITH SHARING OFF, ANNOUNCE SENDS NOTHING",
      SYL.RosterSync.Announce() is False and G.SentCount() == 0,
      G.SentCount())

SYL.Features.SetEnabled("rosterSharing", True)
G.ClearSent()
SYL.SendQueue.Reset()

announced = SYL.RosterSync.Announce()

# Nothing leaves in the frame that asked for it. Thirteen raiders queued and
# sent at once is what tripped the client's rate limit and silently lost a
# message, which leaves the receiving set half-assembled forever —
# tools/test_sendqueue.py is where that is argued and guarded.
check("ANNOUNCING QUEUES RATHER THAN SENDING", G.SentCount() == 0,
      G.SentCount())


def flush():
    """Pump the send queue dry. C_Timer is a no-op under the stub."""
    while SYL.SendQueue.Drain():
        pass


flush()

check("and one message per raider goes out once it drains",
      announced is True and G.SentCount() == 2, G.SentCount())
check("on the guild channel", G.SentChannel(1) == "GUILD", G.SentChannel(1))
check("under its own prefix", G.SentPrefix(1) == "SYLROST", G.SentPrefix(1))

# The whole point of the asymmetry. A client that shares nothing still hears.
SYL.Features.SetEnabled("rosterSharing", False)

SYL.RosterSync.Receive(OFFICER, message(
    1, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="DPS",
))

check("RECEIVING IS NOT GATED BY THE SWITCH",
      "Nashri/DPS" in G.SharedNames(), G.SharedNames())

source, _ = SYL.SharedRoster.Source()

check("and the sender is recorded", source == OFFICER, source)

# --- 3. nothing received reaches the player registry ----------------------
#
# Nashri is a real local record, unmarked. The broadcast above says they are on
# the team. The registry must still say nothing.
# Unpacked: Players.Get returns the record AND the key it resolved to, and
# lupa hands both back as one tuple. Reading .inRaidTeam off that reads a
# method on the tuple and fails somewhere else entirely.
record, _ = SYL.Players.Get(NASHRI)

check("A RECEIVED ROSTER DOES NOT WRITE TO THE REGISTRY",
      record.inRaidTeam is None and record.raidRole is None,
      (record.inRaidTeam, record.raidRole))
check("and is not rebroadcast as though it were ours",
      len(SYL.RosterSync.Own()) == 2, len(SYL.RosterSync.Own()))

# --- the fallback ---------------------------------------------------------
check("a shared tick answers where the local one is silent",
      SYL.RaidTeam.IsMember(NASHRI) is True)

role, detected = SYL.RaidTeam.GetRole(NASHRI)

check("and so does a shared role", role == "DPS" and detected is False,
      (role, detected))

# Local wins. Talestra is marked HEALER here and DPS on the broadcast.
SYL.RosterSync.Receive(OFFICER, message(
    2, 1, 1, key=TALESTRA, name="Talestra", inRaidTeam=True, raidRole="DPS",
))

role, _ = SYL.RaidTeam.GetRole(TALESTRA)

check("A LOCAL ROLE BEATS A SHARED ONE", role == "HEALER", role)

# --- 4. somebody this client has never seen -------------------------------
#
# The recruit has no registry record at all. An early return on the missing
# record would answer nil here and the roster would arrive with them missing.
SYL.RosterSync.Receive(OFFICER, message(
    3, 1, 1, key=RECRUIT, name="Hawt", inRaidTeam=True, raidRole="DPS",
))

check("A RAIDER WITH NO LOCAL RECORD IS STILL ON THE TEAM",
      SYL.RaidTeam.IsMember(RECRUIT) is True)

role, _ = SYL.RaidTeam.GetRole(RECRUIT)

check("and still has their role", role == "DPS", role)

# --- counting -------------------------------------------------------------
#
# Talestra is marked locally AND named on the broadcast. Counted twice, every
# screen that prints a team size is wrong and nothing says so.
SYL.RosterSync.Receive(OFFICER, message(
    4, 1, 1, key=TALESTRA, name="Talestra", inRaidTeam=True, raidRole="DPS",
))

check("SOMEBODY MARKED LOCALLY AND SHARED COUNTS ONCE",
      SYL.RaidTeam.Count() == 1, SYL.RaidTeam.Count())

SYL.RosterSync.Receive(OFFICER, message(
    5, 1, 2, key=TALESTRA, name="Talestra", inRaidTeam=True,
))
SYL.RosterSync.Receive(OFFICER, message(
    5, 2, 2, key=RECRUIT, name="Hawt", inRaidTeam=True,
))

check("and two distinct people count twice",
      SYL.RaidTeam.Count() == 2, SYL.RaidTeam.Count())

# --- 1. a half-delivered set must not commit ------------------------------
before = G.SharedNames()

SYL.RosterSync.Receive(OFFICER, message(
    50, 1, 3, key=SAEBIE, name="Saebie", inRaidTeam=True, raidRole="TANK",
))

check("A HALF-DELIVERED SET CHANGES NOTHING",
      G.SharedNames() == before, G.SharedNames())

SYL.RosterSync.Receive(OFFICER, message(
    50, 2, 3, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="HEALER",
))

check("and still nothing on the second of three",
      G.SharedNames() == before, G.SharedNames())

SYL.RosterSync.Receive(OFFICER, message(
    50, 3, 3, key=TALESTRA, name="Talestra", inRaidTeam=True, raidRole="DPS",
))

after = G.SharedNames()

check("the whole set lands once the last message arrives",
      "Saebie/TANK" in after and "Nashri/HEALER" in after
      and "Talestra/DPS" in after,
      after)
check("replacing what was held before", "Hawt" not in after, after)

# A newer serial supersedes a set still being assembled, rather than mixing
# two broadcasts into a roster that never existed.
SYL.RosterSync.Receive(OFFICER, message(
    51, 1, 2, key=SAEBIE, name="Saebie", inRaidTeam=True, raidRole="TANK",
))
SYL.RosterSync.Receive(OFFICER, message(
    52, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="DPS",
))

after = G.SharedNames()

check("a newer broadcast supersedes a half-assembled older one",
      after == "Nashri/DPS", after)

# --- the empty set clears -------------------------------------------------
SYL.RosterSync.Receive(OFFICER, message(60, 0, 0))

check("AN EMPTY SET CLEARS THE SHARED ROSTER",
      G.SharedNames() == "" and SYL.SharedRoster.HasShared() is False,
      G.SharedNames())
check("and the local marks survive it",
      SYL.RaidTeam.IsMember(TALESTRA) is True)

# --- our own broadcast coming back ----------------------------------------
check("we ignore our own broadcast",
      SYL.RosterSync.Receive(AIMEE, message(
          70, 1, 1, key=SAEBIE, name="Saebie", inRaidTeam=True,
      )) is None)
check("so nothing of ours arrives as somebody else's",
      SYL.SharedRoster.HasShared() is False, G.SharedNames())

# --- a second broadcaster is visible, not silent --------------------------
SYL.RosterSync.Receive(OFFICER, message(
    80, 1, 1, key=SAEBIE, name="Saebie", inRaidTeam=True, raidRole="TANK",
))
SYL.RosterSync.Receive(OTHER, message(
    81, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="HEALER",
))

source, _ = SYL.SharedRoster.Source()

check("the newest complete set wins",
      G.SharedNames() == "Nashri/HEALER", G.SharedNames())
check("AND THE SCREEN CAN SAY WHO IT CAME FROM", source == OTHER, source)

# --- clearing -------------------------------------------------------------
SYL.SharedRoster.Clear()

check("clearing removes the shared roster",
      SYL.SharedRoster.HasShared() is False)
check("AND LEAVES WHAT THIS CLIENT MARKED ITSELF",
      SYL.RaidTeam.IsMember(TALESTRA) is True
      and SYL.RaidTeam.GetChosenRole(TALESTRA) == "HEALER",
      SYL.RaidTeam.GetChosenRole(TALESTRA))
check("and the person who was only shared is gone",
      SYL.RaidTeam.IsMember(RECRUIT) is False)

# --- the wiring -----------------------------------------------------------
#
# No behavioural test can see a button that was never built, and this feature
# has the sharper version of that problem than most: everything above would
# pass with the roster arriving, landing, and displaying, and with no route on
# any screen from "these are not my ticks" to them being gone. Aimee's rule is
# that anything creatable is undoable from the same screen; here the person
# looking at it did not even create it.
roster_screen = (Path(__file__).resolve().parent.parent
                 / "UI" / "RaidersRoster.lua").read_text(encoding="utf-8")

check("THE ROSTER SCREEN CAN CLEAR A ROSTER IT DID NOT MAKE",
      "SharedRoster.Clear" in roster_screen,
      "UI/RaidersRoster.lua shows a shared roster with no way to dismiss it")
check("and says on screen where it came from",
      "shared by " in roster_screen,
      "nothing tells the reader these ticks are somebody else's")

# The broadcast has to be triggered by the screens that change the roster, or
# an officer marks somebody and nobody hears about it until their next login.
for screen, label in (("RaidersRoster", "the Raiders tab"),
                      ("RosterRows", "the roster window rows"),
                      ("RosterControls", "the bulk add and remove buttons")):
    source = (Path(__file__).resolve().parent.parent
              / "UI" / (screen + ".lua")).read_text(encoding="utf-8")

    check("a change made from " + label + " is announced",
          "RosterSync.OnOwnRosterChanged" in source,
          "UI/" + screen + ".lua changes the roster and tells nobody")

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
