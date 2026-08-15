-- Core/AbsenceSync.lua
--
-- Telling the guild who is out, and remembering what they tell you.
--
-- ITS OWN SWITCH, AND OFF BY DEFAULT, like everything here that talks. Officer
-- sync sends drop headers to officers inside your raid; keystone sharing sends
-- one line about your own character to the guild. This sends what you have
-- typed about *other people* to the guild, which is a third thing again and
-- the reason it is a third switch.
--
-- THIS IS THE ONLY THING THIS ADDON SENDS THAT IS A CLAIM RATHER THAN AN
-- OBSERVATION. A keystone is a fact about the sender's own bags. A drop header
-- is something everyone in the raid watched happen. "Talestra is out next
-- week" is one person's assertion about somebody else, and anybody running the
-- addon can make one. So every absence carries who set it, everywhere it is
-- shown — Aimee's call, and the reason the calendar prints "set by" on every
-- line. Attribution instead of authorization: the addon records and shows its
-- working, it does not decide who is allowed to speak.
--
-- EACH CLIENT OWNS WHAT IT WROTE. A client broadcasts the complete set of
-- absences it authored, and a receiver replaces everything it holds from that
-- author with what arrived. Removal then needs no message of its own: an
-- absence that has been deleted simply is not in the next set, and a client
-- that has been away gets the current truth rather than a replay of edits.
-- Tombstones, which is the other way to do this, have to be kept forever and
-- are wrong the moment one is missed.
--
-- THE SENDER DECIDES THE AUTHOR, NOT THE PAYLOAD. Received absences are
-- stamped with the name the addon channel reports, so a client cannot claim to
-- be broadcasting on somebody else's behalf and cannot overwrite their set.
-- Without this, "each client owns what it wrote" would be enforced by nothing.

local SYL = _G.ShowUsYourLoot

local AbsenceSync = {}
SYL.AbsenceSync = AbsenceSync

-- Its own prefix, so a client running an older build never hands these to a
-- parser written for something else.
local PREFIX = "SYLABS"
local VERSION = "1"

local REQUEST = "?"

-- Addon messages cap at 255 bytes. One absence per message keeps the framing
-- trivial and the arithmetic obvious; a guild's worth of absences is a handful
-- of messages, not a stream.
local MAX_REASON = 60

local frame
local enabled = false

local ANSWER_THROTTLE_SECONDS = 20
local lastAnswerAt = 0

-- Sets being assembled, keyed by sender. A set is only committed once every
-- piece of it has arrived, so a half-delivered broadcast never deletes
-- somebody's absences and replaces them with nothing.
local pending = {}

local function CanSend()
    return C_ChatInfo
        and C_ChatInfo.SendAddonMessage
        and IsInGuild()
        and true
        or false
end

local function Send(payload)
    if not CanSend() then
        return false
    end

    pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, "GUILD")

    return true
end

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

-- Tab separated, because an absence id already contains the pipe this addon
-- uses elsewhere and a reason is free text somebody typed.
local function Clean(text, limit)
    text = tostring(text or ""):gsub("[\t\n|]", " ")

    if limit and #text > limit then
        text = text:sub(1, limit)
    end

    return text
end

function AbsenceSync.Encode(serial, index, count, absence)
    local body = ""

    if absence then
        body = table.concat({
            Clean(absence.id),
            Clean(absence.name),
            Clean(absence.from),
            Clean(absence.to),
            Clean(absence.reason, MAX_REASON),
        }, "\t")
    end

    return table.concat({
        VERSION, tostring(serial), tostring(index), tostring(count), body
    }, "\t")
end

-- Returns serial, index, count, absence. The absence is nil for the empty-set
-- marker, which is a real message and the one that clears somebody's list.
function AbsenceSync.Decode(payload)
    if type(payload) ~= "string" then
        return nil
    end

    local version, serial, index, count, body =
        payload:match("^(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")

    if version ~= VERSION then
        return nil
    end

    serial = tonumber(serial)
    index = tonumber(index)
    count = tonumber(count)

    if not serial or not index or not count then
        return nil
    end

    if count == 0 then
        return serial, index, count, nil
    end

    local id, name, from, to, reason =
        body:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.*)$")

    if not id or id == "" or not name or name == "" or not from then
        return nil
    end

    return serial, index, count, {
        id = id,
        name = name,
        from = from,
        to = (to ~= "" and to) or from,
        reason = (reason ~= "" and reason) or nil,
    }
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

