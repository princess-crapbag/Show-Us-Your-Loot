-- Core/TierProgress.lua
--
-- How far the guild is through the tier, on ONE difficulty, and the week it
-- first killed each boss.
--
-- WHY IT IS ITS OWN FILE. The dashboard tile used to count every boss on
-- every difficulty into one number, which is how Aimee's guild read "22 of 23
-- killed" while being 6/8 Heroic in one raid and 1/1 Heroic in the other. Her
-- 22 is eight Normal plus six Heroic plus six LFR in The Venomous Abyss, one
-- Normal and one Heroic in The Tidebound Grotto. Every one of those is a real
-- kill and adding them together describes nothing anybody says out loud.
--
-- Aimee: "there are 8 bosses in one raid and 1 boss in the other, plus there
-- is LFR, Normal, Heroic, Mythic. different guild prog on different
-- difficulties. id like to be able to choose which difficulty that section
-- shows. for us it would be heroic. so were 1/1H in TG and 6/8H in VA."
--
-- NOTHING NEW IS RECORDED FOR THIS. Every raid night already stores its
-- encounters with `killed`, the boss name, an encounter id, a difficulty and
-- a timestamp per pull -- see Core/RaidSession.lua. So the first kill of each
-- boss on every difficulty this guild has ever set foot in is already sitting
-- in the database, on all four difficulties, waiting to be asked for. This
-- file asks.
--
-- THE WEEK IS THE POINT, not the date. Aimee: "everything resets on a tuesday
-- in wow. so 08/18 was week one, 08/25 was week 2, 09/01 was week 3. i think
-- it would be nice to see later what week we first killed which boss." A date
-- answers "when"; the week answers "how long did that take us", which is the
-- question anybody actually asks about progression a tier later.
--
-- HOW MANY BOSSES A RAID HAS is not something an addon is told. The client
-- has no call for "how many encounters are in this instance" outside the
-- Encounter Journal, which is not loaded and cannot be relied on. So the
-- total is the highest number of DISTINCT bosses this guild has seen in that
-- instance on any difficulty -- eight for The Venomous Abyss, because they
-- have cleared eight of them on Normal. That is right for the case that
-- matters and honest about being a floor: it can read low early in a tier and
-- never reads high, and Describe says "of 8 seen" rather than claiming the
-- raid has exactly eight.

local SYL = _G.ShowUsYourLoot

local TierProgress = {}
SYL.TierProgress = TierProgress

-- The four a guild talks about. Stored by id rather than by name because the
-- name is localized and the id is not.
TierProgress.DIFFICULTIES = {
    { id = 17, short = "LFR", label = "Looking For Raid" },
    { id = 14, short = "Normal", label = "Normal" },
    { id = 15, short = "Heroic", label = "Heroic" },
    { id = 16, short = "Mythic", label = "Mythic" },
}

TierProgress.DEFAULT_DIFFICULTY = 15

local function Settings()
    return ShowUsYourLootDB and ShowUsYourLootDB.settings
end

function TierProgress.GetDifficulty()
    local settings = Settings()
    local saved = settings and settings.tierDifficulty

    for _, entry in ipairs(TierProgress.DIFFICULTIES) do
        if entry.id == saved then
            return saved
        end
    end

    return TierProgress.DEFAULT_DIFFICULTY
end

function TierProgress.SetDifficulty(id)
    local settings = Settings()

    if not settings then
        return false
    end

    for _, entry in ipairs(TierProgress.DIFFICULTIES) do
        if entry.id == id then
            settings.tierDifficulty = id

            return true
        end
    end

    return false
end

function TierProgress.Label(id)
    for _, entry in ipairs(TierProgress.DIFFICULTIES) do
        if entry.id == (id or TierProgress.GetDifficulty()) then
            return entry.short
        end
    end

    return "Heroic"
end

