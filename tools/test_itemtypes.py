# -*- coding: utf-8 -*-
"""The item-type filter: what it catches, and what it must never drop.

Core/ItemTypes.lua gates CAPTURE, not display. An untracked type is never
written to the database at all, and nothing recovers it afterwards -- so the
dangerous fault here is not "the filter fails to filter", it is "the filter
drops something it was never asked to drop". That is silent, permanent, and
looks exactly like a quiet raid night.

So the assertions that matter are the negative ones:

  AN UNKNOWN ITEM IS RECORDED. GetItemInfoInstant answers nothing for an id
  the client has never seen, and every drop of a brand new tier is that item
  for a moment.

  A CLASS NONE OF THE NINE ROWS COVERS IS RECORDED. Consumables, containers,
  gems and glyphs are not on the settings screen, so nobody has turned them
  off and nothing may act as though they had.

  DEFAULTS RECORD EVERYTHING. Somebody upgrading from 0.4.0 must capture
  exactly what they captured yesterday.

The classification itself is tested against the real client's numbers, driven
through a stubbed GetItemInfoInstant -- the test client's own returns nil, which
is the "unknown" case and would otherwise be the only case ever exercised.
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


Types = SYL.ItemTypes


# --------------------------------------------------------------------------
# A client that answers
# --------------------------------------------------------------------------
#
# Keyed on the item id in the link, so a test names an item rather than a
# number. The classes are the live ones -- Armor 4, Weapon 2, Tradegoods 7,
# Questitem 12, Miscellaneous 15, Battlepet 17, Housing 20 -- and the
# miscellaneous subclasses are CompanionPet 2, Mount 5, MountEquipment 6.
lua.execute("""
    ITEM_CLASSES = {
        [100] = { 4, 1 },     -- a chest piece            Armor
        [101] = { 2, 7 },     -- a mace                   Weapon
        [102] = { 20, 0 },    -- Black Housing Dye        Housing
        [103] = { 15, 5 },    -- a mount                  Misc / Mount
        [104] = { 15, 2 },    -- a pet                    Misc / CompanionPet
        [105] = { 17, 0 },    -- a caged pet              Battlepet
        [106] = { 7, 6 },     -- Void-Tempered Hide       Tradegoods
        [107] = { 12, 0 },    -- a quest item             Questitem
        [108] = { 9, 0 },     -- a recipe                 Recipe
        [109] = { 0, 1 },     -- a flask                  Consumable, no row
        [110] = { 15, 4 },    -- a toy                    Misc / Other
        [111] = { 15, 6 },    -- mount equipment          Misc / MountEquipment
    }

    TOY_IDS = { [110] = true }

    C_Item.GetItemInfoInstant = function(link)
        local id = tonumber(tostring(link):match('item:(%d+)'))
        local entry = id and ITEM_CLASSES[id]

        if not entry then
            return nil
        end

        -- itemID, itemType, itemSubType, equipLoc, icon, classID, subclassID
        return id, 'Type', 'SubType', '', 0, entry[1], entry[2]
    end

    C_ToyBox = {
        GetToyInfo = function(id)
            if TOY_IDS[id] then return id, 'A Toy' end
            return nil
        end,
    }

    -- Warbound is read from the bind type through Utilities.IsWarbound, which
    -- uses the cached call. Nothing is warbound unless a test says so.
    WARBOUND_IDS = {}

    C_Item.GetItemInfo = function(link)
        local id = tonumber(tostring(link):match('item:(%d+)'))
        local bind = WARBOUND_IDS[id] and 8 or 1

        return 'Name', link, 4, 0, 0, '', '', 1, '', 0, 0, 0, 0, bind
    end

    function LINK(id)
        return '|cffa335ee|Hitem:' .. id .. '::::::::80:::::|h[Item]|h|r'
    end
