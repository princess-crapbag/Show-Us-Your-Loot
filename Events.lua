-- Events.lua

local SYL = _G.ShowUsYourLoot

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("PLAYER_LOGIN")

local ADDON_NAME = "ShowUsYourLoot"

local function GetPlayerFullName()
    local name, realm = UnitFullName("player")

    if not name then
        return "Unknown"
    end

    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

local function NormalizePlayerName(name)
    if not name or name == "" then
        return "Unknown"
    end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    name = name:gsub("[%.,:]+$", "")

    return name
end

local function GetLocationInformation()
    local zoneName =
        GetRealZoneText()
        or GetZoneText()
        or "Unknown"

    local instanceName,
        instanceType,
        difficultyID,
        difficultyName,
        maxPlayers,
        dynamicDifficulty,
        isDynamic,
        instanceID,
        instanceGroupSize =
        GetInstanceInfo()

    local inInstance =
        select(1, IsInInstance())

    return {
        zoneName = zoneName,
        instanceName = instanceName or zoneName,
        instanceType = instanceType or "none",
        difficultyID = difficultyID or 0,
        difficultyName = difficultyName or "None",
        maxPlayers = maxPlayers or 0,
        instanceID = instanceID or 0,
        instanceGroupSize = instanceGroupSize or 0,
        inInstance = inInstance or false,
        inRaidGroup = IsInRaid(),
        inGroup = IsInGroup(),
    }
end

local function ExtractItemInformation(message)
    local itemLink =
        message:match("(|Hitem:.-|h%[.-%]|h)")

    if not itemLink then
        return nil
    end

    local itemID =
        tonumber(itemLink:match("|Hitem:(%d+)"))

    local itemName =
        itemLink:match("%[(.-)%]")

    local quantity =
        tonumber(message:match("|h|r?x(%d+)"))
        or tonumber(message:match("|h x(%d+)"))
        or tonumber(message:match("x(%d+)%p?$"))
        or 1

    return {
        itemLink = itemLink,
        itemID = itemID,
        itemName = itemName,
        quantity = quantity,
    }
end

local function DetermineRecipient(message)
    if message:find("^You ") then
        return GetPlayerFullName()
    end

    local recipient =
        message:match("^(.+) receives loot:")
        or message:match("^(.+) receives item:")
        or message:match(
            "^(.+) receives bonus loot:"
        )

    return NormalizePlayerName(recipient)
end

local function CreateRecordID(
    recipient,
    itemID,
    timestamp,
    rawMessage
)
    local timeBucket =
        math.floor(timestamp / 2)

    return table.concat({
        tostring(recipient or "Unknown"),
        tostring(itemID or 0),
        tostring(timeBucket),
        tostring(rawMessage or ""),
    }, "|")
end

local function CleanRecentRecordIDs()
    ShowUsYourLootDB.recentRecordIDs =
        ShowUsYourLootDB.recentRecordIDs or {}

    local cutoff = time() - 30

    for recordID, recordedAt in pairs(
        ShowUsYourLootDB.recentRecordIDs
    ) do
        if recordedAt < cutoff then
            ShowUsYourLootDB
                .recentRecordIDs[recordID] = nil
        end
    end
end

local function IsDuplicate(recordID)
    ShowUsYourLootDB.recentRecordIDs =
        ShowUsYourLootDB.recentRecordIDs or {}

    if ShowUsYourLootDB
        .recentRecordIDs[recordID]
    then
        return true
    end

    ShowUsYourLootDB
        .recentRecordIDs[recordID] = time()

    return false
end

