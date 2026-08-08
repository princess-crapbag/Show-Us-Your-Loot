-- Core/PlayerHistory.lua
--
-- One player's whole record: every drop they were eligible for, what they
-- chose, and what they got.
--
-- The players window answers "how many" and this answers "which". An officer
-- looking at someone with eleven eligibles and no upgrades wants to know
-- whether they passed on everything or lost eleven rolls, and those are very
-- different conversations.
--
-- Keyed by the main, so a raider's alt runs appear here rather than in a
-- separate history nobody thinks to open. The character actually played is
-- kept on each entry, since "you won that on your alt" is the sort of thing
-- people dispute.
--
-- Pure computation over the records, like Analytics. Nothing stored.

local SYL = _G.ShowUsYourLoot

local PlayerHistory = {}
SYL.PlayerHistory = PlayerHistory

local STATE = SYL.LootHistoryAPI.ROLL_STATE

-- Drops are passed in so a caller can scope this to a season or to
-- everything, the same way BossStats and DueList take theirs.
function PlayerHistory.Build(key, drops)
    if not key then
        return {}
    end

    local entries = {}

    for _, drop in ipairs(drops or {}) do
        local matched = false

        for _, roll in ipairs(drop.rolls or {}) do
            local rollKey =
                SYL.Players.ResolveToMain(roll.guid or roll.name)

            if rollKey == key then
                table.insert(entries, {
                    drop = drop,
                    state = roll.state,
                    roll = roll.roll,
                    won = roll.isWinner and true or false,
                    characterName = roll.name,
                })

                matched = true

                break
            end
        end

        -- Synced records carry a winner but no roll list. Their wins still
        -- belong in a history; they are marked so the absence of everyone
        -- else does not read as "nobody else wanted it".
        if not matched and drop.partial then
            local winnerKey = SYL.Players.ResolveToMain(
                drop.winnerGUID or drop.winnerName
            )

            if winnerKey == key then
                table.insert(entries, {
                    drop = drop,
                    state = drop.winnerState,
                    roll = drop.winnerRoll,
                    won = true,
                    characterName = drop.winnerName,
                    partial = true,
                })
            end
        end
    end

    table.sort(entries, function(left, right)
        return (left.drop.timestamp or 0) > (right.drop.timestamp or 0)
    end)

    return entries
end

-- Counts that describe the list above it. Kept apart from Analytics because
-- that builds every player at once and this answers about one, and running
-- the whole thing to read a single row would be wasteful.
function PlayerHistory.Summarise(entries)
    local totals = {
        eligible = #entries,

        won = 0,
        needWins = 0,
        offspecWins = 0,
        mogWins = 0,
        greedWins = 0,

        passed = 0,
        lost = 0,

        characters = {},
        characterOrder = {},
    }

    for _, entry in ipairs(entries) do
        if entry.won then
            totals.won = totals.won + 1

            if entry.state == STATE.NeedMainSpec then
                totals.needWins = totals.needWins + 1
            elseif entry.state == STATE.NeedOffSpec then
                totals.offspecWins = totals.offspecWins + 1
            elseif entry.state == STATE.Transmog then
                totals.mogWins = totals.mogWins + 1
            elseif entry.state == STATE.Greed then
                totals.greedWins = totals.greedWins + 1
            end
        elseif entry.roll then
            -- They rolled and someone else won it.
            totals.lost = totals.lost + 1
        else
            -- No roll recorded means they never entered: passed, or took
            -- transmog, which does not roll.
            totals.passed = totals.passed + 1
        end

        local name = entry.characterName

        if name and not totals.characters[name] then
            totals.characters[name] = true

            table.insert(totals.characterOrder, name)
        end
    end

    totals.upgrades = totals.needWins + totals.offspecWins

    table.sort(totals.characterOrder)

    return totals
end
