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

-- EMPTY, AND THAT IS THE CHANGE. Six buttons lived here — Due, Settings,
-- Players, Raids, Roster, Bosses — and every one of them is now a tab or the
-- cogwheel. Keeping them would mean two ways to reach each screen sitting a
-- centimetre apart, which is how a window teaches somebody that its
-- navigation is not to be trusted.
--
-- Due has no tab because it became the dashboard, which is the first thing
-- the window opens on. Settings is the cogwheel in the corner. The other four
-- are tabs.
--
-- The list stays rather than being deleted outright: this file exists to turn
-- a list into a row of buttons, and the next thing that wants a footer button
-- should add a line rather than rebuild the loop.
local BUTTONS = {}

-- handlers carries the behavior MainWindow owns and this file cannot reach.
-- Only onClose now: the Refresh button is gone, because every window
-- already redraws on show and on every change, so it was a button whose
-- honest label would have been "do nothing, slowly".
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

        SYL.Tooltips.Attach(button, entry.label, entry.tip)

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

    SYL.Tooltips.Attach(
        closeButton, "Close", "Escape does the same. Nothing is lost."
    )
end
