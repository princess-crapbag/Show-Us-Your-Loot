-- Core/SharedRoster.lua
--
-- A raid team somebody else sent, and where it is kept.
--
-- Split from RosterSync for the same reason Absences is split from
-- AbsenceSync: one file is what is true, the other is how it travels. The
-- readers here — RaidTeam and RosterData — care about the first and nothing
-- at all about the second, and pointing them at a sync module to ask what the
-- roster is made that relationship read backwards.
--
-- ITS OWN BLOCK, NOT THE PLAYER REGISTRY, AND THAT IS THE WHOLE POINT. The
-- registry is this account's own record of people and is what every setter in
-- RaidTeam writes to. A roster that arrived over the guild channel is somebody
-- else's opinion, so it is kept where it cannot be mistaken for a local one:
-- clearing it takes nothing of yours with it, and a screen can always say
-- which of the two it is showing. Sync.lua reaches the same conclusion about
-- arriving drops by marking them partial.
--
-- ONE ROSTER, NOT A SET PER SENDER. The design is one broadcaster, so the
-- newest complete set received replaces what is held. The source is recorded
-- rather than assumed, so a second broadcaster turning their switch on shows
-- up on the screen as a name that changed instead of winning invisibly.

local SYL = _G.ShowUsYourLoot

local SharedRoster = {}
SYL.SharedRoster = SharedRoster

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.sharedRoster = ShowUsYourLootDB.sharedRoster
        or { members = {} }

    ShowUsYourLootDB.sharedRoster.members =
        ShowUsYourLootDB.sharedRoster.members or {}

    return ShowUsYourLootDB.sharedRoster
end

SharedRoster.Store = Store

-- Every member of the received roster, keyed the way it arrived. Callers walk
-- this to find people they hold no record of; RaidTeam asks about one key at a
-- time through Member.
function SharedRoster.Members()
    local store = Store()

    return (store and store.members) or {}
end

-- One received entry, or nil. This is the whole of what RaidTeam reads.
function SharedRoster.Member(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end

    local store = Store()

    return (store and store.members[key]) or nil
end

-- Whether there is anything to show. An emptied roster keeps its source, so
-- "has a source" is a different question and asking it would leave the screen
-- announcing a share with nobody in it.
function SharedRoster.HasShared()
    local store = Store()

    return (store and next(store.members) ~= nil) and true or false
end

function SharedRoster.Source()
    local store = Store()

    if not store then
        return nil, nil
    end

    return store.source, store.receivedAt
end

function SharedRoster.Count()
    local total = 0

    for _ in pairs(SharedRoster.Members()) do
        total = total + 1
    end

    return total
end

-- Replaces the whole roster. The caller has already decided the set is
-- complete; a half-delivered one must never reach this.
function SharedRoster.Replace(source, members)
    local store = Store()

    if not store then
        return 0
    end

    store.source = source
    store.receivedAt = time()
    store.members = {}

    for _, member in ipairs(members or {}) do
        if member.key then
            store.members[member.key] = member
        end
    end

    SharedRoster.Invalidate()

    return #(members or {})
end

-- The undo. Called from the roster screen as well as from here, because
-- anything that can arrive has to be dismissable by the person it arrived at.
function SharedRoster.Clear()
    if not ShowUsYourLootDB then
        return false
    end

    ShowUsYourLootDB.sharedRoster = nil

    SharedRoster.Invalidate()

    return true
end

-- The roster list is built once and kept until something changes it, and both
-- of the above change it. Without this the screen keeps the list it built
-- before the broadcast landed, and the feature looks like it did nothing.
function SharedRoster.Invalidate()
    if SYL.RosterData then
        SYL.RosterData.Invalidate()
    end
end
