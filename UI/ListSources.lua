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

-- The merged list holds both kinds of record joined into one shape, so it
-- reads its own fields rather than either original descriptor.
local FEED_FIELDS = {
    player = function(entry) return entry.player end,
    item = function(entry) return entry.itemName end,
    location = function(entry) return entry.where end,
    timestamp = function(entry) return entry.timestamp end,
    wintype = function(entry) return entry.typeLabel end,
}

function ListSources.GetFields(view)
    return FEED_FIELDS
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
local function InScope(entries, view)
    local scope = view.contentScope

    if not scope or scope == "all" then
        return entries
    end

    local kept = {}

    for _, entry in ipairs(entries) do
        local contentType = SYL.Utilities.GetContentType(
            entry.instanceType, entry.difficultyID
        )

        if contentType == scope then
            table.insert(kept, entry)
        end
    end

    return kept
end

-- Chat capture records everything: reagents, gold, quest items, and three
-- hundred of them bury the dozen that are gear somebody actually received.
-- The same test the due list uses, so the list and the maths agree.
local function GearOnly(entries, view)
    if not view.gearOnly then
        return entries
    end

    local kept = {}

    for _, entry in ipairs(entries) do
        -- A rolled item is always kept: somebody rolled Need on it, which is
        -- a stronger statement than any guess about its item class.
        if SYL.LootFeed.ROLLED[entry.typeKey]
            or SYL.PersonalLoot.IsTrackableGear(entry) == true
        then
            table.insert(kept, entry)
        end
    end

    return kept
end

-- Hidden is a display state, never a deletion, and the two states are
-- separate lists rather than one containing the other.
--
-- Showing hidden rows *alongside* visible ones was the wrong shape: the list
-- got longer, the ticked row was still there dimmed, and there was no way to
-- see what had been set aside without reading opacity. Hidden now shows only
-- hidden, which makes it a place you go rather than a filter you loosen.
--
-- The flag lives on the underlying record rather than on the joined entry,
-- which is rebuilt on every draw.
local function VisibleEntries(entries, view)
    local wantHidden = view.showHidden and true or false
    local kept = {}

    for _, entry in ipairs(entries) do
        local isHidden = entry.record.hidden and true or false

        if isHidden == wantHidden then
            table.insert(kept, entry)
        end
    end

    return kept
end

-- Everything in scope before filtering. Dropdown options are derived from
-- this, so choosing one filter never empties the other dropdowns.
function ListSources.GetUnfiltered(view)
    local drops, loot

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        if not season then
            return {}
        end

        drops, loot = season.drops or {}, season.loot or {}
    elseif view.allSeasons then
        -- allSeasons widens the list rather than being a tab of its own,
        -- which is what made the old All-Time tab redundant.
        drops, loot = SYL.GetAllDrops(), SYL.GetAllLoot()
    else
        local season = SYL.GetActiveSeason()

        drops = SYL.GetActiveDrops()
        loot = season and season.loot or {}
    end

    local entries = SYL.LootFeed.Build(drops, loot)

    return InScope(GearOnly(VisibleEntries(entries, view), view), view)
end

-- The line under the title, saying which records are on screen.
--
-- Lives here rather than in the window because it answers the same question
-- GetUnfiltered does — what is this view looking at — and the two drifting
-- apart would mean a heading that describes a different list to the one
-- below it. The archive line names its record type for that reason: two
-- lists under one season name are otherwise indistinguishable.
function ListSources.DescribeView(view)
    if view.mode == "feed" then
        if view.allSeasons then
            return "Every season"
        end

        local season = SYL.GetActiveSeason()

        return season and season.name or "Active Season"
    end

    if view.mode == "archives" then
        return "Archived Seasons"
    end

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        return season and season.name or "Archived Season"
    end

    return ""
end

-- How many records in scope are hidden right now.
--
-- Hiding was invisible: the count dropped by one and the row vanished into a
-- list where several other copies of the same item were still sitting, which
-- reads as the button not working rather than as it working on exactly the
-- row that was ticked.
function ListSources.CountHiddenInScope(view)
    if view.showHidden then
        return 0
    end

    -- Asked of the same scope with the switch flipped, so the number always
    -- describes the list it is printed above.
    view.showHidden = true

    local hidden = #ListSources.GetUnfiltered(view)

    view.showHidden = false

    return hidden
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
