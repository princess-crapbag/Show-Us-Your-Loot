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

--------------------------------------------------------------------------
-- A person, not a character
--------------------------------------------------------------------------

-- Aimee, 2026-09-06: "can i ask pronglez for his key on pringlescat and it
-- send to whichever character he is online with and show which key im asking
-- for?"
--
-- WHY THE TWO HALVES OF THAT ARE ONE CHANGE. A key belongs to a character --
-- Core/Keystone.lua stores them that way on purpose, "alts hold their own
-- keys, and folding them onto the main would lose exactly the detail being
-- asked for". The moment a request can be delivered to any character of a
-- person, "your key" stops being answerable: on 2026-09-06 that one guildie
-- held +14 and +13 on one dungeon and +15 on another. So the request names
-- the key it is about, and the alert names it back. See KeystoneRequestSync.
--
-- IT ONLY WORKS AS WELL AS THE ALT MAPPING DOES, and that is not a defect to
-- paper over. Before Aimee linked them, five of that person's eight
-- characters pointed at the main and Pronglez -- the one she wanted -- did
-- not, so asking Pronglez could only ever reach Pronglez. Players.
-- ResolveToMain answers with the character's own key when it knows of no
-- mapping, so an unmapped character behaves exactly as it did before this
-- existed rather than reaching somebody at random.

-- Every character the addon knows this person by, including the one asked
-- for. Sorted, so two calls in a row pick the same delivery target and a row
-- does not report a different destination each time it is drawn.
function KeystoneRequests.CharactersOf(name)
    if type(name) ~= "string" or name == "" then
        return {}
    end

    local names = { name }
    local seen = { [name:lower()] = true }

    if not SYL.Players then
        return names
    end

    local mainKey = SYL.Players.ResolveToMain(name)
    local main = SYL.Players.Get(mainKey)

    local function Add(player)
        local full = player and (player.fullName or player.name)

        if full and not seen[full:lower()] then
            seen[full:lower()] = true

            table.insert(names, full)
        end
    end

    Add(main)

    for _, alt in ipairs(SYL.Players.GetAlts(mainKey) or {}) do
        Add(alt)
    end

    table.sort(names, function(left, right)
        return left:lower() < right:lower()
    end)

    return names
end

-- Which character to actually whisper, or nil when none of them is logged in.
--
-- THE ONE ASKED FOR WINS WHEN THEY ARE ONLINE, and that is not just
-- politeness: the whole point of naming a character is that it is the one
-- holding the key, and routing past them to an alt when they are standing
-- right there would read as the addon guessing.
function KeystoneRequests.DeliveryFor(name)
    if KeystoneRequests.IsOnline(name) then
        return name
    end

    for _, character in ipairs(KeystoneRequests.CharactersOf(name)) do
        if KeystoneRequests.IsOnline(character) then
            return character
        end
    end

    return nil
end

-- The key a request is about, as the wire carries it. nil when the addon does
-- not hold one for that character, which is not a refusal -- somebody can ask
-- about a key they saw in guild chat before this client has seen it.
function KeystoneRequests.KeyFor(name)
    local entry = SYL.Keystone and SYL.Keystone.Get(name)

    if not entry or not entry.mapID then
        return nil
    end

    return { owner = name, mapID = entry.mapID, level = entry.level }
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

    -- OFFLINE IS NO LONGER A REFUSAL. Aimee: "i still want to be able to
    -- request keys from other players who are not online and they see the
    -- message when they log in."
    --
    -- The request is held here and sent the moment that character is seen
    -- online -- see FlushQueued, which the guild roster event drives. What an
    -- addon CANNOT do is put anything in front of somebody who is not logged
    -- in: there is no offline delivery in the API at all. Mail would reach
    -- them and needs a mailbox and postage, which is not a thing to do to
    -- somebody's character for a keystone.
    --
    -- So the honest promise is "the next time you are both online", and the
    -- button says exactly that rather than implying it has been sent.

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

    -- WHOEVER OF THEIRS IS LOGGED IN, not only the character named. The key
    -- still belongs to `name` and the request still says so; this is just
    -- which door it is posted through.
    local deliverTo = KeystoneRequests.DeliveryFor(name)
    local key = KeystoneRequests.KeyFor(name)

    if deliverTo
        and not SYL.KeystoneRequestSync.SendAsk(deliverTo, role, key)
    then
        return false, "Could not send that."
    end

    store.outgoing[name] = {
        target = name,
        role = role,
        status = KeystoneRequests.STATUS.PENDING,
        at = time(),

        -- WHERE IT WENT, kept because it is the one thing the screen cannot
        -- work out later. By the time somebody hovers the row, whoever was
        -- online when Ask was pressed may have logged out -- so recomputing
        -- it would report a different character than the one that was
        -- actually whispered.
        sentTo = deliverTo,

        -- Which key was asked about, as it stood at the moment of asking. It
        -- resets weekly and the row has to keep saying what the question was.
        mapID = key and key.mapID,
        level = key and key.level,

        -- Held rather than sent. Cleared by FlushQueued when they appear, and
        -- it is the difference between "they have not answered" and "they
        -- have not been asked yet" -- two states that read identically on a
        -- screen that only knows PENDING.
        queued = (not deliverTo) or nil,
    }

    return true, deliverTo and nil or "queued"
