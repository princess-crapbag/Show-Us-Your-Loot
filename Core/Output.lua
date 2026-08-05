-- Core/Output.lua
--
-- Where the addon's messages are written.
--
-- WoW's chat settings cannot filter addon output: those checkboxes filter
-- message types, and addon text is not a message type — it is written
-- straight into a frame. So the addon has to pick the frame itself, which is
-- what this does.
--
-- Everything the addon prints goes through here, so a single setting moves
-- all of it into a chat window of its own.

local SYL = _G.ShowUsYourLoot

local Output = {}
SYL.Output = Output

local function GetSettings()
    return ShowUsYourLootDB and ShowUsYourLootDB.settings
end

local function GetChatFrame(index)
    local frame = _G["ChatFrame" .. tostring(index)]

    -- A window the user has since deleted leaves a frame that can no longer
    -- take messages, so it is treated as gone.
    if type(frame) == "table" and type(frame.AddMessage) == "function" then
        return frame
    end

    return nil
end

-- Only windows that actually exist. Docked or undocked does not matter; a
-- deleted one reports no name.
function Output.GetWindows()
    local windows = {}
    local total = NUM_CHAT_WINDOWS or 10

    for index = 1, total do
        local name = GetChatWindowInfo(index)

        if type(name) == "string" and name ~= "" and GetChatFrame(index) then
            table.insert(windows, { index = index, name = name })
        end
    end

    return windows
end

function Output.GetWindowIndex()
    local settings = GetSettings()

    return (settings and settings.chatFrameIndex) or 1
end

function Output.GetWindowName()
    local index = Output.GetWindowIndex()
    local name = GetChatWindowInfo(index)

    if type(name) == "string" and name ~= "" then
        return name
    end

    return "General"
end

function Output.SetWindowIndex(index)
    local settings = GetSettings()

    if settings then
        settings.chatFrameIndex = index
    end
end

-- Advances to the next existing window, wrapping around. A cycle rather than
-- a list, because the set of windows changes as the user creates them.
function Output.CycleWindow()
    local windows = Output.GetWindows()

    if #windows == 0 then
        return Output.GetWindowName()
    end

    local current = Output.GetWindowIndex()
    local position = 1

    for index, window in ipairs(windows) do
        if window.index == current then
            position = index
            break
        end
    end

    local nextWindow = windows[(position % #windows) + 1]

    Output.SetWindowIndex(nextWindow.index)

    return nextWindow.name
end

function Output.GetFrame()
    return GetChatFrame(Output.GetWindowIndex())
        or DEFAULT_CHAT_FRAME
        or _G.ChatFrame1
end

function Output.Write(message)
    local frame = Output.GetFrame()

    if frame and frame.AddMessage then
        frame:AddMessage(message)

        return
    end

    -- Last resort, so a message is never simply lost.
    print(message)
end
