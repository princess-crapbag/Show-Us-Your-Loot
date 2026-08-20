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

--------------------------------------------------------------------------
-- The same drop, stored twice
--------------------------------------------------------------------------

-- ELEVEN DUPLICATES FROM ONE RAID NIGHT, found in Aimee's live data.
--
-- A record id begins with the local session's start timestamp, and two people
-- in the same raid start their sessions a second or two apart. Core/Sync.lua
-- deduped incoming drops on the id alone, so every drop a guildmate broadcast
-- was stored again under the sender's own id. Her board read 560 where it
-- should have read 200 — and the duplicates were hard to see, because they
-- carry no item name and nothing in the loot list showed them.
--
-- Worse than the number: a credit correction lands on one record, so the
-- duplicate went on crediting the master looter no matter what she fixed.
--
-- CONSERVATIVE ON PURPOSE. Only a SYNC record is ever removed, and only when a
-- locally captured record says the same thing. The local one is always the
-- richer of the two — it has the roll list, the item and the difficulty — so
-- there is no case where the copy is worth keeping over it. Two SYNC records
-- that duplicate each other with no local original are left alone: something
-- was received that this client never saw for itself, and quietly deleting
-- half of it is not a repair.
--
-- Unconditional rather than version-guarded, like BackfillRecordIDs above and
-- for the same reason: it is idempotent, and the guard is the duplication
-- itself. It also has to keep running. The fix in Core/Sync.lua is on the
-- receiving side, and a guildmate on an older build goes on sending.
function Migrations.DedupeSyncedDrops(database)
    local removed = 0

    local function Season(season)
        if type(season) ~= "table" or type(season.drops) ~= "table" then
            return
        end

        local kept = {}

        for _, record in ipairs(season.drops) do
            local duplicate = false

            if record.source == "SYNC" then
                for _, other in ipairs(season.drops) do
                    if other ~= record
                        and other.source ~= "SYNC"
                        and SYL.DropIdentity.SameDrop(other, record)
                    then
                        duplicate = true

                        break
                    end
                end
            end

            if duplicate then
                removed = removed + 1
            else
                table.insert(kept, record)
            end
        end

        -- Rewritten in place. season.drops is handed out by reference all over
        -- the addon — SYL.GetActiveDrops returns the stored table itself — so
        -- assigning a fresh one would leave every existing holder on the old.
        for index = #season.drops, 1, -1 do
            season.drops[index] = nil
        end

        for index, record in ipairs(kept) do
            season.drops[index] = record
        end
    end

    Season(database.activeSeason)

    for _, season in ipairs(database.archives or {}) do
        Season(season)
    end

    return removed
end

-- Announcing every capture defaulted on, so an install with it on has it on
-- because of the old default rather than because anybody chose it.
--
-- There was a second migration of this exact shape, for countPersonalLoot.
-- It went when the setting did: personal loot no longer resets a drought
-- under any setting, so there was nothing left for it to correct.
--
-- This changes no number, only how loud the addon is — but it is still a
-- saved setting being changed underneath somebody, so it is still said out
-- loud and it still names the way back.
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
-- "everyone" left the scope rotation, so anybody parked on it is parked.
--
-- Core/Audience.lua:CYCLE has the argument for the removal. The consequence is
-- here: the scope is saved account-wide, so a client that had it selected on
-- the day of the update opens the Raiders board on all 399 people it has ever
-- seen and no button offers to leave. Next() sends any unknown scope back to
-- the raid team, so pressing once is a way out — but only for somebody who
-- guesses that the button they are already unhappy with is the answer.
--
-- Only touches "everyone", and only once. A saved "guild" is a choice inside
-- the rotation and is left exactly as it is.
function Migrations.MigrateAudienceScope(storedVersion)
    if type(storedVersion) ~= "number" or storedVersion >= 7 then
        return false
    end

    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings

    if not settings or settings.audienceScope ~= "everyone" then
        return false
    end

    settings.audienceScope = "team"

    return true
end

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
