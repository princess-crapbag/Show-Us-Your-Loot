-- UI/SelectionBar.lua
--
-- The row of controls for the list: the hide or unhide action, ignore, the
-- select-all pair, and the toggles that narrow or widen what is on screen.
--
-- How many rows are ticked is reported by the summary line above, not here —
-- see DescribeCount in UI/LootListView.lua.
--
-- Owns the click behavior for the row checkboxes too, since selection state
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
        Theme.CreateButton(parent, 84, 20, "Show hidden", function()
            view.showHidden = not view.showHidden

            -- The list is about to change shape underneath the selection.
            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    -- THE WHOLE BAR MOVED TO THE FOOTER LINE.
    --
    -- Aimee: "maybe the select all, deselect all, ignore, hide, hide all and
    -- show hidden options can be at the bottom of the frame to free up space
    -- on the top?"
    --
    -- It also had to move: with Hide all added, the buttons reached back into
    -- the "N items · N hidden" summary on the left. That is the second time
    -- this row has collided with that summary -- see the note further down --
    -- and there is no arrangement of nine buttons and a sentence that fits
    -- 830px.
    --
    -- The footer line was free. UI/MainFooter.lua's BUTTONS list has been
    -- empty since all six of its buttons became tabs, so only Close was on
    -- it, hard against the right edge. The actions flow from the LEFT and the
    -- scope toggles sit beside Close on the right, because the two groups do
    -- different things: one acts on the list, the other narrows it.
    --
    -- FOOTER_Y matches UI/MainFooter.lua's own 12-from-the-bottom, so the two
    -- rows are one row.
    local FOOTER_Y = 13

    -- Close is 100 wide at -16, so the scope group starts at -122.
    bar.showHidden:SetPoint("BOTTOMRIGHT", -(16 + 100 + 6), FOOTER_Y)

    -- Three states rather than two, so it cycles instead of toggling. A
    -- Mythic+ drop says nothing about who is due in the raid, and a guild
    -- that runs both had them interleaved with no way to separate them.
    local SCOPES = { "all", "raid", "dungeon" }

    bar.contentScope =
        Theme.CreateButton(parent, 96, 20, "All content", function()
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
    -- same filter the due list uses, so the list and the math agree.
    bar.gearOnly =
        Theme.CreateButton(parent, 74, 20, "Gear only", function()
            view.gearOnly = not view.gearOnly

            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.gearOnly:SetPoint("RIGHT", bar.contentScope, "LEFT", -6, 0)

    -- Not selection, but this is the row of list controls in practice, and
    -- Show hidden already sits here for the same reason.
    bar.allSeasons =
        Theme.CreateButton(parent, 76, 20, "All seasons", function()
            view.allSeasons = not view.allSeasons

            Selection.Clear(view.selection)

            view.offset = 0

            onChanged()
        end)

    bar.allSeasons:SetPoint("RIGHT", bar.gearOnly, "LEFT", -6, 0)

    bar.action = Theme.CreateButton(parent, 70, 20, "Hide", function()
        bar:ApplyHidden(IsShiftKeyDown())
    end)


    -- HIDE EVERY COPY, AS A BUTTON.
    --
    -- This could already be done -- Hide has honoured Shift since it was
    -- written -- and the only place that said so was the Hide tooltip. Aimee,
    -- who has been using this screen for weeks: "when i select an item like a
    -- crystal id like to be able to 'hide all'." She had not found it, which
    -- is the house rule about commands applied to a modifier key: a thing
    -- nobody is told about is a thing nobody has.
    --
    -- Same code path, same undo, same reassurance. Only the door is new.
    bar.hideAllCopies =
        Theme.CreateButton(parent, 74, 20, "Hide all", function()
            bar:ApplyHidden(true)
        end)


    -- Takes the ticked records out of every number without deleting them.
    bar.ignore = Theme.CreateButton(parent, 74, 20, "Ignore", function()
        bar:ApplyIgnored(IsShiftKeyDown())
    end)


    bar.deselect = Theme.CreateButton(parent, 78, 20, "Deselect all", function()
        Selection.Clear(view.selection)

        onChanged()
    end)


    -- Selects what is on the list, which after filtering means what the
    -- filters matched rather than the whole season.
    bar.selectAll = Theme.CreateButton(parent, 68, 20, "Select all", function()
        Selection.SelectAll(view.selection, ListSources.GetFiltered(view))

        onChanged()
    end)


    -- Four of these narrow or widen the same list along different axes and
    -- three of them are toggles, so pressing one to find out what it does
    -- changes what you were reading. See UI/Tooltips.lua.
    local Tip = SYL.Tooltips.Attach

    -- THE ACTION GROUP, PLACED IN ONE PASS AND CHAINED.
    --
    -- Chained rather than given fixed offsets, because the buttons are five
    -- different widths -- 68, 78, 74, 70, 74 -- and a hand-added offset is a
    -- number that goes stale the first time a label changes.
    --
    -- IT FLOWS FROM THE LEFT AND THAT IS NOT ENOUGH ON ITS OWN. This comment
    -- used to claim the group "can grow without ever reaching the scope group
    -- on the right"; it had already reached it. The left chain ended at 404
    -- and the right chain started at 342, so Hide all covered 62 of the 100
    -- pixels of All seasons -- and, being created later at the same frame
    -- level, took its clicks as well.
    --
    -- The four right-hand toggles were each 24 to 34 pixels wider than the
    -- widest label they can ever hold. Trimmed to label + 16 they start at
    -- 430 instead of 342.
    --
    -- THE LIVE BUDGET: the left chain ends at 404, the right chain starts at
    -- 430, and there are 26 pixels between them. Any button added to the loop
    -- below has to be checked against that number, because nothing here will
    -- notice on its own.
    --
    -- Placed here rather than beside each button because selectAll anchors
    -- the rest and is created last.
    local previous

    for _, control in ipairs({
        bar.selectAll, bar.deselect, bar.ignore, bar.action,
        bar.hideAllCopies,
    }) do
        if previous then
            control:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            control:SetPoint("BOTTOMLEFT", 16, FOOTER_Y)
        end

        previous = control
    end

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
        "Sets the ticked rows aside -- only the rows you ticked. Nothing is "
        .. "deleted and the numbers do not change.")

    Tip(bar.hideAllCopies, "Hide every copy",
        "Tick one crystal and this hides every crystal on the list, not just "
        .. "that row. Same as Hide otherwise: nothing is deleted, the numbers "
        .. "do not change, and Show hidden brings them all back.")

    Tip(bar.ignore, "Ignore or restore",
        "Takes the ticked rows out of every number — the due list, droughts, "
        .. "player stats — for when a record is simply wrong. Hold Shift for "
        .. "every copy of the item. Nothing is deleted and it is reversible.")

    Tip(bar.selectAll, "Select all",
        "Ticks everything the filters currently match, not the whole season.")

    Tip(bar.deselect, "Deselect all", "Unticks everything.")

    -- The selected count used to live here, right-anchored into the same
    -- space the "N items · N hidden" summary occupies, and the two overlapped.
    -- It is part of that sentence now — see DescribeCount in
    -- UI/LootListView.lua — which is one text, one anchor, and no collision.

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

    -- Everything this bar owns, off screen. A panel mode draws its own body
    -- and these would otherwise sit on top of it — Update alone is not enough,
    -- because it only ever decides between showing and hiding for the list.
    --
    -- MIND THE TWO MEANINGS OF "HIDE ALL" IN THIS FILE. This one hides the
    -- BAR. The button added above is `hideAllCopies` and hides every copy of
    -- an item, which is why it is not called HideAll -- a second HideAll
    -- would simply have replaced this one.
    bar.HideAll = function(self)
        for _, control in ipairs({
            self.showHidden, self.action, self.hideAllCopies, self.ignore,
            self.deselect, self.selectAll, self.allSeasons,
            self.contentScope, self.gearOnly,
        }) do
            if control then
                control:Hide()
            end
        end
    end

    bar.Update = function(self)
        local count = view.selection.count
        local onList = view.mode ~= "archives"

        -- Buttons stay put rather than appearing and disappearing, so the row
        -- does not reflow every time the selection changes.
        for _, control in ipairs({
            self.showHidden,
            self.action, self.hideAllCopies, self.ignore,
            self.deselect, self.selectAll,
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
    end

    return bar
end
