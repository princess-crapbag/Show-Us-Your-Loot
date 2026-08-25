-- Core/LootAsk.lua
--
-- You rolled on something, somebody else won it, and it is still inside the
-- two hours where they could hand it over. This is the one button that asks.
--
-- WHERE IT CAME FROM. Razorokk, after a week with the addon: "I remember
-- during remix, there was a button you could hit with an addon someone made
-- to be like 'Hey I need that for tmog, do you need it?'". Aimee, on where it
-- would earn its place: "for things like LFR or any other time the standard
-- roll option is in place in a raid with people you dont know".
--
-- It is the mirror of Core/TradeAdvisor.lua. That one opens when you WIN and
-- tells you who else wanted it. This one opens when you LOSE and puts the
-- sentence in your chat box. Both read the same records, both live inside the
-- same two-hour window, and this file takes that window and its clock from
-- TradeAdvisor rather than declaring a second copy of Blizzard's rule.
--
-- IT PREFILLS AND IT DOES NOT SEND, and that is the whole reason it is
-- allowed to exist. UI/TradeAdvisorPanel.lua turns down a whisper button in
-- as many words -- "a popup offering to talk for you erodes one button at a
-- time" -- and that rule stands. What is different here is the mechanism:
-- this is UI/KeyRequestList.lua's Whisper button, which opens the chat box
-- with the message ready and stops. The person still sends it. Nothing in
-- this addon has ever called SendChatMessage and nothing here does either.
--
-- THE SENTENCE ITSELF IS NOT HERE. Core/AskWording.lua holds the default,
-- the player's edit of it and the token substitution, because that half is
-- edited in a dialog and previewed in a box while this half is a watcher on
-- the loot store. Splitting them is what got this file back under the size
-- rule, and the seam was already there.
--
-- THE ONE THING IT CHECKS, and why it is narrower than it first looks. A
-- transmog loss offers the button only when the collection still says the
-- appearance is missing. The client already refuses a Transmog roll on
-- something you have collected, so at the moment of the roll the answer is
-- always yes -- what this catches is the appearance collected SINCE. Two of
-- the same item dropping in one wing is ordinary, and having won the first,
-- being offered a button to go and ask for the second is noise.
--
-- It is not a claim about honesty. The default wording says nothing about
-- transmog, so there is nothing here for the addon to be caught out in.

local SYL = _G.ShowUsYourLoot

local LootAsk = {}
SYL.LootAsk = LootAsk

local API = SYL.LootHistoryAPI
local TradeAdvisor = SYL.TradeAdvisor

-- Every roll you actually made. Not passing, and not sitting it out.
--
-- GREED IS IN THIS LIST AND THE FIRST DRAFT LEFT IT OUT, on the reasoning
-- that greed means "only if nobody else wants it" and asking for somebody's
-- greed win is beggy. Aimee, who plays the content this exists for: "sometimes
-- LFR can be weird and not let you roll need (wrong armor type) or mog (for no
-- known reason) so having the option is good."
--
-- That is the whole argument. Greed is frequently not a choice at all -- it is
-- what is left when the client refuses the other two buttons -- so reading it
-- as a statement of indifference is reading something the player never said.
--
-- Pass and no-roll stay out, and that is a noise rule rather than a manners
-- one: a night of passing on everything would open this window on nearly
-- every drop in the raid.
local WANTED = {
    [API.ROLL_STATE.NeedMainSpec] = true,
    [API.ROLL_STATE.NeedOffSpec] = true,
    [API.ROLL_STATE.Transmog] = true,
    [API.ROLL_STATE.Greed] = true,
}

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.lootAsk = ShowUsYourLootDB.lootAsk or {}

    return ShowUsYourLootDB.lootAsk
end

function LootAsk.IsEnabled()
    return SYL.Features.IsEnabled("lootAsk")
end

--------------------------------------------------------------------------
-- Who to whisper
--------------------------------------------------------------------------

-- A roll list names people the way the client happened to have them, which
-- for anybody on another realm is a bare first name -- and a bare first name
-- whispers into nothing across realms. LFR is 24 strangers from 20 realms, so
-- this is the ordinary case here rather than the edge one. The GUID is the
-- only thing that always resolves.
function LootAsk.WhisperTarget(record)
    if not record then
        return nil
    end

    local guid = record.winnerGUID

    if guid and _G.GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name, realm =
            pcall(_G.GetPlayerInfoByGUID, guid)

        if ok and type(name) == "string" and name ~= "" then
            if type(realm) == "string" and realm ~= "" then
                return name .. "-" .. realm:gsub("%s+", "")
            end

            return name
        end
    end

    if type(record.winnerName) == "string" and record.winnerName ~= "" then
        return record.winnerName
    end

    return nil
end

--------------------------------------------------------------------------
-- Whether there is anything to ask for
--------------------------------------------------------------------------

