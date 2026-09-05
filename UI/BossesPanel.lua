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
local Count = SYL.Utilities.Count

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
-- The mode toggle is gone: the pane shows both lists now, so there is no
-- half to choose between. See UI/BossLoot.lua.
local difficulty

-- "bosses" or "lockouts". The tab draws one or the other, the way the Keys
-- tab already swaps between keystones and dungeon lockouts -- same control in
-- the same corner, so it is a pattern rather than a new idea.
--
-- Raid lockouts are here and not on Keys because Keys is about Mythic+ and a
-- raid lockout is not. Aimee: "this raid lockout info should not be in the
-- keys tab."
local view = "bosses"
local journalRead = false
local Refresh

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

-- ONE DIFFICULTY AT A TIME. Aimee: "can we have a filter there so we dont see
-- all difficulties at once?"
--
-- A boss is keyed per difficulty -- Core/BossStats.lua does that deliberately,
-- since Heroic and Normal are different loot tables and different luck -- so
-- the rail listed her eight Heroic bosses beside the same eight on Normal and
-- six more on LFR. Twenty-two rows for a raid with eight bosses in it.
--
-- The difficulty is the one saved in Core/TierProgress.lua, shared with the
-- dashboard tile rather than kept again here: "which difficulty are we
-- talking about" should be one answer everywhere in the addon, not one per
-- screen.
--
-- ALL is a real choice and is kept, because a guild that raids two
-- difficulties in a week genuinely wants to compare them.
local function Build()
    local bosses = SYL.BossStats.Build(
        SYL.GetActiveDrops(), SYL.GetActiveRaids()
    )

    SYL.BossStats.SortByRecent(bosses)

    if difficulty == "all" then
        return bosses
    end

    local kept = {}

    for _, boss in ipairs(bosses) do
        if boss.difficultyID == difficulty then
            table.insert(kept, boss)
        end
    end

    return kept
end

-- The chooser walks the four difficulties and then ALL, so every state is one
-- press away and nothing is unreachable.
local function NextDifficulty(current)
    if current == "all" then
        return SYL.TierProgress.DIFFICULTIES[1].id
    end

    for index, entry in ipairs(SYL.TierProgress.DIFFICULTIES) do
        if entry.id == current then
            local following = SYL.TierProgress.DIFFICULTIES[index + 1]

            return following and following.id or "all"
        end
    end

    return "all"
end

