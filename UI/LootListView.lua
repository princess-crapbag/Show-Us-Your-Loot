-- UI/LootListView.lua
--
-- Renders drop rows, chat-loot rows and archive rows into an already-built
-- window. The window passes its own state in as `view`, so this file holds no
-- state of its own and can later be reused by a second window.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets
local Rows = SYL.Rows
local ListSources = SYL.ListSources
local Selection = SYL.Selection
local Utilities = SYL.Utilities

-- Every row carries the record it is showing and that record's place in the
-- displayed list, because pooled rows are reused as the list scrolls and a
-- shift-click range needs the on-screen index.
local function BindRow(view, row, record, recordIndex)
    row.record = record
    row.recordIndex = recordIndex

    Rows.SetRowSelected(row, Selection.IsSelected(view.selection, record))
    Rows.SetRowHidden(row, record.hidden)
end

local function ReleaseRow(row)
    row.record = nil
    row.recordIndex = nil
    row.itemLink = nil

    row:Hide()
end

local LootListView = {}
SYL.LootListView = LootListView

local CACHE_RETRY_SECONDS = 0.6

local retryScheduled = false

-- Item quality and icon come from the client cache, which may not hold an
-- item this character has never seen. One delayed refresh lets the cache fill
-- rather than leaving uncoloured names on screen.
local function ScheduleCacheRetry()
    if retryScheduled then
        return
    end

    retryScheduled = true

    C_Timer.After(CACHE_RETRY_SECONDS, function()
        retryScheduled = false

        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end)
end

local DIFFICULTY_SHORT = {
    [14] = "N",
    [15] = "HC",
    [16] = "M",
    [17] = "LFR",
}

local function AbbreviateDifficulty(record)
    local short = DIFFICULTY_SHORT[record.difficultyID]

    if short then
        return short
    end

    local name = record.difficultyName

    if name and name ~= "" and name ~= "None" then
        return name
    end

    return nil
end

--------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------

local function FormatLocation(record)
    local instanceName =
        record.instanceName
        or record.zoneName
        or "Unknown"

    local difficultyName = record.difficultyName

    if difficultyName
        and difficultyName ~= ""
        and difficultyName ~= "None"
    then
        return instanceName .. " - " .. difficultyName
    end

    return instanceName
end

local function SetEmptyState(view, isEmpty, message)
    if isEmpty then
        view.emptyText:SetText(message)
        view.emptyText:Show()
    else
        view.emptyText:Hide()
    end
end

local function DescribeCount(view, shown, singular, plural)
    local total = #ListSources.GetUnfiltered(view)

    if shown == total then
        return shown .. " " .. (shown == 1 and singular or plural)
    end

    return shown .. " of " .. total .. " " .. plural
end

local function ClampOffset(view, total)
    local maxOffset =
        math.max(0, total - SYL.ScrollArea.VisibleRows(view))

    if view.offset > maxOffset then
        view.offset = maxOffset
    end

    return maxOffset
end

local function UpdateScrollRange(view, maxOffset, total)
    local rowHeight = SYL.ScrollArea.RowHeight(view)
    local visibleRows = SYL.ScrollArea.VisibleRows(view)

    view.scrollChild:SetHeight(
        math.max(visibleRows * rowHeight, total * rowHeight)
    )

    view.scrollFrame:SetVerticalScroll(view.offset * rowHeight)

    if view.scrollFrame.ScrollBar then
        view.scrollFrame.ScrollBar:SetMinMaxValues(0, maxOffset * rowHeight)
        view.scrollFrame.ScrollBar:SetValue(view.offset * rowHeight)
    end
end

--------------------------------------------------------------------------
-- Drops
--------------------------------------------------------------------------

-- A win type is not decoration: a transmog win is not an upgrade, so it is
-- muted rather than shown with the same weight as a Need win.
local function SetWinType(row, record)
    local short = SYL.LootHistoryAPI.ShortRollState(record.winnerState)

    row.typeText:SetText(short or "")

    if record.winnerState == 0 or record.winnerState == 1 then
        Theme.SetTextColor(row.typeText, "textPrimary")
    else
        Theme.SetTextColor(row.typeText, "textMuted")
    end
end

