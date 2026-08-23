# -*- coding: utf-8 -*-
"""The weights and the guild threshold, now that both are settings.

These were constants and every number the addon prints derives from them, so
the risk in making them editable is not that the setting fails to save -- it is
that something goes on reading the old constant and two screens quietly
disagree about what a win is worth.

THE OFFSPEC LINK IS THE PART THAT NEEDS A TEST. Four roll states exist and the
settings screen shows three, because Aimee asked for three: "leave the 4
weights, i only want to see the 3 for me if possible." That is only safe while
the hidden weight follows a visible one. If offspec ever stops following greed,
her season's sixteen offspec rolls start scoring at a number nobody can see and
nobody can explain, which is the exact failure the fairness board exists to
prevent.
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


def reset():
    lua.execute("ShowUsYourLootDB = "
                "{ settings = {}, features = {}, dashboard = {} }")


STATE = SYL.LootHistoryAPI.ROLL_STATE
NEED, OFFSPEC, GREED, MOG = (STATE.NeedMainSpec, STATE.NeedOffSpec,
                             STATE.Greed, STATE.Transmog)

Score = SYL.LootScore
Session = SYL.RaidSession


def weights():
    return tuple(int(Score.WeightOf(s)) for s in (NEED, OFFSPEC, GREED, MOG))


# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------

reset()

check("a fresh install scores the way it always did",
      weights() == (100, 20, 20, 0), str(weights()))

check("and the defaults are still declared",
      int(Score.DEFAULT_WEIGHTS[NEED]) == 100)

# --------------------------------------------------------------------------
# Editing
# --------------------------------------------------------------------------

check("a weight can be set", Score.SetWeight(NEED, 50))
check("and it is what scores now", int(Score.WeightOf(NEED)) == 50)

check("a negative weight is refused", not Score.SetWeight(NEED, -1))
check("and refusing leaves the old one alone", int(Score.WeightOf(NEED)) == 50)

check("a non-number is refused", not Score.SetWeight(NEED, "lots"))

# Setting one must not disturb another.
reset()
Score.SetWeight(MOG, 5)

check("setting one weight leaves the rest at their defaults",
      weights() == (100, 20, 20, 5), str(weights()))

# --------------------------------------------------------------------------
# The offspec link, which is the whole reason three rows is safe
# --------------------------------------------------------------------------

reset()

check("offspec is linked to greed out of the box", not Score.IsOffspecSplit())

Score.SetWeight(GREED, 10)

check("so lowering greed lowers offspec with it",
      weights() == (100, 10, 10, 0), str(weights()))

Score.SetWeight(GREED, 35)

check("and raising it raises offspec too",
      weights() == (100, 35, 35, 0), str(weights()))

check("three rows are drawn while they are linked",
      len(Score.EditableStates()) == 3)

Score.SetOffspecSplit(True)

check("splitting them draws a fourth row",
      len(Score.EditableStates()) == 4)

Score.SetWeight(OFFSPEC, 60)

check("and offspec can then differ from greed",
      weights() == (100, 60, 35, 0), str(weights()))

Score.SetOffspecSplit(False)

check("re-linking sends offspec back to greed's number",
      weights() == (100, 35, 35, 0),
      "a stale 60 here is the bug this whole file is about: %s" % str(weights()))

# --------------------------------------------------------------------------
# The guild threshold
# --------------------------------------------------------------------------

reset()

check("the threshold defaults to 80%",
      abs(float(Session.GuildThreshold()) - 0.80) < 0.001,
      str(Session.GuildThreshold()))

check("it can be set", Session.SetGuildThreshold(60))
check("and reads back as a fraction",
      abs(float(Session.GuildThreshold()) - 0.60) < 0.001)

check("over 100 is refused", not Session.SetGuildThreshold(120))
check("below zero is refused", not Session.SetGuildThreshold(-1))
check("and a refusal leaves the old one alone",
      abs(float(Session.GuildThreshold()) - 0.60) < 0.001)

# The one that would be silent: a second function of the same name replaces
# the first, and RaidSession.GuildShare(session) is a different question --
# what fraction of one night was guild.
check("the per-session GuildShare still exists beside it",
      Session.GuildShare is not None and Session.GuildThreshold is not None)

check("and they are not the same function",
      Session.GuildShare != Session.GuildThreshold)

print()
print("FAILURES: %s" % (failures or "none"))
sys.exit(1 if failures else 0)
