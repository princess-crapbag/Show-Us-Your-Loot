-- Core/Audience.lua
--
-- WHICH PEOPLE a window is talking about: the raid team, the guild, or
-- everyone this addon has ever seen.
--
-- Not to be confused with contentScope in the loot list, which is raid versus
-- dungeon — that is about where an item came from, this is about whose name
-- belongs on the list at all.
--
-- THE ORDER IS RAID TEAM, THEN GUILD, THEN EVERYONE, and it is a narrowing
-- rather than a ranking. Aimee's words: "i dont need to know everyone ive run
-- a key with or a pug raid with that didnt get loot. i do need to know if my
-- raid roster people didnt get loot."
--
-- That is the whole argument for the default. The due list ranks people by
-- how long they have gone without an upgrade, and the person at the top of it
-- should be somebody an officer can actually do something about. A pug from a
-- Tuesday key sits in exactly the same rows as a raider of two years, sorts
-- above them for having been seen once and won nothing, and pushes the answer
-- off the visible part of the list.
--
-- WHY THE DEFAULT IS COMPUTED RATHER THAN WRITTEN DOWN. "team" is the right
-- default only once somebody has marked a team. Before that it is a window
-- that opens empty, which reads as broken and is the fastest way to lose
-- somebody in their first five minutes. So the default falls through: team if
-- a team exists, guild if the player is in one, everyone otherwise. Each step
-- is the narrowest scope that can still show something.
--
-- The chosen scope is saved once and shared by every window that shows
-- people, so "this addon is showing me my raid team" is one fact rather than
-- a per-window setting to hunt down. Windows that exist to *build* the team —
-- the roster window — keep their own toggle, because that one is a list of
-- candidates by definition and cannot be narrowed to the team it is used to
-- pick.

local SYL = _G.ShowUsYourLoot

local Audience = {}
SYL.Audience = Audience

-- Cycle order, and also the narrowing order. Widening one step at a time is
-- what a button press means here.
Audience.SCOPES = { "team", "guild", "everyone" }

Audience.LABELS = {
    team = "Raid team",
    guild = "Guild",
    everyone = "Everyone",
}

-- Said under the list, so a number that looks wrong is explained by the row
-- that produced it rather than argued with.
Audience.NOTES = {
    team = "only players marked as being on the raid team",
    guild = "everyone in your guild",
    everyone = "everyone recorded, including pugs",
}

-- The words after a count, so a headline reads "12 on the team" rather than
-- carrying a noun that the scope has quietly stopped describing. A widget that
-- says "on the team" while showing the whole guild is worse than one that says
-- nothing, because it is a number somebody will quote.
Audience.SUBJECTS = {
    team = "on the team",
    guild = "in your guild",
    everyone = "recorded",
}

local function Settings()
    return ShowUsYourLootDB and ShowUsYourLootDB.settings
end

--------------------------------------------------------------------------
-- What the scope should be when nobody has chosen
--------------------------------------------------------------------------

-- The narrowest scope that can still return somebody. See the header: a
-- correct default that shows an empty window is not a correct default.
function Audience.Default()
    if SYL.RaidTeam.Count() > 0 then
        return "team"
    end

    if SYL.Guild.IsInGuild() then
        return "guild"
    end

    return "everyone"
end

function Audience.Get()
    local settings = Settings()
    local saved = settings and settings.audienceScope

    if saved and Audience.LABELS[saved] then
        return saved
    end

    return Audience.Default()
end

function Audience.Set(scope)
    local settings = Settings()

    if not settings or not Audience.LABELS[scope] then
        return
    end

    settings.audienceScope = scope
end

