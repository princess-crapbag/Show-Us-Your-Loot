"""What is allowed to reset a drought, run against the shipped DueList.

The due list is the headline claim on the front of the README and it had no
test at all. This covers the one rule the whole ranking turns on: an upgrade
resets your clock only if it came from content that counts as a raid night.

That rule used to be applied to one side of the sum. Nights came from
RaidSession.RaidsOnly, which excludes Timewalking, Story, Event and Follower
difficulties; upgrades came from every drop ever recorded, with no such test.
A Timewalking raid — group loot, real Need rolls, epic gear — therefore wiped
a raider's drought without adding a night, and the person the list exists to
surface dropped off it. Every difficulty below is checked in both directions.

Core/Utilities.lua and Core/LootHistoryAPI.lua are loaded for real, so the
difficulty tables and the Need/offspec rule under test are the shipped ones
rather than a copy that can drift. The registry and the roster are stubbed:
they are someone else's behavior.

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
lua.execute("ShowUsYourLootDB = { settings = {} }")

# GetItemInfo's 14th return is bindType; 2 is Bind on Equip. Stubbed off the
# link text so a fixture can ask for either, and returning nothing at all is
# the uncached case the real client gives for an item it has not seen.
lua.execute(
    """
    C_Item = {
        GetItemInfo = function(link)
            if link == 'uncached' then
                return nil
            end

            local bindType = 1

            if link == 'boe' then
                bindType = 2
            elseif link == 'warbound' then
                -- Enum.ItemBind.ToWoWAccount. Account gear rather than this
                -- character's upgrade, so excluded like a BoE.
                bindType = 9
            elseif link == 'warbounduntilequipped' then
                bindType = 8
            end

            return 'name', link, 4, 600, 80, '', '', 1, '', '', 0, 4, 1,
                bindType
        end,
    }
    """
)

for module in ("Utilities.lua", "LootHistoryAPI.lua"):
    lua.execute((CORE / module).read_text(encoding="utf-8"))

# Stubs. ResolveToMain is identity because alt folding is tested by its own
# behavior, not here; RaidsOnly mirrors RaidSession.IsRaidSession, which is
# the same IsRaidContent call the fix now makes on the drops side.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    SYL.Players = {
        ResolveToMain = function(key) return key end,
        Get = function() return nil end,
    }

    SYL.PersonalLoot = {
        NameKey = function(name) return name end,
    }

    -- Identity, because no fixture here has been traded. The real one hands
    -- back the recipient for a drop that was; that behavior has its own
    -- suite in test_tradetracker, and stubbing it keeps this file about the
    -- one rule it was written for.
    SYL.TradeTracker = {
        CreditedIdentity = function(_, rawIdentity) return rawIdentity end,
    }

    SYL.RaidSession = {
        NightKey = function(session) return session.nightKey end,

        RaidsOnly = function(sessions)
            local kept = {}

            for _, session in ipairs(sessions or {}) do
                if SYL.Utilities.IsRaidContent(
                    session.instanceType, session.difficultyID
                ) then
                    table.insert(kept, session)
                end
            end

            return kept
        end,
    }
    """
)

lua.execute((CORE / "DueList.lua").read_text(encoding="utf-8"))

DAY = 86400

# Three Mythic raid nights, one player present at all of them.
lua.execute(
    """
    function BuildScenario(dropInstanceType, dropDifficultyID, dropAt, itemLink)
        local roster = { P1 = { guid = 'P1', name = 'Aimee', class = 'MAGE' } }
        local sessions = {}

        for night = 1, 3 do
            table.insert(sessions, {
                startedAt = night * 86400,
                nightKey = 'night' .. night,
                instanceType = 'raid',
                difficultyID = 16,
                roster = roster,
            })
        end

        local drop = {
            timestamp = dropAt,
            itemLink = itemLink or 'bop',
            instanceType = dropInstanceType,
            difficultyID = dropDifficultyID,
            -- NeedMainSpec, read from the shipped enum rather than hardcoded.
            rolls = {
                {
                    isWinner = true,
                    guid = 'P1',
                    state = ShowUsYourLoot.LootHistoryAPI.ROLL_STATE.NeedMainSpec,
                },
            },
        }

        local entries = ShowUsYourLoot.DueList.Build({ drop }, sessions)

        for _, entry in ipairs(entries) do
            if entry.key == 'P1' then
                return entry.nightsSinceUpgrade, entry.everWon
            end
        end

        return nil, nil
    end
    """
)

build = lua.globals().BuildScenario

# The win lands after all three nights, so a drought that counts it reads 0
# dry nights and a drought that ignores it reads 3. No arithmetic to squint at.
RESET, IGNORED = 0, 3

CASES = [
    # label, instanceType, difficultyID, expected dry nights
    ("Mythic raid win resets the clock", "raid", 16, RESET),
    ("Heroic raid win resets the clock", "raid", 15, RESET),
    ("LFR win resets the clock — group loot, real rolls", "raid", 17, RESET),
    ("legacy drop with no location still counts", None, None, RESET),

    # The bug. Every one of these is real raid content the addon has already
    # decided is not a raid team's night.
    ("Timewalking raid win does NOT reset it", "raid", 33, IGNORED),
    ("Timewalking LFR win does NOT reset it", "raid", 151, IGNORED),
    ("Story mode win does NOT reset it", "raid", 220, IGNORED),
    ("Follower raid win does NOT reset it", "raid", 205, IGNORED),
    ("Event raid win does NOT reset it", "raid", 18, IGNORED),

    # Never was a raid night, and the due list says so in its own header.
    ("dungeon win does NOT reset a raid drought", "party", 8, IGNORED),
]

# Aimee's rule: a BoE is not what the drought measures. Same scenario, same
# Mythic raid night, only the item's binding differs.
BIND_CASES = [
    ("a bind-on-pickup win resets the clock", "bop", RESET),
    ("a BoE win does NOT reset it", "boe", IGNORED),

    # Warbound gear goes to the account, not to the raider who was standing
    # there, so it is excluded on the same reasoning as the BoE above.
    ("a warbound win does NOT reset it", "warbound", IGNORED),
    ("nor does warbound until equipped", "warbounduntilequipped", IGNORED),

    # Unknown must count. An uncached item answers nil, and reading that as
    # "BoE" would silently stop counting real upgrades.
    ("an uncached item counts rather than being assumed a BoE", "uncached", RESET),
]

failures = []

for label, instance_type, difficulty, want in CASES:
    got, ever_won = build(instance_type, difficulty, 4 * DAY)

    # everWon has to agree with the dry count, or the status sentence under
    # the number contradicts the number itself.
    want_ever_won = want == RESET
    ok = got == want and bool(ever_won) == want_ever_won

    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        print(f"       dry nights: got {got}, wanted {want}")
        print(f"       everWon:    got {bool(ever_won)}, wanted {want_ever_won}")
        failures.append(label)

for label, link, want in BIND_CASES:
    got, ever_won = build("raid", 16, 4 * DAY, link)

    ok = got == want and bool(ever_won) == (want == RESET)
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        print(f"       dry nights: got {got}, wanted {want}")
        failures.append(label)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
