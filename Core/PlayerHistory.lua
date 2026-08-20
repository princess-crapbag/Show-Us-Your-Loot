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

        -- WHO THIS DROP COUNTS FOR, through the same door the board uses.
        --
        -- This file read roll.state and roll.isWinner raw, so it was the last
        -- screen still answering from the roll alone — and it is one click
        -- from the Players row that answers from the credit. A drop traded
        -- away, or corrected by hand, showed on the winner's detail pane as a
        -- win and on the recipient's as a pass, while the row above said the
        -- opposite. See Core/DropRules.lua; Analytics had the same fault and
        -- for the same reason.
        local creditedKey, creditedState, creditedName

        for _, roll in ipairs(drop.rolls or {}) do
            if roll.isWinner then
                creditedKey = SYL.Players.ResolveToMain(
                    SYL.DropRules.CreditedKey(drop, roll.guid or roll.name)
                )

                creditedState = SYL.DropRules.CreditedState(drop, roll.state)
            end
        end

        if creditedKey == nil and drop.winnerState ~= nil then
            creditedKey = SYL.Players.ResolveToMain(
                SYL.DropRules.CreditedKey(
                    drop, drop.winnerGUID or drop.winnerName
                )
            )

            creditedState = SYL.DropRules.CreditedState(drop, drop.winnerState)
        end

        for _, roll in ipairs(drop.rolls or {}) do
            local rollKey =
                SYL.Players.ResolveToMain(roll.guid or roll.name)

            if rollKey == key then
                local credited = creditedKey ~= nil and creditedKey == key

                table.insert(entries, {
                    drop = drop,

                    -- The corrected response only for whoever the drop is
                    -- credited to. Everybody else's own answer is a fact
                    -- about them and is left alone.
                    state = credited and creditedState or roll.state,
                    roll = roll.roll,
                    won = credited,
                    characterName = roll.name,
                })

                matched = true

                break
            end
        end

        -- CREDITED TO SOMEBODY WHO NEVER ROLLED, which is the ordinary case
        -- under a loot council and after any trade: the recipient was not
        -- eligible, or passed. Without this their own history is the one
        -- screen that never learns they were given it.
        if not matched and creditedKey ~= nil and creditedKey == key then
            local credit = SYL.LootCredit and SYL.LootCredit.Describe(drop)

            table.insert(entries, {
                drop = drop,
                state = creditedState,
                roll = nil,
                won = true,
                characterName = (credit and credit.name) or drop.winnerName,
                credited = true,
            })

            matched = true
        end

        -- Synced records carry a winner but no roll list. Their wins still
        -- belong in a history; they are marked so the absence of everyone
        -- else does not read as "nobody else wanted it".
        if not matched and drop.partial then
            local winnerKey = SYL.Players.ResolveToMain(
                SYL.DropRules.CreditedKey(
                    drop, drop.winnerGUID or drop.winnerName
                )
            )

            if winnerKey == key then
                table.insert(entries, {
                    drop = drop,
                    state = SYL.DropRules.CreditedState(
                        drop, drop.winnerState
                    ),
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
function PlayerHistory.Summarize(entries)
    local totals = {
        eligible = #entries,

        won = 0,
        -- Accumulated in the loop, not derived at the end. See the note there.
        upgrades = 0,
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

            -- The same test the board applies. This file used to add needWins
            -- and offspecWins together at the end and call that upgrades,
            -- which counted bind-on-equip, warbound and non-raid wins — so
            -- opening somebody's detail from the Players list showed a bigger
            -- number than the row that was clicked. See Core/DropRules.lua.
            local isGear = entry.state == STATE.NeedMainSpec
                or entry.state == STATE.NeedOffSpec

            if isGear and SYL.DropRules.CountsAsUpgrade(entry.drop) then
                totals.upgrades = totals.upgrades + 1
            end

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

    table.sort(totals.characterOrder)

    return totals
end
