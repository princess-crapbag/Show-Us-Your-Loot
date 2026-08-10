-- Core/Dashboard.lua
--
-- Which widgets the dashboard shows, and in what order.
--
-- No frames. This is the registry and the saved state; UI/DashboardTab.lua
-- draws whatever this hands it, so adding a widget is a row here plus a
-- renderer there.
--
-- ALL ON BY DEFAULT. A widget reads data you already have and costs a redraw,
-- which is not something to opt into — that is the same call
-- Core/Features.lua makes for raid buffs and Mythic+ scores, and the opposite
-- of the one it makes for sync, which talks to other people.
--
-- THE SAVED ORDER IS A DUMB LIST OF NAMES, and it has to stay dumb. A name it
-- does not recognise is skipped; a widget missing from the list is appended.
-- Both cases then draw a working dashboard rather than an empty one, which is
-- what makes an order saved by an older version safe to read.

local SYL = _G.ShowUsYourLoot

local Dashboard = {}
SYL.Dashboard = Dashboard

-- `needs` names what a widget cannot draw without. "calendar" means it stays
-- a placeholder until the calendar exists, and says so on screen rather than
-- being silently blank.
--
-- `span` is how many of the three columns it takes.
Dashboard.WIDGETS = {
    {
        key = "lastNight",
        label = "Last raid night",
        note = "What dropped, and how many went home with nothing.",
        -- "feed", not "loot". Loot is the tab's label; feed is its key, and
        -- SetMode takes the key. Pointing at the label selected a mode no tab
        -- matched, which cleared every underline and blanked the subtitle.
        tab = "feed",
        span = 1,
    },
    {
        key = "nextNight",
        label = "Next raid night",
        note = "Reads the guild calendar. Blank if nobody keeps it up to date.",
        tab = "nights",
        span = 1,
        needs = "calendar",
    },
    {
        key = "due",
        label = "Who is due",
        note = "Your raid team, ranked by what they have taken per night.",
        tab = "raiders",
        span = 1,
    },
    {
        key = "readiness",
        label = "Readiness",
        note = "Roles and buff gaps. Reads your team's classes while open.",
        tab = "raiders",
        span = 1,
    },
    {
        key = "tier",
        label = "Tier progress",
        note = "Kills per boss, kept separate by difficulty.",
        tab = "bosses",
        span = 1,
    },
    {
        key = "links",
        label = "Links",
        note = "Your own URLs, copied from a box. Addons cannot open a browser.",
        tab = "settings",
        span = 1,
    },
    {
        key = "recording",
        label = "Recording",
        note = "Whether capture is on, and when it last saw anything.",
        tab = "settings",
        span = 3,
    },
}

-- The order the mocks were signed off in.
local DEFAULT_ORDER = {
    "lastNight", "nextNight", "due",
    "readiness", "tier", "links",
    "recording",
}

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.dashboard = ShowUsYourLootDB.dashboard or {}

    return ShowUsYourLootDB.dashboard
end

function Dashboard.Get(key)
    for _, widget in ipairs(Dashboard.WIDGETS) do
        if widget.key == key then
            return widget
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------

-- True unless the saved value says otherwise, so a widget added in a later
-- version arrives switched on rather than missing for everyone who already
-- has a saved table.
function Dashboard.IsEnabled(key)
    local store = Store()

    if not store or not store.disabled then
        return true
    end

    return store.disabled[key] ~= true
end

function Dashboard.SetEnabled(key, enabled)
    local store = Store()

    if not store then
        return
    end

    store.disabled = store.disabled or {}
    store.disabled[key] = (not enabled) or nil
end

function Dashboard.Toggle(key)
    local enabled = not Dashboard.IsEnabled(key)

    Dashboard.SetEnabled(key, enabled)

    return enabled
end

function Dashboard.CountEnabled()
    local total = 0

    for _, widget in ipairs(Dashboard.WIDGETS) do
        if Dashboard.IsEnabled(widget.key) then
            total = total + 1
        end
    end

    return total
end

--------------------------------------------------------------------------
-- Order
--------------------------------------------------------------------------

function Dashboard.GetOrder()
    local store = Store()
    local saved = store and store.order

    local seen, order = {}, {}

    -- Saved names first, skipping anything this version does not know. That
    -- is the case where a widget was removed between versions.
    for _, key in ipairs(saved or DEFAULT_ORDER) do
        if Dashboard.Get(key) and not seen[key] then
            seen[key] = true
            table.insert(order, key)
        end
    end

    -- Then anything the saved list never mentioned, in its declared order.
    -- That is the case where a widget was added between versions, and
    -- appending is what stops it vanishing.
    for _, widget in ipairs(Dashboard.WIDGETS) do
        if not seen[widget.key] then
            seen[widget.key] = true
            table.insert(order, widget.key)
        end
    end

    return order
end

function Dashboard.SetOrder(order)
    local store = Store()

    if not store or type(order) ~= "table" then
        return
    end

    store.order = order
end

function Dashboard.ResetOrder()
    local store = Store()

    if store then
        store.order = nil
    end
end

-- Moves one widget by one place. Returns whether anything moved, so a caller
-- can stay quiet at the ends of the list.
function Dashboard.Move(key, delta)
    local order = Dashboard.GetOrder()

    for index, name in ipairs(order) do
        if name == key then
            local target = index + delta

            if target < 1 or target > #order then
                return false
            end

            order[index], order[target] = order[target], order[index]

            Dashboard.SetOrder(order)

            return true
        end
    end

    return false
end

-- The widgets to draw, in order, already filtered to the enabled ones. The UI
-- iterates this and nothing else.
function Dashboard.Visible()
    local visible = {}

    for _, key in ipairs(Dashboard.GetOrder()) do
        local widget = Dashboard.Get(key)

        if widget and Dashboard.IsEnabled(key) then
            table.insert(visible, widget)
        end
    end

    return visible
end
