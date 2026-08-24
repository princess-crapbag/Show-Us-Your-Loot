# -*- coding: utf-8 -*-
"""What the Loot list opens on, and the raid difficulty filter.

Aimee, reading the Loot tab: "id like to change the default settings for some
things. default to gear only, raids only. still give the option to swap
through others. have the win type default on greed, mog, need. default off
personal." And: "id like to see a difficulty section [...] have it default to
the last raid difficulty you were in. allow multi select."

THE TRAP IN "DEFAULT ON GREED, MOG, NEED" is that it reads as a list of three
and must not be built as one. Her dropdown shows four types because four are
in her data; an explicit {Greed, Mog, Need} would silently hide Offspec the
first time one was recorded, and her own season already holds sixteen offspec
rolls. It is written as an exclusion -- everything shows except what
HIDDEN_BY_DEFAULT names -- so anything new is visible and only Personal is
not.

THE SECOND TRAP is that Filters.Apply returns the records untouched when the
state is not "active", so a default exclusion that did not make it active
would never run: the list would open showing personal loot and only start
hiding it once some other filter was set.

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


Filters = SYL.Filters

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

lua.execute("""
    FIELDS = {
        player = function(r) return r.player end,
        item = function(r) return r.itemName end,
        location = function(r) return r.where end,
        timestamp = function(r) return r.timestamp end,
        wintype = function(r) return r.typeLabel end,
        difficulty = function(r)
            return ShowUsYourLoot.Filters.RAID_DIFFICULTY[r.difficultyID]
        end,
    }

    RECORDS = {
        { player = "Hawt", itemName = "Boots", typeLabel = "Need",
          difficultyID = 14, timestamp = 100 },
        { player = "Camcar", itemName = "Ring", typeLabel = "Greed",
          difficultyID = 15, timestamp = 200 },
        { player = "Phreestyle", itemName = "Cloak", typeLabel = "Mog",
          difficultyID = 16, timestamp = 300 },
        { player = "Arcangila", itemName = "Spark", typeLabel = "Personal",
          difficultyID = 14, timestamp = 400 },
        -- Her season holds sixteen of these. An explicit list of three would
        -- have hidden it.
        { player = "Rakahasa", itemName = "Belt", typeLabel = "Offspec",
          difficultyID = 17, timestamp = 500 },
        -- Not a raid at all: no raid difficulty, so a difficulty choice
        -- filters it out.
        { player = "Niwmn", itemName = "Key", typeLabel = "Need",
          difficultyID = 8, timestamp = 600 },
    }
