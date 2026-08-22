-- Core/CharacterMerge.lua
--
-- One character that changed enough for the client to call it a new one.
--
-- A FACTION CHANGE GIVES A CHARACTER A NEW GUID, which this addon did not
-- know. Aimee, working the test list: "the character Hinokamii faction changed
-- between raid nights 1 and 2 and now he shows up on the list twice. he is
-- only 1 character and the former doesnt exist to mark as an alt or anything.
-- additionally this is something that would happen often in other guilds so we
-- need a fix for it."
--
-- Her data has it exactly: Player-3676-0DF5E74E on the Tuesday and
-- Player-3676-0EEC1213 on the Thursday. Same realm, same name, same class, one
-- night of attendance each where the person raided both.
--
-- WHY THE EXISTING ALT SCREEN CANNOT REACH IT. Core/AltDetect.lua walks the
-- guild roster, and the pre-change character is not in the guild any more — it
-- does not exist at all. There is nothing to click, which is what she means by
-- "the former doesnt exist to mark as an alt".
--
-- THE TEST, AND WHY EACH PART OF IT IS THERE:
--
--   * Same realm. Taken from the GUID, which carries it, rather than from a
--     name that may or may not have one — see the note in HANDOFF about
--     recordedBy carrying a realm where roster members do not.
--   * Same name. Within one realm a name belongs to one character at a time.
--   * Same class. A faction change can move race, faction and appearance. It
--     cannot move class, so a name freed and retaken by somebody else is very
--     likely a different class and is not proposed.
--   * NEVER IN THE SAME RAID. This is the one that makes it safe. Two GUIDs
--     that appear in one session roster are two characters that existed at the
--     same moment, whatever else they share, and no faction change produces
--     that.
--
-- IT PROPOSES AND DOES NOT APPLY, which is the rule Core/AltDetect.lua's
-- header sets out and the reason is the same: folding two identities rewrites
-- attendance and the fairness board retroactively, so it happens when somebody
-- asks and not when a scan runs.
--
-- The fold itself is an ordinary alt mapping — the older character becomes an
-- alt of the newer — because that machinery already exists, already folds
-- history, and is already reversible from the roster screen. The direction
-- matters: fold the dead character into the living one, or her current
-- character becomes an alt of one that cannot be logged into.

local SYL = _G.ShowUsYourLoot

local CharacterMerge = {}
SYL.CharacterMerge = CharacterMerge

-- Player-<realmID>-<hex>. The realm is the part that tells two same-named
-- characters apart, and it is the only place a GUID carries it.
local function RealmOf(guid)
    if type(guid) ~= "string" then
        return nil
    end

    return guid:match("^Player%-(%d+)%-")
end

CharacterMerge.RealmOf = RealmOf

local function NameOf(player)
    local name = player.name or player.fullName

    if type(name) ~= "string" then
        return nil
    end

    return (name:match("^([^-]+)") or name):lower()
end

-- Every pair of GUIDs that were ever in one session roster together. Two
-- characters that existed at the same moment are two characters.
local function BuildCoPresence()
    local together = {}

    for _, session in ipairs(SYL.GetActiveRaids() or {}) do
        local present = {}

        for key, member in pairs(session.roster or {}) do
            table.insert(present, member.guid or key)
        end

        for _, left in ipairs(present) do
            for _, right in ipairs(present) do
                if left ~= right then
                    together[left .. "|" .. right] = true
                end
            end
        end
    end

    return together
end

local function SeenAt(player)
    return player.lastSeen or player.firstSeen or 0
end

-- Pairs of registry entries that look like one character before and after a
-- faction change. Newest first, because the newest is the one somebody is
-- looking at when they notice the duplicate.
function CharacterMerge.Scan()
    local registry = SYL.Players.GetRegistry()
    local together = BuildCoPresence()
    local byIdentity = {}

    for key, player in pairs(registry) do
        local guid = player.guid or key
        local realm = RealmOf(guid)
        local name = NameOf(player)

        -- A registry entry with no GUID predates GUIDs being stored and there
        -- is no realm to compare, so it is left alone rather than guessed at.
        if realm and name and player.class then
            local identity = table.concat(
                { realm, name, player.class }, "|"
            )

            byIdentity[identity] = byIdentity[identity] or {}

            table.insert(byIdentity[identity], {
                key = key,
                guid = guid,
                player = player,
            })
        end
    end

    local proposals = {}

    for _, group in pairs(byIdentity) do
        if #group > 1 then
            table.sort(group, function(left, right)
                return SeenAt(left.player) > SeenAt(right.player)
            end)

            local newest = group[1]

            for index = 2, #group do
                local older = group[index]

                local coPresent =
                    together[newest.guid .. "|" .. older.guid]
                    or together[older.guid .. "|" .. newest.guid]

                -- Already folded, either way round: nothing to propose.
                local settled = older.player.mainGUID == newest.guid
                    or newest.player.mainGUID == older.guid

                if not coPresent and not settled then
                    table.insert(proposals, {
                        oldKey = older.key,
                        oldGUID = older.guid,
                        oldName = older.player.name
                            or older.player.fullName,
                        oldSeenAt = SeenAt(older.player),

                        newKey = newest.key,
                        newGUID = newest.guid,
                        newName = newest.player.name
                            or newest.player.fullName,
                        newSeenAt = SeenAt(newest.player),

                        class = newest.player.class,
                    })
                end
            end
        end
    end

    table.sort(proposals, function(left, right)
        return left.newSeenAt > right.newSeenAt
    end)

    return proposals
end

-- The proposal involving this key, so a screen showing one of the two can
-- offer the merge without scanning for the pair itself.
function CharacterMerge.For(key)
    if not key then
        return nil
    end

    for _, proposal in ipairs(CharacterMerge.Scan()) do
        if proposal.oldKey == key or proposal.newKey == key then
            return proposal
        end
    end

    return nil
end

function CharacterMerge.Describe(proposal)
    if not proposal then
        return nil
    end

    return "Two of " .. tostring(proposal.newName or "this raider")
        .. " on the same realm, same class, never in a raid together. "
        .. "That is what a faction or race change looks like."
end

-- Folded old into new. Stored as a manual mapping, because somebody pressed a
-- button: a later guild-note scan must not quietly undo it.
function CharacterMerge.Apply(proposal)
    if type(proposal) ~= "table" then
        return false, "Nothing to merge."
    end

    return SYL.Players.SetMain(
        proposal.oldKey, proposal.newKey, SYL.Players.MANUAL
    )
end
