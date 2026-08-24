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

    -- WHO IS OUT, WITH ROOM TO SAY SO.
    --
    -- The names were being built correctly and then appended to the subheading
    -- above, which has word wrap off — so a FontString that shows one line was
    -- handed several and drew the first. "1 person out" was the whole of it,
    -- and the names it had just assembled went nowhere. Nothing was missing
    -- from the data and nothing looked broken.
    --
    -- Its own region, wrapping, anchored under the subheading. On a day with
    -- no raid the figures below are hidden and this has the panel to itself,
    -- which is the day somebody is asking about when they click ahead.
    panel.absences = Theme.CreateText(panel, Theme.sizes.rowSmall, "textSecondary")
    panel.absences:SetPoint("TOPLEFT", 10, -52)
    panel.absences:SetPoint("TOPRIGHT", -10, -52)
    panel.absences:SetJustifyH("LEFT")
    panel.absences:SetWordWrap(true)

    -- A fixed grid of figures rather than a sentence, because the numbers are
    -- compared between nights more often than they are read once.
    panel.figures = {}

    for index = 1, 8 do
        local column = (index - 1) % COLUMNS
        local row = math.floor((index - 1) / COLUMNS)

        local holder = CreateFrame("Frame", nil, panel)

        holder:SetSize(150, 34)
        holder:SetPoint("TOPLEFT", 10 + column * 158, -(58 + row * 38))

        -- MOUSE ENABLED, which a plain Frame is not.
        --
        -- Every figure here now carries a hover that names the people or the
        -- bosses behind it, and Tooltips.Attach hooks OnEnter -- which a
        -- mouse-disabled frame never fires. This is the same line whose
        -- absence left all seven dashboard widget tooltips dead: the text was
        -- written, attached, and unreachable.
        holder:EnableMouse(true)

        -- Attached once, at creation, and resolved on hover. The figures are
        -- reused for whichever day is clicked, so a string closed over here
        -- would explain the night that happened to be selected when the
        -- window was first built.
        SYL.Tooltips.Attach(
            holder,
            function(self)
                return self.tipTitle
            end,
            function(self)
                return self.tipBody
            end
        )

        holder.value = Theme.CreateText(holder, Theme.sizes.row, "textPrimary")
        holder.value:SetPoint("TOPLEFT", 0, 0)

        holder.label = Theme.CreateText(holder, Theme.sizes.rowSmall, "textMuted")
        holder.label:SetPoint("TOPLEFT", 0, -17)

        panel.figures[index] = holder
    end

    return panel
end

-- `body` is the hover. The label is its title, because a figure's label is
-- already the shortest true name for what it counts and a second one would
-- only be a second thing to keep in step.
-- HOW MUCH OF THE NIGHT WAS THE GUILD, which is what decides whether the
-- night counts at all.
--
-- Read off the sessions that qualified, so it always reports at least the
-- threshold. A night with two sessions reports the larger of them rather than
-- an average -- the point is to say "this was your raid", not to be exact
-- about a number nobody compares between evenings.
function NightStats.GuildShare(day)
    local best, bestTotal

    for _, session in ipairs(day.sessions or {}) do
        local guilded, total = SYL.RaidSession.GuildCounts(session)

        if total and total > 0 and (not best or guilded > best) then
            best, bestTotal = guilded, total
        end
    end

    return best, bestTotal
end

-- "2h 42m". One place, because three lines were about to format it three
-- ways.
local function Clock(minutes)
    return math.floor(minutes / 60) .. "h "
        .. string.format("%02dm", minutes % 60)
end

-- WHEN THE EVENING RAN, in the words somebody would use out loud.
--
-- Prefers zoned-in to zoned-out, because that is the evening. Falls back to
-- first pull to last pull for every session recorded before arrivals were
-- kept, which is all of them today -- and says "first pull" when it does, so
-- the two are never confused for one another.
function NightStats.DescribeSpan(day)
    local zone = SYL.Utilities.TimeZoneLabel()
    local suffix = zone and (" " .. zone) or ""

    local from, to, label = day.enteredAt, day.leftAt, ""

    if not from or not to then
        from, to, label = day.startedAt, day.endedAt, "first pull "

        for _, session in ipairs(day.sessions or {}) do
            if not to or (session.endedAt or 0) > to then
                to = session.endedAt
            end
        end
    end

    if not from or not to then
        return nil
    end

    local minutes = math.max(0, math.floor((to - from) / 60))

    return label
        .. SYL.Utilities.FormatClock(from)
        .. " - " .. SYL.Utilities.FormatClock(to) .. suffix
        .. "  ·  " .. Clock(minutes)
