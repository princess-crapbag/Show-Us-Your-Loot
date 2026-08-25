-- Core/SlashCommands.lua
--
-- Parses /syl input and dispatches it. Each handler stays short and delegates
-- the real work: chat output to Core/CommandReports.lua, everything else to
-- the module that owns it.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities
local Reports = SYL.CommandReports

local RECENT_LIMIT = Reports.RECENT_LIMIT

-- Ten fits a raid roster without scrolling chat off the screen.
local DUE_LIMIT = 10

local COMMANDS = {}

COMMANDS.help = SYL.CommandList.Help
COMMANDS.season = Reports.SeasonStatus
COMMANDS.archives = function(remainder)
    local word, rest =
        Utilities.Trim(remainder or ""):match("^(%S*)%s*(.*)$")

    if word == "rename" then
        return COMMANDS.archive_rename(rest)
    end

    if word == "merge" then
        return COMMANDS.archive_merge(rest)
    end

    return Reports.Archives()
end
COMMANDS.api = Reports.APIReport
COMMANDS.drops = function()
    Reports.Drops(RECENT_LIMIT)
end

-- Renaming and merging archives, by their number on /syl archives. The list is
-- numbered there for exactly this reason: an archive has no other handle a
-- person can type, and two seasons can share a name — which is most of why
-- somebody is renaming one.
COMMANDS.archive_rename = function(remainder)
    local index, name =
        Utilities.Trim(remainder or ""):match("^(%d+)%s+(.+)$")

    if not index then
        SYL:Print("Usage: /syl archives rename <number> <new name>")
        SYL:Write("  The number is the one beside it in /syl archives.")

        return
    end

    local ok, message = SYL.RenameArchive(tonumber(index), name)

    SYL:Print(message)

    if ok and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

COMMANDS.archive_merge = function(remainder)
    local text = Utilities.Trim(remainder or "")
    local numbers, name = text:match("^([%d%s]+)(.*)$")

    local indexes = {}

    for digits in tostring(numbers or ""):gmatch("%d+") do
        table.insert(indexes, tonumber(digits))
    end

    if #indexes < 2 then
        SYL:Print("Usage: /syl archives merge <number> <number> [new name]")
        SYL:Write(
            "  Folds them into one season. Nothing is deleted, but which "
            .. "season each record came from cannot be recovered afterwards."
        )

        return
    end

    local ok, message = SYL.MergeArchives(indexes, name)

    SYL:Print(message)

    if ok and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

COMMANDS.rename = function(remainder)
    local success, errorMessage = SYL.RenameActiveSeason(remainder)

    if success then
        SYL:Print(
            "Active season renamed to: "
            .. SYL.GetActiveSeason().name
        )
    else
        SYL:Print(errorMessage)
    end
end

COMMANDS.archive = function(remainder)
    local newSeasonName = Utilities.Trim(remainder)

    if not newSeasonName or newSeasonName == "" then
        newSeasonName = "New Season"
    end

    local archivedSeason, newSeason =
        SYL.ArchiveCurrentSeason(newSeasonName)

    if not archivedSeason then
        SYL:Print(newSeason or "Archive failed.")
        return
    end

    SYL:Print(
        "Archived "
        .. archivedSeason.name
        .. " with "
        .. #(archivedSeason.drops or {})
        .. " drops and "
        .. #(archivedSeason.loot or {})
        .. " loot records."
    )

    SYL:Write("New active season: " .. newSeason.name)

    SYL.LootHistoryStore.RebuildIndex()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

COMMANDS.players = function()
    if SYL.OpenPlayerWindow then
        SYL:OpenPlayerWindow()
    end
end

COMMANDS.raids = function()
    if SYL.OpenRaidWindow then
        SYL:OpenRaidWindow()
    end
end

COMMANDS.roster = function()
    if SYL.OpenRosterWindow then
        SYL:OpenRosterWindow()
    end
end

-- `/syl due` still prints. `/syl due window` opens the standalone window.
--
-- The Raiders tab is the board version of this list and is where it is meant
-- to be read now, which left UI/DueWindow.lua with no caller at all — and an
-- unreachable window that still loads is the exact fault emptying the footer
-- caused once already. Kept reachable rather than deleted: the window has a
-- recency toggle the board does not, so whether it is really superseded is
-- Aimee's call and not one to take by quietly removing the last door to it.
COMMANDS.due = function(remainder)
    if SYL.Utilities.Trim(remainder or "") == "window" then
        if SYL.OpenDueWindow then
            SYL:OpenDueWindow()
        end

        return
    end

    Reports.Due(DUE_LIMIT)
