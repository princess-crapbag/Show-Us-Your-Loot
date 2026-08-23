# -*- coding: utf-8 -*-
"""The Raiders board's layout arithmetic, and what each column prints.

Every width on that board is measured rather than declared, which means the
arithmetic that turns those measurements into positions is the thing that can
be wrong -- and wrong there is a column running off the right-hand edge, or a
bar with a negative width, neither of which any other test would catch.

MeasureText is replaced with a ruler of known widths. The point is not what the
real font measures; it is that whatever it measures, the columns come out equal,
the gaps come out even, and the last one ends inside the board.
"""
import io
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


# A ruler with real proportions -- capitals wider than digits, a space narrow --
# so a column that is only wide enough for its heading is still caught.
lua.execute("""
    local widths = { [" "] = 3 }

    ShowUsYourLoot.Theme.MeasureText = function(size, text)
        local total = 0

        for index = 1, #text do
            local char = text:sub(index, index)

            total = total + (widths[char] or (size * 0.62))
        end

        return total
    end
""")

BOARD = 606

board = SYL.RaidersBoard
layout = board.Measure(BOARD)

print("layout: left %.1f  name %.1f  bar %.1f wide %.1f  numbers %.1f  column %.1f"
      % (layout.left, layout.name, layout.bar, layout.barWidth,
         layout.numbers, layout.column))

check("the board is inset by the same gap it puts between columns",
      layout.left == layout.gap,
      "%s vs %s" % (layout.left, layout.gap))

check("the bar starts after the name and a gap",
      abs(layout.bar - (layout.left + layout.name + layout.gap)) < 0.01)

check("the bar has room left over", layout.barWidth > 0,
      "barWidth %s" % layout.barWidth)

columns = board.COLUMNS
count = len(columns)

check("there are four right-hand columns", count == 4, "got %d" % count)

check("the columns are in Aimee's order",
      [str(columns[i + 1].top) + " " + str(columns[i + 1].bottom)
       for i in range(count)]
      == ["# ITEMS RECEIVED", "RAID NIGHTS", "POINTS PER NIGHT",
          "TOTAL POINTS"])

xs = [board.ColumnX(i + 1) for i in range(count)]
gaps = [xs[i + 1] - xs[i] - layout.column for i in range(count - 1)]

check("every gap between columns is the same one",
      all(abs(g - layout.gap) < 0.01 for g in gaps), str(gaps))

check("the first column starts where the numbers do",
      abs(xs[0] - layout.numbers) < 0.01)

# 8, in her words: one full character space after the final number.
right = xs[-1] + layout.column
space = lua.eval('ShowUsYourLoot.Theme.MeasureText(11, " ")')

check("the last column ends one space inside the board",
      abs((right + space) - BOARD) < 0.01,
      "ends at %.1f + %.1f, board is %d" % (right, space, BOARD))

check("nothing overlaps the bar",
      layout.bar + layout.barWidth + layout.gap <= layout.numbers + 0.01)

# Every column has to be able to hold its own widest declared value.
for i in range(count):
    column = columns[i + 1]
    widest = lua.eval('ShowUsYourLoot.Theme.MeasureText(11, "%s")'
                      % column.widest)
    heading = max(
        lua.eval('ShowUsYourLoot.Theme.MeasureText(10, "%s")' % column.top),
        lua.eval('ShowUsYourLoot.Theme.MeasureText(10, "%s")' % column.bottom),
    )

    check("%s holds its widest value and its heading" % column.bottom,
          layout.column >= widest - 0.01 and layout.column >= heading - 0.01,
          "column %.1f, value %.1f, heading %.1f"
          % (layout.column, widest, heading))

# What the cells print, for the two shapes of raider on the board.
ranked = lua.eval("""{
    key = "a", name = "Someone", ranked = true, share = 43.15,
    lootScore = 560, scoringWins = 3, nights = 2,
    byTrack = { Normal = 460, Heroic = 100 },
}""")
unranked = lua.eval("""{
    key = "b", name = "Nobody", ranked = false, nights = 0,
    notRankedReason = "has not raided yet",
}""")
view = lua.eval("{ nightsHeld = 2, highest = 100, average = 43.15 }")

printed = [str(columns[i + 1].value(ranked, view)) for i in range(count)]
check("a ranked raider reads across as her data does",
      printed == ["3", "2 of 2", "43.1", "560"], str(printed))

blank = [str(columns[i + 1].value(unranked, view)) for i in range(count)]
check("an unranked one shows dashes, and still shows the nights",
      blank == ["\u2014", "0 of 2", "\u2014", "\u2014"], str(blank))

# 6, in her words: attended of held, and held is the same for everybody.
view2 = lua.eval("{ nightsHeld = 9 }")
check("raid nights counts against nights held, not against itself",
      str(columns[2].value(ranked, view2)) == "2 of 9")

print()
print("FAILURES: %s" % (failures or "none"))
sys.exit(1 if failures else 0)
