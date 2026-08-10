-- Core/Database.lua
--
-- The shape of the saved database: the settings defaults, the season
-- structure, the migration from before seasons existed, and the one-time
-- setup at ADDON_LOADED.
--
-- Reading what this builds — the active season, the archives, and everything
-- across both — is Core/Seasons.lua.

local SYL = _G.ShowUsYourLoot

-- 4: countPersonalLoot's default flipped to off. See MigrateSettings.
-- 5: syncEnabled became the "sync" feature.
-- 6: announceCaptures' default flipped to off. See MigrateAnnounceDefault.
local DATABASE_VERSION = 6

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

    -- OFF. The addon is silent unless it is asked something.
    --
    -- This is the only thing here that speaks unprompted, in the channel
    -- people actually read, and it fires once per gear drop — which in a full
    -- clear is a wall of text nobody asked for, arriving fastest exactly when
    -- chat is busiest. It has already been narrowed once, from every quality
    -- down to gear, and that was the wrong axis: the problem is not which
    -- items it announces, it is that a recording tool has no business
    -- narrating. Everything it would say is in the loot list a click away,
    -- and it is still recorded either way.
    --
    -- Aimee's reason, which is the one that decides it: a raider who installs
    -- this to be counted did not agree to a running commentary, and an addon
    -- that talks too much gets uninstalled before it has enough data to be
    -- worth anything.
    if ShowUsYourLootDB.settings.announceCaptures == nil then
        ShowUsYourLootDB.settings.announceCaptures = false
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
    -- The argument for off wins because the data cannot support it, and it
    -- fails in one direction. CHAT_MSG_LOOT only ever sees your own loot plus
    -- your current group's, and nobody claims a vault standing next to the
    -- officer running this addon — so the only vault claims in the database
    -- are the officer's own. Their drought resets weekly and nobody else's
    -- does, and they sink to the bottom of a list they wrote. That is worse
    -- than being blind: it is confidently wrong, in a direction that looks
    -- like modesty.
    --
    -- It stays a setting because for a guild where everybody runs the addon
    -- and syncs, on is the better answer. It just cannot be the default until
    -- the sync can fill the gap (F8/E8 in HANDOFF.md).
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

    -- Read before anything writes it, since the migration below is the only
    -- thing that can tell an upgrade from a first run.
    local storedVersion = ShowUsYourLootDB.databaseVersion

    InitializeSettings()

    local settingChanged = SYL.Migrations.MigrateSettings(storedVersion)

    local announceChanged =
        SYL.Migrations.MigrateAnnounceDefault(storedVersion)

    SYL.Migrations.MigrateSyncFeature(storedVersion)

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

    -- Deliberately not named after a patch. "Midnight Season 1" was hardcoded
    -- here, which is right for one season and quietly wrong for every install
    -- after it. A neutral name cannot go stale, and the first-run message
    -- says how to change it.
    if not ShowUsYourLootDB.activeSeason then
        ShowUsYourLootDB.activeSeason =
            CreateSeason("Current Season")
    end

    EnsureSeasonStructure(ShowUsYourLootDB.activeSeason)

    for _, archivedSeason in ipairs(ShowUsYourLootDB.archives) do
        EnsureSeasonStructure(archivedSeason)
        archivedSeason.settings.locked = true
    end

    -- After EnsureSeasonStructure, so every season has its loot and drops
    -- tables to walk. A record with no id cannot be ticked by anything — see
    -- the note in Core/Migrations.lua.
    local backfilled = SYL.Migrations.BackfillRecordIDs(ShowUsYourLootDB)

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

    if settingChanged then
        SYL:Print(
            "Gear taken without a roll no longer counts towards droughts. "
            .. "Your client only sees other people's loot while you are "
            .. "grouped with them, so counting it mostly counted yours. Turn "
            .. "it back on in Settings, or with /syl personalloot."
        )
    end

    -- Said once, because it explains a list that was behaving oddly rather
    -- than announcing routine maintenance. Silent when there is nothing to
    -- fix, which is every install captured after the field existed.
    if backfilled > 0 then
        SYL:Print(
            backfilled
            .. (backfilled == 1 and " older record" or " older records")
            .. " could not be ticked, and can be now. They were captured "
            .. "before records carried an id, so Select all and Hide had no "
            .. "way to reach them."
        )
    end

    if announceChanged then
        SYL:Print(
            "Loot is no longer announced in chat as it is recorded. It is "
            .. "still recorded — the addon just does not say so every time. "
            .. "Turn it back on in Settings, or with /syl announce."
        )
    end
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

    -- The drop indexes describe an array just replaced wholesale.
    SYL.LootHistoryStore.RebuildIndex()

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