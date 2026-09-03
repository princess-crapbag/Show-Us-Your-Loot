"""Handing a season of loot to one officer, and the ways it would go wrong.

The bug this feature exists for is a screen full of dashes. Aimee's officer's
Raiders board showed a number for exactly one person and "—" for the other
fourteen, because their client had never recorded the nights and there was no
way to give them the records. Aimee: "its not showing the score of the items i
marked to match rclc."

What is worth guarding here, and every item is silent:

1. THE ROLL LISTS HAVE TO TRAVEL. The first design sent headers only -- a
   third of the bytes -- and it is wrong in a way that would have shipped
   looking right. Core/Sync.lua marks a header-only record `partial`, and
   Analytics.lua skips every partial record, so the points would have moved
   and attendance, eligibility and the whole of the pass data would have
   stayed blank. Decoded records must not be partial.

2. A LOCAL RECORD IS RICHER AND MUST SURVIVE. Two clients disagree about a
   drop only when one of them saw less -- Core/SyncRolls.lua's rule. The one
   exception is the credit override, which nobody SAW: an officer typed it,
   after the fact, on one screen, so there is no local version to lose.

3. NOTHING TRAVELS BEFORE THE ANSWER. The offer names what is coming and the
   data waits. A transfer that started on send would put three and a half
   minutes of traffic and a few hundred rows into somebody's database because
   a name was clicked on a different screen.

4. THE OUTBOX MUST NOT BE POURED INTO SendQueue. That queue caps at 200 and
   drops the overflow with a debug line. Aimee's season is 983 messages, so
   783 would vanish and the receiver would hold a set that never completes --
   which looks exactly like nothing having been sent.

5. A HALF-ARRIVED RECORD MUST NOT BE COMMITTED, and a stopped transfer must
   leave the database as it was rather than a third merged.

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

    function UnitName() return 'Aimee' end
    function GetRealmName() return 'Area52' end
    function UnitFullName() return 'Aimee', 'Area52' end
    function IsInGuild() return true end

    SENT = {}

    C_ChatInfo.SendAddonMessage = function(prefix, payload, channel, target)
        table.insert(SENT, {
            prefix = prefix, payload = payload,
            channel = channel, target = target,
        })
    end

    function ClearSent() SENT = {} end
    function SentCount() return #SENT end
    function SentPayload(i) return SENT[i] and SENT[i].payload end
    function SentChannel(i) return SENT[i] and SENT[i].channel end
    function SentTarget(i) return SENT[i] and SENT[i].target end
    """
)

G = lua.globals()

AIMEE = "Aimee-Area52"
OFFICER = "Pringlesbop-Illidan"


def flush():
    """Pump the shared send queue dry. C_Timer is a no-op under the stub."""
    while SYL.SendQueue.Drain():
        pass


def drain_history():
    """And the history outbox, which paces itself into that queue."""
    while SYL.HistorySync.Drain():
        flush()

    flush()


# A drop with a full roll list and a credit override, which is the shape that
# matters: the rolls are what stop it being partial, the override is the thing
# Aimee typed and the reason the whole feature exists.
def drop(record_id, item=180000, credited=None, rolls=3):
    roll_list = []

    for index in range(rolls):
        roll_list.append(lua.table_from({
            "name": "Raider%d" % index,
            "guid": "Player-1-ROLL%03d" % index,
            "class": "MAGE",
            "state": 1 if index == 0 else 4,
            "stateText": "Need" if index == 0 else "Pass",
            "roll": 90 - index,
            "isWinner": index == 0 or None,
        }))

    fields = {
        "id": record_id,
        "seasonID": "s1",
        "seasonName": "Midnight Season 2",
        "encounterID": 2900,
        "encounterName": "Grand Magistrix",
        "difficultyID": 15,
        "difficultyName": "Heroic",
        "instanceID": 2810,
        "instanceName": "Midnight Lair",
        "instanceType": "raid",
        "itemID": item,
        "itemName": "Bracers of Testing",
        "itemLink": "|cffa335ee|Hitem:%d::::::::80:::::|h[Bracers]|h|r" % item,
        "itemLevel": 662,
        "winnerName": "Raider0",
        "winnerGUID": "Player-1-ROLL000",
        "winnerClass": "MAGE",
        "winnerRoll": 90,
        "winnerState": 1,
        "eligibleCount": rolls,
        "timestamp": 1788400000 + record_id.__hash__() % 1000,
        "dateText": "2026-08-30",
        "timeText": "21:14:02",
        "recordedBy": AIMEE,
        "rolls": lua.table_from(roll_list),
    }

    if credited:
        fields["creditOverride"] = lua.table_from(credited)

    return lua.table_from(fields)


