-- Core/Links.lua
--
-- The handful of URLs a guild keeps pointing people at.
--
-- AN ADDON CANNOT OPEN A BROWSER, and it cannot write to the clipboard
-- either. Neither is a gap in this addon — the game exposes no API for
-- either, deliberately. What every addon with a Discord link actually does is
-- pop a box with the URL already selected so the user presses Ctrl-C, and
-- that is what ShowCopyBox is.
--
-- Three defaults are seeded on first run because an empty list teaches
-- nothing about what this is for. They are Aimee's own, and any of them can
-- be edited or removed.

local SYL = _G.ShowUsYourLoot

local Links = {}
SYL.Links = Links

local MAX_LINKS = 8

local DEFAULTS = {
    { label = "Warcraft Logs", url = "https://www.warcraftlogs.com/" },
    { label = "Raider.IO", url = "https://raider.io/" },
    { label = "Guild Discord", url = "" },
}

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    if not ShowUsYourLootDB.links then
        ShowUsYourLootDB.links = {}

        for _, link in ipairs(DEFAULTS) do
            table.insert(ShowUsYourLootDB.links, {
                label = link.label,
                url = link.url,
            })
        end
    end

    return ShowUsYourLootDB.links
end

function Links.List()
    return Store() or {}
end

function Links.Count()
    return #Links.List()
end

function Links.Add(label, url)
    local store = Store()

    if not store then
        return nil, "The database is not ready yet."
    end

    label = SYL.Utilities.Trim(label)
    url = SYL.Utilities.Trim(url)

    if not label or label == "" then
        return nil, "Give the link a name, for example: /syl link add Logs https://…"
    end

    if #store >= MAX_LINKS then
        return nil, "That is already " .. MAX_LINKS .. " links, which is plenty."
    end

    table.insert(store, { label = label, url = url or "" })

    return store[#store], "Added " .. label .. "."
end

function Links.Remove(label)
    local store = Store()

    if not store or type(label) ~= "string" then
        return false
    end

    local needle = label:lower()

    for index, link in ipairs(store) do
        if tostring(link.label):lower() == needle then
            table.remove(store, index)

            return true
        end
    end

    return false
end

-- The copy box. A read-only edit box with the text already selected, which is
-- the closest thing to a clipboard the game allows.
--
-- Built once and reused: creating a frame per click leaks one per click, and
-- this is a button somebody presses idly.
local copyFrame

local function BuildCopyFrame()
    -- "BackdropTemplate" is not optional: Theme.StyleWindow calls SetBackdrop,
    -- which has lived on BackdropTemplateMixin rather than on plain frames
    -- since 9.0. Without it, clicking a link throws instead of opening the box.
    local frame = CreateFrame(
        "Frame", "ShowUsYourLootLinkCopy", UIParent, "BackdropTemplate"
    )

    frame:SetSize(420, 110)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")

    SYL.Theme.StyleWindow(frame)
    SYL.Widgets.MakeMovable(frame)
    SYL.Widgets.CloseOnEscape(frame)

    frame.title = SYL.Theme.CreateText(frame, SYL.Theme.sizes.title, "textPrimary")
    frame.title:SetPoint("TOPLEFT", 16, -14)

    frame.hint = SYL.Theme.CreateText(frame, SYL.Theme.sizes.rowSmall, "textMuted")
    frame.hint:SetPoint("TOPLEFT", 16, -34)
    frame.hint:SetText("Press Ctrl-C to copy. Escape closes this.")

    local box = CreateFrame("EditBox", nil, frame)

    box:SetPoint("TOPLEFT", 16, -54)
    box:SetPoint("TOPRIGHT", -16, -54)
    box:SetHeight(22)
    box:SetAutoFocus(true)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)

    local background = SYL.Theme.CreateSolidTexture(box, "button", "BACKGROUND")
    background:SetAllPoints()

    box:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    -- Retyping the URL would only ever break it, so the text is put back
    -- whenever it changes and stays selected for the next Ctrl-C.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(frame.url or "")
            self:HighlightText()
        end
    end)

    frame.box = box

    local close = SYL.Theme.CreateButton(frame, 90, 24, "Close", function()
        frame:Hide()
    end)

    close:SetPoint("BOTTOMRIGHT", -16, 12)

    return frame
end

function Links.ShowCopyBox(link)
    if not link then
        return
    end

    copyFrame = copyFrame or BuildCopyFrame()

    copyFrame.url = link.url or ""
    copyFrame.title:SetText(link.label or "Link")

    copyFrame.box:SetText(copyFrame.url)
    copyFrame.box:HighlightText()
    copyFrame.box:SetFocus()

    if (link.url or "") == "" then
        copyFrame.hint:SetText(
            "This link has no address yet — /syl link add " .. tostring(link.label)
            .. " <url>"
        )
    else
        copyFrame.hint:SetText("Press Ctrl-C to copy. Escape closes this.")
    end

    copyFrame:Show()
end
