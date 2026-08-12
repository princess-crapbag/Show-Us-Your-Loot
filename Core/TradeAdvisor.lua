-- Core/TradeAdvisor.lua
--
-- You won something. Who else rolled Need on it, who among them is owed most,
-- and how long you have left to hand it over.
--
-- WHY THIS IS THE ONE FEATURE WITH NO COLD START. Everything else in this
-- addon needs a season of history before it says anything useful — the score,
-- the board, the calendar all read as empty on install night. The roll list is
-- complete on the very first drop, because the game hands over every eligible
-- player and what each chose at the moment the item is awarded. So this works
-- the first time somebody wins an item, with no history at all, which is why
-- five reviewers put it top.
--
-- IT IS INFORMATIONAL AND CANNOT BE ANYTHING ELSE. An addon cannot click a
-- loot or trade button — they are protected, and Guild Loot Distribution hit
-- that wall and had to fall back to announcing. So this never trades, never
-- whispers and never posts. It answers a question the winner already has to
-- answer, and the answer is the whole feature.
--
-- IT ALSO ANSWERS THE THING NOBODY HAD NAMED. A guild running Group Loot has,
-- by definition, chosen not to have a loot process. Handing them fairness
-- analytics for their own sake invites drama they opted out of. This is the
-- other shape: the history is not the point, it is what makes a decision
-- somebody is already standing there making take five seconds instead of a
-- guess.
--
-- WHAT IS STORED IS AN ID AND A TIME, nothing else. The record itself lives in
-- season.drops and resolves in stages — a roll list captured at the moment of
-- the win is often the emptier one, and a copy taken then would be wrong by
-- the time it is read. So this holds a pointer and re-reads.

local SYL = _G.ShowUsYourLoot

local TradeAdvisor = {}
SYL.TradeAdvisor = TradeAdvisor

local API = SYL.LootHistoryAPI

-- Blizzard's window, and it is two hours from when the item was awarded rather
-- than from when this addon noticed. wonAt is the record's own timestamp for
-- exactly that reason.
TradeAdvisor.WINDOW_SECONDS = 7200

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.tradeWindow = ShowUsYourLootDB.tradeWindow or {}

    return ShowUsYourLootDB.tradeWindow
end

function TradeAdvisor.IsEnabled()
    return SYL.Features.IsEnabled("tradeAdvisor")
end

--------------------------------------------------------------------------
-- Whose win it is
--------------------------------------------------------------------------

-- Only the winner's own client can act on this, so only the winner's client
-- opens it. Matched on GUID first: two people on different realms can share a
-- name, and the name on a roll list is not always realm-qualified.
local function WonByPlayer(record)
    if not record then
        return false
    end

    local guid = UnitGUID and UnitGUID("player")

    if guid and record.winnerGUID then
        return record.winnerGUID == guid
    end

    if not record.winnerName then
        return false
    end

    local full = SYL.Utilities.GetPlayerFullName()
    local short = full and full:match("^([^-]+)") or full

    return record.winnerName == full or record.winnerName == short
end

TradeAdvisor.WonByPlayer = WonByPlayer

--------------------------------------------------------------------------
-- Remembering a win
--------------------------------------------------------------------------

local function Find(store, id)
    for _, entry in ipairs(store) do
        if entry.id == id then
            return entry
        end
    end

    return nil
end

-- Called for every drop the store writes, first capture or later resolution.
-- Deduped on the record id, so a drop that resolves over three passes is one
-- entry rather than three.
function TradeAdvisor.Consider(record)
    if not TradeAdvisor.IsEnabled() or not record or not record.id then
        return false
    end

    if not WonByPlayer(record) then
        return false
    end

    -- A win with nobody else on the roll list has nothing to advise about.
    -- Checked here rather than at draw time so an entry is never created for a
    -- panel that would open empty.
    if #TradeAdvisor.Candidates(record) == 0 then
        return false
    end

    local store = Store()

    if not store then
        return false
    end

    if Find(store, record.id) then
        return false
    end

    table.insert(store, {
        id = record.id,
        wonAt = record.timestamp or time(),
    })

    if SYL.TradeAdvisorPanel then
        SYL.TradeAdvisorPanel.Show()
    end

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

function TradeAdvisor.SecondsLeft(entry)
    if not entry or not entry.wonAt then
        return 0
    end

    return math.max(0, (entry.wonAt + TradeAdvisor.WINDOW_SECONDS) - time())
end

-- Written as "1h 04m" rather than a bare count, because the number people act
-- on is "have I got time to ask them" and minutes alone stops reading as
-- urgent somewhere around ninety of them.
function TradeAdvisor.FormatRemaining(seconds)
    seconds = math.max(0, math.floor(seconds or 0))

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end

    return string.format("%dm %02ds", minutes, seconds % 60)