# --- 1. the wire ----------------------------------------------------------
original = drop("drop-1", credited={
    "guid": "Player-1-ROLL002", "name": "Raider2", "state": 1,
    "setAt": 1788400500, "setBy": AIMEE,
})

encoded = SYL.HistoryPayload.Encode(original)
decoded = SYL.HistoryPayload.Decode(encoded)

check("a drop survives the round trip",
      decoded is not None and decoded.id == "drop-1"
      and decoded.itemID == 180000 and decoded.winnerName == "Raider0",
      encoded[:120])

check("NUMBERS COME BACK AS NUMBERS, not as text that sorts wrong",
      decoded.itemLevel == 662 and decoded.timestamp == original.timestamp
      and decoded.difficultyID == 15,
      (decoded.itemLevel, decoded.timestamp))

check("THE ROLL LIST TRAVELS, which is what stops it being partial",
      len(decoded.rolls) == 3, len(decoded.rolls))

check("and the winner is still the winner inside it",
      decoded.rolls[1].isWinner is True and decoded.rolls[1].roll == 90,
      decoded.rolls[1].roll)
check("and a pass is still a pass",
      decoded.rolls[2].isWinner is None and decoded.rolls[2].stateText == "Pass",
      decoded.rolls[2].stateText)

check("THE CREDIT OVERRIDE TRAVELS, which is the point of the feature",
      decoded.creditOverride is not None
      and decoded.creditOverride.name == "Raider2"
      and decoded.creditOverride.setBy == AIMEE,
      decoded.creditOverride and decoded.creditOverride.name)

check("a record with no override does not invent one",
      SYL.HistoryPayload.Decode(
          SYL.HistoryPayload.Encode(drop("drop-2"))
      ).creditOverride is None)

check("A RECEIVED DROP IS NOT MARKED PARTIAL, or Analytics skips it",
      decoded.partial is None and decoded.source == "SYNC_HISTORY",
      (decoded.partial, decoded.source))

check("hidden and excluded are the receiver's own business",
      decoded.hidden is False and decoded.excludedFromAnalytics is False)

check("a payload from another protocol is ignored",
      SYL.HistoryPayload.Decode("H9\tx\ty") is None)
check("and so is rubbish", SYL.HistoryPayload.Decode("nonsense") is None)

tabbed = SYL.HistoryPayload.Decode(
    SYL.HistoryPayload.Encode(drop("drop\t3"))
)

check("a tab in a field cannot break the framing",
      tabbed is not None and "\t" not in tabbed.id, tabbed and tabbed.id)

# --- 2. the merge ---------------------------------------------------------
season = lua.table_from({"drops": lua.table_from([])})

added, updated, skipped = SYL.HistoryPayload.Merge(
    season, lua.table_from([decoded, SYL.HistoryPayload.Decode(
        SYL.HistoryPayload.Encode(drop("drop-2"))
    )])
)

check("drops this client has never seen are added",
      added == 2 and len(season.drops) == 2, (added, len(season.drops)))

# The same two again. Nothing new, nothing duplicated.
added, updated, skipped = SYL.HistoryPayload.Merge(
    season, lua.table_from([decoded])
)

check("SENDING THE SAME SEASON TWICE DOES NOT DOUBLE IT",
      added == 0 and len(season.drops) == 2, (added, len(season.drops)))

# A local record that is RICHER than the arriving one keeps what it has.
local_rich = drop("drop-4", rolls=5)
season.drops[len(season.drops) + 1] = local_rich

thin = SYL.HistoryPayload.Decode(
    SYL.HistoryPayload.Encode(drop("drop-4", rolls=1, credited={
        "guid": "Player-1-ROLL004", "name": "Raider4", "state": 1,
        "setAt": 1788401000, "setBy": OFFICER,
    }))
)

