-- Core/LootFeed.lua
--
-- One list of everything anybody received, however it reached them.
--
-- The addon kept two: group-loot rolls from the loot history, and everything
-- else from chat. That split describes how a record was captured rather than
-- what it is, and it made the obvious question — what did this person get —
-- unanswerable without checking two tabs and knowing which held what.
--
-- Worse, every raid win was in both. Winning a roll prints a loot line too,
-- so the same item appeared as a roll on one tab and an award on the other.
--
-- STORAGE IS NOT MERGED, ONLY THE VIEW. The two tables have different shapes
-- and different capture paths, and rewriting saved history to fix a display
-- problem risks the one thing this addon promises never to lose. They are
-- joined when the list is built, and the drop wins any tie because it knows
-- strictly more: a chat line cannot say who else rolled.
--
-- WHAT IS KNOWABLE. Roll information exists only in the loot history — chat
-- says "Aimee receives loot" and stops. So a rolled item carries its full
-- roll list and an awarded one carries none, and the type column says which
-- rather than pretending they are the same kind of record.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local LootFeed = {}
SYL.LootFeed = LootFeed

local STATE = SYL.LootHistoryAPI.ROLL_STATE

-- Ordered for the filter dropdown. Rolled types first, since those are the
-- ones with a roll list behind them.
LootFeed.TYPES = {
    "need", "offspec", "mog", "greed", "passed",
    "personal", "vault", "crafted", "world",
}

LootFeed.TYPE_LABELS = {
    need = "Need",
    offspec = "Offspec",
    mog = "Mog",
    greed = "Greed",
    passed = "Passed",
    personal = "Personal",
    vault = "Vault",
    crafted = "Crafted",
    world = "World",
}

-- Whether the type came from a roll. The detail window has a roll list to
-- show for these and nothing to show for the rest.
LootFeed.ROLLED = {
    need = true, offspec = true, mog = true, greed = true, passed = true,
}

local ROLL_STATE_TYPES = {
    [STATE.NeedMainSpec] = "need",
    [STATE.NeedOffSpec] = "offspec",
    [STATE.Transmog] = "mog",
    [STATE.Greed] = "greed",
}

-- HOW THE PERSON WHO GOT IT GOT IT, not how the master looter rolled.
--
-- Aimee, on a dagger she rolled Mog on and credited to Hawt as a Need: "the
-- type still shows as mog in the loot screen. i did roll as mog but he won it
-- as need so it should really show how he won it."
--
-- The roll list first and the header second, the same order Core/LootScore.lua
-- reads them in — a synced record carries no roll list, and the two must not
-- disagree about one drop.
local function CreditedState(drop)
    for _, roll in ipairs(drop.rolls or {}) do
        if roll.isWinner then
            return SYL.DropRules.CreditedState(drop, roll.state)
        end
    end

    return SYL.DropRules.CreditedState(drop, drop.winnerState)
end

local function DropType(drop)
    if drop.allPassed then
        return "passed"
    end

    -- NoRoll, Pass and nil are not Need wins. Defaulting them to need
    -- overstated Need in the type column while DueList correctly refused to
    -- count them, so the list and the math disagreed about one record.
    return ROLL_STATE_TYPES[CreditedState(drop)] or "personal"
end

-- Chat records carry no roll, so the type is inferred from where and how the
-- item arrived. That inference lives in PersonalLoot, because the fairness
-- math has to make the same call and previously did not make it at all.
local LootTypeOf = SYL.PersonalLoot.LootTypeOf

