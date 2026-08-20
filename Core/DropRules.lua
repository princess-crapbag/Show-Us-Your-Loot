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
