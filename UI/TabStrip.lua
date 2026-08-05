-- UI/TabStrip.lua
--
-- A row of tabs with one selected at a time. Knows nothing about loot, so any
-- window can use it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local TabStrip = {}
SYL.TabStrip = TabStrip

-- definitions: { { key = "drops", label = "Drops" }, ... }
function TabStrip.Create(parent, definitions, onSelect, anchorX, anchorY)
    local strip = { tabs = {} }
    local previous

    for _, definition in ipairs(definitions) do
        local tab = Theme.CreateTab(parent, definition.label, function()
            onSelect(definition.key)
        end)

        tab.key = definition.key

        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", anchorX, anchorY)
        end

        previous = tab

        table.insert(strip.tabs, tab)
    end

    function strip:SetSelected(key)
        for _, tab in ipairs(self.tabs) do
            tab:SetSelected(tab.key == key)
        end
    end

    return strip
end
