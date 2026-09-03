-- UI/SharedRosterPrompt.lua
--
-- "Somebody sent you a raid team." The screen that asks before it happens.
--
-- WHY THERE IS A QUESTION HERE AT ALL. There did not used to be. A roster
-- broadcast over the guild channel simply became your roster, and the only
-- sign was a caption saying who it came from. That works exactly as long as
-- one person in the guild is sharing, and Aimee's guild had two: her officer
-- turned the switch on, their nine names replaced her thirteen, and two
-- people nobody had put on any team -- Chippym and Quickadin -- appeared on
-- her board. Core/SharedRoster.lua carries the full account.
--
-- A caption is not consent. Nobody reads the small print under a list to
-- discover the list changed. So the roster waits, and this asks.
--
-- IT SHOWS THE NAMES, which is the whole reason it is a window rather than a
-- Blizzard popup with one line of text. "Accept a raid team from Pringlesbop?"
-- cannot be answered by anybody: the question is not whether you trust them,
-- it is whether the thing they are holding is the roster you want on your
-- screen. Nine names with their roles answers that in a glance, and it is the
-- same glance that would have caught this bug on the first night.
--
-- ONCE, NOT EVERY TIME. Saying yes trusts that sender from then on, so their
-- later changes arrive quietly; saying no is remembered too. A prompt that
-- came back at every login would teach somebody to dismiss it unread, which
-- is worse than no prompt at all.
--
-- Accept and Decline hold the whole job and touch no frame, for the reason
-- UI/ClearSeasonDialog.lua gives: a dialog that cannot be driven from a test
-- is a dialog that ships doing nothing, which has happened here before.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme
local Widgets = SYL.Widgets

local SharedRosterPrompt = {}
SYL.SharedRosterPrompt = SharedRosterPrompt

local WINDOW_WIDTH = 460
local PAD = 20

local HEADER_HEIGHT = 56
local BODY_HEIGHT = 104
local LIST_HEADING = 18
local NAME_ROW = 18
local FOOTER_HEIGHT = 52

-- Sixteen names, eight rows of two. A roster longer than that is real -- a
-- guild running two teams off one list -- and the window must not grow past
-- the screen to show it, so the rest is counted rather than drawn.
local MAX_SHOWN = 16
local COLUMNS = 2

local frame
local titleText
local bodyText
local listHeading
local nameRows = {}
local moreText

--------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------

-- The sender without the realm, because the realm is noise on a guild
-- channel: everybody on it is on your realm or connected to it, and
-- "Pringlesbop-Illidan" is harder to recognize than "Pringlesbop".
function SharedRosterPrompt.ShortName(source)
    return SYL.Utilities.ShortName(source)
end

function SharedRosterPrompt.Title(offer)
    return SharedRosterPrompt.ShortName(offer and offer.source)
        .. " sent you a raid team"
end

-- SHORT WORDS, the same rule the erase dialog follows. Somebody meeting this
-- for the first time has to understand what yes does before they press it,
-- and a sentence they read twice is a sentence they skip.
function SharedRosterPrompt.Describe(offer)
    local count = #((offer and offer.members) or {})
    local who = SharedRosterPrompt.ShortName(offer and offer.source)

    local replacing = SYL.SharedRoster.HasShared()
        and SYL.SharedRoster.AcceptedFrom()

    local text = SYL.Utilities.Count(count, "person", "people")
        .. ", with the roles they were given. Nothing has changed yet -- "
        .. "this is a question, not a notice.\n\n"
        .. "Say yes and their team shows on your roster beside anyone you "
        .. "have ticked yourself. It never touches your own ticks, and Clear "
        .. "shared removes it again whenever you like.\n\n"

    -- The case that is not obvious and is the one Aimee actually hit: there
    -- is already a roster on screen from somebody else. Saying yes here is
    -- not adding a roster, it is swapping which one you are looking at, and
    -- the sentence has to say so before the press rather than after.
    if replacing and replacing ~= (offer and offer.source) then
        text = text
            .. "You are already using "
            .. SharedRosterPrompt.ShortName(replacing)
            .. "'s roster. Saying yes puts "
            .. who
            .. "'s in its place -- one at a time, never both."
    else
        text = text
            .. "Say yes once and " .. who .. "'s later changes arrive "
            .. "quietly. Nobody else can replace it or empty it -- anyone "
            .. "else who starts sharing asks you here, the same way."
    end

    return text