""")

fields = lua.globals().FIELDS
records = lua.globals().RECORDS


def shown(state):
    return sorted(str(r.itemName)
                  for r in Filters.Apply(records, state, fields).values())


# --------------------------------------------------------------------------
# Personal loot is hidden until asked for
# --------------------------------------------------------------------------

state = Filters.CreateState()

check("the list opens without personal loot",
      "Spark" not in shown(state), "%r" % shown(state))

# THE ONE THAT WOULD HAVE BITTEN HER. Offspec is not in her list of three and
# must still show.
check("but offspec, which she did not name, still shows",
      "Belt" in shown(state), "%r" % shown(state))

check("and so does everything else",
      shown(state) == ["Belt", "Boots", "Cloak", "Key", "Ring"],
      "%r" % shown(state))

# Filters.Apply short-circuits on an inactive state, so this has to be true
# or the exclusion never runs at all.
check("a fresh state counts as active, or the default never applies",
      Filters.IsActive(state) is True)

# The tickboxes have to say what the list is doing.
check("the dropdown draws Personal unticked",
      Filters.IsShowing(state, "wintype", "Personal") is False)

check("and everything else ticked",
      Filters.IsShowing(state, "wintype", "Need") is True
      and Filters.IsShowing(state, "wintype", "Offspec") is True)

# Nothing is SELECTED though - that is the difference between showing and
# chosen, and it is what lets the first click start from what is on screen.
check("while nothing is actually selected yet",
      int(Filters.CountSelected(state, "wintype")) == 0)


# --------------------------------------------------------------------------
# The first click makes it explicit
# --------------------------------------------------------------------------

Filters.SelectShowing(state, "wintype",
                      lua.table_from(["Need", "Greed", "Mog", "Personal",
                                      "Offspec"]))

check("selecting what is showing does not tick Personal",
      Filters.IsSelected(state, "wintype", "Personal") is False)

check("but ticks the rest",
      Filters.IsSelected(state, "wintype", "Offspec") is True)

check("and the list is unchanged by it",
      "Spark" not in shown(state) and "Belt" in shown(state),
      "%r" % shown(state))

# Once explicit, Personal can be asked for.
Filters.Toggle(state, "wintype", "Personal")

check("and personal loot can then be asked for",
      "Spark" in shown(state), "%r" % shown(state))


# --------------------------------------------------------------------------
# Raid difficulty
# --------------------------------------------------------------------------

state = Filters.CreateState()

check("difficulty is one of the filter fields",
      "difficulty" in [str(f) for f in Filters.FIELDS.values()])

check("and it is L, N, H, M in that order",
      [str(v) for v in Filters.RAID_DIFFICULTY_ORDER.values()]
      == ["L", "N", "H", "M"])

options = Filters.DeriveOptions(records, fields, "difficulty")

check("the options come out as the ladder, not the alphabet",
      [str(o) for o in options.values()] == ["L", "N", "H", "M"],
      "%r" % [str(o) for o in options.values()])

Filters.Toggle(state, "difficulty", "H")

check("choosing Heroic shows only Heroic",
      shown(state) == ["Ring"], "%r" % shown(state))

# MULTI-SELECT, hers.
Filters.Toggle(state, "difficulty", "M")

check("and it is multi-select",
      shown(state) == ["Cloak", "Ring"], "%r" % shown(state))

# A DUNGEON HAS NO RAID DIFFICULTY, so a control called Raid Difficulty
# filters it out rather than keeping it.
check("a Mythic+ dungeon drop is not a raid difficulty",
      Filters.RAID_DIFFICULTY[8] is None)

check("and is filtered out when a raid difficulty is chosen",
      "Key" not in shown(state), "%r" % shown(state))


# --------------------------------------------------------------------------
# It opens on the last raid difficulty
# --------------------------------------------------------------------------

lua.execute("""
    SESSIONS = {
        { difficultyID = 14, startedAt = 1000 },
        { difficultyID = 15, startedAt = 9000 },
        { difficultyID = 17, startedAt = 5000 },
        -- A dungeon, which is not a raid difficulty and must not win just by
        -- being the most recent thing recorded.
        { difficultyID = 8, startedAt = 99000 },
    }
""")

sessions = lua.globals().SESSIONS

check("the last raid difficulty is the latest RAID, not the latest session",
      str(Filters.LastRaidDifficulty(sessions)) == "H",
      "got %r" % Filters.LastRaidDifficulty(sessions))

fresh = Filters.CreateState()
applied = Filters.ApplyDefaultDifficulty(fresh, sessions)

check("a fresh window opens on it",
      str(applied) == "H" and Filters.IsSelected(fresh, "difficulty", "H"))

# MUST NOT UNDO A CHOICE. Reopening the window would otherwise silently put
# the filter back.
chosen = Filters.CreateState()
Filters.Toggle(chosen, "difficulty", "M")
Filters.ApplyDefaultDifficulty(chosen, sessions)

check("but it never overrides a choice already made",
      Filters.IsSelected(chosen, "difficulty", "M") is True
      and Filters.IsSelected(chosen, "difficulty", "H") is False)

check("and with nothing recorded it constrains nothing",
      Filters.ApplyDefaultDifficulty(
          Filters.CreateState(), lua.table_from([])) is None)


# --------------------------------------------------------------------------
# What the window opens on
# --------------------------------------------------------------------------

main = test_load.ROOT.joinpath("UI/MainWindow.lua").read_text(encoding="utf-8")

check("the list opens gear only", "gearOnly = true," in main)

check("and raids only", 'contentScope = "raid",' in main)

check("and applies the difficulty default when it opens",
      "Filters.ApplyDefaultDifficulty" in main)

# STILL SWAPPABLE, which she asked for explicitly.
bar = test_load.ROOT.joinpath("UI/SelectionBar.lua").read_text(encoding="utf-8")

check("gear only is still a button she can turn off",
      "gearOnly" in bar)

check("and so is the content scope", "contentScope" in bar)


# --------------------------------------------------------------------------
# Hide all
# --------------------------------------------------------------------------
#
# The capability already existed behind Shift and nothing on screen said so,
# which is the house rule about commands applied to a modifier key.

check("hiding every copy is a button now",
      '"Hide all"' in bar)

check("and it says what it does",
      "Tick one crystal and this hides every crystal" in bar)

check("and it is shown and hidden with the rest of the bar",
      bar.count("self.hideAllCopies") == 2,
      "found %d" % bar.count("self.hideAllCopies"))

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
