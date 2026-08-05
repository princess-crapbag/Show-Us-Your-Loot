-- Main.lua
--
-- Addon entry point. Defines the shared addon table and the output helpers
-- every other file relies on. This file must load first.

local addonName, SYL = ...

_G.ShowUsYourLoot = SYL

SYL.name = addonName
SYL.version = "0.0.7"

SYL.colors = {
    addon = "|cff33ff99",
    debug = "|cff66ccff",
    highlight = "|cffffcc00",
    warning = "|cffff6666",
    reset = "|r",
}

-- Both helpers write through Core/Output.lua so a single setting can move
-- every addon message into a chat window of its own.
function SYL:Write(message)
    if SYL.Output and SYL.Output.Write then
        SYL.Output.Write(message)

        return
    end

    print(message)
end

function SYL:Print(message)
    SYL:Write(
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
        SYL:Write(
            SYL.colors.debug
            .. "[SYL Debug]"
            .. SYL.colors.reset
            .. " "
            .. tostring(message)
        )
    end
end

-- Printed before saved settings exist, so this one goes to the default
-- frame regardless of the chosen output window.
print("|cff33ff99Show Us Your Loot loaded!|r")
