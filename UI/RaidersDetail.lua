-- UI/RaidersDetail.lua
--
-- The pane on the right of the Raiders board: who is selected, and the
-- arithmetic behind their number.
--
-- Split from UI/RaidersPanel.lua, which was over the size limit with both in
-- it. That file decides what the board looks like; this one decides what a
-- selected raider says, which is the same division as DashboardWidgets and
-- DashboardParts.
--
-- THIS IS THE SCREEN SOMEBODY STANDS AT WHEN THEY DISAGREE WITH THEIR NUMBER,
-- so it shows the sum rather than the conclusion: every win that counted, what
-- each was worth, and the total those add to. It has to add up on its own. A
-- number that cannot be taken apart is one people stop trusting, and an officer
-- who cannot answer "why am I below him" loses the argument by default.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersDetail = {}
SYL.RaidersDetail = RaidersDetail

local PAD = 10
local LINE_GAP = 5

function RaidersDetail.Create(parent, width, top)
    local detail = CreateFrame("Frame", nil, parent)

    detail:SetWidth(width)
    detail:SetPoint("TOPRIGHT", 0, -top)
    detail:SetPoint("BOTTOM", 0, 20)

    local back = Theme.CreateSolidTexture(detail, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    detail.lines = {}
    detail.count = 0
    detail.top = 12
    detail.width = width

    -- THE ONE CONTROL ON THIS PANE, and it is here because this is where the
    -- problem is visible: a faction change gives a character a new GUID, so
    -- the board draws the same person twice and the roster screen cannot help
    -- — the pre-change character is not in the guild any more. See
    -- Core/CharacterMerge.lua.
    detail.mergeButton = Theme.CreateButton(detail, 140, 22, "", function()
        local proposal = detail.mergeProposal

        if not proposal then
            return
        end

        local ok, reason = SYL.CharacterMerge.Apply(proposal)

        if not ok then
            SYL:Print("Could not merge them: " .. tostring(reason))

            return
        end

        SYL:Print(
            "Merged into one raider. Their nights and loot are counted "
            .. "together from now on. Undo it from the Roster window with "
            .. "Not an alt."
        )

        if SYL.RefreshMainWindow then
            SYL:RefreshMainWindow()
        end
    end)

    detail.mergeButton:Hide()

    return detail
end

-- Lines are pooled and reused, so anything a previous selection wrote has to be
-- overwritten rather than left behind. The dashboard tiles hit exactly this and
-- inherited a stale offset that pushed rows off the body.
local function Line(detail, text, colorKey, size)
    detail.count = detail.count + 1

    local line = detail.lines[detail.count]

    if not line then
        line = Theme.CreateText(
            detail, size or Theme.sizes.rowSmall, colorKey or "textSecondary"
        )

        line:SetWidth(detail.width - (PAD * 2))
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)

        detail.lines[detail.count] = line
    end

    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD, -detail.top)

    Theme.SetTextColor(line, colorKey or "textSecondary")
    line:SetText(text)
    line:Show()

    detail.top = detail.top + line:GetStringHeight() + LINE_GAP

    return line
end

function RaidersDetail.Render(detail, entry)
    for _, line in ipairs(detail.lines) do
        line:Hide()
    end

    detail.count = 0
    detail.top = 12
    detail.mergeProposal = nil
    detail.mergeButton:Hide()

    if not entry then
        Line(detail, "Pick a raider to see where their number came from.", "textMuted")

        return
    end

    local name = Line(detail, tostring(entry.name or "Unknown"), "textPrimary", Theme.sizes.row)
    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(name, classColor[1], classColor[2], classColor[3])
    end

    Line(detail, SYL.LootScore.Describe(entry), entry.ranked and "accent" or "textMuted")

    -- "WINS THAT COUNTED" COUNTED TRANSMOG, which is the one thing on this
    -- pane that did not count. entry.lootWins is every win; scoringWins is the
    -- need and greed ones, and only those are worth anything. Saying the
    -- transmog wins out loud beside them is the same argument the breakdown
    -- below makes: the number somebody is arguing with is the one that does
    -- not mention them.
    local scoring = entry.scoringWins or 0
    local transmog = (entry.lootWins or 0) - scoring

    Line(detail, string.format(
        "%s · %s that scored%s",
        SYL.Utilities.Count(entry.nights or 0, "raid night"),
        SYL.Utilities.Count(scoring, "item"),
        transmog > 0
            and (" · " .. transmog .. " transmog, worth nothing")
            or ""
    ), "textSecondary")

    local breakdown = SYL.LootScore.Breakdown(entry)

    if #breakdown == 0 then
        Line(detail, "No wins have counted yet.", "textMuted")
    else
        Line(detail, "WHERE THE SCORE CAME FROM", "textMuted")

        for _, row in ipairs(breakdown) do
            Line(detail, string.format(
                "%s  ·  %d × %d  =  %d",
                row.label, row.count, row.weight, row.points
            ), "textSecondary")
        end

        Line(detail, string.format("Total  %d points", entry.lootScore or 0), "textPrimary")
    end

    -- Said out loud, because the ranking is share and not score: somebody
    -- reading a big total needs to know it is divided before it is compared,
    -- or the board looks like it is punishing them for turning up.
    if entry.ranked then
        Line(detail, string.format(
            "%d points over %d nights is %s. The board is ordered by that, "
            .. "lowest first — turning up more makes you more due, not less.",
            entry.lootScore or 0, entry.nights or 0, SYL.LootScore.Describe(entry)
        ), "textMuted")
    else
        -- The live floor, not the default constant. The setting can move it
        -- and this sentence states it as fact, so a stale number here would be
        -- the addon explaining a rule it is no longer applying.
        Line(detail,
            "Not ranked yet. Under "
            .. SYL.Utilities.Count(SYL.LootScore.MinNights(), "raid night")
            .. " there is not enough to divide by, so they are "
            .. "listed with the reason rather than given a number that would "
            .. "sort them straight to the top.", "textMuted")
    end

    -- Offered last, under the arithmetic it would change. Somebody reading a
    -- number that looks wrong should see why before being offered the fix.
    local proposal = SYL.CharacterMerge
        and SYL.CharacterMerge.For(entry.key)

    if proposal then
        Line(detail, SYL.CharacterMerge.Describe(proposal), "warning")

        detail.mergeProposal = proposal

        local label = "Merge into one raider"

        detail.mergeButton.label:SetText(label)
        detail.mergeButton:SetWidth(
            Theme.MeasureText(Theme.sizes.rowSmall, label) + 26
        )

        detail.mergeButton:ClearAllPoints()
        detail.mergeButton:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD, -detail.top)
        detail.mergeButton:Show()

        detail.top = detail.top + 26
    end
end