local function SaveLootMessage(message)
    local item =
        ExtractItemInformation(message)

    if not item then
        SYL:DebugPrint(
            "Ignored message without an item link: "
            .. tostring(message)
        )

        return
    end

    local activeSeason =
        SYL.GetActiveSeason()

    if not activeSeason then
        SYL:Print(
            "Could not save loot because no active season exists."
        )

        return
    end

    local recipient =
        DetermineRecipient(message)

    local timestamp = time()
    local location =
        GetLocationInformation()

    local recordID =
        CreateRecordID(
            recipient,
            item.itemID,
            timestamp,
            message
        )

    CleanRecentRecordIDs()

    if IsDuplicate(recordID) then
        SYL:DebugPrint(
            "Duplicate ignored: "
            .. tostring(message)
        )

        return
    end

    local record = {
        id = recordID,

        seasonID = activeSeason.id,
        seasonName = activeSeason.name,

        recipient = recipient,

        itemLink = item.itemLink,
        itemID = item.itemID,
        itemName = item.itemName,
        quantity = item.quantity,

        timestamp = timestamp,
        dateText = date(
            "%Y-%m-%d",
            timestamp
        ),
        timeText = date(
            "%H:%M:%S",
            timestamp
        ),

        recordedBy =
            GetPlayerFullName(),

        zoneName =
            location.zoneName,

        instanceName =
            location.instanceName,

        instanceType =
            location.instanceType,

        instanceID =
            location.instanceID,

        difficultyID =
            location.difficultyID,

        difficultyName =
            location.difficultyName,

        maxPlayers =
            location.maxPlayers,

        instanceGroupSize =
            location.instanceGroupSize,

        inInstance =
            location.inInstance,

        inRaidGroup =
            location.inRaidGroup,

        inGroup =
            location.inGroup,

        archived = false,
        excludedFromAnalytics = false,

        rawMessage = message,
    }

    table.insert(
        activeSeason.loot,
        record
    )

    -- Maintain compatibility with existing UI.
    ShowUsYourLootDB.loot =
        activeSeason.loot

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    if ShowUsYourLootDB
        .settings
        .announceCaptures
    then
        print(
            "|cffffcc00[SYL]|r Recorded "
            .. record.itemLink
            .. " for |cff33ff99"
            .. record.recipient
            .. "|r"
        )
    end
end

local function PrintRecentLoot(limit)
    local records =
        SYL.GetActiveLoot()

    local count = #records

    SYL:Print(
        "Active-season item records: "
        .. count
    )

    if count == 0 then
        print(
            "No item loot has been recorded in this season."
        )

        return
    end

    local startIndex =
        math.max(
            1,
            count - limit + 1
        )

    for index = startIndex, count do
        local record =
            records[index]

        print(
            index
            .. ". "
            .. tostring(
                record.recipient
            )
            .. " — "
            .. tostring(
                record.itemLink
            )
            .. " — "
            .. date(
                "%m/%d %I:%M %p",
                record.timestamp
            )
        )
    end
end

local function PrintPlayerLoot(searchName)
    if not searchName
        or searchName == ""
    then
        SYL:Print(
            "Enter a player name. Example: /syl player Aimee"
        )

        return
    end

    local normalizedSearch =
        string.lower(searchName)

    local matches = {}

    for _, record in ipairs(
        SYL.GetActiveLoot()
    ) do
        local recipient =
            string.lower(
                record.recipient or ""
            )

        if recipient:find(
            normalizedSearch,
            1,
            true
        ) then
            table.insert(
                matches,
                record
            )
        end
    end

    SYL:Print(
        #matches
        .. " active-season records found for "
        .. searchName
    )

    local startIndex =
        math.max(
            1,
            #matches - 9
        )

    for index = startIndex, #matches do
        local record =
            matches[index]

        print(
            record.recipient
            .. " — "
            .. record.itemLink
            .. " — "
            .. date(
                "%m/%d %I:%M %p",
                record.timestamp
            )
        )
    end
end

local function PrintSeasonStatus()
    local season =
        SYL.GetActiveSeason()

    if not season then
        SYL:Print(
            "No active season exists."
        )

        return
    end

    SYL:Print(
        "Active season: "
        .. season.name
    )

    print(
        "Season ID: "
        .. tostring(season.id)
    )

    print(
        "Loot records: "
        .. #(season.loot or {})
    )

    print(
        "Started: "
        .. date(
            "%m/%d/%Y %I:%M %p",
            season.startedAt
        )
    )

    print(
        "Archived seasons: "
        .. #SYL.GetArchives()
    )
end

local function PrintArchives()
    local archives =
        SYL.GetArchives()

    SYL:Print(
        "Archived seasons: "
        .. #archives
    )

    if #archives == 0 then
        print(
            "No seasons have been archived."
        )

        return
    end

    for index, season in ipairs(
        archives
    ) do
        print(
            index
            .. ". "
            .. season.name
            .. " — "
            .. #(season.loot or {})
            .. " items — archived "
            .. date(
                "%m/%d/%Y",
                season.archivedAt
                    or season.startedAt
            )
        )
    end
end