end

-- Sorted the way the roster screen sorts: by name, because the reader is
-- looking for a name rather than reading a ranking.
function SharedRosterPrompt.Names(offer)
    local names = {}

    for _, member in ipairs((offer and offer.members) or {}) do
        table.insert(names, {
            name = member.name or member.key,
            class = member.class,
            role = member.raidRole,
        })
    end

    table.sort(names, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return names
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

function SharedRosterPrompt.Accept()
    local count, source = SYL.SharedRoster.AcceptOffer()

    if not source then
        return false
    end

    SYL:Print(
        "Using " .. SharedRosterPrompt.ShortName(source) .. "'s raid team of "
        .. count .. ". Anyone you marked yourself is untouched, and you can "
        .. "clear it from the roster screen."
    )

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
end

function SharedRosterPrompt.Decline()
    local source = SYL.SharedRoster.DeclineOffer()

    if not source then
        return false
    end

    -- Says that the no sticks. Otherwise the obvious fear is that the same
    -- box arrives every time they log in, which would make dismissing it the
    -- habit rather than the answer.
    SYL:Print(
        "Left " .. SharedRosterPrompt.ShortName(source)
        .. "'s raid team alone. They will not be asked about again."
    )

    return true
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function ListHeight(shown)
    local lines = math.ceil(shown / COLUMNS)

    return LIST_HEADING + math.max(lines, 1) * NAME_ROW
end

local function CreateNameRow(parent, index)
    local row = {}
    local column = (index - 1) % COLUMNS
    local line = math.floor((index - 1) / COLUMNS)
    local half = (WINDOW_WIDTH - PAD * 2) / COLUMNS

    row.name = Theme.CreateText(parent, Theme.sizes.rowSmall, "textPrimary")
    row.name:SetPoint(
        "TOPLEFT", PAD + column * half, -(line * NAME_ROW)
    )

    row.role = Theme.CreateText(parent, Theme.sizes.rowSmall, "textMuted")
    row.role:SetPoint(
        "TOPLEFT", PAD + column * half + half - 60, -(line * NAME_ROW)
    )
    row.role:SetWidth(48)
    row.role:SetJustifyH("RIGHT")

    return row
end

local function CreateWindow()
    if frame then
        return frame
    end

    frame = CreateFrame(
        "Frame",
        "ShowUsYourLootSharedRosterPrompt",
        UIParent,
        "BackdropTemplate"
    )

    frame:SetSize(WINDOW_WIDTH, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    Widgets.MakeMovable(frame)
    Theme.StyleWindow(frame)
    Widgets.CloseOnEscape(frame)

    SYL.WindowStack.KeepPlacement(frame)

    local mark = Theme.CreateAccentMark(frame)
    mark:SetPoint("TOPLEFT", 16, -18)

    titleText = Theme.CreateText(frame, Theme.sizes.title, "textPrimary")
    titleText:SetPoint("LEFT", mark, "RIGHT", 10, 0)

    local separator = Theme.CreateSeparator(frame)
    separator:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT - 8))
    separator:SetPoint("TOPRIGHT", -16, -(HEADER_HEIGHT - 8))

    bodyText = Theme.CreateText(frame, Theme.sizes.rowSmall, "textSecondary")
    bodyText:SetPoint("TOPLEFT", PAD, -HEADER_HEIGHT)
    bodyText:SetWidth(WINDOW_WIDTH - PAD * 2)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetWordWrap(true)

    listHeading = Theme.CreateText(frame, Theme.sizes.columnHeader, "textMuted")
    listHeading:SetPoint("TOPLEFT", PAD, -(HEADER_HEIGHT + BODY_HEIGHT))
    listHeading:SetText("THEIR TEAM")

    -- A holder for the name rows, so one SetPoint moves the whole block when
    -- the body above it is a different number of lines.
    local list = CreateFrame("Frame", nil, frame)

    list:SetPoint(
        "TOPLEFT", 0, -(HEADER_HEIGHT + BODY_HEIGHT + LIST_HEADING)
    )
    list:SetSize(WINDOW_WIDTH, NAME_ROW * (MAX_SHOWN / COLUMNS))

    for index = 1, MAX_SHOWN do
        nameRows[index] = CreateNameRow(list, index)
    end

    moreText = Theme.CreateText(list, Theme.sizes.columnHeader, "textMuted")
    moreText:SetPoint("TOPLEFT", PAD, 0)

    frame.list = list

    frame.accept = Theme.CreateButton(frame, 132, 22, "Use their roster",
        function()
            SharedRosterPrompt.Accept()
            frame:Hide()
        end)

    frame.decline = Theme.CreateButton(frame, 96, 22, "No thanks", function()
        SharedRosterPrompt.Decline()
        frame:Hide()
    end)

    frame.footer = Theme.CreateSeparator(frame)

    frame:Hide()

    return frame