end

--------------------------------------------------------------------------
-- Sending what was held
--------------------------------------------------------------------------

-- Every request waiting on somebody who was offline when it was made, sent
-- now that they are not. Returns how many went.
--
-- Driven by GUILD_ROSTER_UPDATE, which fires whenever anybody in the guild
-- logs in or out -- so a request made on Tuesday afternoon goes out the
-- moment they come online on Tuesday evening, with nobody pressing anything.
--
-- A request whose target is still offline is left exactly where it is. The
-- sweep at the weekly reset clears it if it never got there, in the same pass
-- that drops the key it was about.
function KeystoneRequests.FlushQueued()
    local store = Store()

    if not store or not enabled then
        return 0
    end

    local sent = 0

    for name, request in pairs(store.outgoing) do
        local deliverTo = request.queued
            and request.status == KeystoneRequests.STATUS.PENDING
            and KeystoneRequests.DeliveryFor(name)
            or nil

        if deliverTo then
            -- Re-read rather than replayed from the stored request: a week
            -- is long enough for the key to have changed, and a held request
            -- that finally goes out should name the key they hold now.
            local key = KeystoneRequests.KeyFor(name)

            if SYL.KeystoneRequestSync.SendAsk(deliverTo, request.role, key) then
                request.queued = nil
                request.sentTo = deliverTo
                request.mapID = key and key.mapID
                request.level = key and key.level
                request.at = time()
                sent = sent + 1
            end
        end
    end

    if sent > 0 then
        SYL:Print(
            "Sent " .. SYL.Utilities.Count(sent, "key request")
            .. " that had been waiting for somebody to come online."
        )
    end

    return sent
end

-- How many are still waiting to go out, for a screen that wants to say so.
function KeystoneRequests.QueuedCount()
    local store = Store()
    local total = 0

    for _, request in pairs((store and store.outgoing) or {}) do
        if request.queued then
            total = total + 1
        end
    end

    return total
end

function KeystoneRequests.GetOutgoing(name)
    local store = Store()

    return store and store.outgoing[name] or nil
end

-- The open question addressed to whoever this character belongs to.
--
-- THE LAST RESORT WHEN AN ANSWER CANNOT NAME ITS KEY, which is every answer
-- from a client on an older build. We asked Pronglez, Pringlesbop replied,
-- and without this there is no row for "Pringlesbop" and the answer is
-- dropped -- so somebody who did reply reads as never having.
--
-- PENDING ONLY, and only one. Two open questions to one person cannot be told
-- apart from a bare name, and marking the wrong one answered is worse than
-- leaving both waiting for the whisper that follows anyway.
function KeystoneRequests.OutgoingForPerson(name)
    local store = Store()

    if not store or not SYL.Players then
        return nil
    end

    local person = SYL.Players.ResolveToMain(name)
    local found

    for target, request in pairs(store.outgoing) do
        if request.status == KeystoneRequests.STATUS.PENDING
            and SYL.Players.ResolveToMain(target) == person
        then
            if found then
                return nil
            end

            found = request
        end
    end

    return found
end

-- "+15 Operation: Floodgate on Pronglez", for a screen or a chat line.
--
-- The dungeon name is asked for rather than stored: Core/Keystone.lua keeps
-- mapIDs because the name is localized and comes from the client, so a name
-- written into the database on one machine would be the wrong language on the
-- next. `owner` is dropped when it says nothing -- naming the character is
-- the point only when it might not be the obvious one.
function KeystoneRequests.DescribeKey(key, withOwner)
    if type(key) ~= "table" or not key.mapID then
        return nil
    end

    local text = "+" .. tostring(key.level or "?") .. " "
        .. tostring(SYL.Keystone.GetMapName(key.mapID) or "Unknown")

    if withOwner ~= false and key.owner then
        text = text .. " on " .. SYL.Utilities.ShortName(key.owner)
    end

    return text
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

    local entry = store.incoming[name]

    entry.status = status
    entry.answeredAt = time()

    -- Sent even if it fails to arrive: the holder has answered either way, and
    -- leaving their own list saying Waiting because the asker logged out would
    -- make them answer it twice.
    --
    -- THE ANSWER NAMES THE KEY IT ANSWERS. The asker keyed their row on the
    -- character whose key it is, and this reply may be coming from a
    -- different character of ours entirely -- so without the key in hand they
    -- would have to guess which of their open questions just got answered.
    SYL.KeystoneRequestSync.SendAnswer(name, status, {
        owner = entry.keyOwner,
        mapID = entry.mapID,
        level = entry.level,
    })

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

