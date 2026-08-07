-- Core/Players.lua
--
-- The player registry: who these characters are, and which of them are the
-- same person.
--
-- Everything else in this addon is drop-centric. Records live in
-- season.drops with their roll lists embedded, and DueList, Analytics and
-- BossStats all work by sweeping that array. Nothing has ever held a fact
-- about a *player* that outlives one drop, which is why alts, gear and
-- weekly rewards all had nowhere to go.
--
-- WHY THIS IS NOT season.players, which was carved out for it:
--
-- Seasons get archived. An alt mapping is not a fact about a tier of loot,
-- it is a fact about a person, and archiving a season must not quietly
-- forget that Aimeealt is Aimee. The registry is account level and the
-- season keeps holding its own history, which already carries names and
-- classes as they were at the time on each roll.
--
-- THE CHOKE POINT: ResolveToMain is the only place alt identity is applied.
-- Callers pass a roster key or a roll key and get back the key the maths
-- should count against. Scattering that decision is how half the numbers end
-- up folding alts and the other half do not.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Players = {}
SYL.Players = Players

local MANUAL = "manual"
local GUILD_NOTE = "guildnote"
local INFERRED = "inferred"

Players.MANUAL = MANUAL
Players.GUILD_NOTE = GUILD_NOTE
Players.INFERRED = INFERRED

-- A weaker source never overwrites a stronger one. An officer who maps
-- someone by hand has said something the guild note cannot outrank, and a
-- guess never outranks either.
local PRIORITY = {
    [MANUAL] = 3,
    [GUILD_NOTE] = 2,
    [INFERRED] = 1,
}

Players.SOURCE_LABELS = {
    [MANUAL] = "set by hand",
    [GUILD_NOTE] = "from guild note",
    [INFERRED] = "guessed",
}

-- A mapping chain should be one hop: alt points at main. Two hops means
-- someone mapped an alt to an alt, which is recoverable, and a loop means
-- the data is wrong in a way that would otherwise hang the resolver.
local MAX_HOPS = 4

-- Name to GUID. Rebuilt in memory at login rather than saved, so
-- SavedVariables holds no derived data. Roll lists carry names without a
-- realm, so both spellings are indexed, exactly as Guild.lua does.
local nameIndex = {}

function Players.GetRegistry()
    if not ShowUsYourLootDB then
        return {}
    end

    ShowUsYourLootDB.players = ShowUsYourLootDB.players or {}

    return ShowUsYourLootDB.players
end

local function ShortName(fullName)
    if type(fullName) ~= "string" then
        return nil
    end

    return (fullName:match("^([^-]+)")) or fullName
end

-- Keys are lowercased. Names arrive from three places that disagree about
-- capitalisation — rosters give the canonical spelling, roll lists echo it,
-- and anything a person typed into a note or a slash command is whatever
-- they felt like. Indexing one way makes all three line up.
local function IndexName(name, guid)
    if type(name) ~= "string" or name == "" or not guid then
        return
    end

    local lowered = name:lower()

    -- First writer wins. Two realms can share a name, and overwriting would
    -- make the fallback path answer with whoever was seen most recently
    -- rather than admitting the ambiguity.
    if nameIndex[lowered] == nil then
        nameIndex[lowered] = guid
    elseif nameIndex[lowered] ~= guid then
        nameIndex[lowered] = false
    end
end

function Players.RebuildIndex()
    nameIndex = {}

    for guid, player in pairs(Players.GetRegistry()) do
        IndexName(player.fullName, guid)
        IndexName(player.name, guid)
    end
end

-- Returns the GUID a name refers to, or nil when the name is unknown or
-- ambiguous. Ambiguity is deliberately not resolved: guessing which realm's
-- Aimee was meant is how loot lands on the wrong person's record.
function Players.GUIDForName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local lowered = name:lower()
    local guid = nameIndex[lowered]

    if guid then
        return guid
    end

    -- false rather than nil means the name is known and ambiguous. Guessing
    -- which realm's Aimee was meant is how loot lands on the wrong record,
    -- so this refuses instead.
    if guid == false then
        return nil
    end

    local short = ShortName(lowered)

    if short and short ~= lowered then
        guid = nameIndex[short]

        return guid or nil
    end

    return nil
end