end

COMMANDS.schedule = function(remainder)
    SYL.ScheduleCommands.Schedule(remainder)
end

COMMANDS.out = function(remainder)
    SYL.ScheduleCommands.Out(remainder)
end

COMMANDS["in"] = function(remainder)
    SYL.ScheduleCommands.Back(remainder)
end

COMMANDS.ask = function()
    if not SYL.LootAsk.IsEnabled() then
        SYL:Write(
            "Asking for what you lost is switched off in Settings, under "
            .. "Features."
        )

        return
    end

    if not SYL.LootAskPanel.HasAnything() then
        SYL:Write(
            "Nothing you rolled on is still inside its trade window. This "
            .. "opens by itself when somebody else wins something you can "
            .. "still be given."
        )

        return
    end

    SYL.LootAskPanel.Show()
end

COMMANDS.trade = function()
    if not SYL.TradeAdvisor.IsEnabled() then
        SYL:Write("The trade window advisor is switched off in Settings.")

        return
    end

    if not SYL.TradeAdvisorPanel.HasAnything() then
        SYL:Write(
            "Nothing is inside its trade window. This opens by itself when "
            .. "you win something."
        )

        return
    end

    SYL.TradeAdvisorPanel.Show()
end

COMMANDS.tonight = function()
    SYL.RaidSummary.ReportCurrent()
end

COMMANDS.sync = function(remainder)
    if SYL.Utilities.Trim(remainder or "") == "backfill" then
        if not SYL.Sync.IsEnabled() then
            SYL:Write("Officer sync is switched off in Settings.")

            return
        end

        local asked = SYL.SyncRolls.RequestBackfill()

        SYL:Write(asked == 0
            and "Nothing to backfill — every drop here has its roll list."
            or ("Asked the raid for roll lists on " .. asked
                .. (asked == 1 and " drop." or " drops.")
                .. " Anybody who captured them will answer."))

        return
    end

    SYL.Sync.ReportStatus()
end

COMMANDS.alts = function(remainder)
    SYL.AltCommands.Handle(remainder)
end

-- The way back from a window dragged past the edge of the screen, where the
-- grip that would shrink it is off the monitor with it.
COMMANDS.resetwindows = function()
    local reset = SYL.Widgets.ResetSizes()

    -- The minimap button comes with them. It can be dragged anywhere on the
    -- screen now, which means it can be dragged somewhere it cannot be seen
    -- or clicked, and this is the way back. Nothing else in the addon is a
    -- more obvious place to look for it than the command that puts things
    -- back where they started.
    SYL.MinimapButton.ResetPosition()

    -- Saved sizes are cleared either way. Only windows opened this session
    -- can be resized on the spot, so zero is a normal answer rather than a
    -- failure, and saying so stops it reading as one.
    if reset == 0 then
        SYL:Print(
            "Saved window sizes and positions cleared. Every window will open "
            .. "at its default size, in the middle of the screen. The minimap "
            .. "button is back on the ring."
        )

        return
    end

    SYL:Print(
        SYL.Utilities.Count(reset, "open window")
        .. " put back to the default size and centered, and the minimap "
        .. "button is back on the ring. Saved sizes and positions cleared."
    )
end

COMMANDS.bosses = function()
    if SYL.OpenBossWindow then
        SYL:OpenBossWindow()
    end
end

COMMANDS.export = function()
    if SYL.OpenExportWindow then
        SYL:OpenExportWindow()
    end
end

COMMANDS.settings = function()
    if SYL.OpenSettingsWindow then
        SYL:OpenSettingsWindow()
    end
end

COMMANDS.dev = function()
    if not SYL.Features.IsEnabled("developer") then
        SYL:Print(
            "Developer tools are off. Turn them on in Settings, under "
            .. "Features."
        )

        return
    end

    -- Capture runs on its own; this only opens the inspector window.
    if not SYL.LootHistory.IsEnabled() then
        SYL:Print(
            "Loot History capture is off, so the inspector will stay empty. "
            .. "Turn it on with /syl capture."
        )
    end

    if SYL.OpenDeveloperWindow then
        SYL:OpenDeveloperWindow()
    end
end

