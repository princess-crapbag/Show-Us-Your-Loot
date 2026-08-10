-- Core/Filters.lua
--
-- Filter state and matching for the list views. Pure logic: no frames, no
-- knowledge of which window is asking.
--
-- Callers supply a `fields` descriptor saying how to read each filterable
-- value out of a record, because drop records and chat-loot records store the
-- same concepts under different names.
--
--   fields = {
--       player    = function(record) return record.winnerName end,
--       item      = function(record) return record.itemName end,
--       location  = function(record) return record.instanceName end,
--       timestamp = function(record) return record.timestamp end,
--   }

local SYL = _G.ShowUsYourLoot

local Filters = {}
SYL.Filters = Filters

-- Multi-select fields. Date is a range and search is free text, so neither
-- belongs here.
Filters.FIELDS = { "player", "item", "location", "wintype" }

Filters.LABELS = {
    player = "Player",
    item = "Item",
    location = "Location",
    wintype = "Win type",
}

function Filters.CreateState()
    return {
        search = "",

        -- field -> { [value] = true }. An empty set means "no constraint",
        -- not "match nothing".
        selected = {
            player = {},
            item = {},
            location = {},
            wintype = {},
        },

        dateFrom = nil,
        dateTo = nil,
    }
end

--------------------------------------------------------------------------
-- Multi-select
--------------------------------------------------------------------------

function Filters.IsSelected(state, field, value)
    local set = state.selected[field]

    return set ~= nil and set[value] == true
end

function Filters.Toggle(state, field, value)
    local set = state.selected[field]

    if not set then
        return
    end

    if set[value] then
        set[value] = nil
    else
        set[value] = true
    end
end

function Filters.CountSelected(state, field)
    local set = state.selected[field]
    local count = 0

    if not set then
        return 0
    end

    for _ in pairs(set) do
        count = count + 1
    end

    return count
end

function Filters.SelectAll(state, field, values)
    local set = state.selected[field]

    if not set then
        return
    end

    for _, value in ipairs(values or {}) do
        set[value] = true
    end
end

function Filters.ClearField(state, field)
    state.selected[field] = {}
end

function Filters.ClearAll(state)
    state.search = ""
    state.dateFrom = nil
    state.dateTo = nil

    for _, field in ipairs(Filters.FIELDS) do
        state.selected[field] = {}
    end
end

function Filters.IsActive(state)
    if state.search and state.search ~= "" then
        return true
    end

    if state.dateFrom or state.dateTo then
        return true
    end

    for _, field in ipairs(Filters.FIELDS) do
        if Filters.CountSelected(state, field) > 0 then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------
-- Dates
--------------------------------------------------------------------------

-- Accepts MM-DD-YYYY, which is what every date on screen is written in, and
-- still accepts YYYY-MM-DD.
--
-- Liberal on the way in on purpose: the boxes used to demand ISO, anyone who
-- typed a date the way the rest of the addon prints it got silently no filter,
-- and an empty box and a rejected one look identical. Returns nil for anything
-- else, including an empty box, which the caller treats as "unbounded".
function Filters.ParseDate(text, endOfDay)
    if type(text) ~= "string" then
        return nil
    end

    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    if text == "" then
        return nil
    end

    local month, day, year = text:match("^(%d%d?)-(%d%d?)-(%d%d%d%d)$")

    if not year then
        -- ISO, still accepted so a date copied from anywhere else works.
        year, month, day = text:match("^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
    end

    if not year then
        return nil
    end

    return time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = endOfDay and 23 or 0,
        min = endOfDay and 59 or 0,
        sec = endOfDay and 59 or 0,
    })
end

function Filters.FormatDate(timestamp)
    if not timestamp then
        return ""
    end

    return date("%m-%d-%Y", timestamp)
end

--------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------

local function ReadField(fields, key, record)
    local reader = fields[key]

    if not reader then
        return nil
    end

    return reader(record)
end

local function MatchesSearch(state, fields, record)
    local search = state.search

    if not search or search == "" then
        return true
    end

    local needle = string.lower(search)

    for _, field in ipairs(Filters.FIELDS) do
        local value = ReadField(fields, field, record)

        if type(value) == "string"
            and string.lower(value):find(needle, 1, true)
        then
            return true
        end
    end

    return false
end

-- Values within a field are OR'd, fields are AND'd together. That is what
-- people expect from checkbox filters: ticking two players widens the result,
-- ticking a player and a boss narrows it.
local function MatchesSelections(state, fields, record)
    for _, field in ipairs(Filters.FIELDS) do
        if Filters.CountSelected(state, field) > 0 then
            local value = ReadField(fields, field, record)

            if not value or not Filters.IsSelected(state, field, value) then
                return false
            end
        end
    end

    return true
end

local function MatchesDate(state, fields, record)
    if not state.dateFrom and not state.dateTo then
        return true
    end

    local timestamp = ReadField(fields, "timestamp", record)

    if not timestamp then
        return false
    end

    if state.dateFrom and timestamp < state.dateFrom then
        return false
    end

    if state.dateTo and timestamp > state.dateTo then
        return false
    end

    return true
end

function Filters.Matches(state, fields, record)
    return MatchesSelections(state, fields, record)
        and MatchesDate(state, fields, record)
        and MatchesSearch(state, fields, record)
end

function Filters.Apply(records, state, fields)
    if not Filters.IsActive(state) then
        return records
    end

    local matched = {}

    for _, record in ipairs(records) do
        if Filters.Matches(state, fields, record) then
            table.insert(matched, record)
        end
    end

    return matched
end

--------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------

-- Options come from the records actually present, so a new raid tier
-- populates the dropdowns without any hardcoded list.
function Filters.DeriveOptions(records, fields, field)
    local seen = {}
    local options = {}

    for _, record in ipairs(records) do
        local value = ReadField(fields, field, record)

        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(options, value)
        end
    end

    table.sort(options)

    return options
end
