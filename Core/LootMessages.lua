-- Core/LootMessages.lua
--
-- Reading a loot line without knowing the language.
--
-- LootCapture used to match the literal English "receives loot:", so on any
-- other client nothing matched and every record in the database was filed
-- under one fabricated player called "Unknown" — not a few records, all of
-- them, and silently. A German guild would have installed this, raided a full
-- tier and found a due list with one name on it.
--
-- The client already knows the sentence in its own language: LOOT_ITEM_SELF
-- and friends are the same format strings Blizzard prints with. Turning those
-- into patterns means the parser is correct in every locale, including the
-- ones that put the item before the recipient — a hand-written pattern could
-- not be right in all of them even if somebody translated it.
--
-- Split out of LootCapture because it is a different job: this file turns a
-- sentence into a name, and knows nothing about seasons, records or storage.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local LootMessages = {}
SYL.LootMessages = LootMessages

local STRING_SPECIFIER = "\1"
local NUMBER_SPECIFIER = "\2"
local PLAYER_SPECIFIER = "\3"

-- Blizzard's grammar directives, which the client resolves before the line
-- reaches chat and which therefore never appear in it.
--
--   |1을;를;        Korean, picks a particle to suit the preceding word
--   |4item:items;   English, picks singular or plural — one terminator, and
--                   the alternatives separated by a colon rather than a
--                   second semicolon like |1
--   |2...;          a second-form variant
--   |3-1(...)       Russian, declines a word into a grammatical case
--
-- Which alternative the client picked is not predictable from here, so each
-- directive becomes a wildcard. Left in place they are literal text matching
-- nothing, which is how the Korean and Russian clients would have gone on
-- filing every record under a fabricated player even after the English was
-- taken out.
local function StripGrammarDirectives(text)
    text = text:gsub("|3%-?%d*%b()", STRING_SPECIFIER)
    text = text:gsub("|1[^;]*;[^;]*;", STRING_SPECIFIER)
    text = text:gsub("|4[^;]*;", STRING_SPECIFIER)
    text = text:gsub("|2[^;]*;", STRING_SPECIFIER)

    return text
end

-- Turns "%s receives loot: %s." into a pattern that captures the recipient
-- and ignores the rest. The item is pulled out separately by its link, so
-- only the player is worth capturing; everything else becomes a wildcard that
-- merely has to match.
--
-- playerArgument is which of the format's arguments is the player name, or
-- nil for the "You receive" phrasings where the recipient is implied. It is
-- the argument number rather than the capture number, so a locale that writes
-- "%2$s" first still resolves to the right one.
local function BuildPattern(formatString, playerArgument)
    if type(formatString) ~= "string" or formatString == "" then
        return nil
    end

    local argument = 0
    local playerCapture

    -- Replace the specifiers before escaping, so the escaping does not have
    -- to reason about "%1$s" after its dollar sign has been made literal.
    local marked = formatString:gsub("%%(%d?)%$?([sd])",
        function(position, kind)
            argument = argument + 1

            local index = tonumber(position) or argument

            if index == playerArgument then
                playerCapture = true

                return PLAYER_SPECIFIER
            end

            return kind == "d" and NUMBER_SPECIFIER or STRING_SPECIFIER
        end
    )

    -- A format that never mentions the argument we were promised cannot be
    -- read for it. Better no pattern than one that captures something else.
    if playerArgument and not playerCapture then
        return nil
    end

    marked = StripGrammarDirectives(marked)

    local escaped = marked:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")

    -- Only the player is captured; the item and any count are matched and
    -- thrown away. Deliberately lazy: a recipient name never contains the
    -- literal that follows it, and greedy matching would let an item name
    -- containing the same words swallow the boundary.
    local pattern = escaped
        :gsub(PLAYER_SPECIFIER, "(.-)")
        :gsub(STRING_SPECIFIER, ".-")
        :gsub(NUMBER_SPECIFIER, "%%d+")

    return "^" .. pattern
end

-- Each entry is a global string's name rather than the string itself, because
-- some of these do not exist on every client and asking for a missing global
-- is nil rather than an error.
--
-- ORDER MATTERS, AND NOT THE WAY IT LOOKS. The "self" phrasings are tried
-- LAST. In English "You receive loot: %s." opens with a literal no other line
-- shares, so the order is invisible. In Korean the self string is
-- "%s|1을;를; 획득했습니다." — it opens with the item, so its pattern begins
-- with a wildcard and matches another raider's line just as happily. Checking
-- self first would have credited the entire guild's loot to whoever ran the
-- addon: not a missing record, an actively false one, and only on the clients
-- nobody testing this speaks.
--
-- The "other" phrasings always carry a recipient and the literal around it,
-- so they are the discriminating test and go first.
local SELF_FORMATS = {
    "LOOT_ITEM_SELF",
    "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
}

