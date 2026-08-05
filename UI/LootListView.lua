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

local function FillLootRow(row, record, recordIndex)
    row.numberText:SetText(recordIndex .. ".")
    row.playerText:SetText(record.recipient or "Unknown")

    row.itemText:SetText(
        record.itemLink
        or record.itemName
        or "Unknown item"
    )

    row.locationText:SetText(FormatLocation(record))
    row.dateText:SetText(Utilities.FormatDateTime(record.timestamp))

    Widgets.SetItemLink(row.itemButton, record.itemLink)
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

    view.countText:SetText("Recorded items: " .. totalRecords)

    SetEmptyState(
        view,
        totalRecords == 0,
        "No loot has been recorded in this view."
    )

    local maxOffset = math.max(0, totalRecords - view.visibleRows)

    if view.offset > maxOffset then
        view.offset = maxOffset
    end

    -- Rows read newest first, so row 1 shows the most recent record.
    for rowIndex = 1, view.visibleRows do
        local recordIndex =
            totalRecords - view.offset - rowIndex + 1

        local row = view.lootRows[rowIndex]

        if recordIndex >= 1 then
            FillLootRow(row, records[recordIndex], recordIndex)
            row:Show()
        else
            row.itemButton.itemLink = nil
            row:Hide()
        end
    end

    UpdateScrollRange(view, maxOffset, totalRecords)
end

function LootListView.UpdateArchiveRows(view)
    local archives = SYL.GetArchives()
    local totalArchives = #archives

    view.countText:SetText("Archived seasons: " .. totalArchives)

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

            row.viewButton.archiveIndex = index

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
