-- Core/RosterReceipts.lua
--
-- Who is actually using the raid team you sent, and when they said so.
--
-- WHY THIS EXISTS. Aimee, after the consent model shipped: "how do i know if
-- the other people received my roster?" She could not, and neither could
-- anybody else. Pressing Send printed "Sent your raid team of 11 to the
-- guild", which says only that the messages left this client. Nothing came
-- back, ever.
--
-- That gap is the whole reason this conversation started. "The raid roster
-- isn't syncing to the officer" was TRUE, and there was no way to find that
-- out from her own screen -- so a broken feature and a working one looked
-- exactly alike, and the way she eventually noticed was two strangers
-- appearing on her board. A share with no receipt is a share you have to take
-- on faith, and faith is what let this run for a whole raid week.
--
-- ONE LINE BACK, ON ACCEPT ONLY, AND NOT PER BROADCAST. The obvious version
-- -- everyone confirms every roster they receive -- turns one officer ticking
-- a box into a whisper from every guildie who has the addon, every time. So a
-- client speaks up twice in its life: when it starts using your roster, and
-- when it stops. Between those two it is silent, and the answer holds.
--
-- WHICH IS ALSO WHY STOPPING HAS TO REPORT. A count that only ever goes up is
-- worse than no count: it becomes a number Aimee would quote in Discord that
-- nobody has been using for a month. Clearing a shared roster says so.
--
-- WHISPERED, NOT BROADCAST. It is one person's answer to one person's
-- question, and it names somebody's choice about somebody else's roster.
-- The guild channel is the wrong room for that.

local SYL = _G.ShowUsYourLoot

local RosterReceipts = {}
SYL.RosterReceipts = RosterReceipts

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.rosterReceipts = ShowUsYourLootDB.rosterReceipts or {}

    return ShowUsYourLootDB.rosterReceipts
end

RosterReceipts.Store = Store

-- Somebody has started using our roster. Keyed by their full name, so the
-- same person confirming twice is one row rather than two.
function RosterReceipts.Record(sender, count)
    local store = Store()

    if not store or type(sender) ~= "string" or sender == "" then
        return false
    end

    local existing = store[sender]

    store[sender] = {
        count = tonumber(count) or 0,
        at = time(),

        -- Kept from the first confirmation rather than overwritten, so the
        -- screen can say how long somebody has been on your roster rather
        -- than only when they last said so.
        since = (existing and existing.since) or time(),
    }

    return true
end

function RosterReceipts.Remove(sender)
    local store = Store()

    if not store or not sender or not store[sender] then
        return false
    end

    store[sender] = nil

    return true
end

function RosterReceipts.Get(sender)
    local store = Store()

    return (store and sender and store[sender]) or nil
end

-- Sorted by name, because this is read as a list of people rather than as a
-- ranking of anything.
function RosterReceipts.List()
    local out = {}

    for name, entry in pairs(Store() or {}) do
        table.insert(out, {
            name = name,
            shortName = SYL.Utilities.ShortName(name),
            count = entry.count,
            at = entry.at,
            since = entry.since,
        })
    end

    table.sort(out, function(left, right)
        return left.shortName < right.shortName
    end)

    return out
end

function RosterReceipts.Count()
    local total = 0

    for _ in pairs(Store() or {}) do
        total = total + 1
    end

    return total
end

-- Emptied when there is nothing left to be using. Sending an empty roster on
-- purpose, or leaving the guild, makes every receipt a claim about something
-- that is not there any more -- and the receipts cannot correct themselves,
-- because the other clients have nothing new to report.
function RosterReceipts.Clear()
    if not ShowUsYourLootDB then
        return false
    end

    ShowUsYourLootDB.rosterReceipts = nil

    return true
end

-- The words under the roster list. Nil when nobody has confirmed, so the
-- caller keeps whatever it was saying: "used by 0 people" reads as a failure
-- report on a client that has simply never sent anything.
function RosterReceipts.Describe()
    local total = RosterReceipts.Count()

    if total == 0 then
        return nil
    end

    return "used by " .. SYL.Utilities.Count(total, "person", "people")
end

-- The tooltip: every name, and how many raiders they took. The count is
-- theirs rather than ours on purpose -- if it disagrees with what we hold
-- now, that IS the answer, because it means they are looking at a roster
-- older than the one on this screen.
function RosterReceipts.DescribeEach()
    local lines = {}
    local mine = #SYL.RosterSync.Own()

    for _, entry in ipairs(RosterReceipts.List()) do
        local line = entry.shortName .. " — " .. entry.count

        if entry.count ~= mine then
            line = line .. " (yours has " .. mine .. " now)"
        end

        table.insert(lines, line)
    end

    return lines
end
