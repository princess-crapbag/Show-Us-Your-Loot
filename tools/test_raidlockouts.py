# -*- coding: utf-8 -*-
"""Raid lockouts, per character, and which bosses are already dead.

Aimee: "the way i can see m0 lockouts, id like to be able to see raid boss
kills/lockouts. put it somewhere that makes sense. i want to see this on each
toon as i log into them just the same way keys works. this raid lockout info
should not be in the keys tab."

Core/Lockouts.lua has been reading GetSavedInstanceInfo since it was written
and throwing the raid half away on a `not isRaid`. This reads the other half,
and the bosses inside each lockout, which is the part that makes it worth
having: "saved to the Abyss" is much less use than "five of eight, still needs
Ula'tek".

WHAT THE ASSERTIONS PROTECT:

  ABSENT IS NOT EMPTY. The client can only read the character it is logged in
  as, so a character this account has not played has no entry -- which is a
  different answer from "played, saved to nothing". A screen that says "no
  lockouts" for the first is making a claim the addon cannot make.

  THE RESET IS A MOMENT, NOT A COUNTDOWN. A countdown saved to disk keeps
  counting from whenever the file was written, which is the fault
  Core/Lockouts.lua's header is about.

  EXPIRED LOCKOUTS GO ON READ. Nothing ticks in this addon and an entry read
  from disk can be days stale.

Needs `lupa` - see tools/test_lootmessages.py for the setup.
"""
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import test_load  # noqa: E402

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s  %s" % (name, detail))
        failures.append(name)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

Raid = SYL.RaidLockouts

# A client with two raid lockouts and one dungeon one. The dungeon must not
# come through here -- Core/Lockouts.lua owns those.
lua.execute("""
    SAVED = {
        {
            name = "The Venomous Abyss", id = 3004, reset = 3600,
            difficultyID = 14, locked = true, extended = false, sig = 0,
            isRaid = true, maxPlayers = 30, difficultyName = "Normal",
            numEncounters = 8, progress = 5,
            bosses = {
                { "Nek'zali the Soulcoiler", true },
                { "Entombed Sentinels", true },
                { "The Lost Explorers", true },
                { "Sszorak", true },
                { "Vashnik the Malignant", true },
                { "The Twin Fangs", false },
                { "Ula'tek", false },
                { "The Coiled Altar", false },
            },
        },
        {
            name = "The Tidebound Grotto", id = 2987, reset = 7200,
            difficultyID = 15, locked = true, extended = false, sig = 0,
            isRaid = true, maxPlayers = 30, difficultyName = "Heroic",
            numEncounters = 1, progress = 0,
            bosses = { { "Nymrissa Wavecaller", false } },
        },
        {
            name = "Den of Nalorakk", id = 1, reset = 3600,
            difficultyID = 23, locked = true, extended = false, sig = 0,
            isRaid = false, maxPlayers = 5, difficultyName = "Mythic",
            numEncounters = 4, progress = 4,
            bosses = {},
        },
        -- Locked false: an instance the client knows about and this character
        -- is not saved to.
        {
            name = "Sporefall", id = 1592, reset = 3600,
            difficultyID = 17, locked = false, extended = false, sig = 0,
            isRaid = true, maxPlayers = 30, difficultyName = "LFR",
            numEncounters = 3, progress = 1,
            bosses = {},
        },
    }

    function GetNumSavedInstances() return #SAVED end

    function GetSavedInstanceInfo(index)
        local e = SAVED[index]

        return e.name, e.id, e.reset, e.difficultyID, e.locked, e.extended,
            e.sig, e.isRaid, e.maxPlayers, e.difficultyName, e.numEncounters,
            e.progress
    end

    function GetSavedInstanceEncounterInfo(index, position)
        local boss = SAVED[index].bosses[position]

        if not boss then return nil end

        return boss[1], 0, boss[2]
    end

    function UnitClass() return "Hunter", "HUNTER" end

    ShowUsYourLoot.Keystone.CharacterKey = function()
        return "Arcangila-Area52"
    end
""")


# --------------------------------------------------------------------------
# Reading
# --------------------------------------------------------------------------

found = list(Raid.Read().values())

check("only raids come through", len(found) == 2,
      "got %r" % [str(f.name) for f in found])

check("and only the ones this character is saved to",
      "Sporefall" not in [str(f.name) for f in found])

abyss = None
for entry in found:
    if str(entry.name) == "The Venomous Abyss":
        abyss = entry

