-- Core/RaidSummary.lua
--
-- The end of night report: what was killed, what dropped, and how many people
-- went home with nothing.
--
-- Separate from RaidSession because recording a night and describing one are
-- different jobs, and the recording half was already at the size limit.
--
-- There is no "raid is over" event in the game. Leaving the instance is the
-- closest honest signal, so that is what triggers this, guarded so a night
-- reports once rather than on every zone change.

local SYL = _G.ShowUsYourLoot

local RaidSummary = {}
SYL.RaidSummary = RaidSummary

local API = SYL.LootHistoryAPI

-- Drops carry no session id — they predate sessions entirely — so a night
-- claims the drops that fall inside its own span. The tail allowance covers
-- loot that lands moments after the last boss dies.
local TAIL_SECONDS = 300

local function DropsDuring(session)
    local matched = {}

    local from = session.startedAt or 0
    local upTo = (session.endedAt or 0) + TAIL_SECONDS

    for _, drop in ipairs(SYL.GetAllDrops()) do
        local at = drop.timestamp or 0

        if at >= from and at <= upTo then
            table.insert(matched, drop)
        end
    end

    return matched
end

-- Returns lines rather than printing them, so the same summary can go to chat
-- now and into a window later without being rebuilt.
function RaidSummary.Build(session)
    if not session then
        return nil
    end

    local kills = SYL.RaidSession.GetKillCount(session)
    local pulls = #(session.encounters or {})
    local minutes = SYL.RaidSession.GetDurationMinutes(session)
    local drops = DropsDuring(session)

    local upgrades, other = 0, 0
    local wonBy = {}

    for _, drop in ipairs(drops) do
        local key = drop.winnerGUID or drop.winnerName

        if API.IsUpgradeState(drop.winnerState) then
            upgrades = upgrades + 1

            if key then
                wonBy[key] = true
            end
        elseif not drop.allPassed then
            other = other + 1
        end
    end

    -- Everyone present who did not win an upgrade. This is the number a raid
    -- leader gets asked about the next day.
    --
    -- SCOPED, because the line under it points at /syl due, which is scoped —
    -- unscoped here meant the summary said nine and the ranked list showed
    -- three, with nothing on either screen explaining the gap. The scope is
    -- named in the line rather than applied silently: the total is still a
    -- true count of who was in the raid, and this is a subset of it.
    local scope = SYL.Audience.Get()
    local emptyHanded = 0

    for key, entry in pairs(session.roster or {}) do
        local inScope = SYL.Audience.Includes(
            scope, key, entry and entry.guid, entry and entry.fullName
        )

        if inScope and not wonBy[key] then
            emptyHanded = emptyHanded + 1
        end
    end

    local lines = {}

    table.insert(lines, string.format(
        "%s%s — %dh %02dm, %d of %d pulls killed",
        tostring(session.instanceName or "Unknown"),
        session.difficultyName and (" (" .. session.difficultyName .. ")") or "",
        math.floor(minutes / 60), minutes % 60,
        kills, pulls
    ))

    table.insert(lines, string.format(
        "%d raiders — %d drops, %d upgrades, %d transmog or greed",
        session.rosterCount or 0, #drops, upgrades, other
    ))

    if emptyHanded > 0 then
        -- "9 recorded went home" does not read, so only the narrowing scopes
        -- name themselves. Everyone is the scope where the count already means
        -- what the sentence says.
        table.insert(lines, string.format(
            "%d%s went home without an upgrade. /syl due ranks them.",
            emptyHanded,
            scope == "everyone" and ""
                or (" " .. SYL.Audience.Subject(scope))
        ))
    end

    return lines
end

-- Reports once per night. The flag is stored on the session, so it survives
-- in SavedVariables and a relog mid-raid does not repeat the summary either.
function RaidSummary.ReportIfFinished()
    local session = SYL.RaidSession.GetCurrent()

    if not session or session.summarized then
        return false
    end

    -- Nothing was pulled, so there is no night to report.
    if #(session.encounters or {}) == 0 then
        return false
    end

    local lines = RaidSummary.Build(session)

    session.summarized = true

    SYL.RaidSession.ClearCurrent()

    SYL:Print("Raid night finished:")

    for _, line in ipairs(lines) do
        SYL:Write("  " .. line)
    end

    return true
end

-- Available on demand as well, since "what did tonight look like" gets asked
-- before anyone leaves the instance.
function RaidSummary.ReportCurrent()
    local session = SYL.RaidSession.GetCurrent()

    if not session then
        SYL:Print("No raid night in progress.")

        return false
    end

    SYL:Print("Tonight so far:")

    for _, line in ipairs(RaidSummary.Build(session)) do
        SYL:Write("  " .. line)
    end

    return true
end
