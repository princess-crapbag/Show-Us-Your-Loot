-- Core/HistorySync.lua
--
-- Handing a season of loot to one other officer, once they say yes.
--
-- WHY IT IS NOT A BROADCAST. Everything else this addon shares is small and
-- goes to everyone: a roster is nine names, a keystone is one line. A season
-- is 130 drops with 2,511 rolls under them, which is 983 addon messages off
-- Aimee's own database -- about four minutes of trickle. Sending
-- that to a whole guild because one officer needed it is not sharing, it is
-- a denial of service with good intentions.
--
-- SO IT IS ADDRESSED, ASKED FOR, AND ANSWERED. The shape is RCLootCouncil's,
-- because they solved this exact problem years ago and their Modules/Sync.lua
-- is the reference: the sender picks one name and holds the data; a request
-- goes out first; the receiver is shown what is being offered and says yes or
-- no; only then does anything travel. A decline comes back as a decline
-- rather than as silence, so the sender is never left watching a bar that
-- goes nowhere.
--
-- WHAT WE DO DIFFERENTLY, and it is one thing. RCLootCouncil auto-declines
-- unless the receiver already has the sync window open -- reasonable for them,
-- because both people are expected to be arranging it in voice chat. Here the
-- receiver is an officer who has never heard of this window, so an offer
-- raises a prompt on its own. It is still a question; it just does not require
-- the answerer to have guessed it was coming.
--
-- THE SEND IS PACED BY THIS FILE, not dumped into the shared queue. SendQueue
-- caps at 200 and drops the overflow with a debug line -- 983 messages would
-- lose 783 of them and the receiver would sit on a set that never completes.
-- So the outbox lives here and feeds the queue one message at a time, which
-- also gives an honest progress number: what is actually on the wire, not
-- what has been handed to somebody else's list.
--
-- ONE TRANSFER AT A TIME, in each direction. Two overlapping sends would
-- interleave on the wire and both would be slower; two overlapping receives
-- cannot be told apart at all, since a chunk carries no sender-side session.

local SYL = _G.ShowUsYourLoot

local HistorySync = {}
SYL.HistorySync = HistorySync

local PREFIX = "SYLHIST"
local VERSION = "1"

-- The four things one client says to another. One letter each, because every
-- byte of the envelope is a byte the payload does not get.
local OFFER = "O"
local ACCEPT = "Y"
local DECLINE = "N"
local DATA = "D"
local DONE = "E"

HistorySync.PREFIX = PREFIX

-- Matches SendQueue, which picked it for the same reason: four a second is
-- far under what the client throws away, and the two together are still
-- inside the limit because this feeds that one rather than racing it.
HistorySync.INTERVAL = 0.25

-- Chunking is this file's own, rather than SyncTransport's, because that one
-- is bolted to the RAID channel and to the `sync` feature switch. 255 is the
-- hard cap; the envelope costs about 20 and the margin covers a longer serial
-- than expected. Being wrong here truncates silently.
local CHUNK_SIZE = 200

local outbox = {}
local outboxTarget
local outboxSeason
local sentCount = 0
local totalCount = 0
local draining = false

local incoming
local pendingOffer

local frame
local listening = false

--------------------------------------------------------------------------
-- Who we are and whether we can talk
--------------------------------------------------------------------------

local function Author()
    return SYL.Utilities.GetPlayerFullName()
end

local function CanSend()
    return C_ChatInfo and C_ChatInfo.SendAddonMessage and true or false
end

local function Whisper(target, payload)
    if not CanSend() or not target then
        return false
    end

    return SYL.SendQueue.Queue(PREFIX, payload, "WHISPER", target, CanSend)
end

--------------------------------------------------------------------------
-- What is on offer
--------------------------------------------------------------------------

-- The drops worth sending from a season: everything except what the owner has
-- taken out of the maths themselves. A drop somebody excluded on purpose is a
-- decision about their own database, and pushing it into somebody else's is
-- the one thing a transfer must not do.
function HistorySync.Records(season)
    local records = {}

    for _, drop in ipairs((season and season.drops) or {}) do
        if drop.id and not drop.excludedFromAnalytics then
            table.insert(records, drop)
        end
    end

    return records
end

