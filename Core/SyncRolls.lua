-- Core/SyncRolls.lua
--
-- The per-player roll list, over the wire. The half of officer sync that was
-- deliberately left out until the transport could carry it.
--
-- WHAT THIS FIXES. A synced drop arrived as a header — who won, what, when —
-- and no roll list, so it was marked `partial`. Analytics skips partial
-- records outright, the trade advisor cannot say who lost, and the pass data
-- this addon's whole pitch rests on ("Group Loot remembers who won; this
-- remembers who passed") was missing for every drop the officer running the
-- addon did not personally witness. Wins still counted, through the header
-- fallback in DueList and LootScore — so the gap was never a wrong number, it
-- was a missing answer.
--
-- WHY IT IS SAFE TO SEND, stated rather than assumed, because this widens what
-- officer sync transmits and HANDOFF.md is explicit that widening is a
-- decision to take on purpose. Three reasons:
--
--   1. It goes to the same place the header already goes — RAID channel, guild
--      members only, while you are in a raid with them. No new audience.
--   2. Everybody it names was in that raid and watched that roll resolve in
--      their own loot frame. It is not new information to the recipients; it
--      is the same information, recorded.
--   3. It is still only what the game itself showed: name, class, what they
--      chose, and the number they rolled. No notes, no ranks, no settings, and
--      nothing about anybody who was not eligible for that item.
--
-- A LOCAL RECORD IS ALWAYS RICHER AND IS NEVER OVERWRITTEN. Rolls arriving for
-- a drop this client captured itself are dropped on the floor. The same rule
-- the header merge already follows, for the same reason: two clients disagree
-- about a roll list only when one of them saw less.

local SYL = _G.ShowUsYourLoot

local SyncRolls = {}
SYL.SyncRolls = SyncRolls

local PROTOCOL = "SYLROLL1"
local SEPARATOR = "\t"
local ROLL_SEPARATOR = "\30"
local FIELD_SEPARATOR = "\31"

SyncRolls.PROTOCOL = PROTOCOL

-- A request naming the drops somebody is missing rolls for.
local REQUEST = "SYLROLLREQ1"

SyncRolls.REQUEST = REQUEST

-- Enough ids to cover a night without ever approaching a payload the chunker
-- would struggle with. A backfill that has to run twice is fine; one that
-- builds a 40kb string is not.
local MAX_REQUEST_IDS = 40

local function Clean(value)
    if value == nil then
        return ""
    end

    return (tostring(value):gsub("[\t\n|" .. ROLL_SEPARATOR .. FIELD_SEPARATOR .. "]", " "))
end

--------------------------------------------------------------------------
-- Roll lists
--------------------------------------------------------------------------

function SyncRolls.Encode(record)
    local parts = {}

    for _, roll in ipairs(record.rolls or {}) do
        table.insert(parts, table.concat({
            Clean(roll.name),
            Clean(roll.guid),
            Clean(roll.class),
            Clean(roll.state),
            Clean(roll.roll),
            roll.isWinner and "1" or "",
        }, FIELD_SEPARATOR))
    end

    return table.concat({
        PROTOCOL,
        Clean(record.id),
        table.concat(parts, ROLL_SEPARATOR),
    }, SEPARATOR)
end

function SyncRolls.Decode(payload)
    local protocol, id, body =
        payload:match("^(.-)" .. SEPARATOR .. "(.-)" .. SEPARATOR .. "(.*)$")

    if protocol ~= PROTOCOL or not id or id == "" then
        return nil
    end

    local rolls = {}

    for chunk in (body or ""):gmatch("[^" .. ROLL_SEPARATOR .. "]+") do
        local fields = {}

        for field in (chunk .. FIELD_SEPARATOR):gmatch("(.-)" .. FIELD_SEPARATOR) do
            table.insert(fields, field)
        end

        -- A name is the one field a roll cannot be read without.
        if fields[1] and fields[1] ~= "" then
            table.insert(rolls, {
                name = fields[1],
                guid = fields[2] ~= "" and fields[2] or nil,
                class = fields[3] ~= "" and fields[3] or nil,
                state = tonumber(fields[4]),
                roll = tonumber(fields[5]),
                isWinner = fields[6] == "1" or nil,
            })
        end
    end

    return { id = id, rolls = rolls }
end

