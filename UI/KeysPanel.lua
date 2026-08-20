-- UI/KeysPanel.lua
--
-- The Keys tab: every Mythic+ key this addon knows about, sortable, with a
-- button to ask somebody to run theirs.
--
-- THE ONE SCREEN THAT IS NOT SCOPED TO THE RAID TEAM. Every other people-list
-- narrows raid team, then guild, then everyone — see Core/Audience.lua. This
-- one deliberately does not, and Aimee said so directly: half the names on a
-- key list are not people you raid with, and narrowing it to the raid team
-- would hide most of the keys in the guild. UI/MainWindow.lua already put Keys
-- last in the tab order for the same reason.
--
-- NOTHING HERE CAN READ ANOTHER PLAYER'S BAGS. There is no API for it. Every
-- key on this list except your own arrived because that person is running this
-- addon with sharing on and their client broadcast it. An empty list mostly
-- means nobody else has it installed yet, which the empty state says rather
-- than leaving somebody to conclude the feature is broken.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Count = SYL.Utilities.Count

local KeysPanel = {}
SYL.KeysPanel = KeysPanel

-- Measuring the columns freed about 130px, and dead space between the table
-- and the pane would only have moved the problem rather than fixed it. It goes
-- to the requests, which is the half of this screen that is short of room: a
-- request has to name the key and which of your characters holds it, and four
-- answer buttons already take 220 of the 280 a row had.
local PANE_WIDTH = 420
local GUTTER = 12
local LIST_WIDTH = 868 - PANE_WIDTH - GUTTER

local ROW_HEIGHT = 20
local HEADER_TOP = 34
-- The box every column heading is drawn in. It has to be one number: the
-- headings sit on a shared baseline only because they share a height.
local HEADER_HEIGHT = 18
local LIST_TOP = 58
local VISIBLE_ROWS = 15

-- Columns and rows live in UI/KeyRows.lua. This file decides who is on the
-- list; that one draws them. See its header for why they parted.
local COLUMNS = SYL.KeyRows.COLUMNS

-- Everything a row has to ask this file for. The two callbacks are read when
-- the button is pressed rather than captured now, so the role the request
-- carries is whichever one the header is showing at that moment.
local rowConfig

local frame
local rows = {}
local offset = 0
local sortKey, sortReversed = "level", false
local askRole = "DPS"
local view = "keys"
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

-- Your own characters and everybody who broadcast one, in one list. Your own
-- are marked, because "can I ask for this" has a different answer for them and
-- a list where your own key looks like everybody else's invites the click.
local function Build()
    local entries = {}

    for _, own in ipairs(SYL.Keystone.List()) do
        -- A key from before this week's reset is gone. Carried through as an
        -- entry with no key rather than dropped, so the character still
        -- appears — an alt you have not logged into is exactly who you are
        -- checking on — and the row reads "no key" like anybody else's.
        local expired = own.isStale

        table.insert(entries, {
            name = own.characterKey or own.name,
            mapID = not expired and own.mapID or nil,
            level = not expired and own.level or nil,
            class = own.class,
            isOwn = true,
        })
    end

    -- Features.IsEnabled, not KeystoneSync.IsEnabled. The second is a runtime
    -- flag set by Enable() at login, so it reads false for the whole session
    -- if the feature was switched on afterwards — and the panel then told
    -- somebody their sharing was off while the settings screen and the
    -- recording strip both said on. The setting is what the user changed and
    -- is what they should be told about.
    if SYL.Features.IsEnabled("keystoneSharing") then
        for _, shared in ipairs(SYL.KeystoneSync.List()) do
            table.insert(entries, {
                name = shared.name,
                mapID = shared.mapID,
                level = shared.level,
                class = shared.class,
                isOwn = false,
            })
        end
    end

    local comparators = {
        name = function(left, right)
            return tostring(left.name) < tostring(right.name)
        end,
        dungeon = function(left, right)
            return tostring(SYL.Keystone.GetMapName(left.mapID))
                < tostring(SYL.Keystone.GetMapName(right.mapID))
        end,
        level = function(left, right)
            return (left.level or 0) > (right.level or 0)
        end,
    }

    local comparator = comparators[sortKey] or comparators.level

    table.sort(entries, function(left, right)
        if sortReversed then
            return comparator(right, left)
        end

        return comparator(left, right)
    end)

    return entries
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

