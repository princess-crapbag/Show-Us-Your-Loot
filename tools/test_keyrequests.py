"""Key requests go to one person, and only Denied can be asked again.

Two rules carry this feature and both are social rather than technical, which
is exactly why they need pinning down in a test — nothing about the code looks
wrong when they break.

IT NEVER BROADCASTS. A request is whispered to one named person. A guild-wide
"three people want this key" turns a favour into an auction, and the holder is
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

    function Reset()
        SENT, PREFIXES = {}, {}
        ONLINE = { ['Dravok'] = true, ['Selunne'] = true }

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

check("asking an online guildie works", R.Ask("Dravok", "TANK") is True)
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

ok, reason = R.Ask("Nobody", "DPS")

check("asking somebody offline is refused", ok is False)
check("and says so", reason == "They are offline.", reason)

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

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
