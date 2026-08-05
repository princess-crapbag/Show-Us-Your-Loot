-- UI/ScrollArea.lua
--
-- The scrolling list region: the scroll frame, the pooled rows for each view,
-- and the wheel and scrollbar plumbing.
--
-- Rows are created once and reused. The window owns `view`; this fills in the
-- frame references and leaves rendering to UI/LootListView.lua.

local SYL = _G.ShowUsYourLoot
local Widgets = SYL.Widgets
local Rows = SYL.Rows
local ListSources = SYL.ListSources

local ScrollArea = {}
SYL.ScrollArea = ScrollArea

local function MaxOffset(view)
    return math.max(0, #ListSources.GetFiltered(view) - view.visibleRows)
end

local function AttachScrollHandlers(view, onScrolled)
    view.scrollFrame:EnableMouseWheel(true)

    view.scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        -- The archive list is short and fixed, so it does not scroll.
        if view.mode == "archives" then
            return
        end

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
        if view.mode == "archives" then
            return
        end

        local newOffset =
            math.floor((value / Widgets.ROW_HEIGHT) + 0.5)

        -- Rendering sets the scrollbar, which fires this again; the guard
        -- stops that turning into a loop.
        if newOffset ~= view.offset then
            view.offset = newOffset

            onScrolled()
        end
    end)
end

function ScrollArea.Create(parent, view, config)
    view.scrollFrame = CreateFrame(
        "ScrollFrame",
        "ShowUsYourLootScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )

    view.scrollFrame:SetPoint("TOPLEFT", 16, -180)
    view.scrollFrame:SetPoint("BOTTOMRIGHT", -34, 52)

    view.scrollChild = CreateFrame("Frame", nil, view.scrollFrame)
    view.scrollChild:SetWidth(config.childWidth)
    view.scrollChild:SetHeight(view.visibleRows * Widgets.ROW_HEIGHT)

    view.scrollFrame:SetScrollChild(view.scrollChild)

    for index = 1, view.visibleRows do
        view.dropRows[index] =
            Rows.CreateDropRow(view.scrollChild, index, config.onSelect)

        view.lootRows[index] =
            Rows.CreateLootRow(view.scrollChild, index, config.onSelect)

        view.archiveRows[index] =
            Rows.CreateArchiveRow(view.scrollChild, index, config.onArchiveView)
    end

    AttachScrollHandlers(view, config.onScrolled)

    return view.scrollFrame
end
