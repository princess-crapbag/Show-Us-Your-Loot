-- UI/FilterBar.lua
--
-- The row of controls above the list: free-text search, one multi-select
-- dropdown per filterable field, a date range, and a clear button.
--
-- Holds no filter state of its own. The window owns a Filters state table and
-- passes it in; this only reads and writes it, then calls onChange.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Filters = SYL.Filters
local FilterDropdown = SYL.FilterDropdown

local FilterBar = {}
SYL.FilterBar = FilterBar

local BAR_HEIGHT = 22
local CONTROL_GAP = 6

--------------------------------------------------------------------------
-- Text input
--------------------------------------------------------------------------

local function CreateTextInput(parent, width, placeholder)
    local holder = CreateFrame("Frame", nil, parent)

    holder:SetSize(width, BAR_HEIGHT)

    holder.background =
        Theme.CreateSolidTexture(holder, "button", "BACKGROUND")

    holder.background:SetAllPoints()

    local editBox = CreateFrame("EditBox", nil, holder)

    editBox:SetPoint("TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", -6, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFont(Theme.GetFontPath(), Theme.sizes.rowSmall, "")
    editBox:SetTextColor(unpack(Theme.colors.textPrimary))

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    holder.placeholder =
        Theme.CreateText(holder, Theme.sizes.rowSmall, "textMuted")

    holder.placeholder:SetPoint("LEFT", 7, 0)
    holder.placeholder:SetText(placeholder)

    holder.editBox = editBox

    holder.UpdatePlaceholder = function(self)
        if self.editBox:GetText() == "" and not self.editBox:HasFocus() then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
    end

    editBox:HookScript("OnEditFocusGained", function()
        holder:UpdatePlaceholder()
    end)

    editBox:HookScript("OnEditFocusLost", function()
        holder:UpdatePlaceholder()
    end)

    holder:UpdatePlaceholder()

    return holder
end

--------------------------------------------------------------------------
-- Date inputs
--------------------------------------------------------------------------

-- Invalid text is left in place and coloured, rather than being wiped. Losing
-- what someone typed is worse than showing it is not accepted yet.
local function ApplyDate(input, state, key, endOfDay, onChange)
    local text = input.editBox:GetText()
    local parsed = Filters.ParseDate(text, endOfDay)

    if text ~= "" and not parsed then
        input.editBox:SetTextColor(unpack(Theme.colors.warning))
        return
    end

    input.editBox:SetTextColor(unpack(Theme.colors.textPrimary))

    state[key] = parsed

    onChange()
end

local function CreateDateInput(parent, width, placeholder, state, key, endOfDay, onChange)
    local input = CreateTextInput(parent, width, placeholder)

    input.editBox:SetScript("OnEnterPressed", function(self)
        ApplyDate(input, state, key, endOfDay, onChange)
        self:ClearFocus()
    end)

    input.editBox:HookScript("OnEditFocusLost", function()
        ApplyDate(input, state, key, endOfDay, onChange)
    end)

    return input
end

--------------------------------------------------------------------------
-- Assembly
--------------------------------------------------------------------------

function FilterBar.Create(parent, config)
    local state = config.state
    local onChange = config.onChange

    local bar = CreateFrame("Frame", nil, parent)

    bar:SetHeight(BAR_HEIGHT)
    bar.dropdowns = {}

    local search = CreateTextInput(bar, 170, "Search…")

    search:SetPoint("LEFT", 0, 0)

    search.editBox:SetScript("OnTextChanged", function(self, userInput)
        search:UpdatePlaceholder()

        if not userInput then
            return
        end

        state.search = self:GetText() or ""

        onChange()
    end)

    local previous = search

    for _, field in ipairs(Filters.FIELDS) do
        local dropdown = FilterDropdown.Create(bar, {
            label = Filters.LABELS[field],
            width = 104,

            getOptions = function()
                return Filters.DeriveOptions(
                    config.getRecords(),
                    config.getFields(),
                    field
                )
            end,

            isSelected = function(value)
                return Filters.IsSelected(state, field, value)
            end,

            getCount = function()
                return Filters.CountSelected(state, field)
            end,

            onToggle = function(value)
                Filters.Toggle(state, field, value)
                onChange()
            end,

            onClear = function()
                Filters.ClearField(state, field)
                onChange()
            end,
        })

        dropdown:SetPoint("LEFT", previous, "RIGHT", CONTROL_GAP, 0)

        bar.dropdowns[field] = dropdown
        previous = dropdown
    end

    local fromInput = CreateDateInput(
        bar, 92, "From YYYY-MM-DD", state, "dateFrom", false, onChange
    )

    fromInput:SetPoint("LEFT", previous, "RIGHT", CONTROL_GAP, 0)

    local toInput = CreateDateInput(
        bar, 92, "To YYYY-MM-DD", state, "dateTo", true, onChange
    )

    toInput:SetPoint("LEFT", fromInput, "RIGHT", CONTROL_GAP, 0)

    local clearButton = Theme.CreateButton(bar, 56, BAR_HEIGHT, "Clear", function()
        Filters.ClearAll(state)

        search.editBox:SetText("")
        fromInput.editBox:SetText("")
        toInput.editBox:SetText("")

        FilterDropdown.CloseAll()

        bar:Refresh()
        onChange()
    end)

    clearButton:SetPoint("LEFT", toInput, "RIGHT", CONTROL_GAP, 0)

    bar.Refresh = function(self)
        for _, dropdown in pairs(self.dropdowns) do
            dropdown:UpdateLabel()
        end

        search:UpdatePlaceholder()
        fromInput:UpdatePlaceholder()
        toInput:UpdatePlaceholder()
    end

    return bar
end
