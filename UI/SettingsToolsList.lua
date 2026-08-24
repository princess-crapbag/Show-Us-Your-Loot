-- UI/SettingsToolsList.lua
--
-- WHAT the Tools tab lists, and what each row does when pressed.
-- UI/SettingsTools.lua is HOW it is drawn.
--
-- Split for the reason the size limit exists and the reason HANDOFF.md gives
-- for splitting a panel: the catalog is a table that will grow every time a
-- command is added, and the layout is arithmetic that will not. One file
-- holding both crossed 400 lines the day it was written.
--
-- THIS LIST IS NOT Core/CommandList.ENTRIES, and it must not be made into a
-- walk over it. Four traps are the reason -- see the header in
-- UI/SettingsTools.lua for all of them, and the `run` on each entry below for
-- which one it answers. The short version: three commands open the wrong
-- thing when run by name, one has no click door at all, one destroys a season
-- and is deliberately absent, and ENTRIES is not the whole command surface
-- anyway.

local SYL = _G.ShowUsYourLoot

local SettingsToolsList = {}
SYL.SettingsToolsList = SettingsToolsList

local function Command(text)
    return function()
        SlashCmdList["SHOWUSYOURLOOT"](text)
    end
end

-- Opens the MAIN WINDOW on a tab, which is the fix for the first trap above.
local function Tab(mode)
    return function()
        SYL:OpenMainWindowAt(mode)
    end
end

local function Dialog(name)
    return function()
        local dialog = SYL[name]

        if dialog and dialog.Show then
            dialog.Show()
        end
    end
end

-- THE SCOPE ROW. It cycles raid team / guild / everyone, which is what the
-- command does, and its label says which of the three is in force -- because
-- a control that changes a setting without showing the setting is one you
-- press twice to find out where you started.
local function ScopeLabel()
    return "Who the boards show: " .. SYL.Audience.Label(SYL.Audience.Get())
end

