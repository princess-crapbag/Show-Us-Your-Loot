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

local function OwnName()
    return (UnitName and UnitName("player")) or ""
end

-- handlers:
--   getSelectedDay()   the day key the calendar is showing, or nil
--   onChanged()        redraw
function AbsenceControls.Create(parent, handlers)
    local frame = CreateFrame("Frame", nil, parent)

    frame:SetHeight(24)
    frame:SetPoint("BOTTOMLEFT", 0, 174)
    frame:SetPoint("BOTTOMRIGHT", 0, 174)

    local label = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")

    label:SetPoint("LEFT", 2, 0)
    label:SetText("WHO IS OUT")

    frame.nameInput = SYL.SearchBox.Create(
        frame, INPUT_WIDTH, "Name", function() end, { bordered = true }
    )

    frame.nameInput:SetPoint("LEFT", label, "RIGHT", 10, 0)
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
