-- UI/RosterControls.lua
--
-- Everything around the roster list: the buff summary above it, and the bulk
-- actions below it.
--
-- Split from RosterWindow the third time it crossed the size limit. That file
-- now holds the list state and the redraw; this one holds the controls and
-- what pressing them does.
--
-- The actions act on whatever is ticked. Marking fifteen raiders one click at
-- a time, or mapping six alts one slash command at a time, is the work this
-- replaces — so both are one press over a checked set.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local RosterControls = {}
SYL.RosterControls = RosterControls

-- The button says which list you are on rather than what pressing it does,
-- because the two states are both destinations here.
function RosterControls.UpdateFilters(frame, teamOnly, activeOnly)
    frame.teamButton.label:SetText(teamOnly and "Raid team" or "Whole guild")

    Theme.SetTextColor(
        frame.teamButton.label, teamOnly and "accent" or "textPrimary"
    )

    if not frame.activeButton then
        return
    end

    frame.activeButton.label:SetText(activeOnly and "Active" or "Everyone")

    Theme.SetTextColor(
        frame.activeButton.label, activeOnly and "accent" or "textPrimary"
    )
end

function RosterControls.UpdateRoles(frame, roster)
    local counts = SYL.RaidTeam.CountRoles(roster)

    frame.rolesText:SetText(
        counts.TANK .. " tanks  ·  "
        .. counts.HEALER .. " healers  ·  "
        .. counts.DPS .. " dps"
        .. (counts.unset > 0
            and ("  ·  " .. counts.unset .. " unset") or "")
    )
end

function RosterControls.UpdateCoverage(frame, roster)
    -- Nothing to update when the feature never built the lines.
    if not frame.coverageText then
        return
    end

    local coverage = SYL.RaidBuffs.BuildCoverage(roster)
    local covered, total = SYL.RaidBuffs.Summarize(coverage)
    local missing = SYL.RaidBuffs.Missing(coverage)

    frame.coverageText:SetText(
        covered .. " of " .. total .. " raid buffs covered"
    )

    if #missing == 0 then
        frame.missingText:SetText("Nothing missing.")
        Theme.SetTextColor(frame.missingText, "accent")

        return
    end

    local names = {}

    for _, buff in ipairs(missing) do
        table.insert(names, buff.name)
    end

    frame.missingText:SetText("Missing: " .. table.concat(names, ", "))
    Theme.SetTextColor(frame.missingText, "warning")
end

local function CreateSummary(frame, handlers)
    -- Not created at all when the feature is off, rather than created and
    -- left blank. Two empty lines of chrome are still two lines of chrome.
    if SYL.Features.IsEnabled("raidBuffs") then
        frame.coverageText =
            Theme.CreateText(frame, Theme.sizes.row, "textPrimary")

        frame.coverageText:SetPoint("TOPLEFT", 18, -74)

        frame.missingText = Theme.CreateText(frame, Theme.sizes.row, "warning")
        frame.missingText:SetPoint("TOPLEFT", 18, -96)
        frame.missingText:SetPoint("TOPRIGHT", -16, -96)
        frame.missingText:SetJustifyH("LEFT")
    end

    frame.rolesText =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")

    frame.rolesText:SetPoint("TOPLEFT", 18, -120)

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -142)
    hint:SetPoint("TOPRIGHT", -16, -142)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Whole guild to add people. Tick names to act on several at once, "
        .. "and click ROLE to set what somebody plays."
    )

    -- The raid team is what this window is for, so it opens on it. Adding
    -- somebody means widening to the guild deliberately, which is the rarer
    -- action and the one worth a click.
    frame.teamButton =
        Theme.CreateButton(frame, 130, 20, "Raid team", function()
            handlers.onTeamOnly()
        end)

    frame.teamButton:SetPoint("TOPLEFT", 18, -170)

    -- Somebody who has not signed in for a month is not somebody you can
    -- bring, and in a guild with years of alts in it they are most of the
    -- list. Recruits who have not joined yet are never hidden by this.
    frame.activeButton =
        Theme.CreateButton(frame, 90, 20, "Active", function()
            handlers.onActiveOnly()
        end)

    frame.activeButton:SetPoint("LEFT", frame.teamButton, "RIGHT", 8, 0)

    SYL.Tooltips.Attach(
        frame.activeButton,
        "Active / Everyone",
        "Active hides characters nobody has logged into for "
        .. SYL.RosterData.INACTIVE_DAYS .. " days. Anyone joining the guild "
        .. "is always shown, and so is anyone the client has not told us "
        .. "about yet."
    )

    frame.search =
        SYL.SearchBox.Create(frame, 180, "Search names…", handlers.onSearch)

    frame.search:SetPoint("LEFT", frame.activeButton, "RIGHT", 8, 0)
end

