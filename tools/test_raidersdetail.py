# -*- coding: utf-8 -*-
"""The Raiders detail pane: how it groups loot, and what it puts away.

Two claims worth a test, both of which would fail silently rather than throw.

THE MIDNIGHT ONE. The pane groups a raider's items under the raid night they
were taken on, and it has to use the SESSION's night rather than the date
stamped on the drop. A Tuesday raid that runs to half past midnight writes
Wednesday onto its last few drops, and grouping on that would put a heading on
the pane for a raid night that never happened -- on the one screen whose whole
job is being checkable by somebody who disagrees with it.

THE POOL ONE. Cards own textures and a Button each, not just font strings.
Select an eight-item raider and then a two-item one and the six left over have
to be gone, or they stay on screen showing somebody else's loot in their
tooltips.
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


NEED = SYL.LootHistoryAPI.ROLL_STATE.NeedMainSpec
MOG = SYL.LootHistoryAPI.ROLL_STATE.Transmog

# A Tuesday raid that starts at 20:00 and runs past midnight. The last drop is
# stamped Wednesday by the clock and belongs to Tuesday by the raid.
#
# BUILT FROM LOCAL TIME, not written as an epoch constant. An hour offset that
# crosses midnight in one timezone does not cross it in the next, and a fixture
# that quietly stops crossing midnight turns this whole file into a test that
# passes while proving nothing -- which is what the first version of it did.
import time  # noqa: E402

TUESDAY_2000 = time.mktime((2025, 8, 12, 20, 0, 0, 0, 0, -1))
NEXT_0100 = time.mktime((2025, 8, 13, 1, 0, 0, 0, 0, -1))

assert time.strftime("%Y-%m-%d", time.localtime(TUESDAY_2000)) !=     time.strftime("%Y-%m-%d", time.localtime(NEXT_0100)),     "the fixture has to straddle local midnight to mean anything"

lua.globals().TUESDAY = TUESDAY_2000
lua.globals().PAST_MIDNIGHT = NEXT_0100
lua.globals().NEED = NEED
lua.globals().MOG = MOG

lua.execute("""
    function Fixture()
        local sessions = {
            {
                startedAt = TUESDAY,
                dateText = date("%Y-%m-%d", TUESDAY),
                instanceID = 1,
                instanceName = "Somewhere",
                difficultyID = 14,
                difficultyName = "Normal",
                isRaid = true,
                guildNight = true,
                roster = { ["Someone"] = { name = "Someone" } },
            },
        }

        local function drop(id, at, state, item)
            return {
                id = id,
                timestamp = at,
                dateText = date("%Y-%m-%d", at),
                difficultyID = 14,
                difficultyName = "Normal",
                encounterName = "A Boss",
                itemName = item,
                itemLink = item,
                winnerName = "Someone",
                winnerState = state,
                rolls = {},
            }
        end

        local drops = {
            drop("a", TUESDAY + 600, NEED, "Early Item"),
            -- 01:00 the next morning, so the calendar disagrees with the raid.
            drop("b", PAST_MIDNIGHT, NEED, "Late Item"),
            drop("c", TUESDAY + 900, MOG, "Mog Item"),
        }

        return drops, sessions
    end

    function GroupsFor(drops, sessions)
        local detail = { width = 250, sessions = sessions }

        local items = ShowUsYourLoot.LootScore.ItemsFor("Someone", drops)
        local groups = ShowUsYourLoot.RaidersDetailParts.Groups(detail, items)

        -- Flattened before it crosses back: `items` is a method name on the
        -- Python side of the bridge, so a nested table field called that
        -- cannot be read from there.
        local keys, counts, points, stamps = {}, {}, {}, {}

        for index, group in ipairs(groups) do
            keys[index] = group.key
            counts[index] = #group.items
            points[index] = group.points
            stamps[index] = group.at
        end

        return keys, counts, points, stamps, #items
    end
""")

drops, sessions = lua.globals().Fixture()

check("the fixture's three drops all count",
      all(SYL.DropRules.CountsAsUpgrade(drops[i + 1]) for i in range(3)))

keys, counts, points, labels, count = lua.globals().GroupsFor(
    drops, sessions)

check("all three items reach the pane", count == 3, "got %s" % count)

names = [str(keys[i + 1]) for i in range(len(keys))]
sizes = [int(counts[i + 1]) for i in range(len(counts))]
scores = [int(points[i + 1]) for i in range(len(points))]
groups = names

# THE POINT OF THIS FILE. Two of these drops are stamped 2025-08-13 and one
# 2025-08-14; all three belong to the one Tuesday raid.
check("a raid past midnight is still one night",
      len(groups) == 1,
      "grouped into %d nights: %s" % (len(groups), names))

if len(groups) == 1:
    started = time.strftime("%Y-%m-%d", time.localtime(TUESDAY_2000))

    check("and it is the night the raid started, not the date on the drop",
          names[0] == started, "%s, expected %s" % (names[0], started))

    check("with every item under it", sizes[0] == 3, str(sizes))

    # THE ASSERTION THIS FILE WAS MISSING. The group was keyed on the session
    # all along -- that part was right and tested. What was never checked is
    # the heading actually PRINTED above it, which came from whichever drop
    # landed in the group first. ItemsFor sorts newest first, so that is the
    # latest win of the night, and a Tuesday raid ending after midnight was
    # grouped under Tuesday and then headed AUG 13.
    printed = str(SYL.RaidersDetailParts.NightLabel(labels[1]))
    expected = time.strftime("%b %d", time.localtime(TUESDAY_2000)).upper()

    check("and the heading printed over it names that same night",
          printed == expected, "printed %s, expected %s" % (printed, expected))

    # Mog weighs nothing, so the night's subtotal must not count it.
    check("the night's points exclude the mog",
          scores[0] == 200, "got %s" % scores)

# Without any session to place them against, the pane still has to group
# something rather than lumping every drop the addon has ever seen together.
bare, _sizes, _scores, _stamps, _count = lua.globals().GroupsFor(
    drops, lua.eval("{}"))

check("with no session at all it falls back to the drop's own date",
      len(bare) == 2, "got %d" % len(bare))

# The label, which Aimee renamed.
labels = [str(SYL.LootScore.LABELS[k]) for k in SYL.LootScore.LABELS]

check("transmog reads Mog everywhere", "Mog" in labels and
      "Transmog" not in labels, str(sorted(labels)))

# The sum line is the arithmetic somebody argues with, so it must not carry a
# term worth nothing -- and must still add up.
entry = lua.eval("""{
    key = "Someone", name = "Someone", ranked = true, share = 200,
    nights = 1, lootScore = 200, scoringWins = 2, lootWins = 3,
    byState = { [%d] = 2, [%d] = 1 },
}""" % (NEED, MOG))

summed = SYL.RaidersDetailParts.SumLine(entry)

check("the sum names only what scored, and adds up",
      summed is not None and "Mog" not in str(summed)
      and str(summed).endswith("= 200"),
      str(summed))

print()
print("FAILURES: %s" % (failures or "none"))
sys.exit(1 if failures else 0)
