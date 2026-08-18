-- Core/Features.lua
--
-- Which parts of the addon are switched on.
--
-- Aimee's ask, in her words: "if people don't want things they can turn it
-- off." The shape is ElvUI's and RCLootCouncil's — a feature is a thing with
-- a name and a switch, not a setting buried among other settings.
--
-- WHAT A FEATURE IS, HERE. Something a guild could reasonably not want, that
-- costs something when it is on, and that the rest of the addon keeps working
-- without. That last clause is the test: if turning it off breaks a number
-- somewhere else, it is not a feature, it is a dependency.
--
-- The reviewers wanted five of these deleted outright. They are all still
-- here and default to on, because "some guilds do not want this" and "nobody
-- wants this" are different claims and only the first one was actually
-- argued. A toggle settles it either way without anybody losing anything.
--
-- OFF MEANS NOT BUILT, NOT HIDDEN. A disabled feature should cost nothing:
-- no frames created, no events registered, no commands in the menu. Building
-- something and hiding it is how a switched-off feature still spends memory
-- and still runs on every refresh. So the checks live at construction, and
-- the price of that is stated plainly below — a change takes a /reload.

local SYL = _G.ShowUsYourLoot

local Features = {}
SYL.Features = Features

-- Ordered, because this is also the order they appear in Settings.
--
-- `cost` is what the feature spends when it is on, in the user's terms rather
-- than in milliseconds. It is the tooltip on the row: it used to be a second
-- line under every label, which made the settings window taller than a
-- monitor once there were nine of these.
--
-- `short` is the same feature named for a tick in a three-column grid. `label`
-- stays the full name and is what the tooltip heading and the reload notice
-- say, so nothing is only ever known by its abbreviation.
Features.LIST = {
    {
        key = "raidBuffs",
        short = "Raid buffs",
        label = "Raid buff coverage",
        cost = "Reads your roster's classes when the roster window is open.",
    },
    {
        key = "raiderIO",
        short = "Mythic+ scores",
        label = "Mythic+ scores",
        cost = "Needs the Raider.IO addon. Adds a column to the players and "
            .. "roster windows.",
    },
    {
        key = "lootTables",
        short = "Boss loot tables",
        label = "Boss loot tables",
        cost = "Reads the Encounter Journal the first time you press Loot "
            .. "tables, which takes a moment.",
    },
    {
        key = "sync",
        short = "Officer sync",
        label = "Officer sync",
        cost = "The only feature that sends anything to other players. Off "
            .. "unless you turn it on.",
    },
    {
        key = "keystoneSharing",
        short = "Share keys",
        label = "Share Mythic+ keys with the guild",
        cost = "Tells your guild which key this character holds, and remembers "
            .. "theirs. Needs them to run the addon too. Off unless you turn "
            .. "it on.",
    },
    {
        key = "tradeAdvisor",
        short = "Trade advisor",
        label = "Trade window advisor",
        cost = "Opens a small window when you win something, listing who else "
            .. "rolled on it. Sends nothing to anyone.",
    },
    {
        key = "tradeTracking",
        short = "Follow trades",
        label = "Follow traded loot",
        cost = "Watches your own trades, and credits an item you traded away "
            .. "to whoever received it. Changes the score.",
    },
    {
        key = "keyRequests",
        short = "Ask for keys",
        label = "Ask for guild keystones",
        cost = "Lets you ask a guildie to run their key, and them to ask you. "
            .. "Sends a message to that one person. Off unless you turn it on.",
    },
    {
        key = "absenceSharing",
        short = "Share absences",
        label = "Share who is out with the guild",
        cost = "Sends the absences you have typed to your whole guild, and "
            .. "shows you theirs. Everyone can see who set each one. Off "
            .. "unless you turn it on.",
    },
    {
        key = "rosterSharing",
        short = "Share roster",
        label = "Share your raid team with the guild",
        cost = "Sends who you have marked onto the raid team, and the roles "
            .. "you gave them, to your whole guild. Off unless you turn it "
            .. "on. A roster somebody else shares arrives whether this is on "
            .. "or off — the switch is about sending — and anything you "
            .. "receive can be cleared from the roster screen.",
    },
    {
        key = "lockouts",
        short = "Dungeon lockouts",
        label = "Mythic 0 dungeon lockouts",
        cost = "Asks the server which dungeons this character is saved to, at "
            .. "login and after a dungeon. Sends nothing to anyone.",
    },
    {
        key = "developer",
        short = "Developer tools",
        label = "Developer tools",
        cost = "Adds /syl dev and the event inspector. For diagnosing the "
            .. "addon itself.",
    },
}