-- What the offer says, and what the send window shows before anybody presses
-- anything. Counted rather than estimated: "about a minute" for something
-- that takes four is how a progress bar loses its credibility on first use.
function HistorySync.Describe(season)
    local records = HistorySync.Records(season)
    local credited = 0
    local messages = 0

    for _, record in ipairs(records) do
        if record.creditOverride then
            credited = credited + 1
        end

        local size = #SYL.HistoryPayload.Encode(record)

        messages = messages + math.max(1, math.ceil(size / CHUNK_SIZE))
    end

    return {
        seasonName = (season and season.name) or "this season",
        drops = #records,
        credited = credited,
        messages = messages,
        seconds = math.floor(messages * HistorySync.INTERVAL),
    }
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

local function Encode(serial, index, count, data)
    return table.concat(
        { VERSION, DATA, tostring(serial), tostring(index),
          tostring(count), data },
        "\t"
    )
end

local function Chunk(text)
    local chunks = {}
    local position = 1

    while position <= #text do
        table.insert(chunks, text:sub(position, position + CHUNK_SIZE - 1))

        position = position + CHUNK_SIZE
    end

    if #chunks == 0 then
        chunks[1] = ""
    end

    return chunks
end

local Drain

-- One message onto the shared queue per tick. See the header: handing all 789
-- to SendQueue at once loses everything past its 200th.
Drain = function()
    local payload = table.remove(outbox, 1)

    if not payload then
        draining = false

        if outboxTarget and totalCount > 0 then
            Whisper(outboxTarget, VERSION .. "\t" .. DONE)

            SYL:Print(
                "Finished sending " .. tostring(outboxSeason) .. " to "
                .. SYL.Utilities.ShortName(outboxTarget) .. "."
            )
        end

        outboxTarget = nil

        return false
    end

    Whisper(outboxTarget, payload)

    sentCount = sentCount + 1

    if C_Timer and C_Timer.After then
        C_Timer.After(HistorySync.INTERVAL, Drain)
    end

    return true
end

-- Exported for the same reason SendQueue.Drain is: C_Timer cannot be driven
-- from a test, and the interesting behavior is what happens between two sends.
HistorySync.Drain = Drain

