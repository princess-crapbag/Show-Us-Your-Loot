-- Core/KeystoneRequestSync.lua
--
-- The wire for key requests: the prefix, the format, and what arrives.
--
-- Split from Core/KeystoneRequests.lua, which was over the size limit with
-- both in it. That file owns the rules — who may be asked, what an answer
-- means, when a request expires. This one owns the fact that any of it leaves
-- the machine, which is the part worth being able to read on its own.
--
-- WHISPER, NOT GUILD, and that is the privacy model rather than an
-- implementation detail. Core/KeystoneSync.lua broadcasts what you hold to the
-- whole guild; this sends to one named person and nothing else ever sees it.
-- Two people asking the same holder never learn about each other.
--
-- THE PREFIX IS ONLY REGISTERED WHEN THE FEATURE IS ON. A switched-off feature
-- should cost nothing and claim nothing — keystone sharing follows the same
-- rule and has a test asserting it sends nothing and registers no prefix until
-- it is turned on.

local SYL = _G.ShowUsYourLoot

local KeystoneRequestSync = {}
SYL.KeystoneRequestSync = KeystoneRequestSync

local PREFIX = "SYLKREQ"
local VERSION = "1"

local ASK = "R"
local ANSWER = "A"

-- WHICH KEY, AS ITS OWN MESSAGE, and that shape is the whole backward
-- compatibility story.
--
-- A request can now be delivered to whichever character of a person is logged
-- in, which means "your key" no longer names one thing -- so the key has to
-- travel. Packing it into the ASK's value would have been one message and one
-- broken guildie: 0.4.6 reads that value as the role, finds it in no label
-- table, and quietly asks as DPS.
--
-- Bumping VERSION is worse still. Decode drops anything that is not version
-- 1, so an older client would receive nothing at all -- and a request that
-- silently never arrives is the failure this feature exists to avoid.
--
-- So the detail goes ahead of the thing it describes, in a message an older
-- build ignores: OnMessage below returns on any kind that is not ASK or
-- ANSWER, and always has. 0.4.6 gets exactly what it gets today, with the
-- right role. Anything newer gets the key as well.
local KEY = "K"

KeystoneRequestSync.PREFIX = PREFIX
KeystoneRequestSync.ASK = ASK
KeystoneRequestSync.ANSWER = ANSWER
KeystoneRequestSync.KEY = KEY

-- Inside one value, so the envelope's own "|" split is untouched.
local KEY_FIELD = "	"

--------------------------------------------------------------------------
-- Format
--------------------------------------------------------------------------

-- Version first, so a future change can be recognized and dropped rather than
-- misread. Everything here is short enough that chunking never applies — the
-- longest payload this sends is nine characters.
function KeystoneRequestSync.Encode(kind, value)
    return table.concat({ VERSION, kind, tostring(value or "") }, "|")
end

function KeystoneRequestSync.Decode(payload)
    if type(payload) ~= "string" then
        return nil
    end

    local version, kind, value = payload:match("^(%d+)|(%a)|(.*)$")

    if version ~= VERSION then
        return nil
    end

    return kind, value
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

local function Send(target, payload)
    if not SYL.KeystoneRequests.IsEnabled() then
        return false
    end

    -- The C_ChatInfo capability check that used to sit here is gone: the queue
    -- makes it, at send time, which is the only moment it means anything.
    if type(target) ~= "string" or target == "" then
        return false
    end

    -- Queued like the guild senders. This one whispers a named person rather
    -- than a channel, but it shares the client's limit with everything else
    -- and a request that is silently discarded is a guildie who never answers.
    return SYL.SendQueue.Queue(
        PREFIX, payload, "WHISPER", target,
        function()
            return SYL.KeystoneRequests.IsEnabled()
        end
    )
end

KeystoneRequestSync.Send = Send

-- FIRST, so the receiver is holding it when the thing it describes lands.
-- Both go through SendQueue, which is first in first out, so the order they
-- are handed over is the order they arrive in.
local function SendKey(target, key)
    if type(key) ~= "table" or not key.owner or not key.mapID then
        return false
    end

    return Send(target, KeystoneRequestSync.Encode(KEY, table.concat({
        key.owner, tostring(key.mapID), tostring(key.level or ""),
    }, KEY_FIELD)))
end

KeystoneRequestSync.SendKey = SendKey

function KeystoneRequestSync.SendAsk(target, role, key)
    SendKey(target, key)

    return Send(target, KeystoneRequestSync.Encode(ASK, role))
end

function KeystoneRequestSync.SendAnswer(target, status, key)
    SendKey(target, key)

    return Send(target, KeystoneRequestSync.Encode(ANSWER, status))
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

