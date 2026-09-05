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
-- drop for *any* specialization, so "never dropped" includes items nobody in
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
local Count = SYL.Utilities.Count

local BossLoot = {}
SYL.BossLoot = BossLoot

local PAD = 10
local ROW_HEIGHT = 18
local LIST_TOP = 74

-- TWO COLUMNS, NOT A TOGGLE. Aimee: "do we need a button that says dropped
-- and not dropped? couldnt it just show 2 lists of dropped and not dropped?"
--
-- No, and yes. The toggle was answering "which half of the answer do you want
-- to see", which is not a question anybody has -- what a boss has given you
-- and what it has not are two halves of one thought, and the pane is 606
-- wide, which is two columns and a gutter with room to spare.
local COLUMN_GAP = 12
-- HOW MANY ROWS FIT ABOVE THE FOOTNOTE, which is pinned inside this pane.
--
--    74   LIST_TOP -- heading, subheading and the column headings above it
--  +N*18  the rows
--  + 14   clearance
--  + 40   three wrapped lines of the caveat at 12 plus its rule
--  +  8   bottom inset
--  = 398  the pane
--
-- Solved rather than typed, because the caveat is the thing that grows: it
-- was two lines, it is three now that it says which difficulty the lists are
-- for, and a hardcoded row count is how the last row ended up underneath it
-- the first time.
local FOOTNOTE_SPACE = 62

local function MaxRows(pane)
    local height = (pane and pane:GetHeight()) or 398

    if height <= 1 then
        height = 398
    end

    return math.max(1, math.floor(
        (height - LIST_TOP - FOOTNOTE_SPACE) / ROW_HEIGHT
    ))
end

function BossLoot.Create(parent, width, top)
    local pane = CreateFrame("Frame", nil, parent)

    pane:SetWidth(width)
    pane:SetPoint("TOPRIGHT", 0, -top)
    pane:SetPoint("BOTTOM", 0, 20)

    local back = Theme.CreateSolidTexture(pane, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    pane.width = width

    -- One pool per column; see Row.
    pane.rows = { given = {}, missing = {} }

    pane.heading = Theme.CreateText(pane, Theme.sizes.row, "textPrimary")
    pane.heading:SetPoint("TOPLEFT", PAD, -12)
    pane.heading:SetWidth(width - (PAD * 2))
    pane.heading:SetJustifyH("LEFT")

    pane.subheading = Theme.CreateText(pane, Theme.sizes.rowSmall, "textSecondary")
    pane.subheading:SetPoint("TOPLEFT", PAD, -34)
    pane.subheading:SetWidth(width - (PAD * 2))
    pane.subheading:SetJustifyH("LEFT")

    -- The two column headings, which is where "which list am I looking at"
    -- is answered now that there are two of them and no toggle.
    local column = (width - PAD * 2 - COLUMN_GAP) / 2

    pane.givenHeading =
        Theme.CreateText(pane, Theme.sizes.columnHeader, "textMuted")
    pane.givenHeading:SetPoint("TOPLEFT", PAD, -(LIST_TOP - 16))

    pane.givenCount =
        Theme.CreateText(pane, Theme.sizes.columnHeader, "textMuted")
    pane.givenCount:SetPoint("TOPLEFT", PAD, -(LIST_TOP - 16))
    pane.givenCount:SetWidth(column)
    pane.givenCount:SetJustifyH("RIGHT")

    pane.missingHeading =
        Theme.CreateText(pane, Theme.sizes.columnHeader, "textMuted")
    pane.missingHeading:SetPoint(
        "TOPLEFT", PAD + column + COLUMN_GAP, -(LIST_TOP - 16)
    )

    pane.missingCount =
        Theme.CreateText(pane, Theme.sizes.columnHeader, "textMuted")
    pane.missingCount:SetPoint(
        "TOPLEFT", PAD + column + COLUMN_GAP, -(LIST_TOP - 16)
    )
    pane.missingCount:SetWidth(column)
    pane.missingCount:SetJustifyH("RIGHT")

    -- The rule between them, so two lists read as two rather than as one
    -- list with a wide gap in it.
    pane.divider = Theme.CreateSolidTexture(pane, "separator", "ARTWORK")
    pane.divider:SetPoint("TOPLEFT", PAD + column + COLUMN_GAP / 2 - 1,
        -(LIST_TOP - 20))
    pane.divider:SetWidth(1)
    pane.divider:SetPoint("BOTTOM", pane, "BOTTOM", 0, 56)

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

-- One row in one column. `side` is "given" or "missing", so the two lists
-- keep separate pools -- shared rows would mean the left list's leftovers
-- showing up on the right when one is longer than the other.
local function Row(pane, side, index)
    pane.rows[side] = pane.rows[side] or {}

    local row = pane.rows[side][index]

    if row then
        return row
    end

    local column = (pane.width - PAD * 2 - COLUMN_GAP) / 2
    local left = PAD + (side == "missing" and (column + COLUMN_GAP) or 0)

    row = CreateFrame("Frame", nil, pane)

    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(column)
    row:SetPoint("TOPLEFT", left, -(LIST_TOP + (index - 1) * ROW_HEIGHT))

    -- THE ITEM'S OWN TOOLTIP, which this screen never had. Aimee: "can the
    -- items on both lists show the actual tooltip for the item like we have
    -- in other places?"
    --
    -- Read on hover rather than captured, because rows are pooled and reused
    -- as the list changes -- the same rule every other list in this addon
    -- follows. The link is what the Adventure Guide or the drop record
    -- carried; without one there is nothing to show and the hover stays
    -- quiet rather than opening an empty tooltip.
    row.hover = SYL.Widgets.MakeItemHoverable(row, function()
        return row.itemLink
    end)

    row.hover:SetAllPoints()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 3, 0)

    row.count = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.count:SetPoint("RIGHT", -3, 0)
    row.count:SetJustifyH("RIGHT")

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    pane.rows[side][index] = row

    return row
