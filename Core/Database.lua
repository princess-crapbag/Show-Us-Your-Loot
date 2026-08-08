-- Database.lua

local SYL = _G.ShowUsYourLoot

local DATABASE_VERSION = 3

local function GenerateSeasonID()
    return "season-" .. date("%Y%m%d-%H%M%S")
end

local function CreateSeason(name)
    local timestamp = time()

    return {
        id = GenerateSeasonID(),
        name = name or "Current Season",

        createdAt = timestamp,
        startedAt = timestamp,
        archivedAt = nil,

        loot = {},

        -- Group-loot drops captured from Blizzard's Loot History API. Kept
        -- apart from `loot`, which holds chat-derived item records with a
        -- different shape and a compatibility alias pointing at it.
        drops = {},

        raids = {},
        players = {},
        bosses = {},

        settings = {
            locked = false,
        },
    }
end

local function EnsureSeasonStructure(season)
    season.loot = season.loot or {}
    season.drops = season.drops or {}
    season.raids = season.raids or {}
    season.players = season.players or {}
    season.bosses = season.bosses or {}

    season.settings = season.settings or {}

    if season.settings.locked == nil then
        season.settings.locked = false
    end

    season.createdAt = season.createdAt or time()
    season.startedAt = season.startedAt or season.createdAt
    season.id = season.id or GenerateSeasonID()
    season.name = season.name or "Unnamed Season"

    return season
end

local function InitializeSettings()
    ShowUsYourLootDB.settings = ShowUsYourLootDB.settings or {}

    if ShowUsYourLootDB.settings.debug == nil then
        ShowUsYourLootDB.settings.debug = false
    end

    if ShowUsYourLootDB.settings.announceCaptures == nil then
        ShowUsYourLootDB.settings.announceCaptures = true
    end

    -- Loot History is the primary source, so capture runs by default.
    if ShowUsYourLootDB.settings.lootHistoryCapture == nil then
        ShowUsYourLootDB.settings.lootHistoryCapture = true
    end

    -- Every quality is recorded until one is turned off, so a fresh install
    -- never quietly misses loot.
    if ShowUsYourLootDB.settings.trackedQualities == nil then
        ShowUsYourLootDB.settings.trackedQualities =
            SYL.ItemQuality.GetDefaults()
    end

    if ShowUsYourLootDB.settings.showMinimapButton == nil then
        ShowUsYourLootDB.settings.showMinimapButton = true
    end

    -- Chat window 1 by default, which is wherever the player already reads
    -- chat. Moving output is opt-in.
    if ShowUsYourLootDB.settings.chatFrameIndex == nil then
        ShowUsYourLootDB.settings.chatFrameIndex = 1
    end

    -- The only feature that sends anything to other players, so it stays off
    -- until it is turned on deliberately.
    if ShowUsYourLootDB.settings.syncEnabled == nil then
        ShowUsYourLootDB.settings.syncEnabled = false
    end

    -- Whether gear that arrived without a roll — the vault, a Mythic+ chest,
    -- a catalyst conversion — resets somebody's drought.
    --
    -- OFF, and this was the hardest default in the addon to get right.
    --
    -- The argument for on is real: a large share of retail gearing never
    -- touches a roll, so with this off the due list is blind to a whole
    -- channel and reports raiders as starved who are not.
    --
    -- The argument for off is that the data cannot support it, and defaults
    -- to a bias that runs one way. CHAT_MSG_LOOT only ever sees your own
    -- loot plus your current group's. Nobody claims a vault while standing
    -- next to the officer running this addon, so with it on the only vault
    -- claims in the database are the officer's own. Their drought resets
    -- every week and nobody else's ever does, and the officer sinks to the
    -- bottom of a list they wrote. That is worse than being blind: it is
    -- confidently wrong, in a direction that looks like modesty.
    --
    -- So it stays a setting, because for a guild where everybody runs the
    -- addon and syncs, on is the better answer. It just cannot be the
    -- default until the sync can fill the gap (see F8/E8 in HANDOFF.md).
    if ShowUsYourLootDB.settings.countPersonalLoot == nil then
        ShowUsYourLootDB.settings.countPersonalLoot = false
    end

    -- Which colour scheme the window wears. Stored as a key rather than as
    -- colour values, so editing a palette improves every existing install
    -- instead of only new ones.
    --
    -- Taken from Palettes rather than repeated here: two copies of a default
    -- drift, and the one that loses is always the one nobody remembers.
    -- This runs at ADDON_LOADED, by which point every file has loaded.
    if ShowUsYourLootDB.settings.palette == nil then
        ShowUsYourLootDB.settings.palette = SYL.Palettes.DEFAULT
    end
end

local function MigrateOldLootDatabase()
    local oldLoot = ShowUsYourLootDB.loot

    if type(oldLoot) ~= "table" or #oldLoot == 0 then
        return false
    end

    local season = CreateSeason("Imported Loot")

    for _, record in ipairs(oldLoot) do
        table.insert(season.loot, record)
    end

    ShowUsYourLootDB.activeSeason = season

    return true
end