-- Accepts either a GUID or a name, because roll lists carry one and rosters
-- carry the other.
function Players.Get(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end

    local registry = Players.GetRegistry()

    if registry[key] then
        return registry[key], key
    end

    local guid = Players.GUIDForName(key)

    if guid and registry[guid] then
        return registry[guid], guid
    end

    return nil
end

-- Upserts from anything that knows a character exists: a raid roster, a roll
-- list, the guild roster. Only fills blanks, so a later sighting that
-- happens to lack a class does not erase one already known.
function Players.Ensure(info)
    if type(info) ~= "table" then
        return nil
    end

    local guid = info.guid

    -- Without a GUID there is nothing stable to key on. Names are not
    -- unique across realms and characters get renamed, so a name-only
    -- sighting is used for lookups and never creates a record.
    if type(guid) ~= "string" or guid == "" then
        return nil
    end

    local registry = Players.GetRegistry()
    local player = registry[guid]

    if not player then
        player = {
            guid = guid,
            firstSeen = time(),
        }

        registry[guid] = player
    end

    player.name = info.name or player.name
    player.fullName = info.fullName or player.fullName
    player.class = info.class or player.class
    player.realm = info.realm or player.realm
    player.lastSeen = time()

    IndexName(player.fullName, guid)
    IndexName(player.name, guid)

    return player
end

-- Called for every member of every roster read, so it stays cheap.
function Players.Touch(member)
    return Players.Ensure(member)
end

-- THE CHOKE POINT.
--
-- Given whatever key the caller has, returns the key its numbers should be
-- counted against. An unmapped character resolves to itself, so callers can
-- route every key through this without checking first.
function Players.ResolveToMain(key)
    if type(key) ~= "string" or key == "" then
        return key
    end

    local player, resolvedKey = Players.Get(key)

    if not player then
        return key
    end

    local current = player
    local currentKey = resolvedKey
    local hops = 0

    while current and current.mainGUID and hops < MAX_HOPS do
        local nextPlayer = Players.GetRegistry()[current.mainGUID]

        if not nextPlayer then
            -- Points at somebody not in the registry. The mapping is not
            -- usable, and returning the alt's own key is better than
            -- returning a key nothing else knows about.
            return currentKey
        end

        currentKey = current.mainGUID
        current = nextPlayer
        hops = hops + 1
    end

    return currentKey
end

local function WouldLoop(altGUID, mainGUID)
    local registry = Players.GetRegistry()
    local cursor = registry[mainGUID]
    local hops = 0

    while cursor and hops < MAX_HOPS do
        if cursor.guid == altGUID then
            return true
        end

        cursor = cursor.mainGUID and registry[cursor.mainGUID] or nil
        hops = hops + 1
    end

    return false
end

-- Returns ok, message. The message is shown to the officer either way, so it
-- explains the refusal rather than just reporting one.
function Players.SetMain(altKey, mainKey, source)
    source = source or MANUAL

    local alt, altGUID = Players.Get(altKey)
    local main, mainGUID = Players.Get(mainKey)

    if not alt then
        return false, "Not a character this addon has seen: "
            .. tostring(altKey)
    end

    if not main then
        return false, "Not a character this addon has seen: "
            .. tostring(mainKey)
    end

    if altGUID == mainGUID then
        return false, "A character cannot be its own main."
    end

    if WouldLoop(altGUID, mainGUID) then
        return false,
            "That would point the two at each other. Clear one first."
    end

    -- A weaker source is not an error, it is just ignored. Guild note
    -- parsing runs on every roster refresh and must not undo an officer.
    local existing = alt.identitySource

    if existing and PRIORITY[source] < (PRIORITY[existing] or 0) then
        return false, (alt.name or altKey)
            .. " is already mapped "
            .. (Players.SOURCE_LABELS[existing] or existing)
            .. "."
    end

    alt.mainGUID = mainGUID
    alt.identitySource = source
    alt.identitySetAt = time()

    return true, (alt.name or altKey)
        .. " counts as "
        .. (main.name or mainKey)
        .. "."
end

function Players.ClearMain(altKey)
    local alt, altGUID = Players.Get(altKey)

    if not alt then
        return false, "Not a character this addon has seen: "
            .. tostring(altKey)
    end

    if not alt.mainGUID then
        return false, (alt.name or altGUID) .. " is not mapped to anyone."
    end

    alt.mainGUID = nil
    alt.identitySource = nil
    alt.identitySetAt = nil

    return true, (alt.name or altGUID) .. " is on its own again."
end

function Players.GetAlts(mainKey)
    local _, mainGUID = Players.Get(mainKey)

    if not mainGUID then
        return {}
    end

    local alts = {}

    for guid, player in pairs(Players.GetRegistry()) do
        if player.mainGUID == mainGUID then
            table.insert(alts, player)
        end
    end

    table.sort(alts, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return alts
end

-- How many mappings are folded into whatever the caller is about to show.
-- A due list that silently merges two characters is a due list somebody
-- will argue with, so every window that uses the resolver says this out
-- loud.
function Players.CountMappings()
    local mapped, mains = 0, {}

    for _, player in pairs(Players.GetRegistry()) do
        if player.mainGUID then
            mapped = mapped + 1
            mains[player.mainGUID] = true
        end
    end

    return mapped, Utilities.CountKeys(mains)
end

function Players.DescribeMappings()
    local mapped, mains = Players.CountMappings()

    if mapped == 0 then
        return nil
    end

    return mapped
        .. (mapped == 1 and " alt" or " alts")
        .. " folded into "
        .. mains
        .. (mains == 1 and " main" or " mains")
end
