-- UI/Tooltips.lua
--
-- Explaining a control on hover.
--
-- UI/ItemTooltip.lua and UI/BossTooltip.lua add loot history to tooltips the
-- game already shows. This is the other direction: a tooltip of our own on
-- our own controls.

local SYL = _G.ShowUsYourLoot

local Tooltips = {}
SYL.Tooltips = Tooltips

-- Says what a control does, on hover.
--
-- Roughly two dozen controls in the main window had no explanation anywhere:
-- not on screen, not in the README, not in `/syl help`. "All content", "Gear
-- only" and "All seasons" are three buttons that all narrow or widen the same
-- list in different dimensions, and the only way to learn which was to press
-- one and compare. Several of them are also toggles, so pressing to find out
-- changes what you were looking at.
--
-- Attached with HookScript rather than SetScript, because the buttons already
-- use OnEnter and OnLeave for their hover colour and replacing that would
-- leave them stuck lit.
function Tooltips.Attach(frame, title, body)
    if not frame then
        return
    end

    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)

        if body then
            GameTooltip:AddLine(body, 0.72, 0.66, 0.68, true)
        end

        GameTooltip:Show()
    end)

    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
