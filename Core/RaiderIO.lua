-- Core/RaiderIO.lua
--
-- Reads Mythic+ score and raid progress from the Raider.IO addon, when it is
-- installed.
--
-- Guild.lua states the constraint this works around: addons have no network
-- access, so raider.io itself is unreachable from in game. What *is*
-- reachable is the Raider.IO addon, which ships a static data bundle and
-- exposes it to other addons. 442M downloads makes it a safe thing to look
-- for and an unsafe thing to require.
--
-- SOFT DEPENDENCY, ALWAYS. Every call is guarded and wrapped, and every
-- return path has an answer for "it is not there". A player without the
-- addon sees columns that are blank, never an error.
--
-- THE STALENESS THAT MATTERS: their bundle is refreshed on their release
-- cadence, not live. A score read here can be days old and a character who
-- transferred or renamed may be missing entirely. Fine for "who is this
-- raider", wrong for anything that has to be current, so nothing in the
-- fairness math is allowed to depend on it.

local SYL = _G.ShowUsYourLoot

local RIO = {}
SYL.RaiderIO = RIO

local warned = false

function RIO.IsAvailable()
    local addon = _G.RaiderIO

    return type(addon) == "table"
        and type(addon.GetProfile) == "function"
end

-- Called once from a report rather than on every row, so a guild that does
-- not run Raider.IO is told why the column is empty exactly one time.
function RIO.WarnIfMissing()
    if RIO.IsAvailable() or warned then
        return false
    end

    warned = true

    SYL:DebugPrint(
        "Raider.IO is not installed, so scores and progress are blank."
    )

    return true
end

local function SplitName(name, realm)
    if realm and realm ~= "" then
        return name, realm
    end

    if type(name) ~= "string" then
        return nil, nil
    end

    local short, fromName = name:match("^([^-]+)%-(.+)$")

    if short then
        return short, fromName
    end

    -- No realm anywhere. Raider.IO needs one, and the player's own realm is
    -- the only reasonable guess: roll lists drop the realm precisely when
    -- everyone is on it.
    local _, playerRealm = UnitFullName("player")

    return name, playerRealm
end

-- Returns nil rather than erroring for every failure mode: addon absent,
-- character unknown to their bundle, or their API having changed shape
-- under us. pcall is not paranoia here — this is another author's code
-- running inside our call stack, and it updates on their schedule.
function RIO.GetProfile(name, realm)
    if not RIO.IsAvailable() then
        return nil
    end

    local shortName, resolvedRealm = SplitName(name, realm)

    if not shortName or not resolvedRealm then
        return nil
    end

    local ok, profile = pcall(
        _G.RaiderIO.GetProfile, shortName, resolvedRealm
    )

    if not ok or type(profile) ~= "table" then
        return nil
    end

    return profile
end

-- Flattened to the handful of fields worth showing, so the rest of the addon
-- never reaches into their table shape directly. If they change it, this
-- function is the only thing that breaks.
function RIO.GetSummary(name, realm)
    local profile = RIO.GetProfile(name, realm)

    if not profile then
        return nil
    end

    local summary = {
        name = profile.name,
        realm = profile.realm,
        fetchedAt = time(),
    }

    local keystone = profile.mythicKeystoneProfile

    if type(keystone) == "table" then
        summary.score = tonumber(keystone.currentScore)
        summary.previousScore = tonumber(keystone.previousScore)
        summary.mainScore = tonumber(keystone.mainCurrentScore)
    end

    local raid = profile.raidProfile

    if type(raid) == "table" then
        -- Their raid shape has moved around more than the keystone one, so
        -- this takes whichever readable summary exists and stores it as
        -- text rather than trying to model it.
        summary.raidProgress =
            type(raid.progress) == "string" and raid.progress
            or type(raid.summary) == "string" and raid.summary
            or nil
    end

    local recruitment = profile.recruitmentProfile

    if type(recruitment) == "table" then
        summary.recruiting = recruitment.isRecruiting and true or nil
    end

    return summary
end

-- Colors come from Raider.IO when it is there, so a score reads the same
-- here as it does everywhere else the player sees one. The fallback is the
-- addon's own highlight rather than an invented scale: inventing one would
-- imply a threshold this addon has no business asserting.
function RIO.GetScoreColor(score)
    if not score or score <= 0 then
        return 0.6, 0.6, 0.6
    end

    local addon = _G.RaiderIO

    if type(addon) == "table"
        and type(addon.GetScoreColor) == "function"
    then
        local ok, red, green, blue = pcall(addon.GetScoreColor, score)

        if ok and type(red) == "number" then
            return red, green, blue
        end
    end

    return 1, 0.82, 0
end

-- Cached onto the player registry so a list of 25 rows does not call into
-- another addon 25 times per refresh. Their data only changes when they
-- push a build, so a long cache costs nothing.
local CACHE_SECONDS = 1800

function RIO.GetCached(key, name, realm)
    local player = SYL.Players.Get(key)

    if not player then
        return RIO.GetSummary(name, realm)
    end

    local cached = player.raiderIO

    if cached and cached.fetchedAt
        and (time() - cached.fetchedAt) < CACHE_SECONDS
    then
        -- An earlier miss is cached too, so an unknown character is not
        -- looked up again on every single refresh.
        if cached.missing then
            return nil
        end

        return cached
    end

    -- fullName carries the realm and a bare name does not. Preferring it
    -- keeps a cross-realm raider from being looked up against whichever
    -- realm the officer happens to be standing on.
    local lookup = player.fullName or name or player.name

    local summary = RIO.GetSummary(lookup, realm)

    player.raiderIO = summary or { missing = true, fetchedAt = time() }

    return summary
end

-- Stamps mplusScore onto a list of Analytics entries in place.
--
-- Lives here rather than in the window that draws it so the reach into
-- another addon stays in one file, and out of Analytics, which is
-- deliberately pure computation over the records. Callers apply this before
-- sorting, so the column can be sorted by like any other.
function RIO.AttachScores(entries)
    if not RIO.IsAvailable() then
        return entries
    end

    for _, entry in ipairs(entries or {}) do
        local summary = RIO.GetCached(entry.key, entry.name)

        entry.mplusScore = summary and summary.score or nil
    end

    return entries
end