-- Everything belonging to the keys view, so switching is one loop rather than
-- a list of Hide() calls that grows a bug every time a widget is added.
--
-- HIDING THE LIST IS NOT HIDING THE VIEW. The rows, the empty-state text, the
-- caption and the request pane are four separate things, and leaving any of
-- them up draws it straight through the grid. That has happened here before —
-- see HANDOFF.md on the dashboard tiles.
local function ShowKeysWidgets(shown)
    for _, widget in ipairs(frame.keysWidgets or {}) do
        if shown then
            widget:Show()
        else
            widget:Hide()
        end
    end

    if not shown then
        for _, row in ipairs(rows) do
            row:Hide()
        end

        frame.empty:Hide()
    end
end

Refresh = function()
    if not frame then
        return
    end

    frame.viewButton.label:SetText(view == "keys" and "Lockouts" or "Keys")

    if view == "lockouts" then
        ShowKeysWidgets(false)

        frame.grid:Show()

        local columns, characters = SYL.LockoutsGrid.Refresh()

        frame.caption:SetText(
            characters == 0
                and ("No character has been seen yet. Each one appears the "
                    .. "first time you log into it — nothing can read an alt's "
                    .. "lockouts from here.")
                or (characters .. " characters · " .. columns .. " dungeons · "
                    .. "Mythic 0 only; Mythic+ has no lockout")
        )

        return
    end

    frame.grid:Hide()
    ShowKeysWidgets(true)

    local entries = Build()
    local maxOffset = math.max(0, #entries - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    frame.roleButton.label:SetText(
        SYL.KeystoneRequests.ROLE_LABELS[askRole] or askRole
    )

    local pending = SYL.KeystoneRequests.PendingCount()

    frame.badge:SetText(pending > 0
        and (pending .. (pending == 1 and " request" or " requests") .. " to you")
        or "")

    Theme.SetTextColor(frame.badge, pending > 0 and "warning" or "textMuted")

    if #entries == 0 then
        for _, row in ipairs(rows) do
            row:Hide()
        end

        frame.empty:SetText(
            SYL.Features.IsEnabled("keystoneSharing")
                and ("No keys yet. Yours appears once you have one, and other "
                    .. "people's appear when they run this addon with key "
                    .. "sharing on — nothing can read another player's bags.")
                or ("Key sharing is off, so this shows only your own "
                    .. "characters. Turn it on in Settings to see the guild's.")
        )
        frame.empty:Show()
    else
        frame.empty:Hide()

        for index = 1, VISIBLE_ROWS do
            local entry = entries[index + offset]
            local row = rows[index]

            if not row then
                row = SYL.KeyRows.Create(index, rowConfig)
                rows[index] = row
            end

            if entry then
                row.playerName = entry.name

                row.cells.name:SetText(tostring(entry.name))

                local classColor = Theme.GetClassColor(entry.class)

                if classColor then
                    Theme.SetCustomTextColor(
                        row.cells.name, classColor[1], classColor[2], classColor[3]
                    )
                else
                    Theme.SetTextColor(row.cells.name, "textPrimary")
                end

                row.cells.dungeon:SetText(
                    tostring(SYL.Keystone.GetMapName(entry.mapID) or "Unknown")
                )

                row.cells.level:SetText(tostring(entry.level or "?"))

                SYL.KeyRows.DrawAsk(row, entry, rowConfig)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    SYL.KeyRequestList.Refresh(frame.pane)

    -- Counts keys, not rows. Characters holding none are listed and are not
    -- keys, and neither is an alt's expired one — a caption that counted them
    -- would disagree with the list it sits under.
    local held = 0

    for _, entry in ipairs(entries) do
        if entry.mapID then
            held = held + 1
        end
    end

    frame.caption:SetText(
        Count(held, "key") .. " · resets weekly with your realm"
        .. (SYL.Features.IsEnabled("keystoneSharing")
            and "" or " · sharing off, so this is only your characters")
    )
end

KeysPanel.Refresh = Refresh

function KeysPanel.SetSort(key, reversed)
    sortKey, sortReversed = key, reversed

    Refresh()
end

function KeysPanel.SetRole(role)
    askRole = SYL.KeystoneRequests.ROLE_LABELS[role] and role or "DPS"

    Refresh()
end

function KeysPanel.SetView(next)
    view = (next == "lockouts") and "lockouts" or "keys"

    Refresh()
end

