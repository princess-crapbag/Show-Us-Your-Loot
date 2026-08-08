-- UI/LootListView.lua
--
-- Renders the merged loot list and the archive list into an already-built
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
    -- Joined entries keep hidden on the record underneath.
    Rows.SetRowHidden(row, (record.record or record).hidden)
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

--------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------

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

    local text

    if shown == total then
        text = shown .. " " .. (shown == 1 and singular or plural)
    else
        text = shown .. " of " .. total .. " " .. plural
    end

    -- Said out loud, because a hidden row leaves no trace otherwise. The
    -- count drops by one and the row disappears into a list that may hold
    -- several more copies of the same item, which reads as the button having
    -- done nothing.
    local hidden = ListSources.CountHiddenInScope(view)

    if hidden > 0 then
        text = text .. "  ·  " .. hidden .. " hidden"
    end

    return text
end

local function ClampOffset(view, total)
    local maxOffset =
        math.max(0, total - SYL.ScrollArea.VisibleRows(view))

    if view.offset > maxOffset then
        view.offset = maxOffset
    end

    return maxOffset
end

-- The child is sized so that scrolling it to the bottom lands exactly on
-- maxOffset, rather than from the total number of rows.
--
-- WoW clamps a scroll to `childHeight - frameHeight`, so with a child of
-- `total * rowHeight` the last offset is only reachable when the rows divide
-- the viewport evenly. Loot rows do — 13 x 28 is exactly 364 — and archive
-- rows do not, which left the oldest season unreachable by a few pixels.
local function UpdateScrollRange(view, maxOffset, total)
    local rowHeight = SYL.ScrollArea.RowHeight(view)

    -- Falls back to the row count if the frame has not been laid out yet. A
    -- height of zero here would size the child short and clip the last rows,
    -- which is a hard fault to trace back to a first-draw ordering problem.
    local viewportHeight = view.scrollFrame:GetHeight()

    if not viewportHeight or viewportHeight <= 0 then
        viewportHeight = SYL.ScrollArea.VisibleRows(view) * rowHeight
    end

    view.scrollChild:SetHeight(maxOffset * rowHeight + viewportHeight)

    view.scrollFrame:SetVerticalScroll(view.offset * rowHeight)

    if view.scrollFrame.ScrollBar then
        view.scrollFrame.ScrollBar:SetMinMaxValues(0, maxOffset * rowHeight)
        view.scrollFrame.ScrollBar:SetValue(view.offset * rowHeight)
    end
end

--------------------------------------------------------------------------
-- The merged list
--------------------------------------------------------------------------

-- A win type is not decoration: a transmog win is not an upgrade, so it is
-- muted rather than shown with the same weight as a Need win. Awarded items
-- are muted for a different reason — nobody chose anything.
local STRONG_TYPES = { need = true, offspec = true }

local function FillFeedRow(row, entry, index)
    row.numberText:SetText(index)
    row.playerText:SetText(entry.player or "Unknown")

    local classColor = entry.drop
        and Theme.GetClassColor(entry.drop.winnerClass)

    if classColor then
        Theme.SetCustomTextColor(
            row.playerText, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(row.playerText, "textPrimary")
    end

    row.typeText:SetText(entry.typeLabel or "")

    Theme.SetTextColor(
        row.typeText,
        STRONG_TYPES[entry.typeKey] and "textPrimary" or "textMuted"
    )

    row.locationText:SetText(entry.where or "")
    row.dateText:SetText(Utilities.FormatDateCompact(entry.timestamp))

    return Rows.SetRowItem(row, entry.itemLink, entry.itemName)
end

function LootListView.UpdateFeedRows(view)
    local entries = ListSources.GetFiltered(view)
    local total = #entries

    view.countText:SetText(DescribeCount(view, total, "item", "items"))

    SetEmptyState(
        view,
        total == 0,
        ListSources.IsFiltering(view)
            and "Nothing matches these filters."
            or "No loot recorded yet."
    )

    local maxOffset = ClampOffset(view, total)
    local allCached = true

    for rowIndex = 1, view.visibleRows do
        local entryIndex = total - view.offset - rowIndex + 1
        local row = view.feedRows[rowIndex]

        Widgets.AnchorRow(row, view.offset + rowIndex, Widgets.ROW_HEIGHT)

        if entryIndex >= 1 then
            local entry = entries[entryIndex]

            if not FillFeedRow(row, entry, entryIndex) then
                allCached = false
            end

            BindRow(view, row, entry, entryIndex)

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

        Widgets.AnchorRow(
            row, archiveIndex, Widgets.ARCHIVE_ROW_HEIGHT
        )

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
    for _, row in ipairs(view.feedRows) do
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
