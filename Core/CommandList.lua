-- Core/CommandList.lua
--
-- The catalogue of /syl commands, in the order they should be presented.
--
-- One list feeds both `/syl help` and the minimap menu, so the two can never
-- drift apart. Entries with an `argument` cannot simply be run: clicking them
-- opens the chat box prefilled instead, so the argument can be typed.

local SYL = _G.ShowUsYourLoot

local CommandList = {}
SYL.CommandList = CommandList

CommandList.ENTRIES = {
    { command = "", description = "Open the loot window" },
    {
        command = "drops",
        description = "Recent group-loot drops with winners and rolls",
    },
    { command = "recent", description = "Recent chat-captured loot" },
    { command = "count", description = "Active and all-time totals" },
    {
        command = "player",
        argument = "NAME",
        description = "Active-season loot for one player",
    },
    { command = "season", description = "Active-season information" },
    {
        command = "rename",
        argument = "NAME",
        description = "Rename the active season",
    },
    {
        command = "archive",
        argument = "NEW SEASON NAME",
        description = "Archive this season and start a new one",
    },
    { command = "archives", description = "List archived seasons" },
    {
        command = "players",
        description = "Per-player upgrades, drought and attendance",
    },
    {
        command = "raids",
        description = "Raid nights, kills and who was there",
    },
    {
        command = "roster",
        description = "Potential raiders, their classes and missing buffs",
    },
    {
        command = "alts",
        description = "Which characters count as the same person",
    },
    {
        command = "export",
        description = "Copyable raid night or season summary",
    },
    {
        command = "settings",
        description = "Settings, including which qualities to record",
    },
    {
        command = "due",
        description = "Who has gone longest without an upgrade",
    },
    {
        command = "tonight",
        description = "Summary of the raid night in progress",
    },
    {
        command = "bosses",
        description = "Kills, pulls and drops for every boss",
    },
    {
        command = "sync",
        description = "Officer sync status and where drops came from",
    },
    {
        command = "theme",
        description = "Change the colour scheme",
    },
    {
        command = "output",
        description = "Send addon messages to the next chat window",
    },
    {
        command = "resetwindows",
        description = "Put every window back to its default size and centre",
    },
    { command = "capture", description = "Toggle Loot History capture" },
    {
        command = "personalloot",
        description = "Count gear taken without a roll towards droughts",
    },
    { command = "dev", description = "Open the developer window" },
    { command = "api", description = "Print the live Loot History API" },
    { command = "debug", description = "Toggle debug messages" },
    { command = "announce", description = "Toggle capture messages" },
    { command = "clear", description = "Clear active-season drops and loot" },
}

function CommandList.Format(entry)
    local text = "/syl"

    if entry.command ~= "" then
        text = text .. " " .. entry.command
    end

    if entry.argument then
        text = text .. " " .. entry.argument
    end

    return text
end

-- Commands that take an argument prefill the chat box rather than running,
-- because there is nothing sensible to run them with.
function CommandList.Run(entry)
    if entry.argument then
        local prefill = "/syl " .. entry.command .. " "

        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(prefill)
        else
            SYL:Print("Type: " .. prefill)
        end

        return
    end

    SlashCmdList["SHOWUSYOURLOOT"](entry.command)
end
