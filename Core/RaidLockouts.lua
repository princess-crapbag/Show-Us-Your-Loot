-- Core/RaidLockouts.lua
--
-- Which of this account's characters is saved to which raid, and which bosses
-- each of them has already killed this week.
--
-- Aimee: "the way i can see m0 lockouts, id like to be able to see raid boss
-- kills/lockouts. put it somewhere that makes sense. i want to see this on
-- each toon as i log into them just the same way keys works."
--
-- WHY A SECOND FILE AND NOT A FLAG IN Core/Lockouts.lua. That file reads
-- `not isRaid` and always has, and everything downstream of it -- the season
-- dungeon list from C_ChallengeMode.GetMapTable, the name-to-map join, the
-- daily-or-weekly reasoning -- is about dungeons. A raid lockout is a
-- different shape: it has a difficulty, it has bosses inside it, and it has
-- no challenge-mode map to join to. One file with a boolean would have been
-- two files sharing a name.
--
-- IT ANSWERS BOSSES, WHICH IS THE POINT. GetSavedInstanceInfo reports how
-- many encounters a lockout has and how many are done, and
-- GetSavedInstanceEncounterInfo names each one and says whether it died. That
-- is the difference between "saved to the Abyss" and "saved to the Abyss,
-- five of eight, still needs Ula'tek".
--
-- THE SAME CONSTRAINT AS KEYSTONES AND DUNGEON LOCKOUTS: this can only ever
-- read its OWN character. There is no API for an alt's lockouts, so the list
-- fills in as each character logs in and not before. A character this account
-- has never played since installing is ABSENT rather than empty, and anything
-- drawing this has to say which -- see Core/Keystone.lua, which hit it first.
--
-- THE RESET IS STORED AS A MOMENT, NOT A COUNTDOWN, for the reason
-- Core/Lockouts.lua gives: a countdown saved to disk keeps counting from
-- whenever the file was written.

local SYL = _G.ShowUsYourLoot

local RaidLockouts = {}
SYL.RaidLockouts = RaidLockouts

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.raidLockouts = ShowUsYourLootDB.raidLockouts or {}

    return ShowUsYourLootDB.raidLockouts
end

function RaidLockouts.IsAvailable()
    return type(_G.GetNumSavedInstances) == "function"
        and type(_G.GetSavedInstanceInfo) == "function"
end

-- One lockout is one instance at one difficulty. The same raid on Normal and
-- Heroic is two, which is how the client reports it and how a raider thinks
-- about it.
function RaidLockouts.Key(name, difficultyName)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    return name .. "|" .. tostring(difficultyName or "")
end

-- The bosses inside one lockout, named, with whether each is already dead.
--
-- pcall'd per encounter rather than around the loop: one boss the client will
-- not answer for must cost that boss and not the whole lockout.
local function ReadEncounters(index, count)
    local bosses = {}

    if type(_G.GetSavedInstanceEncounterInfo) ~= "function" then
        return bosses
    end

    for position = 1, (count or 0) do
        local ok, name, _fileDataID, killed =
            pcall(GetSavedInstanceEncounterInfo, index, position)

        if ok and type(name) == "string" and name ~= "" then
            table.insert(bosses, {
                name = name,
                killed = killed and true or false,
            })
        end
    end

    return bosses
end

function RaidLockouts.Read()
    local found = {}

    if not RaidLockouts.IsAvailable() then
        return found
    end

    local ok, count = pcall(GetNumSavedInstances)

    if not ok or type(count) ~= "number" then
        return found
    end

    local now = time()

    for index = 1, count do
        -- name, id, reset, difficultyID, locked, extended, mostSig, isRaid,
        -- maxPlayers, difficultyName, numEncounters, encounterProgress
        local read, name, _id, reset, difficultyID, locked, _extended,
            _mostSig, isRaid, maxPlayers, difficultyName, numEncounters,
            progress = pcall(GetSavedInstanceInfo, index)

        if read and type(name) == "string" and isRaid and locked then
            local seconds = type(reset) == "number" and reset or 0

            if seconds > 0 then
                table.insert(found, {
                    name = name,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    key = RaidLockouts.Key(name, difficultyName),
                    expiresAt = now + seconds,
                    maxPlayers = maxPlayers,

                    total = type(numEncounters) == "number" and numEncounters
                        or 0,

                    killed = type(progress) == "number" and progress or 0,

                    bosses = ReadEncounters(index, numEncounters),
                })
            end
        end
    end

    return found
