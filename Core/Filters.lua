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
Filters.FIELDS = { "player", "item", "location", "wintype", "difficulty" }

Filters.LABELS = {
    player = "Player",
    item = "Item",
    location = "Location",
    wintype = "Win type",
    difficulty = "Difficulty",
}

-- RAID DIFFICULTY, IN ONE LETTER EACH. Aimee drew it as
-- "[] L  [] N  [] H  [] M", and these are the four a raid can be run on.
--
-- Utilities.ShortDifficulty is not reused here: it answers "LFR", "N", "HC",
-- "M" and covers dungeons and delves too, and this filter is about the four
-- rungs of a raid ladder. A dungeon drop answers nothing and is therefore
-- filtered out whenever a raid difficulty is chosen, which is what a control
-- named Raid Difficulty should do.
-- SPELLED OUT, NOT INITIALS. Aimee first sketched it as "[] L [] N [] H
-- [] M" and then, once it had a column of its own with room in it: "i wonder
-- if we should put Difficulty and spell the raid difficulty out. LFR, Normal,
-- Heroic, Mythic."
--
-- One table, so the column and the filter cannot disagree about what a
-- difficulty is called.
Filters.RAID_DIFFICULTY = {
    [17] = "LFR",
    [151] = "LFR",
    [14] = "Normal",
    [33] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
}

-- The order they appear in, which is the ladder rather than the alphabet.
Filters.RAID_DIFFICULTY_ORDER = { "LFR", "Normal", "Heroic", "Mythic" }

-- HIDDEN UNTIL SOMEBODY ASKS FOR THEM, out of the box.
--
-- Aimee: "have the win type default on greed, mog, need. default off
-- personal."
--
-- WRITTEN AS AN EXCLUSION AND NOT AS A LIST OF THREE, which matters more than
-- it looks. Her dropdown shows four types today because four are in her data,
-- and an explicit {Greed, Mog, Need} would silently hide Offspec the first
-- time one is recorded -- her own season already holds sixteen offspec rolls.
-- An exclusion cannot do that: anything new is visible by default and only
-- what is named here is not.
--
-- IT APPLIES ONLY WHILE NOBODY HAS TOUCHED THE FIELD. The moment a value is
-- ticked the selection is explicit and this stops applying, so the control
-- always says what it is doing.
Filters.HIDDEN_BY_DEFAULT = {
    wintype = {
        -- Personal loot is outside the fairness math by design -- it never
        -- reaches the group-loot store at all -- so a list that opens on it
        -- opens on records the boards will never argue about.
        Personal = true,
    },
}

function Filters.HiddenByDefault(field, value)
    local hidden = Filters.HIDDEN_BY_DEFAULT[field]

    return (hidden and value ~= nil and hidden[value]) and true or false
end

-- Whether the dropdown should draw this value ticked. Not the same question
-- as IsSelected: with nothing chosen, everything except the defaults-off set
-- is showing, and the tickboxes have to say so.
function Filters.IsShowing(state, field, value)
    if Filters.CountSelected(state, field) > 0 then
        return Filters.IsSelected(state, field, value)
    end

    -- Touched and empty: nothing is showing, and every box is drawn clear.
    if state.touched and state.touched[field] then
        return false
    end

    return not Filters.HiddenByDefault(field, value)
end

-- THE DIFFICULTY THE LAST RAID WAS ON, as one of L/N/H/M.
--
-- Aimee: "have it default to the last raid difficulty you were in." Read off
-- the most recent recorded raid session rather than from a setting, so it
-- follows the guild through a tier without anybody maintaining it -- the
-- night after they step up to Heroic, the list opens on Heroic.
--
-- Returns nil when nothing has been recorded yet, which leaves the filter
-- unconstrained rather than picking one arbitrarily.
function Filters.LastRaidDifficulty(sessions)
    local latest, letter

    for _, session in ipairs(sessions or {}) do
        local rung = Filters.RAID_DIFFICULTY[session.difficultyID]

        if rung and (not latest or (session.startedAt or 0) > latest) then
            latest = session.startedAt or 0
            letter = rung
        end
    end

    return letter
end

