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

    Line(detail, string.format(
        "%d raid nights · %d wins that counted",
        entry.nights or 0, entry.lootWins or 0
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
        Line(detail,
            "Not ranked yet. Under " .. SYL.LootScore.MIN_NIGHTS
            .. " raid nights there is not enough to divide by, so they are "
            .. "listed with the reason rather than given a number that would "
            .. "sort them straight to the top.", "textMuted")
    end
end
