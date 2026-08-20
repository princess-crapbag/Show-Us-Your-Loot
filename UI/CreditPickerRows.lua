-- UI/CreditPickerRows.lua
--
-- The two kinds of control the credit picker is made of: a candidate row, and
-- the response buttons underneath them.
--
-- Split from UI/CreditPicker.lua from the start rather than afterwards, which
-- is the shape HANDOFF asks for and the one Raiders, Bosses and Nights each
-- arrived at the hard way.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local CreditPickerRows = {}
SYL.CreditPickerRows = CreditPickerRows

local ROLL_STATE = SYL.LootHistoryAPI.ROLL_STATE

-- Aimee's rule, and only her rule: Need 100, offspec and sidegrade and minor
-- upgrade all Greed at 20, mog 0. Three buttons because there are three
-- answers she gives, not because the enum has six values.
CreditPickerRows.WEIGHTS = {
    { state = ROLL_STATE.NeedMainSpec, label = "Need" },
    { state = ROLL_STATE.Greed, label = "Greed" },
    { state = ROLL_STATE.Transmog, label = "Mog" },
}

--------------------------------------------------------------------------
-- A candidate
--------------------------------------------------------------------------

function CreditPickerRows.CreateRow(parent, index, layout, onClick)
    local row = CreateFrame("Button", nil, parent)

    local top = layout.listTop + (index - 1) * layout.rowHeight

    row:SetHeight(layout.rowHeight)
    row:SetPoint("TOPLEFT", 16, -top)
    row:SetPoint("TOPRIGHT", -16, -top)

    Widgets.AddRowBackgrounds(row, index)

    row.selected = Theme.CreateSolidTexture(row, "accentMuted", "BORDER")
    row.selected:SetAllPoints()
    row.selected:Hide()

    row.nameText = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.nameText:SetPoint("LEFT", 10, 0)

    row.noteText = Theme.CreateText(row, Theme.sizes.columnHeader, "textMuted")
    row.noteText:SetPoint("RIGHT", -10, 0)

    -- Widgets.AddRowBackgrounds builds row.highlight and hides it, leaving the
    -- caller to wire it — which every other list in the addon does and this
    -- one did not. A column of ten near-identical names with no reaction to
    -- the pointer reads as a static display rather than as the control that
    -- picks who gets the credit.
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", function(self)
        if self.candidate then
            onClick(self.candidate)
        end
    end)

    return row
end

-- `state` carries the two marks a row can wear: whether it is the one being
-- chosen, and whether it is where the credit sits today. They are different
-- things and on a first open they are the same row, which is why both are
-- drawn rather than one standing in for the other.
function CreditPickerRows.FillRow(row, candidate, state)
    row.candidate = candidate

    row.nameText:SetText(tostring(candidate.name))

    local classColor = Theme.GetClassColor(candidate.class)

    if classColor then
        Theme.SetCustomTextColor(
            row.nameText, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(row.nameText, "textPrimary")
    end

    if state.chosen then
        row.selected:Show()
    else
        row.selected:Hide()
    end

    row.noteText:SetText(state.current and "credited now" or "")
end

--------------------------------------------------------------------------
-- The response buttons
--------------------------------------------------------------------------

-- Selected state is an underline and a colored label rather than a different
-- background, because Theme.CreateButton's hover handlers own the background
-- and would wipe it on the first mouse-over.
function CreditPickerRows.CreateWeightButtons(parent, top, onChoose)
    local buttons = {}
    local left = 16

    for index, weight in ipairs(CreditPickerRows.WEIGHTS) do
        local label =
            weight.label .. " " .. SYL.LootScore.WeightOf(weight.state)

        -- MEASURED. Theme.MeasureText exists for exactly this, and a button
        -- sized by guess is either clipped or too wide — and too wide is a
        -- defect too.
        local width = Theme.MeasureText(Theme.sizes.rowSmall, label) + 22

        local button = Theme.CreateButton(parent, width, 22, label, function()
            onChoose(weight.state)
        end)

        button:SetPoint("TOPLEFT", left, -top)

        button.underline = Theme.CreateSolidTexture(button, "accent", "ARTWORK")
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", 4, 0)
        button.underline:SetPoint("BOTTOMRIGHT", -4, 0)
        button.underline:Hide()

        button.state = weight.state

        buttons[index] = button
        left = left + width + 6
    end

    return buttons
end

function CreditPickerRows.MarkWeight(buttons, chosenState)
    for _, button in ipairs(buttons or {}) do
        if button.state == chosenState then
            button.underline:Show()
            Theme.SetTextColor(button.label, "accent")
        else
            button.underline:Hide()
            Theme.SetTextColor(button.label, "textSecondary")
        end
    end
end