function SyncRolls.Send(record)
    if not record or not record.id then
        return false
    end

    if #(record.rolls or {}) == 0 then
        return false
    end

    return SYL.SyncTransport.Send(SyncRolls.Encode(record), record.id .. ":rolls")
end

-- Attaches a received list to a record that has none, and stops it being
-- partial. Returns false when there was nothing to improve, which is the
-- ordinary case for a drop this client captured itself.
function SyncRolls.Apply(decoded)
    if not decoded or not decoded.id then
        return false
    end

    local record = SYL.LootHistoryStore.GetRecord(decoded.id)

    if not record then
        return false
    end

    -- A RECORD THIS CLIENT WITNESSED IS NEVER OVERWRITTEN. The header says so,
    -- the request side already tests it (`:181`) and so does the answering side
    -- (`:240`) — this was the one place in the round trip that did not, and it
    -- tested length instead. A longer list is not a better one: a client that
    -- saw a roll this one did not is exactly as likely to have missed the
    -- winner, and rolls are what decide who won. So the only records that may
    -- be filled in are the ones that arrived hollow to begin with.
    if not record.partial then
        return false
    end

    -- Among partial records, still never trade a fuller list for an emptier
    -- one — the same test UpdateRecord makes when a drop resolves in stages.
    if #(record.rolls or {}) >= #(decoded.rolls or {}) then
        return false
    end

    record.rolls = decoded.rolls
    record.eligibleCount = #decoded.rolls

    -- The reason the flag existed has gone, so the flag goes with it.
    -- Analytics skips partial records, and leaving it set would mean a record
    -- that now has everything is still treated as if it had nothing.
    record.partial = nil

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
end

--------------------------------------------------------------------------
-- Backfill
--------------------------------------------------------------------------

-- Every drop this client holds with no roll list. These are exactly the ones
-- somebody else can answer, and there is no point asking about anything else.
function SyncRolls.MissingIDs(limit)
    local missing = {}

    for _, drop in ipairs(SYL.GetActiveDrops()) do
        if drop.partial and drop.id and #(drop.rolls or {}) == 0 then
            table.insert(missing, drop.id)

            if #missing >= (limit or MAX_REQUEST_IDS) then
                break
            end
        end
    end

    return missing
end

function SyncRolls.EncodeRequest(ids)
    return table.concat({ REQUEST, table.concat(ids, ROLL_SEPARATOR) }, SEPARATOR)
end

function SyncRolls.DecodeRequest(payload)
    local protocol, body = payload:match("^(.-)" .. SEPARATOR .. "(.*)$")

    if protocol ~= REQUEST then
        return nil
    end

    local ids = {}

    for id in (body or ""):gmatch("[^" .. ROLL_SEPARATOR .. "]+") do
        table.insert(ids, id)
    end

    return ids
end

-- Asks the raid for roll lists this client is missing. Returns how many were
-- asked about, so the caller can say "nothing to backfill" rather than
-- claiming to have sent something.
function SyncRolls.RequestBackfill()
    local ids = SyncRolls.MissingIDs()

    if #ids == 0 then
        return 0
    end

    SYL.SyncTransport.Send(SyncRolls.EncodeRequest(ids), "rollreq")

    return #ids
end

-- Answers a request with whatever full lists this client actually holds.
-- Silent about the rest: an id nobody has is not an error, it is a drop
-- nobody in this raid captured.
function SyncRolls.AnswerBackfill(ids)
    local answered = 0

    for _, id in ipairs(ids or {}) do
        local record = SYL.LootHistoryStore.GetRecord(id)

        if record and not record.partial and #(record.rolls or {}) > 0 then
            SyncRolls.Send(record)

            answered = answered + 1
        end
    end

    return answered
end

-- Routing, so Core/Sync.lua has one place to hand a payload it did not
-- recognize. Returns true when this file dealt with it.
function SyncRolls.OnPayload(payload, sender)
    if type(payload) ~= "string" then
        return false
    end

    if payload:sub(1, #PROTOCOL) == PROTOCOL then
        local decoded = SyncRolls.Decode(payload)

        if decoded and SyncRolls.Apply(decoded) then
            SYL:DebugPrint(
                "Sync filled in a roll list from " .. tostring(sender)
            )
        end

        return true
    end

    if payload:sub(1, #REQUEST) == REQUEST then
        SyncRolls.AnswerBackfill(SyncRolls.DecodeRequest(payload))

        return true
    end

    return false
end
