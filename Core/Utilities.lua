-- Core/Utilities.lua
--
-- Small, dependency-free helpers shared across the addon.
-- Nothing in this file may touch the database or create frames.

local SYL = _G.ShowUsYourLoot

local Utilities = {}
SYL.Utilities = Utilities

function Utilities.Trim(text)
    if type(text) ~= "string" then
        return nil
    end

    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utilities.GetPlayerFullName()
    local name, realm = UnitFullName("player")

    if not name then
        return "Unknown"
    end

    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

-- Strips color codes and trailing punctuation from a name pulled out of a
-- chat message, which is never guaranteed to be clean.
function Utilities.NormalizePlayerName(name)
    if not name or name == "" then
        return "Unknown"
    end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    name = name:gsub("[%.,:]+$", "")

    return name
end

-- The loot method, and the master looter's name when there is one.
--
-- Returns two values so a caller can tell "not master loot" from "master loot
-- and I could not read who". GetLootMethod answers the raid index of the
-- master looter, which has to be turned into a name through the raid roster;
-- a nil there is ordinary while the group is still forming.
local function MasterLooter()
    if not _G.GetLootMethod then
        return nil, nil
    end

    local ok, method, partyIndex, raidIndex = pcall(GetLootMethod)

    if not ok or method ~= "master" then
        return method, nil
    end

    local unit

    if raidIndex and raidIndex > 0 then
        unit = "raid" .. raidIndex
    elseif partyIndex == 0 then
        unit = "player"
    elseif partyIndex then
        unit = "party" .. partyIndex
    end

    if not unit then
        return method, nil
    end

    local named, name, realm = pcall(UnitFullName, unit)

    if not named or not name then
        return method, nil
    end

    return method, (realm and realm ~= "" and (name .. "-" .. realm)) or name
end

function Utilities.GetLocationInformation()
    local zoneName =
        GetRealZoneText()
        or GetZoneText()
        or "Unknown"

    local instanceName,
        instanceType,
        difficultyID,
        difficultyName,
        maxPlayers,
        dynamicDifficulty,
        isDynamic,
        instanceID,
        instanceGroupSize =
        GetInstanceInfo()

    local inInstance =
        select(1, IsInInstance())

    local lootMethod, masterLooter = MasterLooter()

    return {
        zoneName = zoneName,
        instanceName = instanceName or zoneName,
        instanceType = instanceType or "none",
        difficultyID = difficultyID or 0,
        difficultyName = difficultyName or "None",
        maxPlayers = maxPlayers or 0,
        instanceID = instanceID or 0,
        instanceGroupSize = instanceGroupSize or 0,
        inInstance = inInstance or false,
        inRaidGroup = IsInRaid(),
        inGroup = IsInGroup(),

        -- WHO IS HANDING OUT THE LOOT, and by what method.
        --
        -- The addon had no master-looter awareness at all -- GetLootMethod,
        -- IsMasterLooter and masterLooter did not appear anywhere in it. That
        -- is why every drop on a master-looted night reads as the master
        -- looter's win and nothing can tell a drop somebody reviewed and kept
        -- from one nobody has looked at.
        --
        -- pcall'd and read here rather than at each call site, because this
        -- is already the one place the addon asks the client where it is.
        lootMethod = lootMethod,
        masterLooter = masterLooter,
    }
end

function Utilities.GetItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    return tonumber(itemLink:match("|?H?item:(%d+)"))
end