end

-- The client answers about the character that is logged in, so this is called
-- when one does. Returns the entry and whether anything changed, so a caller
-- can decide whether a screen needs redrawing.
function RaidLockouts.Update()
    local store = Store()
    local key = SYL.Keystone.CharacterKey()

    if not store or not key or not RaidLockouts.IsAvailable() then
        return nil, false
    end

    local lockouts = {}
    local count, bossesKilled = 0, 0

    for _, entry in ipairs(RaidLockouts.Read()) do
        if entry.key then
            lockouts[entry.key] = entry
            count = count + 1
            bossesKilled = bossesKilled + entry.killed
        end
    end

    local previous = store[key]

    local changed = not previous
        or (previous.count or 0) ~= count
        or (previous.bossesKilled or 0) ~= bossesKilled

    store[key] = {
        name = key,
        class = select(2, UnitClass("player")),

        lockouts = lockouts,
        count = count,
        bossesKilled = bossesKilled,

        -- "Checked and saved to nothing" and "never checked" are different
        -- answers, and anything drawing this has to draw them differently.
        checkedAt = time(),
    }

    return store[key], changed
end

-- Characters this account has seen, alphabetical, with expired lockouts
-- dropped on the way out.
--
-- CLEANED ON READ RATHER THAN ON A TIMER, because nothing ticks in this addon
-- and an entry read from disk can be days stale. Same rule as
-- Core/Lockouts.lua.
function RaidLockouts.Characters()
    local store = Store()
    local characters = {}
    local now = time()

    if not store then
        return characters
    end

    for key, entry in pairs(store) do
        local live = {}
        local count, killed = 0, 0

        for lockKey, lockout in pairs(entry.lockouts or {}) do
            if (lockout.expiresAt or 0) > now then
                live[lockKey] = lockout
                count = count + 1
                killed = killed + (lockout.killed or 0)
            end
        end

        table.insert(characters, {
            key = key,
            name = entry.name or key,
            class = entry.class,
            lockouts = live,
            count = count,
            bossesKilled = killed,
            checkedAt = entry.checkedAt,
        })
    end

    table.sort(characters, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return characters
end

-- One character's lockouts as a list, newest reset last, so a screen can draw
-- them in a stable order rather than whatever pairs answers.
function RaidLockouts.For(character)
    local rows = {}

    for _, lockout in pairs((character or {}).lockouts or {}) do
        table.insert(rows, lockout)
    end

    table.sort(rows, function(left, right)
        if left.name ~= right.name then
            return tostring(left.name) < tostring(right.name)
        end

        return (left.difficultyID or 0) < (right.difficultyID or 0)
    end)

    return rows
end

-- "5 of 8" for one lockout, and what is left to kill.
function RaidLockouts.Describe(lockout)
    if not lockout then
        return ""
    end

    local total = lockout.total or 0

    if total <= 0 then
        return tostring(lockout.killed or 0) .. " killed"
    end

    return (lockout.killed or 0) .. " of " .. total
end

-- The bosses still standing, named. What somebody actually wants from this
-- screen: not "am I saved" but "what can I still get".
function RaidLockouts.Remaining(lockout)
    local left = {}

    for _, boss in ipairs((lockout or {}).bosses or {}) do
        if not boss.killed then
            table.insert(left, boss.name)
        end
    end

    return left
end

-- Whether this character has been read at all. Absent and empty are different
-- answers and the screen says so.
function RaidLockouts.HasBeenChecked(character)
    return (character or {}).checkedAt ~= nil
end