local function FillDropRow(row, record, recordIndex)
    row.numberText:SetText(recordIndex)

    local difficulty = AbbreviateDifficulty(record)

    row.bossText:SetText(
        tostring(record.encounterName or "Unknown boss")
        .. (difficulty and ("  " .. difficulty) or "")
    )

    if record.allPassed then
        row.winnerText:SetText("all passed")
        Theme.SetTextColor(row.winnerText, "textMuted")
        row.rollText:SetText("")
        row.typeText:SetText("")
    else
        row.winnerText:SetText(tostring(record.winnerName or "Unknown"))

        local classColor = Theme.GetClassColor(record.winnerClass)

        if classColor then
            row.winnerText:SetTextColor(
                classColor[1], classColor[2], classColor[3]
            )
        else
            Theme.SetTextColor(row.winnerText, "textPrimary")
        end

        row.rollText:SetText(
            record.winnerRoll and tostring(record.winnerRoll) or "—"
        )

        SetWinType(row, record)
    end

    row.dateText:SetText(Utilities.FormatDateTime(record.timestamp))

    return Rows.SetRowItem(row, record.itemLink, record.itemName)
end

function LootListView.UpdateDropRows(view)
    local records = ListSources.GetFiltered(view)
    local total = #records

    view.countText:SetText(DescribeCount(view, total, "drop", "drops"))

    SetEmptyState(
        view,
        total == 0,
        ListSources.IsFiltering(view)
            and "No drops match these filters."
            or "No drops recorded yet. They are captured on group-loot rolls."
    )

    local maxOffset = ClampOffset(view, total)
    local allCached = true

    for rowIndex = 1, view.visibleRows do
        local recordIndex = total - view.offset - rowIndex + 1
        local row = view.dropRows[rowIndex]

        if recordIndex >= 1 then
            local record = records[recordIndex]

            if not FillDropRow(row, record, recordIndex) then
                allCached = false
            end

            BindRow(view, row, record, recordIndex)

            row:Show()
        else
            ReleaseRow(row)
        end
    end

    if not allCached then
        ScheduleCacheRetry()
    end

    UpdateScrollRange(view, maxOffset, total)
end

--------------------------------------------------------------------------
-- Chat loot
--------------------------------------------------------------------------

local function FillLootRow(row, record, recordIndex)
    row.numberText:SetText(recordIndex)
    row.playerText:SetText(record.recipient or "Unknown")
    row.locationText:SetText(FormatLocation(record))
    row.dateText:SetText(Utilities.FormatDateTime(record.timestamp))

    return Rows.SetRowItem(row, record.itemLink, record.itemName)
end

function LootListView.UpdateLootRows(view)
    local records = ListSources.GetFiltered(view)
    local total = #records

    view.countText:SetText(DescribeCount(view, total, "item", "items"))

    SetEmptyState(
        view,
        total == 0,
        ListSources.IsFiltering(view)
            and "No loot matches these filters."
            or "No loot has been recorded in this view."
    )

    local maxOffset = ClampOffset(view, total)
    local allCached = true

    -- Rows read newest first, so row 1 shows the most recent record.
    for rowIndex = 1, view.visibleRows do
        local recordIndex = total - view.offset - rowIndex + 1
        local row = view.lootRows[rowIndex]

        if recordIndex >= 1 then
            local record = records[recordIndex]

            if not FillLootRow(row, record, recordIndex) then
                allCached = false
            end

            BindRow(view, row, record, recordIndex)

            row:Show()
        else
            ReleaseRow(row)
        end
    end

    if not allCached then
        ScheduleCacheRetry()
    end

    UpdateScrollRange(view, maxOffset, total)
end

--------------------------------------------------------------------------
-- Archives
--------------------------------------------------------------------------

function LootListView.UpdateArchiveRows(view)
    local archives = SYL.GetArchives()
    local total = #archives

    view.countText:SetText(
        total .. (total == 1 and " archived season" or " archived seasons")
    )

    SetEmptyState(view, total == 0, "No seasons have been archived.")

    local maxOffset = ClampOffset(view, total)
    local visibleRows = SYL.ScrollArea.VisibleRows(view)

    for rowIndex = 1, visibleRows do
        local row = view.archiveRows[rowIndex]
        local archiveIndex = rowIndex + view.offset
        local season = archives[archiveIndex]

        if season then
            row.nameText:SetText(season.name or "Unnamed Season")

            row.countText:SetText(
                #(season.drops or {})
                .. " drops, "
                .. #(season.loot or {})
                .. " items"
            )

            row.dateText:SetText(
                "Archived "
                .. Utilities.FormatDateOnly(
                    season.archivedAt or season.startedAt or time()
                )
            )

            row.archiveIndex = archiveIndex

            row:Show()
        else
            row:Hide()
        end
    end

    UpdateScrollRange(view, maxOffset, total)
end

function LootListView.HideAllRows(view)
    for _, row in ipairs(view.dropRows) do
        row:Hide()
    end

    for _, row in ipairs(view.lootRows) do
        row:Hide()
    end

    for _, row in ipairs(view.archiveRows) do
        row:Hide()
    end
end

-- Kept so callers do not need to know about ListSources.
function LootListView.GetRecords(view)
    return ListSources.GetFiltered(view)
end
