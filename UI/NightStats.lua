-- UI/NightStats.lua
--
-- The dense stat panel under the Nights calendar: one day, everything known
-- about it.
--
-- THIS REPLACED A TABLE, and the table was deleted rather than moved. A list
-- of nights under a grid of nights is the same information twice, and the one
-- that could not be scanned at a glance was the list. The grid answers "when
-- did we raid"; this answers "what happened that night", and only for the day
-- that was clicked.
--
-- Split from UI/NightsPanel.lua, which owns the grid and the month navigation.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local NightStats = {}
SYL.NightStats = NightStats

local PAD = 4
local COLUMNS = 4

function NightStats.Create(parent, height)
    local panel = CreateFrame("Frame", nil, parent)

    panel:SetHeight(height)
    panel:SetPoint("BOTTOMLEFT", 0, 18)
    panel:SetPoint("BOTTOMRIGHT", 0, 18)

    local back = Theme.CreateSolidTexture(panel, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    panel.heading = Theme.CreateText(panel, Theme.sizes.row, "textPrimary")
    panel.heading:SetPoint("TOPLEFT", 10, -10)

    panel.subheading = Theme.CreateText(panel, Theme.sizes.rowSmall, "textSecondary")
    panel.subheading:SetPoint("TOPLEFT", 10, -32)
    panel.subheading:SetPoint("TOPRIGHT", -10, -32)
    panel.subheading:SetJustifyH("LEFT")
    panel.subheading:SetWordWrap(false)

    -- A fixed grid of figures rather than a sentence, because the numbers are
    -- compared between nights more often than they are read once.
    panel.figures = {}

    for index = 1, 8 do
        local column = (index - 1) % COLUMNS
        local row = math.floor((index - 1) / COLUMNS)

        local holder = CreateFrame("Frame", nil, panel)

        holder:SetSize(150, 34)
        holder:SetPoint("TOPLEFT", 10 + column * 158, -(58 + row * 38))

        holder.value = Theme.CreateText(holder, Theme.sizes.row, "textPrimary")
        holder.value:SetPoint("TOPLEFT", 0, 0)

        holder.label = Theme.CreateText(holder, Theme.sizes.rowSmall, "textMuted")
        holder.label:SetPoint("TOPLEFT", 0, -17)

        panel.figures[index] = holder
    end

    return panel
end

local function SetFigure(panel, index, value, label, colorKey)
    local holder = panel.figures[index]

    if not holder then
        return
    end

    holder.value:SetText(tostring(value))
    holder.label:SetText(label)

    Theme.SetTextColor(holder.value, colorKey or "textPrimary")

    holder:Show()
end

local function HideFrom(panel, index)
    for position = index, #panel.figures do
        panel.figures[position]:Hide()
    end
end

-- "Talestra (holiday) · set by Aimee". The author is on every line, because an
-- absence is somebody's claim about another person rather than something the
-- client saw, and the person who knows it is wrong needs to know who to ask.
local function AbsenceLine(entry)
    return tostring(entry.name)
        .. (entry.reason and (" (" .. entry.reason .. ")") or "")
        .. (entry.setBy and ("  ·  set by " .. entry.setBy) or "")
end

local function DescribeAbsences(dayKey)
    if not dayKey then
        return nil, 0
    end

    local out = SYL.Absences.WhoIsOut(dayKey)

    if #out == 0 then
        return nil, 0
    end

    local lines = {}

    for _, entry in ipairs(out) do
        table.insert(lines, AbsenceLine(entry))
    end

    return table.concat(lines, "\n"), #out
end

function NightStats.Render(panel, day, dayKey)
    if not day then
        local absences, count = DescribeAbsences(dayKey)

        -- A day with nobody there yet is still worth opening if somebody has
        -- been marked out on it. Before this, every future day answered "no
        -- night selected" and the absences were invisible on the one screen
        -- built to answer "who is around".
        if absences then
            panel.heading:SetText(tostring(dayKey))
            panel.subheading:SetText(
                count .. (count == 1 and " person out" or " people out")
                .. "\n" .. absences
            )

            HideFrom(panel, 1)

            return
        end

        panel.heading:SetText("No night selected")
        panel.subheading:SetText(
            "Pick a shaded day above. Shaded days are nights this addon "
            .. "recorded — history starts at install and cannot be backfilled."
        )

        HideFrom(panel, 1)

        return
    end

    -- MM-DD-YYYY on screen, from a key that stays ISO. See Core/NightIndex.lua.
    panel.heading:SetText(
        day.startedAt and SYL.Utilities.FormatDateOnly(day.startedAt)
        or tostring(day.key)
    )

    local where = table.concat(day.instanceNames, ", ")
    local how = table.concat(day.difficultyNames, ", ")

    -- Who was marked out, on a night that happened. rosterCount above is a
    -- historical fact about who turned up; this is what was said beforehand,
    -- and the two disagreeing is worth being able to see.
    local absences = DescribeAbsences(dayKey or day.key)

    panel.subheading:SetText(
        (where ~= "" and where or "Unknown")
        .. (how ~= "" and ("  ·  " .. how) or "")
        .. (#day.sessions > 1
            and ("  ·  " .. #day.sessions .. " sessions, one night")
            or "")
        .. (absences and ("\nOut: " .. absences) or "")
    )

    SetFigure(panel, 1, day.kills .. "/" .. day.pulls, "bosses killed")
    SetFigure(panel, 2, day.rosterCount, "raiders there")
    SetFigure(panel, 3, day.drops, "drops")
    SetFigure(panel, 4,
        day.upgrades, "upgrades",
        day.upgrades > 0 and "accent" or "textMuted")

    SetFigure(panel, 5,
        math.floor(day.minutes / 60) .. "h " .. string.format("%02dm", day.minutes % 60),
        "in the instance")

    -- The number a raid leader gets asked about the next day, and the same
    -- subtraction the end of night summary makes.
    local emptyHanded = math.max(0, day.rosterCount - day.upgrades)

    SetFigure(panel, 6,
        emptyHanded, "went home with nothing",
        emptyHanded > 0 and "warning" or "textMuted")

    SetFigure(panel, 7,
        day.pulls > 0 and string.format("%d%%", math.floor((day.kills / day.pulls) * 100)) or "—",
        "of pulls killed")

    SetFigure(panel, 8,
        day.rosterCount > 0 and string.format("%.1f", day.drops / day.rosterCount) or "—",
        "drops per raider")

    HideFrom(panel, 9)
end
