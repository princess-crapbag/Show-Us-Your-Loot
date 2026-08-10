-- UI/TabPanels.lua
--
-- The content behind each tab that is not the loot list.
--
-- Built here rather than in MainWindow, which was already at the size limit
-- before any of these existed. That file owns the chrome, the tab state and
-- the loot list; this one owns what the other five tabs draw.
--
-- EVERY TAB IS A REAL SCREEN NOW. This file used to hold a routing panel per
-- tab — a heading, a blurb, and a button that opened the old standalone
-- window — because folding six windows into one at once would have meant a
-- broken dashboard and a broken roster together, with no way to tell which
-- broke first. That was the right order and it is finished: Raiders, Bosses,
-- Nights and Keys are all drawn in the window, and the routing scaffolding it
-- took to get here has been deleted rather than left behind.
--
-- The windows those panels replaced still load and are still reachable by
-- slash command. Nothing was deleted in the same change that added a screen,
-- so a panel that turns out wrong in game leaves the old answer standing —
-- see `/syl due window`, `/syl raids`, `/syl bosses`, `/syl roster`.

local SYL = _G.ShowUsYourLoot

local TabPanels = {}
SYL.TabPanels = TabPanels

-- Returns mode -> panel. MainWindow shows one and hides the rest, so the keys
-- here have to match the tab keys exactly — a tab whose key names no panel
-- selects a mode nothing matches, which blanks the strip and draws the body
-- anyway, and reads as a rendering glitch rather than a bad link.
function TabPanels.CreateAll(parent, config)
    local panels = {}

    panels.dashboard = SYL.DashboardTab.Create(parent, {
        onOpenTab = config.onOpenTab,
    })

    panels.raiders = SYL.RaidersPanel.Create(parent)
    panels.bosses = SYL.BossesPanel.Create(parent)
    panels.nights = SYL.NightsPanel.Create(parent)
    panels.keys = SYL.KeysPanel.Create(parent)

    return panels
end