-- Only what this client wrote. Somebody else's absences are theirs to
-- broadcast, and re-sending them would make every client an echo of every
-- other one.
function AbsenceSync.Own()
    local mine = {}
    local author = SYL.RaidSchedule.Author()

    for _, absence in ipairs(SYL.RaidSchedule.AllAbsences() or {}) do
        if absence.setBy == author and absence.id then
            table.insert(mine, absence)
        end
    end

    return mine
end

local serial = 0

function AbsenceSync.Announce()
    if not enabled or not CanSend() then
        return false
    end

    local mine = AbsenceSync.Own()

    serial = serial + 1

    -- The empty set is sent, not skipped. Somebody who cleared their last
    -- absence has to be able to say so, and silence would leave it standing on
    -- every other client forever.
    if #mine == 0 then
        Send(AbsenceSync.Encode(serial, 0, 0, nil))

        return true
    end

    for index, absence in ipairs(mine) do
        Send(AbsenceSync.Encode(serial, index, #mine, absence))
    end

    return true
end

function AbsenceSync.Request()
    if not enabled or not CanSend() then
        return false
    end

    Send(REQUEST)

    return true
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

-- Replaces everything held from this sender. See the header: the sender owns
-- what it wrote, so their broadcast is the whole truth about their absences
-- and anything of theirs not in it has been removed.
function AbsenceSync.Commit(sender, absences)
    if not sender then
        return 0
    end

    SYL.RaidSchedule.ReplaceAbsencesFrom(sender, absences or {})

    return #(absences or {})
end

local function Accumulate(sender, serialID, index, count, absence)
    if count == 0 then
        pending[sender] = nil

        return AbsenceSync.Commit(sender, {})
    end

    local set = pending[sender]

    -- A new serial from the same sender supersedes whatever was half
    -- assembled: they have said something newer and the old set is stale.
    if not set or set.serial ~= serialID then
        set = { serial = serialID, count = count, items = {}, seen = 0 }
        pending[sender] = set
    end

    if not set.items[index] then
        set.seen = set.seen + 1
    end

    set.items[index] = absence

    if set.seen < set.count then
        return nil
    end

    local ordered = {}

    for position = 1, set.count do
        if set.items[position] then
            table.insert(ordered, set.items[position])
        end
    end

    pending[sender] = nil

    return AbsenceSync.Commit(sender, ordered)
end

-- One message from one sender. Exported because the interesting behaviour is
-- what happens *between* the messages of a set — a fragment must never reach
-- the store — and that is unreachable through an event handler.
--
-- Returns how many absences were committed, or nil when the set is still
-- being assembled.
function AbsenceSync.Receive(sender, payload)
    -- Our own broadcast comes back to us. RaidSchedule is the authority on
    -- what this client wrote, so committing our own set would replace those
    -- absences with a decoded copy of themselves and lose the fields that do
    -- not travel. Same guard, and the same comparison, as KeystoneSync.
    if not sender or sender == SYL.RaidSchedule.Author() then
        return nil
    end

    local serialID, index, count, absence = AbsenceSync.Decode(payload)

    if not serialID then
        return nil
    end

    return Accumulate(sender, serialID, index, count, absence)
end

local function OnMessage(prefix, payload, _, sender)
    if prefix ~= PREFIX or not enabled then
        return
    end

    if payload == REQUEST then
        if sender == SYL.RaidSchedule.Author() then
            return
        end

        local now = time()

        if now - lastAnswerAt < ANSWER_THROTTLE_SECONDS then
            return
        end

        lastAnswerAt = now

        AbsenceSync.Announce()

        return
    end

    if AbsenceSync.Receive(sender, payload) and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

--------------------------------------------------------------------------
-- Switching on
--------------------------------------------------------------------------

function AbsenceSync.IsEnabled()
    return enabled
end

function AbsenceSync.Enable()
    if enabled then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            OnMessage(...)
        end
    end)

    frame:RegisterEvent("CHAT_MSG_ADDON")

    enabled = true

    return true
end

-- Called whenever this client's own absences change, so the guild sees a
-- removal as promptly as an addition.
function AbsenceSync.OnOwnAbsencesChanged()
    if not enabled then
        return
    end

    AbsenceSync.Announce()
end