-- One key per sender, waiting for the message it describes. Deliberately not
-- saved: it is meaningless a second after it arrives, and a stash that
-- outlived a reload would attach a stale key to the next request.
local pendingKey = {}

local function ParseKey(value)
    local owner, mapID, level = tostring(value or ""):match(
        "^(.-)	(%d+)	(%d*)$"
    )

    if not owner or owner == "" then
        return nil
    end

    return { owner = owner, mapID = tonumber(mapID), level = tonumber(level) }
end

local function TakeKey(sender)
    local key = pendingKey[sender]

    pendingKey[sender] = nil

    return key
end

local function Notify(text)
    SYL:Write(text)

    if SYL.KeysPanel and SYL.KeysPanel.Refresh then
        SYL.KeysPanel.Refresh()
    end
end

function KeystoneRequestSync.OnMessage(prefix, payload, _, sender)
    if prefix ~= PREFIX or not SYL.KeystoneRequests.IsEnabled() then
        return
    end

    if not sender or sender == SYL.Keystone.CharacterKey() then
        return
    end

    local kind, value = KeystoneRequestSync.Decode(payload)

    if not kind then
        return
    end

    local Requests = SYL.KeystoneRequests
    local store = Requests.Store()

    if not store then
        return
    end

    if kind == KEY then
        -- Held for the ASK or ANSWER immediately behind it, and for nothing
        -- else. One slot per sender, overwritten rather than queued: a second
        -- KEY with no message between them means the first never had one.
        pendingKey[sender] = ParseKey(value)

        return
    end

    if kind == ASK then
        local role = Requests.ROLE_LABELS[value] and value or "DPS"
        local key = TakeKey(sender)

        -- A second ask from the same person replaces the first rather than
        -- stacking. They are asking about one key.
        store.incoming[sender] = {
            sender = sender,
            role = role,
            status = Requests.STATUS.PENDING,
            at = time(),

            -- WHICH OF OUR CHARACTERS THEY MEAN. nil from a client on an
            -- older build, which is exactly the state this feature replaced:
            -- the alert then says "your key" and means the one on the
            -- character reading it, the same as it always did.
            keyOwner = key and key.owner,
            mapID = key and key.mapID,
            level = key and key.level,
        }

        Notify(
            SYL.colors.addon .. sender .. SYL.colors.reset
            .. " asked to run "
            .. (key and Requests.DescribeKey(key) or "your key")
            .. " as " .. (Requests.ROLE_LABELS[role] or role) .. "."
        )

        if SYL.KeyRequestAlert then
            SYL.KeyRequestAlert.Show()
        end

        return
    end

    if kind ~= ANSWER then
        return
    end

    local key = TakeKey(sender)

    -- WHICH QUESTION THIS ANSWERS, and it is no longer "the one addressed to
    -- whoever just spoke". The reply can come back from any character of
    -- theirs, so the key it names is what pins it to a row -- and only when
    -- that fails does the sender's own name stand in, which is what a client
    -- on an older build will always fall back to.
    local existing = (key and key.owner and store.outgoing[key.owner])
        or store.outgoing[sender]
        or Requests.OutgoingForPerson(sender)

    -- An answer to something never asked is dropped rather than creating a
    -- row. Otherwise anybody could put entries on somebody else's screen.
    if not existing or not Requests.STATUS_LABELS[value] then
        return
    end

    existing.status = value
    existing.answeredAt = time()

    -- Named, because the row it landed on may not carry the name of whoever
    -- spoke -- and "Pringlesbop answered" over a row reading Pronglez is the
    -- kind of thing that reads as the addon crediting the wrong person.
    local about = existing.target and existing.target ~= sender
        and (" about " .. SYL.Utilities.ShortName(existing.target) .. "'s key")
        or ""

    Notify(
        SYL.colors.addon .. sender .. SYL.colors.reset
        .. " answered" .. about .. ": "
        .. Requests.STATUS_LABELS[value] .. "."
    )
end

--------------------------------------------------------------------------
-- Switching on
--------------------------------------------------------------------------

local frame

function KeystoneRequestSync.Enable()
    if SYL.KeystoneRequests.IsEnabled() then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            KeystoneRequestSync.OnMessage(...)
        end
    end)

    frame:RegisterEvent("CHAT_MSG_ADDON")

    -- Set last. Send() and OnMessage() both check it, so flipping it before
    -- the frame exists would open a window where a message could arrive with
    -- nothing listening — and unlike the announce sync, this one has no
    -- periodic retry that would paper over it.
    SYL.KeystoneRequests.SetEnabled(true)

    return true
end

function KeystoneRequestSync.Disable()
    SYL.KeystoneRequests.SetEnabled(false)
end
