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

    -- The width stays: this button is the root the whole scope chain
    -- measures back from, and it is the one control on the row that should
    -- not be hunted for. Only the type comes down, with the rest of the row.
    Theme.SetTextSize(closeButton.label, Theme.sizes.control)

    closeButton:SetPoint("BOTTOMRIGHT", -16, 12)

    -- OUTRANKS THE RESIZE GRIP, which is 16x16 at BOTTOMRIGHT -4,4 (see
    -- UI/Widgets.lua) and carries frame level +10. Its rect covers this
    -- button's bottom-right corner, 4px wide by 8px tall, and a click there
    -- started a resize instead of closing the window.
    --
    -- Raised rather than moved: the footer row has no 8px to give, and
    -- shifting Close left would drag the whole scope chain with it. The grip
    -- loses nothing visible -- its three diagonal marks all sit outside that
    -- corner -- and +11 is far below WindowStack's band ceiling, so nothing
    -- demotes it again.
    closeButton:SetFrameLevel(parent:GetFrameLevel() + 11)

    SYL.Tooltips.Attach(
        closeButton, "Close", "Escape does the same. Nothing is lost."
    )
end
