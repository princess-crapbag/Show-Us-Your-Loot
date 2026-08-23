-- UI/RaidersDetailCards.lua
--
-- One item on the Raiders detail pane: a banded card with the item's quality
-- down its left edge, its icon, its name, how it was won and where it came
-- from, and the upgrade track as a letter on the right.
--
-- THE NAME IS A REAL ITEM LINK, which is the thing Aimee actually asked for:
-- "id like it to show the item link and just look better." Quality color on
-- the name, the game's own item tooltip on hover, and shift-click to paste it
-- into chat. Plain gray text that happened to say the item's name was not a
-- link, and the difference is the whole point.
--
-- Split from UI/RaidersDetail.lua, which owns the pane around these. Same
-- division as RaidersBoard and RaidersBoardRows one screen along.
--
-- POOLED AND FULLY RESET. Every card owns textures and a Button as well as its
-- font strings, and the pane's old Render hid only font strings -- so
-- selecting an eight-item raider and then a two-item one would have left six
-- ghost cards on screen, still lit, still showing somebody else's loot in
-- their tooltips. Cards.Hide exists for exactly that and the pane calls it on
-- every render.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Cards = {}
SYL.RaidersDetailCards = Cards

Cards.HEIGHT = 28
Cards.GAP = 3

local PAD = 10
local SPINE = 2
local ICON = 16
local ICON_X = 14

-- The gap between the letter and the text that stops before it.
local LETTER_GAP = 10

local NAME_SIZE = Theme.sizes.tiny
local META_SIZE = Theme.sizes.tiny
local LETTER_SIZE = Theme.sizes.row

-- MEASURED ONCE, FROM THE WIDEST LETTER, not from whichever letter this card
-- happens to hold. Sizing the text column against the current letter would
-- move the name a pixel or two every row, which reads as the list being
-- slightly broken rather than as anything meaningful.
local reserved

local function Reserve()
    if reserved then
        return reserved
    end

    local widest = 0

    for _, letter in ipairs(SYL.GearTrack.ORDER) do
        widest = math.max(widest, Theme.MeasureText(LETTER_SIZE, letter))
    end

    reserved = widest + LETTER_GAP

    return reserved
end

-- Both lines as one block, centered in the card, so shrinking the text does
-- not leave it floating against the top edge.
local function TextTop(height)
    local block = Theme.sizes.tiny * 2 + 6

    return (height - block) / 2
end

function Cards.Create(detail, width)
    local card = CreateFrame("Button", nil, detail)

    card:SetSize(width - 12, Cards.HEIGHT)
    card:SetPoint("TOPLEFT", 6, 0)

    card.band = Theme.CreateSolidTexture(card, "rowAlt", "BACKGROUND")
    card.band:SetAllPoints()

    -- The item's quality as a spine down the left edge, so a stack of these
    -- reads as a stack of items before any of them is read.
    card.spine = card:CreateTexture(nil, "BORDER")
    card.spine:SetPoint("TOPLEFT")
    card.spine:SetPoint("BOTTOMLEFT")
    card.spine:SetWidth(SPINE)

    card.hover = Theme.CreateSolidTexture(card, "rowHover", "BORDER")
    card.hover:SetAllPoints()
    card.hover:Hide()

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("LEFT", ICON_X, 0)

    -- The game's icons carry their own border. Every other item row in this
    -- addon trims it the same way; see UI/Rows.lua.
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local textX = ICON_X + ICON + 8
    local room = (width - PAD) - textX - Reserve()

    card.name = Theme.CreateText(card, NAME_SIZE, "textPrimary")
    card.name:SetPoint("TOPLEFT", textX, -TextTop(Cards.HEIGHT))
    card.name:SetWidth(room)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.meta = Theme.CreateText(card, META_SIZE, "textMuted")
    card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.meta:SetWidth(room)
    card.meta:SetJustifyH("LEFT")
    card.meta:SetWordWrap(false)

    -- Aimee, on the track letter: "keep it centered in the space and keep all
    -- of those letters the light grey color that the word need is in." So it
    -- is centered against the whole card rather than against either line, and
    -- it is textMuted like the line beside it rather than colored by track.
    card.letter = Theme.CreateText(card, LETTER_SIZE, "textMuted")
    card.letter:SetPoint("RIGHT", -(PAD - 6), 0)
    card.letter:SetJustifyH("RIGHT")

    -- Read on hover rather than captured here, because cards are pooled: a
    -- link closed over at creation belongs to whoever was in this slot when
    -- the pane was first built.
    card.itemHover = SYL.Widgets.MakeItemHoverable(card, function()
        return card.itemLink
    end)

    -- SIZED BY THE CALLER, ALWAYS. MakeItemHoverable deliberately leaves its
    -- button with no bounds -- see its comment -- and this shipped without
    -- any, so the button was zero by zero, never took the mouse, and the item
    -- tooltip simply did not appear. Aimee, after a reload: "the only thing
    -- its missing is the tool tip on hover."
    --
    -- The whole card is the right target here, unlike the other two callers
    -- that cover only the words. Its warning about stealing clicks is about
    -- same-level SIBLINGS, and a card has no other controls inside it -- the
    -- icon, the spine and the letter are textures and font strings, none of
    -- which take mouse input.
    card.itemHover:SetAllPoints(card)

    -- The highlight hangs off the hover button rather than off the card,
    -- because the button now covers the card and the topmost mouse-enabled
    -- frame is the one that gets OnEnter. Hooked rather than set, or it would
    -- replace the tooltip handler that button was created for.
    card.itemHover:HookScript("OnEnter", function() card.hover:Show() end)
    card.itemHover:HookScript("OnLeave", function() card.hover:Hide() end)

    return card
end

function Cards.Draw(card, item, y)
    card.itemLink = item.itemLink

    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 6, -y)

    local color = Theme.GetItemQualityColor(item.itemLink)

    if color then
        card.spine:SetColorTexture(color[1], color[2], color[3], 1)
        Theme.SetCustomTextColor(card.name, color[1], color[2], color[3])
    else
        -- The client has not cached this item yet, or it never will. Neither
        -- is worth guessing a color for: the name reads plainly and the pane
        -- asks again when the cache fills.
        card.spine:SetColorTexture(1, 1, 1, 0.15)
        Theme.SetTextColor(card.name, "textPrimary")
    end

    card.name:SetText(item.name or "Unknown item")

    local icon = Theme.GetItemIcon(item.itemLink)

    if icon then
        card.icon:SetTexture(icon)
        card.icon:Show()
    else
        card.icon:Hide()
    end

    -- How it was won, then where it came from. The item level used to sit
    -- between them and Aimee took it out: "i removed the ilevel part. i dont
    -- want it to be too cluttered."
    local parts = { item.label or "Unknown" }

    if item.boss and item.boss ~= "" then
        table.insert(parts, item.boss)
    end

    card.meta:SetText(table.concat(parts, " · "))

    card.letter:SetText(SYL.GearTrack.LetterFor(item.itemLink) or "")

    card:Show()

    return color ~= nil
end

function Cards.Hide(cards)
    for _, card in ipairs(cards or {}) do
        card.itemLink = nil
        card:Hide()
    end
end
