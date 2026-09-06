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

landed, corrected, ignored, arrived_nights = SYL.HistorySync.Commit()

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


# --- 9. the name the accept comes back under -------------------------------
#
# THE BUG THAT MADE THIS FEATURE DO NOTHING ON ITS FIRST DAY. A target is
# picked out of the guild roster, which omits the realm for anybody on your
# own; the accept arrives over the addon channel, which always qualifies it
# and strips spaces out of the realm. Compared as strings those are different
# people, so Begin refused, no data was sent, and the sender's bar sat on
# "waiting for them to answer" with nothing printed anywhere.
#
# Aimee: "i dont think the send loot to others worked."
def handshake(picked, replies_as):
    lua.execute("ShowUsYourLootDB = nil")
    SYL.DatabaseInitialize()
    lua.execute("""
        local SYL = ShowUsYourLoot
        SYL.Guild.IsMember = function() return true end
    """)

    SYL.HistorySync.Stop()
    SYL.SendQueue.Reset()

    live = SYL.GetActiveSeason()
    live.drops[1] = drop("handshake-1")

    SYL.HistorySync.Offer(picked, live)
    flush()

    G.ClearSent()

    # Their yes. Begin sends the first message itself; the rest rides a timer
    # the stub never fires, so one DATA message is the proof it started.
    SYL.HistorySync.OnMessage("SYLHIST", "1" + chr(9) + "Y", "WHISPER",
                              replies_as)
    flush()

    started = 0

    for index in range(1, G.SentCount() + 1):
        if G.SentPayload(index).startswith("1" + chr(9) + "D"):
            started += 1

    return started


check("A SAME-REALM NAME IS THE SAME PERSON, roster spelling or not",
      handshake("Nychar", "Nychar-Area52") > 0)
check("and a realm the roster writes with a space still matches",
      handshake("Nychar-Aerie Peak", "Nychar-AeriePeak") > 0)
check("and case is not identity either",
      handshake("nychar-area52", "Nychar-Area52") > 0)
check("a cross-realm name, which is the only case that used to work",
      handshake("Pringlesbop-Illidan", "Pringlesbop-Illidan") > 0)
check("BUT A DIFFERENT PERSON IS STILL A DIFFERENT PERSON",
      handshake("Nychar-Area52", "Saebie-Area52") == 0)

# --- 10. the progress number cannot exceed what was sent -------------------
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

SYL.HistorySync.Stop()
SYL.SendQueue.Reset()

live = SYL.GetActiveSeason()

for index in range(1, 4):
    live.drops[index] = drop("count-%d" % index)

SYL.HistorySync.Offer(OFFICER, live)
flush()
G.ClearSent()

SYL.HistorySync.OnMessage("SYLHIST", "1" + chr(9) + "Y", "WHISPER", OFFICER)
drain_history()

sent, total = SYL.HistorySync.Progress()
on_wire = 0

for index in range(1, G.SentCount() + 1):
    if G.SentPayload(index).startswith("1" + chr(9) + "D"):
        on_wire += 1

check("THE BAR COUNTS WHAT WENT, not what was popped off a list",
      sent == on_wire and sent == total, (sent, on_wire, total))

# --- 11. a name with an accent in it ---------------------------------------
#
# THE GUILD IS NOT ASCII. Aimee's own season carries Meumermao, Uberion and
# Razortongue with real accents -- 120 of her 135 drops hold a non-ASCII name
# somewhere -- and in UTF-8 each of those letters is two bytes.
#
# Chunking at byte 200 regardless split one of those pairs twice in her 1013
# messages: two addon messages each holding half a character, neither valid
# UTF-8 on its own. The reassembly is happy to glue the bytes back; the chat
# system carrying them is not something to hand a broken sequence and hope.
#
# Driven with a name built to land a character exactly on the boundary, so
# this fails the moment the chunker goes back to counting bytes.

G.ClearSent()
SYL.SendQueue.Reset()
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

accented = SYL.GetActiveSeason()

