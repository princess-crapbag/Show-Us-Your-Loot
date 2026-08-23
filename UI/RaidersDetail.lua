-- UI/RaidersDetail.lua
--
-- The pane on the right of the Raiders board: who is selected, and the
-- arithmetic behind their number.
--
-- THIS IS THE SCREEN SOMEBODY STANDS AT WHEN THEY DISAGREE WITH THEIR NUMBER,
-- so it shows the sum rather than the conclusion: every win that counted, what
-- each was worth, and the total those add to. It has to add up on its own. A
-- number that cannot be taken apart is one people stop trusting, and an officer
-- who cannot answer "why am I below him" loses the argument by default.
--
-- WHAT CHANGED, and why it is not decoration. Every line used to be the same
-- size and nearly the same color, the item names were plain gray text, and the
-- name was asked for at size 12 and silently drawn at 11 -- Line() only applied
-- a size when it first created a pooled FontString, and the empty state always
-- created the first one. Aimee, looking at it: "id like it to show the item
-- link and just look better."
--
-- So the items are cards now, with real links on them -- see
-- UI/RaidersDetailCards.lua -- and they are grouped under the raid night they
-- were taken on, because the argument is nearly always about one night.
--
-- GROUPED BY THE SESSION'S NIGHT, NEVER BY THE DROP'S OWN DATE. A raid that
-- runs past midnight writes tomorrow's date onto tonight's loot, and grouping
-- on that would invent a raid night that never happened -- on a screen whose
-- entire job is being checkable. RaidSession.SessionAt already answers which
-- night a timestamp belongs to.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidersDetail = {}
SYL.RaidersDetail = RaidersDetail

local PAD = 10

local STAT_TOP = 32
local STAT_HEIGHT = 36
local STAT_GAP = 76

