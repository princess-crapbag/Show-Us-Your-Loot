-- UI/LootListView.lua
--
-- Renders loot rows and archive rows into an already-built window. The window
-- passes its own state in as `view`, so this file holds no state of its own
-- and can later be reused by a second window.

local SYL = _G.ShowUsYourLoot
local Widgets = SYL.Widgets
local Utilities = SYL.Utilities

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

function LootListView.GetRecords(view)
    if view.mode == "active" then
        local season = SYL.GetActiveSeason()

        return season and season.loot or {}
    end

    if view.mode == "all" then
        return SYL.GetAllLoot()
    end

    if view.mode == "archive" then
        local season = SYL.GetArchives()[view.selectedArchiveIndex]

        return season and season.loot or {}
    end

    return {}
end

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

-- Returns false when the item was not cached, so the caller can retry.
local function FillLootRow(row, record, recordIndex)
    row.numberText:SetText(recordIndex)
    row.playerText:SetText(record.recipient or "Unknown")
    row.locationText:SetText(FormatLocation(record))
    row.dateText:SetText(Utilities.FormatDateTime(record.timestamp))

    return Widgets.SetRowItem(row, record.itemLink, record.itemName)
end

local function UpdateScrollRange(view, maxOffset, totalRecords)
    local rowHeight = Widgets.ROW_HEIGHT

    view.scrollChild:SetHeight(
        math.max(
            view.visibleRows * rowHeight,
            totalRecords * rowHeight
        )
    )

    view.scrollFrame:SetVerticalScroll(view.offset * rowHeight)

    if view.scrollFrame.ScrollBar then
        view.scrollFrame.ScrollBar:SetMinMaxValues(0, maxOffset * rowHeight)
        view.scrollFrame.ScrollBar:SetValue(view.offset * rowHeight)
    end
end

function LootListView.UpdateLootRows(view)
    local records = LootListView.GetRecords(view)
    local totalRecords = #records

    view.countText:SetText(totalRecords .. " items")

    SetEmptyState(
        view,
        totalRecords == 0,
        "No loot has been recorded in this view."
    )

    local maxOffset = math.max(0, totalRecords - view.visibleRows)

    if view.offset > maxOffset then
        view.offset = maxOffset
    end

    local allCached = true

    -- Rows read newest first, so row 1 shows the most recent record.
    for rowIndex = 1, view.visibleRows do
        local recordIndex =
            totalRecords - view.offset - rowIndex + 1

        local row = view.lootRows[rowIndex]

        if recordIndex >= 1 then
            if not FillLootRow(row, records[recordIndex], recordIndex) then
                allCached = false
            end

            row:Show()
        else
            row.itemLink = nil
            row:Hide()
        end
    end

    if not allCached then
        ScheduleCacheRetry()
    end

    UpdateScrollRange(view, maxOffset, totalRecords)
end

function LootListView.UpdateArchiveRows(view)
    local archives = SYL.GetArchives()
    local totalArchives = #archives

    view.countText:SetText(totalArchives .. " archived seasons")

    SetEmptyState(
        view,
        totalArchives == 0,
        "No seasons have been archived."
    )

    for index = 1, view.visibleRows do
        local row = view.archiveRows[index]
        local season = archives[index]

        if season then
            row.nameText:SetText(season.name or "Unnamed Season")
            row.countText:SetText(#(season.loot or {}) .. " items")

            row.dateText:SetText(
                "Archived "
                .. Utilities.FormatDateOnly(
                    season.archivedAt or season.startedAt or time()
                )
            )

            row.archiveIndex = index

            row:Show()
        else
            row:Hide()
        end
    end

    view.scrollChild:SetHeight(
        view.visibleRows * Widgets.ARCHIVE_ROW_HEIGHT
    )

    view.scrollFrame:SetVerticalScroll(0)

    if view.scrollFrame.ScrollBar then
        view.scrollFrame.ScrollBar:SetMinMaxValues(0, 0)
        view.scrollFrame.ScrollBar:SetValue(0)
    end
end

function LootListView.HideAllRows(view)
    for _, row in ipairs(view.lootRows) do
        row:Hide()
    end

    for _, row in ipairs(view.archiveRows) do
        row:Hide()
    end
end
