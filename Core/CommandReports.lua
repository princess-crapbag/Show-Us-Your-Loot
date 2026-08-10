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

-- Answers "who should we favour on the next drop" in chat, which is where it
-- gets asked. See Core/DueList.lua for what "due" is taken to mean.
function Reports.Due(limit)
    local sessions = SYL.GetAllRaids()

    if #sessions == 0 then
        SYL:Print("No raid nights recorded yet.")
        SYL:Write(
            "Attendance comes from the group roster read at each pull, so "
            .. "this fills in from the next boss you engage."
        )

        return
    end

    local entries = SYL.DueList.Build(SYL.GetAllDrops(), sessions)

    entries = SYL.DueList.FilterRecent(entries, sessions)

    -- The same scope the due window is showing, or the two disagree about who
    -- is on the list and there is no way to tell which one is lying.
    local scope = SYL.Audience.Get()
    local beforeScope = #entries

    entries = SYL.Audience.Filter(entries, scope)
    entries = SYL.DueList.Sort(entries)

    if #entries == 0 then
        SYL:Print(
            SYL.Audience.ExplainEmpty(scope, beforeScope)
            or "Nobody from the last few nights to rank yet."
        )

        return
    end

    SYL:Print(
        "Longest without an upgrade — "
        .. SYL.Audience.Note(scope)
        .. ", transmog and greed do not count:"
    )

    for index = 1, math.min(limit or 10, #entries) do
        local entry = entries[index]

        SYL:Write(
            "  " .. index .. ". "
            .. tostring(entry.name)
            .. " — " .. SYL.DueList.Describe(entry)
            .. " (" .. entry.nights .. " raided)"
        )
    end

    -- What went into these numbers, said out loud. A ranking that quietly
    -- changed what counts is one somebody will argue with and be right to.
    --
    -- One sentence now rather than four branches. The personal-loot lines
    -- that used to be here described a setting that no longer exists, and the
    -- two "some items were left out" warnings counted chat records this
    -- calculation never reads any more.
    SYL:Write(
        "  Group-loot Need and offspec wins only, on bind-on-pickup items, "
        .. "from nights that counted as raid nights. The vault, Mythic+ "
        .. "chests, the catalyst and BoEs do not reset a drought."
    )
end

function Reports.Bosses(limit)
    local bosses = SYL.BossStats.Build(SYL.GetAllDrops(), SYL.GetAllRaids())

    if #bosses == 0 then
        SYL:Print("No bosses recorded yet.")

        return
    end

    SYL.BossStats.SortByRecent(bosses)

    SYL:Print(#bosses .. " bosses recorded:")

    for index = 1, math.min(limit or 12, #bosses) do
        local boss = bosses[index]
        local line = "  " .. tostring(boss.name)

        if boss.difficultyName then
            line = line .. " (" .. boss.difficultyName .. ")"
        end

        -- Pulls only exist for kills seen since raid sessions were added, so
        -- a boss can legitimately show drops and no pulls.
        if boss.pulls > 0 then
            line = line .. " — " .. boss.kills .. "/" .. boss.pulls .. " killed"
        end

        line = line .. ", " .. boss.drops .. " drops"

        if boss.upgrades > 0 then
            line = line .. " (" .. boss.upgrades .. " upgrades)"
        end

        SYL:Write(line)
    end
end

-- Built from Core/CommandList.lua so this and the minimap menu always agree.
