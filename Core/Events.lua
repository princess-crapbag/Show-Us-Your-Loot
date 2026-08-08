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

    -- Before any window is built, so frames are created in the saved colours
    -- rather than being built in one palette and repainted into another.
    SYL.Theme.Apply(ShowUsYourLootDB.settings.palette, true)

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
            "Loot History capture is off — no roll data will be recorded. "
            .. "Attendance still is. Turn capture on with /syl capture."
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

    SYL.ItemTooltip.Enable()
    SYL.Sync.Enable()

    -- The reply arrives as GUILD_ROSTER_UPDATE.
    SYL.Guild.Request()
end

local function OnChatMessageLoot(message)
    SYL:DebugPrint("Raw loot: " .. tostring(message))

    SYL.LootCapture.HandleChatMessage(message)
end

-- Names the recipient outright, so it settles any loot line the chat patterns
-- could not read. Registered here rather than with the loot-history events
-- because it is used for attribution, which must keep working when capture is
-- off.
local function OnEncounterLootReceived(
    encounterID, itemID, itemLink, quantity, playerName
)
    SYL.LootCapture.NoteEncounterLoot(
        encounterID, itemID, itemLink, quantity, playerName
    )
end

local function OnGuildRosterUpdate()
    local count = SYL.Guild.Refresh()

    SYL:DebugPrint("Guild roster cached: " .. tostring(count) .. " members.")
end

-- Attendance is not a loot feature and must not be switched off by one.
--
-- These forwarders used to live inside LootHistory's handler table, which is
-- only registered by LootHistory.Enable(). Turning loot capture off with
-- /syl capture therefore stopped raid nights being recorded at all — no
-- sessions, no roster, no attendance, and no message saying so. The due list
-- simply started returning nothing and looked broken rather than disabled.
--
-- Registered here, unconditionally, with everything else the addon always
-- watches. LootHistory still registers the same two events for its own
-- purposes; two frames watching one event is how the API is meant to be used
-- and each gets its own callback.
local function OnEncounterStart(encounterID, encounterName, difficultyID)
    SYL.RaidSession.OnEncounterStart(
        encounterID, encounterName, difficultyID
    )
end

-- The roster has to be read while everyone is still grouped, which is why
-- this is synchronous rather than folded into a refresh.
local function OnEncounterEnd(
    encounterID, encounterName, difficultyID, groupSize, success
)
    SYL.RaidSession.OnEncounterEnd(
        encounterID, encounterName, difficultyID, groupSize, success
    )
end

-- Fires on zoning, including stepping out of the instance at the end of the
-- night. There is no "raid over" event, so leaving is the closest honest
-- signal; RaidSession only reports a night that actually had pulls, and only
-- once.
local function OnPlayerEnteringWorld()
    local inInstance, instanceType = IsInInstance()

    if inInstance and (instanceType == "raid" or instanceType == "party") then
        return
    end

    SYL.RaidSummary.ReportIfFinished()
end

local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    PLAYER_LOGIN = OnPlayerLogin,
    PLAYER_ENTERING_WORLD = OnPlayerEnteringWorld,
    CHAT_MSG_LOOT = OnChatMessageLoot,
    GUILD_ROSTER_UPDATE = OnGuildRosterUpdate,
    ENCOUNTER_START = OnEncounterStart,
    ENCOUNTER_END = OnEncounterEnd,
    ENCOUNTER_LOOT_RECEIVED = OnEncounterLootReceived,
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
