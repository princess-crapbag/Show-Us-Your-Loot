-- Core/KeystoneSync.lua
--
-- Telling the guild which keystone you hold, and remembering theirs.
--
-- Core/Keystone.lua reads your own key and can only ever read your own — no
-- API returns another player's bags. This is the other half: every copy of the
-- addon says what its owner is holding, and every copy listens.
--
-- ITS OWN SWITCH, NOT THE SYNC FEATURE'S. Officer sync sends drop headers to
-- officers inside your own raid group. This sends one line about your own
-- character to your whole guild. Somebody may reasonably want either without
-- the other, and folding them together would mean turning on loot sharing to
-- see keys. Off by default, like everything here that talks.
--
-- WHAT GOES OUT, in full, so it can be read at a glance: an addon-channel
-- message on the GUILD channel containing a version tag, a dungeon map id, a
-- key level, and the character's class. That is all. No loot, no attendance,
-- no roll data, and nothing a player sees in chat — addon messages are a
-- separate channel from the one people read.
--
-- WHEN IT GOES OUT: when your key changes, and when somebody asks. A fresh
-- login asks once; everyone who hears the question answers. That is cheaper
-- than a timer and it means a key is never more than one login stale.
--
-- KEYS EXPIRE. A keystone is worthless after the weekly reset and a stale one
-- makes the list lie, so anything older than the last reset is dropped on
-- read rather than shown with a date beside it.

local SYL = _G.ShowUsYourLoot

local KeystoneSync = {}
SYL.KeystoneSync = KeystoneSync

-- Deliberately not SYLOOT. A different prefix means a client running an older
-- build simply never sees these, rather than handing them to a parser written
-- for drop headers.
local PREFIX = "SYLKEY"

-- Bumped when the payload shape changes. A message whose version is not this
-- one is ignored rather than guessed at.
local VERSION = "1"

local ANNOUNCE = "K"
local REQUEST = "?"

local frame
local enabled = false

-- Answering a request is a broadcast, so twenty people logging in together
-- would be twenty questions and four hundred answers. One answer per this
-- many seconds, whatever asks.
local ANSWER_THROTTLE_SECONDS = 20
local lastAnswerAt = 0

local function CanSend()
    return C_ChatInfo
        and C_ChatInfo.SendAddonMessage
        and IsInGuild()
        and true
        or false
end

-- Queued rather than sent directly. One keystone is a single message and was
-- never the problem on its own, but it leaves at login alongside the absences
-- and the roster, and the client's limit counts all of them together. See
-- Core/SendQueue.lua, which also keeps the pcall: a throttled or malformed
-- send raises rather than returning, and a keystone is never worth taking the
-- addon down for.
local function Send(payload)
    if not enabled or not CanSend() then
        return false
    end

    return SYL.SendQueue.Queue(PREFIX, payload, "GUILD", nil, function()
        return enabled and CanSend()
    end)
end

--------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------

-- Other people's keys, keyed by the sender the client reported. Kept out of
-- Keystone's own table so "what am I holding" and "what did somebody tell me"
-- are never confused for one another.
local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.guildKeystones = ShowUsYourLootDB.guildKeystones or {}

    return ShowUsYourLootDB.guildKeystones
end

-- A key from before the last weekly reset is gone, whatever it says.
--
-- ASKED, NOT ASSUMED. Aimee's realm resets Tuesday; other regions do not, and
-- hardcoding a weekday would be wrong for most of the people who install
-- this. C_DateAndTime.GetSecondsUntilWeeklyReset counts down to the client's
-- own reset, so subtracting a week from it gives the moment the current week
-- began — correct in every region without this file knowing which day it is.
--
-- The flat seven days is the fallback for a client that does not expose it.
-- It is wrong in the safe direction: it keeps a key slightly too long rather
-- than dropping one that is still good.
local WEEK_SECONDS = 7 * 24 * 60 * 60

function KeystoneSync.LastResetAt()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, remaining =
            pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)

        if ok and type(remaining) == "number" and remaining > 0 then
            return (time() + remaining) - WEEK_SECONDS
        end
    end

    return time() - WEEK_SECONDS
end

local function IsStale(entry)
    if not entry or not entry.at then
        return true
    end

    return entry.at < KeystoneSync.LastResetAt()
end

