-- UI/MinimapButton.lua
--
-- LEFT-CLICK OPENS THE ADDON. RIGHT-CLICK DRAGS IT.
--
-- Right-click used to list every /syl command, and Aimee took it off: "they
-- are all in the settings now" -- the Tools tab draws 25 of them as buttons,
-- so the menu was a second door to a room that had grown its own. Freeing the
-- button gave the drag somewhere to live.
--
-- WHICH MEANS LEFT-CLICK NO LONGER DRAGS, and she said so before it was
-- built: "i think that is reasonable". It is the trade every minimap button
-- makes in one direction or the other, and this way round the click people
-- press twenty times a night cannot be turned into a drag by a shaky hand.
--
-- Dragged with the right button it goes anywhere on the screen. Dropped on or
-- near the minimap it snaps onto the ring and remembers the angle; dropped
-- anywhere else it stays exactly where it was put and remembers the spot.
-- Both survive a reload.

local SYL = _G.ShowUsYourLoot

local MinimapButton = {}
SYL.MinimapButton = MinimapButton

local DEFAULT_ANGLE = 214

-- How far outside the minimap's edge the middle of the button sits. Every
-- other addon's ring button uses about this, which is why they all line up.
local EDGE_GAP = 5

-- Let go within this many pixels of the ring and it snaps onto it. Wide
-- enough that dropping it "on the minimap" works without aiming, narrow
-- enough that a button parked beside the minimap stays parked.
local SNAP_BAND = 32

local button

local function Settings()
    return ShowUsYourLootDB and ShowUsYourLootDB.settings
end

-- MEASURED, NEVER ASSUMED. This was a hardcoded 80 -- half of a 160 pixel
-- minimap, plus a little -- and the retail minimap has not been 160 pixels
-- wide for years. So the button sat inside the circle, on top of the map,
-- which is what Razorokk reported after installing it: "Its IN the map
-- circle". The minimap is also resized in Edit Mode and squared off by
-- SexyMap, so the only radius that can be right is the one read at the
-- moment the button is placed.
local function RingRadii()
    return (Minimap:GetWidth() / 2) + EDGE_GAP,
        (Minimap:GetHeight() / 2) + EDGE_GAP
end

-- Addons that reshape the minimap answer this global so buttons can follow
-- it. Absent means the default round one.
local function IsRound()
    local shape = _G.GetMinimapShape and _G.GetMinimapShape()

    return shape == nil or shape == "ROUND"
end

-- Strata and level are re-applied because moving a frame between parents can
-- take them from the new parent instead of keeping the ones set here, and a
-- button that loses its level ends up underneath the minimap it sits on.
local function Reparent(parent)
    if button:GetParent() ~= parent then
        button:SetParent(parent)
    end

    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
end

local function PlaceAtAngle(angle)
    local radians = math.rad(angle)
    local halfWidth, halfHeight = RingRadii()
    local x, y = math.cos(radians), math.sin(radians)

    -- On a squared-off minimap the circle's corners are out in empty space,
    -- so push each point out until it meets the box instead. Dividing by the
    -- larger of the two puts it exactly on an edge, whatever the angle.
    if not IsRound() then
        local reach = math.max(math.abs(x), math.abs(y))

        if reach > 0 then
            x, y = x / reach, y / reach
        end
    end

    Reparent(Minimap)

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * halfWidth, y * halfHeight)
end

-- Offsets from the middle of the screen rather than from a corner, so a
-- change of resolution moves the button by half of the difference instead of
-- leaving it hanging off an edge.
local function ClampToScreen(x, y)
    local limitX = (UIParent:GetWidth() - button:GetWidth()) / 2
    local limitY = (UIParent:GetHeight() - button:GetHeight()) / 2

    return math.max(-limitX, math.min(x, limitX)),
        math.max(-limitY, math.min(y, limitY))
end

