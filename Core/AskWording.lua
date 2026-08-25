-- Core/AskWording.lua
--
-- The sentence the Ask button types, and nothing else.
--
-- SPLIT OUT OF Core/LootAsk.lua because that file was doing two jobs and hit
-- the size rule saying so. The seam is real rather than arithmetic: this half
-- is a string somebody edits in a dialog and reads in a preview, the other
-- half is a watcher that decides whether there is anything to ask for. They
-- share nothing but the record.
--
-- THE DEFAULT IS AIMEE'S OWN, typed 2026-08-25 when she was asked to pick it,
-- and the square brackets are hers too. They are the better call: [item] is
-- already what an item link looks like in chat, so the token reads as the
-- thing it becomes rather than as syntax.
--
-- It does not mention transmog, and that is what makes this feature more than
-- a transmog feature. The same sentence works for a Need roll you lost, which
-- is the case people care most about.

local SYL = _G.ShowUsYourLoot

local AskWording = {}
SYL.AskWording = AskWording

AskWording.DEFAULT = "Hi there, could I have [item] if you don't need it?"

-- The chat edit box takes 255 characters and an item link is about 110 of
-- them before a word is typed, so a wording that looks short on screen can
-- still be cut off. Nothing here refuses a long one -- it is the player's
-- sentence -- but the dialog counts the COMPOSED line rather than the
-- template, because those two are never the same length.
AskWording.CHAT_LIMIT = 255

function AskWording.Get()
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings
    local saved = settings and settings.askWording

    if type(saved) == "string" and saved:match("%S") then
        return saved
    end

    return AskWording.DEFAULT
end

-- Returns ok and a message, the way the dialogs in UI/ expect. An empty
-- wording is refused rather than saved: the button would then open an empty
-- chat line, which reads as the addon being broken rather than as a setting.
function AskWording.Set(typed)
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings

    if not settings then
        return false, "Nothing to save to yet."
    end

    if type(typed) ~= "string" then
        typed = ""
    end

    typed = typed:gsub("^%s+", ""):gsub("%s+$", "")

    if typed == "" then
        return false, "Type the message first, or put the default back."
    end

    settings.askWording = typed

    return true
end

function AskWording.Reset()
    local settings = ShowUsYourLootDB and ShowUsYourLootDB.settings

    if settings then
        settings.askWording = AskWording.DEFAULT
    end

    return AskWording.DEFAULT
end

-- Replacements go through functions rather than through strings because gsub
-- reads % in a replacement as a capture reference, and an item link is
-- somebody else's data arriving from the server. A link carrying a stray
-- percent would otherwise throw inside a chat prefill, which is the worst
-- place in this addon to find out about it.
function AskWording.Compose(record, wording)
    wording = wording or AskWording.Get()

    if not record then
        return wording
    end

    local link = SYL.Utilities.NormalizeItemLink(record.itemLink)
        or record.itemName
        or "that item"

    -- The short name, not the realm-qualified one the whisper is addressed
    -- to. "Hi Sleepadin-Silvermoon" is not how anybody talks.
    local winner = record.winnerName or "there"

    local composed = wording:gsub("%[item%]", function()
        return link
    end)

    composed = composed:gsub("%[player%]", function()
        return winner
    end)

    return composed
end

-- The whole line as it will sit in the chat box, and how long it is. One
-- function so the preview under the box and the button that fills it can
-- never disagree about what is about to be typed.
function AskWording.Line(target, record, wording)
    local composed = AskWording.Compose(record, wording)
    local line = "/w " .. tostring(target or "them") .. " " .. composed

    return line, #line
end
