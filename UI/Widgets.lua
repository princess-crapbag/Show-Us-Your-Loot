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

-- Where a window was left, so it opens there next time.
--
-- Sizes have been remembered since resizing shipped and positions never were,
-- so every window went back to the middle of the screen on every login. Aimee:
-- "i do want the addon to open wherever the user puts it on their screen and
-- remember the place."
--
-- The key comes off the frame rather than through the drag handler, because
-- MakeMovable is called before the window knows what it is called. RestoreSize
-- stamps it, and every window that persists anything already goes through it.
local function RememberPosition(frame)
    local key = frame.sylWindowKey

    if not key or not ShowUsYourLootDB then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)

    if not point then
        return
    end

    ShowUsYourLootDB.settings = ShowUsYourLootDB.settings or {}
    ShowUsYourLootDB.settings.windowPositions =
        ShowUsYourLootDB.settings.windowPositions or {}

    ShowUsYourLootDB.settings.windowPositions[key] = {
        point = point,
        relativePoint = relativePoint or point,
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

function Widgets.RestorePosition(frame, key)
    frame.sylWindowKey = key

    local positions = ShowUsYourLootDB
        and ShowUsYourLootDB.settings
        and ShowUsYourLootDB.settings.windowPositions

    local saved = positions and positions[key]

    if not saved or not saved.point then
        return false
    end

    -- Always relative to UIParent. Anything else would have to still exist,
    -- and a saved anchor to a window that has since been rebuilt is a window
    -- that opens nowhere.
    frame:ClearAllPoints()
    frame:SetPoint(
        saved.point, UIParent, saved.relativePoint or saved.point,
        saved.x or 0, saved.y or 0
    )

    -- A restored position is still the user's answer, so the auto-layout has
    -- to keep its hands off it — otherwise the first second window to open
    -- would slide it somewhere else and undo the whole point of saving it.
    --
    -- BOTH FLAGS, AND THE SECOND IS THE ONE THAT MATTERS. NoteUserMoved alone
    -- only tells WindowLayout to leave this window out of its arrangement; it
    -- does not stop WindowStack.PlaceOnce, which runs on the first Show of
    -- every session and re-centers anything without symlPlaced. So the whole
    -- feature did nothing: the position was read back correctly and then
    -- thrown away one frame later, and every window still opened dead center.
    if SYL.WindowStack then
        SYL.WindowStack.NoteUserMoved(frame)
    end

    -- Set directly rather than through a helper, because it means exactly
    -- "this window has already been put somewhere" and it has.
    frame.symlPlaced = true

    return true
end

local function StopDragging(frame)
    frame:StopMovingOrSizing()

    -- Moved by hand is the user's answer; the layout stops rearranging it.
    if SYL.WindowStack then
        SYL.WindowStack.NoteUserMoved(frame)
    end

    RememberPosition(frame)
end

-- THE TITLE BAR, AND NOTHING ELSE, IS A DRAG HANDLE.
--
-- Aimee, on the roster: you cannot get a name out of a table you cannot click
-- without moving the window, because the drag was registered on the whole
-- window and every pixel was a handle. Below this line is all controls — the
-- tab strip at -66, the filter bars, the column headers, the rows, and a
-- footer full of buttons.
Widgets.TITLE_BAR_HEIGHT = 56

-- Is the cursor inside the window's title bar right now?
--
-- NO EXTRA FRAME. The first two attempts put an invisible mouse-enabled child
-- over the title bar, and it took clicks from the controls underneath it: the
-- settings cog went dead, while the close button beside it kept working
-- because that one is a Blizzard template that sets its own frame level. Same
-- level as its siblings was not enough — this handle is created before all of
-- them, and the engine handed it the mouse anyway.
--
-- So nothing is drawn over anything. The drag stays registered on the window,
-- and OnDragStart simply refuses unless the press began in the title bar.
-- Every control keeps its own clicks because there is no longer anything
-- between them and the cursor.
--
-- GetCursorPosition returns screen coordinates in an unscaled space, so it has
-- to be divided by the frame's effective scale before it can be compared with
-- GetTop.
local function CursorInTitleBar(frame)
    local top = frame:GetTop()

    if not top or not GetCursorPosition then
        -- Cannot tell. Dragging is the friendlier failure: a window that
        -- refuses to move is worse than one that moves when it should not.
        return true
    end

    local scale = frame:GetEffectiveScale() or 1
    local _, cursorY = GetCursorPosition()

    if not cursorY or scale == 0 then
        return true
    end

    return (top - (cursorY / scale)) <= Widgets.TITLE_BAR_HEIGHT
end

function Widgets.MakeMovable(frame, titleBarOnly)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        if titleBarOnly and not CursorInTitleBar(self) then
            return
        end

        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", StopDragging)
end

-- AN ITEM NAME THAT IS NOT IN A LIST STILL DESERVES ITS TOOLTIP.
--
-- Aimee: "in the loot row the item has a tool tip but it the loot details
-- window it doesnt. can the item always have a tooltip?" The list rows get one
-- because the whole row is a Button; a heading is a FontString, and a
-- FontString cannot take mouse input at all — the same reason
-- Widgets.AttachNameCopy attaches to the row rather than to the text.
--
-- So this puts an invisible button over the text. §3z's trap applies and is
-- the reason for the caller-supplied bounds rather than SetAllPoints on the
-- parent: an invisible mouse-enabled child steals clicks from same-level
-- siblings, so it must cover the words and nothing else.
--
-- Shift-click links the item, the same as a row, because somebody reading a
-- drop is exactly who wants to paste it into chat.
function Widgets.MakeItemHoverable(parent, getLink)
    local hover = CreateFrame("Button", nil, parent)

    hover:RegisterForClicks("LeftButtonUp")

    hover:SetScript("OnEnter", function(self)
        local link = getLink()

        if not link then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)

    hover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    hover:SetScript("OnClick", function()
        local link = getLink()

        if link and IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(SYL.Utilities.NormalizeItemLink(link))
        end
    end)

    return hover
end

-- Right-click a row to copy the name it is showing.
--
-- `getName` is called on the click rather than closed over, because rows are
-- pooled and reused as a list scrolls — capturing the name at creation would
-- copy whoever happened to be in that slot when the window opened.
--
-- Attached to the ROW, not to the name's font string: a font string cannot
-- take mouse input at all, and the row is already the thing under the cursor.
-- Left-click behavior is untouched, so wherever a row already opens a detail
-- pane it still does.
--
-- Each caller decides the name form, because they differ and both are right:
-- the roster hands over the bare name its rows show and its "Alt of" box
-- expects, while the keys list hands over Name-Realm, which is how a keystone
-- is stored. The box is an EditBox either way, so trimming one to the other is
-- a drag inside a field that already has focus.
--
-- OnMouseUp rather than OnClick, so this attaches to a plain Frame as well as
-- to a Button. Most rows in this addon are Frames, and OnClick never fires on
-- one; the rows that ARE buttons register only for LeftButtonUp, so hooking
-- OnClick would have silently done nothing on every list.
function Widgets.AttachNameCopy(row, getName)
    row:EnableMouse(true)

    row:HookScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then
            return
        end

        local name = getName()

        if type(name) ~= "string" or name == "" then
            return
        end

        SYL.Links.ShowCopyText(name, name)
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
    -- Position rides along with size. Both are per-window preferences, both
    -- are keyed the same way, and every window that saves one wants the other
    -- — separating them only creates a window that remembers half of where it
    -- was. This also stamps the key the drag handler reads.
    Widgets.RestorePosition(frame, key)

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

        -- Positions as well, now that they are remembered. This command exists
        -- for a window dragged past the edge of the screen, and clearing only
        -- the size would center it for one session and put it back off the
        -- monitor at the next login — which is the failure it is meant to fix.
        ShowUsYourLootDB.settings.windowPositions = {}
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

    -- Title bar only. See MakeMovable.
    Widgets.MakeMovable(frame, true)

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
