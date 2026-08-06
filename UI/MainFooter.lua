-- UI/MainFooter.lua
--
-- The row of buttons along the bottom of the main window.
--
-- Split out of MainWindow, which had reached the size limit. The buttons were
-- also nine near-identical blocks that differed only in label and action, so
-- they are a list here: adding a window means adding a line rather than
-- copying a block and remembering to re-anchor the one after it.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local MainFooter = {}
SYL.MainFooter = MainFooter

local BUTTON_WIDTH = 100
local BUTTON_HEIGHT = 26
local GAP = 6

-- Left to right. Close is anchored to the right separately, since it is the
-- one action that is not a place to go.
local BUTTONS = {
    { label = "Refresh", action = "onRefresh" },
    { label = "Settings", open = "OpenSettingsWindow" },
    { label = "Players", open = "OpenPlayerWindow" },
    { label = "Raids", open = "OpenRaidWindow" },
    { label = "Bosses", open = "OpenBossWindow" },
}

-- handlers carries the behaviour MainWindow owns and this file cannot reach:
-- onRefresh redraws the list, onClose hides the window.
function MainFooter.Create(parent, handlers)
    local separator = Theme.CreateSeparator(parent)
    separator:SetPoint("BOTTOMLEFT", 16, 44)
    separator:SetPoint("BOTTOMRIGHT", -16, 44)

    local previous

    for _, entry in ipairs(BUTTONS) do
        local onClick

        if entry.open then
            -- Looked up at click time rather than now, so load order between
            -- UI files cannot leave a button wired to nothing.
            onClick = function()
                local open = SYL[entry.open]

                if open then
                    open(SYL)
                end
            end
        else
            onClick = handlers[entry.action]
        end

        local button = Theme.CreateButton(
            parent, BUTTON_WIDTH, BUTTON_HEIGHT, entry.label, onClick
        )

        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
        else
            button:SetPoint("BOTTOMLEFT", 16, 12)
        end

        previous = button
    end

    local closeButton = Theme.CreateButton(
        parent, BUTTON_WIDTH, BUTTON_HEIGHT, "Close", handlers.onClose
    )

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)
end
