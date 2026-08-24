# -*- coding: utf-8 -*-
"""Sorting the Raiders board by any column.

Aimee: "in the same raiders board section, id like to be able to sort by each
column."

TWO THINGS COULD HAVE GONE WRONG HERE AND BOTH ARE LOAD-BEARING.

  THE SORT MUST NOT REACH LootScore.Rank. That is the choke point /syl due,
  the dashboard "who is due" tile and UI/DueWindow.lua all read, and the note
  above LootScore.Sort was written about the last time two screens ranked by
  different rules: "/syl due sorted by drought for days after the board moved
  to share." A sort key pushed down there would silently reorder three other
  surfaces. It is a display pass over an already-ranked list instead.

  TIES ARE NOT RARE AND table.sort IS NOT STABLE. In her own season five of
  thirteen raiders sit at 0 items, 0 points and 0.00 per night, three more tie
  at 120 points and two at 100 - ten of thirteen are inside a tied block on at
  least one column. A comparator that answers false both ways leaves their
  order UNDEFINED, so the same data reshuffles between refreshes and the board
  looks broken in a way nothing reports. Every comparison falls through to the
  name.

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


Board = SYL.RaidersBoard

columns = list(Board.COLUMNS.values())


# --------------------------------------------------------------------------
# Every column can be sorted, and says which it is
# --------------------------------------------------------------------------

check("there are still exactly four columns", len(columns) == 4)

check("and every one has a sort key",
      all(str(c.key) for c in columns),
      "%r" % [c.key for c in columns])

check("and a comparator", all(c.sortBy is not None for c in columns))

keys = [str(c.key) for c in columns]

check("the keys are distinct", len(set(keys)) == 4, "%r" % keys)


# --------------------------------------------------------------------------
# The comparators read the right field
# --------------------------------------------------------------------------

lua.execute("""
    ENTRY = {
        name = "Somebody", scoringWins = 3, nights = 2,
        share = 43.1, lootScore = 560, ranked = true,
    }
""")

entry = lua.globals().ENTRY

expected = {"items": 3, "nights": 2, "share": 43.1, "points": 560}

for column in columns:
    key = str(column.key)
    got = column.sortBy(entry)

    check("%s sorts on the number it shows" % key,
          abs(float(got) - expected[key]) < 0.001,
          "got %r, wanted %r" % (got, expected[key]))


# --------------------------------------------------------------------------
# Ties, which is where this breaks if it breaks
# --------------------------------------------------------------------------
#
# Her real tied block: five raiders at 0/0/0.00. Sorted by any column they
# must come out in the same order every time, and that order has to be one a
# person can predict.

lua.execute("""
    TIED = {}

    for _, who in ipairs({
        "Misothelioma", "Syzzlac", "Niwmn", "Saebie", "Looniemoonie",
    }) do
        table.insert(TIED, {
            name = who, scoringWins = 0, nights = 0,
            share = 0, lootScore = 0, ranked = true,
        })
    end
""")


def order(entries):
    return [str(e.name) for e in entries.values()]


# THE REAL COMPARATOR, called rather than copied.
#
# The first version of this suite reimplemented the comparator here, so
# deleting the tiebreak from the addon changed nothing about whether it
# passed. RaidersPanel.SortEntries is exported and pure for exactly that
# reason.
Sort = SYL.RaidersSort.Entries
tied = lua.globals().TIED

first = order(Sort(tied, "items", False))
second = order(Sort(tied, "items", False))

check("a tied block comes out in the same order twice",
      first == second, "%r then %r" % (first, second))

check("and that order is alphabetical, which is one somebody can predict",
      first == sorted(first), "%r" % first)

# Reversing must not scramble the tie - the tiebreak is not the sort.
reversedOrder = order(Sort(tied, "items", True))

check("reversing a column does not scramble a tie inside it",
      reversedOrder == sorted(reversedOrder), "%r" % reversedOrder)

# EVERY COLUMN, because a tie on one is a tie on all of them here.
for key in ("items", "nights", "share", "points", "name"):
    got = order(Sort(tied, key, False))

    check("sorting by %s leaves a tied block alphabetical" % key,
          got == sorted(got), "%r" % got)

# And the sort itself still sorts.
lua.execute("""
    SPREAD = {
        { name = "Camcar", scoringWins = 1, nights = 2, share = 50.0,
          lootScore = 100, ranked = true },
        { name = "Phreestyle", scoringWins = 3, nights = 2, share = 110.0,
          lootScore = 220, ranked = true },
        { name = "Alpha", scoringWins = 2, nights = 1, share = 80.0,
          lootScore = 160, ranked = true },
    }
