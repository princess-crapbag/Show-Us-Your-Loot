-- Core/KeystoneRequests.lua
--
-- Asking somebody to run their key, and answering when somebody asks you.
--
-- PER ACCOUNT, POINT TO POINT, AND THAT IS THE WHOLE PRIVACY MODEL. A request
-- is whispered to one person over the addon channel and nothing is ever
-- broadcast. Two people asking Dravok for the same key never learn about each
-- other, which is deliberate: a guild-wide "3 people want this key" turns a
-- favor into an auction, and the person holding the key is the only one who
-- needs the full picture.
--
-- IT IS A SEPARATE FEATURE FROM SHARING, and off by default like everything
-- here that talks to other players. Sharing tells the guild what you hold;
-- this sends a message to a named person and expects one back. Wanting the
-- first without the second is entirely reasonable — that is the same argument
-- that split officer sync from keystone sharing.
--
-- A DISMISSED REQUEST IS NOT A LOST REQUEST. Dismiss only hides the popup. The
-- request stays in the list until the weekly reset sweeps it, because the
-- failure mode being designed out is somebody clicking the X on a raid night
-- and never finding out who asked.
--
-- ONLY DENIED CAN BE ASKED AGAIN. Pending means they have not looked yet, and
-- letting somebody re-send into that is how the feature becomes a way to
-- pester people. Approved and tentative are answers; asking again after an
-- answer is a whisper, not a button.
--
-- Requests expire at the weekly reset, in the same sweep that drops stale
-- keys, because the key they were about does.

local SYL = _G.ShowUsYourLoot

local KeystoneRequests = {}
SYL.KeystoneRequests = KeystoneRequests

KeystoneRequests.ROLES = { "TANK", "HEALER", "DPS" }

KeystoneRequests.ROLE_LABELS = {
    TANK = "Tank",
    HEALER = "Healer",
    DPS = "DPS",
}

-- Pending is the only one that is not an answer, which is why it is the only
-- one that blocks asking again.
KeystoneRequests.STATUS = {
    PENDING = "pending",
    APPROVED = "approved",
    TENTATIVE = "tentative",
    DENIED = "denied",
}

KeystoneRequests.STATUS_LABELS = {
    pending = "Waiting",
    approved = "Yes",
    tentative = "Maybe",
    denied = "No",
}

local enabled = false

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    local store = ShowUsYourLootDB.keyRequests or {}

    store.outgoing = store.outgoing or {}
    store.incoming = store.incoming or {}

    ShowUsYourLootDB.keyRequests = store

    return store
end

KeystoneRequests.Store = Store

function KeystoneRequests.IsEnabled()
    return enabled
end

-- Set by Core/KeystoneRequestSync.lua, which owns the prefix registration.
-- The state lives here because every rule in this file consults it and none of
-- them should have to reach into the transport to ask.
function KeystoneRequests.SetEnabled(value)
    enabled = value and true or false
end

--------------------------------------------------------------------------
-- Who can be asked
--------------------------------------------------------------------------

-- Online only. A request to somebody offline is a message the game drops, and
-- an entry that sits Waiting forever with nothing having happened is worse
-- than a button that was not offered.
function KeystoneRequests.IsOnline(name)
    local member = SYL.Guild.GetMember(nil, name)

    return (member and member.isOnline) and true or false
end

-- Returns false and a reason, so a button can explain itself in a tooltip
-- rather than being mysteriously grayed out.
function KeystoneRequests.CanAsk(name)
    if not enabled then
        return false, "Key requests are switched off in Settings."
    end

    if name == SYL.Keystone.CharacterKey() then
        return false, "That is your own key."
    end

    if not KeystoneRequests.IsOnline(name) then
        return false, "They are offline."
    end

    local existing = KeystoneRequests.GetOutgoing(name)

    if existing then
        -- The one status that reopens. See the header: pending means they have
        -- not looked yet, and an answer is an answer.
        if existing.status == KeystoneRequests.STATUS.DENIED then
            return true
        end

        if existing.status == KeystoneRequests.STATUS.PENDING then
            return false, "You have already asked. They have not answered yet."
        end

        return false, "They already answered: "
            .. (KeystoneRequests.STATUS_LABELS[existing.status] or "?")
            .. ". Whisper them if it has changed."
    end

    return true