check("the boss progress is read", abyss is not None
      and int(abyss.killed) == 5 and int(abyss.total) == 8,
      "got %r of %r" % (abyss and abyss.killed, abyss and abyss.total))

check("and every boss is named",
      len(list(abyss.bosses.values())) == 8)

# THE PART THAT MAKES IT WORTH HAVING.
remaining = [str(n) for n in Raid.Remaining(abyss).values()]

check("what is left to kill is answerable",
      remaining == ["The Twin Fangs", "Ula'tek", "The Coiled Altar"],
      "%r" % remaining)

check("and a cleared lockout has nothing left",
      len(list(Raid.Remaining(lua.table_from({})).values())) == 0)

# ONE INSTANCE AT ONE DIFFICULTY IS ONE LOCKOUT. The same raid on Normal and
# Heroic is two, which is how the client reports it and how a raider thinks.
check("the key separates difficulties",
      str(Raid.Key("Abyss", "Normal")) != str(Raid.Key("Abyss", "Heroic")))

check("and refuses a nameless one", Raid.Key(None, "Normal") is None)


# --------------------------------------------------------------------------
# Storing
# --------------------------------------------------------------------------

entry, changed = Raid.Update()

check("the character is recorded", entry is not None
      and int(entry.count) == 2, "got %r" % (entry and entry.count))

check("with the bosses it has killed", int(entry.bossesKilled) == 5)

check("and it reports that something changed the first time", changed is True)

_again, changedAgain = Raid.Update()

check("and not the second", changedAgain is False)

# THE RESET IS A MOMENT. A countdown written to disk keeps counting down from
# whenever the file was written.
lockouts = list(Raid.For(entry).values())

check("the reset is stored as a moment, not a countdown",
      all(int(l.expiresAt) > 100000 for l in lockouts),
      "%r" % [int(l.expiresAt) for l in lockouts])


# --------------------------------------------------------------------------
# Reading it back
# --------------------------------------------------------------------------

characters = list(Raid.Characters().values())

check("the account has one character so far", len(characters) == 1)

check("and it has been checked",
      Raid.HasBeenChecked(characters[0]) is True)

check("a character that has never been read has not",
      Raid.HasBeenChecked(lua.table_from({})) is False)

check("the lockouts come back in a stable order",
      [str(l.name) for l in Raid.For(characters[0]).values()]
      == ["The Tidebound Grotto", "The Venomous Abyss"],
      "%r" % [str(l.name) for l in Raid.For(characters[0]).values()])

check("and describe themselves as bosses over bosses",
      str(Raid.Describe(abyss)) == "5 of 8",
      "got %r" % Raid.Describe(abyss))

# EXPIRED GOES ON READ, because nothing ticks in this addon.
lua.execute("""
    for _, entry in pairs(ShowUsYourLootDB.raidLockouts) do
        for _, lockout in pairs(entry.lockouts) do
            lockout.expiresAt = 1
        end
    end
""")

stale = list(Raid.Characters().values())

check("an expired lockout is dropped when it is read",
      int(stale[0].count) == 0, "got %r" % stale[0].count)

# The character is still there, still checked - saved to nothing is an answer.
check("but the character stays, because saved to nothing is an answer",
      len(stale) == 1 and Raid.HasBeenChecked(stale[0]) is True)


# --------------------------------------------------------------------------
# Where it lives
# --------------------------------------------------------------------------

def source(name):
    return test_load.ROOT.joinpath(name).read_text(encoding="utf-8")

keys = source("UI/KeysPanel.lua")

# HERS, EXPLICITLY: "this raid lockout info should not be in the keys tab."
check("the Keys tab does not draw raid lockouts",
      "RaidLockouts" not in keys)

bosses = source("UI/BossesPanel.lua")

check("the Bosses tab does",
      "RaidLockoutsView" in bosses and "ToggleView" in bosses)

check("and swapping to it takes the boss pane off screen",
      "BossLoot.Hide(frame.pane)" in bosses)

events = source("Core/Events.lua")

check("lockouts are read on the same event the dungeon ones are",
      "RaidLockouts.Update" in events)

view = source("UI/RaidLockoutsView.lua")

# ABSENT IS NOT EMPTY.
check("an account with nothing read says so, rather than 'no lockouts'",
      "Nothing read yet" in view
      and "first time you log into it" in view
      and "only see the character it is " in view)

check("and the rows take the mouse, so the hover can fire",
      "row:EnableMouse(true)" in view)

check("nothing is silently truncated",
      "more not shown" in view)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
