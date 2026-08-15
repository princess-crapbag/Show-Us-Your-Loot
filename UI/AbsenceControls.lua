-- UI/AbsenceControls.lua
--
-- Marking somebody out, and back in, from the calendar.
--
-- WHY THIS IS NOT JUST A SLASH COMMAND. `/syl out <name>` has existed for a
-- while and works perfectly for the one person who knows it exists. Aimee
-- ships this addon to a guild: "when you add features or fix things for me,
-- they also need to work for other people who use the addon, which means just
-- putting a command in won't work." A guildie will never find a command they
-- were not told about, so the control belongs on the screen that already shows
-- who is out.
--
-- THE BOX STARTS WITH YOUR OWN NAME. Marking yourself out is the common case
-- and the one that needs no permission from anybody, so it is one click from
-- the calendar. Typing over it marks somebody else, which is equally allowed —
-- attribution rather than authorization, and every absence says who set it.
--
-- BACK IN ONLY REMOVES WHAT THIS CLIENT WROTE. Somebody else's claim is theirs
-- to retract; their copy of the addon is authoritative for it and would
-- rebroadcast it within seconds. So the refusal names who to ask rather than
-- appearing to work and then undoing itself.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local AbsenceControls = {}
SYL.AbsenceControls = AbsenceControls

local INPUT_WIDTH = 150
local SUGGESTIONS = 5
local SUGGESTION_HEIGHT = 18

local function OwnName()
    return (UnitName and UnitName("player")) or ""
end

