-- Core/Events.lua
--
-- Registration and dispatch only. Every handler here should be a thin
-- forwarder into the module that owns the behavior, so that adding a new
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

    -- Before any window is built, so frames are created in the saved colors
    -- rather than being built in one palette and repainted into another.
    SYL.Theme.Apply(ShowUsYourLootDB.settings.palette, true)

    local activeSeason = SYL.GetActiveSeason()
    local recorded = #activeSeason.drops + #activeSeason.loot

    -- A first run said "Database ready. Active season: … — 0 drops, 0 item
    -- records", which is a status line written for whoever built it. It never
    -- mentioned the slash command, so the only way in was the minimap button,
    -- and it never said that zero is the expected number on day one.
    if recorded == 0 then
        SYL:Print(
            "Ready. Nothing is recorded yet — it starts from now, and cannot "
            .. "see loot from before today. Type /syl to open it, or "
            .. "/syl rename <name> to name the season."
        )
    else
        SYL:Print(
            "Ready. "
            .. activeSeason.name
            .. " — "
            .. #activeSeason.drops
            .. " drops, "
            .. #activeSeason.loot
            .. " item records. /syl to open."
        )
    end

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

    -- Not registered at all when off, rather than registered and refusing to
    -- send. A feature that is off should cost nothing, including an addon
    -- message prefix and an event handler.
    if SYL.Features.IsEnabled("sync") then
        SYL.Sync.Enable()
    end

    -- Separate switch from sync: that one sends drop headers to officers in
    -- your group, this sends one line about this character to the guild.
    if SYL.Features.IsEnabled("keystoneSharing") then
        SYL.KeystoneSync.Enable()
    end

    -- A third switch again, and separate for the same reason: sharing tells
    -- the guild what you hold, this sends a message to one named person and
    -- expects one back. Wanting either without the other is reasonable.
    if SYL.Features.IsEnabled("keyRequests") then
        SYL.KeystoneRequestSync.Enable()
    end

    -- The reply arrives as GUILD_ROSTER_UPDATE.
    SYL.Guild.Request()

    -- What this character is holding, read once at login. See
    -- Core/Keystone.lua for why this can only ever be our own key.
    SYL.Keystone.Update()

    -- And which dungeons it is saved to. This one is a round trip: the answer
    -- comes back as UPDATE_INSTANCE_INFO, so asking is all that happens here.
    if SYL.Features.IsEnabled("lockouts") then
        SYL.Lockouts.Request()
    end

    -- Unconditional, like the record-id backfill: an absence written before
    -- ids existed cannot be reconciled with anybody else's copy, and would be
    -- re-sent as new forever. Before the broadcast, so nothing goes out
    -- without an id on it.
    SYL.RaidSchedule.BackfillAbsenceIDs()

    -- A fourth switch, and separate for the same reason as the other three:
    -- this one sends what you have typed about other people to the guild.
    if SYL.Features.IsEnabled("absenceSharing") then
        SYL.AbsenceSync.Enable()

        -- Ask once, then say our own. Everyone who hears the question answers,
        -- so a fresh login is never more than one round trip out of date.
        SYL.AbsenceSync.Request()
        SYL.AbsenceSync.Announce()
    end
end

-- The three ways a key changes: a run finishes and awards the next one, the
-- weekly reset takes it away, and rerolling at the font swaps it — which the
-- client reports as the keystone item moving in the bags rather than as
-- anything Mythic+ specific.
--
-- Update returns whether the answer actually differs, and BAG_UPDATE_DELAYED
-- fires constantly, so the debug line is behind that check rather than
-- printing on every bag change.
local function OnKeystoneMayHaveChanged()
    local entry, changed = SYL.Keystone.Update()

    if changed and entry then
        SYL:DebugPrint("Keystone now: " .. SYL.Keystone.Describe(entry))

        -- Only on a real change. This runs on bag updates, which fire
        -- constantly, and a broadcast per bag update would be a broadcast per
        -- looted gray.
        SYL.KeystoneSync.OnOwnKeyChanged()
    end
end

-- The server's answer to RequestRaidInfo, and the only moment the lockout list
-- is actually readable. It also arrives unprompted whenever a lockout changes,
-- which is how finishing a Mythic 0 lands in the grid without asking again.
--
-- Gated in the handler rather than at registration, for the same reason the
-- trade events are: gating the registration would mean the event is only live
-- for somebody who reloaded after switching the feature on, and a lockout
-- missed for that reason looks like the addon being wrong about the dungeon.
local function OnInstanceInfoUpdated()
    if not SYL.Features.IsEnabled("lockouts") then
        return
    end

    local entry, changed = SYL.Lockouts.Update()

    if changed and entry then
        SYL:DebugPrint("Lockouts now: " .. SYL.Lockouts.Describe(entry))
    end
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

-- GUILD_ROSTER_UPDATE fires on every roster tick and on every member logging
-- in or out, which in a busy guild is constantly. Printing the count each time
-- buried every other debug line under the same sentence repeating, so debug
-- mode was unusable for the one thing it exists for.
--
-- Only a change is worth a line. The refresh itself still runs every time,
-- because that is the point of the event.
local lastGuildCount

local function OnGuildRosterUpdate()
    -- The guild name is only knowable once the roster has arrived, and the
    -- default Warcraft Logs and Raider.IO links point at that guild's page.
    -- Seeded at login they would have to be front pages, so they are upgraded
    -- here — and only if nobody has edited them.
    if SYL.Links and SYL.Links.RefreshDefaults then
        SYL.Links.RefreshDefaults()
    end

    local count = SYL.Guild.Refresh()

    -- A recruit who has now joined stops being a placeholder and becomes a
    -- guild member, carrying their team flag and role with them.
    local promoted = SYL.IncomingRoster.PromoteJoined()

    -- The roster window builds from this, and caches what it built.
    SYL.RosterData.Invalidate()

    if promoted > 0 then
        SYL:Print(
            promoted
            .. (promoted == 1 and " recruit has" or " recruits have")
            .. " joined the guild and moved onto the roster."
        )
    end

    if count ~= lastGuildCount then
        lastGuildCount = count

        SYL:DebugPrint(
            "Guild roster cached: " .. tostring(count) .. " members."
        )
    end
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

-- Registered unconditionally, unlike the feature's own work. A feature that is
-- off should cost nothing, and these four cost nothing: every handler returns
-- on the first line when tradeTracking is off. Gating the registration instead
-- would mean the events are only ever live for somebody who reloaded after
-- turning it on, and a trade missed for that reason is invisible.
local HANDLERS = {
    ADDON_LOADED = OnAddonLoaded,
    TRADE_SHOW = function() SYL.TradeTracker.OnTradeShow() end,
    TRADE_CLOSED = function() SYL.TradeTracker.OnTradeClosed() end,
    TRADE_ACCEPT_UPDATE = function(playerAccepted, targetAccepted)
        SYL.TradeTracker.OnAcceptUpdate(playerAccepted, targetAccepted)
    end,
    UI_INFO_MESSAGE = function(messageType)
        SYL.TradeTracker.OnInfoMessage(messageType)
    end,
    CHALLENGE_MODE_COMPLETED = OnKeystoneMayHaveChanged,
    UPDATE_INSTANCE_INFO = OnInstanceInfoUpdated,
    BAG_UPDATE_DELAYED = OnKeystoneMayHaveChanged,
    ITEM_CHANGED = OnKeystoneMayHaveChanged,
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
