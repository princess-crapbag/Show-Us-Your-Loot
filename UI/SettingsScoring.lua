-- UI/SettingsScoring.lua
--
-- The Scoring tab: the rank floor, the guild threshold, and what a win is
-- worth.
--
-- These are the numbers the boards argue about, and until 0.4.0 every one of
-- them was either a constant in a Core file or a cycling row wedged between
-- "record group loot" and "show the minimap button". They are the reason the
-- tabs exist.
--
-- ITS OWN FILE because UI/SettingsRows.lua is size-exempt at 700 lines and
-- the header there says what growing it costs. This builds with that file's
-- exported row factory and registers into its refresh list, so a row here and
-- a row there cannot drift.
--
-- THE CAUTION IS ON THE TAB, NOT IN A TOOLTIP. Aimee's call, and the reason
-- is that a tooltip is read by somebody who already suspects there is
-- something to know. Changing a weight re-scores every night already raided
-- -- see Core/LootScore.lua, and Core/DropRules.lua for the guild threshold
-- doing the same since bbcf4dc. Somebody has to meet that sentence before
-- they type, not after.
--
-- THE SECTION REBUILDS ITSELF when the offspec link is broken, because that
-- adds a fourth row and the tab is a different height with it. Torn down and
-- built again rather than shuffled, which is how UI/SettingsWidgets.lua does
-- the same job -- and the heading and the "EDITABLE" marker come down with
-- it, because both are font strings on the page rather than children of the
-- container.

local SYL = _G.ShowUsYourLoot

local SettingsScoring = {}
SYL.SettingsScoring = SettingsScoring

local SECTION_GAP = 24
local HEADING_HEIGHT = 18
local ROW_HEIGHT = 20

-- Set by UI/SettingsTabs.lua, which is the only thing that knows how a
-- content height becomes a window height.
SettingsScoring.onHeightChanged = nil

-- Everything drawn, so a rebuild can take all of it down. Containers and the
-- font strings that are not inside them.
local drawn = {}

local state = {}

local function Track(frame)
    if frame then
        table.insert(drawn, frame)
    end

    return frame
end

local function TearDown()
    for _, frame in ipairs(drawn) do
        if frame.Hide then
            frame:Hide()
        end
    end

    drawn = {}
end

--------------------------------------------------------------------------
-- FAIRNESS
--------------------------------------------------------------------------

local GUILD_NOTE =
    "The threshold decides which nights count at all - attendance, the "
    .. "calendar, and since 0.4.0 whether a drop scores. Raising it "
    .. "mid-season re-scores nights you have already raided."

local function BuildFairness(page, top)
    -- One column, not two: these rows are a sentence with a number beside
    -- them and there is nothing to put alongside. extraRows is the guild
    -- threshold, which is not a toggle and so is not in that list.
    local container, height, count = SYL.SettingsRows.BuildToggleSection(
        page, top, "scoring", "FAIRNESS", { columns = 1, extraRows = 1 }
    )

    Track(container)
    Track(container.heading)

    SYL.SettingsNumberRow.Create(container, (count or 0) + 1, {
        label = "Count a night as the guild's at",
        suffix = "%",
        hint = "NEW",

        get = function()
            return math.floor(SYL.RaidSession.GuildThreshold() * 100 + 0.5)
        end,

        set = function(value)
            return SYL.RaidSession.SetGuildThreshold(value)
        end,

        refusal = "The guild threshold is a percentage, so it has to be "
            .. "between 0 and 100.",

        note = GUILD_NOTE,
    })

    local noteHeight, note =
        SYL.SettingsRows.AddNote(page, top - height - 4, GUILD_NOTE)

    Track(note)

    return height + 4 + noteHeight
end

--------------------------------------------------------------------------
-- WHAT A WIN IS WORTH
--------------------------------------------------------------------------

