"""The keystone wire format, which parses input from other people's machines.

Everything decoded here arrived over an addon channel from a client this one
does not control, so every field is checked before it reaches a comparator or
a display string. The cases below are the ones a hostile or simply older
client can produce: a version that is not ours, a truncated line, a level that
is not a number, and the "no key" case that has to travel as a real message
rather than as silence.

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
lua.execute("ShowUsYourLootDB = {}")
lua.execute("function time() return 1700000000 end")
lua.execute("function IsInGuild() return true end")

# The client counts down to its own weekly reset, so the stale test works in
# every region without knowing which weekday it falls on. 3 days out here.
lua.execute("""
    C_DateAndTime = {
        GetSecondsUntilWeeklyReset = function() return 3 * 24 * 60 * 60 end,
    }
""")
lua.execute("function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end } end")

# Every attempt to talk to the guild is recorded rather than performed.
lua.execute(
    """
    Sent = {}
    Registered = {}

    C_ChatInfo = {
        SendAddonMessage = function(prefix, payload, channel)
            table.insert(Sent, prefix .. '|' .. channel .. '|' .. payload)
        end,

        RegisterAddonMessagePrefix = function(prefix)
            table.insert(Registered, prefix)
        end,
    }
    """
)

# KeystoneSync queues rather than sending directly now, because a keystone
# leaves at login alongside the absences and the roster and the client counts
# all of them against one limit. Loaded for real rather than stubbed, so this
# suite exercises the pacing instead of pretending it is not there.
lua.execute("ShowUsYourLoot.DebugPrint = function() end")
lua.execute("C_Timer = { After = function() end }")
lua.execute((CORE / "SendQueue.lua").read_text(encoding="utf-8"))

lua.execute((CORE / "KeystoneSync.lua").read_text(encoding="utf-8"))

sync = lua.globals().ShowUsYourLoot.KeystoneSync
failures = []


def check(label, ok):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def decode(payload):
    result = sync.Decode(payload)

    return result if isinstance(result, tuple) else (result,)


# --- silence until asked --------------------------------------------------
#
# This is the only thing in the addon that talks to the whole guild rather
# than to a raid group, so "off means silent" is a property worth a test and
# not just a default. A later edit to Features.DEFAULTS could flip it without
# anyone noticing; this fails if it does.

lua.execute(
    """
    ShowUsYourLoot.Keystone = {
        GetOwn = function()
            return { mapID = 375, level = 12, class = 'MAGE' }
        end,

        CharacterKey = function() return 'Me' end,
        Update = function() end,
    }
    """
)


def sent():
    return list(lua.globals().Sent.values())


def registered():
    return list(lua.globals().Registered.values())


# Enable() has not been called, which is every install that has not turned the
# feature on. Each of these is a path that ends in a broadcast when it is on.
sync.Announce()
sync.Request()
sync.OnOwnKeyChanged()

check("nothing is sent while the feature is off", len(sent()) == 0)
# Not registering the prefix means it cannot receive either, not merely that
# it declines to send.
check("the addon message prefix is not even registered", len(registered()) == 0)

sync.Enable()

# Nothing leaves in the frame that asked for it. A keystone is one message and
# was never the burst on its own, but it goes out at login beside the absences
# and the roster and the client counts them all against one limit — so it is
# paced with everything else. See Core/SendQueue.lua.
check("enabling queues rather than sending", len(sent()) == 0)


def flush():
    """Pump the send queue dry. C_Timer is a no-op under the stub."""
    while lua.globals().ShowUsYourLoot.SendQueue.Drain():
        pass


flush()

check("turning it on announces and asks, and nothing more", len(sent()) == 2)
check(
    "both go to GUILD on our own prefix",
    all(line.startswith("SYLKEY|GUILD|") for line in sent()),
)
check(
    "the announce carries only dungeon, level and class",
    sent()[0] == "SYLKEY|GUILD|1|K|375|12|MAGE",
)

lua.execute("Sent = {} Registered = {}")

# --- round trip -----------------------------------------------------------
encoded = sync.Encode(375, 12, "MAGE")
check("a key encodes to one short line", encoded == "1|K|375|12|MAGE")

kind, map_id, level, klass = decode(encoded)
check("and decodes back", (kind, map_id, level, klass) == ("K", 375, 12, "MAGE"))

# --- no key ---------------------------------------------------------------
# Has to travel as a message: silence is indistinguishable from not running
# the addon, and last week's key would stand forever.
kind, map_id, level, klass = decode(sync.Encode(None, None, "PRIEST"))
check("no key still sends", kind == "K")
check("and arrives as no key rather than as a zero", map_id is None and level is None)

# --- requests -------------------------------------------------------------
check("a request decodes", decode("1|?|")[0] == "?")

# --- input that must not get through --------------------------------------
REJECTED = [
    ("a future version", "2|K|375|12|MAGE"),
    ("no version", "K|375|12|MAGE"),
    ("a truncated line", "1|K|375"),
    ("a level that is not a number", "1|K|375|twelve|MAGE"),
    ("a map id that is not a number", "1|K|abc|12|MAGE"),
    ("an empty string", ""),
    ("an unknown kind", "1|Z|375|12|MAGE"),
]

for label, payload in REJECTED:
    check("refused: " + label, decode(payload)[0] is None)

check("refused: a non-string", decode(None)[0] is None)

# --- storage and staleness ------------------------------------------------
sync.Remember("Aimee-Silvermoon", 375, 12, "MAGE")
sync.Remember("Someone-Else", 375, 20, "PRIEST")

listed = list(sync.List().values())
check("both are remembered", len(listed) == 2)
check("highest key sorts first", listed[0].level == 20)

# The reset is 3 days away, so this week began 4 days ago. A key from 5 days
# ago predates it and is gone; one from 2 days ago is still good.
lua.execute(
    "ShowUsYourLootDB.guildKeystones['Someone-Else'].at = 1700000000 - (5 * 24 * 60 * 60)"
)

listed = list(sync.List().values())
check("a key from before this week's reset is dropped", len(listed) == 1)
check(
    "and dropped from the store, not just the list",
    lua.globals().ShowUsYourLootDB.guildKeystones["Someone-Else"] is None,
)

# A key from inside this week survives — the guard must not be "older than
# seven days", which would keep a key from before the reset.
sync.Remember("Recent-Key", 375, 11, "MONK")
lua.execute(
    "ShowUsYourLootDB.guildKeystones['Recent-Key'].at = 1700000000 - (2 * 24 * 60 * 60)"
)
check("a key from after the reset is kept", len(list(sync.List().values())) == 2)

# And with no C_DateAndTime at all, the flat week still works.
lua.execute("C_DateAndTime = nil")
lua.execute(
    "ShowUsYourLootDB.guildKeystones['Recent-Key'].at = 1700000000 - (8 * 24 * 60 * 60)"
)
check("without the API it falls back to seven days", len(list(sync.List().values())) == 1)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