-- Fills the outbox. Nothing leaves until the other side says yes -- this is
-- what is HELD, and Begin is what starts it moving.
function HistorySync.Prepare(target, season)
    local records = HistorySync.Records(season)

    outbox = {}
    outboxTarget = nil
    outboxSeason = (season and season.name) or "this season"
    sentCount = 0
    totalCount = 0

    local serial = 0

    for _, record in ipairs(records) do
        serial = serial + 1

        local chunks = Chunk(SYL.HistoryPayload.Encode(record))

        for index, data in ipairs(chunks) do
            table.insert(outbox, Encode(serial, index, #chunks, data))
        end
    end

    totalCount = #outbox

    return totalCount
end

function HistorySync.Offer(target, season)
    if not target or target == Author() then
        return false, "pick somebody other than yourself"
    end

    if HistorySync.IsSending() then
        return false, "a transfer is already going out"
    end

    if not CanSend() then
        return false, "this client cannot send addon messages right now"
    end

    local summary = HistorySync.Describe(season)

    if summary.drops == 0 then
        return false, "there is nothing recorded in this season yet"
    end

    HistorySync.Prepare(target, season)

    -- The offer names what is coming, so the other end can show it rather
    -- than asking somebody to accept an unknown quantity.
    Whisper(target, table.concat({
        VERSION, OFFER, summary.seasonName, tostring(summary.drops),
        tostring(summary.credited), tostring(totalCount),
    }, "\t"))

    HistorySync.awaiting = target

    return true, summary
end

-- They said yes.
function HistorySync.Begin(target)
    if HistorySync.awaiting ~= target or #outbox == 0 then
        return false
    end

    HistorySync.awaiting = nil
    outboxTarget = target
    sentCount = 0

    if draining then
        return true
    end

    draining = true

    Drain()

    return true
end

function HistorySync.Stop()
    outbox = {}
    outboxTarget = nil
    HistorySync.awaiting = nil

    return true
end

function HistorySync.IsSending()
    return outboxTarget ~= nil or HistorySync.awaiting ~= nil
end

-- Sent, total. Both, because a percentage on its own cannot say how long is
-- left and "96 of 201" can.
function HistorySync.Progress()
    return sentCount, totalCount
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

function HistorySync.PendingOffer()
    return pendingOffer
end

-- Yes. Everything from here is the sender's pace, not ours.
function HistorySync.AcceptOffer()
    if not pendingOffer then
        return false
    end

    incoming = { from = pendingOffer.source, records = {}, pieces = {} }

    Whisper(pendingOffer.source, VERSION .. "\t" .. ACCEPT)

    pendingOffer = nil

    return true
end

function HistorySync.DeclineOffer()
    if not pendingOffer then
        return false
    end

    Whisper(pendingOffer.source, VERSION .. "\t" .. DECLINE)

    local source = pendingOffer.source

    pendingOffer = nil

    return true, source
end

-- One data message. Chunks of one record arrive in order under one serial;
-- a record is decoded when its last chunk lands, for the same reason a roster
-- set commits only when complete -- half a record is not a record.
function HistorySync.ReceiveData(sender, serial, index, count, data)
    if not incoming or incoming.from ~= sender then
        return nil
    end

    local set = incoming.pieces

    if set.serial ~= serial then
        set.serial = serial
        set.parts = {}
        set.count = count
    end

    set.parts[index] = data

    for position = 1, count do
        if set.parts[position] == nil then
            return nil
        end
    end

    local record = SYL.HistoryPayload.Decode(table.concat(set.parts))

    set.serial = nil
    set.parts = {}

    if record then
        table.insert(incoming.records, record)
    end

    return record
end

-- Written into the season in one go at the end rather than drop by drop, so a
-- transfer that stops halfway leaves the database exactly as it was instead of
-- a third merged. Returns added, updated, skipped.
function HistorySync.Commit()
    if not incoming then
        return 0, 0, 0
    end

    local season = SYL.GetActiveSeason()
    local records = incoming.records

    incoming = nil

    if not season then
        return 0, 0, 0
    end

    local added, updated, skipped = SYL.HistoryPayload.Merge(season, records)

    if added > 0 or updated > 0 then
        SYL.LootHistoryStore.RebuildIndex()

        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end

    return added, updated, skipped
end

function HistorySync.IsReceiving()
    return incoming ~= nil
end

--------------------------------------------------------------------------
-- The wire
--------------------------------------------------------------------------

-- Guild members only, the same test RosterSync makes and for the same reason:
-- a whisper prefix is reachable by anybody on the server, and this one ends in
-- rows being written into a database.
local function FromGuildMember(sender)
    if not sender then
        return false
    end

    local shortName = sender:match("^([^-]+)")

    return SYL.Guild.IsMember(nil, shortName)
        or SYL.Guild.IsMember(nil, sender)
end

function HistorySync.OnMessage(prefix, payload, _, sender)
    if prefix ~= PREFIX or not sender or sender == Author() then
        return
    end

    if not FromGuildMember(sender) then
        return
    end

    local version, kind, rest = payload:match("^(%d+)\t(%a)\t?(.*)$")

    if version ~= VERSION then
        return
    end

    if kind == OFFER then
        local seasonName, drops, credited, messages =
            rest:match("^(.-)\t(%d+)\t(%d+)\t(%d+)$")

        if not seasonName then
            return
        end

        -- A transfer already running is not interrupted by a second offer.
        if incoming then
            Whisper(sender, VERSION .. "\t" .. DECLINE)

            return
        end

        pendingOffer = {
            source = sender,
            seasonName = seasonName,
            drops = tonumber(drops),
            credited = tonumber(credited),
            messages = tonumber(messages),
        }

        if SYL.HistoryPrompt then
            SYL.HistoryPrompt.Show()
        end

        return
    end

    if kind == ACCEPT then
        HistorySync.Begin(sender)

        return
    end

    if kind == DECLINE then
        if HistorySync.awaiting == sender or outboxTarget == sender then
            HistorySync.Stop()

            -- Said out loud. A decline that looked like silence would leave
            -- somebody watching a bar that never moves and pressing send
            -- again, which is the failure RCLootCouncil names in its own
            -- decline reasons.
            SYL:Print(
                SYL.Utilities.ShortName(sender)
                .. " declined the loot history."
            )
        end

        return
    end

    if kind == DATA then
        local serial, index, count, data =
            rest:match("^(%d+)\t(%d+)\t(%d+)\t(.*)$")

        if serial then
            HistorySync.ReceiveData(
                sender, tonumber(serial), tonumber(index),
                tonumber(count), data
            )
        end

        return
    end

    if kind == DONE then
        local added, updated = HistorySync.Commit()

        SYL:Print(
            "Loot history from " .. SYL.Utilities.ShortName(sender) .. ": "
            .. added .. " new drops, " .. updated .. " credit corrections."
        )
    end
end

function HistorySync.Listen()
    if listening then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            HistorySync.OnMessage(...)
        end
    end)

    frame:RegisterEvent("CHAT_MSG_ADDON")

    listening = true

    return true
end

function HistorySync.IsListening()
    return listening
end
