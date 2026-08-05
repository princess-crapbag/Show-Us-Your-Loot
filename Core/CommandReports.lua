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
        SYL:Write("No item loot has been recorded in this season.")
        return
    end

    local startIndex = math.max(1, count - limit + 1)

    for index = startIndex, count do
        local record = records[index]

        SYL:Write(
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

        SYL:Write(
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
        SYL:Write(
            "No drops recorded yet. They are captured on group-loot rolls "
            .. "during an encounter."
        )

        return
    end

    local startIndex = math.max(1, #drops - limit + 1)

    for index = startIndex, #drops do
        local record = drops[index]

        SYL:Write(
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

    SYL:Write("Season ID: " .. tostring(season.id))
    SYL:Write("Drops: " .. #(season.drops or {}))
    SYL:Write("Chat loot records: " .. #(season.loot or {}))
    SYL:Write("Started: " .. date("%m/%d/%Y %I:%M %p", season.startedAt))
    SYL:Write("Archived seasons: " .. #SYL.GetArchives())

    if SYL.Guild.IsInGuild() then
        SYL:Write(
            "Guild: "
            .. tostring(SYL.Guild.GetGuildName())
            .. " — "
            .. SYL.Guild.GetMemberCount()
            .. " members cached"
        )
    else
        SYL:Write("Guild: not in a guild, so ranks will not be recorded.")
    end
end

function Reports.Archives()
    local archives = SYL.GetArchives()

    SYL:Print("Archived seasons: " .. #archives)

    if #archives == 0 then
        SYL:Write("No seasons have been archived.")
        return
    end

    for index, season in ipairs(archives) do
        SYL:Write(
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
        SYL:Write("C_LootHistory is NOT present in this client.")
        return
    end

    if type(report.functions) ~= "table" then
        SYL:Write(tostring(report.functions))
        return
    end

    local names = Utilities.GetSortedKeys(report.functions)

    SYL:Write("C_LootHistory exposes " .. #names .. " members:")

    for _, name in ipairs(names) do
        SYL:Write("  " .. name .. " (" .. report.functions[name] .. ")")
    end

    for _, enumName in ipairs(Utilities.GetSortedKeys(report.enums)) do
        local values = report.enums[enumName]

        if type(values) == "table" then
            local pieces = {}

            for _, key in ipairs(Utilities.GetSortedKeys(values)) do
                table.insert(pieces, key .. "=" .. tostring(values[key]))
            end

            SYL:Write("Enum." .. enumName .. ": " .. table.concat(pieces, ", "))
        else
            SYL:Write("Enum." .. enumName .. ": not present")
        end
    end

    SYL:Write(
        "Events monitored: "
        .. #report.events.registered
        .. " (capture "
        .. (SYL.LootHistory.IsEnabled() and "on" or "off")
        .. ")"
    )

    for _, event in ipairs(
        Utilities.GetSortedKeys(report.events.unavailable)
    ) do
        SYL:Write("  unavailable: " .. tostring(event))
    end
end

-- Built from Core/CommandList.lua so this and the minimap menu always agree.
function Reports.Help()
    SYL:Print("Commands:")

    for _, entry in ipairs(SYL.CommandList.ENTRIES) do
        SYL:Write(
            SYL.CommandList.Format(entry)
            .. " — "
            .. entry.description
        )
    end
end
