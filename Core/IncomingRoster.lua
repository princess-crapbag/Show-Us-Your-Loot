-- Core/IncomingRoster.lua
--
-- Raiders who are joining but are not in the guild yet.
--
-- Aimee's ask: "i need to be able to add a character-server who is not yet in
-- guild to the roster. they will be joining and i want to account for their
-- class and buff." A recruit agreed on Tuesday who transfers on Friday is
-- part of Friday's raid whether or not the guild roster knows it, and the buff
-- coverage that says "no Mage" is wrong all week if it cannot see them.
--
-- THE CLASS HAS TO BE TYPED, and there is no way around it. The client can
-- only tell you the class of somebody it can see — a guild member, a party
-- member, a friend, a target. For a character on another realm who has not
-- transferred, there is no API that will answer, so the officer adding them
-- says what they play. That is also why this is a small deliberate list of
-- fields rather than a lookup.
--
-- KEYED BY NAME-REALM, lowercased, because that is the only identity these
-- have. Everyone else in this addon is keyed by GUID, which is exact and
-- survives a rename; an incoming raider has no GUID until the client has
-- actually seen them. The moment it does — when they join the guild — Promote
-- moves everything onto the real record and this entry goes away, so the
-- name-keyed period is as short as possible.
--
-- Team membership and role live on the entry itself rather than on the player
-- registry, which is GUID-keyed and would need a fake one. RaidTeam.Record
-- falls back to here, so IsMember, SetRole and the rest work on an incoming
-- raider without knowing they are one.

local SYL = _G.ShowUsYourLoot

local IncomingRoster = {}
SYL.IncomingRoster = IncomingRoster

-- The locale-independent names, which is what class colours, the buff table
-- and the roster rows all key on.
IncomingRoster.CLASSES = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE",
    "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local CLASS_SET = {}

for _, class in ipairs(IncomingRoster.CLASSES) do
    CLASS_SET[class] = true
end

function IncomingRoster.IsClass(class)
    return type(class) == "string" and CLASS_SET[class:upper()] == true
end

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.incoming = ShowUsYourLootDB.incoming or {}

    return ShowUsYourLootDB.incoming
end

-- "Aimee-Silvermoon" and "aimee-silvermoon" are one person. Returns nil for
-- anything without a realm: a bare name is ambiguous across realms, and this
-- exists precisely for characters who are not on yours yet.
function IncomingRoster.Key(fullName)
    if type(fullName) ~= "string" then
        return nil
    end

    local name, realm = fullName:match("^%s*([^%-]+)%-([^%-]+.-)%s*$")

    if not name or name == "" or not realm or realm == "" then
        return nil
    end

    -- Realms are written with spaces by people and without by the client.
    realm = realm:gsub("%s+", "")

    return (name .. "-" .. realm):lower(), name, realm
end

function IncomingRoster.Get(key)
    local store = Store()

    return store and store[key or ""] or nil
end

-- Returns the entry and a message, or nil and why not. The caller prints it:
-- this is reached from a slash command and from a button, and both want the
-- same words.
function IncomingRoster.Add(fullName, class)
    local store = Store()

    if not store then
        return nil, "The database is not ready yet."
    end

    local key, name, realm = IncomingRoster.Key(fullName)

    if not key then
        return nil,
            "Give the character as Name-Realm, for example Aimee-Silvermoon. "
            .. "The realm is needed because they are not on your roster yet."
    end

    if not IncomingRoster.IsClass(class) then
        return nil,
            "Say which class they play — the client cannot look it up for "
            .. "somebody it has never seen. One of: "
            .. table.concat(IncomingRoster.CLASSES, ", "):lower() .. "."
    end

    if SYL.Guild.FindByShortName(name) then
        return nil,
            name .. " is already in the guild, so they are on the roster "
            .. "already."
    end

    local existing = store[key]

    store[key] = {
        key = key,
        name = name,
        realm = realm,
        fullName = name .. "-" .. realm,
        class = class:upper(),

        addedAt = existing and existing.addedAt or time(),

        -- Carried across an edit, so correcting a typo in the class does not
        -- take somebody off the team.
        inRaidTeam = existing and existing.inRaidTeam or nil,
        raidRole = existing and existing.raidRole or nil,
    }

    return store[key],
        (existing and "Updated " or "Added ")
        .. name .. "-" .. realm
        .. " as a " .. class:lower()
        .. ". They count towards raid buff coverage from now on, and will "
        .. "move onto the guild roster by themselves once they join."
end

function IncomingRoster.Remove(fullName)
    local store = Store()
    local key = IncomingRoster.Key(fullName)

    if not store or not key or not store[key] then
        return false
    end

    store[key] = nil

    return true
end

-- Sorted, so the roster draws them in a stable order rather than in whatever
-- order pairs() happens to give today.
function IncomingRoster.List()
    local store = Store()
    local entries = {}

    if not store then
        return entries
    end

    for _, entry in pairs(store) do
        table.insert(entries, entry)
    end

    table.sort(entries, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return entries
end

function IncomingRoster.Count()
    local total = 0

    for _ in pairs(Store() or {}) do
        total = total + 1
    end

    return total
end

-- They joined. Move what an officer decided about them onto the real record
-- and drop the placeholder.
--
-- Matched on the short name against the guild roster, because that is what
-- the guild roster gives and a transfer changes the realm anyway — somebody
-- added as Aimee-Silvermoon who transfers to your realm is Aimee here.
--
-- Only ever moves things ON. If the character already had a role set, that is
-- somebody's later decision about a character the client can actually see,
-- and a placeholder typed a fortnight ago should not overrule it.
function IncomingRoster.PromoteJoined()
    local store = Store()

    if not store then
        return 0
    end

    local promoted = 0

    for key, entry in pairs(store) do
        local member = SYL.Guild.FindByShortName(entry.name)

        if member and member.guid then
            local player = SYL.Players.Get(member.guid)

            if player then
                if entry.inRaidTeam and not player.inRaidTeam then
                    player.inRaidTeam = true
                end

                if entry.raidRole and not player.raidRole then
                    player.raidRole = entry.raidRole
                end
            end

            store[key] = nil
            promoted = promoted + 1
        end
    end

    return promoted
end
