-- UI/BossTooltip.lua
--
-- The names behind the ITEMS column. "2/6" says how much of a boss's loot
-- table has been seen, which is not much use without knowing which two.
--
-- Hovering the count lists both halves: what has dropped, with how many
-- times, and what never has.
--
-- Its own file because BossWindow and LootTable are both close to the
-- project's 400 line limit, and because this is presentation — LootTable
-- answers the question, this one phrases it.
--
-- HOVERING MUST STAY CHEAP, and it takes two guards rather than one.
-- EncounterJournal.IsAvailable reads a tier when it has nothing, so this asks
-- IsReady instead. That alone was not enough: a boss missing from the tiers
-- already read still sent the walk through every remaining one, which is why
-- the loot lookup here is the IfKnown variant.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local BossTooltip = {}
SYL.BossTooltip = BossTooltip

-- Long tables would run off the screen, and the point is a glance rather
-- than a catalog. The remainder is counted rather than dropped silently.
local MAX_LINES = 12

local function Color(key)
    local color = Theme.colors[key] or Theme.colors.textPrimary

    return color[1], color[2], color[3]
end

local function AddCapped(names, formatter, colorKey)
    local shown = math.min(#names, MAX_LINES)

    for index = 1, shown do
        GameTooltip:AddLine(formatter(names[index]), Color(colorKey))
    end

    if #names > shown then
        GameTooltip:AddLine(
            "and " .. (#names - shown) .. " more", Color("textMuted")
        )
    end
end

-- Everything this guild has seen drop, commonest first, which is the order
-- BossStats already sorted them into.
local function AddDropped(boss)
    if #(boss.items or {}) == 0 then
        GameTooltip:AddLine("Nothing recorded yet", Color("textMuted"))

        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
        "Dropped (" .. #boss.items .. ")", Color("accent")
    )

    AddCapped(boss.items, function(name)
        local count = boss.itemCounts[name] or 0

        return "  " .. name .. (count > 1 and ("  x" .. count) or "")
    end, "textPrimary")
end

local function AddNeverDropped(boss)
    if not SYL.Features.IsEnabled("lootTables") then
        return
    end

    -- IsReady rather than IsAvailable: see the header. A hover must not
    -- start reading the journal.
    if not SYL.EncounterJournal.IsReady() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "Press Loot tables to read the journal", Color("textMuted")
        )

        return
    end

    -- IfKnown, not GetMissing: a boss absent from the tiers already read
    -- would otherwise send the journal walk through every remaining one, and
    -- a dungeon boss is never in any of them, so that walk always ran and
    -- always failed. Seconds of frozen game, per hover.
    local missing, total = SYL.LootTable.GetMissingIfKnown(boss)

    if not missing then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "No loot table for this boss", Color("textMuted")
        )

        return
    end

    if #missing == 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "All " .. total .. " items have dropped", Color("accent")
        )

        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
        "Never dropped (" .. #missing .. " of " .. total .. ")",
        Color("textSecondary")
    )

    AddCapped(missing, function(item)
        return "  " .. tostring(item.name)
    end, "textMuted")
end

local function Show(anchor, boss)
    if not boss then
        return
    end

    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")

    local difficulty = SYL.Utilities.ShortDifficulty(
        boss.difficultyID, boss.difficultyName
    )

    GameTooltip:AddLine(
        tostring(boss.name) .. (difficulty and ("  " .. difficulty) or "")
    )

    AddDropped(boss)
    AddNeverDropped(boss)

    GameTooltip:Show()
end

-- Attaches an invisible hit area over one column. FontStrings cannot take
-- mouse events, so the count itself is not hoverable; this sits on top of it.
--
-- The row is passed rather than the boss, because rows are pooled and reused:
-- the boss on a row changes every refresh, and capturing one here would
-- pin the tooltip to whatever was on screen when the row was built.
function BossTooltip.Attach(row, offsetX, width, height)
    local hover = CreateFrame("Frame", nil, row)

    hover:SetPoint("LEFT", offsetX, 0)
    hover:SetSize(width, height)
    hover:EnableMouse(true)

    hover:SetScript("OnEnter", function(self)
        Show(self, row.boss)
    end)

    hover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return hover
end