end

-- WHERE THE TIME WENT, when the night knows.
--
-- Aimee: "how much of our 3 hours were fighting? vs afks?" Only the end of
-- each pull was recorded until now, so this is nil on every night already in
-- the database and says nothing rather than claiming everybody stood still.
--
-- Says so when it is only part of the answer. A night recorded across the
-- change has some pulls with a start and some without, and reporting the
-- fighting it could measure as though that were all of it would understate
-- the raid.
function NightStats.DescribeFighting(day)
    if not day.fightingMinutes or (day.pullsMeasured or 0) == 0 then
        return nil
    end

    local between = math.max(0, (day.minutes or 0) - day.fightingMinutes)

    local text = Clock(day.fightingMinutes) .. " fighting, "
        .. Clock(between) .. " between pulls"

    if (day.pullsMeasured or 0) < (day.pullsTotal or 0) then
        text = text .. " (from " .. day.pullsMeasured
            .. " of " .. day.pullsTotal .. " pulls)"
    end

    return text
end

local function SetFigure(panel, index, value, label, body, colorKey)
    local holder = panel.figures[index]

    if not holder then
        return
    end

    holder.value:SetText(tostring(value))
    holder.label:SetText(label)

    Theme.SetTextColor(holder.value, colorKey or "textPrimary")

    -- nil title means this figure has nothing to say, and Tooltips.Attach
    -- treats that as "show nothing" rather than as an empty box.
    holder.tipTitle = body and label or nil
    holder.tipBody = body

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
-- A day key stays ISO because it is an identifier and reformatting it would
-- re-key every night already recorded — see the dates decision in HANDOFF. On
-- screen it still has to read the way every other date here does.
local function DisplayDay(dayKey)
    local year, month, day = tostring(dayKey):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")

    if not year then
        return tostring(dayKey)
    end

    return month .. "-" .. day .. "-" .. year
end

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

-- A RECORDED RAID THAT IS NOT A GUILD NIGHT.
--
-- Her 2026-08-22 is seven wipes on Ula'tek with 33 people, and clicking that
-- day used to answer "Pick a shaded day" -- an evening she remembers, gone,
-- with nothing on screen to say why. She liked seeing it: "i do like that is
-- says nothing counts but also shows the pulls and the time frame and number
-- of guildies."
--
-- The figure grid stays hidden. Nothing here is a fairness number, and
-- drawing them in the same tiles the real nights use would invite exactly
-- that reading -- her rule: "nothing ever counts to fairness or raid night
-- stuff on those off raids."
local function RenderOther(panel, other)
    panel.heading:SetText(
        other.startedAt and SYL.Utilities.FormatDateOnly(other.startedAt)
        or DisplayDay(other.key)
    )

    local zone = SYL.Utilities.TimeZoneLabel()

    panel.subheading:SetText(
        table.concat({
            table.concat(other.instanceNames, ", "),
            table.concat(other.difficultyNames, ", "),
            other.guilded .. " of " .. other.groupSize .. " guild",
            SYL.Utilities.FormatClock(other.startedAt)
            .. " - " .. SYL.Utilities.FormatClock(other.endedAt)
            .. (zone and (" " .. zone) or ""),
        }, "  ·  ")
    )

    panel.absences:ClearAllPoints()
    panel.absences:SetPoint("TOPLEFT", 10, -56)
    panel.absences:SetPoint("TOPRIGHT", -10, -56)

    panel.absences:SetText(
        "Not a guild night, so nothing here counts."
        .. "\n\n"
        .. SYL.Utilities.Count(other.pulls, "pull")
        .. ", " .. SYL.Utilities.Count(other.kills, "kill")
        .. ". Recorded, and kept out of every fairness figure because only "
        .. other.guilded .. " of the " .. other.groupSize
        .. " people there were in the guild."
    )

    Theme.SetTextColor(panel.absences, "textMuted")

    HideFrom(panel, 1)
end

