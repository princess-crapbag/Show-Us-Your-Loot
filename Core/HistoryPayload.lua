-- Core/HistoryPayload.lua
--
-- A season of loot, flattened for the wire and put back together at the other
-- end. Core/HistorySync.lua is how it travels; this is what a drop becomes.
--
-- Split for the reason Core/Sync.lua and Core/SyncTransport.lua are split, and
-- the reason is load-bearing here: the encoding is the part worth testing on
-- its own, and it is unreachable through a module that will not do anything
-- without somebody at the other end saying yes first.
--
-- WHY A BULK TRANSFER EXISTS AT ALL. Sync.lua already shares drops as they
-- happen, over the raid channel, to whoever is standing there with the addon
-- running. That covers the night; it covers nothing else. An officer who
-- installed the addon in week six has no record of weeks one to five, and no
-- way to get one -- so their board shows a dash for every raider and a number
-- for the one person they happened to loot beside. Aimee, 2026-09-03: "its
-- not showing the score of the items i marked".
--
-- THE ROLL LISTS TRAVEL, and that decision was made twice. The first answer
-- was to send headers only -- who won what, when -- which is what Sync.lua
-- sends live and is a third of the bytes. It is also wrong, and the addon
-- says so in its own code: Sync.lua marks a header-only record `partial`,
-- and Analytics.lua:143 skips every partial record outright. Sending headers
-- would have moved the points and left attendance, eligibility and the whole
-- of the pass data blank -- which is most of what the boards are for.
--
-- Measured against Aimee's own database by running this encoder over all 130
-- of her real drops: headers alone are 267 messages, headers and rolls
-- together are 983. At four a second that is one minute against four. Four
-- minutes, once a season, for records that are actually complete -- and all
-- 130 round-trip with every roll list and every credit mark intact.
--
-- WHAT IS SENT, in full: the drop header Sync.lua already sends, plus the
-- item, the instance and difficulty it dropped in, the roll list Core/
-- SyncRolls.lua already sends, and the credit override -- who an officer
-- decided actually got the item, and what response they gave it.
--
-- WHAT IS NOT SENT: settings, guild ranks, notes, anything about a character
-- who was not eligible for the item, and any season but the one asked for.
--
-- THE CREDIT OVERRIDE IS THE POINT OF THE WHOLE FEATURE, so it is worth being
-- explicit about why it is safe to carry. It names a guild member and a loot
-- response, both of which every person in that raid watched happen. It is
-- also the only field here that somebody TYPED, which is why the merge below
-- lets it win over a local record where nothing else does.

local SYL = _G.ShowUsYourLoot

local HistoryPayload = {}
SYL.HistoryPayload = HistoryPayload

HistoryPayload.PROTOCOL = "H1"

local FIELD = "\t"
local ROLL = "\30"
local PART = "\31"

-- Marks a record as having come from a bulk transfer rather than from this
-- client watching the loot. Not `partial`: these carry their roll lists, so
-- the fairness math can read them. Kept so a screen can say where a record
-- came from, and so a future merge can tell the two apart.
HistoryPayload.SOURCE = "SYNC_HISTORY"

-- The header fields, in order. Adding one goes on the END and bumps the
-- protocol: a receiver on an older build reads the fields it knows and would
-- silently take a new field as the value of an old one otherwise.
local HEADER = {
    "id", "seasonID", "seasonName", "runID",
    "encounterID", "encounterName",
    "difficultyID", "difficultyName",
    "instanceID", "instanceName", "instanceType", "zoneName",
    "itemID", "itemName", "itemLink", "itemLevel", "lootListID",
    "winnerName", "winnerGUID", "winnerClass", "winnerRoll", "winnerState",
    "allPassed", "eligibleCount", "groupSize",
    "timestamp", "dateText", "timeText", "recordedBy",
}

local ROLL_FIELDS = { "name", "guid", "class", "state", "stateText", "roll" }
local CREDIT_FIELDS = { "guid", "name", "state", "setAt", "setBy" }

-- Numbers that must come back as numbers. Everything on the wire is a string,
-- and a timestamp compared as text sorts "9" after "10" -- which is the kind
-- of bug that only shows up on the day the digit count changes.
local NUMERIC = {
    encounterID = true, difficultyID = true, instanceID = true,
    itemID = true, itemLevel = true, winnerRoll = true,
    eligibleCount = true, groupSize = true, timestamp = true,
    lootListID = true,
}

local function Clean(value)
    if value == nil then
        return ""
    end

    if value == true then
        return "1"
    end

    if value == false then
        return ""
    end

    return (tostring(value):gsub("[\t\n\30\31]", " "))
end

-- The separators here are control characters, never Lua pattern magic, so
-- they go into the pattern as themselves.
--
-- NOTHING IS TRIMMED OFF THE END, and the version that did cost the roll list.
-- Appending the separator and matching "(.-)sep" yields exactly one piece per
-- field -- "a\tb" becomes "a\tb\t" and yields "a" and "b", with no empty tail
-- to remove. Removing one anyway silently dropped the LAST field of every
-- split, which is the roll list on a record and the winner flag on a roll:
-- every drop arrived with an empty roll list, which is precisely the
-- header-only shape this whole file exists to avoid, and every count in the
-- test above still passed.
local function Split(text, separator)
    local out = {}

    for piece in (text .. separator):gmatch("(.-)" .. separator) do
        table.insert(out, piece)
    end

    return out