SYL.HistoryPayload.Merge(season, lua.table_from([thin]))

kept = None
for index in range(1, len(season.drops) + 1):
    if season.drops[index].id == "drop-4":
        kept = season.drops[index]

check("A LOCAL RECORD KEEPS ITS OWN ROLL LIST", len(kept.rolls) == 5,
      len(kept.rolls))
check("BUT TAKES THE CREDIT THE OTHER OFFICER TYPED",
      kept.creditOverride is not None
      and kept.creditOverride.name == "Raider4",
      kept.creditOverride and kept.creditOverride.name)

# Both typed one. The newer decision stands, the way it would if one person
# had changed their mind twice.
older = SYL.HistoryPayload.Decode(
    SYL.HistoryPayload.Encode(drop("drop-4", rolls=1, credited={
        "guid": "Player-1-ROLL009", "name": "Raider9", "state": 1,
        "setAt": 1788400001, "setBy": OFFICER,
    }))
)

SYL.HistoryPayload.Merge(season, lua.table_from([older]))

check("an OLDER credit decision does not overwrite a newer one",
      kept.creditOverride.name == "Raider4", kept.creditOverride.name)

# --- 3. nothing travels before the answer ---------------------------------
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

live = SYL.GetActiveSeason()

for index in range(1, 6):
    live.drops[index] = drop("live-%d" % index, item=180000 + index)

G.ClearSent()
SYL.SendQueue.Reset()

ok, summary = SYL.HistorySync.Offer(OFFICER, live)
flush()

check("offering counts what is actually going, not an estimate",
      ok is True and summary.drops == 5 and summary.messages > 5,
      (summary.drops, summary.messages))

check("ONLY THE OFFER GOES OUT, not the season",
      G.SentCount() == 1, G.SentCount())
check("as a whisper to that one person",
      G.SentChannel(1) == "WHISPER" and G.SentTarget(1) == OFFICER,
      (G.SentChannel(1), G.SentTarget(1)))
check("and it names what is coming, so the other end can show it",
      live.name in G.SentPayload(1)
      and G.SentPayload(1).startswith("1" + chr(9) + "O"),
      G.SentPayload(1))

refused, why = SYL.HistorySync.Offer(AIMEE, live)

check("sending to yourself is refused", refused is False, why)

# --- 4. the outbox is paced, not poured -----------------------------------
G.ClearSent()
SYL.SendQueue.Reset()

sent_before, total = SYL.HistorySync.Progress()

check("nothing has been sent while we wait for the answer",
      sent_before == 0 and total > 5, (sent_before, total))

SYL.HistorySync.Begin(OFFICER)
flush()

check("SAYING YES SENDS ONE MESSAGE, NOT ALL OF THEM",
      G.SentCount() == 1, G.SentCount())

sent, _ = SYL.HistorySync.Progress()

check("and the progress number is what is on the wire", sent == 1, sent)

drain_history()

sent, total = SYL.HistorySync.Progress()

check("the whole season goes out once it drains",
      sent == total, (sent, total))
check("under the queue's cap the whole way, so nothing is dropped",
      SYL.SendQueue.Pending() == 0, SYL.SendQueue.Pending())
check("and the last thing said is that it is finished",
      G.SentPayload(G.SentCount()) == "1\tE",
      G.SentPayload(G.SentCount()))

# --- 5. receiving ---------------------------------------------------------
#
# Replayed into a fresh database, which is the officer's client: they have
# nothing, and everything sent has to land.
captured = [G.SentPayload(i) for i in range(1, G.SentCount() + 1)]

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

SYL.HistorySync.OnMessage(
    "SYLHIST", "1\tO\tMidnight Season 2\t5\t0\t20", "WHISPER", OFFICER
)

offer = SYL.HistorySync.PendingOffer()

check("AN OFFER DOES NOT WRITE ANYTHING, it waits",
      offer is not None and offer.drops == 5
      and len(SYL.GetActiveSeason().drops) == 0,
      offer and offer.drops)

SYL.HistorySync.AcceptOffer()

