-- UI/RosterRows.lua
--
-- One row of the raid roster: the cells, and the two of them that are
-- clicked rather than read.
--
-- Split out of RosterWindow the moment it crossed the size limit, the same
-- way Rows.lua came out of the main window. That file decides who is on the
-- list and what the roster is missing; this one draws a person.
--
-- ROLE and TEAM are edited in place. Font strings cannot take mouse events,
-- so each gets an invisible button over it, and the button reads the entry
-- off the row rather than capturing it — rows are pooled and the person in
-- any given one changes on every refresh.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RosterRows = {}
SYL.RosterRows = RosterRows

-- config carries the geometry and one callback:
--   columns, offsets, widths, rowHeight, listTop
--   onChanged()  something was edited and the list needs redrawing
function RosterRows.Create(parent, index, config)
    local row = CreateFrame("Frame", nil, parent)
    local top = config.listTop + (index - 1) * config.rowHeight

    row:SetHeight(config.rowHeight)
    row:SetPoint("TOPLEFT", 16, -top)
    row:SetPoint("TOPRIGHT", -34, -top)

    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.cells = {}

    for _, column in ipairs(config.columns) do
        if column.key ~= "select" then
            local text =
                Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

            text:SetPoint("LEFT", config.offsets[column.key], 0)
            text:SetWidth(column.width)

            row.cells[column.key] = text
        end
    end

    -- A real checkbox rather than a clickable label: ticking several names
    -- and then doing one thing to all of them is the point, and a tick box
    -- is what says "this is one of many" at a glance.
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")

    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT", config.offsets.select, 0)

    row.check:SetScript("OnClick", function(self)
        if row.entry then
            config.onSelect(row.entry, self:GetChecked() and true or false)
        end
    end)

    local function Hit(columnKey, onClick)
        local button = CreateFrame("Button", nil, row)

        button:SetPoint("LEFT", config.offsets[columnKey], 0)
        button:SetSize(config.widths[columnKey] or 60, config.rowHeight)
        button:RegisterForClicks("LeftButtonUp")

        button:SetScript("OnClick", function()
            if row.entry then
                onClick(row.entry)

                -- Both hits below change the roster: one the role, one
                -- membership. Announced here rather than in each so neither
                -- can be added later without it.
                SYL.RosterSync.OnOwnRosterChanged()

                config.onChanged()
            end
        end)

        return button
    end

    row.roleHit = Hit("role", function(entry)
        SYL.RaidTeam.CycleRole(entry.key)
    end)

    row.teamHit = Hit("team", function(entry)
        SYL.RaidTeam.Toggle(entry.key)
    end)

    -- Right-click anywhere on the row to copy the name. `row.entry` is read on
    -- the click rather than captured, because rows are pooled and reused as
    -- the list scrolls.
    --
    -- The short name, not Name-Realm: it is what the row is showing, what the
    -- "Alt of" box below expects, and what you type in a whisper.
    SYL.Widgets.AttachNameCopy(row, function()
        return row.entry and row.entry.name or nil
    end)

    return row
end

function RosterRows.Fill(row, entry, isSelected)
    local cells = row.cells

    -- Read by the hit areas and the checkbox, which outlive any one entry.
    row.entry = entry

    row.check:SetChecked(isSelected and true or false)

    -- Whose alt this is, when it is one. Named rather than flagged, because
    -- "alt" on its own does not tell an officer whether the person is
    -- already on the team under another name.
    cells.main:SetText(entry.mainName or "")
    Theme.SetTextColor(cells.main, "textMuted")

    cells.name:SetText(tostring(entry.name or "Unknown"))

    local classColor = Theme.GetClassColor(entry.class)

    if classColor then
        Theme.SetCustomTextColor(
            cells.name, classColor[1], classColor[2], classColor[3]
        )
    else
        Theme.SetTextColor(cells.name, "textPrimary")
    end

    cells.class:SetText(Theme.ClassLabel(entry.class))
    Theme.SetTextColor(cells.class, "textSecondary")

    local role, detected = SYL.RaidTeam.GetRole(entry.key)

    -- A role nobody has chosen shows what the game reported, in brackets, so
    -- it reads as a guess rather than as a decision somebody made.
    if role then
        local label = SYL.RaidTeam.ROLE_LABELS[role] or role

        cells.role:SetText(detected and ("(" .. label .. ")") or label)

        Theme.SetTextColor(
            cells.role, detected and "textMuted" or "textPrimary"
        )
    else
        cells.role:SetText("—")
        Theme.SetTextColor(cells.role, "textMuted")
    end

    local onTeam = SYL.RaidTeam.IsMember(entry.key)

    cells.team:SetText(onTeam and "Raiding" or "—")
    Theme.SetTextColor(cells.team, onTeam and "accent" or "textMuted")

    cells.rank:SetText(entry.rank or "")
    Theme.SetTextColor(cells.rank, "textMuted")

    -- Zero nights is a real answer, not missing data: somebody in the guild
    -- who has never raided is exactly who this window is for finding.
    cells.nights:SetText(entry.nights)

    Theme.SetTextColor(
        cells.nights, entry.nights > 0 and "textPrimary" or "textMuted"
    )

    if entry.mplusScore and entry.mplusScore > 0 then
        cells.score:SetText(math.floor(entry.mplusScore))
        Theme.SetCustomTextColor(
            cells.score, SYL.RaiderIO.GetScoreColor(entry.mplusScore)
        )
    else
        cells.score:SetText("")
    end
end
