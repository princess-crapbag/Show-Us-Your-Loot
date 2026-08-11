-- UI/Toggles.lua
--
-- Buttons that are on or off and show which.
--
-- Every filter button in this addon was the same fifteen lines: flip a
-- boolean, recolor the label to match, reset the scroll, refresh. Written
-- out each time, which is how one of them ends up not recoloring and looking
-- broken while working perfectly.
--
-- The caller keeps the state. This owns only the appearance of it, because a
-- toggle that remembered its own value would then have two copies of it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Toggles = {}
SYL.Toggles = Toggles

-- onToggle is called with the new state, so callers assign rather than flip
-- and cannot get the two out of step.
function Toggles.Create(parent, width, label, onToggle, startOn)
    local state = startOn and true or false

    local button

    button = Theme.CreateButton(parent, width, 20, label, function()
        state = not state

        Theme.SetTextColor(
            button.label, state and "accent" or "textPrimary"
        )

        onToggle(state)
    end)

    Theme.SetTextColor(
        button.label, state and "accent" or "textPrimary"
    )

    button.IsOn = function()
        return state
    end

    return button
end
