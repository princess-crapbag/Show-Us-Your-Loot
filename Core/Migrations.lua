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