local function PrintHelp()
    SYL:Print("Commands:")

    print(
        "/syl — Open the loot window"
    )

    print(
        "/syl recent — Show recent active-season loot"
    )

    print(
        "/syl count — Show active and all-time totals"
    )

    print(
        "/syl player NAME — Show active-season loot for a player"
    )

    print(
        "/syl season — Show active-season information"
    )

    print(
        "/syl rename NAME — Rename the active season"
    )

    print(
        "/syl archive NEW SEASON NAME — Archive the current season and start a new one"
    )

    print(
        "/syl archives — List archived seasons"
    )

    print(
        "/syl debug — Toggle debug messages"
    )

    print(
        "/syl announce — Toggle capture messages"
    )

    print(
        "/syl clear — Clear active-season loot"
    )
end

eventFrame:SetScript(
    "OnEvent",
    function(self, event, ...)
        if event == "ADDON_LOADED" then
            local loadedAddonName = ...

            if loadedAddonName
                ~= ADDON_NAME
            then
                return
            end

            SYL.DatabaseInitialize()

            local activeSeason =
                SYL.GetActiveSeason()

            SYL:Print(
                "Database ready. Active season: "
                .. activeSeason.name
                .. " — "
                .. #activeSeason.loot
                .. " item records."
            )

            return
        end

        if event == "PLAYER_LOGIN" then
            SYL:DebugPrint(
                "Player login complete."
            )

            return
        end

        if event == "CHAT_MSG_LOOT" then
            local message = ...

            SYL:DebugPrint(
                "Raw loot: "
                .. tostring(message)
            )

            SaveLootMessage(message)
        end
    end
)

SLASH_SHOWUSYOURLOOT1 = "/syl"

SlashCmdList["SHOWUSYOURLOOT"] =
    function(input)
        input = input or ""

        local command, remainder =
            input:match(
                "^(%S*)%s*(.-)$"
            )

        command =
            string.lower(
                command or ""
            )

        remainder =
            remainder or ""

        if command == "" then
            if SYL.OpenMainWindow then
                SYL:OpenMainWindow()
            else
                PrintRecentLoot(10)
            end

            return
        end

        if command == "help" then
            PrintHelp()
            return
        end

        if command == "recent" then
            PrintRecentLoot(10)
            return
        end

        if command == "count" then
            SYL:Print(
                "Active season: "
                .. #SYL.GetActiveLoot()
                .. " items"
            )

            print(
                "All-time: "
                .. #SYL.GetAllLoot()
                .. " items"
            )

            return
        end

        if command == "player" then
            PrintPlayerLoot(remainder)
            return
        end

        if command == "season" then
            PrintSeasonStatus()
            return
        end

        if command == "archives" then
            PrintArchives()
            return
        end

        if command == "rename" then
            local success, errorMessage =
                SYL.RenameActiveSeason(
                    remainder
                )

            if success then
                SYL:Print(
                    "Active season renamed to: "
                    .. SYL.GetActiveSeason().name
                )
            else
                SYL:Print(errorMessage)
            end

            return
        end

        if command == "archive" then
            local newSeasonName =
                remainder

            if newSeasonName == "" then
                newSeasonName =
                    "New Season"
            end

            local archivedSeason,
                newSeason =
                SYL.ArchiveCurrentSeason(
                    newSeasonName
                )

            if not archivedSeason then
                SYL:Print(
                    newSeason
                    or "Archive failed."
                )

                return
            end

            SYL:Print(
                "Archived "
                .. archivedSeason.name
                .. " with "
                .. #archivedSeason.loot
                .. " loot records."
            )

            print(
                "New active season: "
                .. newSeason.name
            )

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end

            return
        end

        if command == "debug" then
            ShowUsYourLootDB
                .settings
                .debug =
                not ShowUsYourLootDB
                    .settings
                    .debug

            SYL:Print(
                "Debug messages "
                .. (
                    ShowUsYourLootDB
                        .settings
                        .debug
                    and "enabled."
                    or "disabled."
                )
            )

            return
        end

        if command == "announce" then
            ShowUsYourLootDB
                .settings
                .announceCaptures =
                not ShowUsYourLootDB
                    .settings
                    .announceCaptures

            SYL:Print(
                "Capture announcements "
                .. (
                    ShowUsYourLootDB
                        .settings
                        .announceCaptures
                    and "enabled."
                    or "disabled."
                )
            )

            return
        end

        if command == "clear" then
            local activeSeason =
                SYL.GetActiveSeason()

            activeSeason.loot = {}

            ShowUsYourLootDB.loot =
                activeSeason.loot

            ShowUsYourLootDB
                .recentRecordIDs = {}

            SYL:Print(
                "Active-season loot history cleared."
            )

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end

            return
        end

        PrintHelp()
    end