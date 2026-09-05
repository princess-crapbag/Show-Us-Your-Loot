-- UI/RaidersDetailParts.lua
--
-- The pooled pieces the Raiders detail pane is assembled from: a flowed line
-- of text, a raid night's heading, and one item card.
--
-- Split from UI/RaidersDetail.lua at the 400-line limit, the same division
-- DashboardWidgets and DashboardParts already use one screen along. That file
-- decides what a selected raider says; this one owns the frames it says it
-- with, and the rule that every one of them is put away again before the next
-- render.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Parts = {}
SYL.RaidersDetailParts = Parts

local PAD = 10

-- A night's heading, the rule under it, and the gap before the next night.
-- Published because the pane does the fitting arithmetic and has to know what
-- a heading costs before it commits to drawing one.
-- The panel is 444 tall (596 of window, less 100 above it and 52 below), this
-- pane starts 26 down and stops 20 short of the bottom. Declared rather than
-- measured because the window does not resize, and because a frame asked for
-- its height before a layout pass answers something else entirely.
Parts.HEIGHT = 398

-- What the tail needs: a rule, the sum, and the closing sentence.
--
-- MEASURED AGAINST THE SENTENCE THAT ACTUALLY WRAPS. This was 46, which is a
-- rule plus two single lines -- but the closing sentence runs to two lines at
-- this width and the not-ranked one to two as well, so the last line of the
-- pane fell past its own bottom edge and simply was not drawn.
--
--   rule 9 + sum 15 + two wrapped lines 28 = 52, and 4 to spare.
Parts.RESERVED = 56

-- A merge proposal adds a wrapped warning and a button under everything else,
-- and it is rare enough that holding this back on every raider would cost
-- three cards for nothing. Added to the reserve only when there is one.
Parts.MERGE_RESERVE = 90

Parts.NIGHT_HEAD = 13
Parts.NIGHT_RULE = 6
Parts.NIGHT_GAP = 8

local function Cards()
    return SYL.RaidersDetailCards
end

Parts.Cards = Cards

-- Every pool hides everything it owns before a render, not just the font
-- strings. The old Render hid only detail.lines, which was correct while lines
-- were all there was; cards own textures and a Button each, so an eight-item
-- raider followed by a two-item one would have left six of them lit and
-- hoverable.
function Parts.Reset(detail)
    for _, line in ipairs(detail.lines) do
        line:Hide()
    end

    for _, night in ipairs(detail.nights) do
        night.label:Hide()
        night.points:Hide()
        night.rule:Hide()
    end

    for _, rule in ipairs(detail.rules) do
        rule:Hide()
    end

    Cards().Hide(detail.cards)

    detail.ruleCount = 0
    detail.lineCount = 0
    detail.nightCount = 0
    detail.cardCount = 0
end

-- The line that separates the loot from the sum of it. Its own pool, because
-- a raider with no items still gets one and a raider with five nights still
-- gets exactly one.
function Parts.Rule(detail, y)
    detail.ruleCount = detail.ruleCount + 1

    local rule = detail.rules[detail.ruleCount]

    if not rule then
        rule = Theme.CreateSolidTexture(detail, "separator", "ARTWORK")

        detail.rules[detail.ruleCount] = rule
    end

    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", PAD, -y)
    rule:SetSize(detail.width - (PAD * 2), 1)
    rule:Show()

    return y + 9
end

function Parts.Line(detail, text, colorKey, y)
    detail.lineCount = detail.lineCount + 1

    local line = detail.lines[detail.lineCount]

    if not line then
        line = Theme.CreateText(detail, Theme.sizes.columnHeader, "textMuted")

        line:SetWidth(detail.width - (PAD * 2))
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)

        detail.lines[detail.lineCount] = line
    end

    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", PAD, -y)

    Theme.SetTextColor(line, colorKey or "textMuted")
    line:SetText(text)
    line:Show()

    return y + line:GetStringHeight() + 3
end

