-- Core/ItemCacheWatch.lua
--
-- "Redraw me when the client finally knows what this item is."
--
-- An item the client has never seen has no icon, no name and no quality until
-- the server answers for it, and the answer arrives whenever it arrives. A
-- screen drawn before then shows a blank square, and nothing brings it back:
-- the draw already happened.
--
-- GET_ITEM_INFO_RECEIVED fires when the cache fills. This owns the one frame
-- that listens for it, registered only while a screen is actually waiting and
-- dropped again the moment none is -- so an idle window listens to nothing.
--
-- KEYED, BECAUSE TWO SCREENS WAIT SEPARATELY. UI/LootListView.lua had this to
-- itself and could unregister the event outright when its own rows were all
-- cached. The Bosses tab waits on the same event, and one screen calling
-- UnregisterAllEvents on a shared frame would take the other's listener with
-- it. Set(key, waiting) per screen; the event follows whether ANY of them is
-- still waiting.
--
-- The burst matters. A boss's loot table resolves as thirty separate events
-- in the same frame, and each one would otherwise redraw the whole window.

local SYL = _G.ShowUsYourLoot

local ItemCacheWatch = {}
SYL.ItemCacheWatch = ItemCacheWatch

local BURST_SECONDS = 0.1

local watcher
local refreshPending = false
local waiting = {}

local function AnyoneWaiting()
    for _, isWaiting in pairs(waiting) do
        if isWaiting then
            return true
        end
    end

    return false
end

local function Watcher()
    if watcher then
        return watcher
    end

    watcher = CreateFrame("Frame")

    watcher:SetScript("OnEvent", function()
        if refreshPending then
            return
        end

        refreshPending = true

        C_Timer.After(BURST_SECONDS, function()
            refreshPending = false

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end
        end)
    end)

    return watcher
end

-- Called by a screen at the end of its draw: true if anything it just drew is
-- still missing its item data, false if everything resolved.
function ItemCacheWatch.Set(key, isWaiting)
    waiting[key] = isWaiting or nil

    local frame = Watcher()

    if AnyoneWaiting() then
        frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

-- For tests and for a screen going away entirely.
function ItemCacheWatch.IsWatching()
    return AnyoneWaiting()
end
