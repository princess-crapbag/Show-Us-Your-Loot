-- UI/ArchiveControls.lua
--
-- Renaming and merging archived seasons, from the Archives tab.
--
-- BOTH OF THESE EXIST AS SLASH COMMANDS AND THAT IS NOT ENOUGH. A guildie will
-- never find a command nobody told them about, and this addon ships to a
-- guild. The Archives tab already lists the seasons; the actions belong on it.
--
-- SELECTION IS KEYED BY SEASON ID, NOT BY ROW NUMBER. Merging removes seasons,
-- which renumbers everything below them — so a selection held as indexes would
-- point at different seasons the moment the merge it was describing finished.
-- The id is the only handle that survives its own operation.
--
-- MERGING IS NOT REVERSIBLE and the button says so before it runs. Nothing is
-- deleted — every drop, item and night ends up in the survivor — but which
-- season each came from cannot be recovered, and that is worth one confirm.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local ArchiveControls = {}
SYL.ArchiveControls = ArchiveControls

local INPUT_WIDTH = 170

function ArchiveControls.Selected(view)
    view.archiveSelection = view.archiveSelection or {}

    local indexes, names = {}, {}

    for index, season in ipairs(SYL.GetArchives()) do
        if season.id and view.archiveSelection[season.id] then
            table.insert(indexes, index)
            table.insert(names, season.name or "Unnamed Season")
        end
    end

    return indexes, names
end

function ArchiveControls.Toggle(view, index)
    local season = SYL.GetArchives()[index]

    if not season or not season.id then
        return false
    end

    view.archiveSelection = view.archiveSelection or {}

    view.archiveSelection[season.id] =
        not view.archiveSelection[season.id] or nil

    return true
end

function ArchiveControls.Clear(view)
    view.archiveSelection = {}
end

function ArchiveControls.IsSelected(view, index)
    local season = SYL.GetArchives()[index]

    return season
        and season.id
        and (view.archiveSelection or {})[season.id]
        and true
        or false
end

