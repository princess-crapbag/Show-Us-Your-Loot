"""Weighted loot value and the Share ranking, against the shipped LootScore.

Aimee's rules: Need 100, offspec and greed 20 each, transmog 0, no decay, and
the ranking is score divided by nights attended so that perfect attendance is
worth something. The star is a label and must move no total.

The floor is the case worth guarding hardest. Share is score ÷ nights, so a
trial with one night and no loot scores 0 and would sit above raiders who have
been there all tier — the exact failure the whole ranking exists to avoid.

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

# bindType 2 is Bind on Equip; only the link named 'boe' is one.
lua.execute(
    """
    C_Item = {
        GetItemInfo = function(link)
            if link == 'uncached' then return nil end
            local bindType = 1
            if link == 'boe' then bindType = 2 end
            return 'n', link, 4, 600, 80, '', '', 1, '', '', 0, 4, 1, bindType
        end,
    }
    """
)

for module in ("Utilities.lua", "LootHistoryAPI.lua"):
    lua.execute((CORE / module).read_text(encoding="utf-8"))

lua.execute(
    """
    ShowUsYourLoot.Players = { ResolveToMain = function(key) return key end }
    """
)

lua.execute((CORE / "LootScore.lua").read_text(encoding="utf-8"))

score = lua.globals().ShowUsYourLoot.LootScore
STATE = lua.globals().ShowUsYourLoot.LootHistoryAPI.ROLL_STATE
failures = []


def check(label, ok):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def drop(who, state, link="bop", difficulty=16, at=1000):
    """One raid drop won by `who` in `state`."""
    lua.execute(
        f"""
        Fixture = {{
            timestamp = {at},
            itemLink = '{link}',
            instanceType = 'raid',
            difficultyID = {difficulty},
            rolls = {{ {{ isWinner = true, guid = '{who}', state = {state} }} }},
        }}
        """
    )
    return lua.globals().Fixture


def totals_for(drops):
    lua.execute("Drops = {}")
    table = lua.globals().Drops
    for i, d in enumerate(drops, 1):
        table[i] = d
    return score.BuildTotals(table)


# --- the weights ----------------------------------------------------------
cases = [
    ("Need is 100", STATE.NeedMainSpec, 100),
    ("offspec is 20 — same as greed, her call", STATE.NeedOffSpec, 20),
    ("greed is 20", STATE.Greed, 20),
    ("transmog is 0 and deducts nothing", STATE.Transmog, 0),
]

for label, state, want in cases:
    got = totals_for([drop("P1", state)])["P1"].score
    check(label, got == want)

# Four Needs and a transmog: the transmog must not move the total either way.
combined = totals_for(
    [drop("P1", STATE.NeedMainSpec), drop("P1", STATE.Transmog)]
)
check("a transmog alongside a Need leaves the score alone", combined["P1"].score == 100)
check("but it still counts as a win", combined["P1"].wins == 2)

# --- what does not count --------------------------------------------------
check("a BoE scores nothing", totals_for([drop("P1", STATE.NeedMainSpec, link="boe")])["P1"] is None)
check(
    "a Timewalking win scores nothing",
    totals_for([drop("P1", STATE.NeedMainSpec, difficulty=33)])["P1"] is None,
)
check(
    "an uncached item still counts",
    totals_for([drop("P1", STATE.NeedMainSpec, link="uncached")])["P1"].score == 100,
)

# --- share, the ranking ---------------------------------------------------
lua.execute(
    """
    function Entries()
        return {
            -- 240 over 13 nights against 240 over 7: same score, different
            -- share. This is Aimee's rule in one fixture.
            { key = 'Selunne', name = 'Selunne', nights = 13 },
            { key = 'Vyx',     name = 'Vyx',     nights = 7 },
            { key = 'Trial',   name = 'Trial',   nights = 1 },
            { key = 'Fresh',   name = 'Fresh',   nights = 0 },
        }
    end
    """
)

# 2 Needs + 2 greeds = 240 each, earned over different numbers of nights.
drops = []
drops += [drop("Selunne", STATE.NeedMainSpec)] * 2
drops += [drop("Selunne", STATE.Greed)] * 2
drops += [drop("Vyx", STATE.NeedMainSpec)] * 2
drops += [drop("Vyx", STATE.Greed)] * 2

lua.execute("Drops = {}")
table = lua.globals().Drops
for i, d in enumerate(drops, 1):
    table[i] = d

entries = lua.globals().Entries()
score.Attach(entries, table)

rows = {e.key: e for e in entries.values()}

check("equal scores are recorded equally", rows["Selunne"].lootScore == rows["Vyx"].lootScore == 240)
check("share divides by nights", abs(rows["Selunne"].share - 240 / 13) < 0.001)
check(
    "better attendance means a lower share, so more due",
    rows["Selunne"].share < rows["Vyx"].share,
)

# --- the floor ------------------------------------------------------------
check("one night is under the floor", rows["Trial"].ranked is False)
check("and gets no share rather than a zero", rows["Trial"].share is None)
check("with a reason to print", "under 3 nights" in rows["Trial"].notRankedReason)
check("never raided says so differently", "has not raided yet" in rows["Fresh"].notRankedReason)

score.Sort(entries)
order = [e.name for e in entries.values()]

check("most due first", order[0] == "Selunne")
# The whole reason the floor exists.
check("nobody unranked outranks a real raider", order[-2:] == ["Fresh", "Trial"] or order[-2:] == ["Trial", "Fresh"])

avg, counted = score.Average(entries)
check("the average counts only ranked raiders", counted == 2)
check("and is the mean of their shares", abs(avg - (240 / 13 + 240 / 7) / 2) < 0.001)

# --- bars -----------------------------------------------------------------
highest = score.Highest(entries)
check("the highest share sets the scale", abs(highest - 240 / 7) < 0.001)
check("the longest bar fills the track", abs(score.BarFraction(rows["Vyx"], highest) - 1.0) < 0.001)
check("an unranked raider has no bar", score.BarFraction(rows["Trial"], highest) == 0)

# --- stars ----------------------------------------------------------------
lua.execute("Rec = {}")
rec = lua.globals().Rec
check("nothing is starred to begin with", score.IsStarred(rec) is False)
score.ToggleStar(rec)
check("a star sticks", score.IsStarred(rec) is True)
score.ToggleStar(rec)
check("and comes off again", score.IsStarred(rec) is False)
# nil rather than false, so a season of records carries no field per drop.
check("off is stored as nothing at all", rec["starred"] is None)

starred = drop("P1", STATE.NeedMainSpec)
score.ToggleStar(starred)
check("a star moves no total", totals_for([starred])["P1"].score == 100)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
