-- UI/RaidLockoutsView.lua
--
-- Which raids each of this account's characters is saved to, and how much of
-- each is already dead.
--
-- Aimee: "the way i can see m0 lockouts, id like to be able to see raid boss
-- kills/lockouts. put it somewhere that makes sense. i want to see this on
-- each toon as i log into them just the same way keys works. this raid lockout
-- info should not be in the keys tab."
--
-- SO IT IS ON THE BOSSES TAB. That tab is about which bosses have given what;
-- this is about which bosses a character can still get anything from. Keys is
-- about Mythic+ and a raid lockout is not, which is her whole point.
--
-- A LIST, NOT A GRID. UI/LockoutsGrid.lua draws characters against the
-- season's dungeons and that shape is right there: a fixed set of columns,
-- one tick each. Raids do not have that shape -- a character has one to three
-- lockouts, each holding a different number of bosses at a difficulty, and
-- the answer wanted is "five of eight, still needs Ula'tek" rather than a
-- tick. Forced into a grid that is either a very wide table or a lot of empty
-- cells.
--
-- ABSENT IS NOT EMPTY. The client can only read the character that is logged
-- in, so a character this account has not played since installing has no
-- entry at all -- and that is a different answer from "played, saved to
-- nothing". Both are said in words rather than left to a blank row. The same
-- constraint Core/Keystone.lua hit first.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RaidLockoutsView = {}
SYL.RaidLockoutsView = RaidLockoutsView

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 18

-- Enough for a full account without scrolling. Beyond that the caption says
-- how many are not drawn rather than silently stopping.
local VISIBLE_ROWS = 18

local rows = {}

--------------------------------------------------------------------------
-- What to draw
--------------------------------------------------------------------------

-- One line per character-lockout, plus a line for a character with none.
--
-- Flattened here rather than in Core/RaidLockouts.lua, because the flattening
-- is a display decision: the store keeps a character with their lockouts,
-- which is the shape the client answers in and the shape sharing would want.
function RaidLockoutsView.Rows()
    local list = {}

    for _, character in ipairs(SYL.RaidLockouts.Characters()) do
        local lockouts = SYL.RaidLockouts.For(character)

        if #lockouts == 0 then
            table.insert(list, {
                character = character,
                empty = true,
            })
        else
            for index, lockout in ipairs(lockouts) do
                table.insert(list, {
                    character = character,
                    lockout = lockout,

                    -- The name is drawn once per character rather than on
                    -- every line, so three lockouts read as one person with
                    -- three rather than as three people.
                    first = index == 1,
                })
            end
        end
    end

    return list
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))

    -- Mouse enabled, or the hover naming what is left never fires. See the
    -- dashboard widget tooltips, which were dead for weeks behind this line.
    row:EnableMouse(true)

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.instance = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.instance:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.instance:SetWidth(220)
    row.instance:SetJustifyH("LEFT")
    row.instance:SetWordWrap(false)

    row.progress = Theme.CreateText(row, Theme.sizes.rowSmall, "accent")
    row.progress:SetPoint("LEFT", row.instance, "RIGHT", 8, 0)
    row.progress:SetWidth(70)
    row.progress:SetJustifyH("LEFT")

    row.resets = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.resets:SetPoint("RIGHT", -6, 0)
    row.resets:SetJustifyH("RIGHT")

    SYL.Tooltips.Attach(
        row,
        function(self)
            return self.tipTitle
        end,
        function(self)
            return self.tipBody
        end
    )

    return row
end