function ArchiveControls.Create(parent, view, config)
    local bar = CreateFrame("Frame", nil, parent)

    bar:SetHeight(24)
    bar:SetPoint("BOTTOMLEFT", 16, 26)
    bar:SetPoint("BOTTOMRIGHT", -16, 26)
    bar:Hide()

    local function Changed()
        if config and config.onChanged then
            config.onChanged()
        end
    end

    bar.count = Theme.CreateText(bar, Theme.sizes.rowSmall, "textMuted")
    bar.count:SetPoint("LEFT", 2, 0)
    bar.count:SetWidth(150)

    bar.nameInput = SYL.SearchBox.Create(
        bar, INPUT_WIDTH, "New name", function() end, { bordered = true }
    )

    bar.nameInput:SetPoint("LEFT", bar.count, "RIGHT", 8, 0)

    local function Named()
        local text = bar.nameInput.editBox:GetText() or ""

        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    bar.renameButton =
        Theme.CreateButton(bar, 84, 22, "Rename", function()
            local indexes = ArchiveControls.Selected(view)

            if #indexes ~= 1 then
                SYL:Print("Tick exactly one season to rename.")

                return
            end

            local ok, message = SYL.RenameArchive(indexes[1], Named())

            SYL:Print(message)

            if ok then
                bar.nameInput.editBox:SetText("")

                if bar.nameInput.UpdatePlaceholder then
                    bar.nameInput.UpdatePlaceholder()
                end

                Changed()
            end
        end)

    bar.renameButton:SetPoint("LEFT", bar.nameInput, "RIGHT", 8, 0)

    bar.mergeButton =
        Theme.CreateButton(bar, 84, 22, "Merge", function()
            local indexes, names = ArchiveControls.Selected(view)

            if #indexes < 2 then
                SYL:Print("Tick two or more seasons to merge them.")

                return
            end

            -- Confirmed rather than done, because it cannot be undone. The
            -- names are listed so somebody who ticked the wrong box sees it
            -- here rather than afterwards.
            SYL:Print(
                "Merge " .. #indexes .. " seasons — "
                .. table.concat(names, ", ") .. "?"
            )
            SYL:Write(
                "Nothing is deleted, but which season each record came from "
                .. "cannot be recovered. Press Merge again to confirm."
            )

            if not bar.pending or bar.pending ~= #indexes then
                bar.pending = #indexes

                return
            end

            bar.pending = nil

            local ok, message = SYL.MergeArchives(indexes, Named())

            SYL:Print(message)

            if ok then
                ArchiveControls.Clear(view)

                bar.nameInput.editBox:SetText("")

                if bar.nameInput.UpdatePlaceholder then
                    bar.nameInput.UpdatePlaceholder()
                end

                Changed()
            end
        end)

    bar.mergeButton:SetPoint("LEFT", bar.renameButton, "RIGHT", 6, 0)

    -- THE WAY BACK FROM THE ARCHIVE BUTTON, which had none. Aimee, having
    -- archived a season she was still raiding: "i archived the 08/18-08/22.
    -- now how do i unarchive them?" There was no answer anywhere in the
    -- addon, which is the rule in HANDOFF broken plainly — anything that can
    -- be created has to be undoable from the same screen, and this is that
    -- screen.
    --
    -- MEASURED, like the two beside it: "Make active" is 65px in the real
    -- font, so 84 holds it with the same padding Rename and Merge use.
    bar.unarchiveButton =
        Theme.CreateButton(bar, 84, 22, "Make active", function()
            local indexes, names = ArchiveControls.Selected(view)

            if #indexes ~= 1 then
                SYL:Print("Tick exactly one season to bring back.")

                return
            end

            local season, displaced = SYL.UnarchiveSeason(indexes[1])

            if not season then
                SYL:Print(displaced or "Could not bring that season back.")

                return
            end

            ArchiveControls.Clear(view)

            -- Said plainly, because this moves two seasons at once and only
            -- one of them was ticked. Somebody who does not know the season
            -- they were on has been filed away will go looking for it.
            SYL:Print(
                "\"" .. tostring(season.name or names[1])
                .. "\" is the active season again."
            )

            if displaced then
                SYL:Write(
                    "The season you were on, \""
                    .. tostring(displaced.name)
                    .. "\", had records in it and was archived rather than "
                    .. "thrown away. It is on this list."
                )
            end

            Changed()
        end)

    bar.unarchiveButton:SetPoint("LEFT", bar.mergeButton, "RIGHT", 6, 0)

    bar.clearButton =
        Theme.CreateButton(bar, 84, 22, "Untick all", function()
            ArchiveControls.Clear(view)
            bar.pending = nil

            Changed()
        end)

    bar.clearButton:SetPoint("LEFT", bar.mergeButton, "RIGHT", 12, 0)

    local Tip = SYL.Tooltips.Attach

    Tip(bar.nameInput, "New name",
        "Used by Rename, and by Merge to name the season the others fold "
        .. "into. Leave it empty and a merge keeps the oldest season's name.")

    Tip(bar.renameButton, "Rename",
        "Renames the one ticked season. An archive's records are sealed; its "
        .. "name is not, and typing it wrong used to be permanent.")

    Tip(bar.mergeButton, "Merge",
        "Folds every ticked season into the oldest one. Nothing is deleted, "
        .. "but which season each record came from cannot be recovered. Press "
        .. "it twice to confirm.")

    Tip(bar.clearButton, "Untick all",
        "Clears the ticks. It changes no season.")

    bar.Refresh = function()
        local indexes = ArchiveControls.Selected(view)

        bar.count:SetText(
            #indexes == 0 and "none ticked"
            or (#indexes .. (#indexes == 1 and " ticked" or " ticked"))
        )

        -- A different selection invalidates a pending confirm, so ticking one
        -- more season cannot be swept into a merge somebody already agreed to.
        if bar.pending and bar.pending ~= #indexes then
            bar.pending = nil
        end
    end

    return bar
end