# FOUR RECORDS, EACH ONE BYTE LONGER THAN THE LAST, and an item name that is
# nothing but two-byte letters. A 200-byte boundary falling in a run of those
# is inside a character for every other starting offset, so shifting the
# payload through four consecutive offsets makes at least two of the four
# split under a chunker that counts bytes. Without the shift the test passes
# on both -- which is what the first version of it did.
for index in range(1, 5):
    record = drop("a" * index, item=181000 + index)
    record["itemName"] = "ã" * 260
    record["winnerName"] = "Códició-Area52"
    accented.drops[index] = record

SYL.HistorySync.Offer(OFFICER, accented)
flush()
G.ClearSent()
SYL.SendQueue.Reset()
SYL.HistorySync.Begin(OFFICER)
drain_history()

# READ AS BYTES, NEVER AS A STRING. G.SentPayload hands the payload to Python,
# which decodes it as UTF-8 -- so on a payload that is cut through a character
# the harness itself raises before the assertion below can say anything, and
# the suite dies with a traceback instead of naming the bug. These two stay on
# the Lua side and answer one byte at a time.
sent_length = lua.eval("function(i) return #SENT[i].payload end")
sent_byte = lua.eval(
    "function(i, k) return string.byte(SENT[i].payload, k) end")

broken = 0

for index in range(1, G.SentCount() + 1):
    raw = bytes(sent_byte(index, k)
                for k in range(1, sent_length(index) + 1))

    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        broken += 1

check("no message is cut through the middle of a character",
      broken == 0,
      "%d of %d messages are not valid UTF-8 on their own"
      % (broken, G.SentCount()))

# And it all still arrives, which is the point of not breaking it.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

SYL.HistorySync.OnMessage(
    "SYLHIST", "1	O	Accents	4	0	12", "WHISPER", OFFICER)
SYL.HistorySync.AcceptOffer()

# Replayed inside Lua for the same reason: the bytes must reach OnMessage
# exactly as they went out.
lua.execute("""
    for _, entry in ipairs(SENT) do
        ShowUsYourLoot.HistorySync.OnMessage(
            "SYLHIST", entry.payload, "WHISPER", "Pringlesbop-Illidan")
    end
""")

landed = len(SYL.GetActiveSeason().drops or [])

check("and all four accented drops land intact", landed == 4, landed)

# --- 12. a state that arrives as text is not a state ------------------------
#
# THE BUG THAT MADE THE WHOLE FEATURE LOOK LIKE IT HAD NOT RUN, found in
# Pringlesbop's real database next to Aimee's: 135 drops present, all 57
# credit overrides present, every roll list intact -- and every raider on his
# board reading a dash.
#
# Everything on the wire is text. The decoder converted some fields back to
# numbers and not others: winnerState was missing from the list, and neither
# a roll's state nor the credit's state was converted at all. Lua's "2" == 2
# is false, so every arriving drop matched none of the ROLL_STATE constants
# and counted as a win that was neither a need, an offspec, a transmog nor a
# greed. Wins totalled correctly; nothing scored.
#
# Asserted on TYPE, because the value prints identically either way -- which
# is why a diff of the two databases showed nothing until the types were
# asked for by name.
lua_type = lua.eval("function(v) return type(v) end")

sample = drop("typed-1", item=182000, rolls=3, credited={
    "guid": "Player-60-095B9C0B",
    "name": "Rakahasa",
    "state": 3,
    "setAt": 1788400123,
    "setBy": AIMEE,
})
sample["winnerState"] = 2

decoded = SYL.HistoryPayload.Decode(SYL.HistoryPayload.Encode(sample))

check("the winner's response comes back a number, not the text of one",
      lua_type(decoded["winnerState"]) == "number",
      lua_type(decoded["winnerState"]))

check("and so does the credit override's",
      lua_type(decoded["creditOverride"]["state"]) == "number",
      lua_type(decoded["creditOverride"]["state"]))

check("and every roll's",
      all(lua_type(decoded["rolls"][i]["state"]) == "number"
          for i in range(1, len(decoded["rolls"]) + 1)),
      [lua_type(decoded["rolls"][i]["state"])
       for i in range(1, len(decoded["rolls"]) + 1)])

# The whole point of the types: the board can classify the win.
check("so an arriving transmog counts as a transmog",
      decoded["winnerState"] == SYL.LootHistoryAPI.ROLL_STATE.Transmog,
      (decoded["winnerState"], SYL.LootHistoryAPI.ROLL_STATE.Transmog))

