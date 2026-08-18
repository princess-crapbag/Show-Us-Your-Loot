"""Pacing what this addon says to the guild, and the burst that broke a feature.

Logging in fired twenty-four addon messages inside one frame — a request and
eight absences, a request and thirteen raiders, and a keystone. The client
rate-limits addon traffic, says so in chat, and throws the overflow away.

THAT IS FATAL RATHER THAN UNTIDY. RosterSync and AbsenceSync both send one
entry per message and commit a set only when every piece has arrived, which is
right: a fragment would draw a raid team with people missing. It also means a
single discarded message leaves the set half-assembled forever. The roster
never lands, nothing errors, and the receiving screen looks exactly like a
roster nobody has shared. The only symptom is "it isn't working".

THE ASSERTION THAT MATTERS IS THE SECOND ONE. The first version of SendQueue
sent straight from Queue whenever the queue happened to be empty, and paced
only what was left over. Callers queue one entry at a time, so each call
emptied the queue before the next arrived and every message still went out at
once. The queue existed, its suite was green, and the burst was untouched. A
test that only checks "everything eventually arrives" passes in both worlds.

C_Timer is a no-op under the stub, so Drain is pumped by hand here. That is
deliberate rather than a workaround: what is being asserted is what happens
BETWEEN two sends, which a real timer would hide.

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


lua.execute(
    """
    local SYL = ShowUsYourLoot

    SENT = {}
    TICKS = 0

    C_ChatInfo.SendAddonMessage = function(prefix, payload, channel, target)
        table.insert(SENT, table.concat(
            { prefix, channel or '-', target or '-', payload }, '|'))
    end

    -- Counts arming rather than firing. One timer in flight at a time is the
    -- property; a second arm while one is pending would be a leak.
    C_Timer = {
        After = function(_, callback)
            TICKS = TICKS + 1
            PENDING = callback
        end,
    }

    function ClearSent() SENT = {}; TICKS = 0; PENDING = nil end
    function SentCount() return #SENT end
    function Sent(i) return SENT[i] end
    function Ticks() return TICKS end
    function Fire() if PENDING then local c = PENDING; PENDING = nil; c() end end
    """
)

G = lua.globals()
Q = SYL.SendQueue


def reset():
    Q.Reset()
    G.ClearSent()


# --- a single message still goes out --------------------------------------
reset()
Q.Queue("SYLTEST", "one", "GUILD")

check("queueing arms a timer rather than sending", G.SentCount() == 0,
      G.SentCount())
check("and one message is waiting", Q.Pending() == 1, Q.Pending())

Q.Drain()

check("draining sends it", G.SentCount() == 1, G.SentCount())
check("with prefix, channel and payload intact",
      G.Sent(1) == "SYLTEST|GUILD|-|one", G.Sent(1))
check("and nothing is left", Q.Pending() == 0, Q.Pending())

# --- THE BURST ------------------------------------------------------------
#
# Aimee's actual login: 24 messages from four modules in one frame. Not one of
# them may leave without a tick of its own.
reset()

for index in range(24):
    Q.Queue("SYLROST", "raider" + str(index), "GUILD")

check("A LOGIN BURST SENDS NOTHING SYNCHRONOUSLY", G.SentCount() == 0,
      G.SentCount())
check("all of it is queued", Q.Pending() == 24, Q.Pending())
check("and exactly one timer is in flight, not twenty-four",
      G.Ticks() == 1, G.Ticks())

# Pump one at a time. Each drain must release exactly one.
for expected in range(1, 25):
    Q.Drain()
    if G.SentCount() != expected:
        break

check("ONE MESSAGE PER DRAIN, NEVER MORE",
      G.SentCount() == 24 and Q.Pending() == 0,
      (G.SentCount(), Q.Pending()))
check("in the order they were queued",
      G.Sent(1).endswith("raider0") and G.Sent(24).endswith("raider23"),
      (G.Sent(1), G.Sent(24)))

# --- the timer re-arms itself while work remains --------------------------
reset()

for index in range(3):
    Q.Queue("SYLABS", "absence" + str(index), "GUILD")

G.Fire()

check("firing the timer sends one and re-arms", G.SentCount() == 1,
      G.SentCount())

G.Fire()
G.Fire()

check("and keeps going until the queue is empty",
      G.SentCount() == 3 and Q.Pending() == 0,
      (G.SentCount(), Q.Pending()))

G.Fire()

check("firing past the end sends nothing", G.SentCount() == 3, G.SentCount())
check("and draining an empty queue is safe and says so",
      Q.Drain() is False)

# --- the gate is re-checked at send time ----------------------------------
#
# A feature switched off, or a guild left, between queueing and a message's
# turn. Sending it late would be sending something the user has since said no
# to.
reset()

lua.execute("ALLOWED = true")
lua.execute(
    "GATE = function() return ALLOWED end"
)

Q.Queue("SYLROST", "before", "GUILD", None, G.GATE)
Q.Queue("SYLROST", "after", "GUILD", None, G.GATE)

Q.Drain()

check("a message passes while its gate holds", G.SentCount() == 1,
      G.SentCount())

lua.execute("ALLOWED = false")

Q.Drain()

check("A MESSAGE WHOSE GATE HAS CLOSED IS DROPPED, NOT SENT LATE",
      G.SentCount() == 1, G.SentCount())
check("and it still leaves the queue rather than blocking it",
      Q.Pending() == 0, Q.Pending())

# --- the cap --------------------------------------------------------------
#
# A queue that grows forever is worse than one that says it is full.
reset()

accepted = 0

for index in range(SYL.SendQueue.MAX + 25):
    if Q.Queue("SYLTEST", "flood" + str(index), "GUILD"):
        accepted += 1

check("the queue refuses past its cap", accepted == SYL.SendQueue.MAX,
      accepted)
check("and holds exactly that many", Q.Pending() == SYL.SendQueue.MAX,
      Q.Pending())

# --- rubbish in ------------------------------------------------------------
reset()

check("a missing payload is refused", Q.Queue("SYLTEST", None) is False)
check("and a missing prefix too", Q.Queue(None, "body") is False)
check("neither of which queues anything", Q.Pending() == 0, Q.Pending())

# --- the senders actually use it -------------------------------------------
#
# The whole fix is worth nothing if one module still calls SendAddonMessage
# directly, and that is invisible from behaviour: it would simply work, and
# burst.
CORE = Path(__file__).resolve().parent.parent / "Core"

for name in ("RosterSync", "AbsenceSync", "KeystoneSync",
             "KeystoneRequestSync"):
    source = (CORE / (name + ".lua")).read_text(encoding="utf-8")

    sends = [
        line for line in source.splitlines()
        if "C_ChatInfo.SendAddonMessage" in line
        and "and C_ChatInfo.SendAddonMessage" not in line
    ]

    check(name + " sends through the queue, not around it",
          not sends and "SendQueue.Queue" in source,
          sends or (name + " never calls SendQueue.Queue"))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
