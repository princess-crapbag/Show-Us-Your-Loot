-- UI/SettingsWidgets.lua
--
-- The dashboard widget list in Settings: a tick per widget, and arrows to
-- move one up or down.
--
-- Its own file because UI/SettingsRows.lua is already size-exempt, and adding
-- a third section to it would mean either growing an exempt file or trimming
-- comments to fit. Neither is a real fix. This is one section, built the same
-- way the other two are and called from the same place.
--
-- ARROWS RATHER THAN DRAG. Aimee asked for drag-to-reorder "if it doesnt
-- break the addon". Dragging inside a WoW settings panel means tracking the
-- cursor against a list of frames and re-anchoring on every move, which is a
-- lot of machinery for a list of eight; two arrows do the same job, cannot
-- drop a widget somewhere ambiguous, and are reachable without a mouse. The
-- saved order is identical either way, so a drag handle can replace them
-- later without touching Core/Dashboard.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SettingsWidgets = {}
SYL.SettingsWidgets = SettingsWidgets

local ROW_HEIGHT = 34
local HEADING_HEIGHT = 26

local rows = {}

function SettingsWidgets.SectionHeight()
    return HEADING_HEIGHT + #SYL.Dashboard.WIDGETS * ROW_HEIGHT + 24
end

local function CreateRow(parent, index, widget, onChanged)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    local box = CreateFrame("Button", nil, row)

    box:SetSize(14, 14)
    box:SetPoint("TOPLEFT", 2, -3)

    box.background = Theme.CreateSolidTexture(box, "button", "BACKGROUND")
    box.background:SetAllPoints()

    box.tick = Theme.CreateText(box, Theme.sizes.rowSmall, "accent")
    box.tick:SetPoint("CENTER", 0, 0)

    box:SetScript("OnClick", function()
        SYL.Dashboard.Toggle(widget.key)
        onChanged()
    end)

    local label = Theme.CreateText(row, Theme.sizes.row, "textPrimary")
    label:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 1)
    label:SetPoint("RIGHT", -70, 0)
    label:SetJustifyH("LEFT")
    label:SetText(widget.label)

    local note = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    note:SetPoint("RIGHT", -70, 0)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(widget.note or "")

    local down = Theme.CreateButton(row, 24, 18, "v", function()
        if SYL.Dashboard.Move(widget.key, 1) then
            onChanged()
        end
    end)

    down:SetPoint("TOPRIGHT", -4, -4)

    local up = Theme.CreateButton(row, 24, 18, "^", function()
        if SYL.Dashboard.Move(widget.key, -1) then
            onChanged()
        end
    end)

    up:SetPoint("RIGHT", down, "LEFT", -4, 0)

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

    container:SetHeight(#SYL.Dashboard.WIDGETS * ROW_HEIGHT + 24)

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

    reset:SetPoint("TOPLEFT", 0, -(#SYL.Dashboard.WIDGETS * ROW_HEIGHT + 2))

    SettingsWidgets.container = container
    SettingsWidgets.parent = parent
    SettingsWidgets.top = top
    SettingsWidgets.addSection = addSection

    SettingsWidgets.Refresh()

    return container
end

-- Tears the section down and builds it again, which is how a reorder shows.
function SettingsWidgets.Rebuild()
    if not SettingsWidgets.container then
        return
    end

    SettingsWidgets.container:Hide()
    SettingsWidgets.container:SetParent(nil)
    SettingsWidgets.container = nil

    SettingsWidgets.Build(
        SettingsWidgets.parent,
        SettingsWidgets.top,
        SettingsWidgets.addSection
    )
end
