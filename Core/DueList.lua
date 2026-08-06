-- Core/DueList.lua
--
-- Who has gone longest without an upgrade, measured in raid nights they were
-- actually present for.
--
-- THE JUDGEMENT CALL, stated plainly because it decides every number here:
-- only a Need or an offspec win resets someone's clock. A transmog or greed
-- win does not. Someone who has won six mog pieces and no gear has been
-- unlucky with gear, and folding those together would hide exactly the case
-- this list exists to surface.
--
-- The second call: drought is counted in *nights attended*, not in days
-- elapsed and not in items rolled on. A raider who missed three weeks has not
-- accrued a claim on loot while away, and a player eligible for forty drops in
-- one night is not owed more than someone eligible for three — they had the
-- same one night of bad luck.
--
-- Both are opinions rather than facts. They are in one file, and the ranking
-- is a single comparable number rather than a weighted score, so disagreeing
-- means changing one rule here instead of retuning constants.

local SYL = _G.ShowUsYourLoot

local DueList = {}
SYL.DueList = DueList

local NEED_MAIN = 0
local NEED_OFF = 1

local function IsUpgrade(state)
    return state == NEED_MAIN or state == NEED_OFF
end

-- When each player last won something that counts as gear.
local function LastUpgradeByPlayer(drops)
    local lastUpgrade = {}

    for _, drop in ipairs(drops or {}) do
        if not drop.excludedFromAnalytics then
            -- Prefer the roll list, which names the winner and their state
            -- together. Synced records have no roll list, so fall back to the
            -- header the sync does carry.
            local counted = false

            for _, roll in ipairs(drop.rolls or {}) do
                if roll.isWinner and IsUpgrade(roll.state) then
                    local key = roll.guid or roll.name

                    if key then
                        local at = drop.timestamp or 0

                        if not lastUpgrade[key] or at > lastUpgrade[key] then
                            lastUpgrade[key] = at
                        end
                    end

                    counted = true
                end
            end

            if not counted and IsUpgrade(drop.winnerState) then
                local key = drop.winnerGUID or drop.winnerName

                if key then
                    local at = drop.timestamp or 0

                    if not lastUpgrade[key] or at > lastUpgrade[key] then
                        lastUpgrade[key] = at
                    end
                end
            end
        end
    end

    return lastUpgrade
end

local function NewEntry(member, key)
    return {
        key = key,
        guid = member.guid,
        name = member.name,
        class = member.class,

        nights = 0,
        nightsSinceUpgrade = 0,

        lastUpgradeAt = nil,
        lastSeenAt = nil,

        everWon = false,
    }
end

-- Sessions and drops are passed in so a caller can scope this to one season.
function DueList.Build(drops, sessions)
    local lastUpgrade = LastUpgradeByPlayer(drops)
    local byKey, order = {}, {}

    for _, session in ipairs(sessions or {}) do
        local startedAt = session.startedAt or 0

        for key, member in pairs(session.roster or {}) do
            local entry = byKey[key]

            if not entry then
                entry = NewEntry(member, key)
                byKey[key] = entry

                table.insert(order, entry)

                -- The roster is keyed by GUID, and so is the loot data, so
                -- the two line up without name matching.
                entry.lastUpgradeAt = lastUpgrade[key]
                entry.everWon = lastUpgrade[key] ~= nil
            end

            entry.nights = entry.nights + 1

            if not entry.lastSeenAt or startedAt > entry.lastSeenAt then
                entry.lastSeenAt = startedAt
            end

            -- The night an upgrade was won is not a night without one, so the
            -- comparison is strict.
            if not entry.lastUpgradeAt or startedAt > entry.lastUpgradeAt then
                entry.nightsSinceUpgrade = entry.nightsSinceUpgrade + 1
            end
        end
    end

    return order
end

-- Longest drought first. Ties break towards the player who has raided more,
-- because two people with three dry nights are not equal if one of them has
-- been there all tier.
function DueList.Sort(entries)
    table.sort(entries, function(left, right)
        if left.nightsSinceUpgrade ~= right.nightsSinceUpgrade then
            return left.nightsSinceUpgrade > right.nightsSinceUpgrade
        end

        if left.nights ~= right.nights then
            return left.nights > right.nights
        end

        return (left.name or "") < (right.name or "")
    end)

    return entries
end

-- Someone who has not raided recently is not "due" in any useful sense, and
-- leaving them at the top of the list is how the list stops being read.
function DueList.FilterRecent(entries, sessions, withinNights)
    withinNights = withinNights or 3

    local recent = {}

    for _, session in ipairs(sessions or {}) do
        table.insert(recent, session.startedAt or 0)
    end

    table.sort(recent, function(left, right) return left > right end)

    local cutoff = recent[withinNights] or recent[#recent] or 0
    local kept = {}

    for _, entry in ipairs(entries) do
        if (entry.lastSeenAt or 0) >= cutoff then
            table.insert(kept, entry)
        end
    end

    return kept
end

function DueList.Describe(entry)
    if not entry.everWon then
        if entry.nights == 1 then
            return "1 night, no upgrade yet"
        end

        return entry.nights .. " nights, no upgrade yet"
    end

    if entry.nightsSinceUpgrade == 0 then
        return "won an upgrade tonight"
    end

    if entry.nightsSinceUpgrade == 1 then
        return "1 night since last upgrade"
    end

    return entry.nightsSinceUpgrade .. " nights since last upgrade"
end
