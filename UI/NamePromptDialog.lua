-- UI/NamePromptDialog.lua
--
-- One box, one sentence saying what goes in it, and a button.
--
-- WHY IT EXISTS. Six /syl commands take an argument. Two of them already had
-- a screen -- UI/SeasonRenameDialog.lua and UI/ArchivePopup.lua -- and the
-- rest had nothing at all, so clicking them anywhere in the addon prefilled
-- the chat box and left the person to finish the sentence. That is the house
-- rule half-kept: they no longer have to KNOW the command, but they still
-- have to type into chat, and `/syl addraider Name-Realm CLASS` is not a
-- thing anybody guesses the shape of from a prefill.
--
-- Adding a recruit is the one that matters most. UI/RaidersPanel.lua told
-- people for months that it lived in the full roster window; IncomingRoster.
-- Add has never had a caller in UI/ at all, so the only way in was a command
-- nobody had been told about. This is that way in.
--
-- GENERIC ON PURPOSE, and it is the third dialog in this addon with the same
-- bones. It is not merged with the other two because both of those do
-- something specific on accept -- one renames a season, the other ends one --
-- and folding three different jobs behind one config table would be more
-- surface than the frames it saves.
--
-- Accept holds the whole job and touches no frame, for the reason
-- UI/SeasonRenameDialog.lua gives.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local NamePromptDialog = {}
SYL.NamePromptDialog = NamePromptDialog

local WINDOW_WIDTH = 440
local WINDOW_HEIGHT = 218

-- THE OPTIONAL PREVIEW, added for the wording box in UI/LootAskPanel.lua.
-- That one is a sentence that will be whispered to a stranger with an item
-- link spliced into it, and the link is about 110 of the 255 characters a
-- whisper allows -- so what you typed and what will actually arrive are not
-- the same length or the same text. A dialog that shows one and sends the
-- other is the shape of thing people only find out about afterwards.
--
-- Generic, because it costs one config key: any dialog can hand over a
-- function and get a live line under the box. Dialogs without one are exactly
-- as tall as they were.
local PREVIEW_HEIGHT = 44
local PREVIEW_BLOCK = PREVIEW_HEIGHT + 12

local frame
local titleText
local bodyText
local nameInput
local previewText
local acceptButton

local current = {}

-- Runs whatever the caller asked for with the typed text.
--
-- Always returns two values, the way SeasonRenameDialog.Confirm does and for
-- the same reason: one on success and two on failure comes back as a tuple in
-- the test harness and reads fine right up until it does not.
function NamePromptDialog.Accept(config, typed)
    if type(config) ~= "table" or type(config.onAccept) ~= "function" then
        return false, "Nothing to do."
    end

    if type(typed) ~= "string" then
        typed = ""
    end

    typed = typed:gsub("^%s+", ""):gsub("%s+$", "")

    if typed == "" then
        return false, config.empty or "Type something first."
    end

    return config.onAccept(typed)
end

local function Attempt()
    local ok, message =
        NamePromptDialog.Accept(current, nameInput and nameInput:GetText() or "")

    if message then
        SYL:Print(message)
    end

    if not ok then
        return
    end

    frame:Hide()

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

-- Recomputed on every keystroke rather than on accept, which is the whole
-- point of it. Wrapped in pcall because the function belongs to the caller
-- and this runs inside a text field: a mistake in it must not make the box
-- impossible to type in.
local function UpdatePreview()
    if not previewText then
        return
    end

    if type(current.preview) ~= "function" then
        previewText:Hide()

        return
    end

    local ok, text, warn = pcall(current.preview, nameInput:GetText() or "")

    if not ok then
        text, warn = "", false
    end

    previewText:SetText(text or "")
    Theme.SetTextColor(previewText, warn and "warning" or "textMuted")
    previewText:Show()
end


local function CreateNameInput(parent)
    local edge = Theme.CreateSolidTexture(parent, "border", "BACKGROUND")
    edge:SetPoint("TOPLEFT", 20, -134)
    edge:SetSize(WINDOW_WIDTH - 40, 26)

    local fill = Theme.CreateSolidTexture(parent, "window", "ARTWORK")
    fill:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)

    nameInput = CreateFrame("EditBox", nil, parent)

    nameInput:SetPoint("TOPLEFT", edge, "TOPLEFT", 7, -1)
    nameInput:SetSize(WINDOW_WIDTH - 54, 24)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(80)
    nameInput:SetFont(Theme.GetFontPath(), Theme.sizes.rowSmall, "")
    nameInput:SetTextColor(unpack(Theme.colors.textPrimary))

    nameInput:SetScript("OnEnterPressed", Attempt)
    nameInput:SetScript("OnTextChanged", UpdatePreview)

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
        "ShowUsYourLootNamePromptDialog",
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

    titleText = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    titleText:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -46)
    separator:SetPoint("TOPRIGHT", -16, -46)

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", 20, -58)
    bodyText:SetWidth(WINDOW_WIDTH - 40)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    CreateNameInput(frame)

    previewText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    previewText:SetPoint("TOPLEFT", 20, -168)
    previewText:SetWidth(WINDOW_WIDTH - 40)
    previewText:SetHeight(PREVIEW_HEIGHT)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetWordWrap(true)
    previewText:Hide()

    acceptButton = Theme.CreateButton(frame, 120, 26, "OK", Attempt)
    acceptButton:SetPoint("BOTTOMRIGHT", -20, 18)

    local cancelButton =
        Theme.CreateButton(frame, 100, 26, "Cancel", function()
            frame:Hide()
        end)

    cancelButton:SetPoint("RIGHT", acceptButton, "LEFT", -8, 0)

    local closeCorner =
        CreateFrame("Button", nil, frame, "UIPanelCloseButton")

    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    frame:Hide()

    return frame
end

-- `config` is:
--   title     the heading
--   body      what to type, and an example of it
--   accept    the button's word ("Add", "Remove")
--   empty     what to say when nothing was typed
--   prefill   text to start with, selected
--   onAccept  takes the typed string, returns ok and a message
--   maxLetters how much the box will hold, 80 by default
--   preview   optional. Takes what is typed, returns the line to show under
--             the box and whether to show it as a warning.
function NamePromptDialog.Show(config)
    current = config or {}

    local dialog = CreateWindow()

    -- Only a dialog that asked for a preview pays for the room it takes.
    frame:SetHeight(
        current.preview and (WINDOW_HEIGHT + PREVIEW_BLOCK) or WINDOW_HEIGHT
    )

    titleText:SetText(current.title or "")
    bodyText:SetText(current.body or "")
    acceptButton.label:SetText(current.accept or "OK")

    nameInput:SetMaxLetters(current.maxLetters or 80)
    nameInput:SetText(current.prefill or "")

    UpdatePreview()

    if current.prefill then
        nameInput:HighlightText()
    end

    SYL.WindowStack.ShowWindow(dialog)

    nameInput:SetFocus()

    return dialog
end
