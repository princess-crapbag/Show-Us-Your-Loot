-- UI/CommandMenu.lua
--
-- The right-click menu on the minimap button: every /syl command as a
-- clickable row, so none of them have to be typed from memory.
--
-- Built with our own frames rather than Blizzard's menu API, which has been
-- rewritten more than once across expansions.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local CommandList = SYL.CommandList

local CommandMenu = {}
SYL.CommandMenu = CommandMenu

local ROW_HEIGHT = 20
local PADDING = 6
local HEADER = 24
local MENU_WIDTH = 320

local panel
local catcher

local function GetCatcher()
    if catcher then
        return catcher
    end

    catcher = CreateFrame("Button", nil, UIParent)

    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:EnableMouse(true)
    catcher:Hide()

    catcher:SetScript("OnClick", function()
        CommandMenu.Close()
    end)

    return catcher
end

function CommandMenu.Close()
    if panel then
        panel:Hide()
    end

    if catcher then
        catcher:Hide()
    end
end

local function CreateRow(parent, index, entry)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, -(HEADER + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -PADDING, -(HEADER + (index - 1) * ROW_HEIGHT))

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.commandText = Theme.CreateText(row, Theme.sizes.rowSmall, "accent")
    row.commandText:SetPoint("LEFT", 6, 0)
    row.commandText:SetWidth(150)
    row.commandText:SetText(CommandList.Format(entry))

    row.descriptionText =
        Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")

    row.descriptionText:SetPoint("LEFT", row.commandText, "RIGHT", 8, 0)
    row.descriptionText:SetPoint("RIGHT", -6, 0)
    row.descriptionText:SetText(entry.description)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row:SetScript("OnClick", function()
        CommandMenu.Close()

        CommandList.Run(entry)
    end)

    return row
end

local function CreatePanel()
    if panel then
        return panel
    end

    local entries = CommandList.ENTRIES

    panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")

    panel:SetWidth(MENU_WIDTH)
    panel:SetHeight(HEADER + #entries * ROW_HEIGHT + PADDING)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    panel:Hide()

    Theme.StyleWindow(panel)

    local heading =
        Theme.CreateText(panel, Theme.sizes.columnHeader, "textMuted")

    heading:SetPoint("TOPLEFT", PADDING + 6, -8)
    heading:SetText("SHOW US YOUR LOOT — COMMANDS")

    for index, entry in ipairs(entries) do
        CreateRow(panel, index, entry)
    end

    return panel
end

-- Anchors to whichever corner keeps the menu on screen, since the minimap
-- button can be dragged anywhere around the ring.
local function AnchorToButton(menu, button)
    menu:ClearAllPoints()

    local centerX, centerY = button:GetCenter()
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()

    if not centerX or not centerY then
        menu:SetPoint("CENTER")
        return
    end

    local horizontal = centerX > screenWidth / 2 and "RIGHT" or "LEFT"
    local vertical = centerY > screenHeight / 2 and "TOP" or "BOTTOM"

    menu:SetPoint(
        vertical .. horizontal,
        button,
        (vertical == "TOP" and "BOTTOM" or "TOP") .. horizontal,
        0,
        vertical == "TOP" and -4 or 4
    )
end

function CommandMenu.Toggle(button)
    local menu = CreatePanel()

    if menu:IsShown() then
        CommandMenu.Close()
        return
    end

    AnchorToButton(menu, button)

    local catcherFrame = GetCatcher()

    catcherFrame:Show()

    menu:SetFrameLevel(catcherFrame:GetFrameLevel() + 10)
    menu:Show()
end
