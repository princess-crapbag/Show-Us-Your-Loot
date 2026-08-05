-- UI/MinimapButton.lua
--
-- Left-click opens the loot window, right-click lists every /syl command.
--
-- Draggable around the minimap ring, with the angle saved so it stays put
-- between sessions.

local SYL = _G.ShowUsYourLoot
local CommandMenu = SYL.CommandMenu

local MinimapButton = {}
SYL.MinimapButton = MinimapButton

local DEFAULT_ANGLE = 214
local RING_RADIUS = 80

local button

local function GetSavedAngle()
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings

    if settings and type(settings.minimapAngle) == "number" then
        return settings.minimapAngle
    end

    return DEFAULT_ANGLE
end

local function SaveAngle(angle)
    if ShowUsYourLootDB and ShowUsYourLootDB.settings then
        ShowUsYourLootDB.settings.minimapAngle = angle
    end
end

local function PlaceAtAngle(angle)
    local radians = math.rad(angle)

    button:ClearAllPoints()
    button:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(radians) * RING_RADIUS,
        math.sin(radians) * RING_RADIUS
    )
end

-- Follows the cursor around the ring rather than moving freely, so the button
-- always sits against the minimap edge.
local function OnDragUpdate()
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()

    if not centerX then
        return
    end

    local angle = math.deg(
        math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)
    )

    PlaceAtAngle(angle)
    SaveAngle(angle)
end

local function BuildTextures()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", -1, 1)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Drawn after the icon so the ring sits on top of it, which is how
    -- Blizzard's own minimap buttons are layered.
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(53, 53)
    button.border:SetPoint("TOPLEFT")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
end

local function ShowTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Show Us Your Loot")

    GameTooltip:AddLine("Left-click: open the loot window", 0.8, 0.8, 0.85)
    GameTooltip:AddLine("Right-click: list all commands", 0.8, 0.8, 0.85)
    GameTooltip:AddLine("Drag: move around the minimap", 0.55, 0.55, 0.6)

    GameTooltip:Show()
end

function MinimapButton.Create()
    if button then
        return button
    end

    button = CreateFrame("Button", "ShowUsYourLootMinimapButton", Minimap)

    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    BuildTextures()
    PlaceAtAngle(GetSavedAngle())

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            CommandMenu.Toggle(self)
            return
        end

        CommandMenu.Close()

        SYL:OpenMainWindow()
    end)

    button:SetScript("OnDragStart", function(self)
        CommandMenu.Close()

        self:SetScript("OnUpdate", OnDragUpdate)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", ShowTooltip)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

function MinimapButton.SetShown(shown)
    local created = MinimapButton.Create()

    if shown then
        created:Show()
    else
        created:Hide()
    end
end