local Parts = SYL.RaidersDetailParts

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function RaidersDetail.Create(parent, width, top)
    local detail = CreateFrame("Frame", nil, parent)

    detail:SetWidth(width)
    detail:SetPoint("TOPRIGHT", 0, -top)
    detail:SetPoint("BOTTOM", 0, 20)

    local back = Theme.CreateSolidTexture(detail, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    detail.width = width
    detail.lines = {}
    detail.nights = {}
    detail.cards = {}
    detail.rules = {}
    detail.ruleCount = 0
    detail.lineCount = 0
    detail.nightCount = 0
    detail.cardCount = 0

    detail.name = Theme.CreateText(detail, Theme.sizes.row, "textPrimary")
    detail.name:SetPoint("TOPLEFT", PAD, -12)
    detail.name:SetWidth(width - (PAD * 2) - 92)
    detail.name:SetJustifyH("LEFT")
    detail.name:SetWordWrap(false)

    detail.share = Theme.CreateText(detail, Theme.sizes.row, "accent")
    detail.share:SetPoint("TOPRIGHT", -PAD, -13)
    detail.share:SetJustifyH("RIGHT")

    -- The three figures, which Aimee picked off one of the samples: "i like how
    -- the top part of the panel looks on 4 columns where it shows the raid
    -- nights and items and points."
    detail.statBand = Theme.CreateSolidTexture(detail, "rowAlt", "BACKGROUND")
    detail.statBand:SetPoint("TOPLEFT", 6, -STAT_TOP)
    detail.statBand:SetSize(width - 12, STAT_HEIGHT)

    detail.stats = {}

    for index = 1, 3 do
        local x = 16 + (index - 1) * STAT_GAP

        local stat = {
            value = Theme.CreateText(detail, Theme.sizes.row, "textPrimary"),
            label = Theme.CreateText(
                detail, Theme.sizes.columnHeader, "textMuted"
            ),
        }

        stat.value:SetPoint("TOPLEFT", x, -(STAT_TOP + 3))
        stat.label:SetPoint("TOPLEFT", x, -(STAT_TOP + 19))

        detail.stats[index] = stat
    end

    -- THE ONE CONTROL ON THIS PANE, and it is here because this is where the
    -- problem is visible: a faction change gives a character a new GUID, so
    -- the board draws the same person twice and the roster screen cannot help
    -- -- the pre-change character is not in the guild any more. See
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

        -- HOW TO UNDO IT, said at the moment it is done. Folding two
        -- characters together rewrites every number on the board
        -- retroactively, and somebody who has just done that by mistake
        -- should not have to go looking for the way back.
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

-- The drops and the sessions the board was built from, so the pane can name a
-- raider's items and place them on a night without sweeping the season again
-- on every selection.
function RaidersDetail.SetDrops(detail, drops, sessions)
    detail.drops = drops
    detail.sessions = sessions
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

local function Tail(detail, entry, y)
    y = Parts.Rule(detail, y + 4)

    local sum = Parts.SumLine(entry)

    if sum then
        y = Parts.Line(detail, sum, "textMuted", y)
    end

    if entry.ranked then
        return Parts.Line(
            detail,
            "Ranked on points per night, lowest first — turning up more "
            .. "makes you more due, not less.",
            "textMuted", y
        )
    end

    -- The live floor, not the default constant. The setting can move it and
    -- this sentence states it as fact, so a stale number here would be the
    -- addon explaining a rule it is no longer applying.
    return Parts.Line(
        detail,
        "Not ranked yet. Under "
        .. SYL.Utilities.Count(SYL.LootScore.MinNights(), "raid night")
        .. " there is not enough to divide by.",
        "textMuted", y
    )
end

local function Header(detail, entry)
    detail.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(
            detail.name, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(detail.name, "textPrimary")
    end

    detail.name:Show()

    if entry.ranked then
        detail.share:SetText(string.format("%.1f", entry.share or 0))
        Theme.SetTextColor(detail.share, "accent")
    else
        detail.share:SetText("not ranked")
        Theme.SetTextColor(detail.share, "textMuted")
    end

    detail.share:Show()

    local scoring = entry.scoringWins or 0

    local figures = {
        { entry.nights or 0, "RAID NIGHTS" },
        { scoring, "ITEMS" },
        { entry.lootScore or 0, "POINTS" },
    }

    for index, stat in ipairs(detail.stats) do
        stat.value:SetText(tostring(figures[index][1]))
        stat.label:SetText(figures[index][2])
        stat.value:Show()
        stat.label:Show()
    end

    detail.statBand:Show()

    local y = STAT_TOP + STAT_HEIGHT + 10

    -- ITEMS counts only what scored, so without this the pane quietly
    -- disagrees with the list underneath it -- which is the first gap somebody
    -- arguing about their number will find.
    local spare = (entry.lootWins or 0) - scoring

    if spare > 0 then
        y = Parts.Line(
            detail,
            string.format("%d more worth nothing", spare),
            "textMuted", y
        ) + 4
    end

    return y
end

local function HideHeader(detail)
    detail.name:Hide()
    detail.share:Hide()
    detail.statBand:Hide()

    for _, stat in ipairs(detail.stats) do
        stat.value:Hide()
        stat.label:Hide()
    end
end

function RaidersDetail.Render(detail, entry)
    Parts.Reset(detail)

    detail.mergeProposal = nil
    detail.mergeButton:Hide()

    if not entry then
        HideHeader(detail)
        Parts.Line(detail, "Pick a raider to see where their number came from.",
             "textMuted", 12)

        return
    end

    local y = Header(detail, entry)

    local items = SYL.LootScore.ItemsFor(entry.key, detail.drops)

    if #items == 0 then
        y = Parts.Line(detail, "Nothing has counted for them yet.",
                 "textSecondary", y)
    else
        y = Parts.DrawGroups(detail, Parts.Groups(detail, items), y)
    end

    y = Tail(detail, entry, y)

    -- Offered last, under the arithmetic it would change. Somebody reading a
    -- number that looks wrong should see why before being offered the fix.
    local proposal = SYL.CharacterMerge and SYL.CharacterMerge.For(entry.key)

    if not proposal then
        return
    end

    y = Parts.Line(detail, SYL.CharacterMerge.Describe(proposal), "warning", y)

    detail.mergeProposal = proposal

    local label = "Merge into one raider"

    detail.mergeButton.label:SetText(label)
    detail.mergeButton:SetWidth(
        Theme.MeasureText(Theme.sizes.rowSmall, label) + 26
    )

    detail.mergeButton:ClearAllPoints()
    detail.mergeButton:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD, -y)
    detail.mergeButton:Show()
end

RaidersDetail.HEIGHT = Parts.HEIGHT
