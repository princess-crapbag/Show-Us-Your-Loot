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
-- fairness maths worse than leaving it alone.
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

-- Rare and above. Below that is reagents and vendor trash, which is not what
-- "did they get geared" is asking about, whatever the quality filter is set
-- to for the loot list.
local MINIMUM_QUALITY = 3

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

-- nil rather than false when the item is not cached yet, so a caller can tell
-- "not gear" from "cannot say yet" and try again on the next refresh.
local function IsTrackableGear(record)
    local link = record.itemLink

    if not link then
        return false
    end

    local _, _, quality, _, _, _, _, _, equipSlot = C_Item.GetItemInfo(link)

    if quality == nil then
        return nil
    end

    if quality < MINIMUM_QUALITY then
        return false
    end

    -- Everything wearable reports a slot. Reagents, consumables and mounts
    -- report an empty one.
    return equipSlot ~= nil and equipSlot ~= "" and equipSlot ~= "INVTYPE_NON_EQUIP"
end

-- Index of the drops already recorded, so the overlap can be subtracted
-- without comparing every chat record against every drop.
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

-- Returns the acquisitions, and how many records could not be judged because
-- the client has not cached the item yet. The caller shows the second number
-- rather than pretending the first is complete.
function PersonalLoot.Build(lootRecords, drops)
    local dropIndex = IndexDrops(drops)

    local entries = {}
    local pending = 0

    for _, record in ipairs(lootRecords or {}) do
        if not record.excludedFromAnalytics then
            local gear = IsTrackableGear(record)

            if gear == nil then
                pending = pending + 1
            elseif gear and not MatchesADrop(record, dropIndex) then
                table.insert(entries, {
                    record = record,
                    key = SYL.Players.ResolveToMain(
                        SYL.Players.GUIDForName(record.recipient)
                        or record.recipient
                    ),
                    nameKey = NameKey(record.recipient),
                    timestamp = record.timestamp or 0,

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

    return entries, pending
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
