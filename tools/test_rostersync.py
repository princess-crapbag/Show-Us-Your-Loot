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

outcome = SYL.RosterSync.Receive(OFFICER, message(
    1, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="DPS",
))

# --- 5. A ROSTER FROM A NEW NAME WAITS TO BE ASKED ABOUT ------------------
#
# The bug this whole model exists for. Aimee and her officer both had the
# sharing switch on, so both were broadcasting into one slot, and his nine
# names -- two of them on nobody's team but his -- simply became her roster.
# Core/SharedRoster.lua carries the account. Nothing lands unasked now.
check("RECEIVING IS NOT GATED BY THE SWITCH, BUT IT IS NOT SILENT EITHER",
      outcome == "pending", outcome)
check("and nothing has reached the roster yet",
      G.SharedNames() == "", G.SharedNames())

offer = SYL.SharedRoster.PendingOffer()

check("the offer says who it is from and what is in it",
      offer is not None and offer.source == OFFICER
      and len(offer.members) == 1,
      offer and offer.source)

landed, from_whom = SYL.SharedRoster.AcceptOffer()

check("SAYING YES IS WHAT PUTS IT ON THE ROSTER",
      landed == 1 and from_whom == OFFICER and "Nashri/DPS" in G.SharedNames(),
      G.SharedNames())
check("and nothing is left pending afterwards",
      SYL.SharedRoster.PendingOffer() is None)

source, _ = SYL.SharedRoster.Source()

check("and the sender is recorded", source == OFFICER, source)
check("who is now the accepted source",
      SYL.SharedRoster.AcceptedFrom() == OFFICER,
      SYL.SharedRoster.AcceptedFrom())

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

# --- the empty set clears, but only from the source we accepted -----------
#
# THE MESSAGE THAT WIPED A GUILD. An officer whose own team is empty answers
# every login request with the empty set -- a real message, meaning "I have
# cleared my roster" -- and it used to land on every client that heard it.
# Aimee's officer had an empty local team precisely BECAUSE everything they
# could see was her shared roster, which Own() deliberately excludes. So the
# guild's roster vanished, repeatedly, and the scope button quietly fell
# through to Guild so the list refilled with all fifteen guildies rather than
# going visibly blank.
#
# Two guards, and this is the one that matters most: an empty set from
# somebody unaccepted is not an offer of anything, and is ignored outright.
check("AN EMPTY SET FROM A STRANGER IS IGNORED",
      SYL.RosterSync.Receive(OTHER, message(59, 0, 0)) == "ignored")
check("and it does not touch the roster we are holding",
      G.SharedNames() == "Nashri/DPS", G.SharedNames())
check("nor does it leave a question on screen about nothing",
      SYL.SharedRoster.PendingOffer() is None)

# From the accepted source it is exactly what it says it is.
SYL.RosterSync.Receive(OFFICER, message(60, 0, 0))

check("AN EMPTY SET FROM THE ACCEPTED SOURCE CLEARS THE SHARED ROSTER",
      G.SharedNames() == "" and SYL.SharedRoster.HasShared() is False,
      G.SharedNames())
check("and the local marks survive it",
      SYL.RaidTeam.IsMember(TALESTRA) is True)
check("and they are still the accepted source afterwards",
      SYL.SharedRoster.AcceptedFrom() == OFFICER,
      SYL.SharedRoster.AcceptedFrom())

# --- our own broadcast coming back ----------------------------------------
check("we ignore our own broadcast",
      SYL.RosterSync.Receive(AIMEE, message(
          70, 1, 1, key=SAEBIE, name="Saebie", inRaidTeam=True,
      )) is None)
check("so nothing of ours arrives as somebody else's",
      SYL.SharedRoster.HasShared() is False, G.SharedNames())

# --- a second broadcaster does NOT win --------------------------------
#
# This is the assertion that changed, and the old one is the bug written
# down: "the newest complete set wins". It did, invisibly, and that is how
# two people nobody had put on a team ended up on Aimee's board.
SYL.RosterSync.Receive(OFFICER, message(
    80, 1, 1, key=SAEBIE, name="Saebie", inRaidTeam=True, raidRole="TANK",
))

check("the accepted source still updates without asking",
      G.SharedNames() == "Saebie/TANK", G.SharedNames())

outcome = SYL.RosterSync.Receive(OTHER, message(
    81, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="HEALER",
))

source, _ = SYL.SharedRoster.Source()

