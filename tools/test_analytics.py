"""Analytics.BuildPlayerStats — the UPGRADES column, and who a win belongs to.

This file feeds the Players window and Core/Export.lua, which is the block that
gets pasted into Discord. It had no copy of the rules the Raiders board and the
due list apply, so the same raider had two different upgrade counts depending
on which screen you asked, and the exported one is the one other people read.

TWO DEFECTS ARE UNDER TEST HERE.

  * A bind-on-equip, warbound or non-raid win counted as an upgrade. Those are
    excluded everywhere else: a BoE is something sellable and a warbound piece
    is account gear, so neither says the raider standing there was looked after.

  * The roll winner was credited rather than the trade recipient. Aimee is her
    guild's master looter, so she receives every drop and hands it out — which
    meant this file credited the entire raid's loot to her.

The eligibility half must NOT move with the credit: everybody in the roll list
was there and rolled, whoever ended up holding the item.

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

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "Core"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("ShowUsYourLoot = {}")
lua.execute("ShowUsYourLootDB = { settings = {} }")

# Fixed, so the drought arithmetic is the same on every run. Drop timestamps
# below are 1000, which makes every win one day old.
lua.execute("time = function() return 1000 + 86400 end")

# bindType 2 is Bind on Equip; 7/8/9 are the warbound values the live client
# reports (confirmed on 12.1.0 build 69382 via /syl api).
lua.execute(
    """
    C_Item = {
        GetItemInfo = function(link)
            local bindType = 1
            if link == 'boe' then bindType = 2 end
            if link == 'warbound' then bindType = 7 end
            return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                   nil, bindType
        end,
    }
    Enum = { ItemBind = {
        ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9,
    } }
    """
)

for module in ("Output.lua", "Utilities.lua", "LootHistoryAPI.lua",
               "DropRules.lua"):
    lua.execute((CORE / module).read_text(encoding="utf-8"))

# Stubs for everything Analytics reaches that is not the maths under test.
# Players folds alts to mains; here every character is its own person.
lua.execute(
    """
    ShowUsYourLoot.Players = {
        ResolveToMain = function(key) return key end,
        Get = function(key) return { guid = key, name = key } end,
    }

    ShowUsYourLoot.Guild = {
        GetMemberForPlayer = function() return nil end,
        GetMembers = function() return {} end,
    }

    -- No roster attendance: these tests are about loot, and nights from the
    -- roster would overwrite the ones counted from drop dates.
    ShowUsYourLoot.RaidSession = {
        BuildAttendance = function() return {}, {} end,

        -- Added when the fairness math adopted the guild-share rule. There are
        -- no sessions in this fixture, so the real one would find none and
        -- answer true — unknown counts, the rule stated in
        -- RaidSession.CountsAsNight. tools/test_guildnights.py owns that
        -- behavior; these assertions are about credit and upgrade counting.
        IsGuildNightAt = function() return true end,
    }

    ShowUsYourLoot.GetActiveRaids = function() return {} end

    -- Trading is on, which is the case that matters. TradeTracker's own
    -- resolution order is GUID before name; both are the same string here.
    ShowUsYourLoot.TradeTracker = {
        IsEnabled = function() return true end,
        CreditedIdentity = function(drop, raw)
            if drop.tradedToGUID and drop.tradedToGUID ~= '' then
                return drop.tradedToGUID
            end
            return raw
        end,
    }
    """
)

lua.execute((CORE / "Analytics.lua").read_text(encoding="utf-8"))

Analytics = lua.globals().ShowUsYourLoot.Analytics
STATE = lua.globals().ShowUsYourLoot.LootHistoryAPI.ROLL_STATE

failures = []


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       got: " + repr(detail))

        failures.append(label)


def drop(winner, state=None, link="normal", traded_to=None, losers=(),
         difficulty=14, instance_type="raid"):
    rolls = [lua.table_from({
        "guid": winner, "name": winner, "isWinner": True,
        "state": STATE.NeedMainSpec if state is None else state,
    })]

    for loser in losers:
        rolls.append(lua.table_from({
            "guid": loser, "name": loser, "state": STATE.NeedMainSpec,
        }))

    fields = {
        "itemLink": link,
        "timestamp": 1000,
        "dateText": "08/19/2026",
        "instanceType": instance_type,
        "difficultyID": difficulty,
        "rolls": lua.table_from(rolls),
    }

    if traded_to:
        fields["tradedToGUID"] = traded_to
        fields["tradedTo"] = traded_to

    return lua.table_from(fields)


def stats_for(*drops):
    built = Analytics.BuildPlayerStats(lua.table_from(list(drops)))

    return {entry.key: entry for entry in built.values()}


# --- what counts as an upgrade -------------------------------------------
rows = stats_for(
    drop("Plain"),
    drop("Boe", link="boe"),
    drop("Warby", link="warbound"),
)

check("an ordinary need win is an upgrade", rows["Plain"].upgradeWins == 1)
check("a bind-on-equip win is not", rows["Boe"].upgradeWins == 0)
check("a warbound win is not", rows["Warby"].upgradeWins == 0)

check(
    "but all three are still counted as wins",
    rows["Plain"].wins == 1 and rows["Boe"].wins == 1 and rows["Warby"].wins == 1,
    (rows["Plain"].wins, rows["Boe"].wins, rows["Warby"].wins),
)

# A Mythic+ dungeon is not raid content, so nothing from one is an upgrade.
dungeon = stats_for(drop("Runner", instance_type="party", difficulty=8))
check("a dungeon win is not an upgrade", dungeon["Runner"].upgradeWins == 0)

# --- greed and transmog stay out of upgrades, and in their own columns ----
rows = stats_for(
    drop("Greedy", state=STATE.Greed),
    drop("Mogger", state=STATE.Transmog),
    drop("Offspec", state=STATE.NeedOffSpec),
)

check("a greed win is not an upgrade", rows["Greedy"].upgradeWins == 0)
check("and is still counted as greed", rows["Greedy"].greedWins == 1)
check("a transmog win is not an upgrade", rows["Mogger"].upgradeWins == 0)
check("and is still counted as transmog", rows["Mogger"].mogWins == 1)
check("an offspec win IS an upgrade", rows["Offspec"].upgradeWins == 1)

# --- the master looter case ----------------------------------------------
# Aimee wins the roll and trades the item to Raider. The upgrade is Raider's.
rows = stats_for(drop("Aimee", traded_to="Raider", losers=("Raider",)))

check("a traded win does not count for the winner",
      rows["Aimee"].upgradeWins == 0, rows["Aimee"].upgradeWins)
check("it counts for whoever received it",
      rows["Raider"].upgradeWins == 1, rows["Raider"].upgradeWins)

check(
    "and eligibility stays where the rolls were",
    rows["Aimee"].eligible == 1 and rows["Raider"].eligible == 1,
    (rows["Aimee"].eligible, rows["Raider"].eligible),
)

# The recipient need not have rolled at all — a master looter hands items to
# people who were not eligible for that particular drop.
rows = stats_for(drop("Aimee", traded_to="Latecomer"))

check("a recipient who never rolled still gets the credit",
      rows["Latecomer"].upgradeWins == 1)
check("and is not credited with having been eligible",
      rows["Latecomer"].eligible == 0, rows["Latecomer"].eligible)

# --- the drought clock ----------------------------------------------------
# lastWinAt drives "days since an upgrade", so it must only move on an upgrade.
rows = stats_for(drop("Sellsword", link="boe"))

check("a BoE win does not restart the drought",
      rows["Sellsword"].lastWinAt is None, rows["Sellsword"].lastWinAt)

rows = stats_for(drop("Geared"))
check("a real upgrade does", rows["Geared"].lastWinAt == 1000)

# --- the credited person is not wearing the winner's name -----------------
#
# The first version of this rewrite passed the WINNER's roll to Ensure when
# creating the recipient's entry, so a traded item produced a second row with
# the master looter's name, class and GUID under the recipient's key. On a
# 20-person raid where the looter wins every roll, that is twenty rows all
# reading "Aimee" and one of them being everybody else.

rows = stats_for(drop("Aimee", traded_to="Latecomer"))

check(
    "the credited entry is named after the person credited",
    rows["Latecomer"].name == "Latecomer",
    rows["Latecomer"].name,
)
check(
    "and does not inherit the winner's class",
    rows["Latecomer"].class_ is None if hasattr(rows["Latecomer"], "class_")
    else rows["Latecomer"]["class"] is None,
    rows["Latecomer"]["class"],
)
check(
    "while the winner keeps their own name",
    rows["Aimee"].name == "Aimee",
    rows["Aimee"].name,
)

# The ordinary untraded case must still carry the roll's identity.
rows = stats_for(drop("Solo"))
check("an untraded winner still gets their identity from the roll",
      rows["Solo"].name == "Solo", rows["Solo"].name)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
