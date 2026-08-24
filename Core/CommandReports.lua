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
    SYL:Write("Started: " .. Utilities.FormatDateTime(season.startedAt))
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

    -- The numbers above are the handle. Printing the list without saying what
    -- can be done with it is how renaming an archive stayed impossible-looking
    -- for as long as it did.
    SYL:Write(
        "  /syl archives rename <number> <name>"
        .. "  ·  /syl archives merge <number> <number> [name]"
    )
    SYL:Write(
        "  Or tick them on the Archives tab and use the buttons there."
    )
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

    -- What the addon resolved those to, rather than what it hoped. These are
    -- the bind types a drop is excluded from the score for, so seeing them
    -- beside Enum.ItemBind above is the check that the fallback was not used
    -- on a client that has moved the numbers.
    local warbound = Utilities.WarboundBindTypes()

    SYL:Write(
        "Treated as warbound (excluded from score and drought): bindType "
        .. (#warbound > 0 and table.concat(warbound, ", ") or "none")
    )

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

-- Answers "who should we favor on the next drop" in chat, which is where it
-- gets asked. See Core/DueList.lua for what "due" is taken to mean.
function Reports.Due(limit)
    local sessions = SYL.GetActiveRaids()

    if #sessions == 0 then
        SYL:Print("No raid nights recorded yet.")
        SYL:Write(
            "Attendance comes from the group roster read at each pull, so "
            .. "this fills in from the next boss you engage."
        )

        return
    end

    local entries = SYL.DueList.Build(SYL.GetActiveDrops(), sessions)

    entries = SYL.DueList.FilterRecent(entries, sessions)

    -- The same scope the due window is showing, or the two disagree about who
    -- is on the list and there is no way to tell which one is lying.
    local scope = SYL.Audience.Get()
    local beforeScope = #entries

    entries = SYL.Audience.Filter(entries, scope)

    -- SHARE, NOT DROUGHT, and that is the whole point of this change. The
    -- board and the dashboard tile have ranked by score-per-night since
    -- weighted loot value replaced the drought; this command was left behind
    -- ranking by nights-since-upgrade. With one ranked raider the two agree by
    -- accident. With a roster they name different people as most owed, and two
    -- lists disagreeing about that is how an officer stops trusting both.
    SYL.LootScore.Rank(entries)

    if #entries == 0 then
        SYL:Print(
            SYL.Audience.ExplainEmpty(scope, beforeScope)
            or "Nobody from the last few nights to rank yet."
        )

        return
    end

    SYL:Print(
        "Owed the most, by loot taken per raid night — "
        .. SYL.Audience.Note(scope)
        .. ":"
    )

    for index = 1, math.min(limit or 10, #entries) do
        local entry = entries[index]

        -- CLASS COLOR IN CHAT NEEDS AN ESCAPE CODE, not SetTextColor -- a
        -- chat line is a string, not a font string. The class is right here
        -- on the entry and there was no way to use it; UI/ClassColor.lua's
        -- Name wraps it and hands back a plain name when the class is
        -- unknown, so a line can never end up with half an escape sequence
        -- in it.
        SYL:Write(
            "  " .. index .. ". "
            .. SYL.ClassColor.Name(entry.name, entry.class)
            .. " — " .. SYL.LootScore.Describe(entry)
            .. " (" .. entry.nights
            .. (entry.nights == 1 and " night, " or " nights, ")
            .. (entry.lootScore or 0) .. " points)"
        )
    end

    -- What went into these numbers, said out loud. A ranking that quietly
    -- changed what counts is one somebody will argue with and be right to.
    --
    -- One sentence now rather than four branches. The personal-loot lines
    -- that used to be here described a setting that no longer exists, and the
    -- two "some items were left out" warnings counted chat records this
    -- calculation never reads any more.
    -- The old sentence said transmog and greed do not count, which was true
    -- of the drought and is not true of the score: greed is worth 20 and
    -- transmog nothing, so both count and only one is free.
    SYL:Write(
        "  Need 100, offspec 20, greed 20, transmog 0, divided by raid nights "
        .. "attended. Group loot on bind-on-pickup items only, from nights "
        .. "that counted. Under "
        .. SYL.Utilities.Count(SYL.LootScore.MinNights(), "night")
        .. " nobody is ranked."
    )
end

function Reports.Bosses(limit)
    local bosses = SYL.BossStats.Build(
        SYL.GetActiveDrops(), SYL.GetActiveRaids()
    )

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
