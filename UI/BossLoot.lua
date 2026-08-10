-- UI/BossLoot.lua
--
-- The right-hand pane of the Bosses tab: one boss's loot table, either what it
-- still owes you or what it has actually given.
--
-- Split from UI/BossesPanel.lua, which owns the boss rail and the controls.
-- This is a pure renderer — it is handed a boss and the two pieces of state
-- the controls hold, and draws. It decides nothing.
--
-- IT DEFAULTS TO WHAT HAS NOT DROPPED, which is the whole reason the screen
-- exists. What a boss has given you is already answerable from the loot list;
-- what it is still holding is not answerable anywhere else in the game without
-- opening the Adventure Guide and comparing by eye.
--
-- THE CAVEAT IS ON SCREEN, not in a comment. The journal lists what a boss can
-- drop for *any* specialisation, so "never dropped" includes items nobody in
-- the raid can use. Left unsaid, that turns into "this addon says we are owed
-- fourteen items" in an officer's mouth, and the number is wrong in a way that
-- is not their fault.
--
-- READING THE JOURNAL MOVES IT, and the walk covers every raid tier, so it is
-- never done on show. GetMissingIfKnown answers from what has already been
-- read; the full walk is a button in the panel header. A per-hover walk froze
-- the game once already.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local BossLoot = {}
SYL.BossLoot = BossLoot

local PAD = 10
local ROW_HEIGHT = 18
local LIST_TOP = 92
local MAX_ROWS = 16

function BossLoot.Create(parent, width, top)
    local pane = CreateFrame("Frame", nil, parent)

    pane:SetWidth(width)
    pane:SetPoint("TOPRIGHT", 0, -top)
    pane:SetPoint("BOTTOM", 0, 20)

    local back = Theme.CreateSolidTexture(pane, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    pane.width = width
    pane.rows = {}

    pane.heading = Theme.CreateText(pane, Theme.sizes.row, "textPrimary")
    pane.heading:SetPoint("TOPLEFT", PAD, -12)
    pane.heading:SetWidth(width - (PAD * 2))
    pane.heading:SetJustifyH("LEFT")

    pane.subheading = Theme.CreateText(pane, Theme.sizes.rowSmall, "textSecondary")
    pane.subheading:SetPoint("TOPLEFT", PAD, -34)
    pane.subheading:SetWidth(width - (PAD * 2))
    pane.subheading:SetJustifyH("LEFT")

    pane.status = Theme.CreateText(pane, Theme.sizes.rowSmall, "textMuted")
    pane.status:SetPoint("TOPLEFT", PAD, -54)
    pane.status:SetWidth(width - (PAD * 2))
    pane.status:SetJustifyH("LEFT")
    pane.status:SetWordWrap(true)

    -- Pinned to the bottom rather than following the list, so the sentence
    -- that qualifies the number does not move around as the list changes
    -- length. It is the caveat; it has to be findable.
    pane.footnote = Theme.CreateText(pane, Theme.sizes.rowSmall, "textMuted")
    pane.footnote:SetPoint("BOTTOMLEFT", PAD, 8)
    pane.footnote:SetPoint("BOTTOMRIGHT", -PAD, 8)
    pane.footnote:SetJustifyH("LEFT")
    pane.footnote:SetWordWrap(true)

    return pane
end

local function Row(pane, index)
    local row = pane.rows[index]

    if not row then
        row = CreateFrame("Frame", nil, pane)

        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", PAD, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -PAD, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

        row.count = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
        row.count:SetPoint("RIGHT", -3, 0)
        row.count:SetJustifyH("RIGHT")

        row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
        row.name:SetPoint("LEFT", 3, 0)
        row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        pane.rows[index] = row
    end

    return row
end

local function HideRowsFrom(pane, index)
    for position = index, #pane.rows do
        pane.rows[position]:Hide()
    end
end

-- Drawn rows, then the honest tail. A list that stops at sixteen without
-- saying so reads as "that is all of them", which is the one thing it is not.
local function DrawList(pane, items, describe)
    local shown = math.min(MAX_ROWS, #items)

    for index = 1, shown do
        local row = Row(pane, index)
        local name, count = describe(items[index])

        row.name:SetText(name)
        row.count:SetText(count or "")
        row:Show()
    end

    if #items > shown then
        local row = Row(pane, shown + 1)

        row.name:SetText("+ " .. (#items - shown) .. " more")
        Theme.SetTextColor(row.name, "textMuted")
        row.count:SetText("")
        row:Show()

        HideRowsFrom(pane, shown + 2)
    else
        HideRowsFrom(pane, shown + 1)
    end
end

function BossLoot.Render(pane, boss, mode, journalRead)
    if not boss then
        pane.heading:SetText("No boss selected")
        pane.subheading:SetText("")
        pane.status:SetText("Pick a boss on the left.")
        pane.footnote:SetText("")

        HideRowsFrom(pane, 1)

        return
    end

    pane.heading:SetText(tostring(boss.name))

    pane.subheading:SetText(string.format(
        "%s · %s · %d pulls, %d kills, %d drops",
        tostring(boss.instanceName or "Unknown"),
        tostring(boss.difficultyName or "?"),
        boss.pulls or 0, boss.kills or 0, boss.drops or 0
    ))

    if mode == "dropped" then
        pane.footnote:SetText("")

        local items = boss.items or {}

        if #items == 0 then
            pane.status:SetText(
                "Nothing recorded from this boss yet. History starts when the "
                .. "addon is installed and cannot be backfilled."
            )

            HideRowsFrom(pane, 1)

            return
        end

        pane.status:SetText(#items .. " items seen, most dropped first")

        DrawList(pane, items, function(name)
            return name, tostring((boss.itemCounts or {})[name] or 0)
        end)

        return
    end

    -- Not dropped. Never walks the journal on its own; see the file header.
    local missing, total, seen

    if journalRead then
        missing, total, seen = SYL.LootTable.GetMissing(boss)
    else
        missing, total, seen = SYL.LootTable.GetMissingIfKnown(boss)
    end

    if not missing then
        pane.footnote:SetText("")
        pane.status:SetText(
            journalRead
                and ("The Adventure Guide has no loot table for this boss. "
                    .. "Dungeon bosses are never in it — it reads raid "
                    .. "instances only.")
                or ("Not read yet. Press \"Read the Adventure Guide\" above. "
                    .. "It walks every raid tier, so it is a button rather "
                    .. "than something that happens when you open the tab.")
        )

        HideRowsFrom(pane, 1)

        return
    end

    pane.footnote:SetText(
        "The Adventure Guide lists what this boss can drop for any "
        .. "specialisation, so this includes items nobody in your raid can "
        .. "use. It is what the boss has never given you, not what you are owed."
    )

    if #missing == 0 then
        pane.status:SetText(
            "Every one of the " .. (total or 0) .. " items in the journal has "
            .. "dropped at least once."
        )

        HideRowsFrom(pane, 1)

        return
    end

    pane.status:SetText(string.format(
        "%d of %d never dropped · %d seen",
        #missing, total or 0, seen or 0
    ))

    DrawList(pane, missing, function(item)
        return tostring(item.name or "Unknown"), item.slot or ""
    end)
end
