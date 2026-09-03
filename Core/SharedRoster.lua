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
--
-- AND THAT IS THE BUG. Aimee, 2026-09-03: "the raid roster isn't syncing to
-- the officer. they added 2 new players to their roster and it seems to have
-- added them to my roster. then their entire raid team disappeared."
--
-- Her database says exactly what happened. `sharedRoster.source` was
-- "Pringlesbop-Illidan" and held nine names, two of them -- Chippym and
-- Quickadin -- on nobody's team but his. Both clients had the sharing switch
-- on, so both were broadcasting, and one slot with last-writer-wins is not a
-- design that survives two writers. "A name that changed instead of winning
-- invisibly" was the whole defense, and a name on a caption is not consent:
-- nobody reads a caption to find out their roster was replaced.
--
-- SO A SOURCE IS ACCEPTED ONCE, BY THE PERSON RECEIVING IT. A roster from a
-- name this client has not agreed to does not land; it waits, as an offer,
-- and something on screen asks. After yes, that name's later rosters arrive
-- quietly and NOBODY ELSE'S DO. After no, that name is not asked about again.
--
-- WHICH ALSO FIXES THE DISAPPEARANCE, and that one was worse than a wrong
-- roster. An officer whose own team is empty broadcasts the empty set --
-- a real message meaning "I have cleared my roster" -- and it wiped every
-- client in the guild, on a loop, because every login asks and every sharer
-- answers. An empty set is now only obeyed from the accepted source, and
-- RosterSync no longer answers a request with one at all.
--
-- DECLINING IS REMEMBERED, or the question comes back at every login of every
-- person in the guild, which is how a prompt teaches somebody to click
-- through prompts without reading them.

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

--------------------------------------------------------------------------
-- Who this client has agreed to listen to
--------------------------------------------------------------------------

-- The sender whose rosters land without asking, or nil for nobody yet.
--
-- Kept apart from `source` on purpose. `source` is where the roster on screen
-- came from and is a fact about the data; this is a decision the person made,
-- and it outlives an empty roster. Reading one for the other would mean an
-- officer who cleared their team also stopped being trusted.
function SharedRoster.AcceptedFrom()
    local store = Store()

    return store and store.acceptedFrom or nil
end

function SharedRoster.IsAccepted(source)
    return source ~= nil and SharedRoster.AcceptedFrom() == source
end

function SharedRoster.HasDeclined(source)
    local store = Store()

    if not store or not source then
        return false
    end

    return (store.declined and store.declined[source]) and true or false
end

-- The offer waiting for an answer, or nil. One at a time: a second sender
-- offering while the first is still on screen replaces it, because two
-- stacked dialogs asking the same question about different people is how
-- somebody accepts the wrong one.
function SharedRoster.PendingOffer()
    local store = Store()

    return store and store.offer or nil
end

-- A complete set has arrived. Returns what became of it, which is the whole
-- of the decision this file exists to make:
--
--   "applied"  -- from the accepted source, already stored
--   "pending"  -- from somebody new, waiting for an answer
--   "ignored"  -- from somebody already declined, or an empty set from a
--                 stranger, which is not an offer of anything
--
-- THE EMPTY SET FROM A STRANGER IS THE ONE THAT MATTERS. It is the message
-- that wiped the guild, and there is no version of it worth asking about:
-- "somebody you have never agreed to has no raid team" is not news, and a
-- dialog offering nothing cannot be answered sensibly either way.
function SharedRoster.Offer(source, members)
    if not source then
        return "ignored"
    end

    members = members or {}

    if SharedRoster.IsAccepted(source) then
        SharedRoster.Replace(source, members)

        return "applied"
    end

    if SharedRoster.HasDeclined(source) or #members == 0 then
        return "ignored"
    end

    local store = Store()

    if not store then
        return "ignored"
    end

    store.offer = { source = source, members = members, at = time() }

    return "pending"
end

-- Yes. The offer becomes the roster, and that name is trusted from here on.
-- Returns how many members landed and who sent them.
function SharedRoster.AcceptOffer()
    local store = Store()
    local offer = store and store.offer

    if not offer then
        return 0, nil
    end

    store.offer = nil
    store.acceptedFrom = offer.source

    -- Accepting one person clears a previous no about them, and only about
    -- them. Somebody who was declined last month and asked again today has
    -- been answered again today.
    if store.declined then
        store.declined[offer.source] = nil
    end

    return SharedRoster.Replace(offer.source, offer.members), offer.source
end

-- No, and remembered. Returns who was declined so the caller can say so.
function SharedRoster.DeclineOffer()
    local store = Store()
    local offer = store and store.offer

    if not offer then
        return nil
    end

    store.offer = nil
    store.declined = store.declined or {}
    store.declined[offer.source] = true

    return offer.source
end

-- The undo. Called from the roster screen as well as from here, because
-- anything that can arrive has to be dismissable by the person it arrived at.
--
-- TAKES THE ACCEPTANCE WITH IT, and that is the point rather than a side
-- effect. Clearing a roster while still trusting the person who sent it means
-- their next broadcast puts it straight back, which reads as a button that
-- did not work. Clearing is how somebody says "not this, not from them" --
-- and if they change their mind, the next offer asks again.
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
