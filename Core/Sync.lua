-- Core/Sync.lua
--
-- Shares captured drops with other officers over addon comms.
--
-- This is the only part of the addon that sends anything to other players,
-- so it is deliberately narrow:
--
--   * OFF by default. Nothing is transmitted until it is switched on.
--   * RAID channel only. Never guild-wide, never whispered, never a chat
--     message a human sees.
--   * Only from senders in your own guild, and only while you are in a raid.
--   * One message per drop, sent once, when the drop resolves.
--
-- WHAT IS SENT, in full, and nothing more:
--
--   record id, encounter id and name, difficulty id, instance id,
--   item id, winner name, winner GUID, winner roll state, winning roll,
--   whether everyone passed, how many were eligible, and the timestamp.
--
-- WHAT IS NOT SENT: the per-player roll list, chat loot, guild ranks,
-- settings, anything about characters not involved in the drop, and any
-- free text a player typed.
--
-- Records arriving this way are marked partial and never overwrite a full
-- local record, because they carry no roll list and the fairness math must
-- not read an absent list as "nobody rolled".
--
-- Getting the bytes there is Core/SyncTransport.lua, which now chunks, so the
-- 255-byte cap no longer decides what can be sent. What IS sent has not
-- changed with it: the list above still holds, and widening it is a decision
-- to take deliberately rather than one to inherit from a roomier transport.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local Sync = {}
SYL.Sync = Sync

local PREFIX = "SYLOOT"
local PROTOCOL = "1"
local SEPARATOR = "\t"

local frame
local registered = false

-- One switch, in the feature registry, rather than a setting of its own.
-- This is the only part of the addon that sends anything to another player,
-- which is exactly the kind of thing somebody should be able to find in one
-- list and turn off.
local function IsEnabled()
    return SYL.Features.IsEnabled("sync")
end

-- Tabs are the field separator, so anything containing one would corrupt the
-- message. Names cannot contain tabs, but this costs nothing.
local function Clean(value)
    if value == nil then
        return ""
    end

    return (tostring(value):gsub("[\t\n|]", " "))
end

local function Encode(record)
    return table.concat({
        PROTOCOL,
        Clean(record.id),
        Clean(record.encounterID),
        Clean(record.encounterName),
        Clean(record.difficultyID),
        Clean(record.instanceID),
        Clean(record.itemID),
        Clean(record.winnerName),
        Clean(record.winnerGUID),
        Clean(record.winnerState),
        Clean(record.winnerRoll),
        record.allPassed and "1" or "",
        Clean(record.eligibleCount),
        Clean(record.timestamp),
    }, SEPARATOR)
end

local function Decode(payload)
    local fields = {}

    for field in (payload .. SEPARATOR):gmatch("(.-)" .. SEPARATOR) do
        table.insert(fields, field)
    end

    if fields[1] ~= PROTOCOL then
        return nil
    end

    local function number(value)
        return tonumber(value)
    end

    return {
        id = fields[2],
        encounterID = number(fields[3]),
        encounterName = fields[4] ~= "" and fields[4] or nil,
        difficultyID = number(fields[5]),
        instanceID = number(fields[6]),
        itemID = number(fields[7]),
        winnerName = fields[8] ~= "" and fields[8] or nil,
        winnerGUID = fields[9] ~= "" and fields[9] or nil,
        winnerState = number(fields[10]),
        winnerRoll = number(fields[11]),
        allPassed = fields[12] == "1" or nil,
        eligibleCount = number(fields[13]),
        timestamp = number(fields[14]),
    }
end

function Sync.Send(record)
    if not record or not record.id then
        return false
    end

    -- Still one message in practice: a drop header is well under a single
    -- chunk. It goes through the chunker anyway so there is one wire format
    -- rather than two.
    local sent = SYL.SyncTransport.Send(Encode(record), record.id)

    -- The roll list follows as its own payload rather than being folded into
    -- the header. Two reasons: the header stays exactly the shape older
    -- clients already parse, and a roll list that fails to arrive leaves a
    -- record that is merely partial rather than one that is missing.
    SYL.SyncRolls.Send(record)

    return sent
