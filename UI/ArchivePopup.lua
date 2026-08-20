-- UI/ArchivePopup.lua
--
-- The "archive this season" dialog: the one button in this addon that ends a
-- tier, and the one that was doing nothing at all.
--
-- IT WAS A BLIZZARD StaticPopup AND NOW IT IS NOT. The dialog appeared, the
-- name could be typed, and pressing Archive had no effect on either of two
-- clients. SYL.ArchiveCurrentSeason was never the problem — driven directly it
-- archives correctly — so the failure was somewhere between the button and
-- OnAccept, inside frame code this addon does not own and no test here can
-- reach. Rather than guess at it, the dialog is now built the way every other
-- window in this addon is built, out of Theme and Widgets, with no dependency
-- on the popup system at all. It was the only StaticPopup here, so nothing
-- else loses anything by it going.
--
-- THE LOGIC IS A FUNCTION WITH NO FRAME IN IT. Confirm does the whole job and
-- Show only collects a name. That split is the actual lesson: a StaticPopup's
-- OnAccept cannot be called from the test harness by any route, so the one
-- action that ends a season had no coverage and shipped dead with every suite
-- green. Confirm is called directly by tools/test_archivedialog.py.
--
-- IT NAMES BOTH SEASONS ON SCREEN. `/syl archive <name>` names the season
-- being *started*, not the one being archived, and has caught Aimee twice —
-- once leaving the active season called "Season 1 tail". The behavior is
-- defensible and the wording was not, so the dialog now says which season is
-- being closed and which one the box is naming, in those words.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local ArchivePopup = {}
SYL.ArchivePopup = ArchivePopup

local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 230

local frame
local nameInput
local bodyText

local onArchived

local DEFAULT_NAME = "New Season"

--------------------------------------------------------------------------
-- What the button does
--------------------------------------------------------------------------

-- Normalises the typed name and archives. Returns the archived season and the
-- new one, or nil and a message.
--
-- No frame is touched here on purpose. See the header.
function ArchivePopup.Confirm(newSeasonName)
    if type(newSeasonName) ~= "string" then
        newSeasonName = ""
    end

    newSeasonName = newSeasonName:gsub("^%s+", ""):gsub("%s+$", "")

    -- An empty box is a name, not an error. Somebody who clears it and presses
    -- Archive still meant to archive, and refusing would be the second way
    -- this button did nothing.
    if newSeasonName == "" then
        newSeasonName = DEFAULT_NAME
    end

    local archivedSeason, newSeason = SYL.ArchiveCurrentSeason(newSeasonName)

    if not archivedSeason then
        return nil, newSeason or "There is no active season to archive."
    end

    return archivedSeason, newSeason
end

-- The sentence over the name box. Built here rather than written into the
-- frame once, because it names the season being closed and that changes.
function ArchivePopup.Describe()
    local active = SYL.GetActiveSeason()
    local name = (active and active.name) or "the current season"
    local drops = active and #(active.drops or {}) or 0

    return "Archiving " .. name .. ", with " .. drops
        .. (drops == 1 and " drop" or " drops")
        .. ". It is sealed and kept.\n\nThe name below is for the NEW season "
        .. "that starts now — not for the one being archived."
end

--------------------------------------------------------------------------
-- The dialog
--------------------------------------------------------------------------

local function Accept()
    local archivedSeason, newSeason = ArchivePopup.Confirm(
        nameInput and nameInput:GetText() or ""
    )

    if not archivedSeason then
        SYL:Print(newSeason)

        return
    end

    SYL:Print(
        "Archived "
        .. archivedSeason.name
        .. " with "
        .. #(archivedSeason.drops or {})
        .. " drops. Find it on the Archives tab."
    )

    SYL:Print("New active season: " .. newSeason.name)

    frame:Hide()

    if onArchived then
        onArchived()
    end
end

local function CreateNameInput(parent)
    local edge = Theme.CreateSolidTexture(parent, "border", "BACKGROUND")
    edge:SetPoint("TOPLEFT", 20, -118)
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
        "ShowUsYourLootArchiveDialog",
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

    -- Centered rather than tiled. The layout arranges the windows somebody
    -- works in; a dialog asking a question belongs in front of them.
    SYL.WindowStack.KeepPlacement(frame)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText("ARCHIVE SEASON")

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -46)
    separator:SetPoint("TOPRIGHT", -16, -46)

    bodyText = Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")
    bodyText:SetPoint("TOPLEFT", 20, -60)
    bodyText:SetWidth(WINDOW_WIDTH - 40)
    bodyText:SetJustifyH("LEFT")

    CreateNameInput(frame)

    local archiveButton =
        Theme.CreateButton(frame, 120, 26, "Archive", Accept)

    archiveButton:SetPoint("BOTTOMRIGHT", -20, 18)

    local cancelButton =
        Theme.CreateButton(frame, 100, 26, "Cancel", function()
            frame:Hide()
        end)

    cancelButton:SetPoint("RIGHT", archiveButton, "LEFT", -8, 0)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

-- onArchived runs only when a season was actually archived, so the caller can
-- move its view back to the new active season.
function ArchivePopup.Show(callback)
    onArchived = callback

    local dialog = CreateWindow()

    bodyText:SetText(ArchivePopup.Describe())

    nameInput:SetText(DEFAULT_NAME)
    nameInput:HighlightText()

    SYL.WindowStack.ShowWindow(dialog)

    nameInput:SetFocus()

    return dialog
end
