-- UI/SearchBox.lua
--
-- A text field with a placeholder, for filtering a list by name.
--
-- The filter bar has one of these built into it, but privately, and the
-- roster window is a different window with no filter bar. Rather than copy
-- thirty lines of edit box plumbing — which is how the boss window ended up
-- with a header that had drifted from the one it was copied from — it lives
-- here and both can use it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SearchBox = {}
SYL.SearchBox = SearchBox

-- options.bordered draws an outline, for a field that is a value rather than
-- a filter.
--
-- The roster window has both, a hundred pixels apart and previously
-- identical: one narrows the list as you type, the other is the name the
-- "Alt of" button will act on and does nothing at all until that button is
-- pressed. Two controls that look the same and behave completely differently
-- is a trap, and the one that does nothing looks broken.
function SearchBox.Create(parent, width, placeholder, onChange, options)
    local holder = CreateFrame("Frame", nil, parent)

    holder:SetSize(width, 20)

    if options and options.bordered then
        local edge = Theme.CreateSolidTexture(holder, "border", "BACKGROUND")

        edge:SetAllPoints()
    end

    local background =
        Theme.CreateSolidTexture(holder, "rowAlt", "BACKGROUND")

    if options and options.bordered then
        background:SetPoint("TOPLEFT", 1, -1)
        background:SetPoint("BOTTOMRIGHT", -1, 1)
    else
        background:SetAllPoints()
    end

    local editBox = CreateFrame("EditBox", nil, holder)

    editBox:SetPoint("TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", -6, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(Theme.CreateText and "GameFontHighlightSmall" or nil)
    editBox:SetTextColor(1, 1, 1, 1)

    local hint = Theme.CreateText(holder, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(placeholder or "Search…")

    holder.editBox = editBox

    -- Shown only while the box is empty, so it reads as a prompt rather than
    -- as text somebody has to clear before typing.
    holder.UpdatePlaceholder = function()
        if (editBox:GetText() or "") == "" then
            hint:Show()
        else
            hint:Hide()
        end
    end

    editBox:SetScript("OnTextChanged", function(self, userInput)
        holder.UpdatePlaceholder()

        if userInput then
            onChange(self:GetText() or "")
        end
    end)

    -- Escape closes the window otherwise, which is a surprise when the only
    -- thing you meant to leave was the text field.
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    holder.UpdatePlaceholder()

    return holder
end
