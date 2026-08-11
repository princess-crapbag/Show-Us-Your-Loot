-- UI/PlayerRows.lua
--
-- One row of the players list, and the columns it is drawn into.
--
-- Split out of PlayerWindow the moment it crossed the size limit, the same
-- way DueRows came out of DueWindow and RosterRows out of RosterWindow. That
-- file decides who is on the list, how the scope narrows it and how it sorts;
-- this one draws a person.
--
-- The columns live here because a cell is set to its column's width, and
-- moving one without the other is how a number ends up truncated. The window
-- still owns WINDOW_WIDTH, which syl_check measures these against.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Utilities = SYL.Utilities

local PlayerRows = {}
SYL.PlayerRows = PlayerRows

PlayerRows.COLUMNS = {
    { key = "name", label = "PLAYER", width = 130, gap = 10 },
    { key = "rank", label = "GUILD RANK", width = 110, gap = 8 },
    -- Blank without Raider.IO, and blank for anyone its bundle has not seen.
    -- Nothing in the fairness maths reads it: it is context, not an input.
    { key = "score", label = "M+", width = 46, gap = 8 },
    { key = "nights", label = "NIGHTS", width = 50, gap = 8 },
    -- ELIGIBLE, not ROLLED ON. The number is how many drops this player could
    -- have won — every roll list they appeared on — and a pass or a no-roll
    -- puts you on that list exactly as a Need does. Labeled "ROLLED ON" it
    -- is the number an officer quotes in a loot dispute, and it would be
    -- wrong in the direction that loses the argument for the quiet raider who
    -- passes on everything.
    { key = "eligible", label = "ELIGIBLE", width = 66, gap = 8 },
    { key = "upgrades", label = "UPGRADES", width = 68, gap = 8 },
    { key = "mog", label = "MOG", width = 40, gap = 8 },
    { key = "lastWin", label = "LAST UPGRADE", width = 100, gap = 8 },
    { key = "drought", label = "DAYS", width = 46, gap = 8 },
}

PlayerRows.OFFSETS = SYL.Widgets.ColumnOffsets(PlayerRows.COLUMNS)

function PlayerRows.Create(parent, index, listTop, rowHeight)
    -- A Button rather than a Frame so the row can be clicked through to the
    -- player's own history.
    local row = CreateFrame("Button", nil, parent)
    local top = listTop + (index - 1) * rowHeight

    row:SetScript("OnClick", function(self)
        if self.entry then
            SYL:OpenPlayerDetail(self.entry)
        end
    end)

    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 16, -top)
    row:SetPoint("TOPRIGHT", -34, -top)

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.cells = {}

    for _, column in ipairs(PlayerRows.COLUMNS) do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

        text:SetPoint("LEFT", PlayerRows.OFFSETS[column.key], 0)
        text:SetWidth(column.width)

        row.cells[column.key] = text
    end

    return row
end

function PlayerRows.Fill(row, entry)
    local cells = row.cells

    -- Read by the click handler. Rows are pooled and reused, so this has to
    -- be set every refresh rather than captured when the row was built.
    row.entry = entry

    cells.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(
            cells.name, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(cells.name, "textPrimary")
    end

    -- Blank rather than "not in guild": most of a pug raid is not, and saying
    -- so on every row would be noise.
    cells.rank:SetText(entry.guildRank or "")

    -- Blank covers three different things — no Raider.IO, a character it has
    -- never seen, and a genuine zero — and none of them is worth a symbol
    -- that would read as a number.
    if entry.mplusScore and entry.mplusScore > 0 then
        cells.score:SetText(math.floor(entry.mplusScore))

        Theme.SetCustomTextColor(
            cells.score, SYL.RaiderIO.GetScoreColor(entry.mplusScore)
        )
    else
        cells.score:SetText("")
    end

    cells.nights:SetText(entry.nights)
    cells.eligible:SetText(entry.eligible)

    cells.upgrades:SetText(entry.upgradeWins)

    if entry.upgradeWins == 0 then
        Theme.SetTextColor(cells.upgrades, "textMuted")
    else
        Theme.SetTextColor(cells.upgrades, "accent")
    end

    cells.mog:SetText(entry.mogWins > 0 and entry.mogWins or "")
    Theme.SetTextColor(cells.mog, "textMuted")

    if entry.lastWinAt then
        cells.lastWin:SetText(Utilities.FormatDateOnly(entry.lastWinAt))
        Theme.SetTextColor(cells.lastWin, "textSecondary")
    else
        cells.lastWin:SetText("never")
        Theme.SetTextColor(cells.lastWin, "textMuted")
    end

    cells.drought:SetText(entry.droughtDays)
end
