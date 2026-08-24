-- UI/SettingsItemTypes.lua
--
-- The Recording tab's second grid: which KINDS of item get written down.
--
-- Sits directly under the quality grid because the two are one question asked
-- twice, and one paragraph under both says so: unticking either never touches
-- a record already saved. Core/ItemTypes.lua holds what each row catches and
-- why; this file only draws them.
--
-- ITS OWN FILE for the reason the header in UI/SettingsRows.lua gives -- that
-- file is size-exempt at 700 lines and the escape hatch is not an invitation.
-- Built with its exported row factory and registered into its refresh list,
-- so these ticks and the quality ticks above them behave identically.
--
-- NINE ROWS, THREE ACROSS, which is the same grid the eight qualities use
-- directly above. Three lines of 20 rather than nine of 20 is the difference
-- between a tab that fits and one that does not.

local SYL = _G.ShowUsYourLoot

local SettingsItemTypes = {}
SYL.SettingsItemTypes = SettingsItemTypes

local ROW_HEIGHT = 20
local HEADING_HEIGHT = 18
local COLUMNS = 3

-- Said once for the quality grid above and this one together. Both filters
-- have exactly the same non-retroactive contract, and saying it twice a
-- section apart is how two sentences come to disagree.
SettingsItemTypes.SHARED_NOTE =
    "Unticked types and qualities are never recorded. Neither removes "
    .. "records you already have."

function SettingsItemTypes.SectionHeight()
    return HEADING_HEIGHT
        + SYL.SettingsRows.GridRows(#SYL.ItemTypes.ORDER, COLUMNS) * ROW_HEIGHT
end

-- "NEW" on the heading rule, because somebody who has used 0.4.0 opens this
-- tab knowing what is on it and would otherwise have to notice a whole grid
-- appearing. It is a marker on a section that changed, not decoration.
function SettingsItemTypes.Build(parent, top)
    local container, heading = SYL.SettingsRows.AddSection(
        parent, "RECORD THESE ITEM TYPES", top, "NEW"
    )

    container:SetHeight(
        SYL.SettingsRows.GridRows(#SYL.ItemTypes.ORDER, COLUMNS) * ROW_HEIGHT
    )

    for index, key in ipairs(SYL.ItemTypes.ORDER) do
        local row = SYL.SettingsRows.CreateRow(
            container,
            index,
            SYL.ItemTypes.NAMES[key],

            function()
                SYL.ItemTypes.SetTracked(key, not SYL.ItemTypes.IsTracked(key))
                SYL.SettingsRows.Refresh()
            end,

            { columns = COLUMNS }
        )

        -- Two words cannot say what "Sparks and hides" catches, and the row
        -- that turns off recording gear entirely should not be one click
        -- away from a person who has not been told what it does.
        SYL.Tooltips.Attach(
            row,
            SYL.ItemTypes.NAMES[key],
            SYL.ItemTypes.NOTES[key] or ""
        )

        row.isChecked = function()
            return SYL.ItemTypes.IsTracked(key)
        end

        SYL.SettingsRows.Register(row)
    end

    return container, SettingsItemTypes.SectionHeight(), heading
end
