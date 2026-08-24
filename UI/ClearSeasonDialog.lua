-- UI/ClearSeasonDialog.lua
--
-- Erasing the active season's records, behind a door somebody has to mean to
-- open.
--
-- WHY THIS IS NOT A BUTTON. `/syl clear` is the only command in this addon
-- that destroys a season's worth of recording, it cannot be undone, and it
-- was once a plain row in the minimap menu -- so it emptied a season on one
-- click, from a list somebody was reading. Core/CommandList.lua:155-165 keeps
-- that record. Its required argument is the only thing that has been guarding
-- it since.
--
-- Putting it on the Tools tab as an ordinary row would rebuild the same trap
-- with a nicer label. Aimee, asked what the Tools tab should do with it:
-- "dont make it a normal button. or make it harder to do. make sure there is
-- an explanation as to why someone should use this button and what will
-- happen if they do. maybe have a danger image near it. [...] give an
-- explanation of what it does so they youngest user can understand."
--
-- So there are four guards, and each one does a different job:
--
--   1. IT IS NOT IN THE LIST. The Tools tab draws it in its own block below
--      everything else, in the warning color, under an alert icon. Nobody
--      reaches it by running their eye down a column.
--   2. THE DIALOG EXPLAINS BEFORE IT ASKS -- in plain words, with the real
--      counts, saying what goes, what stays, and what to do instead.
--   3. THE SEASON'S NAME HAS TO BE TYPED. Not "confirm", which can be typed
--      without reading: the name is the one string that cannot be entered
--      without looking at which season is about to go.
--   4. THE ERASE BUTTON DOES NOTHING UNTIL IT MATCHES, and says so.
--
-- The safe path is offered first and is the larger of the two: almost
-- everybody who reaches this screen wanted Archive, which keeps every record
-- and starts a fresh season beside it.
--
-- Confirm holds the whole job and touches no frame, for the reason
-- UI/SeasonRenameDialog.lua gives: a dialog that cannot be driven from a test
-- is a dialog that ships doing nothing, which has happened here before.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local ClearSeasonDialog = {}
SYL.ClearSeasonDialog = ClearSeasonDialog

local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 420

-- Blizzard's own alert icon, which ships with every client and is the picture
-- a player already reads as "this is serious" -- it is the one on the dialog
-- that asks before deleting a character.
local DANGER_ICON = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

local frame
local nameInput
local bodyText
local matchText
local eraseButton

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

-- SHORT WORDS ON PURPOSE. This is the screen where somebody has to understand
-- what they are about to lose, and a sentence they have to read twice is a
-- sentence they will skip.
function ClearSeasonDialog.Describe()
    local season = SYL.GetActiveSeason()

    if not season then
        return "There is no season running, so there is nothing to erase."
    end

    local drops = #(season.drops or {})
    local loot = #(season.loot or {})

    return "This erases everything this addon has written down for "
        .. (season.name or "the season running now")
        .. ".\n\n"
        .. SYL.Utilities.Count(drops, "group-loot drop")
        .. " and "
        .. SYL.Utilities.Count(loot, "chat item")
        .. " go. Who is due, who turned up, and what each boss has given all "
        .. "go back to nothing, because they are all worked out from those "
        .. "records.\n\n"
        .. "It cannot be undone. There is no backup and no undo button.\n\n"
        .. "Use this only if the addon wrote down a lot you did not want -- a "
        .. "test run, somebody else's raid, or loot from before you set your "
        .. "filters.\n\n"
        .. "If this season is simply over, press Archive instead. That keeps "
        .. "every record and starts a fresh season next to it."
end

-- Whether what has been typed unlocks the button.
--
-- Case and outside spaces are forgiven; the word is not. Somebody who typed
-- the name has looked at it, which is the whole point of asking for the name
-- rather than for "confirm".
function ClearSeasonDialog.Matches(typed)
    local season = SYL.GetActiveSeason()
    local name = season and season.name

    if type(name) ~= "string" or name == "" then
        return false
    end

    if type(typed) ~= "string" then
        return false
    end

    typed = typed:gsub("^%s+", ""):gsub("%s+$", "")

    return typed:lower() == name:lower()
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

-- Runs the real command rather than emptying the tables here.
--
-- Core/SlashCommands.lua's COMMANDS.clear is what has always done this: it
-- rebuilds the drop index, clears recentRecordIDs, and calls
-- Recovery.NoteDeliberateClear -- which is account-wide, so every OTHER
-- character does not report data loss on its next login. A second copy of
-- that in a UI file would be a second thing to keep in step, and the one that
-- forgot the recovery stamp would look completely fine until somebody logged
-- in on an alt.
function ClearSeasonDialog.Confirm(typed)
    if not SYL.GetActiveSeason() then
        return false, "There is no season running."
    end

    if not ClearSeasonDialog.Matches(typed) then
        return false,
            "Type the season's name exactly as it is shown to erase it."
    end

    SlashCmdList["SHOWUSYOURLOOT"]("clear confirm")

    return true
