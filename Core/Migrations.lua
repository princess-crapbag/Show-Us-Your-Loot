-- Core/Migrations.lua
--
-- Saved settings that changed meaning after people had already saved the old
-- ones, and the one-time corrections that carry them across.
--
-- Split out of Database.lua when it crossed the size limit. That file owns
-- the shape of the database and the defaults a fresh install gets; this one
-- owns the exceptions — what to do about an install that predates a default.
-- The two are genuinely different jobs: InitializeSettings fills in what is
-- nil and must never overrule a choice, and everything here overrules a
-- choice on purpose, once, at its own version boundary.
--
-- EVERY MIGRATION GUARDS ITS OWN NUMBER, not DATABASE_VERSION. Written the
-- second way a migration re-fires on every later schema bump and takes away a
-- setting the user deliberately turned back on. tools/test_migrations.py runs
-- these functions directly, against a fresh install, an upgrade that needs
-- them, one that does not, and an install that already ran them — add a row
-- to its MIGRATIONS table when you add one here.

local SYL = _G.ShowUsYourLoot

local Migrations = {}
SYL.Migrations = Migrations

--------------------------------------------------------------------------
-- Records with no id at all
--------------------------------------------------------------------------

-- A RECORD WITHOUT AN ID CANNOT BE TICKED, EVER.
--
-- Selection is keyed by `record.id` because rows are pooled and reused as the
-- list scrolls — Selection.Set returns early when there is no id, and
-- IsSelected can never answer true. So such a record draws a checkbox that
-- does nothing, is skipped by Select all, and can never be hidden or ignored.
-- It is the one row in the addon that no button reaches.
--
-- Found in Aimee's live data: 20 of 321 chat records had no id. They also
-- carry no instanceType and no difficultyID, which dates them — they were
-- captured before `id` was written onto chat records at all. She hit it doing
-- exactly what the list invites: Select all, Hide, and twenty rows stayed put
-- with no way to move them and nothing saying why.
--
-- Backfilled rather than worked around. The alternative — a fallback key
-- derived from the record's fields at selection time — puts identity in two
-- places and would break the moment two reagents matched.
--
-- NOT VERSION GUARDED, deliberately, unlike everything below it. This is not
-- a decision being revisited; it is a field that must never be nil, and the
-- guard is the nil itself. Run every load it is idempotent, costs one pass
-- over records already in memory, and self-heals anything that arrives
-- without an id in future rather than waiting for somebody to notice.
local function AssignMissingIDs(records, seasonID, assigned)
    for index, record in ipairs(records or {}) do
        if type(record) == "table" and not record.id then
            -- Position and season, not the record's contents. Two reagents
            -- looted in the same second from the same boss are identical in
            -- every field they have, so a content hash would give them one id
            -- and ticking either would tick both.
            record.id = table.concat({
                "legacy",
                tostring(seasonID or "season"),
                tostring(record.timestamp or 0),
                tostring(index),
            }, "|")

            assigned = assigned + 1
        end
    end

    return assigned
end

-- Every season, active and archived: an archived season is still browsable
-- with All seasons, and its rows were just as unselectable.
function Migrations.BackfillRecordIDs(database)
    local assigned = 0

    local function Season(season)
        if type(season) ~= "table" then
            return
        end

        assigned = AssignMissingIDs(season.loot, season.id, assigned)
        assigned = AssignMissingIDs(season.drops, season.id, assigned)
    end

    Season(database.activeSeason)

    for _, season in ipairs(database.archives or {}) do
        Season(season)
    end

    return assigned
end

-- A default that changed after people had already saved the old one.
--
-- InitializeSettings only fills in what is nil, which is right: a setting
-- somebody chose must survive an update. But countPersonalLoot was never
-- chosen by anybody. It defaulted on, and in the version that shipped it the
-- only way to reach it was a slash command nothing pointed at — so an install
-- with it on has it on because of the old default, not because of a decision.
--
-- Leaving it alone would mean the correction reached every install except the
-- ones it was written for. It counted almost entirely the addon owner's own
-- loot, which moved them to the bottom of their own due list.
--
-- Once, on the version bump, and said out loud. Changing a saved setting
-- quietly is its own kind of wrong, and this one changes a number they may
-- have been quoting to their raid.
function Migrations.MigrateSettings(storedVersion)
    -- Guarded against the version this migration was introduced at, NOT
    -- against DATABASE_VERSION. Written the second way it re-fires on every
    -- later bump: somebody who migrated to 4, decided they wanted the setting
    -- after all and turned it back on would have it taken away again by the
    -- next unrelated schema change. A migration runs once, at its own
    -- boundary, and every one below owns its own number.
    --
    -- No stored version is a fresh install, not an upgrade: it should take
    -- the new default from InitializeSettings without being told anything.
    if type(storedVersion) ~= "number" or storedVersion >= 4 then
        return false
    end

    if ShowUsYourLootDB.settings.countPersonalLoot ~= true then
        return false
    end

    ShowUsYourLootDB.settings.countPersonalLoot = false

    return true
end

-- The same shape as MigrateSettings above, for the same reason: announcing
-- every capture defaulted on, so an install with it on has it on because of
-- the old default rather than because anybody chose it.
--
-- Unlike countPersonalLoot this changes no number, only how loud the addon
-- is, so it is the safer of the two to apply — but it is still a saved
-- setting being changed underneath somebody, so it is still said out loud and
-- it still names the way back.
function Migrations.MigrateAnnounceDefault(storedVersion)
    if type(storedVersion) ~= "number" or storedVersion >= 6 then
        return false
    end

    if ShowUsYourLootDB.settings.announceCaptures ~= true then
        return false
    end

    ShowUsYourLootDB.settings.announceCaptures = false

    return true
end

-- syncEnabled moved into the feature registry, and it is the one switch here
-- that decides whether the addon talks to other players.
--
-- Carried across rather than defaulted, in both directions. Somebody who
-- turned sync on chose that and should not find it off after an update;
-- somebody who never touched it should not find it on. The old setting is
-- left in place rather than deleted, so a downgrade still reads it.
function Migrations.MigrateSyncFeature(storedVersion)
    if type(storedVersion) ~= "number" or storedVersion >= 5 then
        return
    end

    local wasEnabled = ShowUsYourLootDB.settings.syncEnabled == true

    ShowUsYourLootDB.features = ShowUsYourLootDB.features or {}

    if ShowUsYourLootDB.features.sync == nil then
        ShowUsYourLootDB.features.sync = wasEnabled
    end
end
