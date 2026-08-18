-- Core/RaidTeam.lua
--
-- Who is actually on the raid team, and what they play.
--
-- Guild rank cannot answer this. Officers who do not raid hold the highest
-- rank, trials who do raid hold the lowest, alts sit wherever their owner put
-- them, and every guild draws those lines differently. The only reliable
-- source is somebody saying so.
--
-- Kept on the player registry, which is account level and already the home
-- for facts about a person rather than a season — so a team survives
-- archiving, and marking an alt marks the person once the two are mapped.
--
-- Roles fill themselves in where the game already knows. Anyone seen in a
-- group has a role assigned, so that is remembered as a starting point and a
-- manual choice always beats it: the detected value is what Blizzard thinks
-- you queued as, not what your guild plans to bring you as.

local SYL = _G.ShowUsYourLoot

local RaidTeam = {}
SYL.RaidTeam = RaidTeam

RaidTeam.ROLES = { "TANK", "HEALER", "DPS" }

RaidTeam.ROLE_LABELS = {
    TANK = "Tank",
    HEALER = "Healer",
    DPS = "DPS",
}

-- UnitGroupRolesAssigned speaks DAMAGER; everything a person reads says DPS.
local DETECTED_ROLES = {
    TANK = "TANK",
    HEALER = "HEALER",
    DAMAGER = "DPS",
}

function RaidTeam.NormalizeDetectedRole(role)
    return DETECTED_ROLES[role or ""] or nil
end

-- Deliberately NOT resolved to the main.
--
-- Alt mapping exists so fairness counts a person once: one drought, one
-- attendance record. A raid team is the opposite question — you bring a
-- character, with its class, its role and its gear. Somebody's alt is not on
-- the team because their main is, and resolving here meant marking one
-- character silently marked every other character they own.
-- The registry first, then the incoming list.
--
-- An incoming raider — agreed to join, not in the guild yet — has no GUID, so
-- the registry has nothing to hold their team flag on. Their entry carries the
-- same two fields under the same names, so every function below works on one
-- without knowing the difference. See Core/IncomingRoster.lua.
local function Record(key)
    if not key then
        return nil
    end

    return SYL.Players.Get(key) or SYL.IncomingRoster.Get(key)
end

-- A received roster answers only where the local one is silent, and never the
-- other way round. An unmarked registry record is what every guild member has
-- before anybody touches anything, so it cannot be read as somebody having
-- decided this person is off the team — which is why the fallback is on the
-- nil and not on the record.
local function Shared(key)
    return SYL.SharedRoster and SYL.SharedRoster.Member(key) or nil
end

function RaidTeam.IsMember(key)
    local player = Record(key)

    if player and player.inRaidTeam then
        return true
    end

    local shared = Shared(key)

    return (shared and shared.inRaidTeam) and true or false
end

function RaidTeam.SetMember(key, isMember)
    local player = Record(key)

    if not player then
        return false
    end

    -- Stored as nil rather than false when off, so a registry of five
    -- hundred guild members does not carry five hundred false flags into
    -- SavedVariables.
    player.inRaidTeam = isMember and true or nil

    return true
end

function RaidTeam.Toggle(key)
    local isMember = RaidTeam.IsMember(key)

    RaidTeam.SetMember(key, not isMember)

    return not isMember
end

-- The chosen role, or the one the game reported if nobody has chosen.
function RaidTeam.GetRole(key)
    local player = Record(key)

    if player and player.raidRole then
        return player.raidRole, false
    end

    -- Consulted before the missing-record case below, not after it. A raider
    -- on somebody else's roster may be a character this client has never seen
    -- — a recruit who has not transferred yet is the whole reason
    -- IncomingRoster exists — and returning early on the nil would answer nil
    -- for exactly the people the shared roster was sent to describe.
    --
    -- A shared role also beats a detected one. What an officer typed is a
    -- plan; what the client detected is whatever this person last queued as,
    -- and the header above already says a chosen role wins over a detected
    -- one. That the choice arrived from somebody else does not change which of
    -- the two is a decision.
    local shared = Shared(key)

    if shared and shared.raidRole then
        return shared.raidRole, false
    end

    if not player then
        return nil, false
    end

    return player.detectedRole, true
