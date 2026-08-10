-- UI/TabPanels.lua
--
-- The content behind each tab that is not the loot list.
--
-- Built here rather than in MainWindow, which was already at the size limit
-- before any of these existed. That file owns the chrome, the tab state and
-- the loot list; this one owns what the other five tabs draw.
--
-- WHERE THE ROUTING PANELS COME FROM. Nights, Bosses and Keys are designed and
-- agreed but not yet drawn in the window — the raid, boss and key screens still
-- exist as separate windows and still work. So each tab says what it is for and
-- opens the window that answers it today.
--
-- That is deliberate rather than lazy. Folding six windows into one is a
-- refactor that touches every one of them, and doing it in the same change as
-- new widgets would mean a broken dashboard and a broken roster at once, with
-- no way to tell which broke. The tab is real, the route is real, and the
-- panel replaces the route one screen at a time.
--
-- RAIDERS IS THE FIRST ONE REPLACED. It is drawn by UI/RaidersPanel.lua and no
-- longer routes anywhere. The players and roster windows still exist and are
-- still reachable from the roster button in settings; nothing was deleted in
-- the same change that added a screen.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local TabPanels = {}
SYL.TabPanels = TabPanels

-- key, heading, what it answers, and the window that answers it today.
local ROUTES = {
    {
        mode = "nights",
        title = "Nights",
        blurb = "Every raid night recorded, who was there, what was pulled and "
            .. "what dropped. The calendar view and the next raid night are "
            .. "not built yet — they need the in-game guild calendar, which "
            .. "nothing here reads so far.",
        button = "Open raid nights",
        open = function()
            if SYL.OpenRaidWindow then
                SYL:OpenRaidWindow()
            end
        end,
    },
    {
        mode = "bosses",
        title = "Bosses",
        blurb = "Pulls, kills and drops for every boss, kept apart by "
            .. "difficulty. The loot table showing what a boss still owes you "
            .. "is designed but not drawn yet.",
        button = "Open bosses",
        open = function()
            if SYL.OpenBossWindow then
                SYL:OpenBossWindow()
            end
        end,
    },
    {
        mode = "keys",
        title = "Mythic+ keys",
        blurb = "What your characters are holding, and what your guild is "
            .. "holding if they run this addon with key sharing on. Nothing "
            .. "can read another player's bags, so the list only ever holds "
            .. "what somebody's addon sent.",
        button = "Print keys to chat",
        open = function()
            SlashCmdList["SHOWUSYOURLOOT"]("keys")
        end,
    },
}

local function CreateRoutePanel(parent, route)
    local panel = CreateFrame("Frame", nil, parent)

    panel:SetPoint("TOPLEFT", 16, -100)
    panel:SetPoint("BOTTOMRIGHT", -16, 52)

    local title = Theme.CreateText(panel, Theme.sizes.title, "textPrimary")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText(string.upper(route.title))

    local blurb = Theme.CreateText(panel, Theme.sizes.row, "textSecondary")
    blurb:SetPoint("TOPLEFT", 2, -30)
    blurb:SetWidth(520)
    blurb:SetJustifyH("LEFT")
    blurb:SetWordWrap(true)
    blurb:SetText(route.blurb)

    local open = Theme.CreateButton(panel, 170, 26, route.button, route.open)
    open:SetPoint("TOPLEFT", 2, -116)

    local previous = open

    if route.second then
        local second = Theme.CreateButton(
            panel, 150, 26, route.second, route.openSecond
        )

        second:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        previous = second
    end

    if route.third then
        local third = Theme.CreateButton(
            panel, 150, 26, route.third, route.openThird
        )

        third:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    end

    -- Said plainly rather than left for somebody to work out from the fact
    -- that a button opens a different window.
    local note = Theme.CreateText(panel, Theme.sizes.rowSmall, "textMuted")
    note:SetPoint("TOPLEFT", 2, -152)
    note:SetWidth(520)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(
        "This tab opens the existing window for now. It is being moved into "
        .. "the main window one screen at a time."
    )

    panel:Hide()

    return panel
end

-- Returns mode -> panel. MainWindow shows one and hides the rest.
function TabPanels.CreateAll(parent, config)
    local panels = {}

    panels.dashboard = SYL.DashboardTab.Create(parent, {
        onOpenTab = config.onOpenTab,
    })

    panels.raiders = SYL.RaidersPanel.Create(parent)

    for _, route in ipairs(ROUTES) do
        panels[route.mode] = CreateRoutePanel(parent, route)
    end

    return panels
end