-- With a name, jumps straight to that scheme; without one, cycles. Cycling
-- is the useful default, since choosing a color is a matter of looking at it
-- rather than knowing what it is called.
COMMANDS.theme = function(argument)
    local requested = argument and argument:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local palette

    if requested and requested ~= "" then
        palette = SYL.Palettes.Get(requested)

        if not palette then
            local names = {}

            for _, entry in ipairs(SYL.Palettes.list) do
                names[#names + 1] = entry.key
            end

            SYL:Print(
                "No color scheme called \"" .. requested .. "\". Try: "
                .. table.concat(names, ", ") .. "."
            )

            return
        end

        palette = SYL.Theme.Apply(palette.key)
    else
        palette = SYL.Theme.Apply(SYL.Palettes.Next(SYL.Theme.paletteKey))
    end

    SYL:Print("Color scheme: " .. palette.name .. " — " .. palette.note .. ".")
end

COMMANDS.output = function()
    local name = SYL.Output.CycleWindow()

    -- Printed after the switch, so it lands in the window just chosen and
    -- proves where messages will appear.
    SYL:Print("Messages now go to the \"" .. tostring(name) .. "\" window.")
end

COMMANDS.capture = function()
    local settings = ShowUsYourLootDB.settings

    settings.lootHistoryCapture = not settings.lootHistoryCapture

    if settings.lootHistoryCapture then
        local registeredCount = SYL.LootHistory.Enable()

        SYL:Print(
            "Loot History capture enabled — watching "
            .. tostring(registeredCount)
            .. " events."
        )
    else
        SYL.LootHistory.Disable()

        SYL:Print(
            "Loot History capture disabled. Chat capture still records loot."
        )
    end
end

COMMANDS.debug = function()
    local settings = ShowUsYourLootDB.settings

    settings.debug = not settings.debug

    SYL:Print(
        "Debug messages "
        .. (settings.debug and "enabled." or "disabled.")
    )
end

COMMANDS.announce = function()
    local settings = ShowUsYourLootDB.settings

    settings.announceCaptures = not settings.announceCaptures

    SYL:Print(
        "Capture announcements "
        .. (settings.announceCaptures and "enabled." or "disabled.")
    )
end

-- Cycles raid team, guild, everyone. The same setting the due and players
-- windows read, so changing it here moves both.
COMMANDS.scope = function()
    local scope = SYL.Audience.Cycle()

    SYL:Print(
        "Showing " .. SYL.Audience.Note(scope) .. "."
    )

    if scope == "team" and SYL.RaidTeam.Count() == 0 then
        SYL:Write(
            "  Nobody is marked as being on the team yet, so this will look "
            .. "empty. Open the roster and tick the TEAM column."
        )
    end
end

-- Somebody who is joining but is not in the guild yet, so buff coverage can
-- see them before they arrive. Name-Realm and a class, because the client
-- cannot look up a character it has never seen.
COMMANDS.addraider = function(remainder)
    local text = Utilities.Trim(remainder) or ""

    -- The class is the last word; everything before it is the character, so a
    -- realm with a space in it survives being typed the way people write it.
    local fullName, class = text:match("^(.-)%s+(%S+)$")

    if not fullName then
        SYL:Print("Usage: /syl addraider Name-Realm CLASS")
        SYL:Write("  For example: /syl addraider Aimee-Silvermoon mage")

        return
    end

    local entry, message = SYL.IncomingRoster.Add(fullName, class)

    SYL:Print(message)

    if entry then
        SYL.RosterData.Invalidate()

        if SYL.RefreshRosterWindow then
            SYL:RefreshRosterWindow()
        end
    end
end

COMMANDS.dropraider = function(remainder)
    local fullName = Utilities.Trim(remainder) or ""

    if fullName == "" then
        SYL:Print("Usage: /syl dropraider Name-Realm")

        return
    end

    if SYL.IncomingRoster.Remove(fullName) then
        SYL:Print("Removed " .. fullName .. " from the joining list.")

        SYL.RosterData.Invalidate()

        if SYL.RefreshRosterWindow then
            SYL:RefreshRosterWindow()
        end
    else
        SYL:Print(
            "No one on the joining list called " .. fullName
            .. ". They are listed by /syl roster, marked Joining."
        )
    end
end

-- What this account's characters are holding. Only ever this account's:
-- an addon cannot read anybody else's bags. See Core/Keystone.lua.
COMMANDS.keys = function()
    -- The Keys tab is a real screen now, and it is where requests are
    -- answered. Printing to chat instead would make the notification's own
    -- instruction ("/syl keys to answer") a dead end.
    if SYL.OpenMainWindowAt then
        SYL:OpenMainWindowAt("keys")

        return
    end

    if not SYL.Keystone.IsAvailable() then
        SYL:Print("This client does not expose the Mythic+ keystone API.")

        return
    end

    -- Re-read before reporting, so the answer is current rather than whatever
    -- was true at login.
    SYL.Keystone.Update()

    local entries = SYL.Keystone.List()

    if #entries == 0 then
        SYL:Print("No keystones recorded yet on this account.")

        return
    end

    SYL:Print("Keystones on this account:")

    for _, entry in ipairs(entries) do
        SYL:Write(
            "  " .. tostring(entry.name)
            .. " — " .. SYL.Keystone.Describe(entry)
        )
    end

    local guild = SYL.KeystoneSync.List()

    if #guild > 0 then
        SYL:Write("Guild keys, from officers running the addon:")

        for _, entry in ipairs(guild) do
            SYL:Write(
                "  " .. tostring(entry.name)
                .. " — " .. SYL.Keystone.Describe(entry)
            )
        end
    elseif SYL.KeystoneSync.IsEnabled() then
        SYL:Write(
            "  Nobody else has sent a key yet. They need this addon with key "
            .. "sharing on — nothing can read another player's bags."
        )
    else
        SYL:Write(
            "  Key sharing is off, so this is your account only. Turn it on "
            .. "in Settings under Features to see your guild's keys."
        )
    end
end

-- Core/Links.lua told people to type this in two error messages and the
-- dashboard tile told them a third time, and it did not exist. Adding the
-- command is the honest fix: the messages were describing the right thing.
COMMANDS.link = function(remainder)
    local text = SYL.Utilities.Trim(remainder) or ""
    local verb, rest = text:match("^(%S+)%s*(.-)$")

    verb = verb and verb:lower() or ""

    if verb == "add" then
        -- The URL is the last word; everything before it is the name, so
        -- "Guild Discord https://…" works without quoting.
        local label, url = rest:match("^(.-)%s+(%S+)$")

        if not label then
            label, url = rest, ""
        end

        local entry, message = SYL.Links.Add(label, url)

        SYL:Print(message)

        if entry and SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end

        return
    end

    if verb == "remove" then
        if SYL.Links.Remove(rest) then
            SYL:Print("Removed " .. rest .. ".")

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end
        else
            SYL:Print("No link called " .. tostring(rest) .. ".")
        end

        return
    end

    local links = SYL.Links.List()

    SYL:Print(#links .. " link(s):")

    for _, link in ipairs(links) do
        SYL:Write(
            "  " .. tostring(link.label)
            .. ((link.url or "") ~= "" and (" — " .. link.url) or " — no address yet")
        )
    end

    SYL:Write("  /syl link add <name> <url>  ·  /syl link remove <name>")
end

-- Refuses without the word. This is the only command in the addon that
-- destroys a season's worth of recording, it cannot be undone, and it was
-- reachable in one click from the minimap menu — see the entry in
-- Core/CommandList.lua for how that happened. Saying what would go before it
-- goes is the other half: a count is the only thing that tells somebody
-- whether they are about to lose a night or a tier.
COMMANDS.clear = function(argument)
    local activeSeason = SYL.GetActiveSeason()

    local clearedDrops = #(activeSeason.drops or {})
    local clearedLoot = #(activeSeason.loot or {})

    if string.lower(argument or "") ~= "confirm" then
        SYL:Print(
            "This would remove "
            .. clearedDrops
            .. " drops and "
            .. clearedLoot
            .. " chat items from the active season, and cannot be undone. "
            .. "Type /syl clear confirm if that is what you want. "
            .. "To keep the records and start a new tier instead, archive the "
            .. "season from the Archives tab."
        )

        return
    end

    activeSeason.loot = {}
    activeSeason.drops = {}

    ShowUsYourLootDB.recentRecordIDs = {}

    SYL.LootHistoryStore.RebuildIndex()

    -- Emptying a season on purpose is the one legitimate way for the totals
    -- to fall. Recorded account-wide, not just re-stamped here: the stamp is
    -- per character, so stamping alone would leave every OTHER character
    -- reporting data loss on its next login.
    SYL.Recovery.NoteDeliberateClear()

    SYL:Print(
        "Active season cleared: "
        .. clearedDrops
        .. " drops and "
        .. clearedLoot
        .. " chat items removed. Archived seasons are untouched."
    )

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

SLASH_SHOWUSYOURLOOT1 = "/syl"

SlashCmdList["SHOWUSYOURLOOT"] = function(input)
    input = input or ""

    local command, remainder = input:match("^(%S*)%s*(.-)$")

    command = string.lower(command or "")
    remainder = remainder or ""

    if command == "" then
        if SYL.OpenMainWindow then
            SYL:OpenMainWindow()
        end

        return
    end

    local handler = COMMANDS[command]

    if handler then
        handler(remainder)
        return
    end

    SYL.CommandList.UnknownCommand(command)
end
