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
--   onSort(key, rev)  called when a header NAME is clicked
--   onFilter(key)     called when a header CARET is clicked. Optional; a
--                     header with no onFilter draws no caret at all.
--   isFiltered(key)   whether that column is currently narrowing the list
--
-- TWO JOBS, TWO TARGETS, ONE HEADER.
--
-- Aimee, on moving the filter dropdowns into the headers: "all the sort by
-- filters in the columns, do they allow me to not only sort by but also
-- filter by?" They do. The NAME sorts, which is what it has always done and
-- must not stop doing; the CARET opens the filter.
--
-- THE CARET'S BUTTON IS WIDER THAN THE CARET. A caret measures about eight
-- pixels and an eight pixel target is one people miss, so its button is 18
-- and the full height of the header -- reaching into the gap that already
-- exists between columns, which costs the column no width.
--
-- SORTED AND FILTERED ARE DRAWN ON DIFFERENT CHANNELS, so a column that is
-- both says both: the arrow after the caret means sorted, the NAME going
-- accent means filtered. The arrow used to be appended to the label string,
-- which cannot coexist with a caret sitting in the same place -- so it is its
-- own region now.
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
    local carets = {}
    local arrows = {}

    local CARET_GAP = 4
    local CARET_TARGET = 18

    for _, column in ipairs(config.columns) do
        local button = CreateFrame("Button", nil, header)

        button:SetPoint("LEFT", config.offsets[column.key], 0)
        button:SetSize(column.width, HEIGHT)

        local label =
            Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

        label:SetAllPoints()
        label:SetText(column.label)

        labels[column.key] = label

        -- THE FILTER CARET, and the arrow after it.
        --
        -- Positioned off the MEASURED width of the label rather than off the
        -- column, so it sits against the name whatever the name is. Every
        -- other width in this addon is measured for the same reason; see
        -- Theme.MeasureText.
        if config.makeFilter and column.filterable ~= false
            and column.sortable ~= false
        then
            local nameWidth =
                Theme.MeasureText(Theme.sizes.columnHeader, column.label)

            local caret =
                Theme.CreateText(header, Theme.sizes.columnHeader, "textMuted")

            caret:SetPoint(
                "LEFT", config.offsets[column.key] + nameWidth + CARET_GAP, 0
            )

            caret:SetText("v")

            carets[column.key] = caret

            -- THE HEADER PLACES IT; THE BAR DECIDES WHAT IT DOES.
            --
            -- makeFilter hands back a bare dropdown button -- no background,
            -- no label, just the click and the panel -- built from the same
            -- configuration the bar used when these lived on it. So there is
            -- one definition of what a filter is, and this file only says
            -- where it goes.
            local caretButton = config.makeFilter(column.key, header)

            if caretButton then
                caretButton:SetPoint(
                    "LEFT",
                    config.offsets[column.key] + nameWidth + CARET_GAP - 5,
                    0
                )

                caretButton:SetSize(CARET_TARGET, HEIGHT)

                -- Above the sort button, so a click on the caret filters
                -- rather than sorting. Everywhere else on the header sorts.
                caretButton:SetFrameLevel(button:GetFrameLevel() + 2)

                SYL.Tooltips.Attach(
                    caretButton,
                    "Filter by " .. column.label:lower(),
                    "Click the column NAME to sort by it. This opens the "
                    .. "filter."
                )
            end

            local arrow =
                Theme.CreateText(header, Theme.sizes.columnHeader, "accent")

            arrow:SetPoint(
                "LEFT",
                config.offsets[column.key] + nameWidth + CARET_GAP + 11,
                0
            )

            arrows[column.key] = arrow
        end

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
            local caret = carets[column.key]
            local arrow = arrows[column.key]

            -- FILTERED IS THE NAME'S COLOR. Not the arrow's: a column can be
            -- sorted and filtered at once, and one state must not hide the
            -- other.
            local filtered = config.isFiltered
                and config.isFiltered(column.key)

            Theme.SetTextColor(label, filtered and "accent" or "textMuted")

            if caret then
                Theme.SetTextColor(caret, filtered and "accent" or "textMuted")
            end

            -- SORTED IS THE ARROW. Its own region rather than appended to the
            -- label, because the caret is where the appended arrow used to
            -- go.
            if arrow then
                arrow:SetText(
                    key == column.key and (reversed and "^" or "v") or ""
                )
            end

            -- A column with no caret has nowhere to put an arrow, so it says
            -- so the old way. Only the tickbox and # are in that state, and
            -- neither can be sorted by.
            if not arrow and key == column.key then
                label:SetText(column.label .. (reversed and "  ^" or "  v"))
                Theme.SetTextColor(label, "accent")
            elseif not arrow then
                label:SetText(column.label)
            end
        end
    end

    return header
end