end

-- Drops expired entries and returns how many went. Called before every read,
-- so an entry cannot outlive its window even if nothing ever ticks.
function TradeAdvisor.Sweep()
    local store = Store()

    if not store then
        return 0
    end

    local kept, dropped = {}, 0

    for _, entry in ipairs(store) do
        if TradeAdvisor.SecondsLeft(entry) > 0 then
            table.insert(kept, entry)
        else
            dropped = dropped + 1
        end
    end

    if dropped > 0 then
        ShowUsYourLootDB.tradeWindow = kept
    end

    return dropped
end

function TradeAdvisor.Dismiss(id)
    local store = Store()

    if not store then
        return false
    end

    for index, entry in ipairs(store) do
        if entry.id == id then
            table.remove(store, index)

            return true
        end
    end

    return false
end

-- Still open, soonest to expire first — the one you are about to run out of
-- time on is the one to deal with.
function TradeAdvisor.Active()
    TradeAdvisor.Sweep()

    local store = Store()
    local active = {}

    for _, entry in ipairs(store or {}) do
        local record = SYL.LootHistoryStore.GetRecord(entry.id)

        if record then
            table.insert(active, {
                id = entry.id,
                wonAt = entry.wonAt,
                record = record,
                secondsLeft = TradeAdvisor.SecondsLeft(entry),
            })
        end
    end

    table.sort(active, function(left, right)
        if left.secondsLeft ~= right.secondsLeft then
            return left.secondsLeft < right.secondsLeft
        end

        return tostring(left.id) < tostring(right.id)
    end)

    return active
end

--------------------------------------------------------------------------
-- Who lost
--------------------------------------------------------------------------

-- Need first, then offspec, and each row says which it was. Aimee's rule is
-- that offspec is greed, so the two are not equivalent and must not be shown
-- as one list — but somebody who rolled offspec still wanted it, and leaving
-- them off entirely answers a narrower question than the winner is asking.
local WANTED = {
    [API.ROLL_STATE.NeedMainSpec] = 1,
    [API.ROLL_STATE.NeedOffSpec] = 2,
}

function TradeAdvisor.Candidates(record)
    local candidates = {}

    if not record then
        return candidates
    end

    for _, roll in ipairs(record.rolls or {}) do
        local rank = WANTED[roll.state]

        if rank and not roll.isWinner then
            table.insert(candidates, {
                key = SYL.Players.ResolveToMain(roll.guid or roll.name)
                    or roll.guid or roll.name,
                guid = roll.guid,
                name = roll.name,
                class = roll.class,
                state = roll.state,
                stateRank = rank,
                stateLabel = SYL.LootScore.LABELS[roll.state] or "?",
                roll = roll.roll,
            })
        end
    end

    return candidates
end

-- The candidates with their standing attached, in the order the winner should
-- read them: most due first, within Need before offspec.
--
-- `due` is nil for anybody the fairness maths has never seen, which on install
-- night is everybody. That is the cold-start case and it is not an error — the
-- list is still correct and still worth reading, it just cannot rank yet.
function TradeAdvisor.RankCandidates(record)
    local candidates = TradeAdvisor.Candidates(record)

    if #candidates == 0 then
        return candidates
    end

    local drops = SYL.GetActiveDrops()
    local entries = SYL.DueList.Build(drops, SYL.GetActiveRaids())

    SYL.LootScore.Attach(entries, drops)

    local byKey = {}

    for _, entry in ipairs(entries) do
        byKey[entry.key] = entry
    end

    for _, candidate in ipairs(candidates) do
        candidate.due = byKey[candidate.key]
    end

    table.sort(candidates, function(left, right)
        if left.stateRank ~= right.stateRank then
            return left.stateRank < right.stateRank
        end

        local leftRanked = left.due and left.due.ranked
        local rightRanked = right.due and right.due.ranked

        -- Anybody who can be ranked outranks anybody who cannot, or a trial
        -- with no history would sit above the raider who has been there all
        -- tier purely for having no number.
        if leftRanked ~= rightRanked then
            return leftRanked and true or false
        end

        if leftRanked and left.due.share ~= right.due.share then
            return left.due.share < right.due.share
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return candidates
end

-- What to print beside a name. Falls all the way back to something true rather
-- than to a zero, because a zero here reads as "has taken nothing", which is
-- the opposite of "we have never seen them".
function TradeAdvisor.DescribeCandidate(candidate)
    if not candidate or not candidate.due then
        return "no history yet"
    end

    return SYL.LootScore.Describe(candidate.due)
end
