-- Core/Lockouts.lua
--
-- Which of this account's characters is saved to which Mythic 0 dungeon.
--
-- Mythic+ has no lockout and never has. Mythic 0 does, and the period is not
-- a constant: during a patch week it is weekly, and when the season opens it
-- becomes daily. Midnight Season 2 flips on 2026-08-18.
--
-- SO THE PERIOD IS NEVER WRITTEN DOWN HERE. GetSavedInstanceInfo returns
-- `reset`, the seconds left on that particular lockout, and this stores the
-- moment it expires. Daily and weekly are then the same code, and the flip on
-- season launch needs no release. Same reasoning as keystones expiring at the
-- client's own weekly reset rather than at a hardcoded Tuesday — see
-- Core/KeystoneSync.lua and HANDOFF.md.
--
-- THE SAME CONSTRAINT AS KEYSTONES: this can only ever read its OWN
-- character. There is no API for an alt's lockouts, let alone a guildie's, so
-- the grid fills in as each character logs in and not before. A character this
-- account has never played since installing is absent rather than empty, and
-- the UI has to say which. See Core/Keystone.lua, which hit this first.
--
-- THE SEASON'S DUNGEONS COME FROM THE CLIENT, not from a list in this file.
-- C_ChallengeMode.GetMapTable answers "what is in the rotation right now", so
-- Season 3 needs no edit here. A list typed in today would be wrong in three
-- months and wrong silently, which is the worst way for it to be wrong.
--
-- TWO ID SPACES, AND THEY DO NOT MEET. GetMapTable deals in challenge-mode map
-- ids; GetSavedInstanceInfo knows only instance names. There is no function
-- from one to the other, so the join is by name and the join can miss — a
-- dungeon whose M+ name is not its instance name resolves to nothing. When
-- that happens the lockout is still shown, in its own column, rather than
-- dropped: an unmatched name is a display problem, but a hidden lockout is a
-- wasted evening. Core/EncounterJournal.lua carries the same warning about the
-- journal's two id spaces, which cost an afternoon before it was written down.

local SYL = _G.ShowUsYourLoot

local Lockouts = {}
SYL.Lockouts = Lockouts

function Lockouts.IsAvailable()
    return type(GetSavedInstanceInfo) == "function"
        and type(GetNumSavedInstances) == "function"
end

-- Asks the server to send the lockout list. The answer arrives later as
-- UPDATE_INSTANCE_INFO; nothing here is readable until it does, which is why
-- Update is driven by the event rather than called straight after this.
function Lockouts.Request()
    if type(RequestRaidInfo) == "function" then
        pcall(RequestRaidInfo)
    end
end

--------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------

-- Lowercased and stripped to letters and digits, so "Kings' Rest" and
-- "King's Rest" are the same dungeon. The apostrophe is not decoration here:
-- the M+ map name and the instance name disagree about it for at least one
-- dungeon in every rotation so far.
function Lockouts.NameKey(name)
    if type(name) ~= "string" then
        return nil
    end

    local key = name:lower():gsub("[^%a%d]", "")

    if key == "" then
        return nil
    end

    return key
end

-- Every dungeon lockout this character currently has.
--
-- FILTERED ON isRaid, NOT ON A DIFFICULTY NUMBER. Mythic 0 is difficulty 23
-- today, and a difficulty id is exactly the kind of constant that moves. What
-- is being asked is "which dungeons am I saved to", and every dungeon lockout
-- in modern retail is a Mythic 0 one — heroics stopped having them. The
-- difficulty is recorded so the UI can label it, not so this can gate on it.
function Lockouts.Read()
    local found = {}

    if not Lockouts.IsAvailable() then
        return found
    end

    local ok, count = pcall(GetNumSavedInstances)

    if not ok or type(count) ~= "number" then
        return found
    end

    local now = time()

    for index = 1, count do
        local read, name, _, reset, _, locked, _, _, isRaid,
            _, difficultyName = pcall(GetSavedInstanceInfo, index)

        if read and type(name) == "string" and not isRaid and locked then
            local seconds = type(reset) == "number" and reset or 0

            -- Absolute, because this outlives the session that read it. A
            -- countdown saved to disk is a countdown that keeps counting from
            -- whenever the file was written.
            if seconds > 0 then
                table.insert(found, {
                    name = name,
                    key = Lockouts.NameKey(name),
                    expiresAt = now + seconds,
                    difficultyName = difficultyName,
                })
            end
        end
    end

    return found
end

