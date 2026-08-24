-- Core/GearTrack.lua
--
-- Which upgrade track an item came from, as the single letter the Raiders
-- detail pane prints beside it: V for Veteran, C for Champion, H for Hero,
-- M for Myth, and E and A for the two leveling tracks below them.
--
-- NOT FROM THE DIFFICULTY, which is the obvious idea and is wrong. Her own
-- database disproves it: item levels 279 and 285 appear under BOTH Normal and
-- Looking For Raid, and her Normal drops run from 279 to 302, which is more
-- than one track's worth. Decoding her links directly, bonus ids 12825 to
-- 12828 sit on ilvl 279/282/285/289 and 12833 to 12836 on 292/295/298/302 --
-- two consecutive ladders, so a Normal drop at 285 is Veteran and a Normal
-- drop at 295 is Champion. A difficulty mapping prints C for both.
--
-- NOT FROM THE BONUS IDS EITHER, tempting as that is once you have decoded
-- them. Those numbers are re-issued every season; a table of them is wrong the
-- month after it is written, and ten of the forty-four raid records already in
-- her database carry bonus ids no shipped table on this machine knows.
--
-- The client knows. C_Item.GetItemUpgradeInfo takes a link -- not an owned
-- item, not an inventory slot, a link -- and answers for anything, including
-- somebody else's drop. Seven addons already installed here call it exactly
-- this way.
--
-- THREE-VALUED ON PURPOSE. nil means "not known", and nil must be drawn as
-- nothing rather than guessed at. An item the client has not cached yet
-- answers nil and will answer properly a moment later; a crafted or PvP piece
-- has an upgrade level but no track at all and answers nil forever. Both are
-- blank, and blank is the honest picture.

local SYL = _G.ShowUsYourLoot

local GearTrack = {}
SYL.GearTrack = GearTrack

-- The track's name as the client reports it, mapped to the letter.
--
-- KEYED ON THE NAME, WHICH IS LOCALIZED, so every language this addon can be
-- run in needs its own entries or its players get blanks. That is the same
-- shape EllesmereUI ships for the same API and the same reason.
--
-- Written as literal characters rather than as Lua decimal escapes. A comment
-- in this repository once carried "\194\187" through a heredoc and came out as
-- two bytes of garbage on screen; tools/syl_check.py now refuses control bytes
-- because of it. Accented and non-Latin names go in as themselves.
local LETTERS = {
    -- Explorer
    ["Explorer"] = "E", ["Expedicionario"] = "E", ["Forscher"] = "E",
    ["Explorateur"] = "E", ["Esploratore"] = "E", ["Explorador"] = "E",
    ["Исследователь"] = "E", ["탐험가"] = "E", ["探索者"] = "E",
    ["探險者"] = "E", ["Delve"] = "E",

    -- Adventurer
    ["Adventurer"] = "A", ["Aventurero"] = "A", ["Abenteurer"] = "A",
    ["Aventurier"] = "A", ["Avventuriero"] = "A", ["Aventureiro"] = "A",
    ["Искатель приключений"] = "A", ["모험가"] = "A", ["冒险者"] = "A",
    ["冒險者"] = "A",

    -- Veteran
    ["Veteran"] = "V", ["Veterano"] = "V", ["Vétéran"] = "V",
    ["Ветеран"] = "V", ["노련가"] = "V", ["老兵"] = "V", ["精兵"] = "V",

    -- Champion
    ["Champion"] = "C", ["Campeón"] = "C", ["Campione"] = "C",
    ["Campeão"] = "C", ["Защитник"] = "C", ["챔피언"] = "C",
    ["勇士"] = "C",

    -- Hero
    ["Hero"] = "H", ["Héroe"] = "H", ["Held"] = "H", ["Héros"] = "H",
    ["Eroe"] = "H", ["Herói"] = "H", ["Heroí"] = "H",
    ["Герой"] = "H", ["영웅"] = "H",
    ["英雄"] = "H",

    -- Myth
    ["Myth"] = "M", ["Mito"] = "M", ["Mythos"] = "M", ["Mythe"] = "M",
    ["Легенда"] = "M", ["신화"] = "M", ["神话"] = "M", ["神話"] = "M",
}

