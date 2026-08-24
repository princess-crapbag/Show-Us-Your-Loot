-- Core/LootCredit.lua
--
-- Moving a drop's credit by hand, and putting it back.
--
-- WHY THIS HAS TO EXIST BEFORE ANYTHING READS RCLootCouncil. Nothing on any
-- screen could show a credit, let alone reverse one, so a wrong one could not
-- be undone. Anything that writes credit automatically needs this underneath
-- it first, and it is useful on its own: an officer who hands an item over
-- outside a trade window has had no way to say so.
--
-- THE ADDON IS WRONG ABOUT AIMEE'S GUILD AND THIS IS THE SHAPE OF IT. She is
-- master looter and hands loot out through RCLootCouncil, which SYL cannot
-- see. On her 2026-08-18 raid all eleven drops record her as the winner, and
-- on eight of the eleven every other raider had passed — the group-loot roll
-- is a formality that funnels the item to her. So the board read Arcangila
-- 820 and every one of her raiders 0.
--
-- TWO THINGS ARE WRONG PER DROP, NOT ONE, and this is the part that is easy
-- to get half right. The person is wrong, and so is the response the drop is
-- scored on, because the recorded state is *her* roll and not theirs. On that
-- night six of the eleven carried the wrong weight, and on four of those it
-- was Transmog — which weighs nothing. Moving only the name would have moved
-- nothing at all on those four. So an override carries a state as well as an
-- identity.
--
-- IT IS NOT GATED ON THE TRADE-TRACKING SWITCH, deliberately, and this is the
-- one difference from Core/TradeTracker.lua worth stating out loud. A trade is
-- an observation, and turning observation off should put the numbers back
-- where the client last saw them. A hand-made correction is a statement about
-- what really happened, and a setting nobody remembers touching must not
-- silently revert it. See the test: the trade switch moves a traded item's
-- credit and leaves a corrected one alone.
--
-- AND IT BEATS A WITNESSED TRADE, for the same reason. If the addon saw a
-- trade and was told otherwise afterwards, the person doing the telling was
-- in the raid and the addon was not.
--
-- NOTHING HERE IS DESTRUCTIVE. The roll list and the winner fields are never
-- written. "Won by Arcangila with 51" still reads the same on every screen
-- afterwards, because that is what happened; only the credit moves. Clearing
-- the override is therefore a delete rather than a restore, and there is no
-- prior value to keep or to get wrong.

local SYL = _G.ShowUsYourLoot

local LootCredit = {}
SYL.LootCredit = LootCredit

--------------------------------------------------------------------------
-- Finding the record that is actually stored
--------------------------------------------------------------------------

-- BY ID, NEVER BY THE TABLE THE UI IS HOLDING, and this is not a style
-- preference. Core/LootFeed.lua's ToDetailRecord hands back the live record
-- for a group-loot drop and a freshly built *copy* for a chat-captured one —
-- so a screen that wrote to what it had been given would work on drops and
-- silently lose the change on reload for everything else.
--
-- The store's index covers the active season, which is where all but archived
-- drops live. GetAllDrops copies the array but not the records, so the archive
-- fallback still hands back something a write reaches.
local function FindRecord(dropID)
    if not dropID then
        return nil
    end

    local record = SYL.LootHistoryStore.GetRecord(dropID)

    if record then
        return record
    end

    for _, candidate in ipairs(SYL.GetAllDrops()) do
        if candidate.id == dropID then
            return candidate
        end
    end

    return nil
end

LootCredit.FindRecord = FindRecord

-- Can this record's credit be moved at all?
--
-- CHAT-CAPTURED LOOT CANNOT, AND THE SCREEN HAS TO KNOW BEFORE THE BUTTON IS
-- PRESSED. Personal loot, vault items, crafted gear and world drops are
-- captured from chat into season.loot, not into season.drops — a different
-- store with a differently shaped id (Core/LootCapture.lua builds one from the
-- recipient and the item; Core/LootHistoryStore.lua builds one from the run
-- and the encounter). FindRecord searches the drops, so it can never resolve
-- one of those, and Set would answer "that drop is no longer in the database"
-- about a row the person is looking at.
--
-- That is right as a rule and not just as a limitation: personal loot is
-- outside the fairness math by design, so there is no credit on it to move.
-- The answer is to not offer the control, rather than to offer it and fail.
--
-- Asked of the store rather than of a flag on the record, because the record
-- the UI holds may be a copy — see the note on FindRecord — and the only
-- honest test is whether the thing a write would land on actually exists.
function LootCredit.CanCorrect(drop)
    return drop ~= nil and drop.id ~= nil and FindRecord(drop.id) ~= nil
end

--------------------------------------------------------------------------
-- Reading an override
--------------------------------------------------------------------------

function LootCredit.Get(drop)
    local override = drop and drop.creditOverride

    if type(override) ~= "table" then
        return nil
    end

    -- A record with neither is not an override, it is a leftover. Answering
    -- with it would credit the drop to nobody, which moves the points to a key
    -- nothing uses rather than leaving them where they were.
    if (override.guid == nil or override.guid == "")
        and (override.name == nil or override.name == "")
    then
        return nil
    end

    return override
