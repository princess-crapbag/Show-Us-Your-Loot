-- Core/SlashCommands.lua
--
-- Parses /syl input and dispatches it. Each handler stays short and delegates
-- the real work: chat output to Core/CommandReports.lua, everything else to
-- the module that owns it.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local Reports = SYL.CommandReports

local RECENT_LIMIT = Reports.RECENT_LIMIT

local COMMANDS = {}

COMMANDS.help = Reports.Help
COMMANDS.season = Reports.SeasonStatus
COMMANDS.archives = Reports.Archives
COMMANDS.api = Reports.APIReport
COMMANDS.player = Reports.PlayerLoot

COMMANDS.recent = function()
    Reports.RecentLoot(RECENT_LIMIT)
end

COMMANDS.drops = function()
    Reports.Drops(RECENT_LIMIT)
end

COMMANDS.count = function()
    local counts = SYL.LootHistoryStore.GetCounts()

    SYL:Print(
        "Active season: "
        .. counts.active
        .. " drops, "
        .. #SYL.GetActiveLoot()
        .. " chat items"
    )

    SYL:Write(
        "All-time: "
        .. counts.allTime
        .. " drops, "
        .. #SYL.GetAllLoot()
        .. " chat items"
    )
end

COMMANDS.rename = function(remainder)
    local success, errorMessage = SYL.RenameActiveSeason(remainder)

    if success then
        SYL:Print(
            "Active season renamed to: "
            .. SYL.GetActiveSeason().name
        )
    else
        SYL:Print(errorMessage)
    end
end

COMMANDS.archive = function(remainder)
    local newSeasonName = Utilities.Trim(remainder)

    if not newSeasonName or newSeasonName == "" then
        newSeasonName = "New Season"
    end

    local archivedSeason, newSeason =
        SYL.ArchiveCurrentSeason(newSeasonName)

    if not archivedSeason then
        SYL:Print(newSeason or "Archive failed.")
        return
    end

    SYL:Print(
        "Archived "
        .. archivedSeason.name
        .. " with "
        .. #(archivedSeason.drops or {})
        .. " drops and "
        .. #(archivedSeason.loot or {})
        .. " loot records."
    )

    SYL:Write("New active season: " .. newSeason.name)

    SYL.LootHistoryStore.RebuildIndex()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

COMMANDS.players = function()
    if SYL.OpenPlayerWindow then
        SYL:OpenPlayerWindow()
    end
end

COMMANDS.export = function()
    if SYL.OpenExportWindow then
        SYL:OpenExportWindow()
    end
end

COMMANDS.settings = function()
    if SYL.OpenSettingsWindow then
        SYL:OpenSettingsWindow()
    end
end

COMMANDS.dev = function()
    -- Capture runs on its own; this only opens the inspector window.
    if not SYL.LootHistory.IsEnabled() then
        SYL:Print(
            "Loot History capture is off, so the inspector will stay empty. "
            .. "Turn it on with /syl capture."
        )
    end

    if SYL.OpenDeveloperWindow then
        SYL:OpenDeveloperWindow()
    end
end

COMMANDS.output = function()
    local name = SYL.Output.CycleWindow()

    -- Printed after the switch, so it lands in the window just chosen and
    -- proves where messages will appear.
    SYL:Print("Messages now go to the \"" .. tostring(name) .. "\" window.")
end

COMMANDS.capture = function()
    local settings = ShowUsYourLootDB.settings

    settings.lootHistoryCapture = not settings.lootHistoryCapture

    if settings.lootHistoryCapture then
        local registeredCount = SYL.LootHistory.Enable()

        SYL:Print(
            "Loot History capture enabled — watching "
            .. tostring(registeredCount)
            .. " events."
        )
    else
        SYL.LootHistory.Disable()

        SYL:Print(
            "Loot History capture disabled. Chat capture still records loot."
        )
    end
end

COMMANDS.debug = function()
    local settings = ShowUsYourLootDB.settings

    settings.debug = not settings.debug

    SYL:Print(
        "Debug messages "
        .. (settings.debug and "enabled." or "disabled.")
    )
end

COMMANDS.announce = function()
    local settings = ShowUsYourLootDB.settings

    settings.announceCaptures = not settings.announceCaptures

    SYL:Print(
        "Capture announcements "
        .. (settings.announceCaptures and "enabled." or "disabled.")
    )
end

COMMANDS.clear = function()
    local activeSeason = SYL.GetActiveSeason()

    local clearedDrops = #(activeSeason.drops or {})
    local clearedLoot = #(activeSeason.loot or {})

    activeSeason.loot = {}
    activeSeason.drops = {}

    ShowUsYourLootDB.loot = activeSeason.loot
    ShowUsYourLootDB.recentRecordIDs = {}

    SYL.LootHistoryStore.RebuildIndex()

    SYL:Print(
        "Active season cleared: "
        .. clearedDrops
        .. " drops and "
        .. clearedLoot
        .. " chat items removed. Archived seasons are untouched."
    )

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

SLASH_SHOWUSYOURLOOT1 = "/syl"

SlashCmdList["SHOWUSYOURLOOT"] = function(input)
    input = input or ""

    local command, remainder = input:match("^(%S*)%s*(.-)$")

    command = string.lower(command or "")
    remainder = remainder or ""

    if command == "" then
        if SYL.OpenMainWindow then
            SYL:OpenMainWindow()
        else
            Reports.RecentLoot(RECENT_LIMIT)
        end

        return
    end

    local handler = COMMANDS[command]

    if handler then
        handler(remainder)
        return
    end

    Reports.Help()
end