-- Sets the difficulty filter to whatever was last raided, once.
--
-- ONLY WHEN NOTHING HAS BEEN CHOSEN, so reopening the window cannot undo a
-- choice somebody made -- and it clears itself rather than sticking if there
-- is no answer.
function Filters.ApplyDefaultDifficulty(state, sessions)
    if not state or Filters.CountSelected(state, "difficulty") > 0 then
        return nil
    end

    local letter = Filters.LastRaidDifficulty(sessions)

    if not letter then
        return nil
    end

    state.selected.difficulty[letter] = true

    return letter
end

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
            difficulty = {},
        },

        -- WHETHER ANYBODY HAS TOUCHED THIS FIELD, which is not the same
        -- question as whether anything is selected in it.
        --
        -- An empty selection used to mean one thing -- "no constraint" -- and
        -- it had to mean two. Before anybody touches a field, empty means
        -- "everything except what HIDDEN_BY_DEFAULT names". After they press
        -- None it means "nothing", which is what the button says. Without the
        -- distinction None cleared the set and the list showed EVERYTHING,
        -- which it has done since the button was written.
        touched = {},

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

    state.touched[field] = true

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

    state.touched[field] = true

    for _, value in ipairs(values or {}) do
        set[value] = true
    end
end

-- Ticks everything that is currently showing, which is everything except the
-- defaults-off set. The step that turns "nothing chosen" into an explicit
-- selection without changing what is on screen.
function Filters.SelectShowing(state, field, values)
    local set = state.selected[field]

    if not set then
        return
    end

    for _, value in ipairs(values or {}) do
        if not Filters.HiddenByDefault(field, value) then
            set[value] = true
        end
    end
end

-- NONE, and it means none.
--
-- Empties the field AND marks it touched, so the empty set reads as "chosen
-- nothing" rather than "nothing chosen yet". The dropdown's None button calls
-- this; the bar's Clear button calls ClearField, which is the other one.
function Filters.SelectNone(state, field)
    state.selected[field] = {}
    state.touched[field] = true
end

-- Back to the state a fresh window is in: nothing chosen, and nothing chosen
-- YET, so the defaults apply again.
function Filters.ClearField(state, field)
    state.selected[field] = {}
    state.touched[field] = nil
end

function Filters.ClearAll(state)
    state.search = ""
    state.dateFrom = nil
    state.dateTo = nil

    for _, field in ipairs(Filters.FIELDS) do
        state.selected[field] = {}
        state.touched[field] = nil
    end
end

-- ALWAYS ACTIVE WHILE ANYTHING IS HIDDEN BY DEFAULT.
--
-- Filters.Apply returns the records untouched when this is false, so a
-- default exclusion that did not make the state "active" would never run --
-- the list would open showing personal loot and only start hiding it once
-- some other filter was set. Found by asking why the first version changed
-- nothing.
function Filters.IsActive(state)
    if next(Filters.HIDDEN_BY_DEFAULT) ~= nil then
        return true
    end

    if state.touched and next(state.touched) ~= nil then
        return true
    end

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

-- Filters.FormatDate lived here and had no callers. It was a second date
-- formatter sitting one file away from Utilities.FormatDateOnly, agreeing with
-- it exactly — which is the state a formatter is in right before somebody
-- changes one of them. Deleted rather than kept in step: the separator moved
-- from "-" to "/" on the day this comment was written, and a dead copy would
-- have been the version that stayed behind.

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
        local chosen = Filters.CountSelected(state, field) > 0
        local value = ReadField(fields, field, record)

        if chosen then
            if not value or not Filters.IsSelected(state, field, value) then
                return false
            end
        elseif state.touched[field] then
            -- CHOSEN NOTHING. The field was touched and is now empty, which
            -- is what None leaves behind, and it means what it says.
            return false
        elseif Filters.HiddenByDefault(field, value) then
            -- NOTHING CHOSEN YET, so everything shows except what
            -- HIDDEN_BY_DEFAULT names. See the note there.
            return false
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

-- WHAT GOES IN A DROPDOWN lives in Core/FilterOptions.lua: deriving the
-- distinct values out of the records, and the order they read in. Nothing in
-- this file calls it, which is what made it the seam worth cutting when this
-- file crossed the size limit.
