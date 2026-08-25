-- UI/SettingsToggles.lua
--
-- WHAT the eight switches on the settings screen are. UI/SettingsRows.lua is
-- HOW they are drawn, and UI/SettingsTabs.lua decides which tab each one
-- lands on.
--
-- Split out because UI/SettingsRows.lua is size-exempt and its exemption note
-- had gone stale: it said the file was three sections sharing a row factory
-- and layout constants, which was true before the factory and the refresh
-- registry were exported. They are exported now -- for the item-type grid,
-- the scoring numbers and the tools list, each of which lives in a file of
-- its own -- so this table has nothing left holding it in place except
-- habit. It is two hundred lines of declarations and the reasoning behind
-- them, and it will grow every time a switch is added.
--
-- NOTHING HERE MOVED BUT THE NAMESPACE. Core/Absences.lua is the worked
-- example HANDOFF.md points at for this, and its lesson is to do the move as
-- its own change: a move mixed with an edit shows as hundreds of deleted and
-- added lines and nobody can tell which are which.
--
-- ROWS ARE OF TWO KINDS AND HAVE TO LOOK IT. Most are checkboxes bound to a
-- saved setting. Two are not settings at all -- the color scheme and the
-- output window cycle through values when pressed, and drawing those as
-- checkboxes meant drawing a box that could never be ticked. An entry with an
-- `action` is the second kind, and it carries its current value in its label
-- through `describe`.

local SYL = _G.ShowUsYourLoot

local SettingsToggles = {}
SYL.SettingsToggles = SettingsToggles

-- Said under CAPTURE on the Recording tab, and at the foot of the untabbed
-- behavior block. One string because they are the same sentence, and because
-- the last time two screens carried their own copy of an explanation they
-- drifted.
SettingsToggles.PERSONAL_LOOT_NOTE =
    "Your client only sees other people's loot while you are grouped with "
    .. "them, so counting gear taken without a roll mostly counts yours."

SettingsToggles.LIST = {
    {
        -- Cycles rather than opening a menu, and repaints immediately, so
        -- picking one is a matter of clicking until it looks right instead of
        -- reading color names and guessing.
        label = "Color scheme",
        tab = "display",
        action = function()
            local palette =
                SYL.Theme.Apply(SYL.Palettes.Next(SYL.Theme.paletteKey))

            SYL:Print(
                "Color scheme: " .. palette.name .. " — " .. palette.note .. "."
            )
        end,
        describe = function()
            local palette = SYL.Theme.Current()

            return "Color scheme: " .. (palette and palette.name or "unknown")
        end,
    },
    {
        -- Cycles for the same reason the color scheme does: three positions,
        -- and the answer is visible on the board the moment you close this.
        --
        -- Off / 2 / 3, not Off / 1 / 2 / 3. One night and no floor rank exactly
        -- the same people — Core/LootScore.lua:MinNights has the argument — so
        -- the fourth position would have been a control that does nothing.
        label = "Rank raiders after",
        tab = "scoring",
        action = function()
            local ORDER = { 3, 2, 0 }
            local current = SYL.LootScore.MinNights()
            local nextFloor = ORDER[1]

            for index, value in ipairs(ORDER) do
                if value == current then
                    nextFloor = ORDER[(index % #ORDER) + 1]
                    break
                end
            end

            ShowUsYourLootDB.settings.minRankNights = nextFloor

            SYL:Print(nextFloor == 0
                and "Ranking everybody from their first raid night."
                or ("Ranking raiders once they have "
                    .. SYL.Utilities.Count(nextFloor, "raid night") .. "."))

            if SYL.RefreshMainWindow then
                SYL:RefreshMainWindow()
            end
        end,
        describe = function()
            local floor = SYL.LootScore.MinNights()

            return floor == 0
                and "Rank raiders after: their first night"
                or ("Rank raiders after: "
                    .. SYL.Utilities.Count(floor, "night"))
        end,
    },
    {
        label = "Record group loot from Loot History",
        tab = "recording",
        key = "lootHistoryCapture",

        onChanged = function(enabled)
            if enabled then
                SYL.LootHistory.Enable()
            else
                SYL.LootHistory.Disable()
            end
        end,
    },
    {
        label = "Show the minimap button",
        tab = "display",
        key = "showMinimapButton",

        onChanged = function(enabled)
            SYL.MinimapButton.SetShown(enabled)
        end,
    },
    {
        -- Says gear, because that is now all it announces. Every quality is
        -- still recorded; announcing every quality was what doubled the
        -- user's loot chat with grays after a Mythic+ run.
        -- SHORTENED BECAUSE IT DID NOT FIT. It rendered as "Announce gear in
        -- chat when it is recor..." on the settings screenshot in the
        -- CurseForge gallery. Measured in the real font at 232px against a
        -- cell that takes about 202 — "Record group loot from Loot History"
        -- is the longest label that fits, and it measures exactly that.
        -- Anything added here should be checked against it.
        --
        -- "when it is recorded" was the part carrying no information: this
        -- section is about what gets recorded, and the note underneath says
        -- the rest.
        label = "Announce gear in chat",
        tab = "recording",
        key = "announceCaptures",
    },
    {
        -- Not a checkbox: it cycles windows and reports where it landed.
        label = "Output window",
        tab = "display",
        action = function()
            local name = SYL.Output.CycleWindow()

            SYL:Print(
                "Messages now go to the \"" .. tostring(name) .. "\" window."
            )
        end,
        describe = function()
            return "Output window: " .. SYL.Output.GetWindowName()
        end,
    },
    {
        label = "Show debug messages",
        tab = "display",
        key = "debug",
    },
    {
        -- THE RECOVERY THAT ONLY A COMMAND COULD REACH. This is the way back
        -- from a window dragged past the edge of the screen — where the grip
        -- that would move it is off the monitor with it — and it lived behind
        -- `/syl resetwindows` and nowhere else. Somebody who has lost a window
        -- cannot be expected to know a command nobody told them about, and
        -- this is the one case where they cannot see the interface that would
        -- have told them.
        --
        -- Measured in the real font, like every other label here. "Put windows
        -- back where they started" says more and comes to 203px against a cell
        -- that takes about 202 — one pixel over, which is the whole reason the
        -- note on "Announce gear in chat" above exists. This one is 107 and
        -- has room to spare.
        label = "Reset window sizes",
        tab = "tools",
        action = function()
            local reset = SYL.Widgets.ResetSizes()

            -- Saved sizes go either way; only windows opened this session can
            -- be moved on the spot. Zero is an ordinary answer rather than a
            -- failure, and saying so stops it reading as one. Same wording as
            -- the command, because they are the same act.
            if reset == 0 then
                SYL:Print(
                    "Saved window sizes and positions cleared. Every window "
                    .. "will open at its default size, in the middle of the "
                    .. "screen."
                )

                return
            end

            SYL:Print(
                SYL.Utilities.Count(reset, "open window")
                .. " put back to the default size and centered. Saved sizes "
                .. "and positions cleared."
            )
        end,
    },
}

