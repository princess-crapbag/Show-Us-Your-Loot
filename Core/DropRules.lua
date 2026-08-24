-- Core/DropRules.lua
--
-- Which drops count as an upgrade, and who gets credited for one.
--
-- THREE FILES ANSWERED THIS SEPARATELY AND ONE OF THEM WAS WRONG.
--
-- Core/LootScore.lua had a local `Counts`, whose comment said it was "the same
-- test the drought uses. Kept as one call so the two can never take different
-- views of the same drop" — and it was a second copy of that test, not the
-- same one. Core/DueList.lua had `CountsTowardsDrought`, the original. The two
-- did agree, by hand, which is the state a rule is in right before it stops
-- agreeing.
--
-- Core/Analytics.lua had neither, and that is where it cost something real. It
-- feeds the Players window's UPGRADES column and Core/Export.lua, which is the
-- block people paste into Discord — so a bind-on-equip win, a warbound win, a
-- Timewalking raid and a Mythic+ dungeon all counted as upgrades there and
-- counted as nothing on the Raiders board. The same raider had two different
-- numbers depending on which screen you asked, and the exported one is the one
-- other people read.
--
-- Analytics also credited whoever won the roll rather than whoever the item
-- was traded to, which for a master looter means every drop in the raid is
-- credited to them. That is Aimee.
--
-- So the rule lives here once, and the three of them ask.

local SYL = _G.ShowUsYourLoot

local DropRules = {}
SYL.DropRules = DropRules

-- Unknown counts, in both of the tests below, and it is deliberate in both.
--
-- Utilities.IsBindOnEquip answers nil for an item the client has not cached,
-- which is not the same as "no". Reading nil as "yes, exclude it" would
-- silently stop counting real upgrades in a way indistinguishable from the
-- math being broken — and the same argument applies one step out to warbound.
local function IsExcludedItem(drop)
    return SYL.Utilities.IsBindOnEquip(drop.itemLink) == true
        or SYL.Utilities.IsWarbound(drop.itemLink) == true
end

-- Records written before the location was stored carry neither field.
-- Treating unknown as "not a raid" would erase the upgrade history of
-- everything captured before that, so unknown counts. The drops list is group
-- loot only and retail dungeons award personal loot, so little else can be in
-- there anyway.
local function IsRaidDrop(drop)
    if not drop.instanceType and not drop.difficultyID then
        return true
    end

    return SYL.Utilities.IsRaidContent(drop.instanceType, drop.difficultyID)
end

-- Does this drop count as somebody's upgrade?
--
-- Aimee's rule, and the reason for each half: a bind-on-equip win is something
-- sellable rather than the tier piece a drought measures, and a warbound item
-- is account gear that can be posted to any character — so neither says the
-- raider standing there was looked after. Resetting a clock for either pushes
-- a genuinely starved raider down the list.
-- WAS THIS ONE OF OURS? Aimee, 2026-08-20, on finding an LFR run in her season
-- board: "why is LFR being counted? its not 80% + guild members so it doesnt
-- matter in the fairness log."
--
-- The calendar and the dashboard had applied the guild-share rule since it was
-- written; the fairness math had not, so a 49-person LFR run with one guildie
-- in it fed the same board her twelve raiders are ranked on.
--
-- THIS IS HALF OF A CHANGE. Core/RaidSession.lua's note on RaidsOnly spelled
-- out why it could not ship alone: dropping an LFR win while still counting
-- the LFR night divides every share by a number that includes a night nobody
-- can now earn anything on. Core/DueList.lua counts nights through NightsOnly
-- in the same commit as this line. If one of them is ever reverted, revert
-- both.
local function IsGuildNightDrop(drop)
    if not SYL.RaidSession then
        return true
    end

    return SYL.RaidSession.IsGuildNightAt(drop.timestamp)
end

function DropRules.CountsAsUpgrade(drop)
    if not drop or drop.excludedFromAnalytics then
        return false
    end

    if IsExcludedItem(drop) then
        return false
    end

    if not IsRaidDrop(drop) then
        return false
    end

    return IsGuildNightDrop(drop)
end

-- Who a win belongs to, once trading and any hand-made correction are taken
-- into account.
--
-- Master looters receive everything and hand it out, so without this every
-- drop in the raid lands on one person. Delegates rather than reimplements:
-- Core/TradeTracker.lua owns the "was this traded, and to whom" question and
-- resolves a GUID before a name for reasons its own comment explains at
-- length; Core/LootCredit.lua owns the "somebody said otherwise" question.
--
-- A CORRECTION BEATS AN OBSERVATION. If the addon watched a trade and was
-- told afterwards that the item went somewhere else, the person doing the
-- telling was in the raid and the addon was not. LootCredit answers first for
-- that reason, and answers with the raw identity when nothing was corrected,
-- so the trade rule still runs underneath it.
function DropRules.CreditedKey(drop, rawIdentity)
    if SYL.LootCredit and SYL.LootCredit.IsSet(drop) then
        return SYL.LootCredit.IdentityFor(drop, rawIdentity)
    end

    if not SYL.TradeTracker then
        return rawIdentity
    end

    return SYL.TradeTracker.CreditedIdentity(drop, rawIdentity)
