-- Core/Database.lua
--
-- The shape of the saved database: the settings defaults, the season
-- structure, the migration from before seasons existed, and the one-time
-- setup at ADDON_LOADED.
--
-- Reading what this builds — the active season, the archives, and everything
-- across both — is Core/Seasons.lua.

local SYL = _G.ShowUsYourLoot

-- 4: countPersonalLoot's default flipped to off. The setting is gone
--    entirely now — personal loot never resets a drought — so nothing
--    reads it and the migration that managed it was removed with it.
-- 5: syncEnabled became the "sync" feature.
-- 6: announceCaptures' default flipped to off. See MigrateAnnounceDefault.
-- 7: "everyone" left the Raiders scope rotation. See MigrateAudienceScope.
local DATABASE_VERSION = 7

-- A SERIAL, BECAUSE THE CLOCK IS NOT ENOUGH. This was the timestamp alone, to
-- the second, which is unique right up until two seasons are created in the
-- same one — and archiving then immediately starting a new season is a single
-- keystroke. Two seasons sharing an id are indistinguishable to anything that
-- holds a reference to one: ticking a season on the Archives tab ticked every
-- season that shared its id, and a merge would then take seasons nobody chose.
--
-- The serial lives in the database rather than in a local, so it keeps
-- counting across sessions instead of restarting at one every login.
local function GenerateSeasonID()
    local serial = 1

    if ShowUsYourLootDB then
        ShowUsYourLootDB.seasonSerial =
            (ShowUsYourLootDB.seasonSerial or 0) + 1

        serial = ShowUsYourLootDB.seasonSerial
    end

    return "season-" .. date("%Y%m%d-%H%M%S") .. "-" .. serial
end