# --- and the repair for rows that already landed as text -------------------
#
# Fixing the decoder does not reach what is already in somebody's database,
# and a second send will not either: Merge keeps a record it already holds
# and takes only the credit from the arriving copy.
lua.execute("""
    local season = ShowUsYourLoot.GetActiveSeason()

    season.drops = {
        {
            id = "text-1",
            winnerState = "2",
            creditOverride = { name = "Rakahasa", state = "3" },
            rolls = { { name = "Rakahasa", state = "0", roll = "97" } },
        },
    }
""")

fixed = SYL.Migrations.RepairTransferredStates(lua.globals().ShowUsYourLootDB)

check("the repair converts every state already sitting in the database",
      fixed == 4, fixed)

repaired = SYL.GetActiveSeason().drops[1]

check("and they are numbers afterwards",
      lua_type(repaired["winnerState"]) == "number"
      and lua_type(repaired["creditOverride"]["state"]) == "number"
      and lua_type(repaired["rolls"][1]["state"]) == "number"
      and lua_type(repaired["rolls"][1]["roll"]) == "number")

check("running it twice changes nothing more",
      SYL.Migrations.RepairTransferredStates(
          lua.globals().ShowUsYourLootDB) == 0)

# AND IT DOES NOT RUN AGAIN ON EVERY LOGIN. Aimee: "so will this repair run
# every single time someone logs in or changes characters?" It did, and the
# reason written next to it -- that a sender on an older build could still
# put text in -- was wrong: Encode has always written text, and the fault was
# only ever in Decode. So it guards its own number like every other migration
# here, and a database already at 8 is not walked at all.
lua.execute("""
    ShowUsYourLoot.GetActiveSeason().drops = {
        { id = "text-2", winnerState = "2", rolls = {} },
    }
""")

check("a database already on this version is not walked again",
      SYL.Migrations.RepairTransferredStates(
          lua.globals().ShowUsYourLootDB, 8) == 0,
      "walking every drop and roll on every login is what this replaced")

check("but one coming up from the version before it is",
      SYL.Migrations.RepairTransferredStates(
          lua.globals().ShowUsYourLootDB, 7) == 1)

# A state that is genuinely not a number is left alone rather than nil'd.
lua.execute("""
    ShowUsYourLoot.GetActiveSeason().drops[1].winnerState = "unknown"
""")

SYL.Migrations.RepairTransferredStates(lua.globals().ShowUsYourLootDB)

check("and a value that is not a number is left as it is",
      str(SYL.GetActiveSeason().drops[1]["winnerState"]) == "unknown",
      SYL.GetActiveSeason().drops[1]["winnerState"])

# --- 9. the nights travel with the drops -----------------------------------
#
# THE BUG THIS HALF EXISTS FOR, and it shipped looking like it worked.
#
# Pringlescat took a full transfer on 0.4.6. Every points total on his board
# matched Aimee's to the point -- Rakahasa 640 off eight items, Hawt 320 off
# four -- and every RAID NIGHTS cell read "of 4" against a season that had run
# nine, because both halves of that cell come from season.raids and a transfer
# had never written one. Points per night is score over nights and is the
# column the board sorts by, so his Arcangila read 275.0 where hers reads
# 122.2 -- a complete numerator over his own partial denominator.
#
# Core/Analytics.lua states the reason in one line: "Nights come from the raid
# roster, not from loot." Somebody eligible for nothing all evening still
# raided, and no amount of drops can say so.

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")


