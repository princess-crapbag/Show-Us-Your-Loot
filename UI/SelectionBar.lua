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

    bar.showHidden:SetPoint("TOPRIGHT", -16, -128)

    -- Three states rather than two, so it cycles instead of toggling. A
    -- Mythic+ drop says nothing about who is due in the raid, and a guild
    -- that runs both had them interleaved with no way to separate them.
    local SCOPES = { "all", "raid", "dungeon" }

    bar.contentScope =
        Theme.CreateButton(parent, 110, 20, "All content", function()
            local current = view.contentScope or "all"
            local nextIndex = 1

            for index, scope in ipairs(SCOPES) do
                if scope == current then
                    nextIndex = (index % #SCOPES) + 1
                end
            end

            view.contentScope = SCOPES[nextIndex]

            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.contentScope:SetPoint("RIGHT", bar.showHidden, "LEFT", -6, 0)

    -- Chat capture takes everything, so the tab is mostly reagents and gold
    -- with the gear somebody actually received buried in it. This is the
    -- same filter the due list uses, so the list and the maths agree.
    bar.gearOnly =
        Theme.CreateButton(parent, 100, 20, "Gear only", function()
            view.gearOnly = not view.gearOnly

            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.gearOnly:SetPoint("RIGHT", bar.contentScope, "LEFT", -6, 0)

    -- Not selection, but this is the row of list controls in practice, and
    -- Show hidden already sits here for the same reason.
    bar.allSeasons =
        Theme.CreateButton(parent, 100, 20, "All seasons", function()
            view.allSeasons = not view.allSeasons

            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.allSeasons:SetPoint("RIGHT", bar.gearOnly, "LEFT", -6, 0)

    bar.action = Theme.CreateButton(parent, 70, 20, "Hide", function()
        bar:ApplyHidden(IsShiftKeyDown())
    end)

    bar.action:SetPoint("RIGHT", bar.allSeasons, "LEFT", -6, 0)

    -- Takes the ticked records out of every number without deleting them.
    bar.ignore = Theme.CreateButton(parent, 74, 20, "Ignore", function()
        bar:ApplyIgnored(IsShiftKeyDown())
    end)

    bar.ignore:SetPoint("RIGHT", bar.action, "LEFT", -6, 0)

    bar.deselect = Theme.CreateButton(parent, 78, 20, "Deselect all", function()
        Selection.Clear(view.selection)

        onChanged()
    end)

    bar.deselect:SetPoint("RIGHT", bar.ignore, "LEFT", -6, 0)

    -- Selects what is on the list, which after filtering means what the
    -- filters matched rather than the whole season.
    bar.selectAll = Theme.CreateButton(parent, 68, 20, "Select all", function()
        Selection.SelectAll(view.selection, ListSources.GetFiltered(view))

        onChanged()
    end)

    bar.selectAll:SetPoint("RIGHT", bar.deselect, "LEFT", -6, 0)

    -- Four of these narrow or widen the same list along different axes and
    -- three of them are toggles, so pressing one to find out what it does
    -- changes what you were reading. See UI/Tooltips.lua.
    local Tip = SYL.Tooltips.Attach

    Tip(bar.showHidden, "Show hidden",
        "Hidden rows are set aside, never deleted. This shows only those, "
        .. "so you can put them back.")

    Tip(bar.contentScope, "All content / Raid / Dungeon",
        "Cycles. A Mythic+ drop says nothing about who is due in the raid, "
        .. "and a guild that runs both has them interleaved.")

    Tip(bar.gearOnly, "Gear only",
        "Hides reagents, gold and quest items. The same test the due list "
        .. "uses, so this list and those numbers agree.")

    Tip(bar.allSeasons, "All seasons",
        "Widens the list to archived seasons as well as the active one.")

    Tip(bar.action, "Hide or unhide",
        "Sets the ticked rows aside. Hold Shift to hide every copy of the "
        .. "same item on this list, not just the rows you ticked. Nothing is "
        .. "deleted and the numbers do not change.")

    Tip(bar.ignore, "Ignore or restore",
        "Takes the ticked rows out of every number — the due list, droughts, "
        .. "player stats — for when a record is simply wrong. Hold Shift for "
        .. "every copy of the item. Nothing is deleted and it is reversible.")

    Tip(bar.selectAll, "Select all",
        "Ticks everything the filters currently match, not the whole season.")

    Tip(bar.deselect, "Deselect all", "Unticks everything.")

    bar.countText = Theme.CreateText(parent, Theme.sizes.subtitle, "accent")
    bar.countText:SetPoint("RIGHT", bar.selectAll, "LEFT", -10, 0)
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

    -- Shared by both bulk actions, which differ only in the flag they write.
    --
    -- allCopies comes from Shift being held, which is the game's own idiom
    -- for "and everything like it" and costs no room on a row that has none.
    -- The result line says which happened either way, because the difference
    -- between three records and one is exactly what somebody needs told.
    local function ApplySelection(config)
        local records = ListSources.GetFiltered(view)
        local count = view.selection.count

        if count == 0 then
            SYL:Print("Tick some rows first, or use Select all.")

            return
        end

        local already = config.countOn(view.selection, records)

        -- A mixed selection turns the flag on, because that is what the
        -- button offered.
        local turningOn = already < count

        local changed = config.apply(
            view.selection, records, turningOn, config.allCopies
        )

        Selection.Clear(view.selection)

        SYL:Print(
            changed
            .. (changed == 1 and " record " or " records ")
            .. (turningOn and config.onText or config.offText)
            .. (config.allCopies and " (every copy on this list)" or "")
            .. "."
            .. (turningOn and (" " .. config.reassurance) or "")
        )

        onChanged()
    end

    bar.ApplyHidden = function(_, allCopies)
        ApplySelection({
            allCopies = allCopies,
            countOn = Selection.CountHidden,
            apply = Selection.ApplyHidden,
            onText = "hidden",
            offText = "unhidden",
            reassurance =
                "Nothing was deleted and the numbers are unchanged.",
        })
    end

    bar.ApplyIgnored = function(_, allCopies)
        ApplySelection({
            allCopies = allCopies,
            countOn = Selection.CountIgnored,
            apply = Selection.ApplyIgnored,
            onText = "ignored",
            offText = "counted again",
            reassurance =
                "They are out of every number now, and still in the list.",
        })
    end

    bar.Update = function(self)
        local count = view.selection.count
        local onList = view.mode ~= "archives"

        -- Buttons stay put rather than appearing and disappearing, so the row
        -- does not reflow every time the selection changes.
        for _, control in ipairs({
            self.showHidden,
            self.action, self.ignore, self.deselect, self.selectAll,
        }) do
            if onList then
                control:Show()
            else
                control:Hide()
            end
        end

        -- Widening to every season means nothing when the view is already
        -- pinned to one archived season, and a button that does nothing
        -- reads as a broken one.
        if onList and view.mode ~= "archive" then
            self.allSeasons:Show()
        else
            self.allSeasons:Hide()
        end

        -- Shown on both lists, not only on drops. Retail dungeons award
        -- personal loot with no rolls, so dungeon gear never reaches the
        -- drops list at all — it arrives as chat loot, which makes that the
        -- list where separating raid from dungeon actually does something.
        if onList then
            local scope = view.contentScope or "all"

            self.contentScope.label:SetText(
                scope == "raid" and "Raids only"
                or scope == "dungeon" and "Dungeons only"
                or "All content"
            )

            Theme.SetTextColor(
                self.contentScope.label,
                scope == "all" and "textPrimary" or "accent"
            )

            self.contentScope:Show()
        else
            self.contentScope:Hide()
        end

        -- Both apply to the one list now: content scope sorts by where an
        -- item came from, this by whether it is gear at all.
        if onList then
            self.gearOnly.label:SetText(
                view.gearOnly and "Gear only" or "Everything"
            )

            Theme.SetTextColor(
                self.gearOnly.label,
                view.gearOnly and "accent" or "textPrimary"
            )

            self.gearOnly:Show()
        else
            self.gearOnly:Hide()
        end

        if not onList then
            self.countText:Hide()

            return
        end

        self.showHidden.label:SetText(
            view.showHidden and "Hidden only" or "Show hidden"
        )

        Theme.SetTextColor(
            self.showHidden.label,
            view.showHidden and "accent" or "textPrimary"
        )

        self.allSeasons.label:SetText(
            view.allSeasons and "All seasons" or "This season"
        )

        Theme.SetTextColor(
            self.allSeasons.label,
            view.allSeasons and "accent" or "textPrimary"
        )

        if count == 0 then
            self.countText:Hide()
            self.action.label:SetText("Hide")
            self.ignore.label:SetText("Ignore")

            return
        end

        -- When every selected row already carries the flag, the only sensible
        -- action is to take it off again.
        local records = ListSources.GetFiltered(view)

        local hiddenCount = Selection.CountHidden(view.selection, records)
        local ignoredCount = Selection.CountIgnored(view.selection, records)

        self.action.label:SetText(hiddenCount == count and "Unhide" or "Hide")

        self.ignore.label:SetText(
            ignoredCount == count and "Restore" or "Ignore"
        )

        self.countText:SetText(count .. " selected")
        self.countText:Show()
    end

    return bar
end
