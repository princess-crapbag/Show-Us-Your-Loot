-- UI/Widgets.lua
--
-- Generic frame helpers that know nothing about loot. Row and column layout
-- lives in UI/Rows.lua.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local Widgets = {}
SYL.Widgets = Widgets

Widgets.ROW_HEIGHT = Theme.metrics.rowHeight
Widgets.ARCHIVE_ROW_HEIGHT = Theme.metrics.archiveRowHeight

function Widgets.MakeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        -- Moved by hand is the user's answer; the layout stops rearranging it.
        if SYL.WindowStack then
            SYL.WindowStack.NoteUserMoved(self)
        end
    end)
end

-- Where each column starts, from a list of { key, width, gap }.
--
-- Five windows each carry an identical `do ... end` block computing this, and
-- the header and rows both have to agree with it — the kind of duplication
-- that let the boss window ship with columns wider than its own frame. New
-- windows use this; the older copies can move over when next touched.
function Widgets.ColumnOffsets(columns)
    local offsets = {}
    local x = 0

    for _, column in ipairs(columns) do
        x = x + column.gap
        offsets[column.key] = x
        x = x + column.width
    end

    return offsets
end

-- Escape closes the window, the way every other panel in the game behaves.
--
-- UISpecialFrames is Blizzard's list of frames Escape may close, and it holds
-- global names rather than frames, so anything registered here has to have
-- been created with one. Every window in this addon has one.
--
-- Registering twice would close and reopen on a single press, so this checks
-- first. Windows are created once and kept, but that is a property of the
-- current code rather than a guarantee.
function Widgets.CloseOnEscape(frame)
    local name = frame and frame:GetName()

    if not name then
        return false
    end

    for _, existing in ipairs(UISpecialFrames) do
        if existing == name then
            return false
        end
    end

    table.insert(UISpecialFrames, name)

    return true
end

--------------------------------------------------------------------------
-- Resizing
--------------------------------------------------------------------------

-- The staircase of squares in the bottom right corner. Drawn from theme
-- textures rather than a Blizzard art file so it recolors with the palette
-- like everything else, instead of staying gray on a light scheme.
local function CreateGripMarks(grip)
    local size, gap = 3, 2

    for row = 1, 3 do
        for column = 1, 4 - row do
            local mark = Theme.CreateSolidTexture(grip, "textMuted", "OVERLAY")

            mark:SetSize(size, size)
            mark:SetPoint(
                "BOTTOMRIGHT",
                -((column - 1) * (size + gap)),
                (row - 1) * (size + gap)
            )
        end
    end
end

local function RememberSize(key, width, height)
    if not key or not ShowUsYourLootDB then
        return
    end

    ShowUsYourLootDB.settings = ShowUsYourLootDB.settings or {}
    ShowUsYourLootDB.settings.windowSizes =
        ShowUsYourLootDB.settings.windowSizes or {}

    ShowUsYourLootDB.settings.windowSizes[key] = {
        width = math.floor(width + 0.5),
        height = math.floor(height + 0.5),
    }
end

-- Default sizes, recorded so a window that has been dragged too big can be
-- put back. Keyed the same way the saved sizes are.
local defaultSizes = {}

-- The screen, in the same units frame sizes are measured in. UIParent already
-- accounts for UI scale, so this is what actually fits.
local function ScreenSize()
    local width = UIParent:GetWidth() or 1920
    local height = UIParent:GetHeight() or 1080

    return width, height
end

function Widgets.RestoreSize(frame, key)
    -- Called while the frame is still the size its window declared, so this
    -- is the one moment "default" is knowable. Both CreateListWindow and the
    -- main window come through here, so recording it here covers both.
    if key then
        defaultSizes[key] = {
            frame = frame,
            width = frame:GetWidth(),
            height = frame:GetHeight(),
        }
    end

    local sizes = ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.windowSizes

    local saved = sizes and sizes[key]

    if saved and saved.width and saved.height then
        -- Clamped on the way in as well as on the way out. A size saved
        -- before the bounds existed, or on a larger monitor, would otherwise
        -- restore a window bigger than the screen it is now on — and the
        -- grip that would fix it is off the bottom right corner.
        local maxWidth, maxHeight = ScreenSize()

        frame:SetSize(
            math.min(saved.width, maxWidth),
            math.min(saved.height, maxHeight)
        )

        return true
    end

    return false
end

-- Puts every resizable window back to the size its code declared and forgets
-- what was saved. Returns how many it changed.
function Widgets.ResetSizes()
    if ShowUsYourLootDB and ShowUsYourLootDB.settings then
        ShowUsYourLootDB.settings.windowSizes = {}
    end

    local reset = 0

    for _, entry in pairs(defaultSizes) do
        if entry.frame then
            entry.frame:SetSize(entry.width, entry.height)

            -- Centered as well, because a window big enough to need this is
            -- usually also somewhere unhelpful.
            entry.frame:ClearAllPoints()
            entry.frame:SetPoint("CENTER")
        end

        reset = reset + 1
    end

    return reset
end

