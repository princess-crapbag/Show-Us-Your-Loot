-- Core/ItemTypes.lua
--
-- Which KINDS of item are worth recording, beside Core/ItemQuality.lua's
-- which grades.
--
-- Quality alone cannot say "record epics but not the epic mount". A Mythic
-- raid night drops gear, a mount, a housing decor piece and a fistful of
-- crafting reagents, and they are all the same purple. The fairness board
-- only argues about one of those, so the other three are noise in every list
-- that reads the season.
--
-- SAME CONTRACT AS QUALITY, deliberately: this gates CAPTURE, not display.
-- An untracked type is never written to the database, records already saved
-- stay saved, and items skipped while a type was off are gone for good. Both
-- filters are asked in the same two places -- Core/LootCapture.lua and
-- Core/LootHistoryStore.lua -- and an item has to pass both.
--
-- UNKNOWN IS ALWAYS RECORDED. GetItemInfoInstant answers nothing for an item
-- id the client has never seen, and a filter that drops what it cannot
-- identify would quietly lose the drop that mattered. The cost of guessing
-- wrong the other way is one extra row.
--
-- CLASS IDS ARE WRITTEN AS NUMBERS AND READ FROM THE ENUM. The numbers are
-- the fallback so this file loads and works against a client that exposes no
-- Enum table at all -- which is exactly what the test harness is, and what
-- left ItemQuality listing its own values rather than reading them. The live
-- enum wins when it is there, so a renumbering follows the client rather than
-- this file. That is the lesson of the Enum.ItemBind warbound fallback, which
-- is still on page one of HANDOFF.md as a thing that would be wrong invisibly.

local SYL = _G.ShowUsYourLoot

local ItemTypes = {}
SYL.ItemTypes = ItemTypes

--------------------------------------------------------------------------
-- The client's numbers
--------------------------------------------------------------------------

-- Enum.ItemClass. Named in the comment so a reader can check them against
-- the client, and resolved through Lookup below so the enum is what is
-- actually used when the client has one.
local CLASS = {
    Weapon = 2,        -- Enum.ItemClass.Weapon
    Reagent = 5,       -- Enum.ItemClass.Reagent
    Tradegoods = 7,    -- Enum.ItemClass.Tradegoods
    ItemEnhancement = 8, -- Enum.ItemClass.ItemEnhancement
    Recipe = 9,        -- Enum.ItemClass.Recipe
    Questitem = 12,    -- Enum.ItemClass.Questitem
    Key = 13,          -- Enum.ItemClass.Key
    Miscellaneous = 15, -- Enum.ItemClass.Miscellaneous
    Battlepet = 17,    -- Enum.ItemClass.Battlepet
    Profession = 19,   -- Enum.ItemClass.Profession
    Armor = 4,         -- Enum.ItemClass.Armor

    -- HOUSING IS THE ONE THAT WAS ACTUALLY IN DOUBT, and it is confirmed
    -- rather than guessed: five addons already installed on this machine key
    -- decor on Enum.ItemClass.Housing -- RCLootCouncil/Core/Constants.lua:211,
    -- Auctionator/Source/Groups/Constants.lua:47, Syndicator's
    -- Search/CheckItem.lua:375 (which also names Enum.ItemHousingSubclass.
    -- Decor), EllesmereUIBags and !WilduTools. Aimee's screenshot of four
    -- unlearned decor items is what raised it.
    --
    -- Keyed on the CLASS and not the subclass, which is what RCLootCouncil
    -- does. Every subclass under Housing is a housing item; splitting decor
    -- from dyes would be a second row nobody asked for.
    Housing = 20,      -- Enum.ItemClass.Housing
}

-- Enum.ItemMiscellaneousSubclass. Junk 0, Reagent 1, CompanionPet 2,
-- Holiday 3, Other 4, Mount 5, MountEquipment 6 -- the spellings confirmed
-- against Altoholic_Search/TabSearch.lua:493-499 and RareScanner, which list
-- the whole set.
local MISC = {
    CompanionPet = 2,
    Mount = 5,
    MountEquipment = 6,
}

-- Resolved lazily and cached, never at load. A file-scope read of a nil
-- Enum is the fault that killed the whole quality section once already --
-- see the QualityColor note in UI/SettingsRows.lua.
local resolved = {}

local function Lookup(table_, name, fallback)
    local key = name .. "@" .. tostring(fallback)

    if resolved[key] == nil then
        local live = _G.Enum and _G.Enum[table_] and _G.Enum[table_][name]

        resolved[key] = type(live) == "number" and live or fallback
    end

    return resolved[key]
end

local function ItemClass(name)
    return Lookup("ItemClass", name, CLASS[name])
end

local function MiscSubclass(name)
    return Lookup("ItemMiscellaneousSubclass", name, MISC[name])
end

--------------------------------------------------------------------------
-- The nine rows
--------------------------------------------------------------------------

-- The order the settings screen draws them in, and the order they are tested
-- in below. Both matter: a toy is Miscellaneous like a mount is, so "toys"
-- has to be asked before the miscellaneous classes are.
ItemTypes.ORDER = {
    "gear",
    "warbound",
    "pets",
    "mounts",
    "toys",
    "decor",
    "profession",
    "quest",
    "reagents",
}

ItemTypes.NAMES = {
    gear = "Raid gear",
    warbound = "Warbound gear",
    pets = "Pets",
    mounts = "Mounts",
    toys = "Toys",
    decor = "Housing decor",
    profession = "Profession supplies",
    quest = "Quest items",
    reagents = "Sparks and hides",
}