""")

LINK = lua.globals().LINK


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------

reset()

for label, item_id, expected in (
    ("armor is gear", 100, "gear"),
    ("a weapon is gear", 101, "gear"),
    ("housing dye is decor", 102, "decor"),
    ("a mount is a mount", 103, "mounts"),
    ("a companion pet is a pet", 104, "pets"),
    ("a caged pet is a pet", 105, "pets"),
    ("a hide is a reagent", 106, "reagents"),
    ("a quest item is a quest item", 107, "quest"),
    ("a recipe is profession supplies", 108, "profession"),
    ("mount equipment is a mount", 111, "mounts"),
):
    got = Types.Classify(LINK(item_id))
    check(label, got == expected, "got %r" % got)

# A TOY IS MISCELLANEOUS LIKE A MOUNT IS and carries no subclass that says so,
# so it has to be asked about before the subclasses are. Reversing those two
# tests in Classify makes this the only assertion that fails.
check("a toy is a toy and not miscellaneous nothing",
      Types.Classify(LINK(110)) == "toys",
      "got %r" % Types.Classify(LINK(110)))

# --------------------------------------------------------------------------
# The negative cases, which are the whole point
# --------------------------------------------------------------------------

check("a class no row covers classifies as nothing",
      Types.Classify(LINK(109)) is None)

check("and is therefore recorded", Types.ShouldTrackLink(LINK(109)))

check("an item the client cannot identify classifies as nothing",
      Types.Classify(LINK(999)) is None)

check("and is therefore recorded", Types.ShouldTrackLink(LINK(999)))

check("a nil link is recorded rather than dropped",
      Types.ShouldTrackLink(None))

check("so is an empty one", Types.ShouldTrackLink(""))

# --------------------------------------------------------------------------
# Warbound is a split of gear, not a class
# --------------------------------------------------------------------------

lua.execute("WARBOUND_IDS = { [100] = true }")

check("warbound armor lands on the warbound row",
      Types.Classify(LINK(100)) == "warbound",
      "got %r" % Types.Classify(LINK(100)))

check("plain armor still lands on gear",
      Types.Classify(LINK(101)) == "gear")

lua.execute("WARBOUND_IDS = {}")

# --------------------------------------------------------------------------
# Tracking
# --------------------------------------------------------------------------

reset()

check("every type is recorded on a fresh install",
      int(Types.CountTracked()) == len(list(Types.ORDER.values())))

for key in Types.ORDER.values():
    if not Types.IsTracked(key):
        check("default records %s" % key, False)

check("nine rows, which is what the settings screen draws",
      len(list(Types.ORDER.values())) == 9)

check("every row has a name",
      all(Types.NAMES[k] for k in Types.ORDER.values()))

# EVERY ROW HAS A NOTE. Two words cannot say what "Sparks and hides" catches,
# and a row that turns off recording gear entirely must not be one click away
# from somebody who has not been told what it does.
check("and every row has an explanation",
      all(Types.NOTES[k] for k in Types.ORDER.values()))

Types.SetTracked("mounts", False)

check("a type can be turned off", not Types.IsTracked("mounts"))
check("and the count follows", int(Types.CountTracked()) == 8)
check("a mount is now skipped", not Types.ShouldTrackLink(LINK(103)))
check("and gear is not", Types.ShouldTrackLink(LINK(100)))

Types.SetTracked("mounts", True)
check("and back on again", Types.ShouldTrackLink(LINK(103)))

# --------------------------------------------------------------------------
# The database wires the defaults in
# --------------------------------------------------------------------------

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

check("a fresh database carries the item-type defaults",
      lua.globals().ShowUsYourLootDB.settings.trackedItemTypes is not None)

check("and they record everything",
      int(Types.CountTracked()) == 9)

# --------------------------------------------------------------------------
# Both filters are asked, and an item has to pass both
# --------------------------------------------------------------------------
#
# Read out of the source rather than driven through a capture, because the
# thing that can go wrong is a hook site being dropped in a refactor -- and a
# behavioural test would still pass with one of the two sites gone.

for path in ("Core/LootCapture.lua", "Core/LootHistoryStore.lua"):
    source = test_load.ROOT.joinpath(path).read_text(encoding="utf-8")

    check("%s asks the quality filter" % path,
          "ItemQuality.ShouldTrackLink" in source)

    check("%s asks the item type filter" % path,
          "ItemTypes.ShouldTrackLink" in source)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)
