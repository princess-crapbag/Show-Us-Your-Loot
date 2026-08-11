-- Core/SyncTransport.lua
--
-- Getting bytes to the other officers, and back.
--
-- Split from Core/Sync.lua, which knows what a drop record is. This file does
-- not: it moves payloads and has no opinion about what is in them.
--
-- Two problems live here, and both are about the wire rather than the data.
--
-- ADDON MESSAGES CAP AT 255 BYTES. Everything above that has to be split and
-- put back together, and until it was, every phase in NOTES.md that needs to
-- send more than a drop header was blocked on it.
--
-- THE SERVER RATE-LIMITS THEM. A boss dropping five items produced five
-- immediate sends in the busiest second of a raid, which is exactly when the
-- server discards what arrives over the line. So there is a queue and a
-- timer, and the gate is re-checked at send time rather than only at queue
-- time: a pull ends, a raid breaks up, sync gets switched off.
--
-- WHAT IS SENT IS NOT DECIDED HERE and is deliberately unchanged by the
-- chunking. See the list at the top of Core/Sync.lua; widening it is a
-- decision somebody should take on purpose rather than inherit from a
-- transport that got roomier.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Transport = {}
SYL.SyncTransport = Transport

local PREFIX = "SYLOOT"
local SEPARATOR = "	"

local frame
local registered = false

-- Set by Core/Sync.lua. Called with a reassembled payload and its sender.
Transport.onPayload = nil

local function IsEnabled()
    return SYL.Features.IsEnabled("sync")
end

-- -- Addon messages cap at 255 bytes. Everything above assumes a drop header
-- fits in one, which it does — and that assumption is what blocks NOTES
-- phases 2, 3, 5 and 6, every one of which needs to send something larger
-- than a header.
--
-- So this is a transport: a payload of any size goes out as numbered pieces
-- and is put back together at the other end.
--
-- WHAT IS SENT IS DELIBERATELY UNCHANGED. This makes larger messages
-- possible; it does not make any. The list at the top of this file — no roll
-- lists, no chat loot, nothing about characters not involved in the drop —
-- still holds, and widening it is a separate decision that somebody should
-- take on purpose rather than inherit from a transport change.
--
-- The envelope is `PROTOCOL \t id \t index \t count \t data`, so a receiver
-- running the old single-message version sees a protocol field it recognizes
-- followed by fields it does not, and Decode returns nil rather than
-- misreading it.
local CHUNK_PROTOCOL = "C1"

-- 255 is the hard cap. The envelope costs about 20 and the margin covers a
-- longer message id than expected; being wrong here truncates silently.
local CHUNK_SIZE = 200

-- Incomplete sets are dropped after this. A sender who reloads mid-message
-- never sends the rest, and holding the pieces forever is a slow leak.
local REASSEMBLY_SECONDS = 30

local nextMessageID = 0

-- sender -> id -> { count, received, pieces, at }
local inbound = {}

local function SplitIntoChunks(payload)
    local chunks = {}
    local total = #payload

    local count = math.max(1, math.ceil(total / CHUNK_SIZE))

    for index = 1, count do
        local first = (index - 1) * CHUNK_SIZE + 1

        table.insert(chunks, payload:sub(first, first + CHUNK_SIZE - 1))
    end

    return chunks
end

local function ChunkEnvelope(messageID, index, count, data)
    return table.concat({
        CHUNK_PROTOCOL,
        tostring(messageID),
        tostring(index),
        tostring(count),
        data,
    }, SEPARATOR)
end

-- Returns id, index, count, data, or nil when this is not a chunk envelope.
--
-- Split on a limited number of separators, because the payload itself may
-- contain them — it is another protocol's message and none of its business
-- what this one uses as a delimiter.
local function ParseChunk(message)
    local protocol, messageID, index, count, data =
        message:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")

    if protocol ~= CHUNK_PROTOCOL then
        return nil
    end

    index = tonumber(index)
    count = tonumber(count)

    if not index or not count or index < 1 or count < 1 or index > count then
        return nil
    end

    return messageID, index, count, data
end

local function ForgetStale(now)
    for sender, messages in pairs(inbound) do
        for id, entry in pairs(messages) do
            if now - entry.at > REASSEMBLY_SECONDS then
                messages[id] = nil
            end
        end

        if not next(messages) then
            inbound[sender] = nil
        end
    end
