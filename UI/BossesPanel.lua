-- UI/BossesPanel.lua
--
-- The Bosses tab: a fixed rail of every boss on the left, and that boss's loot
-- table on the right.
--
-- TWO PANES RATHER THAN A TABLE OF EVERYTHING. The boss window this replaces
-- put pulls, kills, drops, upgrades and an items column on one row, which
-- answers "how is the tier going" and cannot answer "what has this boss never
-- given us" without a column per item. A rail plus a detail pane trades a
-- column for a click and gets the whole loot table in return.
--
-- The rail is sorted by BossStats.SortByRecent — most recently killed first,
-- because a raid leader is nearly always asking about this week. Difficulty is
-- part of a boss's identity here, not a filter: the same boss on Heroic and on
-- Mythic are two rows, because they are two different problems and folding
-- them would average a farm kill with a progression wall.
--
-- READING THE JOURNAL IS A BUTTON. It walks every raid tier and it moves the
-- player's own Adventure Guide selection, so it is never done on show. Until
-- it is pressed the pane answers from whatever has already been read.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local BossesPanel = {}
SYL.BossesPanel = BossesPanel

local RAIL_WIDTH = 250
local GUTTER = 12
local PANE_WIDTH = 868 - RAIL_WIDTH - GUTTER

local ROW_HEIGHT = 20
local LIST_TOP = 34
local VISIBLE_ROWS = 18

local frame
local rows = {}
local offset = 0
local selectedKey
local mode = "missing"
local journalRead = false
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

local function Build()
    local bosses = SYL.BossStats.Build(SYL.GetAllDrops(), SYL.GetAllRaids())

    SYL.BossStats.SortByRecent(bosses)

    return bosses
end

local function FindByKey(bosses, key)
    for _, boss in ipairs(bosses) do
        if boss.key == key then
            return boss
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- The rail
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(LIST_TOP + (index - 1) * ROW_HEIGHT))
    row:SetWidth(RAIL_WIDTH)

    local hover = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    hover:SetAllPoints()
    hover:Hide()

    row.selected = Theme.CreateSolidTexture(row, "accentMuted", "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:Hide()

    row:SetScript("OnEnter", function() hover:Show() end)
    row:SetScript("OnLeave", function() hover:Hide() end)

    row.kills = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.kills:SetPoint("RIGHT", -6, 0)
    row.kills:SetJustifyH("RIGHT")

    row.difficulty = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.difficulty:SetPoint("RIGHT", row.kills, "LEFT", -8, 0)
    row.difficulty:SetJustifyH("RIGHT")

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row.difficulty, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function()
        BossesPanel.Select(row.bossKey)
    end)

    rows[index] = row

    return row
end

local function DrawRow(row, boss, isSelected)
    row.bossKey = boss.key

    row.name:SetText(tostring(boss.name))

    row.difficulty:SetText(
        SYL.Utilities.ShortDifficulty(boss.difficultyID, boss.difficultyName)
        or ""
    )

    -- A boss pulled and never killed is the interesting case on a progression
    -- night, so it reads as 0/4 rather than as a bare zero.
    row.kills:SetText((boss.kills or 0) .. "/" .. (boss.pulls or 0))

    if isSelected then
        row.selected:Show()
        Theme.SetTextColor(row.name, "textPrimary")
    else
        row.selected:Hide()
        Theme.SetTextColor(row.name, (boss.kills or 0) > 0 and "textPrimary" or "textSecondary")
    end

    row:Show()
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