-- Drag the bottom right corner to resize. config takes minWidth, minHeight,
-- an optional key to remember the size under, and onResize.
--
-- onResize fires while dragging, not only at the end, so a list can grow row
-- by row as the window does. Anything expensive belongs behind onStop.
function Widgets.MakeResizable(frame, config)
    config = config or {}

    local minWidth = config.minWidth or 400
    local minHeight = config.minHeight or 240

    frame:SetResizable(true)

    -- An upper bound as well as a lower one. Dragged past the screen edge,
    -- the grip goes with it: the corner you would grab to make the window
    -- smaller is the corner that is now off the monitor, and the only way
    -- back is a slash command. Capped at the screen so that cannot happen.
    local maxWidth, maxHeight = ScreenSize()

    -- SetResizeBounds replaced SetMinResize; still guarded, because a client
    -- that has neither would otherwise error at window creation and take the
    -- whole window with it. SetMinResize had no maximum, so old clients keep
    -- the old behavior.
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    elseif frame.SetMinResize then
        frame:SetMinResize(minWidth, minHeight)
    end

    local grip = CreateFrame("Button", nil, frame)

    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:EnableMouse(true)

    CreateGripMarks(grip)

    grip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()

        RememberSize(config.key, frame:GetWidth(), frame:GetHeight())

        if config.onStop then
            config.onStop()
        end
    end)

    if config.onResize then
        frame:SetScript("OnSizeChanged", function()
            config.onResize(frame:GetWidth(), frame:GetHeight())
        end)
    end

    frame.resizeGrip = grip

    return grip
end

-- How many rows of a given height fit between the header and the footer.
-- Clamped to the pool ceiling, since a window dragged to the height of the
-- screen must not build rows without bound.
function Widgets.RowsThatFit(height, listTop, rowHeight, footer, maxRows)
    local usable = height - listTop - (footer or 0)
    local fits = math.floor(usable / rowHeight)

    return math.max(1, math.min(maxRows or fits, fits))
end

-- A resizable window whose list grows and shrinks with it.
--
-- Every list window wants exactly the same thing — work out how many rows now
-- fit, and redraw only when that number actually changes — so the arithmetic
-- and the change check live here rather than three times over. onRows is
-- called with the new count, and only when it differs from the last one; a
-- drag fires OnSizeChanged continuously, and refreshing a list on every pixel
-- would be wasteful for no visible gain.
function Widgets.MakeResizableList(frame, config)
    local rowHeight = config.rowHeight or Widgets.ROW_HEIGHT
    local footer = config.footer or 0
    local minRows = config.minRows or 4

    local current

    return Widgets.MakeResizable(frame, {
        key = config.key,
        minWidth = config.minWidth,
        minHeight = config.listTop + minRows * rowHeight + footer,

        onResize = function(_, height)
            local fits = Widgets.RowsThatFit(
                height, config.listTop, rowHeight, footer, config.maxRows
            )

            if fits ~= current then
                current = fits
                config.onRows(fits)
            end
        end,
    })
end

-- `index` is the row's slot within the scroll child, counting from 1 — not
-- its position on screen. Those are the same thing only at offset 0.
--
-- Safe to call again on an existing row, which is what makes a scrolled list
-- possible: SetPoint adds an anchor rather than replacing one, so without the
-- clear a re-anchored row keeps every position it has ever held.
function Widgets.AnchorRow(row, index, height)
    local offset = -((index - 1) * height)

    row:ClearAllPoints()
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", -20, offset)
end

-- Alternating row shading, kept subtle so it reads as banding rather than as
-- a selected row.
function Widgets.AddRowBackgrounds(row, index)
    if index % 2 == 0 then
        row.stripe = Theme.CreateSolidTexture(row, "rowAlt", "BACKGROUND")
        row.stripe:SetAllPoints()
    end

    row.highlight = Theme.CreateSolidTexture(row, "rowHover", "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()
end

-- Keeps the row highlight lit while the pointer is over a child control, so
-- moving onto an inner button does not flicker the row off.
function Widgets.LinkHoverToRow(child, row)
    child:HookScript("OnEnter", function()
        row.highlight:Show()
    end)

    child:HookScript("OnLeave", function()
        row.highlight:Hide()
    end)
end

-- The frame, chrome and resize behavior every list window shares: a titled
-- panel with a summary line under it, a close button in the corner, and a
-- grip that grows the list.
--
-- Three windows had all of this copied out line for line, which is how the
-- boss window shipped with columns wider than its own frame — the copies had
-- drifted and nobody was comparing them. Adding a fourth list window is now
-- a call rather than a paste.
function Widgets.CreateListWindow(config)
    local frame = CreateFrame(
        "Frame", config.globalName, UIParent, "BackdropTemplate"
    )

    frame:SetSize(
        config.width,
        config.listTop + config.defaultRows * config.rowHeight + config.footer
    )

    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)

    Widgets.MakeResizableList(frame, {
        key = config.key,
        minWidth = config.width,
        listTop = config.listTop,
        rowHeight = config.rowHeight,
        footer = config.footer,
        maxRows = config.maxRows,
        onRows = config.onRows,
    })

    -- After the default size, so a remembered size wins, and after the
    -- resize hook, so restoring one fires the row recount.
    Widgets.RestoreSize(frame, config.key)

    local accentMark = Theme.CreateAccentMark(frame)
    accentMark:SetPoint("TOPLEFT", 16, -20)

    local title = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    title:SetPoint("LEFT", accentMark, "RIGHT", 8, 0)
    title:SetText(config.title)

    frame.summaryText =
        Theme.CreateText(frame, Theme.sizes.subtitle, "textSecondary")

    frame.summaryText:SetPoint("TOPLEFT", 27, -42)
    frame.summaryText:SetPoint("TOPRIGHT", -16, -42)

    local closeCorner = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeCorner:SetPoint("TOPRIGHT", -6, -6)

    Widgets.CloseOnEscape(frame)

    return frame
end