-- The season's dungeons, in the client's own order.
function Lockouts.SeasonMaps()
    local maps = {}

    if type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.GetMapTable) ~= "function"
    then
        return maps
    end

    local ok, ids = pcall(C_ChallengeMode.GetMapTable)

    if not ok or type(ids) ~= "table" then
        return maps
    end

    for _, mapID in ipairs(ids) do
        local name = SYL.Keystone.GetMapName(mapID)

        table.insert(maps, {
            mapID = mapID,
            name = name,
            key = Lockouts.NameKey(name),
        })
    end

    return maps
end

--------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------

-- Per character, for the same reason keystones are: a lockout belongs to the
-- character that walked in the door, and folding alts onto a main would erase
-- the one detail being asked for.
local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.lockouts = ShowUsYourLootDB.lockouts or {}

    return ShowUsYourLootDB.lockouts
end

function Lockouts.Update()
    local store = Store()
    local key = SYL.Keystone.CharacterKey()

    if not store or not key or not Lockouts.IsAvailable() then
        return nil, false
    end

    local instances = {}
    local count = 0

    for _, entry in ipairs(Lockouts.Read()) do
        if entry.key then
            instances[entry.key] = entry
            count = count + 1
        end
    end

    local previous = store[key]
    local changed = not previous or (previous.count or 0) ~= count

    store[key] = {
        name = key,
        class = select(2, UnitClass("player")),

        instances = instances,
        count = count,

        -- "Checked and saved to nothing" and "never checked" are different
        -- answers, and the grid draws them differently.
        checkedAt = time(),
    }

    return store[key], changed
end

-- Characters this account has seen, alphabetical. Expired lockouts are dropped
-- on the way out rather than on a timer: nothing ticks in this addon, and an
-- entry read from disk can be days stale.
function Lockouts.Characters()
    local now = time()
    local characters = {}

    for _, entry in pairs(Store() or {}) do
        local live = {}
        local count = 0

        for mapKey, instance in pairs(entry.instances or {}) do
            if (instance.expiresAt or 0) > now then
                live[mapKey] = instance
                count = count + 1
            end
        end

        table.insert(characters, {
            name = entry.name,
            class = entry.class,
            checkedAt = entry.checkedAt,
            instances = live,
            count = count,
        })
    end

    table.sort(characters, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return characters
end

--------------------------------------------------------------------------
-- The grid
--------------------------------------------------------------------------

-- Columns are the season's dungeons, plus any dungeon somebody is actually
-- saved to that the season list did not account for. That second half is what
-- keeps a failed name join from hiding a lockout: worst case the dungeon gets
-- its own column on the end instead of a tick in the right one.
function Lockouts.Build()
    local characters = Lockouts.Characters()
    local columns = {}
    local seen = {}

    for _, map in ipairs(Lockouts.SeasonMaps()) do
        if map.key and not seen[map.key] then
            seen[map.key] = true

            table.insert(columns, {
                key = map.key, name = map.name, seasonal = true,
            })
        end
    end

    local extras = {}

    for _, character in ipairs(characters) do
        for mapKey, instance in pairs(character.instances) do
            if not seen[mapKey] then
                seen[mapKey] = true

                table.insert(extras, {
                    key = mapKey, name = instance.name, seasonal = false,
                })
            end
        end
    end

    table.sort(extras, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    for _, extra in ipairs(extras) do
        table.insert(columns, extra)
    end

    return columns, characters
end

-- Seconds until this character's earliest lockout lifts, or nil when they hold
-- none. The grid prints one countdown per row rather than one per cell: within
-- a character they nearly always share a reset, and eight identical clocks in
-- a row is noise.
function Lockouts.NextReset(character)
    local soonest

    for _, instance in pairs(character and character.instances or {}) do
        local at = instance.expiresAt or 0

        if at > 0 and (not soonest or at < soonest) then
            soonest = at
        end
    end

    if not soonest then
        return nil
    end

    return math.max(0, soonest - time())
end

-- "3d 4h", "4h 20m", "35m". Days appear because a weekly lockout is most of a
-- week for most of its life, and "76h" is not a number anybody plans around.
function Lockouts.FormatRemaining(seconds)
    seconds = math.max(0, math.floor(seconds or 0))

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    end

    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end

    return string.format("%dm", minutes)
end

function Lockouts.Describe(character)
    if not character then
        return "never seen"
    end

    if (character.count or 0) == 0 then
        return "free everywhere"
    end

    local remaining = Lockouts.NextReset(character)

    return character.count
        .. " saved"
        .. (remaining and ("  ·  " .. Lockouts.FormatRemaining(remaining)) or "")
end