function Parts.NightHeading(detail, label, points, y)
    detail.nightCount = detail.nightCount + 1

    local night = detail.nights[detail.nightCount]

    if not night then
        night = {
            label = Theme.CreateText(detail, Theme.sizes.columnHeader, "accent"),
            points = Theme.CreateText(
                detail, Theme.sizes.columnHeader, "textMuted"
            ),
            rule = Theme.CreateSolidTexture(detail, "accentMuted", "ARTWORK"),
        }

        night.label:SetJustifyH("LEFT")

        night.points:SetWidth(detail.width - (PAD * 2))
        night.points:SetJustifyH("RIGHT")

        detail.nights[detail.nightCount] = night
    end

    night.label:ClearAllPoints()
    night.label:SetPoint("TOPLEFT", PAD, -y)
    night.label:SetText(label)
    night.label:Show()

    night.points:ClearAllPoints()
    night.points:SetPoint("TOPLEFT", PAD, -y)
    night.points:SetText(points)
    night.points:Show()

    night.rule:ClearAllPoints()
    night.rule:SetPoint("TOPLEFT", PAD, -(y + Parts.NIGHT_HEAD))
    night.rule:SetSize(detail.width - (PAD * 2), 1)
    night.rule:Show()

    return y + Parts.NIGHT_HEAD + Parts.NIGHT_RULE
end

function Parts.Card(detail, item, y)
    detail.cardCount = detail.cardCount + 1

    local card = detail.cards[detail.cardCount]

    if not card then
        card = Cards().Create(detail, detail.width)

        detail.cards[detail.cardCount] = card
    end

    Cards().Draw(card, item, y)

    return y + Cards().HEIGHT + Cards().GAP
end

-- Which raid night a drop belongs to.
--
-- The SESSION's night, not the drop's own dateText. See the file header: a
-- raid running past midnight stamps tomorrow onto tonight's loot, and this
-- screen cannot afford to invent a raid night. The date on the record is the
-- fallback, for a drop with no session to place it against.
function Parts.NightOf(detail, at)
    local session = SYL.RaidSession.SessionAt(detail.sessions or {}, at)

    if session then
        return SYL.RaidSession.NightKey(session), session.startedAt or at
    end

    return date("%Y-%m-%d", at or 0), at
end

function Parts.NightLabel(at)
    return string.upper(date("%b %d", at or 0))
end

-- The arithmetic on one line, in the order it is done.
--
-- SCORING STATES ONLY. With all four the line runs past the pane and
-- truncates, and a truncated sum is the one thing this pane cannot ship. Mog
-- is left out rather than the line being shortened elsewhere, because it adds
-- nothing to the total by definition -- the count of them is stated above
-- instead, where it reads as a fact about the raider rather than as a term in
-- a sum.
function Parts.SumLine(entry)
    local parts = {}

    for _, row in ipairs(SYL.LootScore.Breakdown(entry)) do
        if row.weight > 0 then
            table.insert(parts, string.format(
                "%s %d × %d", row.label, row.count, row.weight
            ))
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, " + ")
        .. string.format(" = %d", entry.lootScore or 0)
end

function Parts.Groups(detail, items)
    local order, byNight = {}, {}

    for _, item in ipairs(items) do
        -- THE NIGHT'S OWN TIME, NOT THE ITEM'S. Grouping was already keyed on
        -- the session, but the heading was drawn from whichever drop landed in
        -- the group first -- and ItemsFor sorts newest first, so that is the
        -- LATEST win of the night. A Tuesday raid ending after midnight was
        -- therefore grouped correctly under Tuesday and then headed AUG 13.
        --
        -- Worse where it matters most: raid Tuesday to 00:30 and again on
        -- Wednesday and the pane shows two separate blocks both headed AUG 13,
        -- on the one screen somebody is standing at to argue about which night
        -- was which.
        --
        -- The test that was supposed to cover this checked the group's key and
        -- never the printed label, which is exactly the gap that let it
        -- through 42 green suites.
        local key, nightAt = Parts.NightOf(detail, item.at)

        if not byNight[key] then
            byNight[key] = { key = key, at = nightAt, items = {}, points = 0 }

            table.insert(order, byNight[key])
        end

        table.insert(byNight[key].items, item)

        byNight[key].points = byNight[key].points + (item.weight or 0)
    end

    return order
end

-- Every item as a flat list, each carrying the group it belongs to. Scrolling
-- is what needs this: an offset counted in ITEMS has to be able to start
-- part-way through a night, and a loop nested by group cannot start in the
-- middle of one without repeating the heading logic in two places.
function Parts.Flatten(groups)
    local flat = {}

    for _, group in ipairs(groups or {}) do
        for _, item in ipairs(group.items) do
            table.insert(flat, { group = group, item = item })
        end
    end

    return flat
