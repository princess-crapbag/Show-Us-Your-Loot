"""Key requests go to one person, and only Denied can be asked again.

Two rules carry this feature and both are social rather than technical, which
is exactly why they need pinning down in a test — nothing about the code looks
wrong when they break.

IT NEVER BROADCASTS. A request is whispered to one named person. A guild-wide
"three people want this key" turns a favor into an auction, and the holder is
the only one who needs the full picture. The channel every message goes out on
is asserted here, because switching WHISPER to GUILD is a one-word change that
would work perfectly and quietly destroy the design.

ONLY DENIED CAN BE ASKED AGAIN. Pending means they have not looked yet, and
re-sending into that is how a helpful button becomes a way to pester people.
Approved and tentative are answers; asking again after an answer is a whisper.

Also covered: a dismissed request is hidden, not lost — the failure being
designed out is somebody clicking the X mid-raid and never finding out who
asked — and an answer to something never asked is dropped rather than creating
a row, or anybody could put entries on somebody else's screen.

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
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


# Capture every addon message rather than sending one, plus a guild roster
# whose online status a test can drive.
lua.execute(
    """
    SENT = {}
    PREFIXES = {}
    ONLINE = {}

    C_ChatInfo = {
        SendAddonMessage = function(prefix, payload, channel, target)
            table.insert(SENT, {
                prefix = prefix, payload = payload,
                channel = channel, target = target,
            })
        end,
        RegisterAddonMessagePrefix = function(prefix)
            table.insert(PREFIXES, prefix)

            return true
        end,
    }

    ShowUsYourLoot.Guild.GetMember = function(_, name)
        if name and ONLINE[name] then
            return { name = name, isOnline = true }
        end

        return nil
    end

    ShowUsYourLoot.Keystone.CharacterKey = function() return 'Me-Realm' end

    -- Somebody logging in or out, which is what GUILD_ROSTER_UPDATE reports
    -- and what a held key request is waiting for.
    function SetOnline(name, value)
        ONLINE[name] = value or nil
    end

    function ClearSent()
        SENT = {}
    end

    function Reset()
        SENT, PREFIXES = {}, {}
        ONLINE = { ['Dravok'] = true, ['Selunne'] = true }

        -- The queue too, not just what it has already sent. Requests are
        -- paced now, so anything a previous block queued and did not drain is
        -- still waiting and would arrive in the middle of the next one — which
        -- is how three whispers to Dravok turned up in the answering test.
        ShowUsYourLoot.SendQueue.Reset()

        ShowUsYourLootDB.keyRequests = nil
        ShowUsYourLoot.KeystoneRequests.Store()
    end

    function Channels()
        local out = {}

        for _, message in ipairs(SENT) do
            table.insert(out, message.channel .. '->' .. tostring(message.target))
        end

        return table.concat(out, ',')
    end

    function Deliver(kind, value, sender)
        ShowUsYourLoot.KeystoneRequestSync.OnMessage(
            ShowUsYourLoot.KeystoneRequestSync.PREFIX,
            ShowUsYourLoot.KeystoneRequestSync.Encode(kind, value),
            'WHISPER',
            sender
        )
    end

    function IncomingStatus(name)
        for _, entry in ipairs(ShowUsYourLoot.KeystoneRequests.Incoming()) do
            if entry.sender == name then
                return entry.status, entry.dismissed and true or false
            end
        end

        return nil
    end
    """
)

g = lua.globals()
R = SYL.KeystoneRequests

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
g.Reset()

# --- off means silent ------------------------------------------------------
#
# The same claim keystone sharing makes and has a test for: nothing sent, and
# no prefix even registered, until it is switched on.
check("it starts switched off", R.IsEnabled() is False)

ok, reason = R.Ask("Dravok", "DPS")

check("asking while off does nothing", ok is False, reason)
check("and nothing was sent", len(list(g.SENT.values())) == 0)
check("and no prefix was claimed", len(list(g.PREFIXES.values())) == 0)

# --- switching on ----------------------------------------------------------
SYL.KeystoneRequestSync.Enable()

check("enabling registers exactly one prefix", len(list(g.PREFIXES.values())) == 1)
check(
    "and it is the request prefix, not the sharing one",
    g.PREFIXES[1] == "SYLKREQ",
    g.PREFIXES[1],
)

# --- asking ----------------------------------------------------------------
g.Reset()

check("asking an online guildie works", R.Ask("Dravok", "TANK")[0] is True)

# Queued rather than sent, like everything else that talks. A whisper shares
# the client's rate limit with the guild broadcasts, and a request thrown away
# is a guildie who never answers. See Core/SendQueue.lua.
check("asking queues rather than sending", len(list(g.SENT.values())) == 0)

while SYL.SendQueue.Drain():
    pass

check("one message went out", len(list(g.SENT.values())) == 1)

# The assertion that protects the whole privacy model.
check(
    "it was whispered to that one person, not broadcast",
    g.Channels() == "WHISPER->Dravok",
    g.Channels(),
)
check("and it carried the role", "TANK" in g.SENT[1]["payload"], g.SENT[1]["payload"])

# --- who cannot be asked ---------------------------------------------------
ok, reason = R.Ask("Dravok", "DPS")

check("asking twice while waiting is refused", ok is False)
check("and says they have not answered", "not answered" in reason, reason)

# --- somebody who is offline ----------------------------------------------
#
# Aimee: "i still want to be able to request keys from other players who are
# not online and they see the message when they log in."
#
# Held rather than refused, and held rather than SENT: nothing in the game can
# put a message in front of a character who is not logged in, so the request
# waits and goes out the moment they appear. What must not happen is the
# request looking sent when it is not -- "pending" and "not asked yet" are
# different things to be waiting on.
g.ClearSent()
SYL.SendQueue.Reset()

ok, note = R.Ask("Nobody", "DPS")

while SYL.SendQueue.Drain():
    pass

check("ASKING SOMEBODY OFFLINE IS ACCEPTED", ok is True, note)
check("and nothing is sent, because there is nobody to send it to",
      len(list(g.SENT.values())) == 0, list(g.SENT.values()))

held = R.GetOutgoing("Nobody")

check("the request is held, marked as not yet sent",
      held is not None and held.queued is True,
      held and held.queued)
check("and it counts as one waiting to go", R.QueuedCount() == 1,
      R.QueuedCount())

check("flushing while they are still offline sends nothing",
      R.FlushQueued() == 0 and R.GetOutgoing("Nobody").queued is True)

# They log in. GUILD_ROSTER_UPDATE drives this in game.
g.SetOnline("Nobody", True)

check("ONCE THEY ARE ONLINE IT GOES OUT ON ITS OWN", R.FlushQueued() == 1)

while SYL.SendQueue.Drain():
    pass

check("and the message actually left this time",
      len(list(g.SENT.values())) == 1, list(g.SENT.values()))
check("and it is no longer marked as waiting",
      R.GetOutgoing("Nobody").queued is None and R.QueuedCount() == 0)

R.Dismiss("Nobody")
g.ClearSent()

ok, reason = R.Ask("Me-Realm", "DPS")

check("asking yourself is refused", ok is False)
check("and says why", "your own key" in reason, reason)

# --- only Denied reopens ---------------------------------------------------
for status, expected, label in (
    ("approved", False, "yes"),
    ("tentative", False, "maybe"),
    ("denied", True, "no"),
):
    g.Reset()
    R.Ask("Dravok", "DPS")
    g.Deliver("A", status, "Dravok")

    # CanAsk answers (allowed, reason), and lupa hands a multiple return back
    # as a tuple — so a refusal arrives as a pair and a yes as a bare true.
    answer = R.CanAsk("Dravok")
    allowed = answer[0] if isinstance(answer, tuple) else answer

    check(
        f"after {label}, asking again is {'allowed' if expected else 'refused'}",
        allowed is expected,
        f"CanAsk returned {answer}",
    )

# --- receiving a request ---------------------------------------------------
g.Reset()
g.Deliver("R", "HEALER", "Selunne")

status, dismissed = g.IncomingStatus("Selunne")

check("a request arrives as pending", status == "pending", status)
check("and is not dismissed", dismissed is False)
check("and is counted", R.PendingCount() == 1, R.PendingCount())

# Dismiss hides it from the count and keeps it on the list. This is the whole
# reason the list exists.
R.Dismiss("Selunne")

status, dismissed = g.IncomingStatus("Selunne")

check("dismissing drops it out of the count", R.PendingCount() == 0)
check("but it is still on the list", status == "pending", status)
check("and marked dismissed", dismissed is True)

# --- answering -------------------------------------------------------------
g.Reset()
g.Deliver("R", "DPS", "Selunne")

check("answering works", R.Answer("Selunne", "approved") is True)

while SYL.SendQueue.Drain():
    pass

check(
    "and the answer is whispered back to them alone",
    g.Channels() == "WHISPER->Selunne",
    g.Channels(),
)

status = g.IncomingStatus("Selunne")[0]

check("and the row records it", status == "approved", status)

check("an invented status is refused", R.Answer("Selunne", "maybe-ish") is False)
check("and answering somebody who never asked is refused", R.Answer("Ghost", "approved") is False)

# --- an answer to something never asked ------------------------------------
#
# Otherwise anybody could put rows on somebody else's screen by sending an
# answer nobody requested.
g.Reset()
g.Deliver("A", "approved", "Stranger")

check(
    "an unsolicited answer creates nothing",
    R.GetOutgoing("Stranger") is None,
)

# --- the panel draws -------------------------------------------------------
g.Reset()
g.Deliver("R", "TANK", "Selunne")

panel = None

try:
    panel = SYL.KeysPanel.Create(lua.globals().UIParent)
    SYL.KeysPanel.Refresh()
    check("the keys panel draws", True)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the keys panel draws", False, err)

for key in ("name", "dungeon", "level"):
    try:
        SYL.KeysPanel.SetSort(key, False)
        SYL.KeysPanel.SetSort(key, True)
        check(f"it sorts by {key} both ways", True)
    except Exception as err:  # noqa: BLE001
        check(f"it sorts by {key} both ways", False, err)

try:
    SYL.KeysPanel.SetRole("TANK")
    SYL.KeysPanel.SetRole("HEALER")
    check("the role picker cycles", True)
except Exception as err:  # noqa: BLE001
    check("the role picker cycles", False, err)

# --- the answer has somewhere to go ---------------------------------------
#
# The first working two-client test produced a reply that arrived correctly and
# was drawn as "? Ma..." — the status had been appended to the level cell,
# which is forty pixels wide. Everything about the request was right and the
# only broken part was where the answer was put.
#
# Checked in the source because the Keys panel has no render harness: the
# failure was a layout decision, not a value, and comparing values would have
# passed then too.
# The columns and the row drawing moved to UI/KeyRows.lua when KeysPanel was
# split at 635 lines. Same assertions, same reasoning — they follow the code
# rather than the filename, which is the point of reading the source at all.
rows_source = (Path(__file__).resolve().parent.parent
               / "UI" / "KeyRows.lua").read_text(encoding="utf-8")

panel = rows_source

check("THE REPLY HAS ITS OWN COLUMN",
      'key = "response"' in rows_source,
      "UI/KeyRows.lua has no response column for a reply to land in")
check("and the column is labelled",
      'label = "RESPONSE"' in rows_source, "the response column has no heading")
# Scoped to the function that draws the reply. Searching the whole file for
# "cells.level:SetText" finds the legitimate one further down that writes the
# level and nothing else — so a check reading the last match passed with the
# fault planted, which is what planting it was for.
draw_ask = rows_source.split("function KeyRows.DrawAsk")[1]

check("THE REPLY IS NOT WRITTEN INTO THE LEVEL CELL",
      "cells.level" not in draw_ask and "cells.response:SetText" in draw_ask,
      "a status is being put in the level cell again, where it truncates")

# Pooled rows: a reply left behind reads as the next player's answer.
check("and it is cleared before each row is drawn",
      'row.cells.response:SetText("")' in panel,
      "a stale reply would carry into the next player's row")


# --- a person, not a character ---------------------------------------------
#
# Aimee, 2026-09-06: "can i ask pronglez for his key on pringlescat and it
# send to whichever character he is online with and show which key im asking
# for?"
#
# Both halves are one change and the second is what makes the first safe: once
# a request can land on any character of a person, "your key" is a question
# with as many answers as they have characters. On her roster that guildie
# held +14 and +13 on one dungeon and +15 on another.
#
# THE ALT MAPPING IS THE WHOLE MECHANISM and it is worth a test of its own,
# because it is also the thing that was missing. Before she linked them, five
# of that person's eight characters pointed at the main and Pronglez -- the
# one she wanted -- did not, so asking Pronglez could only ever reach
# Pronglez. That is the fallback below, not a failure.

g.Reset()

lua.execute(
    """
    -- One person on four characters, which is the registry shape
    -- Players.SetMain writes: alts carry mainGUID, the main carries none.
    ShowUsYourLootDB.players = {
        ['P-CAT'] = { guid = 'P-CAT', name = 'Pringlescat',
                      fullName = 'Pringlescat-Illidan', class = 'DRUID' },
        ['P-BOP'] = { guid = 'P-BOP', name = 'Pringlesbop',
                      fullName = 'Pringlesbop-Illidan', class = 'PALADIN',
                      mainGUID = 'P-CAT' },
        ['P-LEZ'] = { guid = 'P-LEZ', name = 'Pronglez',
                      fullName = 'Pronglez-Illidan', class = 'MAGE',
                      mainGUID = 'P-CAT' },
        -- Nobody's alt, and the control for every assertion below.
        ['S-ONE'] = { guid = 'S-ONE', name = 'Selunne',
                      fullName = 'Selunne-Illidan', class = 'PRIEST' },
    }

    ShowUsYourLoot.Players.RebuildIndex()

    -- Their keys, per character, the way Core/Keystone.lua stores them.
    ShowUsYourLootDB.keystones = {
        ['Pronglez-Illidan'] = { name = 'Pronglez-Illidan',
                                 mapID = 585, level = 15 },
        ['Pringlescat-Illidan'] = { name = 'Pringlescat-Illidan',
                                    mapID = 249, level = 14 },
    }

    ONLINE = {}
    """
)

check("all of a person's characters are found from any one of them",
      sorted(list(R.CharactersOf("Pronglez-Illidan").values()))
      == ["Pringlesbop-Illidan", "Pringlescat-Illidan", "Pronglez-Illidan"],
      list(R.CharactersOf("Pronglez-Illidan").values()))

check("and somebody with no alts is just themselves",
      list(R.CharactersOf("Selunne-Illidan").values())
      == ["Selunne-Illidan"])

# --- which door the request goes through -----------------------------------

g.SetOnline("Pronglez-Illidan", True)

check("THE CHARACTER ASKED FOR WINS WHEN THEY ARE ONLINE",
      R.DeliveryFor("Pronglez-Illidan") == "Pronglez-Illidan",
      R.DeliveryFor("Pronglez-Illidan"))

g.SetOnline("Pronglez-Illidan", False)
g.SetOnline("Pringlesbop-Illidan", True)

check("AND AN ALT OF THEIRS CARRIES IT WHEN THEY ARE NOT",
      R.DeliveryFor("Pronglez-Illidan") == "Pringlesbop-Illidan",
      R.DeliveryFor("Pronglez-Illidan"))

g.SetOnline("Pringlesbop-Illidan", False)

check("and nothing of theirs online is nobody, not somebody else",
      R.DeliveryFor("Pronglez-Illidan") is None,
      R.DeliveryFor("Pronglez-Illidan"))

# THE FALLBACK, which is what an unmapped character does. This is the state
# Aimee's own registry was in before she linked Pronglez, and the behavior has
# to be "reaches nobody but themselves" rather than "reaches somebody at
# random" -- Players.ResolveToMain answers with the character's own key when
# it knows of no mapping, and that is what makes this safe.
g.SetOnline("Pringlesbop-Illidan", True)

check("an UNMAPPED character reaches only themselves",
      R.DeliveryFor("Selunne-Illidan") is None,
      "an unlinked alt must not inherit somebody else's delivery")

# --- and it says which key ------------------------------------------------

g.Reset()
lua.execute("ONLINE = { ['Pringlesbop-Illidan'] = true }")

ok, _ = R.Ask("Pronglez-Illidan", "HEALER")

check("asking for an offline character's key still goes out", ok is True)

sent = R.GetOutgoing("Pronglez-Illidan")

check("the row is keyed on WHOSE KEY IT IS", sent.target == "Pronglez-Illidan")
check("and remembers where it actually went",
      sent.sentTo == "Pringlesbop-Illidan", sent.sentTo)
check("and which key was asked about",
      sent.mapID == 585 and sent.level == 15, (sent.mapID, sent.level))
check("so it is not queued -- somebody received it",
      sent.queued is None, sent.queued)

# Drained so the whispers are on the wire rather than in the queue.
while SYL.SendQueue.Drain():
    pass

check("both messages went to the character who is online, as whispers",
      g.Channels() == "WHISPER->Pringlesbop-Illidan,"
                      "WHISPER->Pringlesbop-Illidan",
      g.Channels())

# THE KEY GOES FIRST, so the receiver is holding it when the ask lands. Both
# ride SendQueue, which is first in first out.
check("THE KEY IS SENT AHEAD OF THE ASK",
      g.SENT[1].payload.split("|")[1] == "K"
      and g.SENT[2].payload.split("|")[1] == "R",
      [g.SENT[1].payload, g.SENT[2].payload])

check("and it names the character whose key it is",
      g.SENT[1].payload.split("|")[2].split(chr(9))[0] == "Pronglez-Illidan",
      g.SENT[1].payload)

# --- receiving it ----------------------------------------------------------
#
# The other end of the same wire, replayed into this client.

g.Reset()
lua.execute("ShowUsYourLoot.Keystone.CharacterKey = function() "
            "return 'Pringlesbop-Illidan' end")

g.Deliver("K", "Pronglez-Illidan" + chr(9) + "585" + chr(9) + "15", "Aimee")
g.Deliver("R", "HEALER", "Aimee")

incoming = R.Incoming()[1]

check("the arriving request knows which of MY characters is meant",
      incoming.keyOwner == "Pronglez-Illidan", incoming.keyOwner)
check("and which key", incoming.mapID == 585 and incoming.level == 15,
      (incoming.mapID, incoming.level))
check("and the role asked for", incoming.role == "HEALER", incoming.role)

# A CLIENT ON AN OLDER BUILD SENDS NO KEY, and must still land a request. This
# is the whole reason the key is its own message rather than a longer ask:
# 0.4.6 sends only the role, and it still works.
g.Reset()
g.Deliver("R", "TANK", "Aimee")

older = R.Incoming()[1]

check("A REQUEST WITH NO KEY STILL ARRIVES",
      older.status == "pending" and older.role == "TANK", older.role)
check("and simply does not name one", older.mapID is None, older.mapID)

# --- the answer finds the row it belongs to --------------------------------
#
# We asked Pronglez. Pringlesbop replies. Without the key in hand there is no
# row named "Pringlesbop" and the answer would be dropped -- so somebody who
# did reply reads as never having.

g.Reset()

# BACK TO BEING OURSELVES. The receiving block above logged this client in as
# Pringlesbop to read his side of the wire, and OnMessage drops anything from
# our own character -- so leaving it set would silently discard every answer
# below and the assertions would read as the routing being broken.
lua.execute("ShowUsYourLoot.Keystone.CharacterKey = function() "
            "return 'Aimee-Area52' end")

lua.execute("""
    ShowUsYourLootDB.players = {
        ['P-CAT'] = { guid = 'P-CAT', name = 'Pringlescat',
                      fullName = 'Pringlescat-Illidan' },
        ['P-BOP'] = { guid = 'P-BOP', name = 'Pringlesbop',
                      fullName = 'Pringlesbop-Illidan', mainGUID = 'P-CAT' },
        ['P-LEZ'] = { guid = 'P-LEZ', name = 'Pronglez',
                      fullName = 'Pronglez-Illidan', mainGUID = 'P-CAT' },
    }

    ShowUsYourLoot.Players.RebuildIndex()

    ONLINE = { ['Pronglez-Illidan'] = true }
