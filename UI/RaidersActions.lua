-- UI/RaidersActions.lua
--
-- The Raiders tab's footer bar: archiving whoever is selected, and bringing
-- them back.
--
-- SPLIT OUT because UI/RaidersPanel.lua was carrying the board, the roster
-- toggle, the archived view, the scroll state and this, and had reached nearly
-- twice the size limit. The same reason UI/RaidersSort.lua and
-- UI/RaidersRoster.lua came out of it, and this is the same kind of subject:
-- one strip of the screen, and the rule for what it offers.
--
-- ON THE WINDOW'S FOOTER LINE AND NOT INSIDE THE PANEL. 13 from the bottom is
-- where UI/SelectionBar.lua and UI/ArchiveControls.lua put theirs, so this
-- shares a centre line with Close and with the action row on the other tabs
-- rather than starting a second convention a few pixels off it.
--
-- That means it is parented to the window and does not disappear with the
-- panel on a tab change, so the panel puts it away by hand. The alternative
-- was a branch in UI/MainWindow.lua, which already hides five panels and two
-- other bars.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersActions = {}
SYL.RaidersActions = RaidersActions

local HEIGHT = 22
local FOOTER_Y = 13

-- Close is 100 wide at -16. A bar that ran the full width would put a button
-- nobody could press underneath the one button every window has.
local CLOSE_ROOM = 128

-- A label's own width plus a character of air each side, measured in the font
-- it is drawn in. These buttons are named after a person, so a fixed width
-- would be cut for Misothelioma and hollow for Hawt.
local LABEL_PAD = 26

local function Fit(button, text)
    button.label:SetText(text)
    button:SetWidth(Theme.MeasureText(Theme.sizes.rowSmall, text) + LABEL_PAD)
    button:Show()
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- WHAT PRESSING IT DOES, as a named function rather than an anonymous one
-- hung off the button.
--
-- Not a style choice. The test suite's stub frame answers every method with
-- itself, so a handler passed to SetScript cannot be fetched back out with
-- GetScript -- which means a click path written inline is a click path nothing
-- can drive. This is the one branch in the feature that decides between
-- archiving and restoring, and a test that cannot reach it would leave the
-- wiring proved only by looking at it.
function RaidersActions.Press(handlers)
    local key = handlers.getSelectedKey()

    if not key then
        return false
    end

    if handlers.isArchived() then
        if not SYL.ArchivedRaiders.Restore(key) then
            return false
        end

        SYL:Print("Back on the roster. Still not on the raid team.")
    elseif SYL.ArchivedRaiders.Archive(key) then
        SYL:Print(
            "Archived and taken off the raid team. Their nights and loot "
            .. "are kept — press Archived on the Raiders tab."
        )
    else
        -- The one way this fails: a character with no registry record.
        -- RosterData fills one per guild member before it builds, so this is a
        -- row from a source that had no GUID to key on -- a name off somebody
        -- else's shared roster.
        SYL:Print(
            "Could not archive that one — the addon has no record of the "
            .. "character, which happens for a name off somebody else's "
            .. "roster."
        )

        return false
    end

    handlers.onChanged()

    return true
end

-- `handlers` carries what the panel owns and this file cannot reach: which
-- raider is selected, whether the archived board is the one showing, and what
-- to do once something has changed.
function RaidersActions.Create(parent, handlers)
    local bar = CreateFrame("Frame", nil, parent)

    bar:SetHeight(HEIGHT)
    bar:SetPoint("BOTTOMLEFT", 16, FOOTER_Y)
    bar:SetPoint("BOTTOMRIGHT", -CLOSE_ROOM, FOOTER_Y)
    bar:Hide()

    bar.button = Theme.CreateButton(bar, 120, HEIGHT, "", function()
        RaidersActions.Press(handlers)
    end)

    bar.button:SetPoint("LEFT", 0, 0)

    bar.note = Theme.CreateText(bar, Theme.sizes.rowSmall, "textMuted")
    bar.note:SetPoint("LEFT", bar.button, "RIGHT", 12, 0)
    bar.note:SetPoint("RIGHT", 0, 0)
    bar.note:SetJustifyH("LEFT")
    bar.note:SetWordWrap(false)

    return bar
end

--------------------------------------------------------------------------
-- What it offers
--------------------------------------------------------------------------

-- NOTHING ON THE BOARD, deliberately. The board is the raid team, and
-- archiving somebody is saying they are not coming — doing that in one click
-- to a raider who is on the team is a mistake nobody would make on purpose.
-- Take them off the team first; the roster is one button away and the row is
-- there.
--
-- `name` is taken off the row that is on screen rather than looked up again.
-- If the registry and the row ever disagree, the row is what somebody is
-- reading, and the button has their name on it.
function RaidersActions.Update(bar, name, archived, view, selectedKey)
    if not bar then
        return
    end

    bar.button:Hide()
    bar.note:SetText("")

    if not name then
        bar:Hide()

        return
    end

    if archived then
        bar:Show()

        -- ONLY FOR SOMEBODY ARCHIVED BY HAND. Most of this board is derived —
        -- people who are simply not on the raid team — and there is nothing to
        -- undo for them. A button that explains rather than acts is a button
        -- somebody presses twice and then stops trusting, so it is not drawn:
        -- the line says where their row actually comes from.
        if not SYL.ArchivedRaiders.IsArchived(selectedKey) then
            bar.note:SetText(
                name .. " is here because they are not on the raid team, not "
                .. "because you archived them. Tick them on from the roster."
            )

            return
        end

        Fit(bar.button, "Bring " .. name .. " back")

        bar.note:SetText(
            "Puts them back on the roster. They stay off the raid team."
        )

        return
    end

    if view == "roster" then
        bar:Show()

        Fit(bar.button, "Archive " .. name)

        bar.note:SetText(
            "Takes them off this roster and keeps their season under Archived."
        )

        return
    end

    bar:Hide()
end
