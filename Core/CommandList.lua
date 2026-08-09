-- Core/CommandList.lua
--
-- The catalogue of /syl commands, in the order they should be presented.
--
-- One list feeds both `/syl help` and the minimap menu, so the two can never
-- drift apart. Entries with an `argument` cannot simply be run: clicking them
-- opens the chat box prefilled instead, so the argument can be typed.
--
-- `common` marks the ones worth showing unprompted. There are twenty-nine
-- commands here and printing all of them was the response to any typo — a
-- wall of chat as punishment for a missing letter, in which the answer to
-- what you actually meant is impossible to find. `/syl help` shows the
-- common ones; `/syl help all` shows everything.

local SYL = _G.ShowUsYourLoot

local CommandList = {}
SYL.CommandList = CommandList

CommandList.ENTRIES = {
    { command = "", common = true, description = "Open the loot window" },
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
        common = true,
        description = "Per-player upgrades, drought and attendance",
    },
    {
        command = "raids",
        common = true,
        description = "Raid nights, kills and who was there",
    },
    {
        command = "roster",
        common = true,
        description = "Potential raiders, their classes and missing buffs",
    },
    {
        command = "alts",
        common = true,
        description = "Which characters count as the same person",
    },
    {
        command = "export",
        common = true,
        description = "Copyable raid night or season summary",
    },
    {
        command = "settings",
        common = true,
        description = "Settings, including which qualities to record",
    },
    {
        command = "due",
        common = true,
        description = "Who has gone longest without an upgrade",
    },
    {
        command = "tonight",
        common = true,
        description = "Summary of the raid night in progress",
    },
    {
        command = "bosses",
        common = true,
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

function CommandList.Help(remainder)
    local showAll = (remainder or ""):lower():find("all", 1, true) ~= nil

    SYL:Print(showAll and "Every command:" or "Commands:")

    local hidden = 0

    for _, entry in ipairs(CommandList.ENTRIES) do
        if showAll or entry.common then
            SYL:Write(
                CommandList.Format(entry)
                .. " — "
                .. entry.description
            )
        else
            hidden = hidden + 1
        end
    end

    if hidden > 0 then
        SYL:Write(
            "…and " .. hidden .. " more — /syl help all"
        )
    end
end

-- What to say when a command does not exist.
--
-- The whole catalogue used to be printed, which is twenty-nine lines of chat
-- in response to a typo, with the thing you meant somewhere inside it. Two
-- lines and a guess is more use.
function CommandList.UnknownCommand(command)
    SYL:Print("There is no /syl " .. tostring(command) .. ".")

    -- A prefix match catches the realistic mistake, which is stopping early
    -- or misremembering the ending rather than inventing a word.
    for _, entry in ipairs(CommandList.ENTRIES) do
        if entry.command ~= ""
            and entry.command:sub(1, #command) == command
        then
            SYL:Write(
                "Did you mean " .. CommandList.Format(entry) .. "?"
            )

            return
        end
    end

    SYL:Write("Type /syl help for the list.")
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
