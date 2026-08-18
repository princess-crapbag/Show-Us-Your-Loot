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

KeystoneRequestSync.PREFIX = PREFIX
KeystoneRequestSync.ASK = ASK
KeystoneRequestSync.ANSWER = ANSWER

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

function KeystoneRequestSync.SendAsk(target, role)
    return Send(target, KeystoneRequestSync.Encode(ASK, role))
end

function KeystoneRequestSync.SendAnswer(target, status)
    return Send(target, KeystoneRequestSync.Encode(ANSWER, status))
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

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

    if kind == ASK then
        local role = Requests.ROLE_LABELS[value] and value or "DPS"

        -- A second ask from the same person replaces the first rather than
        -- stacking. They are asking about one key.
        store.incoming[sender] = {
            sender = sender,
            role = role,
            status = Requests.STATUS.PENDING,
            at = time(),
        }

        Notify(
            SYL.colors.addon .. sender .. SYL.colors.reset
            .. " asked to run your key as "
            .. (Requests.ROLE_LABELS[role] or role)
            .. ". " .. SYL.colors.highlight .. "/syl keys"
            .. SYL.colors.reset .. " to answer."
        )

        return
    end

    if kind ~= ANSWER then
        return
    end

    local existing = store.outgoing[sender]

    -- An answer to something never asked is dropped rather than creating a
    -- row. Otherwise anybody could put entries on somebody else's screen.
    if not existing or not Requests.STATUS_LABELS[value] then
        return
    end

    existing.status = value
    existing.answeredAt = time()

    Notify(
        SYL.colors.addon .. sender .. SYL.colors.reset
        .. " answered: " .. Requests.STATUS_LABELS[value] .. "."
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
