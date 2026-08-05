-- UI/ScrollArea.lua
--
-- The scrolling list region: the scroll frame, the pooled rows for each view,
-- and the wheel and scrollbar plumbing.
--
-- Rows are created once and reused. The window owns `view`; this fills in the
-- frame references and leaves rendering to UI/LootListView.lua.
--
-- Archive rows are taller than loot rows, so row height and the number of
-- visible rows are both read per mode rather than assumed.

local SYL = _G.ShowUsYourLoot
local Widgets = SYL.Widgets
local Rows = SYL.Rows
local ListSources = SYL.ListSources

local ScrollArea = {}
SYL.ScrollArea = ScrollArea

local TOP_INSET = 180
local BOTTOM_INSET = 52

function ScrollArea.RowHeight(view)
    if view.mode == "archives" then
        return Widgets.ARCHIVE_ROW_HEIGHT
    end

    return Widgets.ROW_HEIGHT
end

function ScrollArea.VisibleRows(view)
    if view.mode == "archives" then
        return view.archiveVisibleRows
    end

    return view.visibleRows
end

local function TotalCount(view)
    if view.mode == "archives" then
        return #SYL.GetArchives()
    end

    return #ListSources.GetFiltered(view)
end

local function MaxOffset(view)
    return math.max(0, TotalCount(view) - ScrollArea.VisibleRows(view))
end

local function AttachScrollHandlers(view, onScrolled)
    view.scrollFrame:EnableMouseWheel(true)

    view.scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        view.offset = math.max(
            0,
            math.min(MaxOffset(view), view.offset - delta)
        )

        onScrolled()
    end)

    if not view.scrollFrame.ScrollBar then
        return
    end

    view.scrollFrame.ScrollBar:SetScript("OnValueChanged", function(_, value)
        local newOffset =
            math.floor((value / ScrollArea.RowHeight(view)) + 0.5)

        -- Rendering sets the scrollbar, which fires this again; the guard
        -- stops that turning into a loop.
        if newOffset ~= view.offset then
            view.offset = newOffset

            onScrolled()
        end
    end)
end

function ScrollArea.Create(parent, view, config)
    local availableHeight =
        config.windowHeight - TOP_INSET - BOTTOM_INSET

    -- Only as many archive rows as actually fit. Creating a loot row's worth
    -- of them left the last few permanently off-screen.
    view.archiveVisibleRows =
        math.floor(availableHeight / Widgets.ARCHIVE_ROW_HEIGHT)

    view.scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )

    view.scrollFrame:SetPoint("TOPLEFT", 16, -TOP_INSET)
    view.scrollFrame:SetPoint("BOTTOMRIGHT", -34, BOTTOM_INSET)

    view.scrollChild = CreateFrame("Frame", nil, view.scrollFrame)
    view.scrollChild:SetWidth(config.childWidth)
    view.scrollChild:SetHeight(view.visibleRows * Widgets.ROW_HEIGHT)

    view.scrollFrame:SetScrollChild(view.scrollChild)

    for index = 1, view.visibleRows do
        view.dropRows[index] = Rows.CreateDropRow(
            view.scrollChild, index, config.onSelect, config.onActivate
        )

        view.lootRows[index] =
            Rows.CreateLootRow(view.scrollChild, index, config.onSelect)
    end

    for index = 1, view.archiveVisibleRows do
        view.archiveRows[index] =
            Rows.CreateArchiveRow(view.scrollChild, index, config.onArchiveView)
    end

    AttachScrollHandlers(view, config.onScrolled)

    return view.scrollFrame
end
