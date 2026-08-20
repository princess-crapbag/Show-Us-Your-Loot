-- UI/SortHeader.lua
--
-- A column header whose labels are buttons: click one to sort by it, click it
-- again to reverse.
--
-- Lifted out of PlayerWindow, which had grown past the project's size limit
-- doing three jobs at once. None of this knows anything about players, and
-- the next list window that wants sorting should not have to copy it — the
-- boss window already shipped with a header copied out by hand.
--
-- The caller keeps the sort state. This asks for it and reports changes,
-- rather than holding a second copy that has to be kept in step.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SortHeader = {}
SYL.SortHeader = SortHeader

local HEIGHT = 22

-- Exported, because a caller placing something ABOVE this header has to know
-- how much room it takes, and until now nobody could: `top` is where the rows
-- begin and the header was silently backed off it by a magic 24. The roster's
-- filter strip was positioned in a different file, from the top of the window,
-- and the two numbers overlapped by 4px with nothing to catch it.
--
-- LIST_GAP is the clear space between the header's bottom edge and row one.
-- HEIGHT + LIST_GAP is the 24 that used to be written out longhand below.
SortHeader.HEIGHT = HEIGHT
SortHeader.LIST_GAP = 2

-- config:
--   columns, offsets  the same tables the rows are laid out from
--   top               distance from the top of the window to the list
--   getSort()         returns key, reversed
--   onSort(key, rev)  called when a header is clicked
function SortHeader.Create(parent, config)
    local header = CreateFrame("Frame", nil, parent)

    local headerTop = config.top - HEIGHT - SortHeader.LIST_GAP

    header:SetHeight(HEIGHT)
    header:SetPoint("TOPLEFT", 16, -headerTop)
    header:SetPoint("TOPRIGHT", -34, -headerTop)

    header.background =
        Theme.CreateSolidTexture(header, "headerBar", "BACKGROUND")

    header.background:SetAllPoints()

    local separator = Theme.CreateSeparator(header)
    separator:SetPoint("BOTTOMLEFT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", 0, 0)

    local labels = {}

    for _, column in ipairs(config.columns) do
        local button = CreateFrame("Button", nil, header)

        button:SetPoint("LEFT", config.offsets[column.key], 0)
        button:SetSize(column.width, HEIGHT)

        local label =
            Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

        label:SetAllPoints()
        label:SetText(column.label)

        labels[column.key] = label

        -- A column with `sortable = false` is drawn and not clickable.
        --
        -- Every header here was a button whether or not anything could sort
        -- by it, and a key with no comparator falls through to the default
        -- one — so clicking the tickbox column re-sorted the list by name and
        -- then drew the arrow over the tickbox, which reads as "sorted by
        -- this" and is a straight lie about what just happened.
        if column.sortable == false then
            button:EnableMouse(false)
        else
            button:SetScript("OnClick", function()
                local key, reversed = config.getSort()

                -- Clicking the active column flips it; a new column starts
                -- in its natural direction.
                if key == column.key then
                    config.onSort(key, not reversed)
                else
                    config.onSort(column.key, false)
                end
            end)
        end
    end

    -- Called on every refresh, so the arrow follows the sort even when it was
    -- changed by something other than a click.
    header.UpdateLabels = function()
        local key, reversed = config.getSort()

        for _, column in ipairs(config.columns) do
            local label = labels[column.key]

            if key == column.key then
                label:SetText(
                    column.label .. (reversed and "  ^" or "  v")
                )

                Theme.SetTextColor(label, "accent")
            else
                label:SetText(column.label)
                Theme.SetTextColor(label, "textMuted")
            end
        end
    end

    return header
end
