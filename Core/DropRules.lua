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
function DropRules.CountsAsUpgrade(drop)
    if not drop or drop.excludedFromAnalytics then
        return false
    end

    if IsExcludedItem(drop) then
        return false
    end

    return IsRaidDrop(drop)
end

-- Who a win belongs to, once trading is taken into account.
--
-- Master looters receive everything and hand it out, so without this every
-- drop in the raid lands on one person. Delegates rather than reimplements:
-- Core/TradeTracker.lua owns the "was this traded, and to whom" question and
-- resolves a GUID before a name for reasons its own comment explains at
-- length.
function DropRules.CreditedKey(drop, rawIdentity)
    if not SYL.TradeTracker then
        return rawIdentity
    end

    return SYL.TradeTracker.CreditedIdentity(drop, rawIdentity)
end