function KeystoneSync.Remember(sender, mapID, level, class)
    local store = Store()

    if not store or type(sender) ~= "string" or sender == "" then
        return nil
    end

    store[sender] = {
        name = sender,
        class = class,
        mapID = mapID,
        level = level,
        at = time(),
    }

    return store[sender]
end

-- Everything currently known and not stale, highest key first. Stale entries
-- are dropped from the store as they are found, so it does not grow forever
-- with people who left the guild.
function KeystoneSync.List()
    local store = Store()
    local entries = {}

    if not store then
        return entries
    end

    for sender, entry in pairs(store) do
        if IsStale(entry) then
            store[sender] = nil
        else
            table.insert(entries, entry)
        end
    end

    table.sort(entries, function(left, right)
        local leftLevel = left.level or 0
        local rightLevel = right.level or 0

        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        return tostring(left.name) < tostring(right.name)
    end)

    return entries
end

function KeystoneSync.Count()
    return #KeystoneSync.List()
end

--------------------------------------------------------------------------
-- The wire
--------------------------------------------------------------------------

-- "1|K|375|12|MAGE". Positional and tiny: this is one line about one
-- character and a table would cost more to serialise than it carries.
function KeystoneSync.Encode(mapID, level, class)
    return table.concat({
        VERSION,
        ANNOUNCE,
        tostring(mapID or 0),
        tostring(level or 0),
        tostring(class or ""),
    }, "|")
end

-- Returns kind, mapID, level, class — or nil when the message is not ours to
-- read. Every field is checked: this is input from other people's machines,
-- and a number that arrives as a word must not reach the sort comparator.
function KeystoneSync.Decode(payload)
    if type(payload) ~= "string" then
        return nil
    end

    -- [^|]* for the kind rather than a character class per possible letter.
    -- %a?%p? was the first attempt and it captured the delimiter along with
    -- the letter — "K|" instead of "K" — so nothing ever matched ANNOUNCE.
    local version, kind, rest = payload:match("^(%d+)|([^|]*)|?(.*)$")

    if version ~= VERSION then
        return nil
    end

    if kind == REQUEST then
        return REQUEST
    end

    if kind ~= ANNOUNCE then
        return nil
    end

    local mapID, level, class = rest:match("^(%-?%d+)|(%-?%d+)|(%a*)$")

    if not mapID then
        return nil
    end

    mapID = tonumber(mapID)
    level = tonumber(level)

    -- Zero is how "no key" travels, since the fields are always present.
    if not mapID or mapID <= 0 or not level or level <= 0 then
        return ANNOUNCE, nil, nil, class
    end

    return ANNOUNCE, mapID, level, class
end

function KeystoneSync.Announce()
    local entry = SYL.Keystone.GetOwn()

    if not entry then
        SYL.Keystone.Update()
        entry = SYL.Keystone.GetOwn()
    end

    if not entry then
        return false
    end

    return Send(
        KeystoneSync.Encode(entry.mapID, entry.level, entry.class)
    )
end

function KeystoneSync.Request()
    return Send(VERSION .. "|" .. REQUEST .. "|")
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local function OnMessage(prefix, payload, _, sender)
    if prefix ~= PREFIX or not enabled then
        return
    end

    -- Our own broadcast comes back to us. Keystone.GetOwn is the authority on
    -- this character, so hearing ourselves would be a slower copy of it.
    if sender == SYL.Keystone.CharacterKey() then
        return
    end

    local kind, mapID, level, class = KeystoneSync.Decode(payload)

    if kind == REQUEST then
        local now = time()

        if (now - lastAnswerAt) < ANSWER_THROTTLE_SECONDS then
            return
        end

        lastAnswerAt = now

        KeystoneSync.Announce()

        return
    end

    if kind ~= ANNOUNCE then
        return
    end

    KeystoneSync.Remember(sender, mapID, level, class)
end

function KeystoneSync.IsEnabled()
    return enabled
end

function KeystoneSync.Enable()
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

    -- Say what we have and ask what everyone else has. Both are one message.
    KeystoneSync.Announce()
    KeystoneSync.Request()

    return true
end

-- Called whenever this character's key changes. Nothing is sent when the key
-- is the same as the last thing announced, which is the common case: this is
-- reached from a bag update.
function KeystoneSync.OnOwnKeyChanged()
    if not enabled then
        return
    end

    KeystoneSync.Announce()
end