function Audience.Next(scope)
    scope = scope or Audience.Get()

    for index, candidate in ipairs(Audience.SCOPES) do
        if candidate == scope then
            return Audience.SCOPES[(index % #Audience.SCOPES) + 1]
        end
    end

    return Audience.SCOPES[1]
end

-- Advances and saves, returning where it landed so the caller can relabel
-- without asking again.
function Audience.Cycle()
    local scope = Audience.Next(Audience.Get())

    Audience.Set(scope)

    return scope
end

function Audience.Label(scope)
    return Audience.LABELS[scope or Audience.Get()] or "Everyone"
end

function Audience.Note(scope)
    return Audience.NOTES[scope or Audience.Get()] or ""
end

function Audience.Subject(scope)
    return Audience.SUBJECTS[scope or Audience.Get()] or "recorded"
end

--------------------------------------------------------------------------
-- Membership
--------------------------------------------------------------------------

-- Team membership is deliberately kept per character rather than per person —
-- see the note in Core/RaidTeam.lua, which explains why marking one alt must
-- not mark every character its owner has.
--
-- Every list this filters has already folded alts onto the main, though, so
-- asking the fold key alone gets the wrong answer in a case that is not rare:
-- an officer marks the character somebody actually raids on, that character is
-- an alt, and the person then fails their own team test and vanishes off the
-- due list. Bringing your alt to raid is precisely when you want the drought
-- number to keep working.
--
-- So the person is on the team if ANY of their characters is. That is the
-- reading that matches what marking a row meant to the person doing it.
local function AnyCharacterOnTeam(key)
    if SYL.RaidTeam.IsMember(key) then
        return true
    end

    for _, alt in ipairs(SYL.Players.GetAlts(key) or {}) do
        if alt.guid and SYL.RaidTeam.IsMember(alt.guid) then
            return true
        end
    end

    return false
end

-- guid and name are the fallbacks for somebody the registry does not know,
-- which is every pug: they have a name off a roll list and nothing else.
function Audience.Includes(scope, key, guid, name)
    scope = scope or Audience.Get()

    if scope == "everyone" then
        return true
    end

    if scope == "team" then
        return AnyCharacterOnTeam(key or guid or name)
    end

    -- Guild. GetMemberForPlayer resolves through the main first, so a
    -- cross-realm raider whose alt is in the guild still counts as guilded
    -- rather than as a stranger.
    return SYL.Guild.GetMemberForPlayer(key, guid, name) ~= nil
end

-- `read` pulls the identity out of whatever shape the caller holds, since due
-- entries, player stats and roster rows all name these fields differently.
-- Defaults to the shape all three happen to share.
local function DefaultRead(entry)
    return entry.key, entry.guid, entry.name
end

function Audience.Filter(entries, scope, read)
    scope = scope or Audience.Get()

    if scope == "everyone" then
        return entries
    end

    read = read or DefaultRead

    local kept = {}

    for _, entry in ipairs(entries or {}) do
        local key, guid, name = read(entry)

        if Audience.Includes(scope, key, guid, name) then
            table.insert(kept, entry)
        end
    end

    return kept
end

--------------------------------------------------------------------------
-- Empty lists
--------------------------------------------------------------------------

-- An empty list has to say which of two things happened, because the fix is
-- different: nothing is recorded, or the scope is hiding what is. Returns nil
-- when the scope is not the reason, so the caller keeps its own message.
function Audience.ExplainEmpty(scope, totalBeforeScope)
    scope = scope or Audience.Get()

    if scope == "everyone" or (totalBeforeScope or 0) == 0 then
        return nil
    end

    -- Worded without "press" or "click": the same sentence is printed by
    -- /syl due, where there is no button to press.
    if scope == "team" then
        if SYL.RaidTeam.Count() == 0 then
            return "Nobody is marked as being on the raid team yet. Open the "
                .. "roster and tick the TEAM column, or widen the scope to "
                .. "your guild with /syl scope."
        end

        return totalBeforeScope
            .. " recorded, none of them on the raid team. Widen the scope "
            .. "with /syl scope."
    end

    return totalBeforeScope
        .. " recorded, none of them in your guild. Widen the scope with "
        .. "/syl scope."
end
