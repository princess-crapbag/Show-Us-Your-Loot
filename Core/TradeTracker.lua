-- Core/TradeTracker.lua
--
-- Whether the item you won was actually handed over, and to whom.
--
-- E2, and it is a correctness fix wearing a feature's clothes. Group Loot's
-- defining mechanic is that a win is tradable for two hours, and until now
-- nothing here noticed when that happened — so **every traded item was two
-- wrong numbers**: the winner kept credit for loot they gave away, and the
-- person who is wearing it looked like they had gone without.
--
-- ONLY THE WINNER'S CLIENT CAN KNOW. There is no event for "somebody else
-- traded something", so this is a self-report in exactly the way gear and the
-- vault are. Two people running the addon do not see each other's trades, and
-- a guild where only the officer runs it sees only the officer's. That is a
-- real limit and the numbers do not pretend otherwise — an untracked trade
-- leaves the credit where it was, which is what happens today.
--
-- THE TRADE FRAME NAMES A PLAYER, NOT A GUID. Blizzard gives
-- TradeFrameRecipientNameText and nothing else, so credit is resolved by name
-- through the same registry every other name goes through. A name that two
-- realms share resolves to nobody rather than to a guess, which is the rule
-- Core/Players.lua already made.
--
-- THE EVENT ORDER IS THE FIDDLY PART, and it is why the snapshot exists.
-- TRADE_ACCEPT_UPDATE fires while both sides are still deciding and the slots
-- are still readable; by the time the trade has completed the frame is closed
-- and GetTradePlayerItemLink answers nothing. So the slots are captured when
-- both sides have accepted, and committed only when
-- LE_GAME_ERR_TRADE_COMPLETE confirms it landed. Capturing at completion
-- records nothing; committing at acceptance records trades that were
-- canceled a moment later.

local SYL = _G.ShowUsYourLoot

local TradeTracker = {}
SYL.TradeTracker = TradeTracker

-- Six tradable slots. The seventh is the "will not be traded" slot and is
-- deliberately not read: an item sitting there is being shown, not given.
local TRADE_SLOTS = 6

local pending

function TradeTracker.IsEnabled()
    return SYL.Features.IsEnabled("tradeTracking")
end

--------------------------------------------------------------------------
-- The credit rule
--------------------------------------------------------------------------

-- THE ONE CHOKE POINT. Core/DueList.lua and Core/LootScore.lua both call this
-- with whatever identity they were about to credit, and it hands back the one
-- that should actually be credited. Two lists that disagree about who won an
-- item is how an officer stops trusting both, so neither is allowed its own
-- opinion about this.
--
-- Returns the raw identity, before alt folding. The caller still puts it
-- through Players.ResolveToMain, which stays the single place alt identity is
-- applied.
--
-- GUID FIRST, AND THIS COST AN HOUR. The trade frame only ever names a player,
-- but the maths is keyed by GUID — so crediting the bare name moved the points
-- to a key nothing else in the addon uses. They left the winner and arrived
-- nowhere, which is worse than not moving them. tradedToGUID is resolved at
-- commit time off the roll list, where the recipient nearly always already is.
function TradeTracker.CreditedIdentity(drop, rawIdentity)
    if not drop or not TradeTracker.IsEnabled() then
        return rawIdentity
    end

    if drop.tradedToGUID and drop.tradedToGUID ~= "" then
        return drop.tradedToGUID
    end

    if drop.tradedTo and drop.tradedTo ~= "" then
        return drop.tradedTo
    end

    return rawIdentity
end

function TradeTracker.WasTraded(drop)
    return (drop and drop.tradedTo and drop.tradedTo ~= "") and true or false
end

--------------------------------------------------------------------------
-- Matching an offered item to a win
--------------------------------------------------------------------------

-- Exact link first, item id second. Two wins of the same item id at different
-- item levels are different links, and crediting the wrong one would move
-- points between two real people — so the precise answer is tried before the
-- loose one, and the loose one only ever runs when no link matched.
local function MatchEntry(active, link)
    if not link then
        return nil
    end

    for _, entry in ipairs(active) do
        if entry.record.itemLink == link then
            return entry
        end
    end

    local itemID = SYL.Utilities.GetItemIDFromLink(link)

    if not itemID then
        return nil
    end

    for _, entry in ipairs(active) do
        if entry.record.itemID == itemID then
            return entry
        end
    end

    return nil
end

TradeTracker.MatchEntry = MatchEntry

