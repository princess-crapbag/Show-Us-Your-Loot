-- Core/ItemQuality.lua
--
-- Which item qualities are worth recording.
--
-- This gates capture, not display: an untracked quality is never written to
-- the database at all. That is the point — it keeps gray vendor trash and
-- green drops out of a season's records entirely — but it also means the
-- setting is not retroactive in either direction. Records already saved stay
-- saved, and items skipped while a quality was off are gone for good.

local SYL = _G.ShowUsYourLoot

local ItemQuality = {}
SYL.ItemQuality = ItemQuality

local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo

-- Enum.ItemQuality values. Listed rather than read from the enum because the
-- settings UI needs a stable display order, not just the names.
ItemQuality.ORDER = { 0, 1, 2, 3, 4, 5, 6, 7 }

ItemQuality.NAMES = {
    [0] = "Poor (gray)",
    [1] = "Common (white)",
    [2] = "Uncommon (green)",
    [3] = "Rare (blue)",
    [4] = "Epic (purple)",
    [5] = "Legendary (orange)",
    [6] = "Artifact",
    [7] = "Heirloom",
}

-- Everything is tracked until it is turned off. Starting permissive means a
-- fresh install never quietly misses loot, which matters more than a tidy
-- database on day one.
function ItemQuality.GetDefaults()
    local defaults = {}

    for _, quality in ipairs(ItemQuality.ORDER) do
        defaults[quality] = true
    end

    return defaults
end

local function GetSettings()
    if not ShowUsYourLootDB or not ShowUsYourLootDB.settings then
        return nil
    end

    ShowUsYourLootDB.settings.trackedQualities =
        ShowUsYourLootDB.settings.trackedQualities
        or ItemQuality.GetDefaults()

    return ShowUsYourLootDB.settings.trackedQualities
end

function ItemQuality.IsTracked(quality)
    -- An unknown quality is always recorded. The client cache not having the
    -- item yet must never cost us the record.
    if quality == nil then
        return true
    end

    local tracked = GetSettings()

    if not tracked then
        return true
    end

    return tracked[quality] ~= false
end

function ItemQuality.SetTracked(quality, enabled)
    local tracked = GetSettings()

    if not tracked then
        return
    end

    tracked[quality] = enabled and true or false
end

function ItemQuality.CountTracked()
    local tracked = GetSettings()
    local count = 0

    if not tracked then
        return 0
    end

    for _, quality in ipairs(ItemQuality.ORDER) do
        if tracked[quality] ~= false then
            count = count + 1
        end
    end

    return count
end

-- Returns nil when the item is not cached, which callers treat as "track it".
function ItemQuality.FromLink(itemLink)
    if not itemLink then
        return nil
    end

    local success, quality = pcall(function()
        return select(3, GetItemInfo(itemLink))
    end)

    if not success then
        return nil
    end

    return quality
end

function ItemQuality.ShouldTrackLink(itemLink)
    return ItemQuality.IsTracked(ItemQuality.FromLink(itemLink))
end