local function PlaceFree(x, y)
    Reparent(UIParent)

    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function SaveAngle(angle)
    local settings = Settings()

    if not settings then
        return
    end

    settings.minimapAngle = angle

    -- Clearing these is what says "back on the ring". One saved position at a
    -- time, so there is never a question of which of the two wins.
    settings.minimapFreeX = nil
    settings.minimapFreeY = nil
end

local function SaveFree(x, y)
    local settings = Settings()

    if not settings then
        return
    end

    settings.minimapFreeX = x
    settings.minimapFreeY = y
end

local function Restore()
    local settings = Settings()

    if settings
        and type(settings.minimapFreeX) == "number"
        and type(settings.minimapFreeY) == "number"
    then
        PlaceFree(ClampToScreen(settings.minimapFreeX, settings.minimapFreeY))

        return
    end

    local angle = DEFAULT_ANGLE

    if settings and type(settings.minimapAngle) == "number" then
        angle = settings.minimapAngle
    end

    PlaceAtAngle(angle)
end

-- Where the cursor is, in a given frame's own coordinates. GetCursorPosition
-- answers in screen pixels, and the minimap and UIParent can be at different
-- scales -- Edit Mode resizes the minimap cluster -- so the division has to
-- use the scale of whichever frame the answer is compared against.
local function CursorIn(frame)
    local scale = frame:GetEffectiveScale()
    local x, y = GetCursorPosition()

    return x / scale, y / scale
end

-- The button follows the cursor wherever it goes, and only near the minimap
-- does it jump onto the ring. Aimee, passing on the guild's feedback: it
-- "needs to be able to be drug around freely". It used to orbit the minimap
-- and nothing else, so somebody who wanted it somewhere else had one circle
-- to pick a point on and no way to say "over there".
local function OnDragUpdate()
    local centerX, centerY = Minimap:GetCenter()

    if not centerX then
        return
    end

    local cursorX, cursorY = CursorIn(Minimap)
    local offsetX, offsetY = cursorX - centerX, cursorY - centerY
    local halfWidth, halfHeight = RingRadii()
    local distance = math.sqrt(offsetX * offsetX + offsetY * offsetY)

    if distance <= math.max(halfWidth, halfHeight) + SNAP_BAND then
        local angle = math.deg(math.atan2(offsetY, offsetX))

        PlaceAtAngle(angle)
        SaveAngle(angle)

        return
    end

    local screenX, screenY = CursorIn(UIParent)
    local screenCenterX, screenCenterY = UIParent:GetCenter()
    local x, y = ClampToScreen(
        screenX - screenCenterX,
        screenY - screenCenterY
    )

    PlaceFree(x, y)
    SaveFree(x, y)
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
    GameTooltip:AddLine(
        "Right-click and drag: move it anywhere",
        0.8,
        0.8,
        0.85
    )
    GameTooltip:AddLine(
        "Drop it on the minimap to snap it to the ring",
        0.55,
        0.55,
        0.6
    )

    GameTooltip:Show()
end

function MinimapButton.Create()
    if button then
        return button
    end

    button = CreateFrame("Button", "ShowUsYourLootMinimapButton", Minimap)

    button:SetSize(31, 31)
    -- One button each. A right-click that does not move the mouse does
    -- nothing at all, which is the correct amount for a menu that no longer
    -- exists.
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("RightButton")
    button:SetMovable(true)
    button:SetClampedToScreen(true)

    BuildTextures()
    Restore()

    button:SetScript("OnClick", function()
        SYL:OpenMainWindow()
    end)

    button:SetScript("OnDragStart", function(self)
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

-- The way back for a button dropped where it cannot be seen or clicked --
-- behind the bags, under another addon's frame, in the corner of a screen
-- that has since changed resolution. Wired into /syl resetwindows, which
-- already has a button on the Tools tab, so this needs no control of its own.
function MinimapButton.ResetPosition()
    SaveAngle(DEFAULT_ANGLE)

    if button then
        PlaceAtAngle(DEFAULT_ANGLE)
    end
end

function MinimapButton.SetShown(shown)
    local created = MinimapButton.Create()

    if shown then
        created:Show()
    else
        created:Hide()
    end
end