local function CreateActions(frame, handlers)
    local function EachSelected(action)
        local entries = handlers.getSelected()

        for _, entry in ipairs(entries) do
            action(entry)
        end

        return #entries
    end

    local function Finish(message)
        SYL:Print(message)

        -- Once per press rather than once per raider. Both buttons above walk
        -- a selection, and announcing inside the loop would send the whole
        -- roster again for every name in it.
        SYL.RosterSync.OnOwnRosterChanged()

        handlers.onClearSelection()
        handlers.onChanged()
    end

    frame.addButton =
        Theme.CreateButton(frame, 116, 22, "Add to team", function()
            local count = EachSelected(function(entry)
                SYL.RaidTeam.SetMember(entry.guid, true)
            end)

            Finish(count .. " added to the raid team.")
        end)

    frame.addButton:SetPoint("BOTTOMLEFT", 16, 14)

    frame.removeButton =
        Theme.CreateButton(frame, 92, 22, "Remove", function()
            local count = EachSelected(function(entry)
                SYL.RaidTeam.SetMember(entry.guid, false)
            end)

            Finish(count .. " removed from the raid team.")
        end)

    frame.removeButton:SetPoint("LEFT", frame.addButton, "RIGHT", 6, 0)

    -- Bordered, and it says what it is for rather than "Main's name…", which
    -- is what the identical-looking search box above it would have said if it
    -- filtered by main. This one filters nothing: it is the argument to the
    -- button beside it, and does nothing until that button is pressed.
    frame.mainInput = SYL.SearchBox.Create(
        frame, 130, "Alt of whom?", function() end, { bordered = true }
    )

    frame.mainInput:SetPoint("LEFT", frame.removeButton, "RIGHT", 12, 0)

    frame.altButton =
        Theme.CreateButton(frame, 92, 22, "Alt of", function()
            local mainName = frame.mainInput.editBox:GetText() or ""

            -- Resolved before anything is written. A mapping onto a name
            -- that does not resolve would silently do nothing, which is
            -- exactly the failure the TEAM column already had once.
            local mainGUID = SYL.Players.GUIDForName(mainName)

            if not mainGUID then
                SYL:Print(
                    "No character called \"" .. mainName .. "\". Check the "
                    .. "spelling — the name has to be somebody this addon "
                    .. "has seen or who is in the guild."
                )

                return
            end

            local applied, refused = 0, 0

            EachSelected(function(entry)
                local ok = SYL.Players.SetMain(
                    entry.guid, mainGUID, SYL.Players.MANUAL
                )

                if ok then
                    applied = applied + 1
                else
                    refused = refused + 1
                end
            end)

            -- Names the undo at the moment the mistake is made. Mapping the
            -- wrong character is noticed immediately — the main appears on
            -- lists they were never on — and this is the only sentence that
            -- person is guaranteed to read.
            Finish(
                applied .. " mapped as alts of " .. mainName
                .. (refused > 0 and (", " .. refused .. " refused") or "")
                .. ". This changes past numbers as well as future ones. "
                .. "Wrong? Tick them again and press Not an alt."
            )
        end)

    frame.altButton:SetPoint("LEFT", frame.mainInput, "RIGHT", 6, 0)

    -- THE WAY BACK. "Alt of" was a one-way door for months: this screen could
    -- map a character onto a main and had nothing that unmapped one, so a
    -- mistake could only be undone by knowing that `/syl alts clear` exists.
    -- Worse, the button beside it reads "Untick all", which is what somebody
    -- looking for an undo presses — and it clears the ticks, reports nothing,
    -- and leaves the mapping exactly where it was.
    --
    -- Takes no name, because unmapping does not need one: whoever these
    -- characters point at, they stop pointing at them.
    frame.unaltButton =
        Theme.CreateButton(frame, 92, 22, "Not an alt", function()
            local cleared, untouched = 0, 0

            EachSelected(function(entry)
                local ok = SYL.Players.ClearMain(entry.guid)

                if ok then
                    cleared = cleared + 1
                else
                    untouched = untouched + 1
                end
            end)

            Finish(
                cleared .. " back on their own"
                .. (untouched > 0
                    and (", " .. untouched .. " were not mapped to anyone")
                    or "")
                .. ". This changes past numbers as well as future ones."
            )
        end)

    frame.unaltButton:SetPoint("LEFT", frame.altButton, "RIGHT", 6, 0)

    frame.clearButton =
        Theme.CreateButton(frame, 86, 22, "Untick all", function()
            handlers.onClearSelection()
            handlers.onChanged()
        end)

    frame.clearButton:SetPoint("LEFT", frame.unaltButton, "RIGHT", 12, 0)

    local Tip = SYL.Tooltips.Attach

    Tip(frame.addButton, "Add to team",
        "Marks the ticked characters as raiders. Team membership is per "
        .. "character, because you bring a character rather than a person.")

    Tip(frame.removeButton, "Remove",
        "Takes the ticked characters off the raid team. Nothing about their "
        .. "loot history changes.")

    Tip(frame.mainInput, "Whose alt?",
        "Type the main's name, then press Alt of. This box does not filter "
        .. "the list — the search box above it does that.")

    Tip(frame.altButton, "Alt of",
        "Maps every ticked character to the main named on the left. This "
        .. "changes past numbers as well as future ones, because two "
        .. "characters then count as one person. Not an alt undoes it.")

    Tip(frame.unaltButton, "Not an alt",
        "Unmaps every ticked character, so each counts as itself again. Use "
        .. "this to undo an Alt of. It needs no name in the box.")

    Tip(frame.clearButton, "Untick all",
        "Clears the ticked characters. This only changes what is selected — "
        .. "it undoes nothing. To undo an Alt of, use Not an alt.")
end

-- handlers:
--   onTeamOnly(), onActiveOnly()     filter toggles
--   onSearch(text)                  filter changes
--   getSelected()                   the ticked entries
--   onClearSelection()              untick everything
--   onChanged()                     redraw
function RosterControls.Create(frame, handlers)
    CreateSummary(frame, handlers)
    CreateActions(frame, handlers)
end
