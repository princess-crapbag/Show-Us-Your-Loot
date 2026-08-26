-- Core/CommandList.lua
--
-- The catalog of /syl commands, in the order they should be presented.
--
-- One list feeds `/syl help` and the command report in Core/CommandReports.lua,
-- so the two can never drift apart.
--
-- IT USED TO FEED A THIRD THING. UI/CommandMenu.lua drew every entry here as a
-- clickable row off the minimap button's right-click, and that file is gone --
-- the Tools tab in Settings draws the same commands as real buttons, with the
-- three awkward ones fixed on the way, and Aimee took the menu off so the right
-- button could drag the minimap icon instead: "they are all in the settings
-- now". What is left here is the catalog, which is still the single source of
-- what commands exist.
--
-- Two flags decide where an entry appears.
--
-- `common` marks the ones worth showing unprompted. Printing all of them was
-- the response to any typo — a wall of chat as punishment for a missing
-- letter, in which the answer to what you actually meant is impossible to
-- find. `/syl help` shows the common ones; `/syl help all` shows everything.
--
-- `developer` marks the ones that exist to inspect the addon rather than to
-- use it: the inspector window, the raw API dump, the debug toggle, the
-- output window cycle. They keep working when typed and are listed by
-- `/syl help all`, and they are kept off the Tools tab, which is somewhere a
-- person browses rather than somewhere they go on purpose.

local SYL = _G.ShowUsYourLoot

local CommandList = {}
SYL.CommandList = CommandList

CommandList.ENTRIES = {
    { command = "", common = true, description = "Open the loot window" },
    {
        command = "drops",
        description = "Recent group-loot drops with winners and rolls",
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
        description = "Who is owed loot — add 'window' for the old screen",
    },
    {
        command = "schedule",
        common = true,
        description = "Your raid days, the next night, and who is out",
    },
    {
        command = "out",
        common = true,
        description = "Mark somebody out — /syl out <name> [days] [reason]",
    },
    {
        command = "in",
        common = true,
        description = "Cancel an absence — /syl in <name>",
    },
    {
        command = "trade",
        common = true,
        description = "Reopen the trade window advisor for anything still open",
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
        command = "ask",
        common = true,
        description = "Ask whoever won something you rolled on",
    },
    {
        command = "sync",
        description = "Sync status — add 'backfill' to ask for missing roll lists",
    },
    {
        command = "theme",
        description = "Change the color scheme",
    },
    {
        developer = true,
        command = "output",
        description = "Send addon messages to the next chat window",
    },
    {
        command = "resetwindows",
        description = "Put windows and the minimap button back",
    },
    { command = "capture", description = "Toggle Loot History capture" },
    { developer = true, command = "dev", description = "Open the developer window" },
    { developer = true, command = "api", description = "Print the live Loot History API" },
    { developer = true, command = "debug", description = "Toggle debug messages" },
    { command = "announce", description = "Toggle capture messages" },
    {
        command = "link",
        argument = "add|remove NAME URL",
        description = "The links shown on the dashboard",
    },
    {
        command = "keys",
        description = "Mythic+ keystones on this account",
    },
    {
        command = "addraider",
        argument = "NAME-REALM CLASS",
        description = "Add someone joining the guild to the roster",
    },
    {
        command = "dropraider",
        argument = "NAME-REALM",
        description = "Remove someone from the joining list",
    },
    {
        command = "scope",
        description = "Show the raid team, the guild, or everyone",
    },
    -- THE ARGUMENT IS THE GUARD, and it outlived the thing it was guarding
    -- against. A menu of clickable rows once ran anything without an argument
    -- on the press, so this emptied a season on one click, with no confirm and
    -- no undo, from a list somebody was browsing. That menu is gone and the
    -- Tools tab sends `clear` to a dialog that will not act until the season's
    -- name is typed -- but the word stays required, because COMMANDS.clear
    -- refuses without it and a typed command is still a way in.
    {
        command = "clear",
        argument = "confirm",
        description = "Clear active-season drops and loot",
    },
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
-- The whole catalog used to be printed, which is twenty-nine lines of chat
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

