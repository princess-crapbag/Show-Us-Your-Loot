-- Core/DropIdentity.lua
--
-- Whether two records are the same drop, seen from two clients.
--
-- THE RECORD ID IS NOT COMPARABLE BETWEEN CLIENTS, and that cost Aimee a
-- doubled board.
--
-- Core/LootHistoryStore.lua builds an id as runID-encounterID-lootListID, and
-- runID is the *local* session's start timestamp. Two people in the same raid
-- start their sessions a second or two apart, so the same drop is
-- "1787100146-3470-1" here and "1787100144-3470-1" on the client that
-- broadcast it. Core/Sync.lua deduped on the id alone, so every drop a
-- guildmate sent was stored a second time — eleven duplicates from one raid
-- night, every one crediting the master looter, and none of them touched by a
-- correction made on the original. Her board read 560 where it should have
-- read 200, and the copies were hard to spot: they carry no item name, so the
-- loot list had nothing to show for them.
--
-- So there is a second key, made only of what both clients agree on. The
-- encounter and the loot index are Blizzard's and identical everywhere; the
-- winner and their roll pin it to one drop inside that encounter.
--
-- ITS OWN FILE, WITH NO DEPENDENCIES, on purpose. Core/Sync.lua needs it at
-- runtime and Core/Migrations.lua needs it to clean up what shipped before
-- it existed — and tools/test_migrations.py loads Migrations.lua on its own
-- against a stubbed addon table, which is worth keeping. Nothing here touches
-- the game.

local SYL = _G.ShowUsYourLoot

local DropIdentity = {}
SYL.DropIdentity = DropIdentity

-- lootListID repeats the next time the same boss is pulled — the comment on
-- BuildRecordID says so — so the key alone is not enough. Same boss, same loot
-- index, same winner, same roll, twelve hours apart is two drops and not one.
local WINDOW = 12 * 60 * 60

-- Synced records do not carry lootListID as a field of its own. They carry it
-- inside the id, which is the one part of an id that means the same thing on
-- both clients.
local function LootListIDOf(record)
    if record.lootListID then
        return tostring(record.lootListID)
    end

    return tostring(record.id or ""):match("^%d+%-%d+%-(%d+)$")
end

function DropIdentity.ContentKey(record)
    if type(record) ~= "table" or not record.encounterID then
        return nil
    end

    local lootListID = LootListIDOf(record)

    if not lootListID then
        return nil
    end

    -- A drop everyone passed on has no winner and no roll. It is still worth
    -- deduping, and the encounter plus the loot index carries it.
    return table.concat({
        tostring(record.encounterID),
        lootListID,
        tostring(record.winnerGUID or record.winnerName or "-"),
        tostring(record.winnerRoll or "-"),
    }, ":")
end

-- Answers false rather than true when it cannot tell. A missed duplicate is a
-- number that is too big and visibly wrong; a wrong match deletes somebody's
-- record, which is neither.
function DropIdentity.SameDrop(left, right)
    local key = DropIdentity.ContentKey(left)

    if not key or key ~= DropIdentity.ContentKey(right) then
        return false
    end

    local gap = math.abs((left.timestamp or 0) - (right.timestamp or 0))

    return gap <= WINDOW
end
