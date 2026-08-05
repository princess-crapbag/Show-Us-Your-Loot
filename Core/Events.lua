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
    SYL.LootHistoryStore.RebuildIndex()

    local activeSeason = SYL.GetActiveSeason()

    SYL:Print(
        "Database ready. Active season: "
        .. activeSeason.name
        .. " — "
        .. #activeSeason.drops
        .. " drops, "
        .. #activeSeason.loot
        .. " item records."
    )

    -- Loot History is the primary source, so capture runs unless it has been
    -- turned off deliberately. /syl dev only opens the inspector window.
    if ShowUsYourLootDB.settings.lootHistoryCapture then
        local registeredCount = SYL.LootHistory.Enable()

        SYL:DebugPrint(
            "Loot History capture watching "
            .. tostring(registeredCount)
            .. " events."
        )
    else
        SYL:Print(
            "Loot History capture is off. Turn it on with /syl capture."
        )
    end
end

local function OnPlayerLogin()
    SYL:DebugPrint("Player login complete.")

    -- Created here rather than at ADDON_LOADED so the minimap is certain to
    -- exist and to have been positioned.
    SYL.MinimapButton.SetShown(
        ShowUsYourLootDB.settings.showMinimapButton
    )

    -- The reply arrives as GUILD_ROSTER_UPDATE.
    SYL.Guild.Request()
end

local function OnChatMessageLoot(message)
    SYL:DebugPrint("Raw loot: " .. tostring(message))

    SYL.LootCapture.HandleChatMessage(message)
end

local function OnGuildRosterUpdate()
    local count = SYL.Guild.Refresh()

    SYL:DebugPrint("Guild roster cached: " .. tostring(count) .. " members.")
end

local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_LOGIN = OnPlayerLogin,
    CHAT_MSG_LOOT = OnChatMessageLoot,
    GUILD_ROSTER_UPDATE = OnGuildRosterUpdate,
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
