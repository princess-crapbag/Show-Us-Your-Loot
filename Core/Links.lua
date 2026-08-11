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

-- BUILT FROM YOUR OWN GUILD, not hardcoded. Both sites key a guild page on
-- region, realm and guild name, and the client knows all three — so the
-- default links land on this guild's own page rather than on a site's front
-- door, and they do it for anybody who installs the addon rather than only
-- for the person whose URLs were pasted in.
--
-- Falls back to the front page when the client has not answered yet, which is
-- the case at login before GUILD_ROSTER_UPDATE arrives, and for anybody not
-- in a guild at all.
local REGIONS = { "us", "kr", "eu", "tw", "cn" }

local function Region()
    if not GetCurrentRegion then
        return "us"
    end

    local ok, index = pcall(GetCurrentRegion)

    return (ok and REGIONS[index]) or "us"
end

-- THE REALM AND THE GUILD ARE ENCODED DIFFERENTLY, which cost a 404 before
-- Aimee pasted a working URL. The realm is slugified — lowercase, apostrophes
-- dropped, spaces to hyphens, so "Area 52" is area-52. The guild name is not:
-- it keeps its spaces and its capitals and is percent-encoded, so "Show Us
-- Your Kitties" is Show%20Us%20Your%20Kitties.
local function Slug(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local slug = name:gsub("'", ""):gsub("%s+", "-"):lower()

    return slug ~= "" and slug or nil
end

Links.Slug = Slug

-- Spaces only. A guild name can hold an apostrophe and both sites expect it
-- left alone rather than stripped, unlike a realm.
local function Encode(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    return (name:gsub("%s", "%%20"))
end

Links.Encode = Encode

local function GuildPaths()
    local guild = SYL.Guild and SYL.Guild.GetGuildName and SYL.Guild.GetGuildName()
    local realm = GetRealmName and GetRealmName()

    local guildName = Encode(guild)
    local realmSlug = Slug(realm)

    if not guildName or not realmSlug then
        return nil
    end

    return Region() .. "/" .. realmSlug .. "/" .. guildName
end

Links.GuildPaths = GuildPaths

-- Guild pages that cannot be worked out from region, realm and name.
--
-- Warcraft Logs keys a guild on a numeric id — /guild/reports-list/733227 —
-- and nothing in the client exposes that number, so it cannot be derived the
-- way the raider.io URL can. The only way to have it is to know it.
--
-- KEYED ON GUILD AND REALM, not hardcoded outright. Aimee's point was that a
-- link she sets on her own client does not reach the guildies she hands the
-- addon to, which is true and is what this fixes: everybody in Show Us Your
-- Kitties on Area 52 gets it without doing anything. Everybody NOT in that
-- guild gets the derived link instead, which is the reason it is a table
-- rather than a constant — this addon is on CurseForge, and a hardcoded URL
-- would point every stranger who installs it at somebody else's logs.
--
-- Adding a guild here is one line. Anyone who wants a different link for their
-- own guild still has /syl link add, which wins over all of this.
local KNOWN_GUILDS = {
    ["us/area-52/Show%20Us%20Your%20Kitties"] = {
        ["Warcraft Logs"] =
            "https://www.warcraftlogs.com/guild/reports-list/733227",
    },
}

local function Defaults()
    local path = GuildPaths()
    local known = path and KNOWN_GUILDS[path] or {}

    return {
        {
            label = "Warcraft Logs",
            url = known["Warcraft Logs"]
                or (path and ("https://www.warcraftlogs.com/guild/" .. path))
                or "https://www.warcraftlogs.com/",
        },
        {
            label = "Raider.IO",
            url = known["Raider.IO"]
                or (path and ("https://raider.io/guilds/" .. path))
                or "https://raider.io/",
        },
        { label = "Guild Discord", url = "" },
    }
end

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    if not ShowUsYourLootDB.links then
        ShowUsYourLootDB.links = {}

        for _, link in ipairs(Defaults()) do
            table.insert(ShowUsYourLootDB.links, {
                label = link.label,
                url = link.url,
            })
        end
    end

    return ShowUsYourLootDB.links
end

-- The front pages the first version shipped. A link still holding exactly one
-- of these was never edited by anybody, so replacing it with the guild page is
-- an upgrade rather than overwriting somebody's choice.
local FRONT_PAGES = {
    ["https://www.warcraftlogs.com/"] = "Warcraft Logs",
    ["https://raider.io/"] = "Raider.IO",
}

-- Run when the guild name becomes known, which is not at login — the roster
-- arrives on GUILD_ROSTER_UPDATE, and the links are seeded before that. So
-- this is a second pass rather than a migration: a migration would have to
-- guess a guild name it cannot have yet.
--
-- Only ever touches a URL that is still one of the shipped front pages, so a
-- link somebody typed is never changed. Returns how many moved.
function Links.RefreshDefaults()
    local store = Store()

    if not store or not GuildPaths() then
        return 0
    end

    local defaults = {}

    for _, link in ipairs(Defaults()) do
        defaults[link.label] = link.url
    end

    -- A URL is replaceable if it is still something this addon put there: the
    -- original front page, or the derived guild link from before a better one
    -- was known. Anything else was typed by a person and is left alone.
    --
    -- The derived form matters because it already shipped. Somebody who
    -- reloaded once is holding it, and without this they would keep it forever
    -- while a new install got the right link — the worst of both.
    local path = GuildPaths()

    local replaceable = {
        ["Warcraft Logs"] = {
            ["https://www.warcraftlogs.com/"] = true,
            [path and ("https://www.warcraftlogs.com/guild/" .. path) or ""] = true,
        },
        ["Raider.IO"] = {
            ["https://raider.io/"] = true,
            [path and ("https://raider.io/guilds/" .. path) or ""] = true,
        },
    }

    local changed = 0

    for _, link in ipairs(store) do
        local allowed = replaceable[link.label]
        local wanted = defaults[link.label]

        if allowed and wanted
            and allowed[link.url or ""]
            and link.url ~= wanted
        then
            link.url = wanted
            changed = changed + 1
        end
    end

    return changed
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

    -- Through the stack rather than Show(), so it is placed clear of the
    -- windows already open. It used to show itself, which meant it opened
    -- centered on top of the main window every time.
    if SYL.WindowStack then
        SYL.WindowStack.ShowWindow(copyFrame)
    else
        copyFrame:Show()
    end
end
