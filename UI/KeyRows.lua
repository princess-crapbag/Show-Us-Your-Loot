-- UI/KeyRows.lua
--
-- The Mythic+ key list's columns, and one row of it.
--
-- Split out of UI/KeysPanel.lua, which was 635 lines against a 400 limit and
-- carrying four jobs: the key list, the lockouts view, the request pane's
-- host, and this. The house rule is splits before additions and it had been
-- broken three times running — the measured column widths, the alignment fix
-- and the staleness filter all landed in a file already well over.
--
-- The seam is the one the audit named: rows and the Ask button come out, the
-- panel keeps deciding who is on the list. Same shape as UI/RosterRows.lua,
-- which came out of the roster window for the same reason.
--
-- COLUMNS LIVE HERE because both halves read them — the panel draws the
-- headings, the rows draw the cells — and the whole point of the `widest`
-- field is that one table decides both.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local KeyRows = {}
SYL.KeyRows = KeyRows

-- THE ANSWER IS A COLUMN, NOT A SUFFIX. A reply used to be appended to the
-- level cell — "? Maybe" inside forty pixels — so every answer but "No" was
-- drawn cut off as "Ma...". It is its own column now, and the Ask button sits
-- in the same one: a row either offers to ask or reports what came back, never
-- both, so they share the space rather than each reserving some.
--
-- WIDTHS ARE MEASURED, NOT CHOSEN, and x follows from them.
--
-- UI/Columns.lua:50 already wrote this rule down, after the DATE column was
-- cut off twice: estimating characters times pixels is wrong by enough to
-- matter, and wrong by a different amount for every font and locale. These
-- four were picked by eye instead, and every one of them was too wide — most
-- of all RESPONSE, which reserved 110px to hold "Ask again". That string
-- measures 53. A table carrying twice the space its contents need does not
-- read as roomy, it reads as unfinished.
--
-- So each column declares the widest string it can ever hold and the layout
-- measures it. A column can still be wrong, but only by `widest` being wrong,
-- which is a checkable fact about the content rather than a judgment about
-- pixels. Aimee's rule, and it is the right one: no truncation, no padding
-- nobody asked for.
--
-- EVERY COLUMN ALSO STATES ITS OWN JUSTIFICATION, and the header and the cell
-- both read it from here. They used to work it out separately, in two places,
-- from the same `key == "level"` test — so RESPONSE was left in its header and
-- left in its text while the Ask button sharing the column centers its label
-- like every other button here. The column changed alignment depending on
-- whether a row was offering to ask or reporting an answer.
KeyRows.COLUMNS = {
    -- Twelve characters is the cap on a WoW character name, and the realm is
    -- appended by Keystone.CharacterKey. Nordrassil is the longest realm on
    -- Aimee's roster; a longer one truncates rather than widening every row
    -- forever for a guildie who may never appear.
    { key = "name", label = "PLAYER", justify = "LEFT",
      widest = "Likestoflash-Nordrassil" },

    -- The longest Mythic+ dungeon name in recent seasons. Worth re-checking
    -- when a season's pool changes: it is the one value here that Blizzard
    -- gets to move.
    { key = "dungeon", label = "DUNGEON", justify = "LEFT",
      widest = "Priory of the Sacred Flame" },

    -- Two digits covers every key level anybody has ever pushed, and the
    -- heading is wider than the number anyway.
    { key = "level", label = "LVL", justify = "RIGHT", widest = "30" },

    -- Every string this column can hold: Waiting, Yes, Maybe, No, Ask, and
    -- "Ask again". The last is the widest.
    { key = "response", label = "RESPONSE", justify = "CENTER",
      widest = "Ask again", sortable = false },
}

-- Breathing room either side of the widest string. One number, so no column
-- can end up looser than its neighbors.
local COLUMN_PADDING = 12
local COLUMN_START = 4

-- Runs once, from Create, because Theme.MeasureText needs a live client to
-- measure against — the same reason UI/Columns.lua measures inside a function
-- rather than at file scope.
function KeyRows.Measure()
    local x = COLUMN_START

    for _, column in ipairs(KeyRows.COLUMNS) do
        local content = Theme.MeasureText(Theme.sizes.rowSmall, column.widest)
        local heading = Theme.MeasureText(Theme.sizes.columnHeader, column.label)

        -- The heading can be the wider of the two — LVL holds "30" and is
        -- titled "LVL" — and a clipped heading is worse than a loose column.
        column.width = math.max(content, heading) + COLUMN_PADDING
        column.x = x

        x = x + column.width
    end

    return x - COLUMN_START
