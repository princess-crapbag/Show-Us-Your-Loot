-- Core/FilterOptions.lua
--
-- What goes IN a filter dropdown: the distinct values present in the records,
-- in the order they should be read.
--
-- SPLIT FROM Core/Filters.lua when it crossed the size limit, and this is the
-- seam that only points one way -- options are derived FROM records and
-- nothing in the matching half calls them. The other candidate, the defaults,
-- was tried first and rejected: Filters.MatchesSelections has to ask which
-- values are hidden by default, so pulling those out left two files calling
-- into each other and syl_check rightly refused to believe either.
--
-- ORDERED, NOT JUST LISTED. A player list reads raid team first; a raid
-- difficulty reads as the ladder. Sorted alphabetically both are noise.

local SYL = _G.ShowUsYourLoot

local FilterOptions = {}
SYL.FilterOptions = FilterOptions

-- Reading one field out of a record, through the caller's own descriptor.
-- The same three lines as Core/Filters.lua's local of the same name; both are
-- one indirection over a table the caller supplies, and exporting it would be
-- more surface than it saves.
local function ReadField(fields, key, record)
    local reader = fields[key]

    if not reader then
        return nil
    end

    return reader(record)
end

-- The player dropdown is ordered the way every other people-list in the addon
-- is narrowed: raid team first, then guild, then everybody else, alphabetical
-- inside each group.
--
-- ORDERED RATHER THAN FILTERED, and that is the judgement call worth
-- challenging. This dropdown drives the loot list, and the loot list is a
-- record of drops rather than a list of people — a pug's win is a row that is
-- already on screen. Dropping their name would leave a visible row that no
-- filter could reach, which is a worse fault than a long list. Ordering puts
-- the raiders at the top, which is what the scope is actually for here.
--
-- Ranked once per distinct name rather than inside the comparator: Includes
-- walks the registry and the guild map, and a sort would ask it O(n log n)
-- times for an answer that cannot change mid-sort.
local function RankByAudience(options)
    local Audience = SYL.Audience

    if not Audience then
        table.sort(options)

        return
    end

    local rank = {}

    for _, value in ipairs(options) do
        if Audience.Includes("team", nil, nil, value) then
            rank[value] = 0
        elseif Audience.Includes("guild", nil, nil, value) then
            rank[value] = 1
        else
            rank[value] = 2
        end
    end

    table.sort(options, function(a, b)
        if rank[a] ~= rank[b] then
            return rank[a] < rank[b]
        end

        return a < b
    end)
end

-- Options come from the records actually present, so a new raid tier
-- populates the dropdowns without any hardcoded list.
function FilterOptions.Derive(records, fields, field)
    local seen = {}
    local options = {}

    for _, record in ipairs(records) do
        local value = ReadField(fields, field, record)

        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(options, value)
        end
    end

    if field == "player" then
        RankByAudience(options)
    elseif field == "difficulty" then
        -- THE LADDER, NOT THE ALPHABET. Sorted, L H M N reads as nothing;
        -- the four rungs have an order everybody already knows.
        local rank = {}

        for index, letter in ipairs(SYL.Filters.RAID_DIFFICULTY_ORDER) do
            rank[letter] = index
        end

        table.sort(options, function(left, right)
            return (rank[left] or 99) < (rank[right] or 99)
        end)
    else
        table.sort(options)
    end

    return options
end
