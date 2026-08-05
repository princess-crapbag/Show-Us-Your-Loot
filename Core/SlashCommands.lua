-- Core/SlashCommands.lua
--
-- Every /syl command. Each handler stays short and delegates the real work to
-- the module that owns it.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local RECENT_LIMIT = 10
local PLAYER_RESULT_LIMIT = 10

local function PrintRecentLoot(limit)
    local records = SYL.GetActiveLoot()
    local count = #records

    SYL:Print("Active-season item records: " .. count)

    if count == 0 then
        print("No item loot has been recorded in this season.")
        return
    end

    local startIndex = math.max(1, count - limit + 1)

    for index = startIndex, count do
        local record = records[index]

        print(
            index
            .. ". "
            .. tostring(record.recipient)
            .. " — "
            .. tostring(record.itemLink)
            .. " — "
            .. date("%m/%d %I:%M %p", record.timestamp)
        )
    end
end

local function PrintPlayerLoot(searchName)
    searchName = Utilities.Trim(searchName)

    if not searchName or searchName == "" then
        SYL:Print("Enter a player name. Example: /syl player Aimee")
        return
    end

    local normalizedSearch = string.lower(searchName)
    local matches = {}

    for _, record in ipairs(SYL.GetActiveLoot()) do
        local recipient = string.lower(record.recipient or "")

        if recipient:find(normalizedSearch, 1, true) then
            table.insert(matches, record)
        end
    end

    SYL:Print(
        #matches
        .. " active-season records found for "
        .. searchName
    )

    local startIndex = math.max(1, #matches - PLAYER_RESULT_LIMIT + 1)

    for index = startIndex, #matches do
        local record = matches[index]

        print(
            record.recipient
            .. " — "
            .. record.itemLink
            .. " — "
            .. date("%m/%d %I:%M %p", record.timestamp)
        )
    end
end

local function PrintSeasonStatus()
    local season = SYL.GetActiveSeason()

    if not season then
        SYL:Print("No active season exists.")
        return
    end

    SYL:Print("Active season: " .. season.name)

    print("Season ID: " .. tostring(season.id))
    print("Loot records: " .. #(season.loot or {}))
    print("Started: " .. date("%m/%d/%Y %I:%M %p", season.startedAt))
    print("Archived seasons: " .. #SYL.GetArchives())
end

local function PrintArchives()
    local archives = SYL.GetArchives()

    SYL:Print("Archived seasons: " .. #archives)

    if #archives == 0 then
        print("No seasons have been archived.")
        return
    end

    for index, season in ipairs(archives) do
        print(
            index
            .. ". "
            .. season.name
            .. " — "
            .. #(season.loot or {})
            .. " items — archived "
            .. Utilities.FormatDateOnly(
                season.archivedAt or season.startedAt
            )
        )
    end
end

-- Dumps what the live client actually exposes, so the API surface can be
-- confirmed without opening the developer window.
local function PrintAPIReport()
    local report = SYL.LootHistory.GetAPIReport()

    SYL:Print(
        "Client "
        .. tostring(report.clientVersion)
        .. " build "
        .. tostring(report.clientBuild)
        .. " (interface "
        .. tostring(report.interfaceVersion)
        .. ")"
    )

    if not report.namespacePresent then
        print("C_LootHistory is NOT present in this client.")
        return
    end

    if type(report.functions) ~= "table" then
        print(tostring(report.functions))
        return
    end

    local names = Utilities.GetSortedKeys(report.functions)

    print("C_LootHistory exposes " .. #names .. " members:")

    for _, name in ipairs(names) do
        print("  " .. name .. " (" .. report.functions[name] .. ")")
    end

    for _, enumName in ipairs(Utilities.GetSortedKeys(report.enums)) do
        local values = report.enums[enumName]

        if type(values) == "table" then
            local keys = Utilities.GetSortedKeys(values)
            local pieces = {}

            for _, key in ipairs(keys) do
                table.insert(pieces, key .. "=" .. tostring(values[key]))
            end

            print(
                "Enum." .. enumName .. ": "
                .. table.concat(pieces, ", ")
            )
        else
            print("Enum." .. enumName .. ": not present")
        end
    end

    print(
        "Events monitored: "
        .. #report.events.registered
        .. " (inspector "
        .. (SYL.LootHistory.IsEnabled() and "on" or "off")
        .. ")"
    )

    for _, event in ipairs(
        Utilities.GetSortedKeys(report.events.unavailable)
    ) do
        print("  unavailable: " .. tostring(event))
    end
end

local function PrintHelp()
    SYL:Print("Commands:")

    print("/syl — Open the loot window")
    print("/syl recent — Show recent active-season loot")
    print("/syl count — Show active and all-time totals")
    print("/syl player NAME — Show active-season loot for a player")
    print("/syl season — Show active-season information")
    print("/syl rename NAME — Rename the active season")
    print("/syl archive NEW SEASON NAME — Archive the current season and start a new one")
    print("/syl archives — List archived seasons")
    print("/syl dev — Open the Loot History developer window")
    print("/syl dev off — Stop monitoring Loot History events")
    print("/syl api — Print the live Loot History API surface")
    print("/syl debug — Toggle debug messages")
    print("/syl announce — Toggle capture messages")
    print("/syl clear — Clear active-season loot")
end

local COMMANDS = {}

COMMANDS.help = PrintHelp

COMMANDS.recent = function()
    PrintRecentLoot(RECENT_LIMIT)
end

COMMANDS.count = function()
    SYL:Print("Active season: " .. #SYL.GetActiveLoot() .. " items")
    print("All-time: " .. #SYL.GetAllLoot() .. " items")
end

COMMANDS.player = PrintPlayerLoot
COMMANDS.season = PrintSeasonStatus
COMMANDS.archives = PrintArchives
COMMANDS.api = PrintAPIReport

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
        .. #archivedSeason.loot
        .. " loot records."
    )

    print("New active season: " .. newSeason.name)

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

COMMANDS.dev = function(remainder)
    local argument =
        string.lower(Utilities.Trim(remainder) or "")

    if argument == "off" then
        SYL.LootHistory.Disable()
        ShowUsYourLootDB.settings.lootHistoryInspector = false

        SYL:Print("Loot History inspector disabled.")

        return
    end

    if not SYL.LootHistory.IsEnabled() then
        local registeredCount = SYL.LootHistory.Enable()

        ShowUsYourLootDB.settings.lootHistoryInspector = true

        SYL:Print(
            "Loot History inspector enabled — monitoring "
            .. tostring(registeredCount)
            .. " events."
        )
    end

    if SYL.OpenDeveloperWindow then
        SYL:OpenDeveloperWindow()
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

    activeSeason.loot = {}

    ShowUsYourLootDB.loot = activeSeason.loot
    ShowUsYourLootDB.recentRecordIDs = {}

    SYL:Print("Active-season loot history cleared.")

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
            PrintRecentLoot(RECENT_LIMIT)
        end

        return
    end

    local handler = COMMANDS[command]

    if handler then
        handler(remainder)
        return
    end

    PrintHelp()
end