end

--------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------

local function DrawNames(offer)
    local names = SharedRosterPrompt.Names(offer)
    local shown = math.min(#names, MAX_SHOWN)

    for index, row in ipairs(nameRows) do
        local entry = names[index]

        if entry and index <= MAX_SHOWN then
            row.name:SetText(entry.name)

            -- Class colored, the same as every other list of people in this
            -- addon. A roster is read by shape as much as by name.
            SYL.ClassColor.Set(row.name, entry.class, "textPrimary")

            row.role:SetText(
                entry.role and (SYL.RaidTeam.ROLE_LABELS[entry.role]
                    or entry.role) or ""
            )

            row.name:Show()
            row.role:Show()
        else
            row.name:Hide()
            row.role:Hide()
        end
    end

    local hidden = #names - shown

    if hidden > 0 then
        moreText:SetPoint(
            "TOPLEFT", PAD, -(math.ceil(shown / COLUMNS) * NAME_ROW)
        )
        moreText:SetText("and " .. hidden .. " more")
        moreText:Show()
    else
        moreText:Hide()
    end

    return shown, hidden
end

function SharedRosterPrompt.Show()
    local offer = SYL.SharedRoster.PendingOffer()

    if not offer then
        return nil
    end

    local dialog = CreateWindow()

    titleText:SetText(SharedRosterPrompt.Title(offer))
    bodyText:SetText(SharedRosterPrompt.Describe(offer))

    local shown, hidden = DrawNames(offer)

    -- The window is exactly as tall as what is in it. A fixed height would
    -- either clip a full roster or leave a field of empty ground under a
    -- short one, and the empty ground reads as something failing to load.
    local listHeight = ListHeight(shown) + (hidden > 0 and NAME_ROW or 0)
    local height = HEADER_HEIGHT + BODY_HEIGHT + listHeight + FOOTER_HEIGHT

    dialog:SetHeight(height)

    dialog.footer:SetPoint("BOTTOMLEFT", 16, FOOTER_HEIGHT - 18)
    dialog.footer:SetPoint("BOTTOMRIGHT", -16, FOOTER_HEIGHT - 18)

    dialog.decline:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    dialog.accept:SetPoint("RIGHT", dialog.decline, "LEFT", -8, 0)

    SYL.WindowStack.ShowWindow(dialog)

    return dialog
end

-- Closed without an answer -- Escape, or the corner X. The offer stays
-- pending rather than being treated as a no: dismissing a box is not
-- declining, and the roster screen has a line saying one is waiting.
function SharedRosterPrompt.IsShown()
    return frame ~= nil and frame:IsShown() and true or false
end
