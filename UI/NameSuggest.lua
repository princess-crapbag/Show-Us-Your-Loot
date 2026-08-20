-- UI/NameSuggest.lua
--
-- A list of matching names above a text box, so a name can be picked instead
-- of spelled.
--
-- WHY THIS EXISTS. The "Alt of" box on the roster screen takes a name and
-- resolves it before writing anything, and a name that does not resolve is
-- refused with a message. That is the right behavior and it is still a
-- guessing game: the box is 130 pixels of empty field, the answer has to match
-- a character the addon has seen, and nothing on screen says which ones those
-- are. Aimee asked for the names to be suggested from the letters typed, which
-- is the shortest description of the fix there is.
--
-- IT SUGGESTS, IT DOES NOT RESTRICT. Typing a name that matches nothing is
-- still allowed and still reaches the same refusal. Recruits are not in the
-- guild yet, and a box that would only accept what it could offer would be a
-- new way to fail rather than fewer.
--
-- NO ARROW KEYS. An EditBox owns its arrow keys for moving the cursor, and
-- taking them needs OnKeyDown plus SetPropagateKeyboardInput, which turns off
-- keyboard propagation for the whole frame and has broken chat in other
-- addons that tried it. Click a row, or press Enter to take the first one.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local NameSuggest = {}
SYL.NameSuggest = NameSuggest

local MAX_ROWS = 6
local ROW_HEIGHT = 20
local PAD = 4
local HEADING_HEIGHT = 16

-- A prefix match is what somebody typing a name means, so those come first and
-- a match in the middle only fills the space left over. Typing "rak" should
-- not put "Thrashcans" above "Rakahasa".
local function Rank(name, typed)
    local lower = name:lower()

    if lower:sub(1, #typed) == typed then
        return 1
    end

    if lower:find(typed, 1, true) then
        return 2
    end

    return nil
end

function NameSuggest.Match(candidates, typed)
    typed = (typed or ""):lower()

    if typed == "" then
        return {}
    end

    local matched = {}

    for _, entry in ipairs(candidates or {}) do
        local name = entry.name

        if type(name) == "string" and name ~= "" then
            local rank = Rank(name, typed)

            if rank then
                table.insert(matched, { entry = entry, rank = rank, name = name })
            end
        end
    end

    table.sort(matched, function(left, right)
        if left.rank ~= right.rank then
            return left.rank < right.rank
        end

        return left.name:lower() < right.name:lower()
    end)

    local top = {}

    for index = 1, math.min(MAX_ROWS, #matched) do
        table.insert(top, matched[index].entry)
    end

    return top
end

-- What each row says under the name. Class alone is not enough to tell two
-- similar names apart, and picking the wrong one drags somebody onto every
-- list the main appears on — the mistake that used to need a slash command to
-- undo.
local function Note(entry)
    local parts = {}

    if entry.class then
        table.insert(parts, Theme.ClassLabel(entry.class))
    end

    if entry.isAlt and entry.mainName then
        table.insert(parts, "alt of " .. entry.mainName)
    elseif entry.key and SYL.RaidTeam.IsMember(entry.key) then
        -- Asked rather than read off the entry: RosterData does not carry
        -- membership, the row draws it by asking too, and a second copy here
        -- would be one more thing to keep in step.
        table.insert(parts, "raiding")
    end

    if entry.isIncoming then
        table.insert(parts, "joining")
    end

    return table.concat(parts, " · ")
end

local function BuildRow(popup, index)
    local row = CreateFrame("Button", nil, popup)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(HEADING_HEIGHT + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -PAD, -(HEADING_HEIGHT + (index - 1) * ROW_HEIGHT))

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row:SetScript("OnEnter", function(self) self.highlight:Show() end)
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end)

    row.name = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint("LEFT", 6, 0)

    row.note = Theme.CreateText(row, Theme.sizes.columnHeader, "textMuted")
    row.note:SetPoint("RIGHT", -6, 0)
    row.note:SetJustifyH("RIGHT")

    popup.rows[index] = row

    return row
end

-- config:
--   getCandidates()  entries with .name, and optionally .class, .key,
--                    .isAlt, .mainName, .isIncoming
--   nameFor(entry)   the name a pick should insert; defaults to entry.name
--   onAccept(name)   called with the chosen name; optional
function NameSuggest.Attach(holder, config)
    local editBox = holder.editBox

    if not editBox then
        return nil
    end

    local popup = CreateFrame("Frame", nil, holder, "BackdropTemplate")

    -- Opens upward. Every box this is attached to so far sits in a window
    -- footer, where there is nothing below it to open into.
    popup:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
    popup:SetWidth(220)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(holder:GetFrameLevel() + 20)
    popup:Hide()

    Theme.StyleWindow(popup)

    popup.heading = Theme.CreateText(popup, Theme.sizes.columnHeader, "textMuted")
    popup.heading:SetPoint("TOPLEFT", PAD + 6, -5)

    popup.rows = {}
    popup.shown = {}

    local function Hide()
        popup:Hide()
        popup.shown = {}
    end

    local function Accept(name)
        editBox:SetText(name)
        holder.UpdatePlaceholder()
        Hide()

        if config.onAccept then
            config.onAccept(name)
        end
    end

    local function Show(matches, typed)
        if #matches == 0 then
            Hide()

            return
        end

        popup.shown = matches
        popup.heading:SetText("MATCHING \"" .. typed:upper() .. "\"")

        for index = 1, #matches do
            local entry = matches[index]
            local row = popup.rows[index] or BuildRow(popup, index)

            row.name:SetText(entry.name)

            local classColor = Theme.GetClassColor(entry.class)

            if classColor then
                Theme.SetCustomTextColor(
                    row.name, classColor[1], classColor[2], classColor[3]
                )
            else
                Theme.SetTextColor(row.name, "textPrimary")
            end

            row.note:SetText(Note(entry))

            row:SetScript("OnClick", function()
                Accept(config.nameFor and config.nameFor(entry) or entry.name)
            end)

            row:Show()
        end

        for index = #matches + 1, #popup.rows do
            popup.rows[index]:Hide()
        end

        popup:SetHeight(HEADING_HEIGHT + (#matches * ROW_HEIGHT) + PAD + 2)
        popup:Show()
    end

    -- HookScript rather than SetScript: SearchBox already handles this to keep
    -- its placeholder in step, and replacing it would leave the prompt showing
    -- over typed text.
    editBox:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        local typed = self:GetText() or ""

        Show(NameSuggest.Match(config.getCandidates(), typed), typed)
    end)

    editBox:HookScript("OnEnterPressed", function()
        local first = popup.shown[1]

        if popup:IsShown() and first then
            Accept(config.nameFor and config.nameFor(first) or first.name)
        end
    end)

    editBox:HookScript("OnEscapePressed", Hide)

    -- Leaving the box without choosing dismisses the list. Without this it
    -- hangs over whatever the window draws next, and it is drawn above
    -- everything so it would be the top thing on screen.
    editBox:HookScript("OnEditFocusLost", Hide)

    holder.suggest = popup

    return popup
end