local function MyRoll(record)
    local guid = UnitGUID and UnitGUID("player")
    local full = SYL.Utilities.GetPlayerFullName()
    local short = full and full:match("^([^-]+)") or full

    for _, roll in ipairs(record.rolls or {}) do
        if guid and roll.guid and roll.guid == guid then
            return roll
        end

        if not roll.guid
            and roll.name
            and (roll.name == full or roll.name == short)
        then
            return roll
        end
    end

    return nil
end

LootAsk.MyRoll = MyRoll

-- Nil when the client cannot answer. Read as "do not offer" for the transmog
-- case only -- a greed or need loss never asks this question, so a client
-- that cannot answer costs those nothing.
function LootAsk.MissingAppearance(record)
    local collection = _G.C_TransmogCollection

    if not collection or not collection.PlayerHasTransmogByItemInfo then
        return nil
    end

    local link = record and (record.itemLink or record.itemID)

    if not link then
        return nil
    end

    local ok, has = pcall(collection.PlayerHasTransmogByItemInfo, link)

    if not ok or type(has) ~= "boolean" then
        return nil
    end

    return not has
end

-- Why the button is there, in the words the panel shows. Returns nil when
-- there is no reason, which is also the answer to "should this appear".
function LootAsk.Reason(record)
    local roll = MyRoll(record)

    if not roll or roll.isWinner or not WANTED[roll.state] then
        return nil
    end

    if roll.state == API.ROLL_STATE.Transmog then
        if LootAsk.MissingAppearance(record) ~= true then
            return nil
        end

        return "You rolled Transmog, and you are missing this appearance."
    end

    local label = SYL.LootScore.LABELS[roll.state] or "Need"

    return "You rolled " .. label .. " and lost."
end

--------------------------------------------------------------------------
-- Remembering a loss
--------------------------------------------------------------------------

local function Find(store, id)
    for _, entry in ipairs(store) do
        if entry.id == id then
            return entry
        end
    end

    return nil
end

-- Called for every drop the store writes, first capture or later resolution,
-- exactly where TradeAdvisor.Consider is called and for the same reason: the
-- pass that names the losers is often not the pass that named the winner.
--
-- Dismissed entries are kept rather than removed, so that a later resolution
-- pass cannot quietly reopen something somebody has already waved away.
function LootAsk.Consider(record)
    if not LootAsk.IsEnabled() or not record or not record.id then
        return false
    end

    if TradeAdvisor.WonByPlayer(record) then
        return false
    end

    if not LootAsk.Reason(record) then
        return false
    end

    if not LootAsk.WhisperTarget(record) then
        return false
    end

    local store = Store()

    if not store or Find(store, record.id) then
        return false
    end

    local entry = {
        id = record.id,
        wonAt = record.timestamp or time(),
    }

    if LootAsk.SecondsLeft(entry) <= 0 then
        return false
    end

    table.insert(store, entry)

    if SYL.LootAskPanel then
        SYL.LootAskPanel.Show()
    end

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- Blizzard's two hours, taken from TradeAdvisor rather than restated. One
-- copy of a rule that is not ours.
function LootAsk.SecondsLeft(entry)
    return TradeAdvisor.SecondsLeft(entry)
end

function LootAsk.FormatRemaining(seconds)
    return TradeAdvisor.FormatRemaining(seconds)
end

function LootAsk.Sweep()
    local store = Store()

    if not store then
        return 0
    end

    local kept, dropped = {}, 0

    for _, entry in ipairs(store) do
        if LootAsk.SecondsLeft(entry) > 0 then
            table.insert(kept, entry)
        else
            dropped = dropped + 1
        end
    end

    if dropped > 0 then
        ShowUsYourLootDB.lootAsk = kept
    end

    return dropped
end

local function Entry(id)
    local store = Store()

    return store and Find(store, id) or nil
end

function LootAsk.Dismiss(id)
    local entry = Entry(id)

    if not entry then
        return false
    end

    entry.dismissed = true

    return true
end

-- Asking does not remove the entry. Pressing Ask only fills the chat box, and
-- a player who then presses Escape instead of Enter has sent nothing at all --
-- so an entry that vanished on the press would take the only way back with
-- it. It stays, marked, and the button says "Ask again".
function LootAsk.MarkAsked(id)
    local entry = Entry(id)

    if not entry then
        return false
    end

    entry.asked = true

    return true
end

-- Still open and not waved away, soonest to expire first.
function LootAsk.Active()
    LootAsk.Sweep()

    local store = Store()
    local active = {}

    for _, entry in ipairs(store or {}) do
        local record = not entry.dismissed
            and SYL.LootHistoryStore.GetRecord(entry.id)

        if record then
            table.insert(active, {
                id = entry.id,
                wonAt = entry.wonAt,
                asked = entry.asked,
                record = record,
                reason = LootAsk.Reason(record),
                target = LootAsk.WhisperTarget(record),
                secondsLeft = LootAsk.SecondsLeft(entry),
            })
        end
    end

    table.sort(active, function(left, right)
        if left.secondsLeft ~= right.secondsLeft then
            return left.secondsLeft < right.secondsLeft
        end

        return tostring(left.id) < tostring(right.id)
    end)

    return active
end