local OTHER_FORMATS = {
    "LOOT_ITEM",
    "LOOT_ITEM_MULTIPLE",
    "LOOT_ITEM_PUSHED",
    "LOOT_ITEM_PUSHED_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL",
    "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
}

-- Crafting prints down the same channel and has to be told apart, because a
-- crafter making other people's gear is not a crafter receiving gear. Matched
-- against the client's own string so the answer is decided in the locale that
-- produced the line and never re-derived from English afterwards.
local CREATED_FORMATS = {
    "LOOT_ITEM_CREATED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE",
}

local selfPatterns, otherPatterns, createdPatterns

-- Compiled once on first use rather than at load, because the global strings
-- are set up by the client and this file has no guarantee of running after
-- that.
local function CompilePatterns()
    if selfPatterns then
        return
    end

    selfPatterns, otherPatterns, createdPatterns = {}, {}, {}

    local function compile(names, into, playerArgument)
        for _, name in ipairs(names) do
            local pattern = BuildPattern(_G[name], playerArgument)

            if pattern then
                table.insert(into, pattern)
            end
        end
    end

    compile(SELF_FORMATS, selfPatterns, nil)
    compile(OTHER_FORMATS, otherPatterns, 1)
    compile(CREATED_FORMATS, createdPatterns, nil)
end

local function MatchesAny(message, patterns)
    for _, pattern in ipairs(patterns) do
        if message:find(pattern) then
            return true
        end
    end

    return false
end

-- Whether this line is the player making something rather than receiving it.
function LootMessages.WasCreated(message)
    if type(message) ~= "string" then
        return false
    end

    CompilePatterns()

    return MatchesAny(message, createdPatterns)
end

-- Whether this line came from a bonus roll rather than an ordinary pickup.
--
-- WHY IT IS WORTH KNOWING. A bonus roll is loot somebody received and it is
-- NOT loot the raid awarded them — there is no Need or Greed on it and nobody
-- passed for it, so it belongs in the feed and nowhere near the due score.
-- That part already worked, and by accident rather than by design: a bonus
-- roll arrives through chat capture and lands in `loot`, while the fairness
-- math reads `drops`, which is group loot only. What did not work was seeing
-- it — the line was indistinguishable from any other pickup, so it could not
-- be pointed at or filtered out.
--
-- Its own compiled set rather than a re-read of the four formats, because the
-- self and other phrasings have to keep their existing order for the reason
-- described above SELF_FORMATS, and a bonus-roll line is one or the other
-- before it is a bonus roll.
local BONUS_ROLL_FORMATS = {
    "LOOT_ITEM_BONUS_ROLL",
    "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
}

local bonusRollPatterns

function LootMessages.WasBonusRoll(message)
    if type(message) ~= "string" then
        return false
    end

    if not bonusRollPatterns then
        bonusRollPatterns = {}

        for _, name in ipairs(BONUS_ROLL_FORMATS) do
            local format = _G[name]

            if type(format) == "string" and format ~= "" then
                table.insert(bonusRollPatterns, BuildPattern(format))
            end
        end
    end

    return MatchesAny(message, bonusRollPatterns)
end

-- Who received the item, or nil when the line could not be read.
--
-- nil rather than "Unknown", so the caller can tell a sentence it failed to
-- parse from a player genuinely called that. A record with no recipient is
-- worse than no record: it becomes a phantom raider that every real one is
-- measured against.
function LootMessages.DetermineRecipient(message)
    if type(message) ~= "string" then
        return nil
    end

    CompilePatterns()

    -- Crafting first: it names no recipient and its verb is distinct, so it
    -- can be settled before anything has to be inferred.
    if MatchesAny(message, createdPatterns) then
        return Utilities.GetPlayerFullName()
    end

    -- Then the phrasings that carry a name. See the note above SELF_FORMATS
    -- for why these cannot be checked second.
    for _, pattern in ipairs(otherPatterns) do
        local recipient = message:match(pattern)

        if recipient and recipient ~= "" then
            return Utilities.NormalizePlayerName(recipient)
        end
    end

    if MatchesAny(message, selfPatterns) then
        return Utilities.GetPlayerFullName()
    end

    return nil
end

-- Exposed for the locale tests, which build patterns for clients this machine
-- does not have installed.
LootMessages.BuildPattern = BuildPattern
