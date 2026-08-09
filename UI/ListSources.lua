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

--------------------------------------------------------------------------
-- Caching one redraw
--------------------------------------------------------------------------
--
-- Drawing the list called this five times. The row renderer wanted the
-- entries, the count line wanted the total, the hidden count wanted the same
-- list with one flag flipped, the selection bar wanted it twice more, and the
-- mouse wheel asked again to work out how far it could scroll.
--
-- Each pass rebuilt the whole feed from scratch: a table per record, an index
-- over every drop, a sort with a tostring on both sides of every comparison,
-- and — with Gear only on — a C_Item.GetItemInfo call per entry. On a full
-- season that is the dominant cost of showing the window, paid five times to
-- produce five identical answers.
--
-- Cached per redraw rather than memoised forever, because "has anything
-- changed" is not a question this file can answer cheaply and getting it
-- wrong shows stale loot. Invalidate() is called at the top of every redraw,
-- which is the one place every path already goes through.
--
-- Keyed by the view state that changes the answer, not just cleared, because
-- CountHiddenInScope deliberately asks the same question with showHidden
-- flipped and must not be handed the other list.
local unfilteredCache = {}
local filteredCache = {}

function ListSources.Invalidate()
    unfilteredCache = {}
    filteredCache = {}
end

local function Signature(view)
    return table.concat({
        tostring(view.mode),
        view.allSeasons and "1" or "0",
        tostring(view.contentScope or "all"),
        view.gearOnly and "1" or "0",
        view.showHidden and "1" or "0",
        tostring(view.selectedArchiveIndex or 0),

        -- The sort is part of what the cached list *is*, not a thing applied
        -- to it afterwards, because the rows are drawn straight out of it.
        tostring(view.sortKey or "date"),
        view.sortReversed and "1" or "0",
    }, "|")
end

-- The returned tables are shared between callers within one redraw. Nothing
-- may sort or otherwise mutate them in place; every caller reads.
local function Build(view)
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

-- Everything in scope before filtering. Dropdown options are derived from
-- this, so choosing one filter never empties the other dropdowns.
function ListSources.GetUnfiltered(view)
    local key = Signature(view)
    local cached = unfilteredCache[key]

    if cached then
        return cached
    end

    local entries = Build(view)

    unfilteredCache[key] = entries

    return entries
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

-- Cached alongside the unfiltered list. The filter state can only change
-- through a control that redraws, and a redraw invalidates, so the signature
-- does not have to describe the filters themselves.
function ListSources.GetFiltered(view)
    local key = Signature(view)
    local cached = filteredCache[key]

    if cached then
        return cached
    end

    local records = ListSources.GetUnfiltered(view)

    if view.filters then
        records = Filters.Apply(
            records, view.filters, ListSources.GetFields(view)
        )
    end

    -- Copied before sorting when nothing was filtered out, because Apply
    -- hands back the very table the unfiltered cache is holding and sorting
    -- it in place would reorder that too. Same table, two different
    -- questions.
    if records == unfilteredCache[key] then
        local copy = {}

        for index = 1, #records do
            copy[index] = records[index]
        end

        records = copy
    end

    -- Returned in display order, so the rows are drawn straight out of it
    -- rather than being indexed backwards.
    SYL.LootFeed.Sort(records, view.sortKey, view.sortReversed)

    filteredCache[key] = records

    return records
end

function ListSources.IsFiltering(view)
    return view.filters ~= nil and Filters.IsActive(view.filters)
end