local DEFAULTS = {
    raidBuffs = true,
    raiderIO = true,
    lootTables = true,

    -- Matches syncEnabled's own default, which this replaces. It is the one
    -- thing here that talks to other people.
    sync = false,

    -- The second thing here that talks to other players, and the only one
    -- that talks outside your own group. Off for the same reason sync is.
    keystoneSharing = false,

    -- On, despite opening a window unasked, because the window IS the feature
    -- and it only ever appears on your own screen after your own win. It sends
    -- nothing, so the rule it might look like it breaks — the addon does not
    -- talk unless asked — is about chat and is untouched.
    tradeAdvisor = true,

    -- On, because it is a correctness fix and off is the wrong answer that
    -- shipped until now: a traded item credited the winner, who gave it away,
    -- and not the person wearing it. It is still a switch, because it moves
    -- points between two real people and a guild is entitled to say they would
    -- rather it did not.
    tradeTracking = true,

    -- Off, like everything else that sends a message to another player. It is
    -- also the only one that sends to a named person rather than to a channel.
    keyRequests = false,

    -- Off, like everything that talks — and this one talks about other people
    -- rather than about you, which is why it is its own switch rather than
    -- part of keystone sharing.
    absenceSharing = false,

    -- Off, like everything that talks. Unlike every other switch here it
    -- governs sending only — a roster somebody else shares is received either
    -- way — because the guildies this exists for are precisely the people who
    -- will never open this panel to find it. Core/RosterSync.lua argues it at
    -- length.
    rosterSharing = false,

    -- On. It reads one server response at login and sends nothing, and the
    -- grid is empty until a character has actually been played — so off would
    -- mostly mean "collect nothing, then have nothing to show later".
    lockouts = true,

    developer = false,
}

local function Store()
    if not ShowUsYourLootDB then
        return nil
    end

    ShowUsYourLootDB.features = ShowUsYourLootDB.features or {}

    return ShowUsYourLootDB.features
end

-- True unless the saved value says otherwise, so a feature added in a later
-- version arrives switched on rather than silently missing for everyone who
-- already has a saved table.
function Features.IsEnabled(key)
    local store = Store()

    if not store then
        return DEFAULTS[key] ~= false
    end

    local saved = store[key]

    if saved == nil then
        return DEFAULTS[key] ~= false
    end

    return saved == true
end

function Features.SetEnabled(key, enabled)
    local store = Store()

    if not store then
        return
    end

    store[key] = enabled and true or false
end

-- Returns the new state, so the caller can report it without asking again.
function Features.Toggle(key)
    local enabled = not Features.IsEnabled(key)

    Features.SetEnabled(key, enabled)

    return enabled
end

function Features.Get(key)
    for _, feature in ipairs(Features.LIST) do
        if feature.key == key then
            return feature
        end
    end

    return nil
end

-- Everything switched on and off is read once, at load, by the file that owns
-- it. Changing one afterwards therefore does nothing until the UI is rebuilt,
-- and pretending otherwise would mean a half-registered feature — a window
-- that exists with no command, or an event handler with no window.
--
-- So the toggle says so, once, rather than the addon quietly disagreeing with
-- its own settings screen.
function Features.AnnounceReloadNeeded(feature, enabled)
    SYL:Print(
        (feature.label or feature.key)
        .. (enabled and " is on." or " is off.")
        .. " Type /reload to apply it."
    )
end
