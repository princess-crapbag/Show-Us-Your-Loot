-- Core/AltCommands.lua
--
-- The chat surface for alt mapping: /syl alts and its subcommands.
--
-- Split out rather than added to SlashCommands.lua or CommandReports.lua
-- because both are close to the project's 400 line limit, and because
-- detection (AltDetect) and identity (Players) are deliberately free of
-- anything that prints.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local AltCommands = {}
SYL.AltCommands = AltCommands

local function PrintUsage()
    SYL:Print("Alt mapping — who counts as the same person.")
    SYL:Write("  /syl alts            what is mapped now")
    SYL:Write("  /syl alts scan       read guild notes for suggestions")
    SYL:Write("  /syl alts apply      accept every suggestion")
    SYL:Write("  /syl alts set <alt> <main>")
    SYL:Write("  /syl alts clear <alt>")
end

-- Mappings change the due list retroactively, so the count is stated
-- wherever they are, not only where they are edited.
function AltCommands.ReportCurrent()
    local description = SYL.Players.DescribeMappings()

    if not description then
        SYL:Print(
            "No alts are mapped, so every character counts as its own "
            .. "person. Try /syl alts scan."
        )

        return
    end

    SYL:Print(description .. ".")

    local registry = SYL.Players.GetRegistry()
    local mains = {}

    for _, player in pairs(registry) do
        if player.mainGUID then
            mains[player.mainGUID] = true
        end
    end

    for mainGUID in pairs(mains) do
        local main = SYL.Players.Get(mainGUID)
        local names = {}

        for _, alt in ipairs(SYL.Players.GetAlts(mainGUID)) do
            local label = SYL.Players.SOURCE_LABELS[alt.identitySource]

            table.insert(
                names,
                (alt.name or "?")
                .. (label and (" (" .. label .. ")") or "")
            )
        end

        SYL:Write(
            "  " .. ((main and main.name) or "?")
            .. " <- " .. table.concat(names, ", ")
        )
    end
end

function AltCommands.ReportScan()
    if not SYL.Guild.IsInGuild() then
        SYL:Print("Not in a guild, so there are no notes to read.")

        return
    end

    local proposals = SYL.AltDetect.Scan()

    if #proposals == 0 then
        SYL:Print(
            "Nothing new in the guild notes. Mappings can still be set by "
            .. "hand with /syl alts set."
        )

        return
    end

    SYL:Print(
        #proposals
        .. (#proposals == 1 and " suggestion" or " suggestions")
        .. " from guild notes. Nothing has changed yet."
    )

    for _, proposal in ipairs(proposals) do
        SYL:Write("  " .. SYL.AltDetect.Describe(proposal))
    end

    SYL:Write(
        "Accept them all with /syl alts apply, or set them one at a time. "
        .. "Applying changes past numbers as well as future ones."
    )
end

function AltCommands.ApplyScan()
    if not SYL.Guild.IsInGuild() then
        SYL:Print("Not in a guild, so there are no notes to read.")

        return
    end

    local proposals = SYL.AltDetect.Scan()

    if #proposals == 0 then
        SYL:Print("Nothing to apply.")

        return
    end

    local applied, failed = SYL.AltDetect.ApplyAll(proposals)

    SYL:Print(
        applied
        .. (applied == 1 and " mapping" or " mappings")
        .. " applied"
        .. (failed > 0 and (", " .. failed .. " refused") or "")
        .. "."
    )

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

local function SplitTwo(remainder)
    local first, second =
        Utilities.Trim(remainder or ""):match("^(%S+)%s+(%S+)$")

    return first, second
end

function AltCommands.Set(remainder)
    local altName, mainName = SplitTwo(remainder)

    if not altName or not mainName then
        SYL:Print("Usage: /syl alts set <alt> <main>")

        return
    end

    -- Guild members are pulled in first so a main who has never raided is
    -- still a valid target.
    SYL.AltDetect.EnsureGuildMembers()

    local ok, message = SYL.Players.SetMain(
        altName, mainName, SYL.Players.MANUAL
    )

    SYL:Print(message)

    if ok and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

function AltCommands.Clear(remainder)
    local altName = Utilities.Trim(remainder or "")

    if altName == "" then
        SYL:Print("Usage: /syl alts clear <alt>")

        return
    end

    local ok, message = SYL.Players.ClearMain(altName)

    SYL:Print(message)

    if ok and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

local SUBCOMMANDS = {
    scan = AltCommands.ReportScan,
    apply = AltCommands.ApplyScan,
    set = AltCommands.Set,
    clear = AltCommands.Clear,
    help = PrintUsage,
}

function AltCommands.Handle(remainder)
    local subcommand, rest =
        (remainder or ""):match("^(%S*)%s*(.-)$")

    subcommand = string.lower(subcommand or "")

    if subcommand == "" then
        AltCommands.ReportCurrent()

        return
    end

    local handler = SUBCOMMANDS[subcommand]

    if handler then
        handler(rest)

        return
    end

    PrintUsage()
end
