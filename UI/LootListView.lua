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

    -- Joined entries keep both flags on the record underneath.
    local underlying = record.record or record

    Rows.SetRowHidden(row, underlying.hidden)

    -- After the type cell has been filled, since it overwrites it.
    Rows.SetRowIgnored(row, underlying.excludedFromAnalytics)
end

local function ReleaseRow(row)
    row.record = nil
    row.recordIndex = nil
    row.itemLink = nil

    row:Hide()
end

local LootListView = {}
SYL.LootListView = LootListView

-- Item quality and icon come from the client cache, which may not hold an
-- item this character has never seen.
--
-- This used to re-draw the whole list every 0.6 seconds until everything
-- resolved, which is a poll for an answer the client volunteers. Two things
-- were wrong with it: a full season's list was rebuilt twice a second while
-- the window sat open, and an item the server never answers for — a removed
-- id, a failed request — kept it going forever.
--
-- GET_ITEM_INFO_RECEIVED fires when the cache fills. Registered only while
-- something on screen is actually waiting, and dropped again the moment
-- nothing is, so an idle window listens to nothing.
local BURST_SECONDS = 0.1

local cacheWatcher
local refreshPending = false

local function StopWatchingItemCache()
    if cacheWatcher then
        cacheWatcher:UnregisterAllEvents()
    end
end

local function WatchItemCache()
    if not cacheWatcher then
        cacheWatcher = CreateFrame("Frame")

        cacheWatcher:SetScript("OnEvent", function()
            -- A boss's worth of items resolve in one burst, and each would
            -- otherwise redraw the list on its own.
            if refreshPending then
                return
            end

            refreshPending = true

            C_Timer.After(BURST_SECONDS, function()
                refreshPending = false

                if SYL.RefreshMainWindow then
                    SYL:RefreshMainWindow()
                end
            end)
        end)
    end

    cacheWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
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

local function CountIgnored(entries)
    local ignored = 0

    for _, entry in ipairs(entries) do
        if (entry.record or entry).excludedFromAnalytics then
            ignored = ignored + 1
        end
    end

    return ignored
end

local function DescribeCount(view, shown, singular, plural, entries)
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

    -- Said for the same reason as hidden, and it matters more: an ignored
    -- record is still on screen and is no longer in any number, so the list
    -- and the due list disagree by exactly this many.
    local ignored = CountIgnored(entries or {})

    if ignored > 0 then
        text = text .. "  ·  " .. ignored .. " ignored"
    end

    -- On the same line as the other counts rather than in a label of its own.
    --
    -- There was one, anchored to the left edge of Select all — which is where
    -- this sentence ends. A long summary and a two-digit selection drew over
    -- each other, so the number people needed most was the one most likely to
    -- be unreadable. It also disappeared entirely at zero, which is the state
    -- somebody checks when they are asking "did my click register".
    local selected = view.selection and view.selection.count or 0

    if selected > 0 then
        text = text .. "  ·  " .. selected .. " selected"
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

-- Why the list is empty, not just that it is.
--
-- It said "No loot recorded yet" for every empty list, including the four
-- that are empty because of something the user just pressed. Worse, on a
-- fresh install it is the first thing anybody sees, and it reads as "this is
-- not working" — because the one fact that would explain it is nowhere in
-- the addon: history starts at install. Nothing that dropped before then can
-- ever appear, and no amount of waiting will change that.
local function EmptyMessage(view)
    if ListSources.IsFiltering(view) then
        return "Nothing matches these filters."
    end

    if view.showHidden then
        return "Nothing has been hidden. Tick a row and press Hide to set it "
            .. "aside without deleting it."
    end

    if view.gearOnly then
        return "No gear recorded yet. Gear only hides reagents, gold and "
            .. "quest items — press it again to see everything."
    end

    if view.contentScope == "raid" then
        return "Nothing recorded from a raid yet."
    end

    if view.contentScope == "dungeon" then
        return "Nothing recorded from a dungeon yet. Dungeon gear is "
            .. "personal loot, so it arrives without a roll."
    end

    return "Nothing recorded yet.\n\nRecording starts when the addon is "
        .. "installed — it cannot see loot from before that. Run a boss and "
        .. "it will fill in."
end

function LootListView.UpdateFeedRows(view)
    local entries = ListSources.GetFiltered(view)
    local total = #entries

    view.countText:SetText(
        DescribeCount(view, total, "item", "items", entries)
    )

    SetEmptyState(view, total == 0, EmptyMessage(view))

    local maxOffset = ClampOffset(view, total)
    local allCached = true

    -- Drawn forwards now. The list used to be built oldest-first and read
    -- backwards to show the newest at the top, which worked exactly as long
    -- as there was only ever one order. A sortable header needs the array to
    -- already be in the order it is displayed in, so the reversal moved into
    -- LootFeed.Sort where the direction is a comparator rather than a
    -- subtraction.
    for rowIndex = 1, view.visibleRows do
        local entryIndex = view.offset + rowIndex
        local row = view.feedRows[rowIndex]

        Widgets.AnchorRow(row, entryIndex, Widgets.ROW_HEIGHT)

        if entryIndex <= total then
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

    if allCached then
        StopWatchingItemCache()
    else
        WatchItemCache()
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
