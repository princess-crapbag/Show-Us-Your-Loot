-- Core/Events.lua
--
-- Registration and dispatch only. Every handler here should be a thin
-- forwarder into the module that owns the behaviour, so that adding a new
-- data source never means growing this file.

local SYL = _G.ShowUsYourLoot

local ADDON_NAME = "ShowUsYourLoot"

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(loadedAddonName)
    if loadedAddonName ~= ADDON_NAME then
        return
    end

    SYL.DatabaseInitialize()

    local activeSeason = SYL.GetActiveSeason()

    SYL:Print(
        "Database ready. Active season: "
        .. activeSeason.name
        .. " — "
        .. #activeSeason.loot
        .. " item records."
    )

    -- The Loot History inspector is a developer tool, so it stays off until
    -- it is switched on explicitly with /syl dev.
    if ShowUsYourLootDB.settings.lootHistoryInspector then
        local registeredCount = SYL.LootHistory.Enable()

        SYL:DebugPrint(
            "Loot History inspector enabled for "
            .. tostring(registeredCount)
            .. " events."
        )
    end
end

local function OnPlayerLogin()
    SYL:DebugPrint("Player login complete.")
end

local function OnChatMessageLoot(message)
    SYL:DebugPrint("Raw loot: " .. tostring(message))

    SYL.LootCapture.HandleChatMessage(message)
end

local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_LOGIN = OnPlayerLogin,
    CHAT_MSG_LOOT = OnChatMessageLoot,
}

for event in pairs(HANDLERS) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = HANDLERS[event]

    if handler then
        handler(...)
    end
end)