--------------------------------------------------------------------------
-- Turning a name into somebody the maths knows
--------------------------------------------------------------------------

-- Realm-insensitive, because the trade frame gives a bare name and roll lists
-- do not always. Two people in one raid with the same name on different realms
-- would be ambiguous — that resolves to nobody rather than to a guess, which
-- is the rule Core/Players.lua already set for exactly this.
local function ShortName(name)
    if type(name) ~= "string" then
        return nil
    end

    return (name:match("^([^-]+)") or name):lower()
end

-- The roll list is the best source there is: the person you traded to is
-- nearly always one of the people who rolled and lost, and unlike the trade
-- frame the roll list carries their GUID.
function TradeTracker.ResolveRecipientGUID(record, recipient)
    local wanted = ShortName(recipient)

    if not wanted then
        return nil
    end

    local found, ambiguous

    for _, roll in ipairs((record and record.rolls) or {}) do
        if roll.guid and ShortName(roll.name) == wanted then
            if found and found ~= roll.guid then
                ambiguous = true
            end

            found = roll.guid
        end
    end

    if ambiguous then
        return nil
    end

    if found then
        return found
    end

    -- Not on the roll list — traded to somebody who was not eligible, which is
    -- ordinary for an offspec handout. The registry is the fallback, and it
    -- already answers false rather than a guess when two realms share the name.
    local guid = SYL.Players.GUIDForName(recipient)

    return guid or nil
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local function ReadRecipient()
    if not TradeFrameRecipientNameText
        or not TradeFrameRecipientNameText.GetText
    then
        return nil
    end

    local name = TradeFrameRecipientNameText:GetText()

    if type(name) ~= "string" or name == "" then
        return nil
    end

    return SYL.Utilities.NormalizePlayerName(name)
end

local function ReadOfferedLinks()
    local links = {}

    if not GetTradePlayerItemLink then
        return links
    end

    for slot = 1, TRADE_SLOTS do
        local link = GetTradePlayerItemLink(slot)

        if link then
            table.insert(links, link)
        end
    end

    return links
end

function TradeTracker.OnTradeShow()
    if not TradeTracker.IsEnabled() then
        return
    end

    pending = { recipient = ReadRecipient(), links = {} }
end

-- Both sides accepted, so the slots are final and still readable. Re-read the
-- recipient here too: TRADE_SHOW can fire before the name text is populated.
function TradeTracker.OnAcceptUpdate(playerAccepted, targetAccepted)
    if not TradeTracker.IsEnabled() then
        return
    end



    if not playerAccepted or not targetAccepted then
        return
    end

    pending = pending or {}
    pending.recipient = ReadRecipient() or pending.recipient
    pending.links = ReadOfferedLinks()
end

function TradeTracker.OnTradeClosed()
    pending = nil
end

-- Returns how many wins were credited, so a caller can tell "nothing was
-- traded" from "the trade held nothing this addon recorded".
function TradeTracker.Commit()
    if not TradeTracker.IsEnabled() or not pending then
        return 0
    end

    local recipient = pending.recipient
    local links = pending.links or {}

    pending = nil

    if not recipient or #links == 0 then
        return 0
    end

    local active = SYL.TradeAdvisor.Active()

    if #active == 0 then
        return 0
    end

    local credited = 0

    for _, link in ipairs(links) do
        local entry = MatchEntry(active, link)

        if entry then
            entry.record.tradedTo = recipient
            entry.record.tradedToGUID =
                TradeTracker.ResolveRecipientGUID(entry.record, recipient)
            entry.record.tradedAt = time()

            -- It has been handed over, so it is no longer a decision waiting
            -- to be made. Leaving it in the advisor would keep asking the
            -- winner to choose somebody they have already chosen.
            SYL.TradeAdvisor.Dismiss(entry.id)

            credited = credited + 1
        end
    end

    if credited > 0 and SYL.TradeAdvisorPanel then
        SYL.TradeAdvisorPanel.Refresh()
    end

    return credited
end

function TradeTracker.OnInfoMessage(messageType)
    if not TradeTracker.IsEnabled() then
        return
    end

    -- The constant is missing on some clients, and comparing against nil would
    -- commit on every info message — including "your bags are full".
    if LE_GAME_ERR_TRADE_COMPLETE == nil then
        return
    end

    if messageType ~= LE_GAME_ERR_TRADE_COMPLETE then
        return
    end

    TradeTracker.Commit()
end

-- For tests and for /syl dev: what is staged but not yet committed.
function TradeTracker.GetPending()
    return pending
end
