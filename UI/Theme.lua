-- UI/Theme.lua
--
-- Every color, font size and spacing value the UI uses. Frame code should
-- never hardcode a color: change the look here and the whole addon follows.
--
-- The palette is a dark panel with a single accent, taken from the addon's
-- existing chat color (|cff33ff99) so the window and the chat output read as
-- the same product.

local SYL = _G.ShowUsYourLoot

local Theme = {}
SYL.Theme = Theme

-- Item APIs moved under C_Item in recent clients; keep working either way.
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo

local GetItemInfoInstant =
    C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant

-- Resolved at call time rather than into an upvalue at load. A client that
-- exposes neither spelling made this nil, and every item row and tooltip that
-- asked for a color then threw. See the same note in UI/SettingsRows.lua,
-- where it took out the whole settings window.
local function LookUpQualityColor(quality)
    local lookup = (C_Item and C_Item.GetItemQualityColor)
        or _G.GetItemQualityColor

    if lookup then
        local ok, red, green, blue = pcall(lookup, quality)

        if ok and red then
            return red, green, blue
        end
    end

    local colors = _G.ITEM_QUALITY_COLORS

    if colors and colors[quality] then
        local color = colors[quality]

        return color.r, color.g, color.b
    end

    return nil
end

-- The active palette. Populated by Theme.Apply, which runs at load once the
-- saved setting is known; the starting value keeps the UI safe if anything
-- draws before then.
Theme.colors = SYL.Palettes.Get(SYL.Palettes.DEFAULT).colors
Theme.paletteKey = SYL.Palettes.DEFAULT

-- Anything Theme colors is recorded here so a palette change can repaint it
-- in place. Without this, switching would only affect windows built after the
-- change, and the settings window doing the switching would keep its old
-- colors — the one window guaranteed to be open at the time.
--
-- These are strong references, which is fine: frames and their regions live
-- for the session anyway, and WoW has no way to destroy one.
local painted = {
    textures = {},
    texts = {},
    windows = {},
}

-- Which window is currently the front one. Every palette gives `window` an
-- alpha just under 1 — 0.97 on the dark schemes — which reads as depth on a
-- single window and as a mess on two: overlap them and the back one's text
-- shows through the front one's body. So the window on top is painted solid
-- and the rest keep the palette's alpha.
--
-- Kept here rather than on the frame because Apply repaints every tracked
-- window on a palette change, and a focus written onto the frame would be
-- silently flattened by that loop — which is how the class colors were lost
-- once already, a few lines below.
local focusedWindow = nil

local function WindowAlpha(frame)
    local alpha = Theme.colors.window[4] or 1

    if frame == focusedWindow then
        return 1
    end

    return alpha
end