for payload in captured:
    SYL.HistorySync.OnMessage("SYLHIST", payload, "WHISPER", OFFICER)

received = SYL.GetActiveSeason()

check("EVERY DROP ARRIVES", len(received.drops) == 5,
      len(received.drops))
check("with its roll list intact",
      len(received.drops[1].rolls) == 3, len(received.drops[1].rolls))
check("and none of them marked partial, so the board can count them",
      all(received.drops[i].partial is None for i in range(1, 6)))

# A half-delivered record must not land.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

SYL.HistorySync.OnMessage(
    "SYLHIST", "1\tO\tMidnight Season 2\t1\t0\t3", "WHISPER", OFFICER
)
SYL.HistorySync.AcceptOffer()

big = SYL.HistoryPayload.Encode(drop("half-1"))

SYL.HistorySync.OnMessage(
    "SYLHIST", "1\tD\t1\t1\t2\t" + big[:100], "WHISPER", OFFICER
)

landed, corrected, ignored = SYL.HistorySync.Commit()

check("A HALF-ARRIVED RECORD IS NOT COMMITTED",
      landed == 0 and corrected == 0,
      (landed, corrected, ignored))
check("and the season is untouched by it",
      len(SYL.GetActiveSeason().drops) == 0,
      len(SYL.GetActiveSeason().drops))

# --- 6. a decline is heard -------------------------------------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

live = SYL.GetActiveSeason()
live.drops[1] = drop("solo-1")

G.ClearSent()
SYL.SendQueue.Reset()

SYL.HistorySync.Offer(OFFICER, live)
flush()

SYL.HistorySync.OnMessage("SYLHIST", "1\tN", "WHISPER", OFFICER)

G.ClearSent()
drain_history()

check("A DECLINE STOPS THE TRANSFER DEAD",
      SYL.HistorySync.IsSending() is False and G.SentCount() == 0,
      G.SentCount())

# --- 7. not from strangers -------------------------------------------------
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return false end
""")

SYL.HistorySync.OnMessage(
    "SYLHIST", "1\tO\tSomething\t9\t9\t9", "WHISPER", "Stranger-Ravencrest"
)

check("AN OFFER FROM OUTSIDE THE GUILD IS NOT EVEN A QUESTION",
      SYL.HistorySync.PendingOffer() is None,
      SYL.HistorySync.PendingOffer())


# --- 8. what the two windows say ------------------------------------------
#
# Frame-free, for the reason UI/ClearSeasonDialog.lua's header gives.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

live = SYL.GetActiveSeason()

for index in range(1, 4):
    live.drops[index] = drop(
        "facts-%d" % index,
        credited=({"guid": "g", "name": "Raider2", "state": 1,
                   "setAt": 1, "setBy": AIMEE} if index == 1 else None),
    )

facts = SYL.ShareWindow.Facts()

check("THE SEND WINDOW COUNTS WHAT IS THERE",
      "3 drops" in facts and "1 of them carrying credit" in facts, facts)
check("and says how long it will take, in messages and minutes",
      "messages" in facts and "minute" in facts, facts)

empty = lua.table_from({"name": "Nothing Yet",
                        "drops": lua.table_from([])})

check("an empty season says so rather than offering nothing",
      "nothing to send" in SYL.HistorySync.Describe(empty).seasonName
      or SYL.HistorySync.Describe(empty).drops == 0)

offer = lua.table_from({
    "source": OFFICER, "seasonName": "Midnight Season 2",
    "drops": 130, "credited": 52, "messages": 983,
})

check("THE RECEIVER'S PROMPT NAMES THE SENDER WITHOUT THE REALM",
      SYL.HistoryPrompt.Title(offer)
      == "Pringlesbop is sending loot history",
      SYL.HistoryPrompt.Title(offer))

body = SYL.HistoryPrompt.Describe(offer)

check("and says what is coming, and that nothing has arrived",
      "130 drops" in body and "Nothing has arrived yet" in body, body[:100])
check("AND STATES THE MERGE RULE BEFORE THE PRESS, not after",
      "Anything you already recorded is kept" in body
      and "takes their credit mark" in body,
      body[-200:])
check("and says how long it will take", "4 minutes" in body, body)

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
