-- Core/BossStats.lua
--
-- Per-boss numbers: how often it was pulled, how often it died, and what it
-- dropped.
--
-- Two sources, deliberately kept apart. Pulls and kills come from raid
-- sessions, which record every encounter whether or not anything dropped.
-- Loot comes from drop records. A boss killed on a night nobody looted still
-- has a kill count, and a boss that dropped loot before raid sessions existed
-- still shows its drops — neither source can answer for the other.
--
-- Pure computation, recalculated on demand. Nothing here is stored.

local SYL = _G.ShowUsYourLoot

local BossStats = {}
SYL.BossStats = BossStats

local NEED_MAIN = 0
local NEED_OFF = 1

-- Bosses are keyed by encounter and difficulty together. The same boss on
-- Heroic and on Mythic is two different problems for a raid team, and folding
-- them into one row would average a farm kill with a progression wall.
local function BossKey(encounterID, name, difficultyName)
    return table.concat({
        tostring(encounterID or "?"),
        tostring(name or "Unknown"),
        tostring(difficultyName or "?"),
    }, "|")
end

local function NewBoss(key, name, instanceName, difficultyName, difficultyID)
    return {
        key = key,
        name = name or "Unknown",
        instanceName = instanceName,
        difficultyName = difficultyName,
        difficultyID = difficultyID,

        pulls = 0,
        kills = 0,

        drops = 0,
        upgrades = 0,

        firstKilledAt = nil,
        lastKilledAt = nil,
        lastDropAt = nil,

        itemCounts = {},
        items = {},
    }
end

local function Earlier(current, candidate)
    if not candidate then
        return current
    end

    if not current or candidate < current then
        return candidate
    end

    return current
end

local function Later(current, candidate)
    if not candidate then
        return current
    end

    if not current or candidate > current then
        return candidate
    end

    return current
end

local function Ensure(byKey, order, key, name, instanceName, difficultyName,
                      difficultyID)
    local boss = byKey[key]

    if not boss then
        boss = NewBoss(key, name, instanceName, difficultyName, difficultyID)
        byKey[key] = boss

        table.insert(order, boss)
    end

    -- Later records may know a name an earlier one did not.
    boss.instanceName = boss.instanceName or instanceName
    boss.difficultyName = boss.difficultyName or difficultyName
    boss.difficultyID = boss.difficultyID or difficultyID

    return boss
end

local function CountEncounters(byKey, order, sessions)
    for _, session in ipairs(sessions or {}) do
        for _, encounter in ipairs(session.encounters or {}) do
            local key = BossKey(
                encounter.encounterID, encounter.name, session.difficultyName
            )

            local boss = Ensure(
                byKey, order, key,
                encounter.name, session.instanceName, session.difficultyName,
                session.difficultyID
            )

            boss.pulls = boss.pulls + 1

            if encounter.killed then
                boss.kills = boss.kills + 1
                boss.firstKilledAt = Earlier(boss.firstKilledAt, encounter.at)
                boss.lastKilledAt = Later(boss.lastKilledAt, encounter.at)
            end
        end
    end
end

local function CountDrops(byKey, order, drops)
    for _, drop in ipairs(drops or {}) do
        if not drop.excludedFromAnalytics then
            local key = BossKey(
                drop.encounterID, drop.encounterName, drop.difficultyName
            )

            local boss = Ensure(
                byKey, order, key,
                drop.encounterName, drop.instanceName, drop.difficultyName,
                drop.difficultyID
            )

            boss.drops = boss.drops + 1
            boss.lastDropAt = Later(boss.lastDropAt, drop.timestamp)

            local itemName = drop.itemName

            if itemName then
                if not boss.itemCounts[itemName] then
                    boss.itemCounts[itemName] = 0
                    table.insert(boss.items, itemName)
                end

                boss.itemCounts[itemName] = boss.itemCounts[itemName] + 1
            end

            -- Counted from the winning roll rather than from the drop, since
            -- a synced record carries a winner state but no roll list.
            local state = drop.winnerState

            if state == NEED_MAIN or state == NEED_OFF then
                boss.upgrades = boss.upgrades + 1
            end
        end
    end
end

-- Sessions and drops are passed in rather than read here, so a caller can ask
-- about one season, or about everything, without this needing to know which.
function BossStats.Build(drops, sessions)
    local byKey, order = {}, {}

    CountEncounters(byKey, order, sessions)
    CountDrops(byKey, order, drops)

    for _, boss in ipairs(order) do
        table.sort(boss.items, function(left, right)
            local leftCount = boss.itemCounts[left] or 0
            local rightCount = boss.itemCounts[right] or 0

            if leftCount ~= rightCount then
                return leftCount > rightCount
            end

            return left < right
        end)
    end

    return order
end

-- Most recently killed first, then bosses never killed but pulled, then the
-- rest. A raid leader is nearly always asking about this week.
function BossStats.SortByRecent(bosses)
    table.sort(bosses, function(left, right)
        local leftAt = left.lastKilledAt or left.lastDropAt or 0
        local rightAt = right.lastKilledAt or right.lastDropAt or 0

        if leftAt ~= rightAt then
            return leftAt > rightAt
        end

        return (left.name or "") < (right.name or "")
    end)

    return bosses
end

function BossStats.KillRate(boss)
    if not boss or (boss.pulls or 0) == 0 then
        return nil
    end

    return (boss.kills or 0) / boss.pulls
end
