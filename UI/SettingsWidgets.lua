-- UI/SettingsWidgets.lua
--
-- The dashboard widget list in Settings: a tick per widget.
--
-- Its own file because UI/SettingsRows.lua is already size-exempt, and adding
-- a third section to it would mean either growing an exempt file or trimming
-- comments to fit. Neither is a real fix. This is one section, built the same
-- way the other two are and called from the same place.
--
-- REORDERING IS GONE, and only the buttons are. Aimee: "i cant see most of
-- the dashboard widgets to rearrange them. im not sure people need to be able
-- to rearrange them anymore." Every widget is a fixed size on a fixed grid, so
-- moving one swaps two tiles and changes nothing else — which is not worth the
-- two buttons per row it cost, or the height they forced.
--
-- Core/Dashboard.lua keeps Move, GetOrder and SetOrder untouched, and the
-- saved order is still read and honored. Nothing has been deleted: putting
-- the control back is this file again, and any order somebody already saved
-- still draws exactly as it did.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SettingsWidgets = {}
SYL.SettingsWidgets = SettingsWidgets

-- 24 and three across, which is what the rest of the settings window uses.
-- It was 48 and one per line to fit a two-line note under every label; the
-- note is a tooltip now, for the same reason the feature costs are.
local ROW_HEIGHT = 20
local COLUMNS = 3
local HEADING_HEIGHT = 26

local rows = {}

function SettingsWidgets.SectionHeight()
    return HEADING_HEIGHT
        + SYL.SettingsRows.GridRows(#SYL.Dashboard.WIDGETS, COLUMNS) * ROW_HEIGHT
        + 24
end

local function CreateRow(parent, index, widget, onChanged)
    local row = CreateFrame("Frame", nil, parent)

    local column = (index - 1) % COLUMNS
    local line = math.floor((index - 1) / COLUMNS)
    local width = (parent:GetWidth() or 360) / COLUMNS

    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(width - 6)
    row:SetPoint("TOPLEFT", column * width, -(line * ROW_HEIGHT))

    -- ALL SEVEN OF THESE TOOLTIPS WERE DEAD, and this line is why.
    --
    -- The row is a plain Frame, and a Frame does not take the mouse unless it
    -- is told to. Tooltips.Attach hooks OnEnter, which a mouse-disabled frame
    -- never fires -- so every widget note in Core/Dashboard.lua:33-78 was
    -- unreachable text. Only the 14x14 box took clicks, and it is a Button,
    -- which is why toggling a widget worked and pointing at one did nothing.
    --
    -- It looked exactly like a tooltip nobody had bothered to write.
    row:EnableMouse(true)

    local box = CreateFrame("Button", nil, row)

    box:SetSize(14, 14)
    box:SetPoint("LEFT", 2, 0)

    box.background = Theme.CreateSolidTexture(box, "button", "BACKGROUND")
    box.background:SetAllPoints()

    box.tick = Theme.CreateText(box, Theme.sizes.rowSmall, "accent")
    box.tick:SetPoint("CENTER", 0, 0)

    box:SetScript("OnClick", function()
        SYL.Dashboard.Toggle(widget.key)
        onChanged()
    end)

    local label = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(widget.label)

    -- The note is a hover rather than a second line, which is what let the
    -- section go from seven tall rows to three short ones.
    SYL.Tooltips.Attach(row, widget.label, widget.note or "")

    row.box = box
    row.widget = widget

    return row
end

function SettingsWidgets.Refresh()
    for _, row in ipairs(rows) do
        local enabled = SYL.Dashboard.IsEnabled(row.widget.key)

        row.box.tick:SetText(enabled and "x" or "")
    end
end

function SettingsWidgets.Build(parent, top, addSection)
    local container = addSection(parent, "DASHBOARD WIDGETS", top)

    -- THE GRID IS THREE ACROSS, so seven widgets are three lines and not
    -- seven. Sizing this as one-per-line made the container 164 tall against
    -- a 60px grid, and the Default order button below it was anchored off the
    -- same wrong number -- which put it 82px past the bottom of the section
    -- and clean off the window. It has been drawn but unreachable ever since
    -- the section went three across.
    local lines = SYL.SettingsRows.GridRows(#SYL.Dashboard.WIDGETS, COLUMNS)

    container:SetHeight(lines * ROW_HEIGHT + 26)

    rows = {}

    local function Changed()
        SettingsWidgets.Refresh()

        -- The dashboard is very likely open behind this window.
        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end

    -- Drawn in the saved order, so the list reads as the dashboard reads.
    for index, key in ipairs(SYL.Dashboard.GetOrder()) do
        local widget = SYL.Dashboard.Get(key)

        if widget then
            table.insert(rows, CreateRow(container, index, widget, function()
                Changed()

                -- Reordering changes which row is which, so the whole section
                -- is rebuilt rather than trying to shuffle frames in place.
                SettingsWidgets.Rebuild()
            end))
        end
    end

    local reset = Theme.CreateButton(container, 150, 20, "Default order", function()
        SYL.Dashboard.ResetOrder()
        SettingsWidgets.Rebuild()
        Changed()
    end)

    reset:SetPoint("TOPLEFT", 0, -(lines * ROW_HEIGHT + 4))

    SettingsWidgets.container = container
    SettingsWidgets.parent = parent
    SettingsWidgets.top = top
    SettingsWidgets.addSection = addSection

    SettingsWidgets.Refresh()

    -- The height as well, so a tab can stack whatever comes next under it.
    -- The button is inside the container, so it is inside this number.
    return container, HEADING_HEIGHT + lines * ROW_HEIGHT + 26
end

-- Tears the section down and builds it again, which is how a reorder shows.
function SettingsWidgets.Rebuild()
    if not SettingsWidgets.container then
        return
    end

    -- The heading too. It belongs to the window rather than the container, so
    -- hiding only the container stacked a fresh "DASHBOARD WIDGETS" on top of
    -- the old one every time the order changed.
    if SettingsWidgets.container.heading then
        SettingsWidgets.container.heading:Hide()
    end

    SettingsWidgets.container:Hide()
    SettingsWidgets.container = nil

    SettingsWidgets.Build(
        SettingsWidgets.parent,
        SettingsWidgets.top,
        SettingsWidgets.addSection
    )
end
