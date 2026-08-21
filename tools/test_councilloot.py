"""Reading who else responded, out of RCLootCouncil.

WHY THIS IS THE SHAPE IT IS. Aimee, 2026-08-20: "i cant see who rolled
need/greed/mog on items." The client only ever reports the group-loot roll,
where under a council everybody passes and the master looter takes it. The real
answers happen inside RCLootCouncil.

And RCLootCouncil does not keep them unless you ask it to. "Send Session
Responses" defaults to false — its own description says it "can hurt comms
performance" — and with it off nothing anywhere records who responded, not even
RCLootCouncil's own history. Her install had never stored one, so the four
states below are all real and the difference between them is the whole point:
"not installed" must not nag, "off" must offer the fix, and "on but nothing for
this drop" must not claim the setting is wrong.

The fixtures encode responses the way ml_core.lua's GetSessionResponses does,
because that is what ends up in the saved variables and this addon has to read
it as found rather than as it would have written it.

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
lua.execute((CORE / "CouncilLoot.lua").read_text(encoding="utf-8"))

CouncilLoot = lua.globals().ShowUsYourLoot.CouncilLoot
failures = []

LINK = "|cnIQ4:|Hitem:268203::::::::90:253::3:3:6652|h[Hexing Spiritrender]|h|r"
OTHER_LINK = "|cnIQ4:|Hitem:999999::::::::90:253::3:3:1111|h[Other Thing]|h|r"


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       got: " + repr(detail))

        failures.append(label)


def drop(link=LINK, date="2026-08-18"):
    lua.execute(
        "Drop = { itemLink = %r, dateText = %r }" % (link, date)
    )
    return lua.globals().Drop


# --- no RCLootCouncil at all ----------------------------------------------
#
# The common case for anybody who does not run a council, and it must say
# nothing rather than advertise a setting in an addon they do not have.
lua.execute("RCLootCouncil = nil")

check("with no RCLootCouncil, nothing is present",
      CouncilLoot.IsPresent() is False)
check("and it cannot tell whether recording is on",
      CouncilLoot.IsRecordingResponses() is None)
check("the screen is told to say nothing",
      CouncilLoot.Describe(drop()).state == "absent")

# --- installed, but not recording -----------------------------------------
#
# Her install, and the reason she could not see who rolled.
lua.execute(
    """
    RCLootCouncil = {
        db = { profile = { sendSessionResponses = false } },
        GetHistoryDB = function() return {} end,
    }
    """
)

check("an installed RCLootCouncil is found", CouncilLoot.IsPresent() is True)
check("and it is not recording", CouncilLoot.IsRecordingResponses() is False)
check("which is a state of its own, not 'nothing here'",
      CouncilLoot.Describe(drop()).state == "off",
      CouncilLoot.Describe(drop()).state)

# The one write this file ever makes, and only from a button.
check("turning it on reports that it is on",
      CouncilLoot.StartRecordingResponses() is True)
check("and it really is", CouncilLoot.IsRecordingResponses() is True)
check("so the screen stops offering", CouncilLoot.Describe(drop()).state
      == "none", CouncilLoot.Describe(drop()).state)

# --- recording, with responses stored --------------------------------------
#
# Two of the eleven from her real guild night. The winner's row carries only
# ilvl and roll because RCLootCouncil keeps the rest on the award itself.
lua.execute(
    """
    RCLootCouncil = {
        db = { profile = { sendSessionResponses = true } },

        GetHistoryDB = function()
            return {
                ['Phreestyle-Area52'] = {
                    {
                        lootWon = %r,
                        date = '2026/08/18',
                        typeCode = 'default',
                        class = 'SHAMAN',
                        response = 'Greed',
                        votes = 3,
                        owner = 'Arcangila-Area52',
                        player = 'Phreestyle-Area52',
                        sessionResponses = {
                            ['Phreestyle-Area52'] = { ilvl = 285, roll = 71 },
                            ['Razorshift-Thrall'] = {
                                ilvl = 279, class = 'DRUID',
                                response = 1, roll = 44, votes = 1,
                            },
                            ['Jtkurayami-Stormrage'] = {
                                ilvl = 291, class = 'PRIEST',
                                response = 2, roll = 12, votes = 0,
                            },
                        },
                    },
                },
            }
        end,

        -- The id is meaningless without the item type, which is why this is
        -- asked of RCLootCouncil rather than mapped here.
        GetResponse = function(_, _, id)
            local TEXT = { [1] = 'Need', [2] = 'Greed', [3] = 'Mog' }

            return { text = TEXT[id] }
        end,
    }
    """ % LINK
)

described = CouncilLoot.Describe(drop())

check("responses are found", described.state == "responses", described.state)

rows = described.responses
by_name = {rows[i].name: rows[i] for i in range(1, len(rows) + 1)}

check("everybody who answered is listed", len(by_name) == 3, sorted(by_name))
check("the winner is marked",
      by_name["Phreestyle-Area52"].isWinner is True)
check("and takes their response from the award, not the response table",
      by_name["Phreestyle-Area52"].response == "Greed",
      by_name["Phreestyle-Area52"].response)

# THE POINT OF THE WHOLE FEATURE: who else wanted it, and how.
check("somebody who needed it says Need",
      by_name["Razorshift-Thrall"].response == "Need",
      by_name["Razorshift-Thrall"].response)
check("somebody who greeded says Greed",
      by_name["Jtkurayami-Stormrage"].response == "Greed",
      by_name["Jtkurayami-Stormrage"].response)
check("their rolls come through",
      by_name["Razorshift-Thrall"].roll == 44
      and by_name["Jtkurayami-Stormrage"].roll == 12)
check("and their item levels", by_name["Razorshift-Thrall"].ilvl == 279)
check("the winner sorts first",
      rows[1].name == "Phreestyle-Area52", rows[1].name)

# --- matching the right award ---------------------------------------------
check("a different item finds nothing",
      CouncilLoot.AwardFor(drop(link=OTHER_LINK)) is None)

# The same item can be awarded on two nights, and the link matches both.
check("the same item on another night is not this award",
      CouncilLoot.AwardFor(drop(date="2026-08-25")) is None)

check("a drop with no link at all is not a crash",
      CouncilLoot.AwardFor(drop(link="")) is None)

# --- stored raw, as it is on disk -----------------------------------------
#
# On a fresh login the entry carries only the packed SR strings; the decode
# runs on the comm that delivered it. RCLootCouncil owns that format, so this
# asks the module to unpack rather than unpacking it here — a second copy of
# somebody else's wire format goes wrong silently the first time they change it.
lua.execute(
    """
    DECODE_CALLS = 0

    RCLootCouncil.GetHistoryDB = function()
        return {
            ['Phreestyle-Area52'] = {
                {
                    lootWon = %r,
                    date = '2026/08/18',
                    typeCode = 'default',
                    response = 'Greed',
                    player = 'Phreestyle-Area52',
                    SR = { ['x'] = '279@11@1@44@1' },
                },
            },
        }
    end

    RCLootCouncil.GetModule = function(_, name)
        if name ~= 'RCLootHistory' then return nil end

        return {
            DecodeSessionResponses = function(_, entry)
                DECODE_CALLS = DECODE_CALLS + 1

                entry.sessionResponses = {
                    ['Razorshift-Thrall'] = {
                        ilvl = 279, class = 'DRUID',
                        response = 1, roll = 44, votes = 1,
                    },
                }
            end,
        }
    end
    """ % LINK
)

described = CouncilLoot.Describe(drop())

check("a raw entry is decoded by the addon that wrote it",
      described.state == "responses" and lua.globals().DECODE_CALLS == 1,
      (described.state, lua.globals().DECODE_CALLS))
check("and comes back readable",
      described.responses[1].response == "Need",
      described.responses[1].response)

# --- RCLootCouncil present but broken --------------------------------------
#
# A different major version, or mid-load. None of that is this addon's business
# to throw on: the drop detail window has a list to draw either way.
lua.execute(
    """
    RCLootCouncil = {
        db = { profile = { sendSessionResponses = true } },
        GetHistoryDB = function() error('nope') end,
    }
    """
)

check("a history call that errors is survived",
      CouncilLoot.Describe(drop()).state == "none",
      CouncilLoot.Describe(drop()).state)

lua.execute("RCLootCouncil = { }")

check("an RCLootCouncil with no database at all is survived",
      CouncilLoot.Describe(drop()).state == "none")
check("and reports that it cannot tell, rather than 'off'",
      CouncilLoot.IsRecordingResponses() is None)
check("turning it on then fails honestly",
      CouncilLoot.StartRecordingResponses() is False)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