function KeysPanel.ToggleView()
    KeysPanel.SetView(view == "keys" and "lockouts" or "keys")
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function KeysPanel.Create(parent)
    -- Before anything is anchored: rows and headings both read column.x and
    -- column.width, and neither exists until this has run.
    SYL.KeyRows.Measure()

    frame = CreateFrame("Frame", nil, parent)

    -- After the frame exists, because the rows hang off it. Rows are built
    -- lazily on the first draw, so this only has to be ready before Refresh.
    rowConfig = {
        parent = frame,
        rowHeight = ROW_HEIGHT,
        listTop = LIST_TOP,
        width = LIST_WIDTH,
        getRole = function() return askRole end,
        onChanged = function() Refresh() end,
    }

    frame:SetPoint("TOPLEFT", 16, -100)
    frame:SetPoint("BOTTOMRIGHT", -16, 52)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText("MYTHIC+ KEYS")

    -- One role for the whole panel rather than a picker per row: the answer is
    -- the same for every key you ask about in a sitting, and a menu per row is
    -- three clicks where this is none.
    frame.roleButton = Theme.CreateButton(frame, 90, 20, "DPS", function()
        local roles = SYL.KeystoneRequests.ROLES

        for index, role in ipairs(roles) do
            if role == askRole then
                KeysPanel.SetRole(roles[(index % #roles) + 1])

                return
            end
        end

        KeysPanel.SetRole(roles[1])
    end)

    frame.roleButton:SetPoint("TOPLEFT", title, "TOPRIGHT", 14, -2)

    SYL.Tooltips.Attach(
        frame.roleButton,
        "What you would come as",
        "Sent with every request you make from this screen, so the person "
        .. "with the key knows whether you fill a hole they still have."
    )

    frame.badge = Theme.CreateText(frame, Theme.sizes.rowSmall, "warning")
    frame.badge:SetPoint("LEFT", frame.roleButton, "RIGHT", 12, 0)

    -- The second view. Keys is what the tab is named after, so it stays the
    -- one that opens.
    frame.viewButton = Theme.CreateButton(frame, 90, 20, "Lockouts", function()
        KeysPanel.ToggleView()
    end)

    frame.viewButton:SetPoint("TOPRIGHT", -4, -2)

    SYL.Tooltips.Attach(
        frame.viewButton,
        "Mythic 0 lockouts",
        "Which of your characters is saved to which dungeon this season. "
        .. "Mythic+ has no lockout; Mythic 0 resets weekly during a patch week "
        .. "and daily once the season is open."
    )

    -- The pane joins this after it is built, a few lines down. Listing it here
    -- would put a nil in the table and hide nothing.
    frame.keysWidgets = { frame.roleButton, frame.badge }

    -- ONE PATH FOR EVERY COLUMN, sortable or not.
    --
    -- There were two, and they placed their text differently. A sortable
    -- header is a button whose label fills it, so the glyphs sit centered
    -- inside 18px; RESPONSE took the other branch and was a bare font string
    -- anchored TOPLEFT with no height at all. Same anchor, different box, and
    -- the one heading nobody can sort by rode a few pixels above the other
    -- three for as long as the column has existed.
    --
    -- A column that cannot be sorted is the same header with its mouse
    -- switched off. UI/SortHeader.lua has always known that (see its own note
    -- on why a non-sortable header must still be drawn); this file was written
    -- before it and never caught up.
    for _, column in ipairs(COLUMNS) do
        if column.label ~= "" then
            local button = CreateFrame("Button", nil, frame)

            table.insert(frame.keysWidgets, button)

            button:SetPoint("TOPLEFT", column.x, -HEADER_TOP)
            button:SetSize(column.width, HEADER_HEIGHT)

            local label =
                Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

            label:SetAllPoints()
            label:SetJustifyH(column.justify)
            label:SetText(column.label)

            if column.sortable == false then
                button:EnableMouse(false)
            else
                button:SetScript("OnClick", function()
                    if sortKey == column.key then
                        KeysPanel.SetSort(column.key, not sortReversed)
                    else
                        KeysPanel.SetSort(column.key, false)
                    end
                end)
            end
        end
    end

    frame.pane = SYL.KeyRequestList.Create(frame, PANE_WIDTH, HEADER_TOP - 8)

    table.insert(frame.keysWidgets, frame.pane)

    frame.grid = SYL.LockoutsGrid.Create(frame)

    frame.empty = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.empty:SetPoint("TOPLEFT", 2, -(LIST_TOP + 6))
    frame.empty:SetWidth(LIST_WIDTH)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWordWrap(true)
    frame.empty:Hide()

    frame.caption = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 2, 2)
    frame.caption:SetWidth(LIST_WIDTH)
    frame.caption:SetJustifyH("LEFT")

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(Build()) - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)

    frame:Hide()

    return frame
end
