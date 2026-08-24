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

-- Invalid text is left in place and colored, rather than being wiped. Losing
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

-- The word sits outside the box so the placeholder only has to fit the date
-- format. Packing "From MM-DD-YYYY" inside a 92px box is what made these look
-- cut off in the first place.
--
-- The box is then measured rather than guessed. 84px was a guess, and at a
-- twelve pixel inset it left seventy-two for ten characters — right on the
-- edge, which is why this came back. Measuring the widest string the box ever
-- holds and adding the inset cannot be off.
local DATE_PLACEHOLDER = "MM-DD-YYYY"

-- The editbox is inset six pixels each side inside its holder, and a caret
-- sits at the end of the text.
local INPUT_INSET = 12
local CARET_ROOM = 8

local function CreateDateField(parent, labelText, state, key, endOfDay, onChange, anchorTo)
    local label = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")

    label:SetText(labelText)
    label:SetWidth(label:GetStringWidth() + 2)
    label:SetPoint("LEFT", anchorTo, "RIGHT", 10, 0)

    -- A typed date and the placeholder are both ten characters, but zeroes are
    -- not the widest digits, so the placeholder is measured alongside a worst
    -- case of real digits.
    local width = math.max(
        Theme.MeasureText(Theme.sizes.rowSmall, DATE_PLACEHOLDER),
        Theme.MeasureText(Theme.sizes.rowSmall, "0000-00-00")
    ) + INPUT_INSET + CARET_ROOM

    local input =
        CreateDateInput(parent, width, DATE_PLACEHOLDER, state, key, endOfDay, onChange)

    input:SetPoint("LEFT", label, "RIGHT", 4, 0)

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

    local search = CreateTextInput(bar, 100, "Search…")

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
            width = 86,

            getOptions = function()
                return SYL.FilterOptions.Derive(
                    config.getRecords(),
                    config.getFields(),
                    field
                )
            end,

            -- IsShowing, not IsSelected. With nothing chosen, the list is
            -- showing everything except what Filters.HIDDEN_BY_DEFAULT names,
            -- and a box drawn empty beside a row that IS showing is a control
            -- lying about what it is doing.
            isSelected = function(value)
                return Filters.IsShowing(state, field, value)
            end,

            getCount = function()
                return Filters.CountSelected(state, field)
            end,

            -- THE FIRST CLICK IN A FIELD MAKES THE SELECTION EXPLICIT.
            --
            -- Before it, nothing is chosen and the default exclusion decides.
            -- Toggling one value there would leave the other three unticked
            -- and hide them, which is the opposite of what unticking one box
            -- looks like it should do. So the first click starts from what
            -- was on screen and then applies itself.
            onToggle = function(value)
                if Filters.CountSelected(state, field) == 0 then
                    Filters.SelectShowing(
                        state,
                        field,
                        SYL.FilterOptions.Derive(
                            config.getRecords(),
                            config.getFields(),
                            field
                        )
                    )
                end

                Filters.Toggle(state, field, value)
                onChange()
            end,

            onSelectAll = function()
                Filters.SelectAll(
                    state,
                    field,
                    SYL.FilterOptions.Derive(
                        config.getRecords(),
                        config.getFields(),
                        field
                    )
                )

                onChange()
            end,

            onClear = function()
                Filters.ClearField(state, field)
                onChange()
            end,
        })

        dropdown:SetPoint("LEFT", previous, "RIGHT", CONTROL_GAP, 0)

        -- Ticking two values inside one dropdown widens the result; ticking
        -- across two dropdowns narrows it. That is what people expect from
        -- checkbox filters and it is not obvious from looking at them.
        SYL.Tooltips.Attach(
            dropdown,
            Filters.LABELS[field],
            "Tick several to see any of them. Filters in different dropdowns "
            .. "apply together."
        )

        bar.dropdowns[field] = dropdown
        previous = dropdown
    end

    local fromInput = CreateDateField(
        bar, "From", state, "dateFrom", false, onChange, previous
    )

    local toInput = CreateDateField(
        bar, "To", state, "dateTo", true, onChange, fromInput
    )

    -- Anchored to the right edge rather than flowed from the left, so nothing
    -- widening ahead of it can push it off the bar.
    -- Clears the toggles on the row below as well, not just this row's boxes.
    --
    -- "Clear" was read — reasonably — as "show me everything again", and it
    -- left This season, Gear only and Raids only exactly as they were. That
    -- is not a cosmetic gap: with Gear only still on, a list that looks
    -- cleared is still hiding every reagent, and Select all then ticks a
    -- subset of what is actually there. It cost Aimee a bulk Hide that missed
    -- twenty records and looked like a bug in Hide.
    --
    -- Show hidden is deliberately NOT reset. Every other toggle narrows the
    -- list, so clearing them shows more; that one only ever shows more, so
    -- clearing it would show less and make Clear mean two opposite things.
    local clearButton = Theme.CreateButton(bar, 54, BAR_HEIGHT, "Clear", function()
        Filters.ClearAll(state)

        search.editBox:SetText("")
        fromInput.editBox:SetText("")
        toInput.editBox:SetText("")

        FilterDropdown.CloseAll()

        if config.onClear then
            config.onClear()
        end

        bar:Refresh()
        onChange()
    end)

    SYL.Tooltips.Attach(
        clearButton,
        "Clear filters",
        "Empties the search, the dates and every dropdown. It does not "
        .. "change any record."
    )

    clearButton:SetPoint("RIGHT", 0, 0)

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
