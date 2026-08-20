-- Core/PersonalLoot.lua
--
-- Gear that arrived without a roll: the Great Vault, a Mythic+ chest, a
-- catalyst conversion, anything awarded rather than won.
--
-- WHY THE FAIRNESS NUMBERS NEEDED THIS. Everything derived — the due list,
-- droughts, who went home empty handed — reads season.drops, which is the
-- group-loot roll history. In current retail a large share of gearing never
-- touches a roll, so somebody claiming a mythic-track vault item every week
-- appeared in the due list as though they had received nothing at all. The
-- number was not slightly off; it was blind to a whole channel.
--
-- THE TRAP: CHAT LOOT ALREADY CONTAINS THE ROLLS. Winning a group-loot roll
-- also prints "You receive loot", so season.loot overlaps season.drops
-- almost entirely inside a raid. Folding one into the other without
-- subtracting the overlap would count every raid drop twice and make the
-- fairness math worse than leaving it alone.
--
-- So a chat record only counts here when it is
--   * equippable gear of a quality worth tracking, and
--   * not matched by a drop already recorded for the same player and item.
--
-- Pure computation over the records, like Analytics. Nothing stored.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local PersonalLoot = {}
SYL.PersonalLoot = PersonalLoot

-- How far apart a chat line and its drop record may sit and still be the same
-- award. The two are written by different code paths on different events, and
-- the loot history one can resolve a while after the item is handed over.
local MATCH_WINDOW_SECONDS = 180

-- Epic and above.
--
-- This was rare, and rare is too low to mean anything on a max-level
-- character. Every gear track a raider is actually chasing — Veteran through
-- Myth — awards epics; blue is Explorer and Adventurer, which is levelling
-- gear and world drops. A Mythic raider who picked up a blue ring in Dornogal
-- had their drought reset by it, which is the opposite of what this number is
-- for.
--
-- The loot list's own quality filter is a separate setting and stays where it
-- is: recording a green is fine, counting it as an upgrade is not.
local MINIMUM_QUALITY = 4