end

-- The response column by name rather than by index. It was COLUMNS[4], which
-- is correct until somebody inserts a column.
function KeyRows.ByKey(key)
    for _, column in ipairs(KeyRows.COLUMNS) do
        if column.key == key then
            return column
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- One row
--------------------------------------------------------------------------

-- config carries the geometry and the two things a row has to ask the panel:
--   parent, rowHeight, listTop, width
--   getRole()    the role the Ask button sends
--   onChanged()  something happened and the list needs redrawing
function KeyRows.Create(index, config)
    local row = CreateFrame("Frame", nil, config.parent)

    row:SetHeight(config.rowHeight)
    row:SetPoint(
        "TOPLEFT", 0,
        -(config.listTop + (index - 1) * config.rowHeight)
    )
    row:SetWidth(config.width)

    if index % 2 == 0 then
        local stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        stripe:SetAllPoints()
    end

    row.cells = {}

    -- Every column gets a cell now, response included. It used to skip the
    -- fourth because that one held only the Ask button and had no text of its
    -- own — which is exactly why the answer had nowhere to go and ended up
    -- squeezed into the level.
    for _, column in ipairs(KeyRows.COLUMNS) do
        local text = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")

        text:SetPoint("LEFT", column.x, 0)
        text:SetWidth(column.width)
        text:SetJustifyH(column.justify)
        text:SetWordWrap(false)

        row.cells[column.key] = text
    end

    -- Sized to the column rather than the column to it. The button was 110
    -- wide and the column was widened to match, which is how a 53px label
    -- ended up reserving twice that.
    local response = KeyRows.ByKey("response")

    row.ask = Theme.CreateButton(row, response.width, 17, "Ask", function()
        if not row.playerName then
            return
        end

        local ok, reason = SYL.KeystoneRequests.Ask(row.playerName, config.getRole())

        SYL:Write(ok
            and ("Asked " .. row.playerName .. " to run their key as "
                .. (SYL.KeystoneRequests.ROLE_LABELS[config.getRole()] or config.getRole()) .. ".")
            or (reason or "Could not ask."))

        config.onChanged()
    end)

    row.ask:SetPoint("LEFT", response.x, 0)

    -- Right-click to copy. These names carry the realm, because that is the
    -- form a keystone is stored under.
    SYL.Widgets.AttachNameCopy(row, function()
        return row.playerName
    end)

    return row
end

-- The button says what will happen, or why it will not. A grayed button with
-- no explanation is the thing this is avoiding: "offline" and "you already
-- asked" are different problems and only one of them is worth waiting on.
function KeyRows.DrawAsk(row, entry, config)
    -- Cleared on every draw before anything decides to fill it. Rows are
    -- pooled, so a reply left behind would be read as this player's answer —
    -- the same trap the dashboard tiles have.
    row.cells.response:SetText("")

    if entry.isOwn then
        row.ask:Hide()

        return
    end

    local existing = SYL.KeystoneRequests.GetOutgoing(entry.name)

    if existing and existing.status ~= SYL.KeystoneRequests.STATUS.DENIED then
        row.ask:Hide()

        -- In the response column at full width, not appended to the level.
        row.cells.response:SetText(
            SYL.KeystoneRequests.STATUS_LABELS[existing.status] or ""
        )

        -- Waiting is a state, not an answer, so it reads quieter than one.
        Theme.SetTextColor(
            row.cells.response,
            existing.status == SYL.KeystoneRequests.STATUS.PENDING
                and "textMuted"
                or "textPrimary"
        )

        return
    end

    local allowed, reason = SYL.KeystoneRequests.CanAsk(entry.name)

    row.ask.label:SetText(existing and "Ask again" or "Ask")
    row.ask:Show()

    -- Left clickable either way so the tooltip can be read; the click prints
    -- the reason rather than doing nothing.
    Theme.SetTextColor(row.ask.label, allowed and "textPrimary" or "textMuted")

    SYL.Tooltips.Attach(
        row.ask,
        allowed and "Ask for this key" or "Cannot ask",
        allowed
            and ("Sends a request to " .. entry.name .. " as "
                .. (SYL.KeystoneRequests.ROLE_LABELS[config.getRole()] or config.getRole())
                .. ". Only they see it.")
            or (reason or "")
    )
end
