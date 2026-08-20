-- Core/Recovery.lua
--
-- Notices when a season's records have gone missing, and says so loudly.
--
-- WHY THIS IS NOT PARANOIA. If WoW cannot parse ShowUsYourLootDB.lua it throws
-- the whole file away and hands the addon an empty table. Everything then
-- behaves correctly for a database that has never been used: a fresh season is
-- built, the cheerful first-run line prints, and a tier of loot history is
-- gone with nothing on screen that looks like an error. The person finds out
-- weeks later when somebody asks why they are top of the due list.
--
-- Blizzard keeps one .bak, replaced every logout. So the recovery window is a
-- single session: log in twice after a corruption and the copy is gone too.
-- That is the whole reason this has to be noticed on the spot rather than
-- whenever somebody happens to look.
--
-- THE STAMP CANNOT LIVE IN THE FILE IT IS WATCHING. Storing "how much did I
-- have last time" inside ShowUsYourLootDB would lose it in the same accident.
-- It goes in SavedVariablesPerCharacter, which WoW writes to a different file
-- under a different folder — so an account-wide file that fails to load leaves
-- the character-level one intact, and vice versa.
--
-- ONLY A LOSS IS REPORTED. Totals are counted across the active season and
-- every archive together, because archiving moves records between the two
-- rather than removing them.
--
-- `/syl clear` is the one legitimate way for the number to fall, and it cannot
-- be handled by re-stamping alone. The stamp is per character; the database it
-- measures is per account. So clearing on the main healed the main and left
-- every other character holding a stamp from before the clear — each of them
-- shouting RECORDS ARE MISSING once, on their next login, and sending their
-- owner to recover a backup of a file nothing had happened to.
--
-- The account-wide mark below is what fixes that: a deliberate emptying is
-- recorded where every character can see it, and a stamp older than the last
-- one is not evidence of anything.

local SYL = _G.ShowUsYourLoot

local Recovery = {}
SYL.Recovery = Recovery

-- Where Blizzard puts the copy. Named in the warning because somebody who has
-- just lost a tier should not also have to find out where to look, and they
-- have one session to do it in.
local BACKUP_HINT =
    "WTF\\Account\\<ACCOUNT>\\SavedVariables\\ShowUsYourLoot.lua.bak"

local function Totals()
    local drops, loot = 0, 0

    local function Add(season)
        if type(season) ~= "table" then
            return
        end

        drops = drops + #(season.drops or {})
        loot = loot + #(season.loot or {})
    end

    Add(ShowUsYourLootDB and ShowUsYourLootDB.activeSeason)

    for _, archived in ipairs(ShowUsYourLootDB and ShowUsYourLootDB.archives or {}) do
        Add(archived)
    end

    return drops, loot
end

Recovery.Totals = Totals

-- Records what this character can see right now. Called after every load and
-- again after anything that legitimately empties a season.
function Recovery.Stamp()
    if type(ShowUsYourLootCharDB) ~= "table" then
        ShowUsYourLootCharDB = {}
    end

    local drops, loot = Totals()

    ShowUsYourLootCharDB.lastSeen = {
        drops = drops,
        loot = loot,
        at = time(),
    }

    return ShowUsYourLootCharDB.lastSeen
end

-- Records that somebody emptied a season on purpose, account-wide, so the
-- characters that were not logged in at the time do not read it as loss.
function Recovery.NoteDeliberateClear()
    if type(ShowUsYourLootDB) == "table" then
        ShowUsYourLootDB.lastDeliberateClear = time()
    end

    return Recovery.Stamp()
end

-- Returns the stamp and the current totals when records have gone missing, or
-- nil when they have not. Split from the printing so a test can ask the
-- question without a chat frame.
function Recovery.CheckForLoss()
    local stamp = type(ShowUsYourLootCharDB) == "table"
        and ShowUsYourLootCharDB.lastSeen
        or nil

    if type(stamp) ~= "table" then
        return nil
    end

    local drops, loot = Totals()

    -- Strictly fewer. Equal is the ordinary case and more is a raid night.
    if drops >= (stamp.drops or 0) and loot >= (stamp.loot or 0) then
        return nil
    end

    -- Somebody cleared a season deliberately, and this character's stamp
    -- predates it. Nothing was lost; this character simply was not logged in
    -- when it happened.
    local cleared = type(ShowUsYourLootDB) == "table"
        and ShowUsYourLootDB.lastDeliberateClear
        or nil

    if cleared and (stamp.at or 0) <= cleared then
        return nil
    end

    return stamp, { drops = drops, loot = loot }
end

-- Says it in the loudest register this addon has, and says what to do about it
-- while there is still time to do it.
function Recovery.Report()
    local stamp, now = Recovery.CheckForLoss()

    if not stamp then
        return false
    end

    SYL:Print(
        "RECORDS ARE MISSING. This character last saw "
        .. SYL.Utilities.Count(stamp.drops or 0, "drop")
        .. " and " .. SYL.Utilities.Count(stamp.loot or 0, "chat item")
        .. "; it can see " .. now.drops .. " and " .. now.loot .. " now."
    )

    SYL:Write(
        "  Nothing here deleted them. The usual cause is the saved variables "
        .. "file failing to load, which WoW handles by discarding it."
    )

    SYL:Write(
        "  There is one backup and it is replaced at every logout, so copy it "
        .. "BEFORE playing on: " .. BACKUP_HINT
    )

    SYL:Write(
        "  If this was you — /syl clear, or an archive you removed — it is "
        .. "expected, and this will not say it again."
    )

    return true
end
