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

-- The rule stated at the top of this file — only Need and offspec reset a
-- clock — now lives with the roll states themselves, so the type column and
-- the boss stats answer it identically instead of each keeping their own copy
-- of Blizzard's numbering.
local IsUpgrade = SYL.LootHistoryAPI.IsUpgradeState

-- Whether a win from this drop is allowed to reset somebody's clock.
--
-- THE SUM HAD THE EXCLUSION ON ONE SIDE ONLY, and it silently wiped
-- droughts. Nights come from RaidSession.RaidsOnly, which drops Timewalking
-- raids, Story mode, Timewalking LFR, Event and Follower difficulties — see
-- NOT_A_RAID_NIGHT in Core/Utilities.lua. Upgrades came from every drop ever
-- recorded, with no such test.
--
-- So a Timewalking raid — group loot, real Need rolls, epic gear, and
-- explicitly not a raid night — set lastUpgradeAt to that evening for
-- everyone who won. The comparison below is `startedAt > lastUpgradeAt`, so
-- every genuine raid night before it then stopped counting, and a raider who
-- had gone two months without an upgrade showed zero dry nights on the
-- strength of a Timewalking win. The list exists to surface exactly that
-- person, and this hid them.
--
-- The rule is now the same on both sides: an upgrade resets your clock only
-- if it came from content that would have counted as a night.
-- A BoE is not what the drought is measuring.
--
-- Aimee's rule, in her words: "boes received does not change the raid
-- drought". Winning a BoE is winning something sellable, and resetting a
-- clock for it pushes a genuinely starved raider down the list.
--
-- Unknown counts as not-BoE — see Utilities.IsBindOnEquip. An uncached item
-- answers nil, and reading that as "yes" would silently stop counting real
-- upgrades in a way indistinguishable from the maths being broken.
local function IsBindOnEquipWin(drop)
    return SYL.Utilities.IsBindOnEquip(drop.itemLink) == true
end

local function CountsTowardsDrought(drop)
    if IsBindOnEquipWin(drop) then
        return false
    end

    -- Records written before the location was stored carry neither field.
    -- Treating unknown as "not a raid" would erase the upgrade history of
    -- everything captured before that, so unknown counts. The drops list is
    -- group loot only and retail dungeons award personal loot, so nothing
    -- much else can be in there anyway.
    if not drop.instanceType and not drop.difficultyID then
        return true
    end

    return SYL.Utilities.IsRaidContent(
        drop.instanceType, drop.difficultyID
    )
end

-- When each player last won something that counts as gear.
local function LastUpgradeByPlayer(drops)
    local lastUpgrade = {}

    for _, drop in ipairs(drops or {}) do
        if not drop.excludedFromAnalytics and CountsTowardsDrought(drop) then
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

-- PERSONAL LOOT NEVER RESETS A RAID DROUGHT, and there is no longer a setting
-- for it.
--
-- Aimee's rule, and it is stricter than the one this file used to implement:
-- "the due option is only for loot received in our guilds raids... also
-- personal loot in raid and boes received does not change the raid drought
-- either." So the vault, a Mythic+ chest, a catalyst conversion and a
-- personal-loot item handed out mid-raid are all outside it.
--
-- This used to merge PersonalLoot into the upgrade times whenever
-- countPersonalLoot was on. That setting is gone rather than defaulted off:
-- it only ever fed this calculation, and a switch that no longer changes any
-- number is worse than no switch. Chat loot is still captured, still on the
-- loot list, still exported — "i do want to know about other loot received"
-- — it simply has no bearing on who is due.
--
-- What is left is a definition small enough to state in one line: a drought
-- is reset by a Need or offspec win, on a bind-on-pickup item, from group
-- loot, on a night that counted as a raid night.

-- Sessions and drops are passed in so a caller can scope this to one season.
--
-- Chat loot is no longer an argument. It fed the personal-loot merge and
-- nothing else, and that is gone; callers passing a third value are simply
-- ignored rather than broken.
function DueList.Build(drops, sessions)
    local lastUpgrade = LastUpgradeByPlayer(drops)
    local byKey, order = {}, {}

    -- Dungeons are not raid nights. A Mythic+ run used to open one and put
    -- its five people in the roster, so a guild that runs keys together was
    -- being ranked partly on dungeon attendance.
    -- One night is one night however many characters of theirs were in it,
    -- and however many difficulties the night passed through. Keyed by night
    -- rather than reset per session: a Heroic clear followed by Mythic pulls
    -- is two sessions, and counting both moved nightsSinceUpgrade — the only
    -- key this list ranks on — twice as fast for everyone who stayed for
    -- both. See RaidSession.NightKey.
    local countedOn = {}

    for _, session in ipairs(SYL.RaidSession.RaidsOnly(sessions)) do
        local startedAt = session.startedAt or 0
        local nightKey = SYL.RaidSession.NightKey(session)

        countedOn[nightKey] = countedOn[nightKey] or {}

        local countedTonight = countedOn[nightKey]

        for rawKey, member in pairs(session.roster or {}) do
            local key = SYL.Players.ResolveToMain(rawKey)
            local entry = byKey[key]

            if not entry then
                entry = NewEntry(Identify(member, key), key)
                byKey[key] = entry

                table.insert(order, entry)

                -- The roster is keyed by GUID and so is the drop data, so
                -- the two line up without name matching. The short-name
                -- fallback that used to sit here existed only for chat loot,
                -- which carries no GUID — with personal loot out of this
                -- calculation there is nothing left for it to match.
                local at = lastUpgrade[key]

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

    -- Raids only, the same as Build. lastSeenAt can only ever hold a raid
    -- night, so a cutoff computed from dungeon sessions too is measured
    -- against a clock nothing on this list runs on: three keys after raid
    -- pushed the cutoff past the last raid and emptied the whole list.
    --
    -- One entry per night for the same reason, or a guild that runs Heroic
    -- and Mythic every Tuesday reaches "the last three nights" in a night and
    -- a half, and everybody who missed this week vanishes off the list.
    local earliest = {}

    for _, session in ipairs(SYL.RaidSession.RaidsOnly(sessions)) do
        local key = SYL.RaidSession.NightKey(session)
        local startedAt = session.startedAt or 0

        -- The night's own start, so somebody recorded in its later half is
        -- still inside the cutoff that night sets.
        if key and (not earliest[key] or startedAt < earliest[key]) then
            earliest[key] = startedAt
        end
    end

    for _, startedAt in pairs(earliest) do
        table.insert(recent, startedAt)
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