end

-- HOW MANY ITEMS CAN BE SCROLLED PAST. Zero when everything fits, which is
-- what stops the wheel doing anything on a raider with three drops.
--
-- SEARCHED, NOT SUBTRACTED, and the version that subtracted left the last
-- item unreachable. total minus "how many fit at the top" assumes the number
-- that fits never changes -- but scrolling into the middle of a night draws
-- that night's heading at the top of the pane, and the heading costs a card's
-- worth of room. Rakahasa's eleven items showed seven, so it offered four
-- scroll steps, and at the fourth only six fit: ten reachable, the eleventh
-- one row below the bottom edge with nothing to say so.
--
-- So the answer is the first offset whose own visible run reaches the end.
-- One walk per step, and a season of items is small enough that this is
-- cheaper than being wrong.
function Parts.MaxOffset(detail, groups, y, reserve)
    local total = #Parts.Flatten(groups)

    for offset = 0, math.max(0, total - 1) do
        local shown = Parts.DrawGroups(detail, groups, y, reserve, offset, true)

        if offset + shown >= total then
            return offset
        end
    end

    return math.max(0, total - 1)
end

-- Draws from `offset` items in, and returns how many it drew.
--
-- SCROLLS NOW, and the reason it could not before was not the cards. Aimee:
-- "i can only see 5 items ... i want to be able to see what those 6 more are,
-- probably all season long."
--
-- The cap was never a count. This stopped when the next card would cross
-- HEIGHT minus RESERVED, and RESERVED was 56 pixels held back for the points
-- breakdown and the ranking sentence PINNED UNDER THE LIST. So the footer
-- cost the list three or four cards, and nothing could scroll because the
-- thing at the bottom had to stay at the bottom. Moving that block above the
-- list -- see UI/RaidersDetail.lua -- buys the pixels back and frees the
-- bottom edge, and both were needed.
--
-- `measureOnly` walks the same arithmetic without drawing, so MaxOffset above
-- cannot drift from what is actually on screen: one loop, asked twice.
function Parts.DrawGroups(detail, groups, y, reserve, offset, measureOnly)
    local step = Cards().HEIGHT + Cards().GAP
    local floor = Parts.HEIGHT - (reserve or Parts.RESERVED)

    local flat = Parts.Flatten(groups)

    offset = math.max(0, math.min(offset or 0, #flat))

    local drawn = 0
    local currentGroup

    for index = offset + 1, #flat do
        local entry = flat[index]

        -- A heading whenever the night changes, including for the night a
        -- scroll has landed in the middle of -- otherwise the top of the pane
        -- is a row of items belonging to nothing.
        local needsHeading = entry.group ~= currentGroup
        local headingCost = needsHeading
            and (Parts.NIGHT_HEAD + Parts.NIGHT_RULE
                + (currentGroup and Parts.NIGHT_GAP or 0))
            or 0

        if y + headingCost + step > floor then
            break
        end

        if needsHeading then
            if currentGroup then
                y = y + Parts.NIGHT_GAP
            end

            if not measureOnly then
                y = Parts.NightHeading(
                    detail,
                    Parts.NightLabel(entry.group.at),
                    string.format("%d points", entry.group.points),
                    y
                )
            else
                y = y + Parts.NIGHT_HEAD + Parts.NIGHT_RULE
            end

            currentGroup = entry.group
        end

        if measureOnly then
            y = y + step
        else
            y = Parts.Card(detail, entry.item, y)
        end

        drawn = drawn + 1
    end

    if measureOnly then
        return drawn
    end

    -- Counted, never dropped silently, and now it says which end. A list that
    -- stops without saying so reads as the whole list.
    local above = offset
    local below = #flat - offset - drawn

    if above > 0 or below > 0 then
        local text

        if above > 0 and below > 0 then
            text = string.format("%d above · %d below · scroll", above, below)
        elseif above > 0 then
            text = string.format("%d above · scroll up", above)
        else
            text = string.format("%d more · scroll down", below)
        end

        y = Parts.Line(detail, text, "textMuted", y)
    end

    return y, drawn
end