SettingsToolsList.GROUPS = {
    {
        title = "OPEN A SCREEN",
        entries = {
            -- FIRST, and it was in none of the 34 with a door of its own.
            -- The Raiders board is the headline screen of this addon and the
            -- only way to it was the tab strip on a window you already had
            -- open.
            {
                label = "Raiders board",
                run = Tab("raiders"),
                note = "The fairness board: share, drought and attendance.",
            },
            {
                label = "Players",
                run = Command("players"),
                note = "Per-player upgrades, drought and attendance, in a "
                    .. "window of its own. The Export button lives here.",
            },
            {
                label = "Raid nights",
                run = Command("raids"),
                note = "Raid nights, kills and who was there.",
            },
            {
                -- `due` prints unless you append `window`. See the header.
                label = "Who is due",
                run = Command("due window"),
                note = "Who is owed loot, on screen rather than in chat.",
            },
            {
                -- The tab, not UI/BossWindow.lua. See the header.
                label = "Bosses",
                run = Tab("bosses"),
                note = "Kills, pulls and drops for every boss.",
            },
            {
                -- Deliberately NOT called "Roster": this is the standalone
                -- window with search, buff coverage and recruits, and it is
                -- a different screen from the Raiders board above.
                label = "Full roster",
                run = Command("roster"),
                note = "Search, raid buff coverage, and who is joining.",
            },
            {
                label = "Schedule",
                run = Command("schedule"),
                note = "Your raid days, the next night, and who is out.",
            },
            {
                label = "Keystones",
                run = Tab("keys"),
                note = "Mythic+ keystones and dungeon lockouts.",
            },
            {
                -- BUG FIXED BY THIS ROW. Export's only button in the whole
                -- addon was inside UI/PlayerWindow.lua, which is itself
                -- reachable only by typing /syl players -- so a feature with
                -- a button had no door.
                label = "Export for Discord",
                run = Command("export"),
                note = "A copyable raid night or season summary to paste "
                    .. "into Discord.",
            },
        },
    },

    {
        title = "THIS SEASON",
        entries = {
            {
                label = "Season status",
                run = Command("season"),
                note = "What the active season is called and what is in it.",
            },
            {
                label = "Rename season",
                needsInput = true,
                run = Dialog("SeasonRenameDialog"),
                note = "Change what the season running now is called. "
                    .. "Nothing recorded in it changes.",
            },
            {
                label = "Archive and start new",
                needsInput = true,
                run = Dialog("ArchivePopup"),
                note = "Keeps everything recorded so far and starts a fresh "
                    .. "season beside it. This is what to use when a tier "
                    .. "ends.",
            },
            {
                label = "Archived seasons",
                run = Tab("archives"),
                note = "Every season you have archived.",
            },
        },
    },

    {
        title = "PEOPLE",
        entries = {
            {
                -- The Calendar panel, because UI/AbsenceControls.lua is
                -- already there with a name box and suggestions. Prefilling
                -- chat would be a worse version of a screen that exists.
                label = "Mark somebody out",
                needsInput = true,
                run = Tab("nights"),
                note = "Opens the Calendar, where absences are set and "
                    .. "cleared.",
            },
            {
                label = "Cancel an absence",
                needsInput = true,
                run = Tab("nights"),
                note = "Opens the Calendar. Absences are removed on the same "
                    .. "screen they are set on.",
            },
            {
                label = "Alts and mains",
                run = Command("alts"),
                note = "Which characters count as the same person.",
            },
            {
                label = "Add a recruit",
                needsInput = true,
                run = function()
                    SYL.NamePromptDialog.Show({
                        title = "ADD A RECRUIT",
                        accept = "Add",

                        body = "Somebody joining the guild who is not in it "
                            .. "yet, so raid buff coverage can see them "
                            .. "before they arrive.\n\nType their full name "
                            .. "and their class, like this:\n\n"
                            .. "Arcangela-Area52 MAGE",

                        empty = "Type a name and a class, like "
                            .. "Arcangela-Area52 MAGE.",

                        onAccept = function(typed)
                            SlashCmdList["SHOWUSYOURLOOT"]("addraider " .. typed)

                            return true
                        end,
                    })
                end,
                note = "The client cannot look up a character it has never "
                    .. "seen, which is why this needs the realm and the "
                    .. "class typed.",
            },
            {
                label = "Remove a recruit",
                needsInput = true,
                run = function()
                    SYL.NamePromptDialog.Show({
                        title = "REMOVE A RECRUIT",
                        accept = "Remove",

                        body = "Takes somebody off the joining list.\n\nType "
                            .. "their full name, like this:\n\n"
                            .. "Arcangela-Area52",

                        empty = "Type a name, like Arcangela-Area52.",

                        onAccept = function(typed)
                            SlashCmdList["SHOWUSYOURLOOT"](
                                "dropraider " .. typed
                            )

                            return true
                        end,
                    })
                end,
                note = "This only removes somebody who was added by hand. "
                    .. "Real guild members come from the guild roster.",
            },
            {
                -- The command with no click door anywhere. See the header.
                label = ScopeLabel,
                run = Command("scope"),
                note = "Raid team, guild, or everyone. The due list and the "
                    .. "players window both read this. Click to cycle.",
            },
        },
    },

    {
        title = "SHARING AND TRADES",
        entries = {
            {
                label = "Sync status",
                run = Command("sync"),
                note = "What officer sync has sent and received.",
            },
            {
                label = "Trade advisor",
                run = Command("trade"),
                note = "Reopens the advisor for anything still open.",
            },
            {
                -- Left on the chat prefill deliberately: the argument is
                -- `add|remove NAME URL`, three values, and one name box
                -- cannot ask for that honestly.
                label = "Dashboard links",
                needsInput = true,
                run = Command("link"),
                note = "The links shown on the dashboard. This one opens "
                    .. "chat, because it needs a name and a web address.",
            },
        },
    },

    {
        title = "REPORTS IN CHAT",
        entries = {
            {
                label = "Recent drops",
                run = Command("drops"),
                note = "Recent group-loot drops with winners and rolls.",
            },
            {
                label = "Tonight so far",
                run = Command("tonight"),
                note = "A summary of the raid night in progress.",
            },
            {
                label = "Command list",
                run = Command("help all"),
                note = "Every /syl command, printed to chat.",
            },
        },
    },
}

