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

-- The chosen window is remembered by NAME as well as by index, and the name
-- is what wins.
--
-- Chat window indices are positions, not identities. Delete window 2 and
-- everything below it shifts up, so a saved index of 3 now addresses what
-- used to be window 4 — and the addon starts writing into whichever window
-- happens to be sitting there. That reads as the setting not having stuck,
-- because from the outside it is indistinguishable: you chose "Loot" and the
-- messages are somewhere else.
--
-- Names are what the user actually picked and they move with the window.
-- The index stays as a fallback for a window with no name, and for anything
-- saved before this.
local function FindByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local total = NUM_CHAT_WINDOWS or 10

    for index = 1, total do
        local windowName = GetChatWindowInfo(index)

        if windowName == name and GetChatFrame(index) then
            return index
        end
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

    if not settings then
        return 1
    end

    -- Name first: it survives the windows being reordered underneath it.
    local byName = FindByName(settings.chatFrameName)

    if byName then
        return byName
    end

    return settings.chatFrameIndex or 1
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

    if not settings then
        return
    end

    settings.chatFrameIndex = index

    -- Stored alongside, so the choice can be found again after the windows
    -- have been rearranged. nil rather than "" when the window has no name,
    -- so the index fallback takes over cleanly.
    local name = GetChatWindowInfo(index)

    settings.chatFrameName =
        (type(name) == "string" and name ~= "") and name or nil
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
