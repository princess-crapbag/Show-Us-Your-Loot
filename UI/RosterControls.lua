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
    local coverage = SYL.RaidBuffs.BuildCoverage(roster)
    local covered, total = SYL.RaidBuffs.Summarise(coverage)
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
    frame.coverageText =
        Theme.CreateText(frame, Theme.sizes.row, "textPrimary")

    frame.coverageText:SetPoint("TOPLEFT", 18, -74)

    frame.missingText = Theme.CreateText(frame, Theme.sizes.row, "warning")
    frame.missingText:SetPoint("TOPLEFT", 18, -96)
    frame.missingText:SetPoint("TOPRIGHT", -16, -96)
    frame.missingText:SetJustifyH("LEFT")

    frame.rolesText =
        Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")

    frame.rolesText:SetPoint("TOPLEFT", 18, -120)

    local hint = Theme.CreateText(frame, Theme.sizes.rowSmall, "textMuted")
    hint:SetPoint("TOPLEFT", 18, -142)
    hint:SetPoint("TOPRIGHT", -16, -142)
    hint:SetJustifyH("LEFT")
    hint:SetText(
        "Tick names to act on several at once. Click ROLE to set what "
        .. "somebody plays; a role in brackets is what the game reported."
    )

    frame.teamButton =
        SYL.Toggles.Create(frame, 130, "Raid team only", handlers.onTeamOnly)

    frame.teamButton:SetPoint("TOPLEFT", 18, -170)

    frame.search =
        SYL.SearchBox.Create(frame, 180, "Search names…", handlers.onSearch)

    frame.search:SetPoint("LEFT", frame.teamButton, "RIGHT", 8, 0)
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

    frame.mainInput =
        SYL.SearchBox.Create(frame, 130, "Main's name…", function() end)

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

            Finish(
                applied .. " mapped as alts of " .. mainName
                .. (refused > 0 and (", " .. refused .. " refused") or "")
                .. ". This changes past numbers as well as future ones."
            )
        end)

    frame.altButton:SetPoint("LEFT", frame.mainInput, "RIGHT", 6, 0)

    frame.clearButton =
        Theme.CreateButton(frame, 86, 22, "Untick all", function()
            handlers.onClearSelection()
            handlers.onChanged()
        end)

    frame.clearButton:SetPoint("LEFT", frame.altButton, "RIGHT", 12, 0)
end

-- handlers:
--   onTeamOnly(on), onSearch(text)  filter changes
--   getSelected()                   the ticked entries
--   onClearSelection()              untick everything
--   onChanged()                     redraw
function RosterControls.Create(frame, handlers)
    CreateSummary(frame, handlers)
    CreateActions(frame, handlers)
end