end

-- Returns the reassembled payload once the last piece arrives, else nil.
local function Reassemble(sender, messageID, index, count, data)
    local now = time()

    ForgetStale(now)

    inbound[sender] = inbound[sender] or {}

    local entry = inbound[sender][messageID]

    if not entry then
        entry = { count = count, received = 0, pieces = {}, at = now }
        inbound[sender][messageID] = entry
    end

    -- A repeat of a piece already held is not a second piece.
    if entry.pieces[index] then
        return nil
    end

    entry.pieces[index] = data
    entry.received = entry.received + 1
    entry.at = now

    if entry.received < entry.count then
        return nil
    end

    local parts = {}

    for position = 1, entry.count do
        table.insert(parts, entry.pieces[position])
    end

    inbound[sender][messageID] = nil

    return table.concat(parts)
end

--------------------------------------------------------------------------
-- Sending, one at a time
--------------------------------------------------------------------------
--
-- A boss drops five items at once and every one of them resolved into an
-- immediate SendAddonMessage, back to back, in the busiest second of a raid.
-- The server rate-limits addon traffic and drops what arrives over the line —
-- so the messages most likely to be thrown away were the ones from the moment
-- this addon exists to record. A client that keeps it up gets disconnected.
--
-- Most addons reach for ChatThrottleLib here. This one bundles no libraries,
-- and the requirement is small enough not to need it: a queue and a timer.
--
-- The gate is re-checked at send time rather than only at queue time. A pull
-- can end, the raid can break up, or sync can be switched off in the seconds
-- between a drop resolving and its turn coming round, and none of those
-- should still put a message on the wire.
local SEND_INTERVAL = 0.25

-- Roughly a minute of backlog. A queue longer than this means something is
-- wrong upstream, and silently growing it forever is worse than saying so.
local MAX_QUEUE = 200

local queue = {}
local draining = false

local function CanSend()
    return IsEnabled()
        and IsInRaid()
        and C_ChatInfo
        and C_ChatInfo.SendAddonMessage
        and true
        or false
end

local function Drain()
    local payload = table.remove(queue, 1)

    if not payload then
        draining = false

        return
    end

    if CanSend() then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "RAID")
    end

    C_Timer.After(SEND_INTERVAL, Drain)
end

-- Queues a payload of any length, split across as many messages as it takes.
function Transport.Send(payload, describe)
    local chunks = SplitIntoChunks(payload)

    if #queue + #chunks > MAX_QUEUE then
        SYL:DebugPrint("Sync queue full, dropped: " .. tostring(describe))

        return false
    end

    nextMessageID = nextMessageID + 1

    local messageID = tostring(nextMessageID)

    for index, data in ipairs(chunks) do
        table.insert(
            queue, ChunkEnvelope(messageID, index, #chunks, data)
        )
    end

    if not draining then
        draining = true

        Drain()
    end

    return true
end

function Transport.IsRegistered()
    return registered
end

local function OnAddonMessage(prefix, payload, channel, sender)
    if prefix ~= PREFIX or not IsEnabled() then
        return
    end

    -- Ignore our own broadcast coming back around.
    if sender and Utilities.GetPlayerFullName() == sender then
        return
    end

    -- Guild members only. Anyone else in the raid is not a source this addon
    -- has any reason to trust.
    local shortName = sender and sender:match("^([^-]+)") or nil

    if not SYL.Guild.IsMember(nil, shortName)
        and not SYL.Guild.IsMember(nil, sender)
    then
        return
    end

    -- Every message is an envelope now. Anything else is either a much older
    -- version of this addon or not ours at all, and is ignored rather than
    -- guessed at.
    local messageID, index, count, data = ParseChunk(payload)

    if not messageID then
        return
    end

    local complete = Reassemble(sender, messageID, index, count, data)

    if not complete then
        return
    end

    -- Complete. What it means is somebody else's job.
    if Transport.onPayload then
        Transport.onPayload(complete, sender)
    end
end

function Transport.Enable()
    if registered then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")

    frame:SetScript("OnEvent", function(_, _, ...)
        OnAddonMessage(...)
    end)

    registered = true

    return true
end
