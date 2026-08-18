-- UI/SeasonRenameDialog.lua
--
-- Renaming the season that is running now.
--
-- WHY THIS EXISTS. An archive could be renamed from the Archives tab since
-- v0.3.2 — tick it, type, press Rename. The *active* season could only be
-- renamed with /syl rename, a command nobody has been told about, which is
-- Aimee's own rule broken in the place it matters most: the name is typed
-- once, into the archive dialog, at the moment a tier ends and everybody is
-- in a hurry. Getting it wrong there is ordinary, and the way back was a
-- command a guildie would never find.
--
-- It sits beside Archive Season on the Archives tab, because that is where
-- somebody already goes to think about seasons, and because the two are the
-- same subject: one ends a season, the other fixes what it was called.
--
-- Confirm holds the whole job and touches no frame, for the same reason the
-- archive dialog does: a dialog that cannot be driven from a test is a dialog
-- that ships doing nothing, which is exactly what happened to the other one.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local SeasonRenameDialog = {}
SYL.SeasonRenameDialog = SeasonRenameDialog

local WINDOW_WIDTH = 420
local WINDOW_HEIGHT = 176

local frame
local nameInput
local bodyText

local onRenamed

-- Renames the active season. Always returns two values — the new name and a
-- message, or nil and the reason — so a caller never has to know which of the
-- two shapes it got. Returning one value on success and two on failure is the
-- kind of thing that reads fine in Lua and comes back as a tuple in the test
-- harness; see the lupa note in HANDOFF.
--
-- An empty name is refused rather than defaulted. The archive dialog fills a
-- blank in because somebody there is starting a season and must end up with
-- one; here they are correcting a name, and silently substituting "New Season"
-- would be a second wrong name rather than a fix.
function SeasonRenameDialog.Confirm(newName)
    if type(newName) ~= "string" then
        newName = ""
    end

    newName = newName:gsub("^%s+", ""):gsub("%s+$", "")

    if newName == "" then
        return nil, "Enter a season name."
    end

    local ok, message = SYL.RenameActiveSeason(newName)

    if not ok then
        return nil, message or "Could not rename the season."
    end

    local named = SYL.GetActiveSeason().name

    return named, "Active season renamed to: " .. named
end

function SeasonRenameDialog.Describe()
    local active = SYL.GetActiveSeason()

    if not active then
        return "There is no active season."
    end

    return "Renaming the season running now, currently called "
        .. (active.name or "Unnamed Season")
        .. ".\n\nNothing recorded in it changes — only what it is called."
end

local function Accept()
    local name, message = SeasonRenameDialog.Confirm(
        nameInput and nameInput:GetText() or ""
    )

    SYL:Print(message)

    if not name then
        return
    end

    frame:Hide()

    if onRenamed then
        onRenamed()
    end
end

local function CreateNameInput(parent)
    local edge = Theme.CreateSolidTexture(parent, "border", "BACKGROUND")
    edge:SetPoint("TOPLEFT", 20, -96)
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

    nameInput:SetScript("OnEnterPressed", Accept)

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
        "ShowUsYourLootSeasonRenameDialog",
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

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("RENAME SEASON")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -46)
    separator:SetPoint("TOPRIGHT", -16, -46)

    bodyText = Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")
    bodyText:SetPoint("TOPLEFT", 20, -58)
    bodyText:SetWidth(WINDOW_WIDTH - 40)
    bodyText:SetJustifyH("LEFT")

    CreateNameInput(frame)

    local renameButton = Theme.CreateButton(frame, 110, 26, "Rename", Accept)

    renameButton:SetPoint("BOTTOMRIGHT", -20, 18)

    local cancelButton =
        Theme.CreateButton(frame, 100, 26, "Cancel", function()
            frame:Hide()
        end)

    cancelButton:SetPoint("RIGHT", renameButton, "LEFT", -8, 0)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

function SeasonRenameDialog.Show(callback)
    onRenamed = callback

    local dialog = CreateWindow()
    local active = SYL.GetActiveSeason()

    bodyText:SetText(SeasonRenameDialog.Describe())

    -- Prefilled with the name it already has and selected, so correcting a
    -- typo is one keystroke and keeping it is Escape.
    nameInput:SetText((active and active.name) or "")
    nameInput:HighlightText()

    SYL.WindowStack.ShowWindow(dialog)

    nameInput:SetFocus()

    return dialog
end