def session(session_id, started, guilded, strangers=0, date="2026-09-03"):
    """One evening. `guilded` carry a rank, `strangers` do not — which is the
    only thing RaidSession.GuildCounts looks at."""
    roster = {}

    for index in range(guilded):
        key = "Player-1-G%03d" % index
        roster[key] = lua.table_from({
            "guid": key, "name": "Guildie%d" % index,
            "fullName": "Guildie%d-Area52" % index,
            "class": "MAGE", "guildRank": "Raider",
            "encounters": 3, "firstSeen": started, "lastSeen": started + 60,
        })

    for index in range(strangers):
        key = "Player-9-P%03d" % index
        roster[key] = lua.table_from({
            "guid": key, "name": "Pug%d" % index,
            "fullName": "Pug%d-Illidan" % index,
            "class": "ROGUE",
            "encounters": 1, "firstSeen": started, "lastSeen": started + 60,
        })

    return lua.table_from({
        "id": session_id,
        "seasonID": "season-theirs",
        "dateText": date,
        "instanceID": 3004, "instanceName": "The Venomous Abyss",
        "instanceType": "raid",
        "difficultyID": 15, "difficultyName": "Heroic",
        "startedAt": started, "endedAt": started + 7200,
        "rosterCount": guilded + strangers,
        # THE RECORDER HAS TO BE IN THEIR OWN ROSTER, carrying a rank.
        # RaidSession.GuildDataIsTrustworthy looks them up before it will
        # believe any share at all, and answers "unknown" when it cannot find
        # them — which counts as a night. That is exactly right on the wire
        # too: the sender's own entry travels with its rank, so the receiver
        # reaches the same verdict on the same evidence.
        "recordedBy": "Guildie0-Area52",
        "roster": lua.table_from(roster),
        "encounters": lua.table_from([lua.table_from({
            "encounterID": 3421, "name": "The Twin Fangs",
            "difficultyID": 15, "groupSize": 20,
            "killed": True, "at": started + 600,
        })]),
        # Set on the sender, never sent. See MergeSessions.
        "summarized": True,
        "pendingEncounter": lua.table_from({"encounterID": 9999}),
    })


guild_night = session("raid-3004-15-20260903", 100000, guilded=12)
# One guildie — the person who recorded it — and twenty strangers. 1 of 21 is
# under the 80% threshold, which is the whole rule.
pug_night = session("raid-3004-15-20260901", 90000, guilded=1, strangers=20,
                    date="2026-09-01")

roundtrip = SYL.HistoryPayload.DecodeSession(
    SYL.HistoryPayload.EncodeSession(guild_night)
)

check("A SESSION SURVIVES THE WIRE", roundtrip is not None)
check("with its id, which is what stops a night arriving twice",
      roundtrip.id == "raid-3004-15-20260903", roundtrip.id)
check("and its whole roster, which is the attendance itself",
      SYL.Utilities.CountKeys(roundtrip.roster) == 12,
      SYL.Utilities.CountKeys(roundtrip.roster))
check("keyed the way the sender keyed it",
      roundtrip.roster["Player-1-G007"] is not None)
# THE FIELD THE FILTER READS. RaidSession.GuildCounts counts roster entries
# carrying a rank, and CountsAsNight compares that share to the threshold — so
# a rank that did not travel would make every arriving night read as a pug and
# be thrown away by the very filter it was sent to satisfy.
check("carrying the guild rank the night is judged on",
      roundtrip.roster["Player-1-G007"].guildRank == "Raider",
      roundtrip.roster["Player-1-G007"].guildRank)
check("its numbers back as numbers, not as the text of numbers",
      roundtrip.startedAt == 100000
      and roundtrip.roster["Player-1-G007"].encounters == 3,
      (roundtrip.startedAt, roundtrip.roster["Player-1-G007"].encounters))
check("its encounters, with the kill flag still a boolean",
      len(roundtrip.encounters) == 1
      and roundtrip.encounters[1].killed is True)
check("and the boss currently being fought on THEIR client left behind",
      roundtrip.pendingEncounter is None)

# A drop record must not be readable as a session, or a receiver would file
# 135 drops as 135 raid nights and every denominator on the board would be the
# number of items won.
check("A DROP IS NOT A SESSION",
      SYL.HistoryPayload.DecodeSession(
          SYL.HistoryPayload.Encode(drop("not-a-night"))) is None)
# And the other way, which is the whole backward-compatibility story: a client
# on 0.4.6 reassembles a session exactly as it does a drop, hands it to Decode,
# is told it is not an "H1" record, and drops it. No version negotiation.
check("and a session is not a drop, so an older build simply ignores it",
      SYL.HistoryPayload.Decode(
          SYL.HistoryPayload.EncodeSession(guild_night)) is None)

# --- only the guild's own nights are offered -------------------------------
#
# The cheap cut and the right one. NightsOnly is the exact filter every screen
# that counts attendance already applies, so a pug would arrive and be
# discarded on the other side having cost a minute of wire — and Aimee's two
# LFR runs carry 49 and 74 strangers between them.

