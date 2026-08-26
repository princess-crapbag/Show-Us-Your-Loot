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
-- ANY CLICK OPENS THE LOOT WINDOW, and there is nothing else to learn. These
-- doors briefly listed every /syl command on a right-click, because the
-- minimap button did; when Aimee took that off the ring button -- "they are
-- all in the settings now" -- these were the last two callers of the menu, and
-- keeping it alive here would have meant a feature reachable only from Titan
-- Panel and a compartment list. So it went, and UI/CommandMenu.lua went with
-- it. The Tools tab in Settings is where the commands live.

local SYL = _G.ShowUsYourLoot

local Launchers = {}
SYL.Launchers = Launchers

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local LABEL = "Show Us Your Loot"

local dataObject

-- The mouse button is read and then ignored, which is deliberate: it costs
-- nothing here and it means a display addon that only ever sends left clicks
-- and one that reports both behave identically.
local function Activate()
    SYL:OpenMainWindow()
end

local function Describe(tooltip)
    tooltip:AddLine(LABEL)
    tooltip:AddLine("Click: open the loot window", 0.8, 0.8, 0.85)
    tooltip:AddLine("Commands live on the Tools tab", 0.55, 0.55, 0.6)
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
-- Only the hover needs an argument, and it needs the row's frame to anchor a
-- tooltip to. Picked out by type rather than by position on purpose: the addon
-- name, the mouse button and the button frame have not always been passed in
-- the same order, and a handler that counts arguments is one that needs
-- editing every time that changes.
local function FrameIn(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if type(value) == "table" and value.GetCenter then
            return value
        end
    end

    return nil
end

function _G.ShowUsYourLoot_OnAddonCompartmentClick()
    Activate()
end

function _G.ShowUsYourLoot_OnAddonCompartmentEnter(...)
    local frame = FrameIn(...)

    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    Describe(GameTooltip)
    GameTooltip:Show()
end

function _G.ShowUsYourLoot_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