end

function RaidTeam.SetRole(key, role)
    local player = Record(key)

    if not player then
        return false
    end

    player.raidRole = role

    return true
end

-- What this player was actually assigned, ignoring what the game guessed.
--
-- GetRole answers "what role should I show", which falls back to the detected
-- one. That is right for display and wrong for cycling: see below.
function RaidTeam.GetChosenRole(key)
    local player = Record(key)

    return player and player.raidRole or nil
end

-- Cycles Tank, Healer, DPS, then back to unset. Unset is a real state and
-- has to be reachable: it means nobody has said, which is different from
-- somebody saying DPS.
--
-- This cycles the CHOSEN role, not the displayed one, and the difference was
-- a dead button for most of a raid. It used to read GetRole, which falls back
-- to whatever the game detected. For anyone the game assigned DAMAGER that
-- returned "DPS" with nothing chosen, so the cycle jumped straight to the end
-- of the list, wrote nil, and the next read fell back to "DPS" again —
-- clicking did nothing, permanently, for four fifths of a raid group. Tanks
-- and healers worked, which is exactly why it survived being tried.
function RaidTeam.CycleRole(key)
    local current = RaidTeam.GetChosenRole(key)
    local nextRole

    if not current then
        nextRole = RaidTeam.ROLES[1]
    else
        for index, role in ipairs(RaidTeam.ROLES) do
            if role == current then
                -- nil at the end of the list is deliberate: that is unset,
                -- and it is the step that returns the row to the game's own
                -- answer.
                nextRole = RaidTeam.ROLES[index + 1]

                break
            end
        end
    end

    RaidTeam.SetRole(key, nextRole)

    return nextRole
end

-- Remembered rather than applied: this is what the game said, and a manual
-- choice outranks it.
function RaidTeam.RememberDetectedRole(key, detected)
    local role = RaidTeam.NormalizeDetectedRole(detected)

    if not role then
        return
    end

    local player = Record(key)

    if player then
        player.detectedRole = role
    end
end

function RaidTeam.Filter(roster)
    local kept = {}

    for _, entry in ipairs(roster or {}) do
        if RaidTeam.IsMember(entry.key) then
            table.insert(kept, entry)
        end
    end

    return kept
end

function RaidTeam.Count()
    local counted = {}
    local total = 0

    -- Keyed rather than tallied, because the three sources overlap: a shared
    -- roster names people this client already has marked, and counting a
    -- person twice would be invisible here and wrong on every screen that
    -- prints a team size.
    local function Add(key, isMember)
        if not isMember or not key or counted[key] then
            return
        end

        counted[key] = true
        total = total + 1
    end

    for key, player in pairs(SYL.Players.GetRegistry()) do
        Add(key, player.inRaidTeam)
    end

    -- Counted here too, or a roster made entirely of recruits reads as no
    -- team at all — and Audience.Default would fall back to the whole guild
    -- on the strength of it.
    for _, entry in ipairs(SYL.IncomingRoster.List()) do
        Add(entry.key, entry.inRaidTeam)
    end

    -- And a received roster, for the same reason again: a guildie who has
    -- marked nobody has a team of zero by every local measure, so the audience
    -- default would step past the team scope to the whole guild — on the one
    -- client the shared roster exists to serve.
    for key, member in pairs(
        SYL.SharedRoster and SYL.SharedRoster.Members() or {}
    ) do
        Add(key, member.inRaidTeam)
    end

    return total
end

-- Tanks, healers and damage, for a roster that is being checked for shape as
-- well as for buffs.
function RaidTeam.CountRoles(roster)
    local counts = { TANK = 0, HEALER = 0, DPS = 0, unset = 0 }

    for _, entry in ipairs(roster or {}) do
        local role = RaidTeam.GetRole(entry.key)

        if role and counts[role] then
            counts[role] = counts[role] + 1
        else
            counts.unset = counts.unset + 1
        end
    end

    return counts
end
