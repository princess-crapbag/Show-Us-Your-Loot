-- Core/Export.lua
--
-- Text summaries meant to be copied out and pasted somewhere else.
--
-- Addons have no network access, so nothing here posts anywhere. It produces
-- a block you select and copy — which is all a Discord thread needs.
--
-- Output is deliberately plain text with no colour codes or item links: those
-- are WoW escape sequences and would paste as garbage outside the game.

local SYL = _G.ShowUsYourLoot

local Export = {}
SYL.Export = Export

local function Plain(text)
    if type(text) ~= "string" then
        return tostring(text)
    end

    -- Strip colour codes and unwrap hyperlinks down to the item name.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(%[.-%])|h", "%1")
    text = text:gsub("^%[(.*)%]$", "%1")

    return text
end

local function DescribeWin(record)
    if record.allPassed then
        return "everyone passed"
    end

    local winType = SYL.LootHistoryAPI.ShortRollState(record.winnerState)

    return tostring(record.winnerName or "Unknown")
        .. (winType and (" (" .. winType) or " (")
        .. (record.winnerRoll and (" " .. record.winnerRoll) or "")
        .. ")"
end

-- Groups drops by the date they were recorded. Distinct dates stand in for
-- raid nights, which is the same assumption the player stats make.
function Export.GetNights(drops)
    local nights = {}
    local order = {}

    for _, record in ipairs(drops or {}) do
        local key = record.dateText or "unknown"

        if not nights[key] then
            nights[key] = { date = key, records = {} }

            table.insert(order, nights[key])
        end

        table.insert(nights[key].records, record)
    end

    table.sort(order, function(left, right)
        return left.date > right.date
    end)

    return order
end

function Export.BuildNightSummary(night)
    local lines = {}

    table.insert(lines, "Loot — " .. tostring(night.date))
    table.insert(lines, "")

    local bosses = {}
    local bossOrder = {}

    for _, record in ipairs(night.records) do
        local boss = record.encounterName or "Unknown boss"

        if not bosses[boss] then
            bosses[boss] = {}
            table.insert(bossOrder, boss)
        end

        table.insert(bosses[boss], record)
    end

    for _, boss in ipairs(bossOrder) do
        local records = bosses[boss]
        local difficulty = records[1] and records[1].difficultyName

        table.insert(
            lines,
            boss .. (difficulty and (" (" .. difficulty .. ")") or "")
        )

        for _, record in ipairs(records) do
            table.insert(
                lines,
                "  "
                .. Plain(record.itemLink or record.itemName or "Unknown item")
                .. " - "
                .. DescribeWin(record)
            )
        end

        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

-- Who went home with nothing. Transmog and greed do not count as an upgrade,
-- so they do not remove anyone from this list.
function Export.BuildEmptyHandedSummary(drops)
    local stats = SYL.Analytics.BuildPlayerStats(drops)
    local empty = SYL.Analytics.FilterEmptyHanded(stats)

    SYL.Analytics.Sort(empty, "eligible", false)

    local lines = {}

    table.insert(lines, "No upgrade yet (" .. #empty .. " players)")
    table.insert(lines, "")

    for _, entry in ipairs(empty) do
        table.insert(
            lines,
            "  "
            .. tostring(entry.name)
            .. (entry.guildRank and (" [" .. entry.guildRank .. "]") or "")
            .. " - eligible for "
            .. entry.eligible
            .. (entry.mogWins > 0 and (", " .. entry.mogWins .. " mog") or "")
        )
    end

    return table.concat(lines, "\n")
end

function Export.BuildPlayerSummary(drops)
    local stats = SYL.Analytics.BuildPlayerStats(drops)

    SYL.Analytics.Sort(stats, "upgrades", false)

    local lines = {}

    table.insert(lines, "Player totals (" .. #stats .. " players)")
    table.insert(lines, "")
    table.insert(lines, "Player | Rank | Nights | Eligible | Upgrades | Mog")

    for _, entry in ipairs(stats) do
        table.insert(
            lines,
            table.concat({
                tostring(entry.name),
                entry.guildRank or "-",
                entry.nights,
                entry.eligible,
                entry.upgradeWins,
                entry.mogWins,
            }, " | ")
        )
    end

    return table.concat(lines, "\n")
end

function Export.BuildSeasonSummary(drops)
    local nights = Export.GetNights(drops)
    local lines = {}

    local season = SYL.GetActiveSeason()

    table.insert(
        lines,
        "Season: " .. tostring(season and season.name or "Unknown")
    )

    table.insert(
        lines,
        #drops .. " drops across " .. #nights .. " nights"
    )

    table.insert(lines, "")

    for _, night in ipairs(nights) do
        table.insert(lines, Export.BuildNightSummary(night))
    end

    table.insert(lines, Export.BuildPlayerSummary(drops))
    table.insert(lines, "")
    table.insert(lines, Export.BuildEmptyHandedSummary(drops))

    return table.concat(lines, "\n")
end