local function DifficultyLabel(current)
    if current == "all" then
        return "All"
    end

    return SYL.TierProgress.Label(current)
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

    -- ONLY WHEN IT TELLS YOU SOMETHING. With a difficulty chosen, every row
    -- carries the same tag -- "HC" eight times down a list that already says
    -- Heroic on the button above it. On ALL it is the only thing telling two
    -- otherwise identical rows apart.
    row.difficulty:SetText(
        difficulty == "all"
            and (SYL.Utilities.ShortDifficulty(
                boss.difficultyID, boss.difficultyName) or "")
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

    frame.viewButton.label:SetText(view == "bosses" and "Lockouts" or "Bosses")

    -- THE BOSS LIST AND ITS PANE GO AWAY ENTIRELY in the lockouts view, or
    -- they sit under it. Hiding the container is not enough: the rows, the
    -- pane and the caption are all parented to the panel rather than to a
    -- body frame, which is the same reason UI/SelectionBar.lua has a HideAll.
    if view == "lockouts" then
        for _, row in ipairs(rows) do
            row:Hide()
        end

        frame.empty:Hide()
        frame.caption:SetText("")
        frame.modeButton:Hide()
        frame.readButton:Hide()

        SYL.BossLoot.Hide(frame.pane)

        frame.lockouts:Show()
        SYL.RaidLockoutsView.Refresh()

        return
    end

    frame.lockouts:Hide()
    frame.modeButton:Show()
    frame.readButton:Show()

    local bosses = Build()

    difficulty = difficulty or SYL.TierProgress.GetDifficulty()

    frame.modeButton.label:SetText(DifficultyLabel(difficulty))
    Theme.SetTextColor(
        frame.modeButton.label,
        difficulty == "all" and "textPrimary" or "accent"
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

        SYL.BossLoot.Render(frame.pane, nil, nil, journalRead)
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

    SYL.BossLoot.Render(
        frame.pane, FindByKey(bosses, selectedKey), nil, journalRead
    )

    frame.caption:SetText(
        Count(#bosses, "boss", "bosses")
        .. " recorded · kept apart by difficulty"
    )
end

BossesPanel.Refresh = Refresh

-- The controls go through these rather than closing over the locals, so what
-- a button does has a name and can be driven without a click. The journal walk
-- in particular is worth being able to assert has NOT happened.
function BossesPanel.SetDifficulty(next)
    difficulty = next

    -- The chosen difficulty is shared with the dashboard, so picking Heroic
    -- here is picking it there. ALL is this screen's own and is not saved
    -- into that setting -- the tile has no sensible "all" to show.
    if next ~= "all" then
        SYL.TierProgress.SetDifficulty(next)
    end

    -- A boss selected on another difficulty is not on this list any more.
    selectedKey = nil
    offset = 0

    Refresh()
end

function BossesPanel.CycleDifficulty()
    BossesPanel.SetDifficulty(NextDifficulty(difficulty))
end

-- ALSO WHAT FILLS THE NIGHT PANE'S BOSS TOTAL.
--
-- The walk counts bosses per raid as it goes -- see
-- Core/EncounterJournal.lua -- which is what turns "5 bosses down" on the
-- calendar into "5 of 8". IsAvailable is what actually walks; journalRead
-- only lets this panel ask for the expensive lookups.
function BossesPanel.ReadJournal()
    journalRead = true

    SYL.EncounterJournal.IsAvailable()

    Refresh()

    -- The calendar is very likely open behind this, and its denominators have
    -- just become knowable.
    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

function BossesPanel.ToggleView()
    view = view == "bosses" and "lockouts" or "bosses"

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
        Theme.CreateButton(frame, 78, 20, "Heroic", function()
            BossesPanel.CycleDifficulty()
        end)

    frame.modeButton:SetPoint("TOPLEFT", title, "TOPRIGHT", 14, -2)

    SYL.Tooltips.Attach(
        frame.modeButton,
        "Which difficulty",
        "A boss is recorded once per difficulty, because Heroic and Normal "
        .. "are different loot tables and different luck -- so without this "
        .. "the list holds every boss three or four times. Shared with the "
        .. "dashboard's tier progress, so both screens mean the same thing "
        .. "by Heroic."
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

    -- The raid lockouts, as a second view of this tab.
    frame.viewButton =
        Theme.CreateButton(frame, 100, 20, "Lockouts", function()
            BossesPanel.ToggleView()
        end)

    frame.viewButton:SetPoint("LEFT", frame.readButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.viewButton,
        "Bosses / Lockouts",
        "Lockouts shows which raids each of your characters is saved to this "
        .. "week and how many bosses are already dead on each. It fills in as "
        .. "you log into them, the same way keystones do."
    )

    frame.pane = SYL.BossLoot.Create(frame, PANE_WIDTH, LIST_TOP - 8)

    frame.lockouts = SYL.RaidLockoutsView.Create(frame)
    -- LIST_TOP, the same offset the boss rail's first row uses, because it
    -- clears the control row by 8px -- and the same number UI/LockoutsGrid.lua
    -- uses for the identical control on the Keys tab.
    --
    -- At LIST_TOP - 12 the view began at 22, and the Bosses/Lockouts button
    -- ends at 26: the BOSSES DOWN heading was drawn 4px up into it. That
    -- button is the only way back out of this view, so it cannot be hidden
    -- here the way the other two are. The view simply starts 12px lower.
    frame.lockouts:SetPoint("TOPLEFT", 2, -LIST_TOP)
    frame.lockouts:SetPoint("BOTTOMRIGHT", -2, 0)

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