end

-- The response a win is scored on, once a correction is taken into account.
--
-- THE WEIGHT IS WRONG AS OFTEN AS THE NAME IS, which is why this exists
-- beside CreditedKey rather than being folded into it. Under a loot council
-- the recorded state is the master looter's roll and not the recipient's
-- answer — on Aimee's 2026-08-18 raid six of eleven drops carried the wrong
-- weight and four of those were Transmog, which weighs nothing. A reassign
-- that moved only the name would have moved nothing at all on those four.
--
-- Feeds the drought as well as the score: Transmog corrected to Need has to
-- reset a clock, because it turned out to be gear.
function DropRules.CreditedState(drop, rawState)
    if not SYL.LootCredit then
        return rawState
    end

    return SYL.LootCredit.StateFor(drop, rawState)
end

-- WHO A DROP GAVE SOMETHING WORTH HAVING TO, or nil.
--
-- Returns the credited person's key, folded to their main, so a caller can
-- count PEOPLE rather than items. The night pane's "6 of 11 went home with
-- gear" is this, and the figure it replaced was a count of drop RECORDS read
-- off the raw roll state -- which on a master-looted night is the master
-- looter's roll, counted once per item.
--
-- MOG DOES NOT COUNT. Aimee: "i dont want to say someone went home with loot
-- if all they got was a mog item." Need, offspec and greed do.
--
-- THIS IS A WIDER SET THAN THE DROUGHT'S, deliberately. Core/DueList.lua
-- admits only need and offspec, because being owed loot is about upgrades.
-- This answers a different question -- did the evening give you anything --
-- and a greed win is something.
-- BUILT ON FIRST CALL, NOT AT LOAD. This file is fourth in the .toc and
-- Core/LootHistoryAPI.lua is fiftieth, so reading ROLL_STATE at file scope
-- indexes a nil and kills the whole file -- which is how it failed the first
-- time. Every screen downstream then reads as empty rather than as broken.
local worthHaving

local function WorthHavingStates()
    if worthHaving then
        return worthHaving
    end

    local states = SYL.LootHistoryAPI.ROLL_STATE

    worthHaving = {
        [states.NeedMainSpec] = true,
        [states.NeedOffSpec] = true,
        [states.Greed] = true,
    }

    return worthHaving
end

function DropRules.WorthHaving(drop)
    if not drop then
        return nil
    end

    local state = DropRules.CreditedState(drop, drop.winnerState)

    if not WorthHavingStates()[state] then
        return nil
    end

    local key = DropRules.CreditedKey(
        drop, drop.winnerGUID or drop.winnerName
    )

    if not key then
        return nil
    end

    return SYL.Players.ResolveToMain(key) or key
end

-- MIND THE NAME FORM. The master looter is stored with a realm --
-- "Arcangila-Area52", from Utilities.GetPlayerFullName -- and a drop's
-- winnerName is the bare "Arcangila" for somebody on your own realm.
-- Core/RaidSession.lua has a local doing exactly this comparison, and its
-- comment records what happened when the first version compared them
-- directly: it found nobody and quietly reported every night's guild share as
-- unknown, turning the whole filter off. Not exported from there because it
-- takes a roster member rather than a name.
local function SameName(left, right)
    if type(left) ~= "string" or type(right) ~= "string" then
        return false
    end

    return (left:match("^([^-]+)") or left)
        == (right:match("^([^-]+)") or right)
end

-- A DROP NOBODY HAS LOOKED AT YET, on a master-looted night.
--
-- Aimee: "when loot drops can it be listed as 'MasterLooter Won' and only
-- reassigned to me when i award it to me [...] that way its clear what i
-- received vs what i won as ml"
--
-- WHY THIS IS THE FIX AND AUTO-CREDITING IS NOT. Blizzard's Loot History
-- names the master looter as the winner of everything, so all eighteen drops
-- on her two guild nights record her. She corrects them by hand and the
-- corrections are what make the fairness board honest. The credit is not
-- wrong -- she checked two that looked like oversights against
-- RCLootCouncil's own award history and both are genuinely hers.
--
-- What was missing is that "I checked this and it is mine" and "nobody has
-- ever looked at this" rendered as the same thing: source = "roll", drawn as
-- "won the roll, never traded".
--
-- NOT USED BY ANY FAIRNESS FIGURE. Turning an unreviewed drop into a
-- non-drop would put eighteen items in limbo instead of two, and
-- Core/CreditCandidates.lua explains why the roll list cannot supply a
-- replacement: under a council everybody passes, so the only candidate the
-- client offers is the master looter. This marks; it does not withhold.
function DropRules.NeedsReview(drop)
    if not drop or SYL.LootCredit.IsSet(drop) then
        return false
    end

    local session =
        SYL.RaidSession.SessionAt(SYL.GetActiveRaids(), drop.timestamp)

    -- No `if not looter` guard: SameName refuses anything that is not a
    -- string, so a session that never recorded a master looter -- which is
    -- every session in the database before this shipped -- already answers
    -- false. A second check would be a branch no test could reach.
    return SameName(session and session.masterLooter, drop.winnerName)
end