Refresh = function()
    if not frame then
        return
    end

    local bosses = Build()

    frame.modeButton.label:SetText(mode == "missing" and "Not dropped" or "Dropped")
    Theme.SetTextColor(
        frame.modeButton.label,
        mode == "missing" and "accent" or "textPrimary"
    )

    local maxOffset = math.max(0, #bosses - VISIBLE_ROWS)

    if offset > maxOffset then
        offset = maxOffset
    end

    if #bosses == 0 then
        for _, row in ipairs(rows) do
            row:Hide()
        end

        frame.empty:SetText(
            "No bosses recorded yet. This fills in from the next pull — "
            .. "history starts when the addon is installed and cannot be "
            .. "backfilled."
        )
        frame.empty:Show()

        SYL.BossLoot.Render(frame.pane, nil, mode, journalRead)
        frame.caption:SetText("")

        return
    end

    frame.empty:Hide()

    -- Selecting the first boss rather than nothing: the pane exists to be
    -- read, and a tab that opens on "pick something" wastes the click that
    -- got here. Recent-first means the default is this week's boss.
    if not selectedKey or not FindByKey(bosses, selectedKey) then
        selectedKey = bosses[1].key
    end

    for index = 1, VISIBLE_ROWS do
        local boss = bosses[index + offset]
        local row = rows[index] or CreateRow(index)

        if boss then
            DrawRow(row, boss, boss.key == selectedKey)
        else
            row:Hide()
        end
    end

    SYL.BossLoot.Render(frame.pane, FindByKey(bosses, selectedKey), mode, journalRead)

    frame.caption:SetText(
        #bosses .. " bosses recorded · kept apart by difficulty"
    )
end

BossesPanel.Refresh = Refresh

-- The controls go through these rather than closing over the locals, so what
-- a button does has a name and can be driven without a click. The journal walk
-- in particular is worth being able to assert has NOT happened.
function BossesPanel.SetMode(next)
    mode = (next == "dropped") and "dropped" or "missing"

    Refresh()
end

function BossesPanel.ToggleMode()
    BossesPanel.SetMode(mode == "missing" and "dropped" or "missing")
end

function BossesPanel.ReadJournal()
    journalRead = true

    Refresh()
end

function BossesPanel.Select(key)
    selectedKey = key

    Refresh()
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function BossesPanel.Create(parent)
    frame = CreateFrame("Frame", nil, parent)

    frame:SetPoint("TOPLEFT", 16, -100)
    frame:SetPoint("BOTTOMRIGHT", -16, 52)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText("BOSSES")

    frame.modeButton =
        Theme.CreateButton(frame, 110, 20, "Not dropped", function()
            BossesPanel.ToggleMode()
        end)

    frame.modeButton:SetPoint("TOPLEFT", title, "TOPRIGHT", 14, -2)

    SYL.Tooltips.Attach(
        frame.modeButton,
        "Not dropped / Dropped",
        "Not dropped lists what the Adventure Guide says this boss can give "
        .. "and never has. Dropped lists what it actually gave you, most "
        .. "frequent first."
    )

    -- Separate from the mode toggle on purpose. Switching the view is free;
    -- this one walks every raid tier and moves the player's own Adventure
    -- Guide selection, so it has to be asked for.
    frame.readButton =
        Theme.CreateButton(frame, 190, 20, "Read the Adventure Guide", function()
            BossesPanel.ReadJournal()
        end)

    frame.readButton:SetPoint("LEFT", frame.modeButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.readButton,
        "Read the Adventure Guide",
        "Walks every raid tier to learn what each boss can drop. It moves "
        .. "your own Adventure Guide selection and puts it back, and it is a "
        .. "button rather than automatic because doing it on every hover "
        .. "froze the game."
    )

    frame.pane = SYL.BossLoot.Create(frame, PANE_WIDTH, LIST_TOP - 8)

    frame.empty = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.empty:SetPoint("TOPLEFT", 2, -(LIST_TOP + 6))
    frame.empty:SetWidth(RAIL_WIDTH)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWordWrap(true)
    frame.empty:Hide()

    frame.caption = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 2, 2)
    frame.caption:SetWidth(RAIL_WIDTH + GUTTER)
    frame.caption:SetJustifyH("LEFT")

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #(Build()) - VISIBLE_ROWS)

        offset = math.max(0, math.min(maxOffset, offset - delta))

        Refresh()
    end)

    frame:SetScript("OnShow", Refresh)

    frame:Hide()

    return frame
end
