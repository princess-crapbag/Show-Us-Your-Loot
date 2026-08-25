-- UI/Launchers.lua
--
-- The doors into the addon that are not our own minimap button: the Data
-- Broker feed that Titan Panel, Bazooka and ChocolateBar read, and the game's
-- own addon compartment -- the list behind the plus sign on the minimap.
--
-- Razorokk, running eighteen addons, on the ring button: "its not something
-- that can be seen with Titan Panel", "or the map 'Addons' tidy up list thats
-- built in to the game". Somebody who has already tidied every other addon
-- into one bar has said where they want their launchers, and an addon that
-- can only be reached from the minimap ring is asking them to make an
-- exception for it. Both of these cost nothing to offer, and together they
-- mean the ring button is a preference rather than the only way in.
--
-- Left opens the window and right lists the commands, which is what the
-- minimap button did when this was written.
--
-- IT NO LONGER MATCHES THE MINIMAP BUTTON, and that is deliberate rather than
-- drift. Aimee took the command menu off the ring button so the right button
-- could drag it: "they are all in the settings now". Nothing on a Titan bar
-- or in the compartment needs dragging, so nothing there had to give up its
-- right-click, and these two are where the menu still lives. If it should go
-- from here as well, UI/CommandMenu.lua loses its last caller and can go with
-- it.

local SYL = _G.ShowUsYourLoot
local CommandMenu = SYL.CommandMenu

local Launchers = {}
SYL.Launchers = Launchers

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local LABEL = "Show Us Your Loot"

local dataObject

local function Activate(frame, mouseButton)
    if mouseButton == "RightButton" then
        -- Anchored to whatever was clicked, which for a Titan Panel plugin is
        -- a bar button at the top of the screen and for the compartment is a
        -- row in its list. CommandMenu picks the corner that keeps the menu
        -- on screen from there.
        CommandMenu.Toggle(frame or Minimap)

        return
    end

    CommandMenu.Close()

    SYL:OpenMainWindow()
end

local function Describe(tooltip)
    tooltip:AddLine(LABEL)
    tooltip:AddLine("Left-click: open the loot window", 0.8, 0.8, 0.85)
    tooltip:AddLine("Right-click: list all commands", 0.8, 0.8, 0.85)
end

-- REGISTERED AT LOGIN, NOT AT LOAD. LibDataBroker is not ours and is not
-- shipped here: it arrives inside whichever display addon the player runs, so
-- whether it exists before this file runs is alphabetical luck. By
-- PLAYER_LOGIN every addon has loaded, and the library announces objects
-- created after its displays started, so late works and early cannot.
--
-- Not bundled deliberately. Carrying a copy of a library only to publish one
-- launcher would put it in the game for the majority of players who have no
-- display to read it -- and if no display addon is installed, there is
-- nothing for the feed to appear in anyway.
function Launchers.Register()
    if dataObject then
        return
    end

    local libStub = _G.LibStub

    if not libStub or not libStub.GetLibrary then
        return
    end

    -- Both calls are wrapped: the library is another author's code and this
    -- is a convenience feature. A launcher that cannot be published is worth
    -- a debug line, never an error at somebody's login screen.
    local found, broker = pcall(
        libStub.GetLibrary,
        libStub,
        "LibDataBroker-1.1",
        true
    )

    if not found or not broker then
        SYL:DebugPrint("No LibDataBroker present, so no launcher published.")

        return
    end

    local published, object = pcall(broker.NewDataObject, broker, LABEL, {
        type = "launcher",
        label = LABEL,
        icon = ICON,
        OnClick = Activate,
        OnTooltipShow = Describe,
    })

    if not published or not object then
        SYL:DebugPrint("LibDataBroker refused the launcher: name in use.")

        return
    end

    dataObject = object

    SYL:DebugPrint("Launcher published to LibDataBroker.")
end

-- THE COMPARTMENT ENTRY. The .toc names these three functions as strings and
-- the game calls them by name, so globals is what they have to be. See the
-- AddonCompartmentFunc lines in ShowUsYourLoot.toc.
--
-- The arguments are read by type rather than by position on purpose: the
-- addon name, the mouse button and the button frame have not always been
-- passed in the same order, and a handler that counts arguments is one that
-- needs editing every time that changes.
local function ArgumentsOf(...)
    local frame, mouseButton

    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if type(value) == "table" and value.GetCenter then
            frame = frame or value
        elseif value == "LeftButton" or value == "RightButton" then
            mouseButton = mouseButton or value
        end
    end

    return frame, mouseButton
end

function _G.ShowUsYourLoot_OnAddonCompartmentClick(...)
    local frame, mouseButton = ArgumentsOf(...)

    Activate(frame, mouseButton)
end

function _G.ShowUsYourLoot_OnAddonCompartmentEnter(...)
    local frame = ArgumentsOf(...)

    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    Describe(GameTooltip)
    GameTooltip:Show()
end

function _G.ShowUsYourLoot_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