-- WHY THREE ROWS AND FOUR WEIGHTS. Aimee: "leave the 4 weights, i only want
-- to see the 3 for me if possible." The client reports offspec separately
-- from greed and her season holds sixteen offspec rolls, so the weight has to
-- keep existing; it follows greed instead of being shown. That link is what
-- makes hiding it safe rather than merely tidy -- a hidden number free to
-- drift from a visible one would eventually score those sixteen rolls at a
-- value nobody could see or explain, which is the exact failure the fairness
-- board exists to prevent.
local LINKED_NOTE =
    "Your client reports offspec separately from greed. Yours are worth the "
    .. "same, so only one row shows and offspec follows it. Unlink them if "
    .. "your guild scores them differently."

local SPLIT_NOTE =
    "Offspec is scored on its own now. It no longer follows greed, so the "
    .. "two can be set to different numbers."

local CAUTION =
    "Changing a weight re-scores every night already raided, not just the "
    .. "next one. Set these before a season and leave them."

local function BuildWeights(page, top)
    local split = SYL.LootScore.IsOffspecSplit()
    local states = SYL.LootScore.EditableStates()

    local container, heading =
        SYL.SettingsRows.AddSection(page, "WHAT A WIN IS WORTH", top, "EDITABLE")

    Track(container)
    Track(heading)
    Track(container.marker)

    -- The weight rows, then the checkbox that decides how many there are.
    container:SetHeight((#states + 1) * ROW_HEIGHT)

    for index, rollState in ipairs(states) do
        local label = SYL.LootScore.LABELS[rollState] or "?"

        SYL.SettingsNumberRow.Create(container, index, {
            label = label,

            -- Said on the row that is actually carrying the fourth weight,
            -- so the link is visible from the tab rather than only from this
            -- file. It disappears the moment the two are unlinked.
            hint = (not split and label == "Greed") and "offspec too" or nil,

            get = function()
                return SYL.LootScore.WeightOf(rollState)
            end,

            set = function(value)
                return SYL.LootScore.SetWeight(rollState, value)
            end,

            refusal = label
                .. " has to be zero or more. A win cannot be worth a "
                .. "penalty.",

            note = "What one " .. label .. " win adds to somebody's share.",
        })
    end

    local checkbox = SYL.SettingsRows.CreateRow(
        container,
        #states + 1,
        "Score offspec separately",

        function()
            SYL.LootScore.SetOffspecSplit(not SYL.LootScore.IsOffspecSplit())
            SettingsScoring.Rebuild()
        end,

        { columns = 1 }
    )

    checkbox.isChecked = function()
        return SYL.LootScore.IsOffspecSplit()
    end

    SYL.SettingsRows.Register(checkbox)
    checkbox:SetChecked(split)

    SYL.Tooltips.Attach(
        checkbox,
        "Score offspec separately",
        split and SPLIT_NOTE or LINKED_NOTE
    )

    local height = HEADING_HEIGHT + (#states + 1) * ROW_HEIGHT

    local linkHeight, linkNote = SYL.SettingsRows.AddNote(
        page, top - height - 4, split and SPLIT_NOTE or LINKED_NOTE
    )

    Track(linkNote)

    height = height + 4 + linkHeight

    -- In the warning color, on the tab. See the header.
    local cautionHeight, caution =
        SYL.SettingsRows.AddNote(page, top - height - 2, CAUTION, "warning")

    Track(caution)

    return height + 2 + cautionHeight
end

--------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------

-- Returns the content height. UI/SettingsTabs.lua turns that into a window
-- height, because it owns the padding above and below.
function SettingsScoring.Build(page, top)
    state.page = page
    state.top = top

    -- Safe to clear the whole list here because this tab is the only thing
    -- in the addon that builds number rows. If a second one ever does, this
    -- has to become a per-owner forget rather than a reset.
    SYL.SettingsNumberRow.Reset()

    local y = top
    local height = BuildFairness(page, y)

    y = y - height - SECTION_GAP

    local weights = BuildWeights(page, y)

    return height + SECTION_GAP + weights
end

-- Only the notes and the section that owns them are font strings on the page,
-- and TearDown hides those. The rows inside a container go with it.
function SettingsScoring.Rebuild()
    if not state.page then
        return
    end

    TearDown()

    local height = SettingsScoring.Build(state.page, state.top)

    if SettingsScoring.onHeightChanged then
        SettingsScoring.onHeightChanged(height)
    end

    SYL.SettingsRows.Refresh()
end