-- One spelling per person.
--
-- The two sources disagree: the loot history gives "Aimee" and chat gives
-- "Aimee-Draenor" for the same character on the same night. The list showed
-- both, and the Player filter listed both as separate options — so filtering
-- to a raider hid half their loot, silently, and the half it hid depended on
-- which pipeline had captured it.
--
-- The registry knows which characters exist and refuses to answer when a bare
-- name is ambiguous across realms. That refusal is kept: an unresolvable name
-- keeps its realm suffix and stays its own entry, because two people really
-- called Aimee are two people, and merging them would be a worse error than
-- listing them twice.
-- RETURNS THE CLASS TOO, and that second value is the whole reason every
-- chat-captured row in the loot list was drawn in plain white.
--
-- Personal loot, vault items, crafted gear and world drops all come through
-- FromLoot below, and it set `player` from here and no class at all -- so
-- UI/LootListView.lua had nothing to color with and fell through to
-- textPrimary on what is by far the most numerous kind of row in the list.
-- Her database holds 193 chat-captured records against 38 group-loot ones.
--
-- The player record was already being fetched and thrown away one line later.
-- No new lookup, nothing stored, and an unresolvable name still answers no
-- class rather than a guessed one.
local function DisplayName(name)
    if type(name) ~= "string" or name == "" then
        return name
    end

    local guid = SYL.Players.GUIDForName(name)
    local player = guid and SYL.Players.Get(guid)

    if not player then
        return name
    end

    return player.name or name, player.class
end

local function WhereOf(record)
    local place = record.instanceName or record.zoneName

    if not place or place == "" then
        return ""
    end

    local difficulty = Utilities.ShortDifficulty(
        record.difficultyID, record.difficultyName
    )

    if difficulty then
        return place .. "  " .. difficulty
    end

    return place
end

local function FromDrop(drop)
    local typeKey = DropType(drop)

    -- WHO IT COUNTS FOR, NOT WHO THE CLIENT SAYS WON IT. Aimee, on a loot tab
    -- showing her name against eight items she had handed out: "from the loot
    -- tab it looks like i got all of these items."
    --
    -- Under a loot council she wins every roll and gives the item away, so her
    -- name on every row is true and useless. The row names whoever the drop is
    -- credited to and marks that it was passed on; who won the roll is on the
    -- row's tooltip and on the drop detail, both one step away.
    local credit = SYL.LootCredit and SYL.LootCredit.Describe(drop)

    local passedOn = credit
        and credit.source ~= "roll"
        and credit.name ~= credit.priorName
        or nil

    return {
        id = drop.id,
        source = "drop",
        record = drop,
        drop = drop,

        player = DisplayName(credit and credit.name or drop.winnerName),

        -- Kept beside it rather than folded into the name, so the list can
        -- mark the row and the tooltip can say both halves.
        passedOn = passedOn,
        wonBy = passedOn and DisplayName(credit.priorName) or nil,
        creditSource = credit and credit.source or nil,
        creditedClass = credit and credit.class or nil,
        itemLink = drop.itemLink,
        itemName = drop.itemName,
        itemID = drop.itemID,

        typeKey = typeKey,
        typeLabel = LootFeed.TYPE_LABELS[typeKey],
        roll = drop.winnerRoll,

        -- Carried onto the entry so the list can group by them without
        -- reaching back into the record it was built from. A drop is group
        -- loot and can never be a bonus roll, so only the flag travels.
        excludedFromAnalytics = drop.excludedFromAnalytics,

        where = WhereOf(drop),
        instanceType = drop.instanceType,
        difficultyID = drop.difficultyID,

        timestamp = drop.timestamp or 0,
    }
end

local function FromLoot(record)
    local typeKey = LootTypeOf(record)
    local displayName, displayClass = DisplayName(record.recipient)

    return {
        id = record.id,
        source = "loot",
        record = record,

        player = displayName,

        -- The same field name FromDrop uses, so UI/LootListView.lua asks one
        -- question of both kinds of row.
        creditedClass = displayClass,

        itemLink = record.itemLink,
        itemName = record.itemName,
        itemID = record.itemID,

        typeKey = typeKey,
        typeLabel = LootFeed.TYPE_LABELS[typeKey],

        excludedFromAnalytics = record.excludedFromAnalytics,

        -- Only chat-captured records can be one. A bonus roll has no Need or
        -- Greed on it and never reaches the Loot History API at all, which is
        -- why it has always been outside the fairness math.
        bonusRoll = record.bonusRoll,

        where = WhereOf(record),
        instanceType = record.instanceType,
        difficultyID = record.difficultyID,

        timestamp = record.timestamp or 0,
    }
