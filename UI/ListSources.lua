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

function ListSources.GetFields(view)
    if view.mode == "drops" then
        return DROP_FIELDS
    end

    return LOOT_FIELDS
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
            return VisibleRecords(SYL.GetAllDrops(), view)
        end

        return VisibleRecords(SYL.GetActiveDrops(), view)
    end

    if view.mode == "active" then
        if view.allSeasons then
            return VisibleRecords(SYL.GetAllLoot(), view)
        end

        local season = SYL.GetActiveSeason()

        return VisibleRecords(season and season.loot or {}, view)
    end

    if view.mode == "all" then
        return VisibleRecords(SYL.GetAllLoot(), view)
    end

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        return VisibleRecords(season and season.loot or {}, view)
    end

    return {}
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