-- A link the chat box will accept.
--
-- Chat capture stored only the |Hitem:…|h[Name]|h part, dropping the |cff…
-- color prefix and the |r that closes it. That renders fine in a font string,
-- which is why it went unnoticed, but shift-clicking such a row inserted a
-- broken link into chat: the recipient sees raw escape codes rather than an
-- item, which for an addon whose whole subject is items is not a small thing.
--
-- The client can rebuild it, since the item id inside the fragment is intact.
-- Uncached items have no answer yet and keep what they had, which is no worse
-- than before and fixes itself on the next hover.
function Utilities.NormalizeItemLink(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return itemLink
    end

    if itemLink:find("|c", 1, true) then
        return itemLink
    end

    local _, fullLink = C_Item.GetItemInfo(itemLink)

    return fullLink or itemLink
end

function Utilities.GetItemNameFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    return itemLink:match("%[(.-)%]")
end

-- The effective item level of a link, or nil when the client has not cached
-- the item yet.
--
-- Nothing recorded an item level, so every acquisition weighed the same: a
-- Champion piece out of a +7 and a Myth piece out of the vault both counted
-- as "they got something", and the due list ranked a raider who took one of
-- each below a raider who took two Veteran rings. This stores the number.
-- What the fairness math does with it is a separate decision and has
-- deliberately not been made here — changing how the ranking is weighted is
-- not a bug fix, and it should not arrive as a side effect of one.
--
-- Crest upgrades stay invisible regardless. Spending crests fires no loot
-- event of any kind, so an item that goes from Champion 1 to Champion 8 is
-- unobservable from here; only its level at the moment it dropped is known.
function Utilities.GetItemLevel(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local success, level = pcall(function()
        return C_Item.GetDetailedItemLevelInfo(itemLink)
    end)

    if not success then
        return nil
    end

    return level
end

-- Bind on Equip, as far as the client will say.
--
-- Aimee's rule: a BoE does not reset a raid drought. Somebody who wins a BoE
-- has won something sellable, not the tier piece the drought is measuring, and
-- resetting their clock for it pushes a genuinely starved raider down the list.
--
-- THREE ANSWERS, NOT TWO. nil means the client has not cached the item yet and
-- genuinely does not know. Callers must not read that as "yes": treating an
-- uncached item as a BoE would silently stop counting real upgrades, and the
-- failure would look exactly like the drought math being broken. Not-BoE is
-- the safe default because it is the answer that keeps counting.
--
-- bindType is field 14 of GetItemInfo, and 2 is Bind on Equip. Read from the
-- link at the time the question is asked rather than stored at capture, so
-- this works on the history already recorded instead of only on new drops.
local BIND_ON_EQUIP = 2

function Utilities.IsBindOnEquip(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local success, bindType = pcall(function()
        return select(14, C_Item.GetItemInfo(itemLink))
    end)

    if not success or type(bindType) ~= "number" then
        return nil
    end

    return bindType == BIND_ON_EQUIP
end

-- Warbound gear: account-wide rather than stuck on the character that won it.
--
-- EXCLUDED FROM THE NUMBERS, LIKE A BoE, and for the same reason. The rule
-- already written down is that a drought resets on a bind-on-pickup win —
-- gear this character now has to wear. A warbound item can be posted to any
-- character on the account, so it is account gear rather than this raider's
-- upgrade, and counting it would say somebody was looked after when the raider
-- who was standing there may not have been. Aimee's call.
--
-- READ FROM THE LIVE ENUM, with the observed numbering as a fallback, the same
-- way Core/LootHistoryAPI.lua handles the roll states. Bind types are Blizzard
-- constants and a renamed key here would silently start counting warbound
-- gear again — /syl api prints what the client actually exposes so the fallback
-- can be checked rather than trusted.
--
-- CHECKED, ON 12.1.0 BUILD 69382, 2026-08-19. This is the verification HANDOFF
-- had open, and the answer is in two halves.
--
-- The good half: Enum.ItemBind is present, so the live values are what get
-- used, and they are 7, 8, 9 — warbound gear is correctly excluded.
--
-- The other half: every key below was mapped to the wrong number. The client
-- reports ToWoWAccount=7, ToBnetAccount=8, ToBnetAccountUntilEquipped=9, and
-- this table had 9, 7, 8. It never mattered, because the three values are only
-- ever used as a set to test membership against, and {9,7,8} is the same set
-- as {7,8,9} — so the fallback would have behaved correctly even if it had
-- been reached. Corrected anyway: it is documented as "the observed
-- numbering", it was not, and the next person to read a single key out of it
-- would be reading a wrong answer that this file vouches for.
local WARBOUND_KEYS = {
    ToWoWAccount = 7,
    ToBnetAccount = 8,
    ToBnetAccountUntilEquipped = 9,
}

local warboundValues

local function WarboundValues()
    if warboundValues then
        return warboundValues
    end

    warboundValues = {}

    for key, fallback in pairs(WARBOUND_KEYS) do
        local value = fallback

        if type(Enum) == "table"
            and type(Enum.ItemBind) == "table"
            and type(Enum.ItemBind[key]) == "number"
        then
            value = Enum.ItemBind[key]
        end

        warboundValues[value] = true
    end

    return warboundValues
end

-- Exposed so /syl api can print what this resolved to on the live client.
function Utilities.WarboundBindTypes()
    local values = {}

    for value in pairs(WarboundValues()) do
        table.insert(values, value)
    end

    table.sort(values)

    return values
end

-- nil for "cannot tell", which every caller treats as not warbound. An
-- uncached item answers nothing, and the safe default is the one that keeps
-- counting rather than the one that quietly stops.
function Utilities.IsWarbound(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local success, bindType = pcall(function()
        return select(14, C_Item.GetItemInfo(itemLink))
    end)

    if not success or type(bindType) ~= "number" then
        return nil
    end

    return WarboundValues()[bindType] == true
end

-- MM-DD-YYYY throughout, which is where Aimee reads dates.
--
-- Three formats were in use before this: %m/%d/%Y, %m/%d/%y and %Y-%m-%d,
-- depending on which file drew the row. The ISO one is still used for two
-- things that are NOT dates on screen — RaidSession's night key and the
-- season id — and those must not be touched, because changing them re-keys
-- every night already recorded.
function Utilities.FormatDateTime(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%Y %I:%M %p", timestamp)
end

-- A WALL CLOCK, which is how a raid night is remembered. "6:42 PM".
--
-- Aimee: "the time should be in 12 hours am/pm format rather than 24 hour
-- format." The leading zero goes because "06:42 PM" is not how anybody says
-- it and the pane is tight for width.
function Utilities.FormatClock(timestamp)
    if not timestamp then
        return "?"
    end

    return (date("%I:%M %p", timestamp):gsub("^0", ""))
end

-- The player's own time zone, short. "MST", "EST".
--
-- The client answers a long name on most systems -- "Mountain Standard Time"
-- -- so the capitals are taken, which is how those names abbreviate in every
-- locale that has them. Anything that does not reduce to two to five capitals
-- answers nothing rather than a guess, and the caller simply omits the zone.
function Utilities.TimeZoneLabel()
    local ok, name = pcall(date, "%Z")

    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end

    if #name <= 5 then
        return name
    end

    local short = name:gsub("[^A-Z]", "")

    if #short >= 2 and #short <= 5 then
        return short
    end

    return nil
end

-- The list columns' version. "08/05/26 12:32 PM" is seventeen characters
-- against a column that also has to share a row with an item name, and it was
-- the format, not the width, that made the date column impossible. Dropping
-- to a 24 hour clock loses the " PM" and three characters with it, and stays
-- unambiguous.
--
-- THE ONE PLACE THE YEAR STAYS TWO DIGITS. The DATE column is 96px and this
-- string already had to be cut down once to fit it; a four digit year puts
-- two characters straight back. Same US order and same separator as
-- everywhere else, so it does not read as a different format — just shorter.
function Utilities.FormatDateCompact(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%y %H:%M", timestamp)
end

-- Difficulty names are long enough to break any column they land in:
-- "Looking For Raid" is sixteen characters against boss and player names
-- that are shorter. Every list shows the short form instead.
local DIFFICULTY_SHORT = {
    [1] = "5N",
    [2] = "5H",
    [8] = "M+",
    [14] = "N",
    [15] = "HC",
    [16] = "M",
    [17] = "LFR",
    [23] = "5M",
    [24] = "TW",
    [33] = "TW",
    [151] = "LFR TW",
    [205] = "Fol",
    [208] = "Delve",
    [220] = "Story",
}

function Utilities.ShortDifficulty(difficultyID, difficultyName)
    local short = DIFFICULTY_SHORT[difficultyID]

    if short then
        return short
    end

    if difficultyName
        and difficultyName ~= ""
        and difficultyName ~= "None"
    then
        -- An id this does not know yet. Initials beat truncation: "Looking
        -- For Raid" becomes LFR rather than "Looking Fo…".
        local initials = ""

        for word in difficultyName:gmatch("%a+") do
            initials = initials .. word:sub(1, 1):upper()
        end

        if #initials >= 2 then
            return initials
        end

        return difficultyName
    end

    return nil
end

-- Raid or dungeon, which the addon had no way of telling apart.
--
-- This matters more than a filter: RaidSession opened a night for anything
-- inside an instance, so a Mythic+ run recorded a five person raid night and
-- inflated attendance and the drought numbers that rank the due list.
--
-- GetInstanceInfo's instanceType is the authority — "raid" or "party" — but
-- it was never stored, so records written before this cannot be asked. The
-- difficulty id answers for those: dungeon and raid difficulties come from
-- disjoint sets and every record has one.
local RAID_DIFFICULTIES = {
    [3] = true, [4] = true,     -- 10 and 25 player, legacy
    [5] = true, [6] = true,     -- 10 and 25 player heroic, legacy
    [7] = true,                 -- LFR, legacy
    [9] = true,                 -- 40 player
    [14] = true, [15] = true, [16] = true,
    [17] = true,                -- LFR
    [18] = true,                -- Event, 40 player
    [33] = true,                -- Timewalking raid
    [151] = true,               -- Timewalking LFR
    [220] = true,               -- Story
}

local DUNGEON_DIFFICULTIES = {
    [1] = true, [2] = true,     -- Normal and Heroic
    [8] = true,                 -- Mythic Keystone
    [19] = true,                -- Event, 5 player
    [23] = true,                -- Mythic
    [24] = true,                -- Timewalking
    [205] = true,               -- Follower
}

-- Delves are the one that mattered. GetInstanceInfo reports them as
-- "scenario", which nothing here handled, so every delve drop was filed as
-- world loot alongside a quest reward picked up in Dornogal. A delve is
-- instanced content that awards gear on a track, and calling it "world" put
-- it in the one bucket the fairness math ignores hardest.
--
-- Torghast and the Visions are in here for the same reason: instanced, not a
-- raid, not a dungeon, and previously answering "other".
local SCENARIO_DIFFICULTIES = {
    [11] = true, [12] = true,   -- Heroic and Normal scenario
    [20] = true,                -- Event scenario
    [152] = true,               -- Visions of N'Zoth
    [167] = true,               -- Torghast
    [208] = true,               -- Delves
}

-- Raid content that is not a raid team's night.
--
-- IsRaidContent decides whether a session opens, and instanceType wins over
-- the difficulty, so anything flagged "raid" by the client opened a night —
-- including a Story clear done alone on a Tuesday, which then sat in the
-- attendance history as a one-person raid and moved everybody's drought.
--
-- These are all scaled or off-schedule versions of a raid: real raid content
-- by instance type, but never the thing the roster is being measured on. They
-- still classify as "raid" for the loot list, because that is where the item
-- came from — only attendance excludes them.
local NOT_A_RAID_NIGHT = {
    [18] = true,                -- Event
    [33] = true,                -- Timewalking raid
    [151] = true,               -- Timewalking LFR
    [205] = true,               -- Follower
    [220] = true,               -- Story
}

function Utilities.GetContentType(instanceType, difficultyID)
    if instanceType == "raid" then
        return "raid"
    end

    if instanceType == "party" then
        return "dungeon"
    end

    if instanceType == "scenario" then
        return "scenario"
    end

    -- No instanceType stored, so fall back to the difficulty. Anything in
    -- none of the sets — arenas, an id this does not know yet — answers
    -- "other" rather than being guessed into one of them.
    if RAID_DIFFICULTIES[difficultyID] then
        return "raid"
    end

    if DUNGEON_DIFFICULTIES[difficultyID] then
        return "dungeon"
    end

    if SCENARIO_DIFFICULTIES[difficultyID] then
        return "scenario"
    end

    return "other"
end

-- Convenience for the places that only care whether something counts toward
-- raid attendance, which is the question the due list is really asking.
--
-- Deliberately narrower than GetContentType: see NOT_A_RAID_NIGHT above.
function Utilities.IsRaidContent(instanceType, difficultyID)
    if NOT_A_RAID_NIGHT[difficultyID] then
        return false
    end

    return Utilities.GetContentType(instanceType, difficultyID) == "raid"
end

function Utilities.FormatClockTime(timestamp)
    if not timestamp then
        return "--:--:--"
    end

    return date("%H:%M:%S", timestamp)
end

function Utilities.FormatDateOnly(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%m/%d/%Y", timestamp)
end

-- "1 night", "2 nights". The count and its noun, agreeing.
--
-- Thirteen strings concatenated a count with a hard-coded "s", so a guild's
-- first raid night read "1 nights this month" — on a screenshot that was
-- selling the addon on CurseForge. Four other places did guard it, each by
-- hand and each slightly differently, and that is exactly why it survived:
-- the problem looks solved wherever you happen to be reading.
--
-- `plural` is only needed for the words English does not finish with an s.
function Utilities.Count(count, singular, plural)
    count = tonumber(count) or 0

    if count == 1 then
        return count .. " " .. singular
    end

    return count .. " " .. (plural or (singular .. "s"))
end

function Utilities.CountKeys(value)
    if type(value) ~= "table" then
        return 0
    end

    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    return count
end

-- Returns the keys of a table sorted into a stable order so that debug output
-- and exports do not shuffle between reads.
function Utilities.GetSortedKeys(value)
    local keys = {}

    if type(value) ~= "table" then
        return keys
    end

    for key in pairs(value) do
        table.insert(keys, key)
    end

    table.sort(keys, function(left, right)
        local leftIsNumber = type(left) == "number"
        local rightIsNumber = type(right) == "number"

        if leftIsNumber and rightIsNumber then
            return left < right
        end

        if leftIsNumber ~= rightIsNumber then
            return leftIsNumber
        end

        return tostring(left) < tostring(right)
    end)

    return keys
end