-- Roster names starting with what has been typed. Prefix rather than
-- substring: people type the beginning of a name, and a substring match on two
-- letters offers most of the guild.
function AbsenceControls.Match(typed, limit)
    local found = {}

    if type(typed) ~= "string" or typed == "" then
        return found
    end

    local wanted = typed:lower()
    local seen = {}

    for _, entry in ipairs(SYL.RosterData.Build() or {}) do
        local name = entry.name

        if type(name) == "string"
            and not seen[name]
            and name:lower():sub(1, #wanted) == wanted
        then
            seen[name] = true

            table.insert(found, name)
        end
    end

    table.sort(found)

    while #found > (limit or SUGGESTIONS) do
        table.remove(found)
    end

    return found
end

-- Redraws the suggestion popup for whatever is in the box. Hidden when there
-- is nothing to suggest, and when the only match is what has already been
-- typed in full — offering somebody the word they just finished typing is
-- noise the first time and an obstacle every time after.
function AbsenceControls.RefreshSuggestions(frame)
    if not frame or not frame.suggestions then
        return 0
    end

    local typed = frame.nameInput.editBox:GetText() or ""
    local matches = AbsenceControls.Match(typed, SUGGESTIONS)

    if #matches == 0
        or (#matches == 1 and matches[1]:lower() == typed:lower())
    then
        frame.suggestions:Hide()

        return 0
    end

    for index, row in ipairs(frame.suggestionRows) do
        local name = matches[index]

        if name then
            row.value = name
            row.label:SetText(name)
            row:Show()
        else
            row.value = nil
            row:Hide()
        end
    end

    frame.suggestions:SetHeight(SUGGESTION_HEIGHT * #matches)
    frame.suggestions:Show()

    return #matches
end

-- handlers:
--   getSelectedDay()   the day key the calendar is showing, or nil
--   onChanged()        redraw
function AbsenceControls.Create(parent, handlers)
    -- ON THE TOOLBAR, NOT ABOVE THE STAT PANEL. The month grid runs to six
    -- rows and the stat panel is 152 tall; between them there is no room for a
    -- control strip, and one put there lands on the last week of the month.
    -- The top row has horizontal space going spare.
    local frame = CreateFrame("Frame", nil, parent)

    frame:SetHeight(22)
    frame:SetPoint("TOPRIGHT", -2, -2)
    frame:SetWidth(400)

    local label = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")

    label:SetPoint("LEFT", 0, 0)
    label:SetText("OUT")

    frame.nameInput = SYL.SearchBox.Create(
        frame, INPUT_WIDTH, "Name", function()
            AbsenceControls.RefreshSuggestions(frame)
        end, { bordered = true }
    )

    frame.nameInput:SetPoint("LEFT", label, "RIGHT", 8, 0)
    frame.nameInput.editBox:SetText(OwnName())

    local function Selected()
        return handlers.getSelectedDay and handlers.getSelectedDay() or nil
    end

    local function Named()
        local text = frame.nameInput.editBox:GetText() or ""

        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- Every path through both buttons ends here, so a day that was never
    -- picked says so once rather than in four places.
    local function Require()
        local dayKey = Selected()
        local name = Named()

        if not dayKey then
            SYL:Print("Pick a day on the calendar first.")

            return nil
        end

        if name == "" then
            SYL:Print("Type a name, or leave your own in the box.")

            return nil
        end

        return dayKey, name
    end

    frame.outButton =
        Theme.CreateButton(frame, 90, 22, "Mark out", function()
            frame.suggestions:Hide()

            local dayKey, name = Require()

            if not dayKey then
                return
            end

            local absence = SYL.RaidSchedule.AddAbsence(name, dayKey, dayKey)

            if not absence then
                SYL:Print("Could not mark " .. name .. " out.")

                return
            end

            SYL:Print(
                name .. " is out on " .. dayKey
                .. (SYL.Features.IsEnabled("absenceSharing")
                    and ". The guild will see it."
                    or ". Turn on Share who is out in Settings for the guild "
                        .. "to see it.")
            )

            SYL.AbsenceSync.OnOwnAbsencesChanged()

            if handlers.onChanged then
                handlers.onChanged()
            end
        end)

    frame.outButton:SetPoint("LEFT", frame.nameInput, "RIGHT", 8, 0)

    frame.backButton =
        Theme.CreateButton(frame, 90, 22, "Back in", function()
            frame.suggestions:Hide()

            local dayKey, name = Require()

            if not dayKey then
                return
            end

            local removed, theirs, setByWhom =
                SYL.RaidSchedule.RemoveAbsencesFor(name, dayKey)

            if removed == 0 then
                if theirs > 0 then
                    SYL:Print(
                        name .. " was marked out by "
                        .. (setByWhom or "somebody else")
                        .. ", so only they can take it back."
                    )
                else
                    SYL:Print(
                        "Nothing recorded for " .. name .. " on " .. dayKey
                        .. "."
                    )
                end

                return
            end

            SYL:Print(
                name .. " is back on " .. dayKey .. "."
                .. (theirs > 0
                    and ("  " .. theirs
                        .. " set by somebody else were left alone.")
                    or "")
            )

            SYL.AbsenceSync.OnOwnAbsencesChanged()

            if handlers.onChanged then
                handlers.onChanged()
            end
        end)

    frame.backButton:SetPoint("LEFT", frame.outButton, "RIGHT", 6, 0)

    -- A popup rather than a reserved row. It exists only while somebody is
    -- typing, so giving it permanent space would cost the grid a week of the
    -- month for something visible a few seconds at a time. Raised above the
    -- calendar because it is allowed to cover it.
    frame.suggestions = CreateFrame("Frame", nil, frame)

    frame.suggestions:SetPoint("TOPLEFT", frame.nameInput, "BOTTOMLEFT", 0, -2)
    frame.suggestions:SetWidth(INPUT_WIDTH)
    frame.suggestions:SetHeight(SUGGESTION_HEIGHT * SUGGESTIONS)
    -- Guarded, because a frame that has not been laid out has no level to
    -- add to and the answer is not always a number.
    local level = frame:GetFrameLevel()

    if type(level) == "number" then
        frame.suggestions:SetFrameLevel(level + 10)
    end
    frame.suggestions:Hide()

    local back =
        Theme.CreateSolidTexture(frame.suggestions, "headerBar", "BACKGROUND")

    back:SetAllPoints()

    frame.suggestionRows = {}

    for index = 1, SUGGESTIONS do
        local row = CreateFrame("Button", nil, frame.suggestions)

        row:SetPoint(
            "TOPLEFT", 0, -(index - 1) * SUGGESTION_HEIGHT
        )
        row:SetSize(INPUT_WIDTH, SUGGESTION_HEIGHT)

        row.label = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
        row.label:SetPoint("LEFT", 6, 0)

        row:SetScript("OnClick", function(self)
            if not self.value then
                return
            end

            frame.nameInput.editBox:SetText(self.value)
            frame.nameInput.editBox:ClearFocus()

            if frame.nameInput.UpdatePlaceholder then
                frame.nameInput.UpdatePlaceholder()
            end

            frame.suggestions:Hide()
        end)

        frame.suggestionRows[index] = row
    end

    local Tip = SYL.Tooltips.Attach

    Tip(frame.nameInput, "Who is out",
        "Starts as your own character, so marking yourself out is one click. "
        .. "Type over it to mark somebody else — anyone can, and every absence "
        .. "records who set it.")

    Tip(frame.outButton, "Mark out",
        "Marks that person out on the day selected above. With Share who is "
        .. "out switched on, everyone in the guild running this addon sees it.")

    Tip(frame.backButton, "Back in",
        "Removes an absence you set on the selected day. An absence somebody "
        .. "else set can only be removed by them, and this will say who.")

    return frame
end
