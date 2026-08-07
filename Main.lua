-- Main.lua
--
-- Addon entry point. Defines the shared addon table and the output helpers
-- every other file relies on. This file must load first.

local addonName, SYL = ...

_G.ShowUsYourLoot = SYL

SYL.name = addonName

-- Read from the .toc rather than written here. Two copies drifted apart
-- almost immediately — this said 0.0.7 while the .toc said 0.0.9-alpha, and
-- the wrong one was being stamped onto every export by DataExport and
-- LootHistoryAPI, so saved data claimed to come from a version that never
-- produced it.
--
-- It also matters for releases: the packager rewrites the .toc's version from
-- the git tag when it builds the zip, so anything hardcoded here would ship
-- reporting whatever was last typed by hand.
local function ReadVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
        or _G.GetAddOnMetadata

    if not get then
        return "unknown"
    end

    local ok, value = pcall(get, addonName, "Version")

    if ok and type(value) == "string" and value ~= "" then
        return value
    end

    return "unknown"
end

SYL.version = ReadVersion()

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
