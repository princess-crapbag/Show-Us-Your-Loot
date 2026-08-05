-- UI/SelectionBar.lua
--
-- The row of controls that appears once rows are ticked: how many are
-- selected, the hide or unhide action, and the toggle that reveals hidden
-- records so they can be brought back.
--
-- Owns the click behaviour for the row checkboxes too, since selection state
-- and the actions on it belong together.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Selection = SYL.Selection
local ListSources = SYL.ListSources

local SelectionBar = {}
SYL.SelectionBar = SelectionBar

function SelectionBar.Create(parent, view, config)
    local bar = {}
    local onChanged = config.onChanged

    bar.showHidden =
        Theme.CreateButton(parent, 108, 20, "Show hidden", function()
            view.showHidden = not view.showHidden

            -- The list is about to change shape underneath the selection.
            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.showHidden:SetPoint("TOPRIGHT", -16, -130)

    bar.action = Theme.CreateButton(parent, 70, 20, "Hide", function()
        bar:ApplyHidden()
    end)

    bar.action:SetPoint("RIGHT", bar.showHidden, "LEFT", -6, 0)

    bar.deselect = Theme.CreateButton(parent, 70, 20, "Deselect", function()
        Selection.Clear(view.selection)

        onChanged()
    end)

    bar.deselect:SetPoint("RIGHT", bar.action, "LEFT", -6, 0)

    bar.countText = Theme.CreateText(parent, Theme.sizes.subtitle, "accent")
    bar.countText:SetPoint("RIGHT", bar.deselect, "LEFT", -10, 0)
    bar.countText:SetJustifyH("RIGHT")
    bar.countText:Hide()

    -- Plain click toggles one row and becomes the anchor. Shift extends from
    -- that anchor to here, adding rather than replacing, so several ranges
    -- can be built up.
    bar.OnRowSelect = function(_, row, isShift)
        if not row.record then
            return
        end

        if isShift and view.selection.anchorIndex then
            Selection.SelectRange(
                view.selection,
                ListSources.GetFiltered(view),
                row.recordIndex
            )
        else
            Selection.Toggle(view.selection, row.record)

            view.selection.anchorIndex = row.recordIndex
        end

        onChanged()
    end

    bar.ApplyHidden = function()
        local records = ListSources.GetFiltered(view)
        local count = view.selection.count
        local hiddenCount = Selection.CountHidden(view.selection, records)

        -- A mixed selection hides, because that is what the button offered.
        local makeHidden = hiddenCount < count

        local changed =
            Selection.ApplyHidden(view.selection, records, makeHidden)

        Selection.Clear(view.selection)

        SYL:Print(
            changed
            .. (changed == 1 and " record " or " records ")
            .. (makeHidden and "hidden." or "unhidden.")
            .. (makeHidden and " Nothing was deleted." or "")
        )

        onChanged()
    end

    bar.Update = function(self)
        local count = view.selection.count
        local onList = view.mode ~= "archives"

        if onList then
            self.showHidden:Show()

            self.showHidden.label:SetText(
                view.showHidden and "Showing hidden" or "Show hidden"
            )

            Theme.SetTextColor(
                self.showHidden.label,
                view.showHidden and "accent" or "textPrimary"
            )
        else
            self.showHidden:Hide()
        end

        if count == 0 or not onList then
            self.countText:Hide()
            self.action:Hide()
            self.deselect:Hide()

            return
        end

        -- When every selected row is already hidden, the only sensible action
        -- is to put them back.
        local hiddenCount =
            Selection.CountHidden(view.selection, ListSources.GetFiltered(view))

        self.action.label:SetText(hiddenCount == count and "Unhide" or "Hide")

        self.countText:SetText(count .. " selected")
        self.countText:Show()
        self.action:Show()
        self.deselect:Show()
    end

    return bar
end