end

local function Attempt()
    local ok, message =
        ClearSeasonDialog.Confirm(nameInput and nameInput:GetText() or "")

    if not ok then
        SYL:Print(message)
        return
    end

    frame:Hide()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

-- The button is drawn dead until the name matches, and the line above it says
-- which of the two states it is in. A control that looks pressable and is not
-- reads as broken; one that says why it is not reads as a lock.
local function UpdateLock()
    local unlocked = ClearSeasonDialog.Matches(
        nameInput and nameInput:GetText() or ""
    )

    if unlocked then
        eraseButton:Enable()
        Theme.SetTextColor(eraseButton.label, "warning")
        matchText:SetText("The name matches. Erase is unlocked.")
        Theme.SetTextColor(matchText, "warning")
    else
        eraseButton:Disable()
        Theme.SetTextColor(eraseButton.label, "textMuted")
        matchText:SetText("Erase stays locked until the name matches.")
        Theme.SetTextColor(matchText, "textMuted")
    end
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function CreateNameInput(parent, top)
    local edge = Theme.CreateSolidTexture(parent, "warning", "BACKGROUND")
    edge:SetPoint("TOPLEFT", 20, top)
    edge:SetSize(WINDOW_WIDTH - 40, 26)

    local fill = Theme.CreateSolidTexture(parent, "window", "ARTWORK")
    fill:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)

    nameInput = CreateFrame("EditBox", nil, parent)

    nameInput:SetPoint("TOPLEFT", edge, "TOPLEFT", 7, -1)
    nameInput:SetSize(WINDOW_WIDTH - 54, 24)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(60)
    nameInput:SetFont(Theme.GetFontPath(), Theme.sizes.rowSmall, "")
    nameInput:SetTextColor(unpack(Theme.colors.textPrimary))

    -- NOT PREFILLED, unlike the rename dialog. There the name is prefilled so
    -- correcting a typo is one keystroke; here the typing IS the guard, and
    -- filling it in would remove the only thing standing between a stray
    -- click and an erased season.
    nameInput:SetScript("OnTextChanged", UpdateLock)
    nameInput:SetScript("OnEnterPressed", Attempt)

    nameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootClearSeasonDialog",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DANGER_ICON)
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 16, -16)

    local title = Theme.CreateText(frame, Theme.sizes.title, "warning")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText("ERASE THIS SEASON")

    local separator = Theme.CreateSeparator(frame, "warning")
    separator:SetPoint("TOPLEFT", 16, -56)
    separator:SetPoint("TOPRIGHT", -16, -56)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", 20, -68)
    bodyText:SetWidth(WINDOW_WIDTH - 40)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    local prompt = Theme.CreateText(frame, Theme.sizes.rowSmall, "textPrimary")
    prompt:SetPoint("TOPLEFT", 20, -274)
    prompt:SetPoint("TOPRIGHT", -20, -274)
    prompt:SetJustifyH("LEFT")
    prompt:SetWordWrap(true)
    prompt:SetHeight(30)

    CreateNameInput(frame, -308)

    matchText = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    matchText:SetPoint("TOPLEFT", 21, -340)
    matchText:SetJustifyH("LEFT")

    frame.prompt = prompt

    -- ARCHIVE IS THE BIG ONE AND IT IS ON THE RIGHT, where the button
    -- somebody presses without reading lives. Nearly everybody who opens this
    -- screen wanted this and not the other.
    local archiveButton =
        Theme.CreateButton(frame, 150, 26, "Archive instead", function()
            frame:Hide()

            if SYL.ArchivePopup and SYL.ArchivePopup.Show then
                SYL.ArchivePopup.Show()
            end
        end)

    archiveButton:SetPoint("BOTTOMRIGHT", -20, 18)

    eraseButton = Theme.CreateButton(frame, 150, 26, "Erase", Attempt)
    eraseButton:SetPoint("BOTTOMLEFT", 20, 18)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

function ClearSeasonDialog.Show()
    local dialog = CreateWindow()
    local season = SYL.GetActiveSeason()

    bodyText:SetText(ClearSeasonDialog.Describe())

    dialog.prompt:SetText(
        "To erase it, type its name here exactly:  "
        .. ((season and season.name) or "-")
    )

    -- Always emptied on open. A dialog that reopened still holding a matching
    -- name would be unlocked before it was read.
    nameInput:SetText("")
    UpdateLock()

    SYL.WindowStack.ShowWindow(dialog)

    return dialog
end
