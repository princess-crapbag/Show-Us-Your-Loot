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

local KeysPanel = {}
SYL.KeysPanel = KeysPanel

local PANE_WIDTH = 300
local GUTTER = 12
local LIST_WIDTH = 868 - PANE_WIDTH - GUTTER

local ROW_HEIGHT = 20
local HEADER_TOP = 34
local LIST_TOP = 58
local VISIBLE_ROWS = 15

local COLUMNS = {
    { key = "name", label = "PLAYER", x = 4, width = 150 },
    { key = "dungeon", label = "DUNGEON", x = 158, width = 210 },
    { key = "level", label = "LVL", x = 372, width = 40 },
    { key = "ask", label = "", x = 420, width = 120, sortable = false },
}

local frame
local rows = {}
local offset = 0
local sortKey, sortReversed = "level", false
local askRole = "DPS"
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
        table.insert(entries, {
            name = own.characterKey or own.name,
            mapID = own.mapID,
            level = own.level,
            class = own.class,
            isOwn = true,
        })
    end

    if SYL.KeystoneSync.IsEnabled() then
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
-- Rows
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, frame)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetWidth(LIST_WIDTH)

    if index % 2 == 0 then
        local stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        stripe:SetAllPoints()
    end

    row.cells = {}

    for _, column in ipairs(COLUMNS) do
        if column.key ~= "ask" then
            local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

            text:SetPoint("LEFT", column.x, 0)
            text:SetWidth(column.width)
            text:SetJustifyH(column.key == "level" and "RIGHT" or "LEFT")
            text:SetWordWrap(false)

            row.cells[column.key] = text
        end
    end

    row.ask = Theme.CreateButton(row, 110, 17, "Ask", function()
        if not row.playerName then
            return
        end

        local ok, reason = SYL.KeystoneRequests.Ask(row.playerName, askRole)

        SYL:Write(ok
            and ("Asked " .. row.playerName .. " to run their key as "
                .. (SYL.KeystoneRequests.ROLE_LABELS[askRole] or askRole) .. ".")
            or (reason or "Could not ask."))

        Refresh()
    end)

    row.ask:SetPoint("LEFT", COLUMNS[4].x, 0)

    rows[index] = row

    return row
end

-- The button says what will happen, or why it will not. A greyed button with
-- no explanation is the thing this is avoiding: "offline" and "you already
-- asked" are different problems and only one of them is worth waiting on.
local function DrawAsk(row, entry)
    if entry.isOwn then
        row.ask:Hide()

        return
    end

    local existing = SYL.KeystoneRequests.GetOutgoing(entry.name)

    if existing and existing.status ~= SYL.KeystoneRequests.STATUS.DENIED then
        row.ask:Hide()

        row.cells.level:SetText(
            (entry.level or "?") .. "  "
            .. (SYL.KeystoneRequests.STATUS_LABELS[existing.status] or "")
        )

        return
    end

    local allowed, reason = SYL.KeystoneRequests.CanAsk(entry.name)

    row.ask.label:SetText(existing and "Ask again" or "Ask")
    row.ask:Show()

    -- Left clickable either way so the tooltip can be read; the click prints
    -- the reason rather than doing nothing.
    Theme.SetTextColor(row.ask.label, allowed and "textPrimary" or "textMuted")

    SYL.Tooltips.Attach(
        row.ask,
        allowed and "Ask for this key" or "Cannot ask",
        allowed
            and ("Sends a request to " .. entry.name .. " as "
                .. (SYL.KeystoneRequests.ROLE_LABELS[askRole] or askRole)
                .. ". Only they see it.")
            or (reason or "")
    )
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

Refresh = function()
    if not frame then
        return
    end

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
            SYL.KeystoneSync.IsEnabled()
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
            local row = rows[index] or CreateRow(index)

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

                DrawAsk(row, entry)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    SYL.KeyRequestList.Refresh(frame.pane)

    frame.caption:SetText(
        #entries .. " keys · resets " .. (SYL.KeystoneSync.IsEnabled()
            and "weekly, with your realm" or "weekly")
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

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function KeysPanel.Create(parent)
    frame = CreateFrame("Frame", nil, parent)

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

    -- Column headers, clickable to sort.
    for _, column in ipairs(COLUMNS) do
        if column.sortable ~= false then
            local button = CreateFrame("Button", nil, frame)

            button:SetPoint("TOPLEFT", column.x, -HEADER_TOP)
            button:SetSize(column.width, 18)

            local label =
                Theme.CreateText(button, Theme.sizes.columnHeader, "textMuted")

            label:SetAllPoints()
            label:SetJustifyH(column.key == "level" and "RIGHT" or "LEFT")
            label:SetText(column.label)

            button:SetScript("OnClick", function()
                if sortKey == column.key then
                    KeysPanel.SetSort(column.key, not sortReversed)
                else
                    KeysPanel.SetSort(column.key, false)
                end
            end)
        end
    end

    frame.pane = SYL.KeyRequestList.Create(frame, PANE_WIDTH, HEADER_TOP - 8)

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