""")

spread = lua.globals().SPREAD

check("smallest first, because the board answers who is owed",
      order(Sort(spread, "points", False))
      == ["Camcar", "Alpha", "Phreestyle"],
      "%r" % order(Sort(spread, "points", False)))

check("and reversing puts the top scorer first",
      order(Sort(spread, "points", True))
      == ["Phreestyle", "Alpha", "Camcar"],
      "%r" % order(Sort(spread, "points", True)))

check("the name column reads A to Z",
      order(Sort(spread, "name", False))
      == ["Alpha", "Camcar", "Phreestyle"],
      "%r" % order(Sort(spread, "name", False)))

check("and Z to A reversed",
      order(Sort(spread, "name", True))
      == ["Phreestyle", "Camcar", "Alpha"],
      "%r" % order(Sort(spread, "name", True)))

# AN UNKNOWN KEY MUST NOT THROW. The saved sort could name a column that no
# longer exists after an update, and a board that errors on open is worse
# than one in an unexpected order.
check("an unknown column falls back to the name rather than throwing",
      order(Sort(spread, "nonsense", False))
      == ["Alpha", "Camcar", "Phreestyle"])

check("the original list is not reordered in place",
      order(spread) == ["Camcar", "Phreestyle", "Alpha"],
      "%r" % order(spread))


# --------------------------------------------------------------------------
# The click convention
# --------------------------------------------------------------------------
#
# Same as UI/SortHeader.lua, which three other screens already use: clicking
# the active column flips it, a new column starts in its natural direction.
# The board behaving differently from the rest of the addon is a defect
# nothing would report.

Click = SYL.RaidersSort.OnClick
Key = SYL.RaidersSort.Key

key, reversed_ = Key()

check("the board opens on points per night",
      str(key) == "share", "got %r" % key)

# SMALLEST FIRST, because the board answers who is OWED. A first click that
# buried the people with least under the top scorers would be a worse default
# than the one it had.
check("smallest first", reversed_ is False)

Click("points", None)
key, reversed_ = Key()

check("a new column starts in its natural direction",
      str(key) == "points" and reversed_ is False,
      "got %r reversed=%r" % (key, reversed_))

Click("points", None)
key, reversed_ = Key()

check("and clicking it again flips it",
      str(key) == "points" and reversed_ is True,
      "got %r reversed=%r" % (key, reversed_))

Click("items", None)
key, reversed_ = Key()

check("moving to another column resets the direction",
      str(key) == "items" and reversed_ is False,
      "got %r reversed=%r" % (key, reversed_))

lua.execute("REFRESHED = 0")
Click("share", lua.eval("function() REFRESHED = REFRESHED + 1 end"))

check("and the board is redrawn",
      int(lua.globals().REFRESHED) == 1)

# Put it back, so nothing after this reads a board somebody else sorted.
Click("share", None)


# --------------------------------------------------------------------------
# The sort does not reach the ranking
# --------------------------------------------------------------------------
#
# Read out of the source, because the failure is that THREE OTHER SCREENS
# change and this one looks fine.

def source(name):
    return test_load.ROOT.joinpath(name).read_text(encoding="utf-8")

score = source("Core/LootScore.lua")

check("LootScore.Rank takes no sort key",
      "function LootScore.Rank(entries, drops)" in score,
      "Rank's signature changed - /syl due, the dashboard tile and DueWindow "
      "all read it")

check("and LootScore.Sort takes none either",
      "function LootScore.Sort(entries)" in score)

panel = source("UI/RaidersPanel.lua")
sortsrc = source("UI/RaidersSort.lua")

check("the sort owns its own state",
      "local sortKey" in sortsrc and "local sortReversed" in sortsrc)

check("and the panel applies it after ranking, as a display pass",
      "SYL.RaidersSort.Entries(entries, sortKey, sortReversed)" in panel)

check("and every comparison falls through to the name",
      "leftName < rightName" in sortsrc)

check("and the comparator is exported, so a test can call it",
      "function RaidersSort.Entries(entries, key, reversed)" in sortsrc)

board = source("UI/RaidersBoard.lua") + sortsrc

# The arrow cannot be appended to the label: Measure sets one shared column
# width from the widest heading line, so "PER NIGHT" leaves exactly zero
# pixels of slack.
check("the arrow is its own region, not appended to a heading",
      "header.arrows" in board and '.. "  v"' not in board)

check("the headings are buttons",
      "HeadingButton" in board)

check("and hiding the header hides them too",
      "for _, button in pairs(header.buttons or {}) do" in board)

# The bar heading names the same number POINTS PER NIGHT does, so making both
# clickable would give one sort two controls and two places to draw one arrow.
check("the bar heading is not a second control for the same sort",
      board.count("onSort(") == 2, "found %d" % board.count("onSort("))

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