""")

R.Ask("Pronglez-Illidan", "DPS")

g.Deliver("K", "Pronglez-Illidan" + chr(9) + "585" + chr(9) + "15",
          "Pringlesbop-Illidan")
g.Deliver("A", "approved", "Pringlesbop-Illidan")

answered = R.GetOutgoing("Pronglez-Illidan")

check("AN ANSWER FROM AN ALT LANDS ON THE ROW IT ANSWERS",
      answered.status == "approved", answered.status)

# And the same thing from a client that cannot name the key, which falls back
# to resolving the speaker to the person who was asked.
lua.execute("ShowUsYourLootDB.keyRequests = nil")
SYL.KeystoneRequests.Store()
g.ClearSent()

R.Ask("Pronglez-Illidan", "DPS")
g.Deliver("A", "denied", "Pringlesbop-Illidan")

fallback = R.GetOutgoing("Pronglez-Illidan")

check("and so does one from an older build that cannot name it",
      fallback.status == "denied", fallback.status)

# TWO OPEN QUESTIONS TO ONE PERSON CANNOT BE TOLD APART FROM A BARE NAME, and
# marking the wrong one answered is worse than leaving both waiting.
lua.execute("ShowUsYourLootDB.keyRequests = nil")
SYL.KeystoneRequests.Store()

R.Ask("Pronglez-Illidan", "DPS")
R.Ask("Pringlescat-Illidan", "DPS")

g.Deliver("A", "approved", "Pringlesbop-Illidan")

check("but an ambiguous one is left alone rather than guessed at",
      R.GetOutgoing("Pronglez-Illidan").status == "pending"
      and R.GetOutgoing("Pringlescat-Illidan").status == "pending",
      "a bare name cannot say which of two open questions it answers")

# --- the alert ------------------------------------------------------------
#
# What the popup would say, without drawing it. The wording is the feature:
# a request that arrives on an alt is correct and looks like a bug unless the
# window says why.

g.Reset()
lua.execute("ShowUsYourLoot.Keystone.CharacterKey = function() "
            "return 'Pringlesbop-Illidan' end")
lua.execute("ShowUsYourLoot.Keystone.GetMapName = function() "
            "return 'Operation: Floodgate' end")

g.Deliver("K", "Pronglez-Illidan" + chr(9) + "585" + chr(9) + "15", "Aimee")
g.Deliver("R", "HEALER", "Aimee")

Alert = SYL.KeyRequestAlert
pending = Alert.Next()

check("the alert picks up the unanswered request",
      pending is not None and pending.sender == "Aimee")
check("names the key rather than saying 'your key'",
      Alert.Key(pending) == "+15 Operation: Floodgate", Alert.Key(pending))
check("and the character it sits on",
      Alert.Owner(pending) == "on Pronglez", Alert.Owner(pending))

routed = Alert.Routed(pending)

check("AND WHY IT ARRIVED HERE AND NOT THERE",
      routed is not None and "Pronglez" in routed
      and "Pringlesbop" in routed, routed)

# The other half: a request that landed where it was aimed has nothing to
# explain, and a sentence explaining it anyway is noise on every normal ask.
lua.execute("ShowUsYourLoot.Keystone.CharacterKey = function() "
            "return 'Pronglez-Illidan' end")

check("and nothing to explain when it landed where it was aimed",
      Alert.Routed(pending) is None, Alert.Routed(pending))

# A hidden request must not raise the popup again -- that is the difference
# between Hide and an answer, and the reason Hide is safe.
R.Dismiss("Aimee")

check("HIDE TAKES IT OFF THE POPUP", Alert.Next() is None)
check("and leaves it on the Keys tab", len(R.Incoming()) == 1,
      len(R.Incoming()))


print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
