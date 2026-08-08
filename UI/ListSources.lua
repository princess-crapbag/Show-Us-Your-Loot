-- UI/ListSources.lua
--
-- Decides which records a view is looking at, and teaches the filter engine
-- how to read them.
--
-- Drop records and chat-loot records store the same concepts under different
-- names, so each view supplies its own field descriptor rather than the
-- filter engine knowing about either shape.

local SYL = _G.ShowUsYourLoot
local Filters = SYL.Filters

local ListSources = {}
SYL.ListSources = ListSources

local DROP_FIELDS = {
    player = function(record) return record.winnerName end,
    item = function(record) return record.itemName end,
    location = function(record) return record.instanceName end,
    timestamp = function(record) return record.timestamp end,

    wintype = function(record)
        if record.allPassed then
            return "All passed"
        end

        return SYL.LootHistoryAPI.ShortRollState(record.winnerState)
    end,
}

local LOOT_FIELDS = {
    player = function(record) return record.recipient end,
    item = function(record) return record.itemName end,
    location = function(record)
        return record.instanceName or record.zoneName
    end,
    timestamp = function(record) return record.timestamp end,
}

-- An archived season holds both kinds of record, and which one is on screen
-- is a toggle rather than a tab, so the field descriptor has to ask.
function ListSources.ArchiveShowsDrops(view)
    return view.mode == "archive" and not view.archiveShowsLoot
end

function ListSources.GetFields(view)
    if view.mode == "drops" or ListSources.ArchiveShowsDrops(view) then
        return DROP_FIELDS
    end

    return LOOT_FIELDS
end

-- Raid loot and dungeon loot are the same shape and different questions. A
-- Mythic+ drop has no bearing on who is due in the raid, and mixing them
-- makes the list unreadable for a guild that runs both.
--
-- This matters most on the chat-loot side, which is not where it looks like
-- it should. Retail dungeons award personal loot: there are no need or greed
-- rolls, so the loot history has nothing to record and the drops list is
-- correctly empty of dungeons no matter how many keys were run. Dungeon gear
-- arrives as chat loot, so that is the list the raid/dungeon split has to
-- work on.
--
-- Records written before instanceType was stored fall back to the difficulty
-- id inside GetContentType, so this works on existing history rather than
-- only on what is captured from now on.
local function InScope(records, view)
    local scope = view.contentScope

    if not scope or scope == "all" then
        return records
    end

    local kept = {}

    for _, record in ipairs(records) do
        local contentType = SYL.Utilities.GetContentType(
            record.instanceType, record.difficultyID
        )

        if contentType == scope then
            table.insert(kept, record)
        end
    end

    return kept
end

-- Chat capture records everything: reagents, gold, quest items, and three
-- hundred of them bury the dozen that are gear somebody actually received.
--
-- This is the same filter the due list uses, so what is on screen and what
-- resets a drought are the same set rather than two ideas of "personal
-- loot" that drift. Group-loot wins are subtracted, because winning a roll
-- also prints a loot line and those already have their own tab.
--
-- Order is taken from the original list rather than from the filter, which
-- sorts newest first: the loot list reads its array oldest to newest and
-- would otherwise show the whole thing upside down.
local function GearOnly(records, view)
    if not view.gearOnly then
        return records
    end

    local entries = SYL.PersonalLoot.Build(records, SYL.GetAllDrops())
    local wanted = {}

    for _, entry in ipairs(entries) do
        wanted[entry.record] = true
    end

    local kept = {}

    for _, record in ipairs(records) do
        if wanted[record] then
            table.insert(kept, record)
        end
    end

    return kept
end

-- Hidden records are a display state, never a deletion, so they come back the
-- moment the toggle is flipped.
local function VisibleRecords(records, view)
    if view.showHidden then
        return records
    end

    local visible = {}

    for _, record in ipairs(records) do
        if not record.hidden then
            table.insert(visible, record)
        end
    end

    return visible
end

-- Everything in scope before filtering. Dropdown options are derived from
-- this, so choosing one filter never empties the other dropdowns.
function ListSources.GetUnfiltered(view)
    -- allSeasons widens whichever dataset the tab is showing, rather than
    -- being a tab of its own, so it works for drops and chat loot alike.
    if view.mode == "drops" then
        if view.allSeasons then
            return InScope(VisibleRecords(SYL.GetAllDrops(), view), view)
        end

        return InScope(VisibleRecords(SYL.GetActiveDrops(), view), view)
    end

    if view.mode == "active" then
        if view.allSeasons then
            return InScope(
                GearOnly(VisibleRecords(SYL.GetAllLoot(), view), view), view
            )
        end

        local season = SYL.GetActiveSeason()

        return InScope(
            GearOnly(VisibleRecords(season and season.loot or {}, view), view),
            view
        )
    end

    if view.mode == "all" then
        return InScope(
            GearOnly(VisibleRecords(SYL.GetAllLoot(), view), view), view
        )
    end

    -- An archived season keeps its drops and its chat loot in separate
    -- tables, exactly as the active one does. Only the chat loot was ever
    -- shown here, so archiving a season made its group loot unreachable —
    -- the records were never lost, just never rendered.
    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        if not season then
            return {}
        end

        if view.archiveShowsLoot then
            return InScope(
                GearOnly(VisibleRecords(season.loot or {}, view), view), view
            )
        end

        return InScope(VisibleRecords(season.drops or {}, view), view)
    end

    return {}
end

-- Which table an archive should open on. Drops are the primary record, but a
-- season archived before drop capture existed has none, and opening it on an
-- empty list reads as lost history rather than as the wrong toggle.
function ListSources.DefaultArchiveShowsLoot(archiveIndex)
    local season = SYL.GetArchives()[archiveIndex]

    return season ~= nil
        and #(season.drops or {}) == 0
        and #(season.loot or {}) > 0
end

-- The line under the title, saying which records are on screen.
--
-- Lives here rather than in the window because it answers the same question
-- GetUnfiltered does — what is this view looking at — and the two drifting
-- apart would mean a heading that describes a different list to the one
-- below it. The archive line names its record type for that reason: two
-- lists under one season name are otherwise indistinguishable.
function ListSources.DescribeView(view)
    if view.mode == "drops" then
        local season = SYL.GetActiveSeason()

        return (season and season.name or "Active Season") .. " — group loot"
    end

    if view.mode == "active" then
        local season = SYL.GetActiveSeason()

        return season and season.name or "Active Season"
    end

    if view.mode == "all" then
        return "All-Time Loot History"
    end

    if view.mode == "archives" then
        return "Archived Seasons"
    end

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        return (season and season.name or "Archived Season")
            .. (view.archiveShowsLoot and " — chat loot" or " — group loot")
    end

    return ""
end

function ListSources.GetFiltered(view)
    local records = ListSources.GetUnfiltered(view)

    if not view.filters then
        return records
    end

    return Filters.Apply(records, view.filters, ListSources.GetFields(view))
end

function ListSources.IsFiltering(view)
    return view.filters ~= nil and Filters.IsActive(view.filters)
end
