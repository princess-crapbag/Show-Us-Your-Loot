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
--
-- ALTS: every key is put through Players.ResolveToMain, so a raider who
-- brings a different character still has one drought. That fold creates a
-- case this file has to handle on its own — somebody who raids on a main and
-- an alt the same night is present once, not twice — because counting the
-- night twice would push them down the list for turning up more.

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
                    local key = SYL.Players.ResolveToMain(
                        roll.guid or roll.name
                    )

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
                local key = SYL.Players.ResolveToMain(
                    drop.winnerGUID or drop.winnerName
                )

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

-- The roster entry names whichever character turned up. Once alts are folded
-- the list has to show the person, so identity comes from the registry when
-- it knows them and falls back to the character as recorded.
local function Identify(member, key)
    local player = SYL.Players.Get(key)

    if not player then
        return member
    end

    return {
        guid = player.guid or member.guid,
        name = player.name or member.name,
        class = player.class or member.class,
    }
end

-- Gear that arrived without a roll counts too, when the setting allows it.
--
-- The due list reads roll history, and in current retail a large share of
-- gearing never touches a roll: the vault, a Mythic+ chest, a catalyst
-- conversion. Somebody taking a mythic-track vault item every week appeared
-- here as though they had received nothing, which is not a small error in a
-- list whose only job is to say who has gone without.
--
-- PersonalLoot subtracts the overlap first, because a group-loot win also
-- prints a chat loot line and counting both would double every raid drop.
local function MergePersonalLoot(lastUpgrade, lootRecords, drops)
    if not ShowUsYourLootDB
        or not ShowUsYourLootDB.settings
        or not ShowUsYourLootDB.settings.countPersonalLoot
    then
        return lastUpgrade, 0
    end

    local entries, pending = SYL.PersonalLoot.Build(lootRecords, drops)
    local last = SYL.PersonalLoot.LastByPlayer(entries)

    for key, at in pairs(last) do
        if not lastUpgrade[key] or at > lastUpgrade[key] then
            lastUpgrade[key] = at
        end
    end

    return lastUpgrade, pending
end

-- Sessions and drops are passed in so a caller can scope this to one season.
function DueList.Build(drops, sessions, lootRecords)
    local lastUpgrade = LastUpgradeByPlayer(drops)
    local byKey, order = {}, {}

    local pendingItems

    lastUpgrade, pendingItems =
        MergePersonalLoot(lastUpgrade, lootRecords, drops)

    DueList.pendingItems = pendingItems

    -- Dungeons are not raid nights. A Mythic+ run used to open one and put
    -- its five people in the roster, so a guild that runs keys together was
    -- being ranked partly on dungeon attendance.
    for _, session in ipairs(SYL.RaidSession.RaidsOnly(sessions)) do
        local startedAt = session.startedAt or 0

        -- One night is one night however many characters of theirs were in
        -- it. Reset per session, not per player.
        local countedTonight = {}

        for rawKey, member in pairs(session.roster or {}) do
            local key = SYL.Players.ResolveToMain(rawKey)
            local entry = byKey[key]

            if not entry then
                entry = NewEntry(Identify(member, key), key)
                byKey[key] = entry

                table.insert(order, entry)

                -- The roster is keyed by GUID, and so is the drop data, so
                -- the two line up without name matching. Chat loot carries
                -- no GUID, so personal gear is also indexed by short name
                -- and checked as a fallback.
                local byName =
                    lastUpgrade[SYL.PersonalLoot.NameKey(member.name) or ""]

                local at = lastUpgrade[key]

                if byName and (not at or byName > at) then
                    at = byName
                end

                entry.lastUpgradeAt = at
                entry.everWon = at ~= nil
            end

            if not countedTonight[key] then
                countedTonight[key] = true

                entry.nights = entry.nights + 1

                -- The night an upgrade was won is not a night without one,
                -- so the comparison is strict.
                if not entry.lastUpgradeAt
                    or startedAt > entry.lastUpgradeAt
                then
                    entry.nightsSinceUpgrade = entry.nightsSinceUpgrade + 1
                end
            end

            if not entry.lastSeenAt or startedAt > entry.lastSeenAt then
                entry.lastSeenAt = startedAt
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