end

local function HideRowsFrom(pane, side, index)
    for position = index, #(pane.rows[side] or {}) do
        pane.rows[side][position]:Hide()
    end
end

local function HideAllRows(pane)
    for _, side in ipairs({ "given", "missing" }) do
        HideRowsFrom(pane, side, 1)
    end
end

-- Drawn rows, then the honest tail. A list that stops without saying so reads
-- as "that is all of them", which is the one thing it is not.
local function DrawList(pane, side, items, describe)
    local maximum = MaxRows(pane)
    local shown = math.min(maximum, #items)

    for index = 1, shown do
        local row = Row(pane, side, index)
        local name, count, link, quality = describe(items[index])

        row.itemLink = link
        row.name:SetText(name)
        row.count:SetText(count or "")

        local icon = link and Theme.GetItemIcon(link)

        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        -- Colored by rarity, the way every other item in this addon is, so a
        -- list of names reads as a list of items.
        local color = link and Theme.GetItemQualityColor(link)

        if color then
            row.name:SetTextColor(color.r, color.g, color.b)
        else
            Theme.SetTextColor(row.name, "textPrimary")
        end

        row:Show()
    end

    if #items > shown then
        local row = Row(pane, side, shown + 1)

        row.itemLink = nil
        row.icon:Hide()
        row.name:SetText("and " .. (#items - shown) .. " more")
        Theme.SetTextColor(row.name, "textMuted")
        row.count:SetText("")
        row:Show()

        HideRowsFrom(pane, side, shown + 2)
    else
        HideRowsFrom(pane, side, shown + 1)
    end
end

-- THE WHOLE PANE OFF SCREEN, for when the tab is drawing something else.
--
-- Render(pane, nil) empties it but leaves the headings and the "Pick a boss
-- on the left" standing, which is right when there are no bosses and wrong
-- when the tab has swapped to the raid lockouts -- that text would sit
-- underneath them saying to pick something that is not there. Same reason
-- UI/SelectionBar.lua has a HideAll of its own.
function BossLoot.Hide(pane)
    if not pane then
        return
    end

    HideAllRows(pane)

    -- THE FRAME, NOT ITS PARTS. The first version cleared the four font
    -- strings and hid a `pane.background` that does not exist -- the
    -- background is a local in Create and was never put on the pane -- so the
    -- panel's rowAlt block stayed on screen under the lockout list. The test
    -- client answers a function for any field it has not been given, which is
    -- what turned an invented field into an error rather than a silent
    -- nothing.
    pane:Hide()
end

-- Both lists, always. `mode` is gone -- see COLUMN_GAP above.
function BossLoot.Render(pane, boss, _, journalRead)
    -- Shown here rather than in each branch: a pane with no boss selected is
    -- still a pane, and it is Hide that takes it off screen.
    pane:Show()

    if not boss then
        pane.heading:SetText("No boss selected")
        pane.subheading:SetText("")
        pane.givenHeading:SetText("")
        pane.givenCount:SetText("")
        pane.missingHeading:SetText("")
        pane.missingCount:SetText("")
        pane.status:SetText("Pick a boss on the left.")
        pane.footnote:SetText("")

        HideAllRows(pane)

        return
    end

    pane.heading:SetText(tostring(boss.name))

    -- PLAIN WORDS. Aimee: "can you also make sure the text in this section is
    -- very clear and not confusing to other users?" This read
    -- "3 pulls, 2 kills, 5 drops" as a comma list of three different units,
    -- which needs a moment even when you wrote it.
    pane.subheading:SetText(string.format(
        "%s · %s · killed %s · %s from it so far",
        tostring(boss.instanceName or "Unknown"),
        tostring(boss.difficultyName or "?"),
        Count(boss.kills or 0, "time"),
        Count(boss.drops or 0, "item")
    ))

    --------------------------------------------------------------------
    -- What it has given
    --------------------------------------------------------------------

    local items = boss.items or {}

    pane.givenHeading:SetText("IT HAS GIVEN YOU")
    pane.givenCount:SetText(#items > 0 and (#items .. " different") or "")

    if #items == 0 then
        HideRowsFrom(pane, "given", 1)
    else
        DrawList(pane, "given", items, function(name)
            local count = (boss.itemCounts or {})[name] or 0

            return name,
                count > 1 and ("x" .. count) or "",
                (boss.itemLinks or {})[name]
        end)
    end

    --------------------------------------------------------------------
    -- What it has not
    --------------------------------------------------------------------

    local missing, total, seen

    if journalRead then
        missing, total, seen = SYL.LootTable.GetMissing(boss)
    else
        missing, total, seen = SYL.LootTable.GetMissingIfKnown(boss)
    end

    pane.missingHeading:SetText("IT HAS NOT GIVEN YOU")

    if not missing then
        pane.missingCount:SetText("")
        HideRowsFrom(pane, "missing", 1)

        -- The status line carries this rather than the missing column,
        -- because it is about the whole screen and not about one list.
        pane.status:SetText(
            journalRead
                and ("The Adventure Guide has no loot table for this boss, so "
                    .. "the second list cannot be filled in. Dungeon bosses "
                    .. "are never in it -- it covers raids only.")
                or ("Press \"Read the Adventure Guide\" above to fill in the "
                    .. "second list. It reads every raid tier once, which is "
                    .. "why it is a button rather than something that happens "
                    .. "when you open this tab.")
        )

        pane.footnote:SetText("")

        return
    end

    pane.status:SetText("")

    pane.missingCount:SetText(
        (total or 0) > 0 and (#missing .. " of " .. (total or 0)) or ""
    )

    if #missing == 0 then
        HideRowsFrom(pane, "missing", 1)

        local row = Row(pane, "missing", 1)

        row.itemLink = nil
        row.icon:Hide()
        row.name:SetText("Nothing -- it has given you all " .. (total or 0))
        Theme.SetTextColor(row.name, "textMuted")
        row.count:SetText("")
        row:Show()

        HideRowsFrom(pane, "missing", 2)
    else
        DrawList(pane, "missing", missing, function(item)
            return tostring(item.name or "Unknown"),
                item.slot or "",
                item.link
        end)
    end

    --------------------------------------------------------------------
    -- The caveat, which changes what the right-hand number means
    --------------------------------------------------------------------

    -- SAYS WHICH DIFFICULTY, which it never did. Both lists are about one
    -- difficulty of one boss, and "6 of 8 never dropped" reads as a fact
    -- about the raid until you know that.
    pane.footnote:SetText(
        "Both lists are " .. tostring(boss.difficultyName or "this difficulty")
        .. " only. \"Has not given you\" comes from the Adventure Guide, "
        .. "which lists every item a boss can drop for any class -- so some "
        .. "of them are for nobody in your raid. It is what has not dropped, "
        .. "not what you are owed."
    )
end
