-- Core/SendQueue.lua
--
-- One outgoing addon message at a time, for everything that talks to the guild.
--
-- THE BUG THIS EXISTS FOR. Logging in fired twenty-four addon messages inside
-- a single frame: one request and eight absences, one request and thirteen
-- raiders, and a keystone. The client rate-limits addon traffic, prints "The
-- number of messages that can be sent is limited, please wait to send another
-- message", and throws the overflow away.
--
-- Dropping messages is bad everywhere and fatal for a set. RosterSync and
-- AbsenceSync both send one entry per message and commit only once every piece
-- of a set has arrived — which is right, because a fragment would show a team
-- with people missing. But it means a single discarded message leaves the set
-- permanently half-assembled: the roster never lands, nothing errors, and the
-- receiving screen looks exactly like a roster nobody has set up. Aimee found
-- it as "it's not working", which is the only symptom there is.
--
-- SHARED, NOT ONE QUEUE PER MODULE. The limit is per client, so three modules
-- each politely pacing themselves would still add up to a burst. There is one
-- queue and everything that sends to the guild goes through it.
--
-- Core/SyncTransport.lua reached all of this first and says so at length —
-- "the messages most likely to be thrown away were the ones from the moment
-- this addon exists to record" — and keeps its own queue for RAID-channel
-- chunks. That one is left alone: it is a different channel, it only runs
-- during a pull, and it already works. The two together are still inside the
-- limit.
--
-- THE GATE IS RE-CHECKED AT SEND TIME, not only when something is queued. A
-- feature can be switched off, or a guild left, in the seconds between a
-- message being queued and its turn coming round, and none of those should
-- still put it on the wire. Callers pass the same predicate they would have
-- tested themselves.
--
-- DRAIN IS PUBLIC because C_Timer cannot be driven from a test. The
-- interesting behaviour is what happens *between* two sends, and an internal
-- timer callback is unreachable — the same reason AbsenceSync.Receive is
-- exported.

local SYL = _G.ShowUsYourLoot

local SendQueue = {}
SYL.SendQueue = SendQueue

-- Matches SyncTransport, which picked it for the same reason and has been
-- shipping on it. Four a second is far under the limit and still empties a
-- login's worth in a few seconds.
SendQueue.INTERVAL = 0.25

-- Roughly a minute of backlog. A queue longer than this means something is
-- wrong upstream, and silently growing it forever is worse than saying so.
SendQueue.MAX = 200

local queue = {}
local scheduled = false

function SendQueue.Pending()
    return #queue
end

-- Tests only. Nothing in the addon empties the queue without sending it.
function SendQueue.Reset()
    queue = {}
    scheduled = false
end

local ScheduleNext

-- NOTHING IS EVER SENT STRAIGHT FROM Queue, and the first version of this file
-- got that wrong in a way that looked right. It sent immediately whenever the
-- queue happened to be empty and only paced what was left behind — but a
-- roster is queued one raider at a time, and each call emptied the queue
-- before the next arrived, so all thirteen still went out in the same frame.
-- The queue existed, the tests passed, and the burst was untouched.
--
-- Every message now waits its turn, including the first. A lone keystone is
-- delayed a quarter second, which nobody can perceive and which is the entire
-- cost of the guarantee that this cannot burst again.
function SendQueue.Drain()
    local entry = table.remove(queue, 1)

    if not entry then
        return false
    end

    -- The gate, re-checked. A message whose reason for existing has gone away
    -- between queueing and its turn is dropped rather than sent late.
    if (not entry.gate or entry.gate() == true)
        and C_ChatInfo and C_ChatInfo.SendAddonMessage
    then
        -- pcall because a throttled or malformed send raises rather than
        -- returning, and nothing here is worth taking the addon down for.
        pcall(
            C_ChatInfo.SendAddonMessage,
            entry.prefix, entry.payload, entry.channel, entry.target
        )
    end

    ScheduleNext()

    return true
end

-- One timer in flight at a time. Re-armed after every send while anything is
-- still waiting, so the queue drains at a steady INTERVAL rather than in
-- whatever bursts the callers happen to arrive in.
ScheduleNext = function()
    if scheduled or #queue == 0 then
        return false
    end

    if not C_Timer or not C_Timer.After then
        return false
    end

    scheduled = true

    C_Timer.After(SendQueue.INTERVAL, function()
        scheduled = false

        SendQueue.Drain()
    end)

    return true
end

function SendQueue.Queue(prefix, payload, channel, target, gate)
    if type(prefix) ~= "string" or type(payload) ~= "string" then
        return false
    end

    if #queue >= SendQueue.MAX then
        SYL:DebugPrint(
            "Send queue full, dropped a " .. prefix .. " message."
        )

        return false
    end

    table.insert(queue, {
        prefix = prefix,
        payload = payload,
        channel = channel or "GUILD",
        target = target,
        gate = gate,
    })

    ScheduleNext()

    return true
end
