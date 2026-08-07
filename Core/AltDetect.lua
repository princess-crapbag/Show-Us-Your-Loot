-- Core/AltDetect.lua
--
-- Reads guild notes and proposes which characters are alts of which mains.
--
-- Guilds have written this down for twenty years and never in the same way.
-- "Alt of Aimee", "Aimee's alt", "Main: Aimee", "(Aimee)", or just "Aimee".
-- The patterns below cover what people actually type, and anything not
-- recognised is left alone rather than guessed at.
--
-- NOTHING HERE APPLIES ITSELF.
--
-- The plan this came from had note parsing outrank inference and write
-- straight into the registry. That was wrong for one reason: a mapping
-- changes the due list *retroactively*, so a roster refresh could silently
-- re-rank who is owed loot because somebody edited a note. Scanning produces
-- proposals; an officer accepts them in one action. One keystroke either
-- way, and the numbers only ever move when a person asked them to.
--
-- Officer notes are read only when the player's rank can see them. Blizzard
-- returns "" rather than nil in that case, which Guild.lua already turns
-- into absent.

local SYL = _G.ShowUsYourLoot

local AltDetect = {}
SYL.AltDetect = AltDetect

-- WoW names are letters only, but not necessarily ASCII ones. The high byte
-- range keeps accented realms working; without it "Zoë" truncates to "Zo".
local NAME = "([%a\128-\255]+)"

-- Ordered. The first pattern that matches wins, so the explicit forms are
-- tried before the loose ones.
local PATTERNS = {
    { pattern = "alt%s+of%s+" .. NAME, explicit = true },
    { pattern = NAME .. "'s%s+alt", explicit = true },
    { pattern = NAME .. "s'%s+alt", explicit = true },
    { pattern = "main%s*[:%-]%s*" .. NAME, explicit = true },
    { pattern = "main%s+is%s+" .. NAME, explicit = true },
    { pattern = "alt%s*[:%-]%s*" .. NAME, explicit = true },
    { pattern = "^%(%s*" .. NAME .. "%s*%)$", explicit = false },
    { pattern = "^" .. NAME .. "%s+alt$", explicit = false },
    { pattern = "^" .. NAME .. "$", explicit = false },
}

-- Words that match the bare-name patterns but are never a person. Without
-- this, a note reading "alt" maps somebody to a guild member called Alt if
-- one happens to exist, and "bank" is a guild bank character in most guilds.
local NOT_A_NAME = {
    alt = true,
    alts = true,
    main = true,
    bank = true,
    banker = true,
    guild = true,
    inactive = true,
    trial = true,
    social = true,
    raider = true,
    officer = true,
    friend = true,
    mule = true,
}

local function LooksLikeAName(candidate)
    if type(candidate) ~= "string" or candidate == "" then
        return false
    end

    -- WoW caps names at 12 characters, but `#` counts bytes and an accented
    -- name spends two per letter. The bound is generous on purpose: it is
    -- here to reject sentences, not to validate names.
    if #candidate < 2 or #candidate > 24 then
        return false
    end

    return not NOT_A_NAME[candidate:lower()]
end

-- Returns the referenced name and whether the note said so explicitly.
function AltDetect.ParseNote(note)
    if type(note) ~= "string" or note == "" then
        return nil
    end

    local lowered = note:lower():gsub("^%s+", ""):gsub("%s+$", "")

    for _, entry in ipairs(PATTERNS) do
        local candidate = lowered:match(entry.pattern)

        if LooksLikeAName(candidate) then
            return candidate, entry.explicit
        end
    end

    return nil
end

-- Guild members are put in the registry whether or not they have ever been
-- in a raid, because a note can name somebody who has not. Without this,
-- mapping an alt to a main who only ever logs in to craft would fail.
function AltDetect.EnsureGuildMembers()
    local added = 0

    for guid, member in pairs(SYL.Guild.GetMembers()) do
        if guid then
            local existing = SYL.Players.Get(guid)

            SYL.Players.Ensure({
                guid = guid,
                name = member.shortName,
                fullName = member.name,
            })

            if not existing then
                added = added + 1
            end
        end
    end

    return added
end

-- Proposals, never applied. Each carries enough to be shown to a human and
-- accepted or ignored.
function AltDetect.Scan()
    AltDetect.EnsureGuildMembers()

    local proposals = {}

    for guid, member in pairs(SYL.Guild.GetMembers()) do
        local note = member.officerNote or member.publicNote
        local from = member.officerNote and "officer note" or "public note"

        local candidate, explicit = AltDetect.ParseNote(note)

        if candidate then
            local main = SYL.Guild.FindByShortName(candidate)

            -- The note has to name somebody actually in this guild. A main
            -- on another server or a name that is simply a word is not a
            -- mapping, it is a note.
            if main and main.guid and main.guid ~= guid then
                local player = SYL.Players.Get(guid)

                -- Already mapped the same way: nothing to propose.
                local settled = player
                    and player.mainGUID == main.guid

                if not settled then
                    table.insert(proposals, {
                        altGUID = guid,
                        altName = member.shortName,
                        mainGUID = main.guid,
                        mainName = main.shortName,

                        note = note,
                        noteSource = from,
                        explicit = explicit,

                        -- An existing mapping that disagrees is worth
                        -- showing differently: accepting it overwrites a
                        -- decision somebody already made.
                        replaces = player and player.mainGUID or nil,
                    })
                end
            end
        end
    end

    table.sort(proposals, function(left, right)
        if left.explicit ~= right.explicit then
            return left.explicit
        end

        return tostring(left.altName) < tostring(right.altName)
    end)

    return proposals
end

function AltDetect.Describe(proposal)
    local text = (proposal.altName or "?")
        .. " -> "
        .. (proposal.mainName or "?")

    if proposal.replaces then
        text = text .. " (replaces an existing mapping)"
    end

    if not proposal.explicit then
        text = text .. " (loose match)"
    end

    return text .. "  [" .. (proposal.noteSource or "note")
        .. ': "' .. tostring(proposal.note) .. '"]'
end

function AltDetect.Apply(proposal)
    if type(proposal) ~= "table" then
        return false, "Nothing to apply."
    end

    -- An officer accepting a proposal has made the same decision as typing
    -- it by hand, so it is stored as a manual mapping and a later note edit
    -- will not quietly undo it.
    return SYL.Players.SetMain(
        proposal.altGUID,
        proposal.mainGUID,
        SYL.Players.MANUAL
    )
end

function AltDetect.ApplyAll(proposals)
    local applied, failed = 0, 0

    for _, proposal in ipairs(proposals or {}) do
        local ok = AltDetect.Apply(proposal)

        if ok then
            applied = applied + 1
        else
            failed = failed + 1
        end
    end

    return applied, failed
end