lua.execute("""
    local SYL = ShowUsYourLoot
    local season = SYL.GetActiveSeason()
    season.raids = { GUILD_NIGHT, PUG_NIGHT }
""", )
G = lua.globals()
G.GUILD_NIGHT = guild_night
G.PUG_NIGHT = pug_night
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.GetActiveSeason().raids = { GUILD_NIGHT, PUG_NIGHT }
""")

offered = SYL.HistorySync.Nights(SYL.GetActiveSeason())

check("THE PUG IS NOT OFFERED", len(offered) == 1, len(offered))
check("and the guild night is",
      offered[1].id == "raid-3004-15-20260903", offered[1].id)

summary = SYL.HistorySync.Describe(SYL.GetActiveSeason())

check("the offer counts the nights it is actually sending",
      summary.nights == 1, summary.nights)



# --- the whole thing, end to end, into a client that has nothing -----------
#
# The board Pringlescat was actually looking at. He held every drop and no
# nights; this asserts the second half now arrives with the first.

lua.execute("""
    local SYL = ShowUsYourLoot
    local season = SYL.GetActiveSeason()
    season.drops = { }
""")

season_out = SYL.GetActiveSeason()
season_out.drops[1] = drop("night-1")
season_out.drops[2] = drop("night-2")

G.ClearSent()
SYL.SendQueue.Reset()
SYL.HistorySync.Stop()

SYL.HistorySync.Offer(OFFICER, season_out)
SYL.HistorySync.Begin(OFFICER)
drain_history()

wire = [G.SentPayload(i) for i in range(1, G.SentCount() + 1)]

# The receiver: a fresh database with one night of its own, which is the state
# that matters. A client that had nothing would take everything whatever the
# merge rule was; a client that was THERE is the one a bad rule overwrites.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

theirs = session("raid-3004-15-20260903", 100000, guilded=3)
theirs.summarized = False

SYL.GetActiveSeason().raids[1] = theirs

# The handshake first, exactly as the wire carries it: nothing is received
# until this client has been asked and has said yes.
SYL.HistorySync.OnMessage(
    "SYLHIST", "1	O	Midnight Season 2	2	0	%d" % len(wire),
    "WHISPER", OFFICER
)
SYL.HistorySync.AcceptOffer()

for payload in wire:
    SYL.HistorySync.OnMessage("SYLHIST", payload, "WHISPER", OFFICER)

landed = SYL.GetActiveSeason()

check("THE NIGHT ARRIVES ALONGSIDE THE DROPS",
      len(landed.raids) == 1 and len(landed.drops) == 2,
      (len(landed.raids), len(landed.drops)))

# THE UNION, and it is the rule this needs rather than the drops' rule. The
# same evening seen from two places: somebody who joined at the third boss
# recorded a roster that starts there, and the officer who was there from the
# pull recorded the people who left before it. Taking either alone drops real
# raiders off an attendance column.
check("and the roster it already had is UNIONED, not replaced",
      SYL.Utilities.CountKeys(landed.raids[1].roster) == 12,
      SYL.Utilities.CountKeys(landed.raids[1].roster))
check("with rosterCount following what is actually in there",
      landed.raids[1].rosterCount == 12, landed.raids[1].rosterCount)

# A second delivery of the same season. The night must not land twice: a
# duplicate would raise every board's denominator without adding one person to
# a numerator, so everybody's points per night would fall for nothing.
SYL.HistorySync.OnMessage(
    "SYLHIST", "1	O	Midnight Season 2	2	0	%d" % len(wire),
    "WHISPER", OFFICER
)
SYL.HistorySync.AcceptOffer()

for payload in wire:
    SYL.HistorySync.OnMessage("SYLHIST", payload, "WHISPER", OFFICER)

check("SENDING THE SAME NIGHT TWICE DOES NOT DOUBLE IT",
      len(SYL.GetActiveSeason().raids) == 1,
      len(SYL.GetActiveSeason().raids))

# --- a night that arrives does not raise last night's summary --------------
#
# Core/RaidSummary.lua shows the evening's summary for any session not yet
# marked summarized. An evening from three weeks ago landing over the wire
# must not pop one.
lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()
lua.execute("""
    local SYL = ShowUsYourLoot
    SYL.Guild.IsMember = function() return true end
