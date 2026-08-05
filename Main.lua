-- Main.lua
--
-- Addon entry point. Defines the shared addon table and the output helpers
-- every other file relies on. This file must load first.

local addonName, SYL = ...

_G.ShowUsYourLoot = SYL

SYL.name = addonName
SYL.version = "0.0.6"

SYL.colors = {
    addon = "|cff33ff99",
    debug = "|cff66ccff",
    highlight = "|cffffcc00",
    warning = "|cffff6666",
    reset = "|r",
}

function SYL:Print(message)
    print(
        SYL.colors.addon
        .. "Show Us Your Loot:"
        .. SYL.colors.reset
        .. " "
        .. tostring(message)
    )
end

function SYL:DebugPrint(message)
    if ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.debug
    then
        print(
            SYL.colors.debug
            .. "[SYL Debug]"
            .. SYL.colors.reset
            .. " "
            .. tostring(message)
        )
    end
end

print("|cff33ff99Show Us Your Loot loaded!|r")