end

--------------------------------------------------------------------------
-- Asking
--------------------------------------------------------------------------

function KeystoneRequests.Ask(name, role)
    local allowed, reason = KeystoneRequests.CanAsk(name)

    if not allowed then
        return false, reason
    end

    local store = Store()

    if not store then
        return false, "No saved variables."
    end

    if not KeystoneRequests.ROLE_LABELS[role] then
        role = "DPS"
    end

    if not SYL.KeystoneRequestSync.SendAsk(name, role) then
        return false, "Could not send that."
    end

    store.outgoing[name] = {
        target = name,
        role = role,
        status = KeystoneRequests.STATUS.PENDING,
        at = time(),
    }

    return true
end

function KeystoneRequests.GetOutgoing(name)
    local store = Store()

    return store and store.outgoing[name] or nil
end

--------------------------------------------------------------------------
-- Answering
--------------------------------------------------------------------------

function KeystoneRequests.Answer(name, status)
    local store = Store()

    if not store or not store.incoming[name] then
        return false
    end

    if status ~= KeystoneRequests.STATUS.APPROVED
        and status ~= KeystoneRequests.STATUS.TENTATIVE
        and status ~= KeystoneRequests.STATUS.DENIED
    then
        return false
    end

    store.incoming[name].status = status
    store.incoming[name].answeredAt = time()

    -- Sent even if it fails to arrive: the holder has answered either way, and
    -- leaving their own list saying Waiting because the asker logged out would
    -- make them answer it twice.
    SYL.KeystoneRequestSync.SendAnswer(name, status)

    return true
end

-- Local only, and it does not change the answer. See the header.
function KeystoneRequests.Dismiss(name)
    local store = Store()

    if not store or not store.incoming[name] then
        return false
    end

    store.incoming[name].dismissed = true

    return true
end

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

local function Expired(entry)
    return not entry
        or not entry.at
        or entry.at < SYL.KeystoneSync.LastResetAt()
end

function KeystoneRequests.Sweep()
    local store = Store()

    if not store then
        return 0
    end

    local dropped = 0

    for name, entry in pairs(store.outgoing) do
        if Expired(entry) then
            store.outgoing[name] = nil
            dropped = dropped + 1
        end
    end

    for name, entry in pairs(store.incoming) do
        if Expired(entry) then
            store.incoming[name] = nil
            dropped = dropped + 1
        end
    end

    return dropped
end

local function Sorted(map, field)
    local entries = {}

    for _, entry in pairs(map) do
        table.insert(entries, entry)
    end

    -- Unanswered first, then most recent. The holder's list is a queue of
    -- things to do, and something already answered is not one of them.
    table.sort(entries, function(left, right)
        local leftPending = left.status == KeystoneRequests.STATUS.PENDING
        local rightPending = right.status == KeystoneRequests.STATUS.PENDING

        if leftPending ~= rightPending then
            return leftPending
        end

        if (left.at or 0) ~= (right.at or 0) then
            return (left.at or 0) > (right.at or 0)
        end

        return tostring(left[field]) < tostring(right[field])
    end)

    return entries
end

function KeystoneRequests.Incoming()
    KeystoneRequests.Sweep()

    local store = Store()

    return store and Sorted(store.incoming, "sender") or {}
end

function KeystoneRequests.Outgoing()
    KeystoneRequests.Sweep()

    local store = Store()

    return store and Sorted(store.outgoing, "target") or {}
end

-- What the panel badges: things asked of you that you have not answered and
-- have not hidden.
function KeystoneRequests.PendingCount()
    local count = 0

    for _, entry in ipairs(KeystoneRequests.Incoming()) do
        if entry.status == KeystoneRequests.STATUS.PENDING
            and not entry.dismissed
        then
            count = count + 1
        end
    end

    return count
end

