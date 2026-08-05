-- Core/CommandReports.lua
--
-- Everything the slash commands print to chat. Kept apart from
-- Core/SlashCommands.lua so that file stays a thin parse-and-dispatch layer
-- and these can be reused from elsewhere.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Reports = {}
SYL.CommandReports = Reports

Reports.RECENT_LIMIT = 10

local PLAYER_RESULT_LIMIT = 10

function Reports.RecentLoot(limit)
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

function Reports.PlayerLoot(searchName)
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

local function DescribeOutcome(record)
    if record.allPassed then
        return "all passed"
    end

    return tostring(record.winnerName)
        .. (record.winnerRoll and (" (" .. record.winnerRoll .. ")") or "")
end

function Reports.Drops(limit)
    local counts = SYL.LootHistoryStore.GetCounts()

    SYL:Print(
        counts.active
        .. " drops this season ("
        .. counts.rolls
        .. " rolls recorded, "
        .. counts.allTime
        .. " all-time)"
    )

    local drops = SYL.GetActiveDrops()

    if #drops == 0 then
        print(
            "No drops recorded yet. They are captured on group-loot rolls "
            .. "during an encounter."
        )

        return
    end

    local startIndex = math.max(1, #drops - limit + 1)

    for index = startIndex, #drops do
        local record = drops[index]

        print(
            index
            .. ". "
            .. tostring(record.encounterName or "Unknown boss")
            .. " — "
            .. tostring(record.itemLink or record.itemName or "Unknown item")
            .. " — "
            .. DescribeOutcome(record)
            .. " — "
            .. tostring(record.eligibleCount or 0)
            .. " eligible"
        )
    end
end

function Reports.SeasonStatus()
    local season = SYL.GetActiveSeason()

    if not season then
        SYL:Print("No active season exists.")
        return
    end

    SYL:Print("Active season: " .. season.name)

    print("Season ID: " .. tostring(season.id))
    print("Drops: " .. #(season.drops or {}))
    print("Chat loot records: " .. #(season.loot or {}))
    print("Started: " .. date("%m/%d/%Y %I:%M %p", season.startedAt))
    print("Archived seasons: " .. #SYL.GetArchives())

    if SYL.Guild.IsInGuild() then
        print(
            "Guild: "
            .. tostring(SYL.Guild.GetGuildName())
            .. " — "
            .. SYL.Guild.GetMemberCount()
            .. " members cached"
        )
    else
        print("Guild: not in a guild, so ranks will not be recorded.")
    end
end

function Reports.Archives()
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
            .. #(season.drops or {})
            .. " drops, "
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
function Reports.APIReport()
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
            local pieces = {}

            for _, key in ipairs(Utilities.GetSortedKeys(values)) do
                table.insert(pieces, key .. "=" .. tostring(values[key]))
            end

            print("Enum." .. enumName .. ": " .. table.concat(pieces, ", "))
        else
            print("Enum." .. enumName .. ": not present")
        end
    end

    print(
        "Events monitored: "
        .. #report.events.registered
        .. " (capture "
        .. (SYL.LootHistory.IsEnabled() and "on" or "off")
        .. ")"
    )

    for _, event in ipairs(
        Utilities.GetSortedKeys(report.events.unavailable)
    ) do
        print("  unavailable: " .. tostring(event))
    end
end

-- Built from Core/CommandList.lua so this and the minimap menu always agree.
function Reports.Help()
    SYL:Print("Commands:")

    for _, entry in ipairs(SYL.CommandList.ENTRIES) do
        print(
            SYL.CommandList.Format(entry)
            .. " — "
            .. entry.description
        )
    end
end