Theme.sizes = {
    title = 15,
    subtitle = 11,
    row = 12,
    rowSmall = 11,
    columnHeader = 10,

    -- The Raiders detail pane's item cards, and nothing else yet. Aimee asked
    -- for that text smaller than anything the addon had: "i dont want it to be
    -- too cluttered and i want that text to be smaller if possible." Named
    -- rather than passed as a bare 9, because no other file in UI/ passes a
    -- size that is not one of these and this should not be the first.
    tiny = 9,
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
    local color = Theme.colors.window

    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(color[1], color[2], color[3], WindowAlpha(frame))
    frame:SetBackdropBorderColor(unpack(Theme.colors.border))

    painted.windows[frame] = true
end

-- The front window, painted solid; everything else back to the palette's
-- alpha. Passing nil means nothing is in front, which is the right answer once
-- the last window closes.
--
-- WindowStack decides who this is, from the frame levels it has already
-- raised — so there is no second idea of "selected" here that could disagree
-- with what is actually drawn on top.
function Theme.SetFocusedWindow(frame)
    if focusedWindow == frame then
        return false
    end

    focusedWindow = frame

    local color = Theme.colors.window

    for window in pairs(painted.windows) do
        window:SetBackdropColor(
            color[1], color[2], color[3], WindowAlpha(window)
        )
    end

    return true
end

function Theme.FocusedWindow()
    return focusedWindow
end

function Theme.SetTextColor(fontString, colorKey)
    local key = colorKey or "textPrimary"
    local color = Theme.colors[key] or Theme.colors.textPrimary

    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    painted.texts[fontString] = key
end

-- A color the palette does not own: item quality, class, a Mythic+ score.
--
-- Setting these raw was the bug. Every such font string had been through
-- SetTextColor at least once — at creation, if nothing else — so it stayed on
-- the repaint list under a palette key it no longer wore, and changing theme
-- flattened purple item names and class-colored raiders back to plain text.
--
-- Deregistering states the truth: this string's color is not the palette's
-- business. Rows are reused, so a later SetTextColor puts it back on the list.
function Theme.SetCustomTextColor(fontString, red, green, blue, alpha)
    fontString:SetTextColor(red, green, blue, alpha or 1)

    painted.texts[fontString] = nil
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

-- How wide a string actually renders, rather than how wide it was guessed to
-- be. Every column and box that has come out truncated was sized from an
-- estimate of characters times pixels, which is wrong by enough to matter and
-- wrong by a different amount for every font and locale.
--
-- One hidden font string per size, reused, because creating one per call
-- would leak a region on every layout pass.
local rulers = {}

function Theme.MeasureText(size, text)
    size = size or Theme.sizes.row

    local ruler = rulers[size]

    if not ruler then
        ruler = UIParent:CreateFontString(nil, "OVERLAY")
        ruler:SetFont(fontPath, size, "")
        ruler:Hide()

        rulers[size] = ruler
    end

    ruler:SetText(text or "")

    return math.ceil(ruler:GetStringWidth())
end

function Theme.CreateSolidTexture(parent, colorKey, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    local key = colorKey or "separator"
    local color = Theme.colors[key] or Theme.colors.separator

    texture:SetColorTexture(
        color[1], color[2], color[3], color[4] or 1
    )

    painted.textures[texture] = key

    return texture
end

--------------------------------------------------------------------------
-- Switching palette
--------------------------------------------------------------------------

-- Repaints everything Theme has ever colored.
--
-- Only what the palette owns. Colors that come from somewhere else — item
-- quality, class, a Mythic+ score — are set through SetCustomTextColor, which
-- takes the string off this list precisely so that changing theme does not
-- flatten them. The main window redraws below and would have restored its own
-- rows, but every other window would have stayed gray until a /reload.
function Theme.Apply(key, skipRefresh)
    local palette = SYL.Palettes.Get(key) or SYL.Palettes.Get(SYL.Palettes.DEFAULT)

    Theme.colors = palette.colors
    Theme.paletteKey = palette.key

    for texture, colorKey in pairs(painted.textures) do
        local color = Theme.colors[colorKey]

        if color then
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end

    for fontString, colorKey in pairs(painted.texts) do
        local color = Theme.colors[colorKey] or Theme.colors.textPrimary

        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end

    -- Through WindowAlpha, or changing palette would flatten the front window
    -- back to translucent and quietly undo the whole point of focusing it.
    for frame in pairs(painted.windows) do
        local window = Theme.colors.window

        frame:SetBackdropColor(
            window[1], window[2], window[3], WindowAlpha(frame)
        )
        frame:SetBackdropBorderColor(unpack(Theme.colors.border))
    end

    if ShowUsYourLootDB and ShowUsYourLootDB.settings then
        ShowUsYourLootDB.settings.palette = palette.key
    end

    -- Rows paint per record, so the list needs a redraw rather than a
    -- recolor. RefreshMainWindow already does nothing when the window is
    -- closed; the guard here is for Apply running at load, before the UI
    -- files have finished defining it.
    if not skipRefresh and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return palette
end

function Theme.Current()
    return SYL.Palettes.Get(Theme.paletteKey)
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
-- the selected one still reads as text rather than as a grayed-out control.
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
-- class-colored. Chat-derived loot records cannot: they hold only a name.
-- "DEATHKNIGHT" is what the roster stores, because it keys the colors above
-- and the buff lookups. "Death Knight" is what a person reads.
--
-- Beside GetClassColor rather than in the one file that happened to need it
-- first: two screens now turn a class into text, and a second copy of this
-- would be a second place for a locale to be handled differently.
function Theme.ClassLabel(classFile)
    if not classFile or classFile == "" then
        return ""
    end

    local localized = _G.LOCALIZED_CLASS_NAMES_MALE

    return (localized and localized[classFile]) or classFile
end

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
-- signal to retry shortly rather than to render a wrong color permanently.
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

    local red, green, blue = LookUpQualityColor(quality)

    if not red then
        return nil
    end

    return { red, green, blue }
end
