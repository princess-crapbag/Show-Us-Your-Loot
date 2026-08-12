-- Core/Seasons.lua
--
-- Reading the season store: what is in the active season, what is in the
-- archives, and everything across both.
--
-- Split from Core/Database.lua, which owns the schema — the defaults, the
-- migration and DatabaseInitialize. This file only reads what that built.
--
-- Every list is returned live rather than copied, except the All* functions,
-- which have to join the active season to the archives and so must build a
-- new array. Callers of those iterate and discard; nothing writes through
-- them, and the drop indexes exist precisely so the hot paths do not call
-- them at all.

local SYL = _G.ShowUsYourLoot

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

-- EVERY SEASON, ARCHIVES INCLUDED. Use this only for questions about an item
-- or about the database itself — "has this ever dropped", "how much is
-- recorded in total". Anything about a *person* belongs to one season.
--
-- Archiving is how a guild starts a tier fresh, and until this was written
-- down every board, due list and attendance count read across the archives:
-- the first archive ever taken changed nothing on screen, because with one
-- season and no archives GetAll and GetActive had always returned the same
-- list and nothing had ever told them apart.
--
-- Returns a copy. GetActiveDrops hands back the stored table by reference, so
-- a caller that sorts what it is given must copy first.
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