function NightStats.Render(panel, day, dayKey, other)
    if not day and other then
        RenderOther(panel, other)

        return
    end

    if not day then
        local absences, count = DescribeAbsences(dayKey)

        -- A day with nobody there yet is still worth opening if somebody has
        -- been marked out on it. Before this, every future day answered "no
        -- night selected" and the absences were invisible on the one screen
        -- built to answer "who is around".
        if absences then
            -- MM-DD-YYYY like everywhere else. The key stays ISO because it
            -- is an identifier; showing it raw was the one place a date
            -- reached the screen in the wrong format.
            panel.heading:SetText(DisplayDay(dayKey))

            panel.subheading:SetText(
                count .. (count == 1 and " person out" or " people out")
            )

            -- One per line, with the reason and who said so. The figures are
            -- hidden on a day with no raid, so the whole panel is free.
            panel.absences:ClearAllPoints()
            panel.absences:SetPoint("TOPLEFT", 10, -52)
            panel.absences:SetPoint("TOPRIGHT", -10, -52)
            panel.absences:SetText(absences)
            panel.absences:Show()

            HideFrom(panel, 1)

            return
        end

        panel.heading:SetText("No night selected")
        panel.subheading:SetText(
            "Pick a shaded day above. Shaded days are nights this addon "
            .. "recorded — history starts at install and cannot be backfilled."
        )

        panel.absences:SetText("")

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
    local absences, absentCount = DescribeAbsences(dayKey or day.key)

    -- THE SUBHEADING CARRIES THE TIME AND THE GUILD SHARE.
    --
    -- The time was a figure reading "Xh YYm in the instance", which was
    -- neither the instance nor, on a multi-session night, the evening. Here
    -- it can say what it actually is: when the group got there, when the last
    -- pull ended, and how long that was.
    --
    -- 12-hour with a zone, which is Aimee's: "the time should be in 12 hours
    -- am/pm format rather than 24 hour format [...] just make sure it says
    -- MST or EST."
    --
    -- The guild share is here because it decides whether the night exists at
    -- all, it became a setting in 0.4.0, and there was nothing on screen
    -- anywhere to say so -- moving that slider silently adds and removes
    -- nights from every fairness figure in the addon.
    local parts = { where ~= "" and where or "Unknown" }

    if how ~= "" then
        table.insert(parts, how)
    end

    local guilded, total = NightStats.GuildShare(day)

    if guilded then
        table.insert(parts, guilded .. " of " .. total .. " guild")
    end

    local span = NightStats.DescribeSpan(day)

    if span then
        table.insert(parts, span)
    end

    local fighting = NightStats.DescribeFighting(day)

    if fighting then
        table.insert(parts, fighting)
    end

    if #day.sessions > 1 then
        table.insert(parts, #day.sessions .. " sessions, one night")
    end

    panel.subheading:SetText(table.concat(parts, "  ·  "))

    -- WHO WAS NOT THERE, on its own line at the bottom.
    --
    -- It used to be anchored at -52, six pixels above the first row of
    -- figures, and it wraps -- so a night with two people out drew straight
    -- through them. At the bottom it has the width of the pane.
    --
    -- Two different facts, kept apart. "Marked out" is somebody who said
    -- beforehand; "never came" is somebody on the raid team who simply was
    -- not there and never said. Folding them together lets a silent no-show
    -- hide among the people who did the right thing.
    panel.absences:ClearAllPoints()
    panel.absences:SetPoint("BOTTOMLEFT", 10, 6)
    panel.absences:SetPoint("BOTTOMRIGHT", -10, 6)

    local said = {}

    for _, entry in ipairs(SYL.Absences.WhoIsOut(dayKey or day.key) or {}) do
        table.insert(said, tostring(entry.name))
    end

    local missing = {}

    for _, person in ipairs(
        SYL.NightFigures.NeverCame(day, dayKey or day.key)
    ) do
        table.insert(missing, tostring(person.name))
    end

    local lines = {}

    if #said > 0 then
        table.insert(lines, "Out: " .. table.concat(said, ", "))
    end

    if #missing > 0 then
        table.insert(lines, "Never came: " .. table.concat(missing, ", "))
    end

    -- WHERE THE NIGHT WENT, on the same line as the people, because they are
    -- the two things somebody reads after the figures and there is one line
    -- of room for both.
    local story = SYL.NightFigures.MostPulls(day)

    if story then
        table.insert(lines, story)
    end

    panel.absences:SetText(table.concat(lines, "     ·     "))

    -- FOUR FIGURES, AND EVERY ONE OF THEM CARRIES NAMES.
    --
    -- UI/NightFigures.lua works out what each says and what its hover holds.
    -- Four of the eight that used to be here were wrong and two said nothing;
    -- that file's header has the whole account.
    SetFigure(panel, 1, SYL.NightFigures.Bosses(day))
    SetFigure(panel, 2, SYL.NightFigures.Raiders(day, dayKey or day.key))
    SetFigure(panel, 3, SYL.NightFigures.Loot(day))

    local gearValue, gearLabel, gearBody = SYL.NightFigures.Gear(day)

    SetFigure(
        panel, 4, gearValue, gearLabel, gearBody,
        day.upgrades > 0 and "accent" or "warning"
    )

    HideFrom(panel, 5)
end