-- Cycles, the way every other chooser in this addon does. Four values is one
-- press each rather than a menu.
function TierProgress.NextDifficulty(id)
    id = id or TierProgress.GetDifficulty()

    for index, entry in ipairs(TierProgress.DIFFICULTIES) do
        if entry.id == id then
            local following = TierProgress.DIFFICULTIES[
                (index % #TierProgress.DIFFICULTIES) + 1
            ]

            return following.id
        end
    end

    return TierProgress.DEFAULT_DIFFICULTY
end

--------------------------------------------------------------------------
-- Weeks
--------------------------------------------------------------------------

local DAY = 86400
local WEEK = DAY * 7

-- The most recent Tuesday reset at or before a timestamp.
--
-- Tuesday because that is when the US region resets, which is where this
-- guild plays. Reading it off the client is not possible for a PAST week --
-- C_DateAndTime.GetSecondsUntilWeeklyReset answers about now -- so the week
-- boundary is computed from the date, and the season's own first night
-- anchors week one.
--
-- date("*t") is used rather than arithmetic on the epoch because the answer
-- has to be in the player's own time zone: a kill at 20:00 local on Monday is
-- in the week that began the Tuesday before, whatever UTC says.
function TierProgress.WeekStart(timestamp)
    if type(timestamp) ~= "number" then
        return nil
    end

    local parts = date("*t", timestamp)

    -- date("*t").wday is 1 for Sunday, so Tuesday is 3.
    local since = (parts.wday - 3) % 7

    -- Back to midnight, then back to the Tuesday.
    return timestamp
        - (parts.hour * 3600 + parts.min * 60 + parts.sec)
        - since * DAY
end

-- Which week of the season a timestamp falls in, counting from one.
--
-- The season's anchor is the first raid night rather than createdAt: somebody
-- who installs the addon on a Thursday would otherwise have their season
-- start mid-week and every week number would be off by the remainder.
function TierProgress.WeekOf(timestamp, seasonStart)
    if not timestamp or not seasonStart then
        return nil
    end

    local first = TierProgress.WeekStart(seasonStart)
    local this = TierProgress.WeekStart(timestamp)

    if not first or not this then
        return nil
    end

    return math.floor((this - first) / WEEK) + 1
end

--------------------------------------------------------------------------
-- Reading the nights
--------------------------------------------------------------------------

-- The earliest raid night in the season, which anchors week one.
function TierProgress.SeasonStart(sessions)
    local earliest

    for _, session in ipairs(sessions or {}) do
        local at = session.startedAt or session.enteredAt

        if at and (not earliest or at < earliest) then
            earliest = at
        end
    end

    return earliest
end

-- Every first kill on one difficulty, keyed by instance.
--
-- Returns a list of instances, each with its bosses in the order they first
-- died, plus how many distinct bosses this guild has ever seen in there on
-- ANY difficulty -- which is the closest thing to "how many bosses the raid
-- has" that a client can answer. See the header.
function TierProgress.Build(sessions, difficultyID)
    difficultyID = difficultyID or TierProgress.GetDifficulty()

    local seasonStart = TierProgress.SeasonStart(sessions)

    local instances = {}
    local order = {}
    local seenAnywhere = {}

    local function Instance(name)
        if not instances[name] then
            instances[name] = { name = name, kills = {}, killOrder = {} }

            table.insert(order, instances[name])
        end

        return instances[name]
    end

    for _, session in ipairs(sessions or {}) do
        local instanceName = session.instanceName

        if instanceName then
            local entry = Instance(instanceName)

            for _, encounter in ipairs(session.encounters or {}) do
                local difficulty = encounter.difficultyID
                    or session.difficultyID
                local name = encounter.name

                if encounter.killed and name then
                    -- Counted on every difficulty, which is what makes the
                    -- total mean anything: a guild pushing Heroic has usually
                    -- cleared Normal, and that is where the boss count comes
                    -- from before they finish.
                    seenAnywhere[instanceName] = seenAnywhere[instanceName]
                        or {}

                    if not seenAnywhere[instanceName][name] then
                        seenAnywhere[instanceName][name] = true
                        entry.seen = (entry.seen or 0) + 1
                    end

                    if difficulty == difficultyID then
                        local at = encounter.at or session.startedAt

                        local existing = entry.kills[name]

                        if not existing or (at or 0) < existing.at then
                            if not existing then
                                table.insert(entry.killOrder, name)
                            end

                            entry.kills[name] = {
                                name = name,
                                at = at,
                                week = TierProgress.WeekOf(at, seasonStart),
                                encounterID = encounter.encounterID,
                            }
                        end
                    end
                end
            end
        end
    end

    local result = {}

    for _, entry in ipairs(order) do
        local killed = {}

        for _, name in ipairs(entry.killOrder) do
            table.insert(killed, entry.kills[name])
        end

        -- Oldest first, which is the order a progression list is read in.
        table.sort(killed, function(left, right)
            return (left.at or 0) < (right.at or 0)
        end)

        -- Instances this guild has never entered on this difficulty are left
        -- out entirely rather than listed at 0 of 8. A raid you have not
        -- opened yet is not progress you are behind on.
        if #killed > 0 then
            table.insert(result, {
                name = entry.name,
                killed = #killed,
                seen = math.max(entry.seen or 0, #killed),
                kills = killed,
            })
        end
    end

    -- The raid with the most left to do leads, since that is the one being
    -- pushed. Ties fall back to the name so the order does not wander.
    table.sort(result, function(left, right)
        local leftLeft = left.seen - left.killed
        local rightLeft = right.seen - right.killed

        if leftLeft ~= rightLeft then
            return leftLeft > rightLeft
        end

        return left.name < right.name
    end)

    return result
end

-- Every first kill across every instance, newest first. What the tile shows,
-- and what the Bosses tab lists in full.
function TierProgress.Recent(instances)
    local all = {}

    for _, instance in ipairs(instances or {}) do
        for _, kill in ipairs(instance.kills) do
            table.insert(all, {
                name = kill.name,
                at = kill.at,
                week = kill.week,
                instanceName = instance.name,
            })
        end
    end

    table.sort(all, function(left, right)
        return (left.at or 0) > (right.at or 0)
    end)

    return all
end

-- "6 of 8 seen" rather than "6 of 8". See the header: the total is a floor
-- taken from what this guild has actually met, not a fact about the raid.
function TierProgress.Describe(instance)
    if not instance then
        return ""
    end

    return instance.killed .. "/" .. instance.seen
end

function TierProgress.Totals(instances)
    local killed, seen = 0, 0

    for _, instance in ipairs(instances or {}) do
        killed = killed + instance.killed
        seen = seen + instance.seen
    end

    return killed, seen
end
