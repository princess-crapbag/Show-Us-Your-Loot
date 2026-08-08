-- UI/Selection.lua
--
-- Which rows are ticked, and what the bulk actions do to them.
--
-- Records are tracked by id rather than by row, because rows are pooled and
-- reused as the list scrolls or filters change.

local SYL = _G.ShowUsYourLoot

local Selection = {}
SYL.Selection = Selection

function Selection.Create()
    return {
        ids = {},
        count = 0,

        -- Index into the currently displayed list, used as the fixed end of a
        -- shift-click range.
        anchorIndex = nil,
    }
end

function Selection.IsSelected(selection, record)
    return record ~= nil
        and record.id ~= nil
        and selection.ids[record.id] == true
end

function Selection.Set(selection, record, on)
    if not record or not record.id then
        return
    end

    local already = selection.ids[record.id] == true

    if on and not already then
        selection.ids[record.id] = true
        selection.count = selection.count + 1
    elseif not on and already then
        selection.ids[record.id] = nil
        selection.count = selection.count - 1
    end
end

function Selection.Toggle(selection, record)
    Selection.Set(selection, record, not Selection.IsSelected(selection, record))
end

-- Selects everything currently on the list, which after filtering means
-- everything the filters matched rather than everything in the season.
function Selection.SelectAll(selection, records)
    for _, record in ipairs(records) do
        Selection.Set(selection, record, true)
    end
end

function Selection.Clear(selection)
    selection.ids = {}
    selection.count = 0
    selection.anchorIndex = nil
end

-- Selects everything between the anchor and the clicked row inclusive, in the
-- order currently on screen. Adds to the selection rather than replacing it,
-- so several ranges can be built up.
function Selection.SelectRange(selection, records, toIndex)
    local fromIndex = selection.anchorIndex or toIndex

    if fromIndex > toIndex then
        fromIndex, toIndex = toIndex, fromIndex
    end

    for index = fromIndex, toIndex do
        Selection.Set(selection, records[index], true)
    end
end

-- Returns how many records actually changed, so the caller can report
-- honestly rather than echoing the selection size.
function Selection.ApplyHidden(selection, records, hidden)
    local changed = 0

    for _, record in ipairs(records) do
        if Selection.IsSelected(selection, record) then
            local target = HideTarget(record)
            local current = target.hidden and true or false

            if current ~= hidden then
                target.hidden = hidden or nil
                changed = changed + 1
            end
        end
    end

    return changed
end

-- Counts how many of the selected records are currently hidden, which decides
-- whether the bulk action should read Hide or Unhide.
-- The merged list passes joined entries rather than raw records, and hidden
-- lives on the record underneath: the entry is rebuilt on every draw, so a
-- flag written to it would last until the next refresh and no longer.
local function HideTarget(record)
    return record.record or record
end

function Selection.CountHidden(selection, records)
    local hidden = 0

    for _, record in ipairs(records) do
        if Selection.IsSelected(selection, record)
            and HideTarget(record).hidden
        then
            hidden = hidden + 1
        end
    end

    return hidden
end