end

-- Oldest first, because the list draws from the end of the array so that row
-- one is the most recent. Returning newest first would show it upside down.
function LootFeed.Build(drops, lootRecords)
    local entries = {}

    for _, drop in ipairs(drops or {}) do
        table.insert(entries, FromDrop(drop))
    end

    -- The overlap is subtracted using the same matcher the due list uses, so
    -- the list and the math cannot disagree about what counts as a repeat.
    local dropIndex = SYL.PersonalLoot.IndexDrops(drops)

    for _, record in ipairs(lootRecords or {}) do
        if not SYL.PersonalLoot.MatchesADrop(record, dropIndex) then
            table.insert(entries, FromLoot(record))
        end
    end

    -- A stable tiebreak, or two items received in the same second swap places
    -- between redraws. Computed once per entry rather than inside the
    -- comparator, which ran tostring on both sides of every comparison — n
    -- log n calls to convert strings that were already strings.
    for _, entry in ipairs(entries) do
        entry.sortID = tostring(entry.id)
    end

    table.sort(entries, function(left, right)
        if left.timestamp ~= right.timestamp then
            return left.timestamp < right.timestamp
        end

        return left.sortID < right.sortID
    end)

    return entries
end

-- Sorting the list by a column.
--
-- Build above produces the canonical order — oldest first, stable. This is
-- the display order, which is a different question and is the user's to
-- answer. Kept here rather than in the window because the entry shape is
-- this file's, and a comparator that reads a field the builder renamed
-- should break next to the builder.
local function Text(value)
    return tostring(value or ""):lower()
end

LootFeed.COMPARATORS = {
    -- Newest first, which is what the list has always shown and what the
    -- window opens on.
    date = function(left, right)
        return (left.timestamp or 0) > (right.timestamp or 0)
    end,

    player = function(left, right)
        return Text(left.player) < Text(right.player)
    end,

    item = function(left, right)
        return Text(left.itemName) < Text(right.itemName)
    end,

    location = function(left, right)
        return Text(left.where) < Text(right.where)
    end,

    wintype = function(left, right)
        return Text(left.typeLabel) < Text(right.typeLabel)
    end,
}

function LootFeed.Sort(entries, key, reversed)
    local comparator = LootFeed.COMPARATORS[key] or LootFeed.COMPARATORS.date

    table.sort(entries, function(left, right)
        local result = comparator(left, right)

        -- A tie falls back to the canonical order, which is unique per
        -- entry. That is not only for stable output: table.sort raises
        -- "invalid order function" when a comparator reports two elements as
        -- equal inconsistently, and sorting a season of loot by four-letter
        -- type labels produces a great many ties.
        if not result and not comparator(right, left) then
            if (left.timestamp or 0) ~= (right.timestamp or 0) then
                return (left.timestamp or 0) > (right.timestamp or 0)
            end

            return left.sortID < right.sortID
        end

        if reversed then
            return comparator(right, left)
        end

        return result
    end)

    return entries
end

-- The detail window was written for drop records. A rolled entry hands its
-- own straight over; an awarded one has no roll list to show, so this builds
-- the shape that window expects and leaves the rolls empty rather than
-- inventing any.
function LootFeed.ToDetailRecord(entry)
    if not entry then
        return nil
    end

    if entry.drop then
        return entry.drop
    end

    return {
        id = entry.id,
        itemLink = entry.itemLink,
        itemName = entry.itemName,

        encounterName = entry.typeLabel,
        instanceName = entry.where,

        winnerName = entry.player,
        winnerRoll = nil,

        timestamp = entry.timestamp,

        -- Empty rather than absent: the window counts it, and "0 eligible
        -- players" is the honest answer for something nobody rolled on.
        rolls = {},

        awarded = true,
    }
end

function LootFeed.CountByType(entries)
    local counts = {}

    for _, entry in ipairs(entries or {}) do
        counts[entry.typeKey] = (counts[entry.typeKey] or 0) + 1
    end

    return counts
end
