-- UI/KeyRequestList.lua
--
-- The right-hand pane of the Keys tab: people who have asked to run your key,
-- and what you told them.
--
-- THIS PANE IS THE REASON DISMISS IS SAFE. A popup you can close is only
-- acceptable if closing it cannot lose anything, so the durable list is built
-- first and the popup is the optional convenience on top. Dismiss hides a row
-- from the badge and leaves it here until the weekly reset.
--
-- Split from UI/KeysPanel.lua, which owns the key list and the asking side.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local KeyRequestList = {}
SYL.KeyRequestList = KeyRequestList

local PAD = 10
local ROW_HEIGHT = 46
local MAX_ROWS = 7

local STATUS_COLORS = {
    pending = "warning",
    approved = "accent",
    tentative = "textSecondary",
    denied = "textMuted",
}

function KeyRequestList.Create(parent, width, top)
    local pane = CreateFrame("Frame", nil, parent)

    pane:SetWidth(width)
    pane:SetPoint("TOPRIGHT", 0, -top)
    pane:SetPoint("BOTTOM", 0, 20)

    local back = Theme.CreateSolidTexture(pane, "rowAlt", "BACKGROUND")
    back:SetAllPoints()

    pane.width = width
    pane.rows = {}

    pane.heading = Theme.CreateText(pane, Theme.sizes.rowSmall, "textMuted")
    pane.heading:SetPoint("TOPLEFT", PAD, -10)
    pane.heading:SetText("REQUESTS TO YOU")

    pane.empty = Theme.CreateText(pane, Theme.sizes.rowSmall, "textMuted")
    pane.empty:SetPoint("TOPLEFT", PAD, -32)
    pane.empty:SetWidth(width - (PAD * 2))
    pane.empty:SetJustifyH("LEFT")
    pane.empty:SetWordWrap(true)

    return pane
end

local function Row(pane, index)
    local row = pane.rows[index]

    if row then
        return row
    end

    row = CreateFrame("Frame", nil, pane)

    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -(32 + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -PAD, -(32 + (index - 1) * ROW_HEIGHT))

    row.who = Theme.CreateText(row, Theme.sizes.rowSmall, "textPrimary")
    row.who:SetPoint("TOPLEFT", 0, 0)
    row.who:SetJustifyH("LEFT")

    row.status = Theme.CreateText(row, Theme.sizes.rowSmall, "textMuted")
    row.status:SetPoint("TOPRIGHT", 0, 0)
    row.status:SetJustifyH("RIGHT")

    -- Four buttons rather than a menu. The whole interaction is meant to take
    -- one click while somebody is standing at a summoning stone.
    local function Button(label, offset, onClick)
        local button = Theme.CreateButton(row, 52, 18, label, onClick)

        button:SetPoint("TOPLEFT", offset, -20)

        return button
    end

    row.approve = Button("Yes", 0, function()
        SYL.KeystoneRequests.Answer(row.sender, SYL.KeystoneRequests.STATUS.APPROVED)
        KeyRequestList.Refresh(pane)
    end)

    row.tentative = Button("Maybe", 56, function()
        SYL.KeystoneRequests.Answer(row.sender, SYL.KeystoneRequests.STATUS.TENTATIVE)
        KeyRequestList.Refresh(pane)
    end)

    row.deny = Button("No", 112, function()
        SYL.KeystoneRequests.Answer(row.sender, SYL.KeystoneRequests.STATUS.DENIED)
        KeyRequestList.Refresh(pane)
    end)

    -- Prefills rather than sends. The addon does not talk unless asked, and
    -- "asked" means the person typed the message, not that they pressed a
    -- button labelled with somebody else's name.
    row.whisper = Button("Whisper", 168, function()
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat("/w " .. tostring(row.sender) .. " ")
        end
    end)

    row.dismiss = Theme.CreateButton(row, 20, 18, "x", function()
        SYL.KeystoneRequests.Dismiss(row.sender)
        KeyRequestList.Refresh(pane)
    end)

    row.dismiss:SetPoint("TOPRIGHT", 0, -20)

    SYL.Tooltips.Attach(
        row.dismiss,
        "Hide this",
        "Takes it off the count without answering. It stays on this list until "
        .. "the weekly reset, so hiding it is never the same as losing it."
    )

    pane.rows[index] = row

    return row
end

function KeyRequestList.Refresh(pane)
    if not pane then
        return
    end

    local requests = SYL.KeystoneRequests.Incoming()

    -- The setting rather than the runtime flag, for the same reason KeysPanel
    -- reads Features: the runtime one is set at login, so switching the
    -- feature on mid-session left the panel insisting it was off.
    if not SYL.Features.IsEnabled("keyRequests") then
        pane.empty:SetText(
            "Key requests are switched off. Turn them on in Settings to let "
            .. "guildies ask to run your key, and to ask for theirs."
        )
        pane.empty:Show()

        for _, row in ipairs(pane.rows) do
            row:Hide()
        end

        return
    end

    if #requests == 0 then
        pane.empty:SetText(
            "Nobody has asked to run your key. When somebody does it appears "
            .. "here and in chat, and stays until the weekly reset."
        )
        pane.empty:Show()

        for _, row in ipairs(pane.rows) do
            row:Hide()
        end

        return
    end

    pane.empty:Hide()

    local shown = math.min(MAX_ROWS, #requests)

    for index = 1, shown do
        local request = requests[index]
        local row = Row(pane, index)

        row.sender = request.sender

        row.who:SetText(
            tostring(request.sender)
            .. "  "
            .. (SYL.KeystoneRequests.ROLE_LABELS[request.role] or "?")
        )

        row.status:SetText(
            SYL.KeystoneRequests.STATUS_LABELS[request.status] or "?"
        )

        Theme.SetTextColor(row.status, STATUS_COLORS[request.status] or "textMuted")

        -- Answered rows keep their buttons: an answer is changeable right up
        -- until the key expires, and taking the buttons away would mean a
        -- misclick could only be fixed by whispering.
        row:Show()
    end

    for index = shown + 1, #pane.rows do
        pane.rows[index]:Hide()
    end

    if #requests > shown then
        pane.empty:SetText("+ " .. (#requests - shown) .. " more")
        pane.empty:ClearAllPoints()
        pane.empty:SetPoint("BOTTOMLEFT", PAD, 8)
        pane.empty:Show()
    end
end
