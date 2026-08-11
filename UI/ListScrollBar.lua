-- UI/ListScrollBar.lua
--
-- A scrollbar for the pooled-row lists.
--
-- The main window scrolls a real ScrollFrame and gets Blizzard's bar with it.
-- The other list windows do not: they keep a fixed pool of rows and change
-- which records are drawn into them, which is cheaper and means there is no
-- scroll frame for a bar to attach to. So the wheel worked and there was
-- nothing on screen saying how far down a list of four hundred people you
-- were, or any way to get there but spinning.
--
-- Built from a plain Slider rather than UIPanelScrollBarTemplate, which
-- expects named child buttons and a parent naming convention none of these
-- windows follow.
--
-- The caller owns the offset. This reads it, writes it back, and never keeps
-- a second copy to fall out of step with.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local ListScrollBar = {}
SYL.ListScrollBar = ListScrollBar

local WIDTH = 10

-- config:
--   top, bottom     insets from the window edges
--   getMax()        the largest offset the list can be scrolled to
--   getOffset()     where it is now
--   onScroll(value) put it here
function ListScrollBar.Create(parent, config)
    local slider = CreateFrame("Slider", nil, parent)

    slider:SetOrientation("VERTICAL")
    slider:SetWidth(WIDTH)
    slider:SetPoint("TOPRIGHT", -16, -config.top)
    slider:SetPoint("BOTTOMRIGHT", -16, config.bottom)

    local track = Theme.CreateSolidTexture(slider, "rowAlt", "BACKGROUND")
    track:SetAllPoints()

    -- Built through Theme so it repaints with the palette. A thumb colored
    -- once at creation stays the old scheme's color after a theme change,
    -- which is the bug the theme layer exists to prevent.
    local thumb = Theme.CreateSolidTexture(slider, "accent", "ARTWORK")

    thumb:SetSize(WIDTH, 40)

    slider:SetThumbTexture(thumb)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetMinMaxValues(0, 1)
    slider:SetValue(0)

    -- Guards the write-back, because Update calls SetValue and that fires
    -- OnValueChanged again. Without it a redraw would scroll the list.
    local updating = false

    slider:SetScript("OnValueChanged", function(_, value)
        if updating then
            return
        end

        config.onScroll(math.floor(value + 0.5))
    end)

    -- Called after every redraw, since the range depends on how many rows
    -- fit and how many records there are, and both change.
    slider.Update = function(self)
        local maxOffset = config.getMax() or 0

        updating = true

        self:SetMinMaxValues(0, math.max(0, maxOffset))
        self:SetValue(math.min(config.getOffset() or 0, maxOffset))

        updating = false

        -- Hidden rather than disabled when everything fits. A bar that
        -- cannot move reads as a list that is stuck.
        if maxOffset <= 0 then
            self:Hide()
        else
            self:Show()
        end
    end

    return slider
end
