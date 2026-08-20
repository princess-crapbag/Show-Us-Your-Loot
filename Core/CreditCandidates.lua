-- Core/CreditCandidates.lua
--
-- Who a drop could reasonably be credited to.
--
-- THE ROLL LIST CANNOT BE THE CANDIDATE LIST, and Aimee's own data is the
-- proof. On the 2026-08-18 guild night every one of the eleven raiders passed
-- on eight of the eleven drops and she took them on a Transmog roll — because
-- under a loot council the group-loot roll is a formality that funnels the
-- item to the master looter. A picker built from the people who rolled would
-- have offered exactly one name: hers.
--
-- So the raid session's roster comes first: the people who were actually
-- standing there. The roll list is the fallback for a drop with no session —
-- a synced record, or one captured before sessions were stored.
--
-- No frames here on purpose. UI/CreditPicker.lua draws whatever this returns,
-- and the rule is worth being able to test without a client.

local SYL = _G.ShowUsYourLoot

local CreditCandidates = {}
SYL.CreditCandidates = CreditCandidates

-- A drop belongs to the last session that had started when it dropped.
-- Matching on the date instead would split a raid that runs past midnight,
-- which is the trap Core/NightIndex.lua already names.
local SESSION_WINDOW = 12 * 60 * 60

function CreditCandidates.SessionFor(record)
    if not record then
        return nil
    end

    local at = record.timestamp or 0
    local best

    for _, session in ipairs(SYL.GetActiveRaids() or {}) do
        local startedAt = session.startedAt or 0

        if startedAt <= at
            and at - startedAt <= SESSION_WINDOW
            and (not best or startedAt > (best.startedAt or 0))
        then
            best = session
        end
    end

    return best
end

local function ByName(left, right)
    return tostring(left.name or "") < tostring(right.name or "")
end

-- Deduplicated on GUID where there is one and on name where there is not,
-- because the same person can appear in the session roster and the roll list
-- and offering them twice makes the picker look broken.
function CreditCandidates.Build(record)
    if not record then
        return {}
    end

    local list, seen = {}, {}

    local function Add(guid, name, class)
        local key = guid or name

        if not key or not name or name == "" or seen[key] then
            return
        end

        seen[key] = true

        table.insert(list, { guid = guid, name = name, class = class })
    end

    local session = CreditCandidates.SessionFor(record)

    if session then
        for _, member in pairs(session.roster or {}) do
            Add(member.guid, member.name, member.class)
        end
    end

    for _, roll in ipairs(record.rolls or {}) do
        Add(roll.guid, roll.name, roll.class)
    end

    -- The winner is always offerable, so that undoing a correction by hand
    -- stays possible even when the session roster has been trimmed.
    Add(record.winnerGUID, record.winnerName, record.winnerClass)

    table.sort(list, ByName)

    return list
end

-- Name search, case-insensitive and plain rather than pattern-matched: a
-- realm name with a hyphen in it is not a character class.
function CreditCandidates.Filter(candidates, search)
    local wanted = tostring(search or ""):lower()

    if wanted == "" then
        return candidates
    end

    local matched = {}

    for _, candidate in ipairs(candidates or {}) do
        if tostring(candidate.name):lower():find(wanted, 1, true) then
            table.insert(matched, candidate)
        end
    end

    return matched
end