end

-- Only merges what is missing. A record captured locally is always richer,
-- because it carries the full roll list, so it is never replaced.
local function Merge(decoded, sender)
    local drops = SYL.GetActiveDrops()

    for _, existing in ipairs(drops) do
        if existing.id == decoded.id then
            return false
        end
    end

    local season = SYL.GetActiveSeason()

    if not season then
        return false
    end

    local record = {
        id = decoded.id,

        seasonID = season.id,
        seasonName = season.name,

        encounterID = decoded.encounterID,
        encounterName = decoded.encounterName,
        difficultyID = decoded.difficultyID,
        instanceID = decoded.instanceID,

        itemID = decoded.itemID,

        winnerName = decoded.winnerName,
        winnerGUID = decoded.winnerGUID,
        winnerState = decoded.winnerState,
        winnerRoll = decoded.winnerRoll,
        allPassed = decoded.allPassed,
        eligibleCount = decoded.eligibleCount,

        timestamp = decoded.timestamp or time(),
        dateText = date("%Y-%m-%d", decoded.timestamp or time()),

        recordedBy = sender,
        source = "SYNC",

        -- No roll list traveled with this, and analytics must not treat an
        -- absent list as "nobody rolled".
        partial = true,
        rolls = {},

        hidden = false,
        excludedFromAnalytics = false,
    }

    table.insert(drops, record)

    SYL.LootHistoryStore.RebuildIndex()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
end

-- Called by the transport once a payload has arrived complete and from a
-- sender it is willing to accept.
local function OnPayload(payload, sender)
    -- Roll lists and backfill requests share the transport and are handled by
    -- Core/SyncRolls.lua. Dispatched on the protocol marker rather than by
    -- registering a second prefix, so there is still one channel to audit.
    if SYL.SyncRolls.OnPayload(payload, sender) then
        return
    end

    local decoded = Decode(payload)

    if not decoded or not decoded.id then
        return
    end

    if Merge(decoded, sender) then
        SYL:DebugPrint("Sync received a drop from " .. tostring(sender))
    end
end

function Sync.Enable()
    SYL.SyncTransport.onPayload = OnPayload

    return SYL.SyncTransport.Enable()
end

function Sync.IsEnabled()
    return IsEnabled()
end

-- Counts where the season's drops came from. Synced records are deliberately
-- second class — they carry no roll list, so the fairness math skips them —
-- and there was previously no way to see how much of the history that
-- affected. A history that looks complete but is half partial gives answers
-- nobody should trust.
function Sync.BuildStatus()
    local status = {
        enabled = IsEnabled(),
        registered = SYL.SyncTransport.IsRegistered(),

        total = 0,
        local_ = 0,
        partial = 0,

        contributors = {},
        contributorOrder = {},
    }

    for _, drop in ipairs(SYL.GetActiveDrops()) do
        status.total = status.total + 1

        if drop.partial then
            status.partial = status.partial + 1

            local who = drop.recordedBy or "unknown"

            if not status.contributors[who] then
                status.contributors[who] = 0

                table.insert(status.contributorOrder, who)
            end

            status.contributors[who] = status.contributors[who] + 1
        else
            status.local_ = status.local_ + 1
        end
    end

    table.sort(status.contributorOrder, function(left, right)
        return status.contributors[left] > status.contributors[right]
    end)

    return status
end

function Sync.ReportStatus()
    local status = Sync.BuildStatus()

    SYL:Print(
        "Officer sync is " .. (status.enabled and "on" or "off")
        .. ". It sends drop headers to other officers in your raid, never "
        .. "roll lists and never outside the group."
    )

    SYL:Write(
        "  This season: " .. status.total .. " drops — "
        .. status.local_ .. " recorded here, "
        .. status.partial .. " received from others."
    )

    for _, who in ipairs(status.contributorOrder) do
        SYL:Write("    " .. who .. ": " .. status.contributors[who])
    end

    if status.partial > 0 then
        SYL:Write(
            "  Received drops have no roll list, so they are left out of "
            .. "player fairness numbers. They still show in the loot list."
        )
    end
end
