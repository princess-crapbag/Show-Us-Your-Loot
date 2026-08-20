-- Core/Keystone.lua
--
-- Which Mythic+ keystone this character is holding, and when it was last
-- checked.
--
-- THE CONSTRAINT THAT DECIDES THE WHOLE DESIGN: an addon can only ever read
-- its OWN player's keystone. There is no API that reads another player's bags
-- — not for guild members, not for people in your group. Every addon that
-- shows a guild's keys works the same way, and it is the only way it can
-- work: each player runs the addon, each addon reads its own key, and they
-- tell each other over an addon channel.
--
-- So this file does exactly half the job. It answers "what am I holding" and
-- remembers it per character. Putting other people's keys on the same list
-- needs a guild-wide broadcast, which is a deliberate decision about what
-- this addon sends and to whom — see HANDOFF.md. Nothing here sends anything.
--
-- READ RATHER THAN SCANNED. Aimee asked for a bag scan, which is how this
-- used to be done and how the older addons still do it: walk every container
-- slot, match the item against the keystone item id, parse the link for the
-- level. C_MythicPlus answers both questions directly, so there is no reason
-- to walk 200 bag slots on every BAG_UPDATE. If a future client drops those
-- functions this returns nothing and says so, rather than guessing.
--
-- WHEN IT RUNS. At login, and again whenever the key could have changed: on
-- finishing a dungeon, on the weekly reset, and when the keystone item itself
-- moves in or out of the bags. A reroll at the font is a bag change, which is
-- why that event is watched at all.

local SYL = _G.ShowUsYourLoot

local Keystone = {}
SYL.Keystone = Keystone

-- Not every client build exposes the same three, so each is tried and the
-- first that answers wins. Feature-detected rather than assumed, the same way
-- Core/LootHistoryAPI.lua handles Enum.
local MAP_FUNCTIONS = {
    "GetOwnedKeystoneChallengeMapID",
    "GetOwnedKeystoneMapID",
}

local function Call(namespace, functionName, ...)
    if type(namespace) ~= "table" then
        return nil
    end

    local apiFunction = namespace[functionName]

    if type(apiFunction) ~= "function" then
        return nil
    end

    local ok, result = pcall(apiFunction, ...)

    if not ok then
        return nil
    end

    return result
end

function Keystone.IsAvailable()
    return type(C_MythicPlus) == "table"
end

-- The dungeon this key opens, as a map id, or nil for "not holding one".
function Keystone.GetOwnedMapID()
    for _, name in ipairs(MAP_FUNCTIONS) do
        local mapID = Call(C_MythicPlus, name)

        -- 0 is "none" from some of these, nil from others.
        if type(mapID) == "number" and mapID > 0 then
            return mapID
        end
    end

    return nil
end

function Keystone.GetOwnedLevel()
    local level = Call(C_MythicPlus, "GetOwnedKeystoneLevel")

    if type(level) == "number" and level > 0 then
        return level
    end

    return nil
end

-- "Ara-Kara, City of Echoes". Falls back to the raw id rather than to nothing,
-- so an unknown dungeon still shows something a person can act on.
function Keystone.GetMapName(mapID)
    if not mapID then
        return nil
    end

    local name = Call(C_ChallengeMode, "GetMapUIInfo", mapID)

    if type(name) == "string" and name ~= "" then
        return name
    end

    return "Map " .. tostring(mapID)
end

--------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------

-- Per character, not per person. Alts hold their own keys, and "who has a key
-- for this dungeon" is answered by a character walking in the door — folding
-- them onto the main would lose exactly the detail being asked for.
local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.keystones = ShowUsYourLootDB.keystones or {}

    return ShowUsYourLootDB.keystones
end

function Keystone.CharacterKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()

    if type(name) ~= "string" or name == "" then
        return nil
    end

    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm:gsub("%s+", "")
    end

    return name
end

-- Records what this character is holding right now, including "nothing",
-- which is a real answer and the one that has to overwrite last week's key.
--
-- Returns the entry and whether it changed, so a caller can stay quiet when
-- the answer is the same as the last time it asked — this runs on bag
-- updates, which fire constantly.
function Keystone.Update()
    local store = Store()
    local key = Keystone.CharacterKey()

    if not store or not key then
        return nil, false
    end

    if not Keystone.IsAvailable() then
        return nil, false
    end

    local mapID = Keystone.GetOwnedMapID()
    local level = Keystone.GetOwnedLevel()

    local previous = store[key]

    local changed = not previous
        or previous.mapID ~= mapID
        or previous.level ~= level

    store[key] = {
        name = key,
        class = select(2, UnitClass("player")),

        mapID = mapID,
        level = level,

        -- Kept even when there is no key, because "checked an hour ago and
        -- they have none" and "never checked" are different answers and the
        -- second one should not read as the first.
        checkedAt = time(),
    }

    return store[key], changed
end

function Keystone.Get(characterKey)
    local store = Store()

    return store and store[characterKey or ""] or nil
end

function Keystone.GetOwn()
    return Keystone.Get(Keystone.CharacterKey())
end

-- A KEY FROM BEFORE THE LAST RESET IS GONE, WHATEVER IT SAYS.
--
-- `checkedAt` has been written on every entry since keystones were recorded
-- and was read by nothing, so a character logged into three weeks ago still
-- advertised whatever key it was holding then. Guild keys have always been
-- filtered for exactly this — see Core/KeystoneSync.lua, whose comment
-- explains why the reset moment is asked for rather than assumed — and your
-- own alts were the half that never was.
--
-- Marked rather than dropped. The list deliberately includes characters with
-- no key, because "that alt has none" is an answer; "that alt had one last
-- week" is a better one than silence, and it says the row is not askable.
function Keystone.IsStale(entry)
    if not entry or not entry.mapID then
        return false
    end

    if not entry.checkedAt then
        -- Recorded before the field existed. Unknown is not stale, the same
        -- way an uncached item is not a BoE: the failure of guessing wrong
        -- here is hiding a key somebody actually has.
        return false
    end

    return entry.checkedAt < SYL.KeystoneSync.LastResetAt()
end

-- Everything this account knows, newest check first. Characters with no key
-- are included: "Aimee has none" is the answer to "who has a key" as much as
-- the ones who do.
function Keystone.List()
    local entries = {}

    for _, entry in pairs(Store() or {}) do
        entry.isStale = Keystone.IsStale(entry)

        table.insert(entries, entry)
    end

    table.sort(entries, function(left, right)
        -- A key that has expired sorts with the characters holding none, not
        -- above a live one just because last week's was higher.
        local leftLevel = (not left.isStale) and (left.level or 0) or 0
        local rightLevel = (not right.isStale) and (right.level or 0) or 0

        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return entries
end

function Keystone.Describe(entry)
    if not entry then
        return "no key recorded"
    end

    if not entry.mapID or not entry.level then
        return "no key"
    end

    -- Says when rather than what. The dungeon name is still in the record and
    -- naming it would read as a key somebody could be asked to run.
    if entry.isStale or Keystone.IsStale(entry) then
        return "no key this week"
    end

    return "+" .. entry.level .. " " .. Keystone.GetMapName(entry.mapID)
end