local function NameKey(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    -- Chat gives the player's own full name and other people's short one, and
    -- the loot history is inconsistent the other way. Compare on the short
    -- name, lowercased, which is the part both always carry.
    local short = name:match("^([^-]+)") or name

    return short:lower()
end

PersonalLoot.NameKey = NameKey

-- Gear is decided by item class, not by whether it reports an equip slot.
--
-- The slot test was the first attempt and it leaked badly: crafting reagents,
-- essences and reward containers came through as gear because a non
-- equippable item does not reliably report an empty slot — some return
-- INVTYPE_NON_EQUIP_IGNORE, which is not the empty string and is not the one
-- constant that was being checked for. Epic-quality reagents then sailed
-- through the quality test as well.
--
-- Class is unambiguous: weapons and armour are gear, and a reagent is class
-- Tradeskill however good it is. The slot is kept as a second check, because
-- tabards and cosmetic pieces are armour without being anything a raider was
-- waiting on.
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local ARMOR_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4

-- Armour that nobody's raid performance depends on.
--
-- The comment above claimed the slot check already handled these. It did not:
-- a tabard is class Armor with a real equip slot, so it passed every test and
-- a guild tabard reset somebody's drought. Cosmetic pieces reach epic quality
-- too, so the quality floor does not catch them either.
local COSMETIC_SLOTS = {
    INVTYPE_TABARD = true,
    INVTYPE_BODY = true,          -- shirts
}

-- nil rather than false when the item is not cached yet, so a caller can tell
-- "not gear" from "cannot say yet" and try again on the next refresh.
local function IsTrackableGear(record)
    local link = record.itemLink

    if not link then
        return false
    end

    local _, _, quality, _, _, _, _, _, equipSlot, _, _, classID =
        C_Item.GetItemInfo(link)

    if quality == nil or classID == nil then
        return nil
    end

    if quality < MINIMUM_QUALITY then
        return false
    end

    if classID ~= WEAPON_CLASS and classID ~= ARMOR_CLASS then
        return false
    end

    if COSMETIC_SLOTS[equipSlot] then
        return false
    end

    return equipSlot ~= nil
        and equipSlot ~= ""
        and not equipSlot:find("NON_EQUIP", 1, true)
end

-- Index of the drops already recorded, so the overlap can be subtracted
-- without comparing every chat record against every drop.
--
-- Public, because the merged loot list needs the same answer for a different
-- reason: it wants every chat record that is not already a drop, gear or
-- otherwise. Two definitions of "this line is that roll" would drift, and the
-- one that lost would be whichever nobody was looking at.
local function IndexDrops(drops)
    local byItem = {}

    for _, drop in ipairs(drops or {}) do
        local itemID = drop.itemID
        local who = NameKey(drop.winnerName)

        if itemID and who then
            local key = itemID .. "|" .. who

            byItem[key] = byItem[key] or {}

            table.insert(byItem[key], drop.timestamp or 0)
        end
    end

    return byItem
end

local function MatchesADrop(record, dropIndex)
    local itemID = record.itemID
    local who = NameKey(record.recipient)

    if not itemID or not who then
        return false
    end

    local timestamps = dropIndex[itemID .. "|" .. who]

    if not timestamps then
        return false
    end

    local at = record.timestamp or 0

    for _, dropAt in ipairs(timestamps) do
        if math.abs(at - dropAt) <= MATCH_WINDOW_SECONDS then
            return true
        end
    end

    return false
end

-- How the item arrived, inferred from where and how it was captured.
--
-- This lived in LootFeed, which is where it is displayed, and the consequence
-- was that the math never asked. Crafting prints through the loot channel, so
-- a guild's enchanter making other people's gear read as the enchanter
-- receiving a piece every time — and since only the *last* acquisition
-- matters, they could never appear in the due list at all. The one person in
-- a guild most likely to be handing gear away was the one person guaranteed
-- to look showered in it.
--
-- It moved here because the fairness math is the caller that must not skip
-- it. LootFeed loads after this file and reads it from here for the type
-- column, so the list and the math cannot disagree about what a record is.
--
-- Honest guesswork, and the categories are deliberately coarse: better a right
-- answer at "personal" than a confident wrong one at "vault".
function PersonalLoot.LootTypeOf(record)
    -- Decided at capture time against the client's own "you create" string,
    -- so it is right in every locale. Records written before that flag
    -- existed fall back to reading the raw line, which only ever worked in
    -- English and is kept only so old history is not reclassified.
    if record.created then
        return "crafted"
    end

    local raw = record.rawMessage or ""

    if raw:find("create", 1, true) or raw:find("Create", 1, true) then
        return "crafted"
    end

    -- Set at capture time, when the weekly rewards frame was open. Records
    -- written before that existed have no flag and fall through to the
    -- location test below, so old vault items read as world rather than
    -- being wrongly claimed.
    if record.fromVault then
        return "vault"
    end

    local contentType = Utilities.GetContentType(
        record.instanceType, record.difficultyID
    )

    -- Scenario covers delves, which award gear on a track and are the reason
    -- this branch exists at all. "world" is for loot that arrived outside an
    -- instance; a delve is not that.
    if contentType == "raid"
        or contentType == "dungeon"
        or contentType == "scenario"
    then
        return "personal"
    end

    return "world"
end

-- Arrival types that are not evidence anybody got geared.
--
-- Crafted is the one that matters and the reason this set exists: a create
-- line says an item was made, never that the person who made it kept it.
-- There is no way to tell the two apart from chat, and the two errors are not
-- symmetric — a crafter wrongly counted as geared drops off the due list for
-- the rest of the tier, while a crafter who made their own piece and is not
-- counted merely keeps a drought they will lose on the next real drop.
local NOT_AN_ACQUISITION = {
    crafted = true,
}

-- Only what the addon could have seen for everybody, not only for its owner.
--
-- CHAT_MSG_LOOT delivers your own loot wherever you are, and everyone else's
-- only while they are in your group. Counting both together does not produce
-- an incomplete ranking, it produces an inverted one: the officer running the
-- addon is the single player whose vault, world drops and solo delves are all
-- visible, so theirs is the only drought that ever resets outside a raid and
-- they sink to the bottom of their own due list.
--
-- Restricting to records captured while grouped makes the coverage symmetric.
-- Inside a group every member's loot lands in chat, so nobody is observed more
-- closely than anybody else. Solo acquisitions are dropped for everyone
-- including the addon's owner, which is the whole point — an unseen upgrade
-- and an upgrade nobody's client could have seen are the same thing to a
-- fairness number.
--
-- Records written before the flag existed have no answer and are left out
-- rather than assumed grouped; assuming would reinstate exactly the bias.
local function ObservableForEveryone(record)
    return record.inGroup == true
end

-- Returns the acquisitions, how many records could not be judged because the
-- client has not cached the item yet, and how many were gear but arrived
-- outside a group and so could not be counted for anyone. The caller shows
-- both of the latter rather than pretending the first is complete.
PersonalLoot.IsTrackableGear = IsTrackableGear
PersonalLoot.IndexDrops = IndexDrops
PersonalLoot.MatchesADrop = MatchesADrop

function PersonalLoot.Build(lootRecords, drops)
    local dropIndex = IndexDrops(drops)

    local entries = {}
    local pending = 0
    local unobserved = 0

    for _, record in ipairs(lootRecords or {}) do
        local lootType = PersonalLoot.LootTypeOf(record)

        if not record.excludedFromAnalytics
            and not NOT_AN_ACQUISITION[lootType]
        then
            local gear = IsTrackableGear(record)

            if gear == nil then
                pending = pending + 1
            elseif gear and not ObservableForEveryone(record) then
                unobserved = unobserved + 1
            elseif gear and not MatchesADrop(record, dropIndex) then
                table.insert(entries, {
                    record = record,
                    key = SYL.Players.ResolveToMain(
                        SYL.Players.GUIDForName(record.recipient)
                        or record.recipient
                    ),
                    nameKey = NameKey(record.recipient),
                    timestamp = record.timestamp or 0,

                    lootType = lootType,

                    contentType = Utilities.GetContentType(
                        record.instanceType, record.difficultyID
                    ),
                })
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.timestamp > right.timestamp
    end)

    return entries, pending, unobserved
end

-- When each player last received gear this way. Keyed both by the resolved
-- player key and by the bare name, because chat records carry no GUID and the
-- registry may not know the name yet.
function PersonalLoot.LastByPlayer(entries)
    local last = {}

    local function remember(key, at)
        if not key then
            return
        end

        if not last[key] or at > last[key] then
            last[key] = at
        end
    end

    for _, entry in ipairs(entries or {}) do
        remember(entry.key, entry.timestamp)
        remember(entry.nameKey, entry.timestamp)
    end

    return last
end

function PersonalLoot.CountByPlayer(entries)
    local counts = {}

    for _, entry in ipairs(entries or {}) do
        local key = entry.key or entry.nameKey

        if key then
            counts[key] = (counts[key] or 0) + 1
        end
    end

    return counts
end