end

function LootCredit.IsSet(drop)
    return LootCredit.Get(drop) ~= nil
end

-- GUID first, for the reason Core/TradeTracker.lua paid an hour to learn: the
-- math is keyed by GUID, and crediting a bare name moves the points to a key
-- nothing else in the addon reads. They leave the winner and arrive nowhere.
function LootCredit.IdentityFor(drop, rawIdentity)
    local override = LootCredit.Get(drop)

    if not override then
        return rawIdentity
    end

    if override.guid and override.guid ~= "" then
        return override.guid
    end

    return override.name
end

-- The weight half. Returns the recorded state untouched when no override is
-- set, so every caller can ask unconditionally.
function LootCredit.StateFor(drop, rawState)
    local override = LootCredit.Get(drop)

    if not override or override.state == nil then
        return rawState
    end

    return override.state
end

--------------------------------------------------------------------------
-- Writing one
--------------------------------------------------------------------------

local function Now()
    return (type(time) == "function" and time()) or 0
end

-- Returns the record on success, or nil plus a reason. The reason is shown,
-- not swallowed: "nothing happened" and "that drop is not in this database"
-- look identical on screen otherwise.
function LootCredit.Set(dropID, recipient)
    local record = FindRecord(dropID)

    if not record then
        return nil, "that drop is no longer in the database"
    end

    if type(recipient) ~= "table" then
        return nil, "no player was chosen"
    end

    local guid = recipient.guid
    local name = recipient.name

    if (guid == nil or guid == "") and (name == nil or name == "") then
        return nil, "no player was chosen"
    end

    record.creditOverride = {
        guid = guid,
        name = name,

        -- nil is allowed and means "keep the recorded response". The picker
        -- always sends one; a caller that only wants to move the person can
        -- leave it out rather than having to look the old one up first.
        state = recipient.state,

        setAt = Now(),
        setBy = SYL.Utilities.GetPlayerFullName(),
    }

    return record
end

-- A delete, not a restore. See the file header: the winner was never
-- overwritten, so there is nothing to put back.
function LootCredit.Clear(dropID)
    local record = FindRecord(dropID)

    if not record then
        return nil, "that drop is no longer in the database"
    end

    record.creditOverride = nil

    return record
end

--------------------------------------------------------------------------
-- What the screens say about it
--------------------------------------------------------------------------

-- Everything the credit line needs, worked out once here rather than three
-- times in three windows. Returns name, state, and whether a hand-made
-- override is what produced them.
--
-- The order matches the rule: an override beats a trade, and a trade beats
-- the roll.
-- The class of whoever a name belongs to, for a screen that colors it. The
-- roll list first, because it carries the class as recorded on the night;
-- the registry after, because a credit can land on somebody who never rolled.
local function ClassOf(drop, name)
    if not name then
        return nil
    end

    for _, roll in ipairs(drop.rolls or {}) do
        if roll.name == name and roll.class then
            return roll.class
        end
    end

    local player = SYL.Players and SYL.Players.Get(name)

    return player and player.class or nil
end

function LootCredit.Describe(drop)
    if not drop then
        return nil
    end

    local rawName, rawState

    for _, roll in ipairs(drop.rolls or {}) do
        if roll.isWinner then
            rawName = roll.name
            rawState = roll.state
        end
    end

    rawName = rawName or drop.winnerName
    rawState = rawState == nil and drop.winnerState or rawState

    local override = LootCredit.Get(drop)

    if override then
        local name = override.name or override.guid

        return {
            name = name,
            class = ClassOf(drop, name)
                or (SYL.Players and override.guid
                    and (SYL.Players.Get(override.guid) or {}).class)
                or nil,
            state = override.state == nil and rawState or override.state,
            source = "manual",
            priorName = rawName,
            priorState = rawState,
            setBy = override.setBy,
            setAt = override.setAt,
        }
    end

    if SYL.TradeTracker and SYL.TradeTracker.WasTraded(drop)
        and SYL.TradeTracker.IsEnabled()
    then
        return {
            name = drop.tradedTo,
            class = ClassOf(drop, drop.tradedTo),
            state = rawState,
            source = "traded",
            priorName = rawName,
            priorState = rawState,
        }
    end

    -- A FOURTH SOURCE, and the only one that says "nobody has looked".
    --
    -- On a master-looted night the client reports the master looter as the
    -- winner of everything, so "I checked this and it is mine" and "this has
    -- never been looked at" both arrived here as source = "roll" and drew the
    -- same words. Aimee: "that way its clear what i received vs what i won as
    -- ml."
    --
    -- The name and the state are unchanged. Nothing is withheld from any
    -- fairness figure -- see DropRules.NeedsReview for why marking beats
    -- withholding.
    if SYL.DropRules.NeedsReview(drop) then
        return {
            name = rawName,
            class = ClassOf(drop, rawName) or drop.winnerClass,
            state = rawState,
            source = "masterloot",
        }
    end

    return {
        name = rawName,
        class = ClassOf(drop, rawName) or drop.winnerClass,
        state = rawState,
        source = "roll",
    }
end