local function DrawRow(row, entry)
    local character = entry.character

    row.name:SetText(entry.first ~= false and tostring(character.name) or "")
    SYL.ClassColor.Set(row.name, character.class)

    if entry.empty then
        -- SAVED TO NOTHING IS AN ANSWER. It means every raid is open to this
        -- character this week, which is the most useful thing this screen can
        -- say about an alt.
        row.instance:SetText("not saved to anything")
        Theme.SetTextColor(row.instance, "textMuted")

        row.progress:SetText("")
        row.resets:SetText("")

        row.tipTitle = tostring(character.name)
        row.tipBody = "Every raid is open on this character this week."

        row:Show()

        return
    end

    local lockout = entry.lockout
    local short = SYL.Utilities.ShortDifficulty(
        lockout.difficultyID, lockout.difficultyName
    )

    row.instance:SetText(
        tostring(lockout.name)
        .. (short and short ~= "" and ("  " .. short) or "")
    )

    Theme.SetTextColor(row.instance, "textSecondary")

    row.progress:SetText(SYL.RaidLockouts.Describe(lockout))

    -- Cleared reads differently from part-way through: there is nothing left
    -- to get, so it stops being a thing to plan around.
    Theme.SetTextColor(
        row.progress,
        (lockout.total or 0) > 0 and lockout.killed >= lockout.total
            and "textMuted" or "accent"
    )

    row.resets:SetText(
        SYL.Lockouts.FormatRemaining((lockout.expiresAt or 0) - time())
    )

    local remaining = SYL.RaidLockouts.Remaining(lockout)

    row.tipTitle = tostring(lockout.name)

    -- WHAT IS LEFT, WHICH IS THE QUESTION. "Am I saved" is answered by the
    -- row existing; "what can I still get" is not, and it is the one somebody
    -- opens this screen to ask.
    row.tipBody = #remaining > 0
        and ("Still to kill: " .. table.concat(remaining, ", "))
        or "Cleared. Nothing left on this lockout."

    row:Show()
end

--------------------------------------------------------------------------
-- The view
--------------------------------------------------------------------------

function RaidLockoutsView.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)

    frame:SetAllPoints()
    frame:Hide()

    local function Heading(text, x, width)
        local fontString =
            Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

        fontString:SetPoint("TOPLEFT", x, 0)
        fontString:SetWidth(width)
        fontString:SetJustifyH("LEFT")
        fontString:SetText(text)

        return fontString
    end

    Heading("CHARACTER", 6, 150)
    Heading("RAID", 164, 220)
    Heading("BOSSES DOWN", 392, 90)

    frame.resetHeading =
        Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")

    frame.resetHeading:SetPoint("TOPRIGHT", -6, 0)
    frame.resetHeading:SetJustifyH("RIGHT")
    frame.resetHeading:SetText("RESETS IN")

    frame.empty = Theme.CreateText(frame, Theme.sizes.row, "textMuted")
    frame.empty:SetPoint("TOPLEFT", 6, -40)
    frame.empty:SetPoint("TOPRIGHT", -6, -40)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetWordWrap(true)
    frame.empty:Hide()

    frame.caption = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    frame.caption:SetPoint("BOTTOMLEFT", 6, 4)

    rows = {}
    frame.rows = rows

    RaidLockoutsView.frame = frame

    return frame
end

function RaidLockoutsView.Refresh()
    local frame = RaidLockoutsView.frame

    if not frame then
        return
    end

    local list = RaidLockoutsView.Rows()

    if #list == 0 then
        for _, row in ipairs(rows) do
            row:Hide()
        end

        -- ABSENT, NOT EMPTY. See the file header: nothing has been read for
        -- any character yet, which is a different thing from everybody being
        -- unsaved, and saying "no lockouts" here would be a claim the addon
        -- cannot make.
        frame.empty:SetText(
            "Nothing read yet. This addon can only see the character it is "
            .. "logged in as, so each of your characters appears here the "
            .. "first time you log into it -- the same way keystones do."
        )

        frame.empty:Show()
        frame.caption:SetText("")

        return
    end

    frame.empty:Hide()

    for index = 1, VISIBLE_ROWS do
        local entry = list[index]
        local row = rows[index]

        if not row then
            row = CreateRow(frame, index)
            rows[index] = row
        end

        if entry then
            DrawRow(row, entry)
        else
            row:Hide()
        end
    end

    local characters = SYL.RaidLockouts.Characters()
    local saved = 0

    for _, character in ipairs(characters) do
        if character.count > 0 then
            saved = saved + 1
        end
    end

    -- NO SILENT TRUNCATION. A list that stops at eighteen without saying so
    -- reads as an account with eighteen rows in it.
    frame.caption:SetText(
        SYL.Utilities.Count(#characters, "character")
        .. " · " .. saved .. " saved · resets weekly with your realm"
        .. (#list > VISIBLE_ROWS
            and ("  ·  " .. (#list - VISIBLE_ROWS) .. " more not shown")
            or "")
    )
end