end

--------------------------------------------------------------------------
-- One drop, out
--------------------------------------------------------------------------

function HistoryPayload.EncodeRolls(rolls)
    local out = {}

    for _, roll in ipairs(rolls or {}) do
        local fields = {}

        for _, name in ipairs(ROLL_FIELDS) do
            table.insert(fields, Clean(roll[name]))
        end

        -- isWinner last, so the field list above stays the readable part.
        table.insert(fields, roll.isWinner and "1" or "")

        table.insert(out, table.concat(fields, PART))
    end

    return table.concat(out, ROLL)
end

function HistoryPayload.EncodeCredit(credit)
    if type(credit) ~= "table" then
        return ""
    end

    local fields = {}

    for _, name in ipairs(CREDIT_FIELDS) do
        table.insert(fields, Clean(credit[name]))
    end

    return table.concat(fields, PART)
end

function HistoryPayload.Encode(record)
    local fields = { HistoryPayload.PROTOCOL }

    for _, name in ipairs(HEADER) do
        table.insert(fields, Clean(record[name]))
    end

    table.insert(fields, HistoryPayload.EncodeCredit(record.creditOverride))
    table.insert(fields, HistoryPayload.EncodeRolls(record.rolls))

    return table.concat(fields, FIELD)
end

--------------------------------------------------------------------------
-- One drop, back
--------------------------------------------------------------------------

local function DecodeRolls(text)
    if text == nil or text == "" then
        return {}
    end

    local rolls = {}

    for _, piece in ipairs(Split(text, ROLL)) do
        local parts = Split(piece, PART)
        local roll = {}

        for index, name in ipairs(ROLL_FIELDS) do
            local value = parts[index]

            if value ~= nil and value ~= "" then
                roll[name] = (name == "roll" and tonumber(value)) or value
            end
        end

        roll.isWinner = parts[#ROLL_FIELDS + 1] == "1" or nil

        if roll.name or roll.guid then
            table.insert(rolls, roll)
        end
    end

    return rolls
end

local function DecodeCredit(text)
    if text == nil or text == "" then
        return nil
    end

    local parts = Split(text, PART)
    local credit = {}

    for index, name in ipairs(CREDIT_FIELDS) do
        local value = parts[index]

        if value ~= nil and value ~= "" then
            credit[name] = (name == "setAt" and tonumber(value)) or value
        end
    end

    if not credit.guid and not credit.name then
        return nil
    end

    return credit
end

-- Returns a record, or nil for anything this build cannot read. Nil rather
-- than a half-filled record on purpose: a drop missing its id cannot be
-- merged, deduplicated or pointed at later, so it is not a drop.
function HistoryPayload.Decode(payload)
    if type(payload) ~= "string" then
        return nil
    end

    local parts = Split(payload, FIELD)

    if parts[1] ~= HistoryPayload.PROTOCOL then
        return nil
    end

    local record = {}

    for index, name in ipairs(HEADER) do
        local value = parts[index + 1]

        if value ~= nil and value ~= "" then
            record[name] = NUMERIC[name] and tonumber(value) or value
        end
    end

    if not record.id then
        return nil
    end

    record.allPassed = record.allPassed == "1" or nil

    record.creditOverride = DecodeCredit(parts[#HEADER + 2])
    record.rolls = DecodeRolls(parts[#HEADER + 3])

    record.source = HistoryPayload.SOURCE

    -- Both are display state on the receiver's own screen and neither travels.
    -- Somebody who hid a drop on their client hid it there.
    record.hidden = false
    record.excludedFromAnalytics = false

    return record
end

--------------------------------------------------------------------------
-- Putting it into the season
--------------------------------------------------------------------------

-- THE MERGE RULE, and it is one sentence: a local record keeps everything it
-- has, except the credit, which the sender typed and the receiver did not.
--
-- Everything else follows from "two clients disagree about a drop only when
-- one of them saw less", which is the rule Core/SyncRolls.lua already states
-- and the reason a local roll list is never overwritten. Credit is the
-- exception because it is not something a client SAW -- it is something an
-- officer decided, after the fact, on one screen. There is no version of it
-- to lose by taking the sender's.
--
-- A record the receiver does not have at all is simply added.
--
-- Returns added, updated, skipped.
function HistoryPayload.Merge(season, records)
    if type(season) ~= "table" then
        return 0, 0, 0
    end

    season.drops = season.drops or {}

    local byID = {}

    for _, drop in ipairs(season.drops) do
        if drop.id then
            byID[drop.id] = drop
        end
    end

    local added, updated, skipped = 0, 0, 0

    for _, record in ipairs(records or {}) do
        local existing = record.id and byID[record.id]

        if not existing then
            table.insert(season.drops, record)

            byID[record.id] = record
            added = added + 1
        elseif record.creditOverride
            and not existing.creditOverride
        then
            existing.creditOverride = record.creditOverride
            updated = updated + 1
        elseif record.creditOverride
            and existing.creditOverride
            and (record.creditOverride.setAt or 0)
                > (existing.creditOverride.setAt or 0)
        then
            -- Both typed one. The newer decision is the one that stands, the
            -- same way it would if one person had changed their mind twice.
            existing.creditOverride = record.creditOverride
            updated = updated + 1
        else
            skipped = skipped + 1
        end
    end

    return added, updated, skipped
end
