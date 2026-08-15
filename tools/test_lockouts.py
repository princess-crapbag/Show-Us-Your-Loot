"""Mythic 0 lockouts, and the two things that would make them lie.

THE PERIOD IS NEVER ASSUMED. Mythic 0 is on a weekly lockout during a patch
week and a daily one once the season opens — Midnight Season 2 flips on
2026-08-18. Core/Lockouts.lua stores the moment a lockout expires rather than
the rule that produced it, so both are the same code. The fixture here holds
one of each at once, which is the state an account is actually in on a
transition week, and neither is told apart anywhere in the addon.

A LOCKOUT MUST NEVER BE HIDDEN. The season's dungeons come from
C_ChallengeMode.GetMapTable, which deals in challenge-mode map ids, while
GetSavedInstanceInfo knows only instance names. There is no function from one
to the other, so the join is by name and the join can miss. A miss that drops
the row would tell somebody a dungeon is free on a character that is saved to
it, and they would find out by walking in. The assertion is that an unmatched
lockout gets its own column instead.

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

NOW = 1700000000  # what test_load's time() answers


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


# The client. GetSavedInstanceInfo's real signature, in order, is
#   name, id, reset, difficulty, locked, extended, instanceIDMostSig,
#   isRaid, maxPlayers, difficultyName, ...
# and the reader destructures by position, so the stub has to keep the gaps.
lua.execute(
    """
    local SYL = ShowUsYourLoot

    SAVED = {}
    CHARACTER = 'Aimee'

    function UnitName() return CHARACTER end
    function GetRealmName() return 'Realm' end
    function UnitClass() return 'Priest', 'PRIEST' end

    function GetNumSavedInstances() return #SAVED end

    function GetSavedInstanceInfo(index)
        local entry = SAVED[index]

        if not entry then
            return nil
        end

        return entry.name, 1234, entry.reset, 23, entry.locked ~= false,
            false, 0, entry.isRaid == true, 5, entry.difficultyName or 'Mythic'
    end

    -- The season's rotation. Midnight Season 2's eight, with King's Rest
    -- spelled the way the M+ map table spells it — the instance spells it
    -- differently, which is the join this file is about.
    SEASON = {
        [1] = 'Altar of Fangs',
        [2] = 'Murder Row',
        [3] = 'Den of Nalorakk',
        [4] = 'The Blinding Vale',
        [5] = 'Voidscar Arena',
        [6] = "King's Rest",
        [7] = 'Temple of Sethraliss',
        [8] = 'Ruby Life Pools',
    }

    C_ChallengeMode = C_ChallengeMode or {}

    function C_ChallengeMode.GetMapTable()
        local ids = {}

        for id in pairs(SEASON) do
            table.insert(ids, id)
        end

        table.sort(ids)

        return ids
    end

    function C_ChallengeMode.GetMapUIInfo(id)
        return SEASON[id]
    end

    function SetSaved(list)
        SAVED = list
    end

    function ColumnNames()
        local columns = SYL.Lockouts.Build()
        local out = {}

        for _, column in ipairs(columns) do
            table.insert(out, column.name .. (column.seasonal and '' or '*'))
        end

        return table.concat(out, ' ~ ')
    end

    function SavedCountFor(name)
        local _, characters = SYL.Lockouts.Build()

        for _, character in ipairs(characters) do
            if tostring(character.name):match('^' .. name) then
                return character.count
            end
        end

        return -1
    end
    """
)

g = lua.globals()

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

# --- one weekly lockout and one daily, at the same time -------------------
#
# The transition week. 6 days is a weekly reset most of the way through its
# life; 20 hours is a daily. Nothing anywhere is told which is which.
lua.execute(
    """
    SetSaved({
        { name = 'Altar of Fangs', reset = 6 * 86400 },
        { name = 'Murder Row', reset = 20 * 3600 },
    })
    """
)

entry, changed = SYL.Lockouts.Update()

check("the lockouts are read", entry is not None and entry.count == 2,
      entry and entry.count)
check("and that counts as a change the first time", changed is True)

check("a weekly and a daily lockout are both just an expiry",
      entry.instances["altaroffangs"].expiresAt == NOW + 6 * 86400
      and entry.instances["murderrow"].expiresAt == NOW + 20 * 3600)

# The countdown a row prints is the soonest of them, which on a transition
# week is the daily one.
character = SYL.Lockouts.Characters()[1]

check("the row counts down to the soonest reset",
      SYL.Lockouts.NextReset(character) == 20 * 3600,
      SYL.Lockouts.NextReset(character))
check("and reads as hours rather than a bare second count",
      SYL.Lockouts.FormatRemaining(20 * 3600) == "20h 00m",
      SYL.Lockouts.FormatRemaining(20 * 3600))
check("a weekly one reads in days",
      SYL.Lockouts.FormatRemaining(6 * 86400 + 4 * 3600) == "6d 4h",
      SYL.Lockouts.FormatRemaining(6 * 86400 + 4 * 3600))

# --- raids are not dungeon lockouts ---------------------------------------
#
# The same API answers for both, and a raid lockout in this grid would be a
# dungeon nobody can find.
lua.execute(
    """
    SetSaved({
        { name = 'Altar of Fangs', reset = 6 * 86400 },
        { name = 'Manaforge Omega', reset = 3 * 86400, isRaid = true },
    })
    """
)

entry, _ = SYL.Lockouts.Update()

check("a raid lockout is not a dungeon lockout",
      entry.count == 1 and entry.instances["manaforgeomega"] is None,
      entry.count)

# --- an unlocked instance is not a lockout --------------------------------
lua.execute(
    """
    SetSaved({
        { name = 'Altar of Fangs', reset = 6 * 86400 },
        { name = 'Murder Row', reset = 0, locked = false },
    })
    """
)

entry, _ = SYL.Lockouts.Update()

check("an expired or unlocked instance is not counted", entry.count == 1,
      entry.count)

# --- THE ONE THAT MATTERS: the name join ----------------------------------
#
# "Kings' Rest" from the instance list against "King's Rest" from the map
# table, plus a dungeon the season does not contain at all.
lua.execute(
    """
    SetSaved({
        { name = "Kings' Rest", reset = 6 * 86400 },
        { name = 'Some Old Dungeon', reset = 2 * 86400 },
    })
    """
)

SYL.Lockouts.Update()

columns = g.ColumnNames()

check("the apostrophe does not cost a match",
      columns.count("King's Rest") == 1 and "Kings' Rest" not in columns,
      columns)
check("A LOCKOUT THE SEASON DOES NOT LIST IS STILL SHOWN",
      "Some Old Dungeon*" in columns, columns)
check("and it is marked as not seasonal rather than blending in",
      columns.endswith("Some Old Dungeon*"), columns)
check("the season's eight are all columns",
      len([c for c in columns.split(" ~ ") if not c.endswith("*")]) == 8,
      columns)

# --- per character, like keystones ----------------------------------------
lua.execute("CHARACTER = 'Aimeepriest'")

lua.execute("SetSaved({ { name = 'Voidscar Arena', reset = 20 * 3600 } })")
SYL.Lockouts.Update()

check("a second character keeps its own lockouts",
      g.SavedCountFor("Aimee") == 2 and g.SavedCountFor("Aimeepriest") == 1,
      f"Aimee={g.SavedCountFor('Aimee')} "
      f"priest={g.SavedCountFor('Aimeepriest')}")

_, characters = SYL.Lockouts.Build()

check("both characters are on the grid", len(characters) == 2, len(characters))

# --- expiry is absolute, so it survives a logout --------------------------
#
# A countdown written to disk keeps counting from whenever the file was
# written. This one is stamped with the moment it ends, and a stale entry read
# back days later is simply gone.
lua.execute(
    """
    local store = ShowUsYourLootDB.lockouts

    for _, entry in pairs(store) do
        for _, instance in pairs(entry.instances or {}) do
            instance.expiresAt = 1
        end
    end
    """
)

check("a lockout that has already reset is dropped on read",
      g.SavedCountFor("Aimee") == 0 and g.SavedCountFor("Aimeepriest") == 0)

# --- a client that cannot answer ------------------------------------------
lua.execute(
    """
    REAL_NUM = GetNumSavedInstances
    GetNumSavedInstances = nil
    """
)

check("no saved-instance API means no lockouts, not an error",
      len(SYL.Lockouts.Read()) == 0)
absent, absentChanged = SYL.Lockouts.Update()

check("and Update says so rather than storing nothing over something",
      absent is None and absentChanged is False, (absent, absentChanged))

lua.execute("GetNumSavedInstances = REAL_NUM")

lua.execute(
    """
    REAL_TABLE = C_ChallengeMode.GetMapTable
    C_ChallengeMode.GetMapTable = nil
    """
)

check("no map table still draws the lockouts somebody has",
      len(SYL.Lockouts.SeasonMaps()) == 0)

lua.execute("C_ChallengeMode.GetMapTable = REAL_TABLE")

# --- the abbreviations stay distinct --------------------------------------
seen = {}
collide = []

for index in range(1, 9):
    name = lua.globals().SEASON[index]
    short = SYL.LockoutsGrid.Abbreviate(name)

    if short in seen:
        collide.append(f"{name} and {seen[short]} are both {short}")

    seen[short] = name

check("every dungeon this season abbreviates differently", not collide,
      "; ".join(collide))

# --- and the grid draws ---------------------------------------------------
lua.execute("CHARACTER = 'Aimee'")
lua.execute("SetSaved({ { name = 'Altar of Fangs', reset = 6 * 86400 } })")
SYL.Lockouts.Update()

try:
    panel = SYL.KeysPanel.Create(lua.globals().UIParent)
    SYL.KeysPanel.SetView("lockouts")
    check("the grid draws", True)
except Exception as err:  # noqa: BLE001 — any Lua error is the finding
    check("the grid draws", False, err)

try:
    SYL.KeysPanel.SetView("keys")
    SYL.KeysPanel.SetView("lockouts")
    SYL.KeysPanel.ToggleView()
    check("and switching back and forth is safe", True)
except Exception as err:  # noqa: BLE001
    check("and switching back and forth is safe", False, err)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