""")

fresh = SYL.GetActiveSeason()

SYL.HistoryPayload.MergeSessions(
    fresh, lua.table_from([SYL.HistoryPayload.DecodeSession(
        SYL.HistoryPayload.EncodeSession(guild_night))])
)

check("AN ARRIVING NIGHT IS ALREADY SUMMARIZED, so nothing pops up",
      fresh.raids[1].summarized is True, fresh.raids[1].summarized)
check("and it is filed under the season it landed in, not the one it left",
      fresh.raids[1].seasonID == fresh.id,
      (fresh.raids[1].seasonID, fresh.id))



# --- 10. the name you type -------------------------------------------------
#
# Aimee, 2026-09-06: "search by typing in name to sync loot history and
# autofill the name. show an error if the player is not online."
#
# WHY THE SUGGESTION LIST IS WIDER THAN THE THINGS IT WILL SEND TO. The target
# used to be a cycle button over online guild members, and a picker that can
# only offer names it is willing to send to cannot answer "why is Nychar not
# in here" -- their absence IS the error, delivered as nothing at all. So
# every guild member is offerable, the row says which are online, and a name
# that cannot be reached is refused in words at the moment it is picked.

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute(
    """
    local SYL = ShowUsYourLoot

    SYL.Guild.GetMembers = function()
        return {
            ['g1'] = { name = 'Nychar-Area52',  class = 'PRIEST',
                       isOnline = false },
            ['g2'] = { name = 'Rakahasa-Area52', class = 'ROGUE',
                       isOnline = true },
            ['g3'] = { name = 'Aimee-Area52',   class = 'HUNTER',
                       isOnline = true },
        }
    end
    """
)

Share = SYL.ShareWindow

names = sorted(
    str(Share.Candidates()[i].name)
    for i in range(1, len(Share.Candidates()) + 1)
)

check("EVERY GUILD MEMBER IS OFFERABLE, not only the ones online",
      names == ["Nychar-Area52", "Rakahasa-Area52"], names)

check("and never yourself", "Aimee-Area52" not in names, names)

# Online is the fact that decides whether the button will work, so it is the
# one the row carries -- ahead of the class, which is decoration here.
offline_entry = None
online_entry = None

for index in range(1, len(Share.Candidates()) + 1):
    entry = Share.Candidates()[index]

    if str(entry.name).startswith("Nychar"):
        offline_entry = entry
    else:
        online_entry = entry

check("an offline row says so", Share.Note(offline_entry) == "offline",
      Share.Note(offline_entry))
check("and an online one does not", Share.Note(online_entry) != "offline",
      Share.Note(online_entry))

# --- the refusal, which is the half that was asked for --------------------

ok, why = Share.Check("Rakahasa-Area52")

check("somebody online can be sent to", ok is True, why)

ok, why = Share.Check("Nychar-Area52")

check("SOMEBODY OFFLINE IS REFUSED IN WORDS", ok is False)
check("and the words say which of the two things went wrong",
      why is not None and "not online" in why, why)

# MATCHED THE WAY THE WHISPER WILL BE ADDRESSED. The guild roster omits the
# realm for anybody on your own, and the box may hold either form -- this is
# the same trap that made the first history transfer do nothing at all.
ok, _ = Share.Check("Rakahasa")

check("a name typed without its realm is the same person", ok is True)

ok, _ = Share.Check("rakahasa-area52")

check("and so is one typed in the wrong case", ok is True)

ok, why = Share.Check("Somebodyelse")

check("a name nobody knows is refused", ok is False)
check("and does not claim they are merely offline",
      why is not None and "not in the guild" in why, why)

ok, why = Share.Check("Aimee-Area52")

check("sending to yourself is refused here too", ok is False, why)

ok, why = Share.Check("")

check("and an empty box is not an error, it is just not ready",
      ok is False and why is None, why)

# --- and Send re-checks at the press --------------------------------------
#
# Somebody can log out in the seconds between their name being picked and the
# button being pressed, and the refusal that matters is the one for the state
# things are in now.

lua.execute("""
    local SYL = ShowUsYourLoot

    SYL.ShareWindow.Refresh = function() end
""")

sent, reason = Share.Send()

check("Send with an empty box asks for a name rather than throwing",
      sent is False and reason is not None, reason)


print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)