function SYL.DatabaseInitialize()
    ShowUsYourLootDB = ShowUsYourLootDB or {}

    InitializeSettings()

    ShowUsYourLootDB.archives = ShowUsYourLootDB.archives or {}
    ShowUsYourLootDB.recentRecordIDs =
        ShowUsYourLootDB.recentRecordIDs or {}


    -- Account level, not per season. An alt mapping is a fact about a
    -- person, and archiving a season must not forget who somebody is.
    ShowUsYourLootDB.players = ShowUsYourLootDB.players or {}

    local migrated = false

    if not ShowUsYourLootDB.activeSeason then
        migrated = MigrateOldLootDatabase()
    end

    if not ShowUsYourLootDB.activeSeason then
        ShowUsYourLootDB.activeSeason =
            CreateSeason("Midnight Season 1")
    end

    EnsureSeasonStructure(ShowUsYourLootDB.activeSeason)

    for _, archivedSeason in ipairs(ShowUsYourLootDB.archives) do
        EnsureSeasonStructure(archivedSeason)
        archivedSeason.settings.locked = true
    end

    ShowUsYourLootDB.databaseVersion = DATABASE_VERSION

    -- The name to GUID index is derived, so it is rebuilt at login rather
    -- than saved. Every alt lookup by name depends on it.
    SYL.Players.RebuildIndex()

    -- Compatibility alias for the current UI.
    -- Existing code that reads ShowUsYourLootDB.loot will continue working.
    ShowUsYourLootDB.loot =
        ShowUsYourLootDB.activeSeason.loot

    if migrated then
        SYL:Print(
            "Existing loot was moved into the active season: "
            .. ShowUsYourLootDB.activeSeason.name
        )
    end
end

function SYL.GetActiveSeason()
    return ShowUsYourLootDB
        and ShowUsYourLootDB.activeSeason
end

function SYL.GetActiveLoot()
    local season = SYL.GetActiveSeason()

    if not season then
        return {}
    end

    season.loot = season.loot or {}

    return season.loot
end

function SYL.GetArchives()
    if not ShowUsYourLootDB then
        return {}
    end

    ShowUsYourLootDB.archives =
        ShowUsYourLootDB.archives or {}

    return ShowUsYourLootDB.archives
end

function SYL.GetAllLoot()
    local allLoot = {}

    local activeSeason = SYL.GetActiveSeason()

    if activeSeason and activeSeason.loot then
        for _, record in ipairs(activeSeason.loot) do
            table.insert(allLoot, record)
        end
    end

    for _, season in ipairs(SYL.GetArchives()) do
        for _, record in ipairs(season.loot or {}) do
            table.insert(allLoot, record)
        end
    end

    return allLoot
end

function SYL.GetActiveDrops()
    local season = SYL.GetActiveSeason()

    if not season then
        return {}
    end

    season.drops = season.drops or {}

    return season.drops
end

function SYL.GetAllDrops()
    local allDrops = {}

    local activeSeason = SYL.GetActiveSeason()

    if activeSeason and activeSeason.drops then
        for _, record in ipairs(activeSeason.drops) do
            table.insert(allDrops, record)
        end
    end

    for _, season in ipairs(SYL.GetArchives()) do
        for _, record in ipairs(season.drops or {}) do
            table.insert(allDrops, record)
        end
    end

    return allDrops
end

function SYL.GetActiveRaids()
    local season = SYL.GetActiveSeason()

    if not season then
        return {}
    end

    season.raids = season.raids or {}

    return season.raids
end

function SYL.GetAllRaids()
    local allRaids = {}

    local activeSeason = SYL.GetActiveSeason()

    if activeSeason and activeSeason.raids then
        for _, session in ipairs(activeSeason.raids) do
            table.insert(allRaids, session)
        end
    end

    for _, season in ipairs(SYL.GetArchives()) do
        for _, session in ipairs(season.raids or {}) do
            table.insert(allRaids, session)
        end
    end

    return allRaids
end

function SYL.StartNewSeason(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")

    if not name or name == "" then
        name = "New Season"
    end

    ShowUsYourLootDB.activeSeason = CreateSeason(name)

    -- Keep old UI and code pointed at the new active-season loot table.
    ShowUsYourLootDB.loot =
        ShowUsYourLootDB.activeSeason.loot

    ShowUsYourLootDB.recentRecordIDs = {}

    return ShowUsYourLootDB.activeSeason
end

function SYL.ArchiveCurrentSeason(newSeasonName)
    local activeSeason = SYL.GetActiveSeason()

    if not activeSeason then
        return nil, "There is no active season to archive."
    end

    activeSeason.archivedAt = time()
    activeSeason.settings =
        activeSeason.settings or {}
    activeSeason.settings.locked = true

    table.insert(
        ShowUsYourLootDB.archives,
        activeSeason
    )

    local archivedSeason = activeSeason

    local newSeason = SYL.StartNewSeason(
        newSeasonName or "New Season"
    )

    return archivedSeason, newSeason
end

function SYL.RenameActiveSeason(newName)
    newName = newName and
        newName:gsub("^%s+", ""):gsub("%s+$", "")

    if not newName or newName == "" then
        return false, "Enter a season name."
    end

    local activeSeason = SYL.GetActiveSeason()

    if not activeSeason then
        return false, "There is no active season."
    end

    activeSeason.name = newName

    return true
end

function SYL.GetSeasonSummary(season)
    if not season then
        return nil
    end

    return {
        id = season.id,
        name = season.name,
        lootCount = #(season.loot or {}),
        dropCount = #(season.drops or {}),
        startedAt = season.startedAt,
        archivedAt = season.archivedAt,
        locked = season.settings
            and season.settings.locked
            or false,
    }
end