-- Main.lua

local addonName, SYL = ...

_G.ShowUsYourLoot = SYL

SYL.name = addonName
SYL.version = "0.0.5"

function SYL:Print(message)
    print("|cff33ff99Show Us Your Loot:|r " .. tostring(message))
end

function SYL:DebugPrint(message)
    if ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.debug
    then
        print("|cff66ccff[SYL Debug]|r " .. tostring(message))
    end
end

print("|cff33ff99Show Us Your Loot loaded!|r")