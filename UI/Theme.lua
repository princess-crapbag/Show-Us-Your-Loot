-- UI/Theme.lua
--
-- Every colour, font size and spacing value the UI uses. Frame code should
-- never hardcode a colour: change the look here and the whole addon follows.
--
-- The palette is a dark panel with a single accent, taken from the addon's
-- existing chat colour (|cff33ff99) so the window and the chat output read as
-- the same product.

local SYL = _G.ShowUsYourLoot

local Theme = {}
SYL.Theme = Theme

-- Item APIs moved under C_Item in recent clients; keep working either way.
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo

local GetItemInfoInstant =
    C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant

local GetItemQualityColor =
    C_Item and C_Item.GetItemQualityColor or _G.GetItemQualityColor

-- A charcoal panel rather than a near-black one. The neutrals carry a slight
-- blue bias so the green accent reads as deliberate against them instead of
-- floating on flat grey.
Theme.colors = {
    window = { 0.13, 0.13, 0.155, 0.97 },
    border = { 0.30, 0.30, 0.35, 1 },

    headerBar = { 0.18, 0.18, 0.215, 1 },
    separator = { 1, 1, 1, 0.10 },

    accent = { 0.20, 0.95, 0.60, 1 },
    accentMuted = { 0.20, 0.95, 0.60, 0.16 },

    rowAlt = { 1, 1, 1, 0.035 },
    rowHover = { 0.20, 0.95, 0.60, 0.12 },

    button = { 1, 1, 1, 0.085 },
    buttonHover = { 1, 1, 1, 0.16 },

    textPrimary = { 0.95, 0.95, 0.96, 1 },
    textSecondary = { 0.72, 0.72, 0.77, 1 },
    textMuted = { 0.54, 0.54, 0.60, 1 },
}

Theme.sizes = {
    title = 15,
    subtitle = 11,
    row = 12,
    rowSmall = 11,
    columnHeader = 10,
}

Theme.metrics = {
    rowHeight = 28,
    archiveRowHeight = 40,
    iconSize = 18,
    padding = 16,
}

local WINDOW_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

-- Pulled from a live font object rather than a global constant, which has
-- changed name across expansions.
local fontPath = GameFontNormal:GetFont()

function Theme.GetFontPath()
    return fontPath
end

function Theme.StyleWindow(frame)
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(unpack(Theme.colors.window))
    frame:SetBackdropBorderColor(unpack(Theme.colors.border))
end

function Theme.SetTextColor(fontString, colorKey)
    local color = Theme.colors[colorKey] or Theme.colors.textPrimary

    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

function Theme.CreateText(parent, size, colorKey, layer)
    local fontString =
        parent:CreateFontString(nil, layer or "OVERLAY")

    fontString:SetFont(fontPath, size or Theme.sizes.row, "")
    fontString:SetJustifyH("LEFT")
    fontString:SetWordWrap(false)

    Theme.SetTextColor(fontString, colorKey or "textPrimary")

    return fontString
end

function Theme.CreateSolidTexture(parent, colorKey, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    local color = Theme.colors[colorKey] or Theme.colors.separator

    texture:SetColorTexture(
        color[1], color[2], color[3], color[4] or 1
    )

    return texture
end

-- A one-pixel horizontal rule.
function Theme.CreateSeparator(parent, colorKey)
    local separator =
        Theme.CreateSolidTexture(parent, colorKey or "separator", "ARTWORK")

    separator:SetHeight(1)

    return separator
end

-- The short vertical accent mark that sits left of the window title.
function Theme.CreateAccentMark(parent)
    local mark = Theme.CreateSolidTexture(parent, "accent", "ARTWORK")

    mark:SetSize(3, 16)

    return mark
end

--------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------

local function ApplyButtonVisuals(button)
    button.background =
        Theme.CreateSolidTexture(button, "button", "BACKGROUND")

    button.background:SetAllPoints()

    button.label = Theme.CreateText(button, Theme.sizes.rowSmall, "textPrimary")
    button.label:SetPoint("CENTER")
    button.label:SetJustifyH("CENTER")

    button:SetScript("OnEnter", function(self)
        local color = Theme.colors.buttonHover

        self.background:SetColorTexture(
            color[1], color[2], color[3], color[4]
        )
    end)

    button:SetScript("OnLeave", function(self)
        local color = Theme.colors.button

        self.background:SetColorTexture(
            color[1], color[2], color[3], color[4]
        )
    end)
end

function Theme.CreateButton(parent, width, height, text, onClick)
    local button = CreateFrame("Button", nil, parent)

    button:SetSize(width, height)

    ApplyButtonVisuals(button)

    button.label:SetText(text)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    return button
end

-- Tabs carry their selected state themselves rather than being disabled, so
-- the selected one still reads as text rather than as a greyed-out control.
function Theme.CreateTab(parent, text, onClick)
    local tab = CreateFrame("Button", nil, parent)

    tab:SetHeight(26)

    tab.label = Theme.CreateText(tab, Theme.sizes.row, "textSecondary")
    tab.label:SetPoint("CENTER", 0, 1)
    tab.label:SetJustifyH("CENTER")
    tab.label:SetText(text)

    tab:SetWidth(math.max(70, tab.label:GetStringWidth() + 28))

    tab.underline = Theme.CreateSolidTexture(tab, "accent", "ARTWORK")
    tab.underline:SetHeight(2)
    tab.underline:SetPoint("BOTTOMLEFT", 6, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    tab.underline:Hide()

    tab.SetSelected = function(self, selected)
        self.selected = selected

        if selected then
            self.underline:Show()
            Theme.SetTextColor(self.label, "accent")
        else
            self.underline:Hide()
            Theme.SetTextColor(self.label, "textSecondary")
        end
    end

    tab:SetScript("OnEnter", function(self)
        if not self.selected then
            Theme.SetTextColor(self.label, "textPrimary")
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.selected then
            Theme.SetTextColor(self.label, "textSecondary")
        end
    end)

    if onClick then
        tab:SetScript("OnClick", onClick)
    end

    tab:SetSelected(false)

    return tab
end

--------------------------------------------------------------------------
-- Item presentation
--------------------------------------------------------------------------

-- Instant lookup: works for items that are not in the local cache yet, which
-- matters when browsing an archive full of items this character never saw.
function Theme.GetItemIcon(itemLink)
    if not itemLink then
        return nil
    end

    local success, icon = pcall(function()
        return select(5, GetItemInfoInstant(itemLink))
    end)

    if success then
        return icon
    end

    return nil
end

-- Drop records store the winner's class file name, so their names can be
-- class-coloured. Chat-derived loot records cannot: they hold only a name.
function Theme.GetClassColor(classFile)
    if not classFile or classFile == "" then
        return nil
    end

    local color

    if C_ClassColor and C_ClassColor.GetClassColor then
        color = C_ClassColor.GetClassColor(classFile)
    end

    if not color and RAID_CLASS_COLORS then
        color = RAID_CLASS_COLORS[classFile]
    end

    if not color then
        return nil
    end

    return { color.r, color.g, color.b }
end

-- Returns nil when the item is not cached yet, which the caller uses as a
-- signal to retry shortly rather than to render a wrong colour permanently.
function Theme.GetItemQualityColor(itemLink)
    if not itemLink then
        return nil
    end

    local success, quality = pcall(function()
        return select(3, GetItemInfo(itemLink))
    end)

    if not success or not quality then
        return nil
    end

    local red, green, blue = GetItemQualityColor(quality)

    if not red then
        return nil
    end

    return { red, green, blue }
end
