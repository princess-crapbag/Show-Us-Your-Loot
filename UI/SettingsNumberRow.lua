-- UI/SettingsNumberRow.lua
--
-- A settings row you type a number into.
--
-- WHY THIS IS A FILE AND NOT FOUR LINES. Every row in this addon's settings
-- window was a checkbox or a value that cycles when you press it. Cycling is
-- right for three color schemes and wrong for a weight, which is any number
-- at all -- so the Scoring tab could not be built until something here could
-- take a typed number. It is the whole reason that tab shipped in 0.4.0
-- showing one row.
--
-- COMMIT ON ENTER AND ON FOCUS LOST, both. Enter is what a person who knows
-- the control does. Clicking away is what everybody else does, and a field
-- that silently discarded what they typed would be worse than no field: they
-- would believe the weight had changed and the board would disagree with them
-- for a season.
--
-- ESCAPE PUTS IT BACK. That is the difference between a field somebody is
-- willing to experiment in and one they are afraid of.
--
-- REFUSAL IS VISIBLE AND NEVER SILENT. LootScore.SetWeight returns false for
-- a negative and for anything that is not a number rather than clamping, and
-- this row honours that: the field goes back to what it held and the reason
-- is printed. A control that quietly turns -50 into 0 teaches somebody that
-- the number they typed was accepted.
--
-- syl-check: the layout constants below are the mockup's, measured rather
-- than chosen -- tools/mockup_settings_tabs.py:number_row is the approved
-- drawing and this is the same 54x16 box at the same right margin.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local SettingsNumberRow = {}
SYL.SettingsNumberRow = SettingsNumberRow

local ROW_HEIGHT = 20

-- The field. 54 wide takes four digits and a percent sign at rowSmall with
-- room to spare, which is every number this addon will ever put in one: a
-- weight and a percentage.
local BOX_WIDTH = 54
local BOX_HEIGHT = 16
local BOX_INSET = 6

-- Digits only, so most of the refusal path never has to run. The rest of it
-- still does -- an empty field and a pasted word both reach Commit.
local MAX_DIGITS = 6

-- NOT SetNumeric(true), which was the first thing tried and is wrong here.
--
-- A numeric EditBox refuses every character that is not a digit, including
-- the ones this widget puts there ITSELF: the guild threshold shows "80%",
-- and SetNumeric would have eaten the percent sign on the way in -- either
-- silently, leaving the field reading 80 with no unit, or by refusing the
-- SetText outright and leaving it blank. Neither is visible from a test,
-- because the test client's EditBox is a stub that accepts anything.
--
-- So the filter is ours: digits and the suffix character survive, everything
-- else is dropped as it is typed. The guard is because SetText inside
-- OnTextChanged fires OnTextChanged again.
local ALLOWED = "[^%d%%]"

local function FilterToNumbers(input)
    local guard = false

    input:SetScript("OnTextChanged", function(self)
        if guard then
            return
        end

        local text = self:GetText() or ""
        local cleaned = text:gsub(ALLOWED, "")

        if cleaned ~= text then
            guard = true
            self:SetText(cleaned)
            guard = false
        end
    end)
end

-- Everything built here, so one call refreshes every number on the screen
-- after something else changed one. Cleared by Reset when a tab rebuilds.
local rows = {}

function SettingsNumberRow.Reset()
    rows = {}
end

function SettingsNumberRow.Refresh()
    for _, row in ipairs(rows) do
        if row.refreshValue then
            row.refreshValue()
        end
    end
end

-- `options` is:
--   label     the text on the left
--   get       returns the number to show
--   set       takes a number, returns true if it took it
--   suffix    drawn after the number, and stripped before parsing ("%")
--   hint      small muted text to the left of the field
--   refusal   what to print when `set` says no
local function Build(parent, index, options)
    local row = CreateFrame("Frame", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- MOUSE ENABLED, which a plain Frame is not.
    --
    -- This is the same fault that left all seven dashboard widget tooltips
    -- dead: Tooltips.Attach hooks OnEnter, and a frame with no mouse never
    -- fires it, so the explanation was drawn into a hook nothing could reach.
    -- Every note in Core/Dashboard.lua was unreachable text for weeks behind
    -- exactly this line being absent.
    row:EnableMouse(true)

    row.label = Theme.CreateText(row, Theme.sizes.rowSmall, "textSecondary")
    row.label:SetPoint("LEFT", 2, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(options.label)

    local edge = Theme.CreateSolidTexture(row, "border", "BACKGROUND")
    edge:SetPoint("RIGHT", -4, 0)
    edge:SetSize(BOX_WIDTH, BOX_HEIGHT)

    local fill = Theme.CreateSolidTexture(row, "rowHover", "ARTWORK")
    fill:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)

    -- The accent stripe down the left of the field, which is what says "you
    -- can type in this" on a screen where every other box is a tick.
    local stripe = Theme.CreateSolidTexture(row, "accent", "OVERLAY")
    stripe:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, 0)
    stripe:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", 0, 0)
    stripe:SetWidth(1)

    local input = CreateFrame("EditBox", nil, row)

    input:SetPoint("TOPLEFT", edge, "TOPLEFT", 3, 0)
    input:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -BOX_INSET + 3, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(MAX_DIGITS)
    input:SetJustifyH("RIGHT")
    input:SetFont(Theme.GetFontPath(), Theme.sizes.rowSmall, "")
    input:SetTextColor(unpack(Theme.colors.textPrimary))

    if options.hint then
        row.hint = Theme.CreateText(row, Theme.sizes.columnHeader, "textMuted")
        row.hint:SetPoint("RIGHT", edge, "LEFT", -10, 0)
        row.hint:SetJustifyH("RIGHT")
        row.hint:SetText(options.hint)
    end

    -- What the setting says right now, with the suffix put back on. Called on
    -- every refresh and after every refusal, so the field can never sit
    -- showing a number the addon did not accept.
    local function Show()
        local value = options.get and options.get()

        input:SetText(tostring(value or 0) .. (options.suffix or ""))
    end

    local function Commit()
        local typed = (input:GetText() or ""):gsub("%%", "")
        local value = tonumber(typed)

        if value == nil then
            Show()

            SYL:Print(
                options.label
                .. " needs a number. Left it at "
                .. tostring(options.get and options.get())
                .. (options.suffix or "")
                .. "."
            )

            return
        end

        if options.set and options.set(value) == false then
            Show()

            SYL:Print(
                options.refusal
                or (options.label
                    .. " could not be set to "
                    .. tostring(value)
                    .. ".")
            )

            return
        end

        Show()

        SYL.SettingsRows.Refresh()
    end

    FilterToNumbers(input)

    input:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)

    -- The one that matters more, and the one a field like this usually
    -- forgets. See the header.
    input:SetScript("OnEditFocusLost", Commit)

    input:SetScript("OnEscapePressed", function(self)
        Show()
        self:ClearFocus()
    end)

    if options.note then
        SYL.Tooltips.Attach(row, options.label, options.note)
    end

    row.input = input
    row.refreshValue = Show

    Show()

    table.insert(rows, row)

    return row
end

-- Draws one row and hands it back. `index` is its line inside the container,
-- the way every other row factory in this window numbers them.
function SettingsNumberRow.Create(parent, index, options)
    return Build(parent, index, options)
end

-- How tall a run of them is, so a tab stacks what comes next without
-- measuring a frame. One line each; there is no grid here, because a number
-- and its label need the whole width to stay readable.
function SettingsNumberRow.Height(count)
    return (count or 0) * ROW_HEIGHT
end
