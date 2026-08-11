-- Core/LootScore.lua
--
-- What each raider has taken, weighted, and how that compares to how often
-- they turn up.
--
-- AIMEE'S RULES, and every number here is one of them:
--
--   Need      100    the baseline
--   Offspec    20    "offspec = greed", her words
--   Greed      20
--   Transmog    0    costs nothing and deducts nothing
--
-- SHARE IS THE RANKING, not raw score. Share is score divided by raid nights
-- attended, lowest first. That is the whole of "someone with perfect
-- attendance should be valued higher for needing loot than someone who is
-- only there half the time" — two raiders on 240 points are not equal if one
-- earned it over thirteen nights and the other over seven, and dividing says
-- so without a separate attendance bonus bolted on top.
--
-- THE FLOOR EXISTS BECAUSE ZERO SORTS FIRST. A trial with one night and no
-- loot has a share of 0 and would top the list ahead of raiders who have been
-- there all tier. Below MIN_NIGHTS nobody is ranked at all — they are listed,
-- with the reason, rather than hidden or given a fake number.
--
-- WHAT COUNTS is exactly what the drought counts, and deliberately so: group
-- loot, from content that counted as a raid night, on bind-on-pickup items.
-- Two lists that disagree about which wins are real is how an officer stops
-- trusting both. See Core/DueList.lua, which owns those tests.
--
-- No decay. A season is short and archiving resets everybody to zero.

local SYL = _G.ShowUsYourLoot

local LootScore = {}
SYL.LootScore = LootScore

local API = SYL.LootHistoryAPI

-- Keyed by the roll state the API reports, so this table is the only place
-- the weights live and the UI never does arithmetic of its own.
LootScore.WEIGHTS = {
    [API.ROLL_STATE.NeedMainSpec] = 100,
    [API.ROLL_STATE.NeedOffSpec] = 20,
    [API.ROLL_STATE.Greed] = 20,
    [API.ROLL_STATE.Transmog] = 0,
}

-- Shown in the settings screen and in the tooltip that explains a number.
LootScore.LABELS = {
    [API.ROLL_STATE.NeedMainSpec] = "Need",
    [API.ROLL_STATE.NeedOffSpec] = "Offspec",
    [API.ROLL_STATE.Greed] = "Greed",
    [API.ROLL_STATE.Transmog] = "Transmog",
}

-- Three nights, matching the "recent raiders" window the due list already
-- uses. One threshold in the addon rather than two that drift.
LootScore.MIN_NIGHTS = 3

function LootScore.WeightOf(state)
    return LootScore.WEIGHTS[state] or 0
end

--------------------------------------------------------------------------
-- Which drops count
--------------------------------------------------------------------------

-- The same test the drought uses. Kept as one call so the two can never take
-- different views of the same drop.
local function Counts(drop)
    if drop.excludedFromAnalytics then
        return false
    end

    if SYL.Utilities.IsBindOnEquip(drop.itemLink) == true then
        return false
    end

    -- Records with no location predate the field and are almost certainly
    -- raid drops; treating unknown as "not a raid" would erase real history.
    if not drop.instanceType and not drop.difficultyID then
        return true
    end

    return SYL.Utilities.IsRaidContent(drop.instanceType, drop.difficultyID)
end

--------------------------------------------------------------------------
-- Stars
--------------------------------------------------------------------------

-- An officer's mark on a won item. Deliberately worth nothing: Aimee asked
-- for the rare multiplier to be dropped and replaced by "a star to represent
-- it was a rare item", so this changes no total anywhere. It is the thing you
-- point at in an argument rather than the thing that wins it.
function LootScore.IsStarred(record)
    return (record and record.starred) and true or false
end

function LootScore.ToggleStar(record)
    if not record then
        return false
    end

    -- nil rather than false when off, so a season of records does not carry a
    -- field per drop into SavedVariables.
    record.starred = (not record.starred) or nil

    return record.starred == true
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- Takes the roll state rather than the weight it maps to, so the one place
-- that reads WEIGHTS is also the place that can remember what was counted.
-- Without that, a total is a number with no way back to the wins behind it,
-- and "where did my score come from" cannot be answered from stored data.
local function Add(totals, key, state, at)
    if not key then
        return
    end

    local entry = totals[key]

    if not entry then
        entry = { key = key, score = 0, wins = 0, lastAt = nil, byState = {} }
        totals[key] = entry
    end

    entry.score = entry.score + LootScore.WeightOf(state)
    entry.wins = entry.wins + 1

    -- Transmog weighs nothing and still counts here. A raider with six
    -- transmog wins and a zero contribution from them is exactly the person
    -- who wants to see the six listed, because the number they are arguing
    -- with is the one that does not mention them.
    if state ~= nil then
        entry.byState[state] = (entry.byState[state] or 0) + 1
    end

    if at and (not entry.lastAt or at > entry.lastAt) then
        entry.lastAt = at
    end
end