-- Said on hover, because nine labels of one or two words cannot carry what
-- each one actually catches, and "Sparks and hides" is Aimee's name for a
-- category the client has no name for at all.
ItemTypes.NOTES = {
    gear = "Armor and weapons. This is what the fairness board is about — "
        .. "turning it off stops the addon recording the thing it exists for.",

    warbound = "Armor and weapons that can be sent to your other characters. "
        .. "They are recorded but never counted as an upgrade, because the "
        .. "rule has always been bind-on-pickup.",

    pets = "Battle pets, caged or not.",

    mounts = "Mounts and mount equipment.",

    toys = "Anything that goes into the toy box.",

    decor = "Housing decor and dyes.",

    profession = "Recipes, patterns, techniques, and profession tools.",

    quest = "Quest items and keys.",

    reagents = "Crafting materials — sparks, hides, cloth, leather, ore and "
        .. "the rest. Raid bosses drop these and people roll on them.",
}

-- EVERYTHING ON UNTIL IT IS TURNED OFF, for the same reason quality starts
-- permissive: a fresh install must never quietly miss loot, and an upgrade
-- from 0.4.0 has to record exactly what it recorded yesterday. Defaults that
-- filtered anything would change what an existing season captures without
-- anybody asking for it.
function ItemTypes.GetDefaults()
    local defaults = {}

    for _, key in ipairs(ItemTypes.ORDER) do
        defaults[key] = true
    end

    return defaults
end

local function GetSettings()
    if not ShowUsYourLootDB or not ShowUsYourLootDB.settings then
        return nil
    end

    ShowUsYourLootDB.settings.trackedItemTypes =
        ShowUsYourLootDB.settings.trackedItemTypes or ItemTypes.GetDefaults()

    return ShowUsYourLootDB.settings.trackedItemTypes
end

function ItemTypes.IsTracked(key)
    -- An unclassified item is always recorded. See the header.
    if key == nil then
        return true
    end

    local tracked = GetSettings()

    if not tracked then
        return true
    end

    return tracked[key] ~= false
end

function ItemTypes.SetTracked(key, enabled)
    local tracked = GetSettings()

    if not tracked then
        return
    end

    tracked[key] = enabled and true or false
end

function ItemTypes.CountTracked()
    local tracked = GetSettings()
    local count = 0

    if not tracked then
        return 0
    end

    for _, key in ipairs(ItemTypes.ORDER) do
        if tracked[key] ~= false then
            count = count + 1
        end
    end

    return count
end

--------------------------------------------------------------------------
-- Which row an item belongs to
--------------------------------------------------------------------------

-- GetItemInfoInstant and not GetItemInfo: it answers from the item id alone
-- and never needs the item cached, which is the difference between a filter
-- that works on the first drop of the night and one that works on the
-- second. Quality has to use the cached call; the class does not.
local function ClassOf(itemLink)
    local instant = C_Item and C_Item.GetItemInfoInstant

    if not instant then
        return nil, nil
    end

    local success, _id, _type, _subType, _equipLoc, _icon, classID, subclassID =
        pcall(instant, itemLink)

    if not success then
        return nil, nil
    end

    return classID, subclassID
end

local function IsToy(itemLink)
    if not C_ToyBox or not C_ToyBox.GetToyInfo then
        return false
    end

    local itemID = SYL.Utilities.GetItemIDFromLink(itemLink)

    if not itemID then
        return false
    end

    -- Syndicator/Search/CheckItem.lua:825 asks exactly this way, and it is
    -- the only reliable test: a toy is Miscellaneous like a mount is, and
    -- carries no subclass of its own.
    local success, info = pcall(C_ToyBox.GetToyInfo, itemID)

    return success and info ~= nil
end

-- Which of the nine an item is, or nil for anything the nine do not cover.
--
-- NIL IS A REAL ANSWER AND NOT A FAILURE. Consumables, containers, gems and
-- glyphs are none of these rows, and the nine are not meant to be a partition
-- of everything the game has -- they are the kinds that turn up in a raid's
-- loot history. Anything else is recorded, which is what the addon did before
-- this file existed.
function ItemTypes.Classify(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local classID, subclassID = ClassOf(itemLink)

    if classID == nil then
        return nil
    end

    if classID == ItemClass("Housing") then
        return "decor"
    end

    if classID == ItemClass("Battlepet") then
        return "pets"
    end

    if classID == ItemClass("Miscellaneous") then
        -- Before the subclasses, because a toy has no subclass that says so.
        if IsToy(itemLink) then
            return "toys"
        end

        if subclassID == MiscSubclass("CompanionPet") then
            return "pets"
        end

        if subclassID == MiscSubclass("Mount")
            or subclassID == MiscSubclass("MountEquipment")
        then
            return "mounts"
        end

        return nil
    end

    if classID == ItemClass("Armor") or classID == ItemClass("Weapon") then
        -- WARBOUND IS A SPLIT OF GEAR, not a class of its own. The client
        -- reports it in the bind type, not the item class, so it is asked
        -- here rather than in ClassOf. Utilities.IsWarbound answers nil for
        -- an uncached item and every caller reads that as "not warbound" --
        -- which here means the drop lands on the "gear" row, the one that is
        -- on by default.
        if SYL.Utilities.IsWarbound(itemLink) == true then
            return "warbound"
        end

        return "gear"
    end

    if classID == ItemClass("Recipe") or classID == ItemClass("Profession") then
        return "profession"
    end

    if classID == ItemClass("Questitem") or classID == ItemClass("Key") then
        return "quest"
    end

    if classID == ItemClass("Tradegoods")
        or classID == ItemClass("Reagent")
        or classID == ItemClass("ItemEnhancement")
    then
        return "reagents"
    end

    return nil
end

function ItemTypes.ShouldTrackLink(itemLink)
    return ItemTypes.IsTracked(ItemTypes.Classify(itemLink))
end