-- Repairs seasons that already share one. Ids were only unique to the second
-- until this was fixed, so an install that archived twice quickly is carrying
-- a collision, and every operation keyed by id would act on both.
local function EnsureUniqueSeasonIDs(database)
    local seen = {}
    local repaired = 0

    local function Fix(season)
        if type(season) ~= "table" then
            return
        end

        if not season.id or seen[season.id] then
            season.id = GenerateSeasonID()
            repaired = repaired + 1
        end

        seen[season.id] = true
    end

    Fix(database.activeSeason)

    for _, season in ipairs(database.archives or {}) do
        Fix(season)
    end

    return repaired
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

    -- Which color scheme the window wears. Stored as a key rather than as
    -- color values, so editing a palette improves every existing install
    -- instead of only new ones.
    --
    -- Taken from Palettes rather than repeated here: two copies of a default
    -- drift, and the one that loses is always the one nobody remembers.
    -- This runs at ADDON_LOADED, by which point every file has loaded.
    if ShowUsYourLootDB.settings.palette == nil then
        ShowUsYourLootDB.settings.palette = SYL.Palettes.DEFAULT
    end

    -- How many nights before the board ranks somebody. Taken from LootScore
    -- for the same reason the palette is taken from Palettes: the module that
    -- owns the rule owns its default, and a second copy here is one that
    -- drifts. Zero is a real value, so the test is against nil.
    if ShowUsYourLootDB.settings.minRankNights == nil then
        ShowUsYourLootDB.settings.minRankNights = SYL.LootScore.MIN_NIGHTS
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

    local announceChanged =
        SYL.Migrations.MigrateAnnounceDefault(storedVersion)

    SYL.Migrations.MigrateSyncFeature(storedVersion)
    SYL.Migrations.MigrateAudienceScope(storedVersion)

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
    -- Before anything can hold a reference to a season. Unconditional, and the
    -- guard is the collision itself.
    EnsureUniqueSeasonIDs(ShowUsYourLootDB)

    local backfilled = SYL.Migrations.BackfillRecordIDs(ShowUsYourLootDB)

    -- SAID OUT LOUD, because it is the one repair here that deletes a record
    -- rather than filling one in. Every other migration changes a setting and
    -- can be changed back by hand; this one takes rows out of the database,
    -- and an officer who watches a number drop deserves to know why it did.
    -- Core/Migrations.lua argues for why the rows are safe to lose.
    local deduped = SYL.Migrations.DedupeSyncedDrops(ShowUsYourLootDB)

    if deduped > 0 then
        SYL:Write(
            SYL.colors.highlight .. "[SYL]" .. SYL.colors.reset
            .. " removed " .. deduped
            .. (deduped == 1 and " duplicate drop" or " duplicate drops")
            .. " received from another player's copy of this addon."
            .. " Scores that counted them are now correct."
        )
    end

    if backfilled > 0 then
        SYL:DebugPrint("Assigned ids to " .. backfilled .. " record(s)")
    end

    -- A HIGH-WATER MARK, NOT THE CURRENT VERSION.
    --
    -- Installing an older file over a newer one is an ordinary thing to do on
    -- CurseForge — roll back a release that broke something, or run whatever
    -- version the guild agreed on. Written as a plain assignment, the older
    -- build stamps its own lower number, and every migration between the two
    -- re-arms and fires again on the way back up. Migrations here exist
    -- specifically to overrule a saved choice once, so firing twice takes away
    -- a setting somebody deliberately turned back on.
    --
    -- Never going backwards costs nothing: a migration that has already run
    -- has already run, whichever build is reading the file now.
    ShowUsYourLootDB.databaseVersion = math.max(
        ShowUsYourLootDB.databaseVersion or 0, DATABASE_VERSION
    )

    -- The name to GUID index is derived, so it is rebuilt at login rather
    -- than saved. Every alt lookup by name depends on it.
    SYL.Players.RebuildIndex()

    -- Before the stamp is overwritten, or the comparison is against itself.
    -- See Core/Recovery.lua for why a corrupt file is otherwise silent.
    SYL.Recovery.Report()
    SYL.Recovery.Stamp()

    -- THE COMPATIBILITY ALIAS IS GONE, AND SO IS THE COPY OF IT ON DISK.
    --
    -- `ShowUsYourLootDB.loot` pointed at the same table as
    -- `activeSeason.loot`, kept in step by four separate assignments. Nothing
    -- read it. WoW's SavedVariables writer does not dedupe a shared reference,
    -- so it serialized the whole loot table a second time — measured on
    -- Aimee's live file at 100,740 bytes, 5.1% of everything saved, for no
    -- reader at all.
    --
    -- MigrateOldLootDatabase above still reads it, and must: it is how a
    -- database written before seasons existed is found. That runs earlier and
    -- only when there is no active season, so by here it has had its chance
    -- and the key can go. Clearing it is what removes the copy from an install
    -- that already has one; leaving it nil would only stop it growing.
    ShowUsYourLootDB.loot = nil

    if migrated then
        SYL:Print(
            "Existing loot was moved into the active season: "
            .. ShowUsYourLootDB.activeSeason.name
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

-- THE WAY BACK, and until now there was not one.
--
-- Aimee, after working through the test list: "i archived the 08/18-08/22. now
-- how do i unarchive them?" There was no answer — archiving was reachable from
-- a button on the Archives tab and nothing anywhere undid it, which is the
-- rule in HANDOFF broken in its plainest form: anything that can be created
-- has to be undoable from the same screen.
--
-- WHAT HAPPENS TO THE SEASON THAT IS ACTIVE NOW. Archiving leaves a brand new
-- empty one behind, and that is nearly always what is sitting there when
-- somebody wants this. So an empty one is discarded rather than archived,
-- because filing an empty season away as history is not history — it is
-- litter, and it would accumulate one entry per mistake.
--
-- A season with records in it is archived properly instead. Nothing is thrown
-- away that anybody could want, and the swap is symmetric: it is exactly what
-- archiving does, in the other direction.
--
-- THE LOCK COMES OFF. An archive is sealed so its history cannot change, which
-- is the promise that makes archiving safe; a season being raided in cannot be
-- sealed, or the night's drops would have nowhere to go.
function SYL.UnarchiveSeason(index)
    local archives = ShowUsYourLootDB and ShowUsYourLootDB.archives

    if type(archives) ~= "table" then
        return nil, "There is nothing archived."
    end

    local season = archives[index]

    if not season then
        return nil, "That archived season is not there any more."
    end

    local active = SYL.GetActiveSeason()
    local displaced

    if active then
        local records = #(active.drops or {}) + #(active.loot or {})

        if records > 0 then
            active.archivedAt = time()
            active.settings = active.settings or {}
            active.settings.locked = true

            table.insert(archives, active)

            displaced = active
        end
    end

    table.remove(archives, index)

    season.archivedAt = nil
    season.settings = season.settings or {}
    season.settings.locked = false

    ShowUsYourLootDB.activeSeason = season

    -- The drop index describes an array that has just been replaced wholesale,
    -- the same as StartNewSeason above.
    ShowUsYourLootDB.recentRecordIDs = {}

    SYL.LootHistoryStore.RebuildIndex()

    return season, displaced
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

-- THE LOCK IS ABOUT RECORDS, NOT THE LABEL. An archived season is sealed so
-- nothing can be added to or removed from its history, which is the promise
-- that makes archiving safe. A name is not history: it is what somebody typed,
-- and until now typing it wrong was permanent, because RenameActiveSeason only
-- ever reached the active one. Archiving before renaming is the ordinary way
-- to do it and left no way back.
function SYL.RenameArchive(index, newName)
    newName = newName and
        newName:gsub("^%s+", ""):gsub("%s+$", "")

    if not newName or newName == "" then
        return false, "Enter a season name."
    end

    local archives = SYL.GetArchives()
    local season = archives[index]

    if not season then
        return false, "No archived season there."
    end

    local was = season.name

    season.name = newName

    return true, (was or "That season") .. " is now " .. newName .. "."
end

-- Folds several archives into one.
--
-- WHAT IT IS FOR: a season boundary taken on the wrong day. Archiving the day
-- before the tier actually changed leaves a stub holding a handful of nights
-- that belong to the season before it, and no amount of renaming makes three
-- archives read like the two seasons that happened.
--
-- NOT REVERSIBLE, and the caller is expected to have said so. Nothing here
-- deletes a record — every drop, item and night from every source lands in the
-- result — but which season each came from is gone afterwards, and only a
-- manual re-archive could put it back.
--
-- Indexes are sorted and removed from the back, because removing from the
-- front renumbers everything after it and would take the wrong seasons.
function SYL.MergeArchives(indexes, newName)
    local archives = SYL.GetArchives()

    if type(indexes) ~= "table" or #indexes < 2 then
        return false, "Pick at least two archived seasons to merge."
    end

    local ordered = {}
    local seen = {}

    for _, index in ipairs(indexes) do
        if not archives[index] then
            return false, "No archived season there."
        end

        if not seen[index] then
            seen[index] = true

            table.insert(ordered, index)
        end
    end

    if #ordered < 2 then
        return false, "Pick at least two archived seasons to merge."
    end

    table.sort(ordered)

    -- The oldest one is the survivor, so the merged season keeps the earliest
    -- start date and reads as the whole span rather than as the day the merge
    -- happened.
    local target = archives[ordered[1]]
    local merged = { drops = 0, loot = 0, raids = 0 }

    for position = 2, #ordered do
        local source = archives[ordered[position]]

        for _, list in ipairs({ "drops", "loot", "raids" }) do
            for _, record in ipairs(source[list] or {}) do
                table.insert(target[list], record)

                merged[list] = merged[list] + 1
            end
        end

        if (source.startedAt or 0) > 0
            and (source.startedAt < (target.startedAt or math.huge))
        then
            target.startedAt = source.startedAt
        end

        if (source.archivedAt or 0) > (target.archivedAt or 0) then
            target.archivedAt = source.archivedAt
        end
    end

    for position = #ordered, 2, -1 do
        table.remove(archives, ordered[position])
    end

    if newName and newName:gsub("%s", "") ~= "" then
        target.name = (newName:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    return true, "Merged into " .. (target.name or "one season")
        .. ": " .. merged.drops .. " drops, " .. merged.loot
        .. " items and " .. merged.raids .. " nights moved."
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