check("A SECOND BROADCASTER CANNOT REPLACE IT INVISIBLY",
      outcome == "pending" and G.SharedNames() == "Saebie/TANK",
      G.SharedNames())
check("AND THE SCREEN STILL SAYS WHO THE ROSTER CAME FROM",
      source == OFFICER, source)

# Saying no is remembered, or the same box arrives at every login of every
# person in the guild -- which teaches somebody to click through it unread.
declined = SYL.SharedRoster.DeclineOffer()

check("declining names who was declined", declined == OTHER, declined)
check("and they are not asked about again",
      SYL.RosterSync.Receive(OTHER, message(
          82, 1, 1, key=NASHRI, name="Nashri", inRaidTeam=True,
      )) == "ignored")
check("while the roster on screen is untouched by any of it",
      G.SharedNames() == "Saebie/TANK", G.SharedNames())

# --- sending on purpose ---------------------------------------------------
#
# The button. The switch was the only way to share and reads like the way to
# receive, which is how Aimee's officer became a broadcaster by accident.
SYL.Features.SetEnabled("rosterSharing", False)
G.ClearSent()
SYL.SendQueue.Reset()

sent = SYL.RosterSync.SendNow()
flush()

check("SEND WORKS WITH THE SWITCH OFF, because pressing it IS the asking",
      sent == 2 and G.SentCount() == 2, (sent, G.SentCount()))

# An empty team has nothing to send and says so, rather than broadcasting the
# empty set at the guild.
for key in (TALESTRA, SAEBIE, NASHRI):
    SYL.RaidTeam.SetMember(key, False)
    SYL.RaidTeam.SetRole(key, None)

G.ClearSent()
SYL.SendQueue.Reset()

sent, reason = SYL.RosterSync.SendNow()
flush()

check("AN EMPTY TEAM SENDS NOTHING AND SAYS WHY",
      sent is None and G.SentCount() == 0 and "nobody" in reason,
      (sent, reason, G.SentCount()))

# Announce is still allowed to send the empty set: an officer who unmarked
# their last raider has to be able to say so to the people who accepted them.
# It is ANSWERING a request with one that was the bug.
SYL.Features.SetEnabled("rosterSharing", True)
G.ClearSent()
SYL.SendQueue.Reset()

SYL.RosterSync.Announce()
flush()

check("but a deliberate announce still carries the empty set",
      G.SentCount() == 1, G.SentCount())

SYL.RaidTeam.SetMember(TALESTRA, True)
SYL.RaidTeam.SetRole(TALESTRA, "HEALER")

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


# --- 6. what the prompt actually says -------------------------------------
#
# Frame-free on purpose. UI/ClearSeasonDialog.lua's header says why: a dialog
# that cannot be driven from a test is a dialog that ships doing nothing, and
# that has happened in this addon before.
Prompt = SYL.SharedRosterPrompt
THIRD = "Kotastrophe-Area52"

SYL.RosterSync.Receive(THIRD, message(
    91, 1, 2, key=SAEBIE, name="Saebie", inRaidTeam=True, raidRole="TANK",
))
SYL.RosterSync.Receive(THIRD, message(
    91, 2, 2, key=NASHRI, name="Nashri", inRaidTeam=True, raidRole="HEALER",
))

pending = SYL.SharedRoster.PendingOffer()

check("an offer from a third name is waiting to be described",
      pending is not None and pending.source == THIRD,
      pending and pending.source)

check("THE TITLE NAMES WHO SENT IT, without the realm",
      Prompt.Title(pending) == "Kotastrophe sent you a raid team",
      Prompt.Title(pending))

body = Prompt.Describe(pending)

check("the body says how many people and that nothing has happened yet",
      "2 people" in body and "Nothing has changed yet" in body, body[:90])

names = Prompt.Names(pending)

check("the names are listed, sorted, with their roles",
      len(names) == 2 and names[1].name == "Nashri"
      and names[1].role == "HEALER",
      [(names[i].name, names[i].role) for i in range(1, len(names) + 1)])

accepted = Prompt.Accept()

check("ACCEPTING THROUGH THE PROMPT IS WHAT LANDS IT",
      accepted is True
      and G.SharedNames() == "Nashri/HEALER Saebie/TANK",
      G.SharedNames())

check("and that name is the accepted source afterwards",
      SYL.SharedRoster.AcceptedFrom() == THIRD,
      SYL.SharedRoster.AcceptedFrom())

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