-- Score per player key. Alts fold through ResolveToMain, the same as
-- everywhere else — a person has one score however many characters earned it.
function LootScore.BuildTotals(drops)
    local totals = {}

    for _, drop in ipairs(drops or {}) do
        if Counts(drop) then
            local counted = false

            -- The roll list names the winner and their state together. Synced
            -- records carry no roll list, so the header is the fallback.
            for _, roll in ipairs(drop.rolls or {}) do
                if roll.isWinner then
                    -- Traded away means credited away. Routed through the same
                    -- choke point DueList uses, because two lists that
                    -- disagree about who won an item is how an officer stops
                    -- trusting both.
                    Add(
                        totals,
                        SYL.Players.ResolveToMain(
                            SYL.TradeTracker.CreditedIdentity(
                                drop, roll.guid or roll.name
                            )
                        ),
                        roll.state,
                        drop.timestamp
                    )

                    counted = true
                end
            end

            if not counted and drop.winnerState ~= nil then
                Add(
                    totals,
                    SYL.Players.ResolveToMain(
                        SYL.TradeTracker.CreditedIdentity(
                            drop, drop.winnerGUID or drop.winnerName
                        )
                    ),
                    drop.winnerState,
                    drop.timestamp
                )
            end
        end
    end

    return totals
end

-- Attaches score, share and rankability onto rows that already carry a key
-- and a nights count — which is what DueList.Build returns, so the two
-- compose rather than each sweeping the drops again.
--
-- `share` is nil rather than 0 for anybody under the floor. Nil is what makes
-- the sort put them last and the UI print a reason; a zero would put them
-- first and look like an answer.
function LootScore.Attach(entries, drops)
    local totals = LootScore.BuildTotals(drops)

    for _, entry in ipairs(entries or {}) do
        local totalsFor = totals[entry.key]

        entry.lootScore = totalsFor and totalsFor.score or 0
        entry.lootWins = totalsFor and totalsFor.wins or 0
        entry.byState = totalsFor and totalsFor.byState or {}

        local nights = entry.nights or 0

        if nights >= LootScore.MIN_NIGHTS then
            entry.share = entry.lootScore / nights
            entry.ranked = true
        else
            entry.share = nil
            entry.ranked = false
            entry.notRankedReason = nights == 0
                and "has not raided yet"
                or ("under " .. LootScore.MIN_NIGHTS .. " nights")
        end
    end

    return entries
end

-- The average share across everybody who is ranked. Drawn as the line on the
-- board, and it is the only reason a bar length means anything.
function LootScore.Average(entries)
    local total, counted = 0, 0

    for _, entry in ipairs(entries or {}) do
        if entry.ranked and entry.share then
            total = total + entry.share
            counted = counted + 1
        end
    end

    if counted == 0 then
        return 0, 0
    end

    return total / counted, counted
end

-- Lowest share first: the most due raider is the one who has taken least per
-- night. Unranked always last, whatever their score, then alphabetical so the
-- order does not shuffle between redraws.
function LootScore.Sort(entries)
    table.sort(entries, function(left, right)
        if left.ranked ~= right.ranked then
            return left.ranked
        end

        if left.ranked and left.share ~= right.share then
            return left.share < right.share
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return entries
end

-- One number for a bar, 0 to 1, scaled against the highest share on the list
-- rather than against the average — so the longest bar always reaches the end
-- and the shape uses the full width whatever the numbers happen to be.
function LootScore.BarFraction(entry, highest)
    if not entry.ranked or not entry.share or not highest or highest <= 0 then
        return 0
    end

    return math.min(1, entry.share / highest)
end

function LootScore.Highest(entries)
    local highest = 0

    for _, entry in ipairs(entries or {}) do
        if entry.ranked and entry.share and entry.share > highest then
            highest = entry.share
        end
    end

    return highest
end

-- Fixed order, worth most first. Read off WEIGHTS would shuffle, because
-- pairs over a table keyed by enum values has no order to promise.
LootScore.STATE_ORDER = {
    API.ROLL_STATE.NeedMainSpec,
    API.ROLL_STATE.NeedOffSpec,
    API.ROLL_STATE.Greed,
    API.ROLL_STATE.Transmog,
}

-- Where a score came from, as rows: label, how many, what each was worth, and
-- what they contributed. This is the screen somebody stands at when they
-- disagree with their number, so it has to add up to the total on its own
-- rather than asking them to take the total on trust.
--
-- Rows with no wins are dropped. A breakdown listing four zeroes to explain a
-- score of zero says less than the sentence "no wins yet" does.
function LootScore.Breakdown(entry)
    local rows = {}

    if not entry then
        return rows
    end

    local byState = entry.byState or {}

    for _, state in ipairs(LootScore.STATE_ORDER) do
        local count = byState[state] or 0

        if count > 0 then
            local weight = LootScore.WeightOf(state)

            table.insert(rows, {
                state = state,
                label = LootScore.LABELS[state] or "Unknown",
                count = count,
                weight = weight,
                points = count * weight,
            })
        end
    end

    return rows
end

-- ATTACH AND SORT TOGETHER, because doing one without the other is how two
-- screens end up ranking by different rules. /syl due sorted by drought for
-- days after the board moved to share: with one ranked raider they agreed by
-- accident, and with a roster they would have named different people as most
-- owed. Same reasoning as Players.ResolveToMain and TradeTracker
-- .CreditedIdentity — one choke point, so there is nothing to keep in step.
function LootScore.Rank(entries, drops)
    LootScore.Attach(entries, drops or SYL.GetAllDrops())

    return LootScore.Sort(entries)
end

function LootScore.Describe(entry)
    if not entry.ranked then
        return entry.notRankedReason or "not ranked"
    end

    return string.format("%.1f per night", entry.share)
end