-- What each letter stands for, spelled out. The pane prints the letter; the
-- tooltip that explains a card prints this, because "V" is only obvious to
-- somebody who already knows.
GearTrack.NAMES = {
    E = "Explorer",
    A = "Adventurer",
    V = "Veteran",
    C = "Champion",
    H = "Hero",
    M = "Myth",
}

GearTrack.ORDER = { "E", "A", "V", "C", "H", "M" }

-- WHAT THE RAID DIFFICULTY IMPLIES, for items the upgrade API will not answer
-- for.
--
-- TIER TOKENS HAVE NO TRACK ON THEM AT ALL. Aimee, who settled this: "there is
-- no track on the token. but champion drops from normal and hero drops from
-- heroic, mythic from mythic. veteran from lfr." A token is
-- Enum.ItemClass.Miscellaneous rather than equipment, so
-- C_Item.GetItemUpgradeInfo has nothing to say about it -- three addons
-- installed on this machine gate that same call behind an equipment test for
-- the same reason.
--
-- So the track is read off the difficulty the thing dropped on, which the
-- addon already records on every drop.
--
-- THIS IS NOT A TABLE OF BONUS IDS, and the distinction matters. The header
-- above refuses to build on bonus ids because they are re-issued every season
-- and a table of them is wrong the month after it is written. Difficulty ids
-- are not like that: 14, 15, 16 and 17 have meant Normal, Heroic, Mythic and
-- Looking For Raid for a decade, and Core/Utilities.lua's RAID_DIFFICULTIES
-- has depended on exactly that since this addon was written.
GearTrack.BY_DIFFICULTY = {
    [17] = "V",     -- Looking For Raid
    [151] = "V",    -- Timewalking LFR
    [14] = "C",     -- Normal
    [33] = "C",     -- Timewalking raid
    [15] = "H",     -- Heroic
    [16] = "M",     -- Mythic
}

-- The letter for a link, or nil when nothing can say.
--
-- `difficultyID` is optional and is only consulted when the client has no
-- answer of its own. The API wins wherever it speaks, because it knows about
-- upgrades and the difficulty does not: a Champion piece crested up to Hero
-- still dropped on Normal, and the item is what it is now rather than what it
-- was when it fell.
--
-- pcall'd like every other client call in this addon: GetItemUpgradeInfo is
-- newer than most of the API surface here, and a missing function has to read
-- as "no answer" rather than as an error thrown out of a draw.
function GearTrack.LetterFor(itemLink, difficultyID)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    if C_Item and C_Item.GetItemUpgradeInfo then
        local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemLink)

        if ok and type(info) == "table" then
            local letter = LETTERS[info.trackString or ""]

            if letter then
                return letter
            end
        end
    end

    return GearTrack.BY_DIFFICULTY[difficultyID]
end

-- The letter and how far up the track it is, for the tooltip: "Champion 3 of
-- 6". The maximum is read from the client rather than assumed, because it is
-- not the same number every season -- it was 8, it is 6 now, and a hardcoded
-- "/8" would be a wrong fact printed confidently.
function GearTrack.Describe(itemLink, difficultyID)
    local letter = GearTrack.LetterFor(itemLink, difficultyID)

    if not letter then
        return nil
    end

    if not C_Item or not C_Item.GetItemUpgradeInfo then
        return GearTrack.NAMES[letter]
    end

    local ok, info = pcall(C_Item.GetItemUpgradeInfo, itemLink)

    if not ok or type(info) ~= "table" then
        -- A TIER TOKEN LANDS HERE, and it is right that it says "Champion"
        -- and stops. The letter came from the difficulty, so there is no
        -- current level to report -- and "Champion 1 of 6" would be a number
        -- invented to fill the shape of the sentence.
        return GearTrack.NAMES[letter]
    end

    local name = GearTrack.NAMES[letter] or letter
    local at = info.currentLevel
    local most = info.maxLevel

    if type(at) ~= "number" or type(most) ~= "number" or most <= 0 then
        return name
    end

    return string.format("%s %d of %d", name, at, most)
end
