-- UI/DeveloperReport.lua
--
-- Builds the human-readable text shown in the developer window. Kept apart
-- from the window itself so the report can also be printed or exported.
--
-- Raw tables are included alongside the derived fields on purpose: the whole
-- point of this tool is to reveal fields we do not yet know the names of.

local SYL = _G.ShowUsYourLoot
local Serializer = SYL.Serializer
local Utilities = SYL.Utilities
local LootHistory = SYL.LootHistory

local DeveloperReport = {}
SYL.DeveloperReport = DeveloperReport

local RECENT_EVENT_LIMIT = 15

local function IndentBlock(text, spaces)
    local prefix = string.rep(" ", spaces)
    local lines = {}

    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, prefix .. line)
    end

    return table.concat(lines, "\n")
end

local function AppendInspectorSection(lines)
    local state = LootHistory.state

    table.insert(lines, "INSPECTOR")
    table.insert(lines, "  enabled: " .. tostring(LootHistory.IsEnabled()))

    table.insert(
        lines,
        "  C_LootHistory present: " .. tostring(LootHistory.IsAvailable())
    )

    table.insert(lines, "  events captured: " .. state.logCounter)
    table.insert(lines, "  events monitored: " .. #state.registeredEvents)

    local unavailableCount = Utilities.CountKeys(state.unavailableEvents)

    if unavailableCount > 0 then
        table.insert(
            lines,
            "  events unavailable in this client: " .. unavailableCount
        )

        for _, event in ipairs(
            Utilities.GetSortedKeys(state.unavailableEvents)
        ) do
            table.insert(lines, "    " .. tostring(event))
        end
    end

    table.insert(lines, "")
end

local function AppendLastEventSection(lines)
    local entry = LootHistory.state.lastEvent

    table.insert(lines, "LAST EVENT")

    if not entry then
        table.insert(lines, "  none captured yet")
        table.insert(lines, "")

        return
    end

    table.insert(
        lines,
        "  "
        .. entry.clockText
        .. "  "
        .. entry.event
        .. "  ("
        .. entry.argCount
        .. " args)"
    )

    for index = 1, entry.argCount do
        table.insert(
            lines,
            "    [" .. index .. "] " .. tostring(entry.args[index])
        )
    end

    table.insert(lines, "")
end

local function AppendPlayers(lines, players, playerError)
    if playerError then
        table.insert(lines, "      players: " .. tostring(playerError))
        return
    end

    if #players == 0 then
        table.insert(lines, "      players: none returned")
        return
    end

    table.insert(lines, "      players (" .. #players .. "):")

    for _, player in ipairs(players) do
        table.insert(
            lines,
            "        "
            .. player.index
            .. ". "
            .. tostring(player.name)
            .. "  ["
            .. tostring(player.class)
            .. "]  state="
            .. tostring(player.rollStateText)
            .. "  roll="
            .. tostring(player.roll)
            .. "  winner="
            .. tostring(player.isWinner)
        )

        table.insert(
            lines,
            IndentBlock(Serializer.ToText(player.raw, "raw"), 10)
        )
    end
end

local function AppendDrop(lines, drop, position)
    table.insert(
        lines,
        "    DROP "
        .. position
        .. "  lootListID="
        .. tostring(drop.lootListID)
    )

    table.insert(lines, "      item: " .. tostring(drop.itemHyperlink))
    table.insert(lines, "      itemID: " .. tostring(drop.itemID))
    table.insert(lines, "      allPassed: " .. tostring(drop.allPassed))

    table.insert(
        lines,
        "      isCurrentlyRolling: " .. tostring(drop.isCurrentlyRolling)
    )

    table.insert(lines, "      winner: " .. tostring(drop.winnerName))

    table.insert(
        lines,
        "      playerRollState: " .. tostring(drop.rollStateText)
    )

    AppendPlayers(lines, drop.players, drop.playerError)

    table.insert(
        lines,
        IndentBlock(Serializer.ToText(drop.raw, "raw drop"), 6)
    )

    table.insert(lines, "")
end

local function AppendEncounterSection(lines)
    local state = LootHistory.state
    local snapshot = state.currentSnapshot

    table.insert(lines, "CURRENT ENCOUNTER")

    if not snapshot then
        table.insert(lines, "  no encounter data captured yet")
        table.insert(lines, "")

        return
    end

    table.insert(lines, "  encounterID: " .. tostring(snapshot.encounterID))

    table.insert(
        lines,
        "  encounterName: " .. tostring(snapshot.encounterName)
    )

    table.insert(
        lines,
        "  capturedAt: " .. Utilities.FormatClockTime(snapshot.capturedAt)
    )

    table.insert(
        lines,
        "  currentLootListID: " .. tostring(state.currentLootListID)
    )

    if snapshot.error then
        table.insert(lines, "  error: " .. tostring(snapshot.error))
        table.insert(lines, "")

        return
    end

    table.insert(lines, "  drops: " .. #snapshot.drops)
    table.insert(lines, "")

    for position, drop in ipairs(snapshot.drops) do
        AppendDrop(lines, drop, position)
    end
end

local function AppendRecentEventsSection(lines)
    local log = LootHistory.GetLog()

    table.insert(lines, "RECENT EVENTS")

    if #log == 0 then
        table.insert(lines, "  none captured yet")

        return
    end

    local startIndex = math.max(1, #log - RECENT_EVENT_LIMIT + 1)

    for index = startIndex, #log do
        local entry = log[index]
        local arguments = {}

        for argIndex = 1, entry.argCount do
            table.insert(arguments, tostring(entry.args[argIndex]))
        end

        table.insert(
            lines,
            "  "
            .. entry.clockText
            .. "  "
            .. entry.event
            .. "("
            .. table.concat(arguments, ", ")
            .. ")"
        )
    end
end

function DeveloperReport.Build()
    local lines = {}

    AppendInspectorSection(lines)
    AppendLastEventSection(lines)
    AppendEncounterSection(lines)
    AppendRecentEventsSection(lines)

    return table.concat(lines, "\n")
end
