-- Core/Absences.lua
--
-- Who is out, and when.
--
-- Split from Core/RaidSchedule.lua, which had grown to two unrelated jobs in
-- one file: which weekdays this guild raids, and which people are away. The
-- second half kept growing — ids, authorship, guild sharing — and none of it
-- has anything to say about the first.
--
-- A PURE MOVE. Nothing here changed on the way across; the only edits are the
-- namespace and the store now being asked for rather than closed over.
--
-- THE STORE IS STILL RAIDSCHEDULE'S. Absences live in the same saved table as
-- the weekdays and the typed nights, because they are all the schedule, and
-- one place shaping that table is the reason it can never be half-built. This
-- file asks for it rather than reaching into the database itself.
--
-- The date helpers stay there too — Offset, TimestampOf, TodayKey are calendar
-- arithmetic, not absence logic, and half this addon uses them.

local SYL = _G.ShowUsYourLoot

local Absences = {}
SYL.Absences = Absences

local function Store()
    return SYL.RaidSchedule.Store()
end

-- from and to are inclusive day keys. A single day passes the same key twice,
-- which keeps every reader on one shape.
-- WHO SET IT, ALWAYS. An absence is the one thing this addon records that is
-- somebody's claim about another person rather than something the client
-- observed. Once these travel between guildies, "Talestra is out" with no
-- author is unanswerable — the person who knows it is wrong cannot tell who to
-- ask. Anybody may set one; everybody can see who did.
function Absences.Author()
    return (SYL.Keystone and SYL.Keystone.CharacterKey()) or "unknown"
end

-- AUTHOR-SCOPED, BECAUSE THESE TRAVEL. Each client is authoritative for the
-- absences it wrote and broadcasts that whole set, so an id only has to be
-- unique within one author — and prefixing the author makes it unique across
-- the guild without anybody sharing a counter.
local function NewAbsenceID(setBy)
    local store = Store()

    if not store then
        return nil
    end

    store.absenceSerial = (store.absenceSerial or 0) + 1

    return table.concat({
        tostring(setBy or "?"),
        tostring(time()),
        tostring(store.absenceSerial),
    }, "|")
end

function Absences.AddAbsence(name, fromKey, toKey, options)
    local store = Store()

    if not store or not name or name == "" or not fromKey then
        return nil
    end

    options = options or {}

    local setBy = options.setBy or Absences.Author()

    local absence = {
        id = options.id or NewAbsenceID(setBy),
        name = name,
        key = SYL.Players.GUIDForName(name) or nil,
        from = fromKey,
        to = toKey or fromKey,
        reason = options.reason,
        source = options.source or "manual",
        setBy = setBy,
        addedAt = options.addedAt or time(),
    }

    table.insert(store.absences, absence)

    return absence
end

function Absences.RemoveAbsence(index)
    local store = Store()

    if not store or not store.absences[index] then
        return false
    end

    table.remove(store.absences, index)

    return true
end

-- BY ID, NOT BY POSITION. Positions do not survive a merge: two clients
-- reconciling their lists agree about what an absence *is* and never about
-- where it sits in an array. The same lesson the drop records learned, which
-- is why every record in this addon carries one.
function Absences.RemoveAbsenceByID(id)
    local store = Store()

    if not store or not id then
        return false
    end

    for index, absence in ipairs(store.absences) do
        if absence.id == id then
            table.remove(store.absences, index)

            return true
        end
    end

    return false
end

-- Everything one person wrote, replaced in one go.
--
-- THE AUTHOR IS THE UNIT OF TRUTH. A client broadcasts every absence it wrote
-- and nothing else, so what arrives is the whole of that person's list and
-- anything of theirs missing from it has been removed. Merging entry by entry
-- would mean a deletion could only travel as a message of its own, and a
-- missed one would leave somebody marked out forever.
--
-- Only ever called with a sender the addon channel reported, so nobody can
-- replace a set that is not theirs.
function Absences.ReplaceAbsencesFrom(author, absences)
    local store = Store()

    if not store or not author or author == "" then
        return 0
    end

    local kept = {}

    for _, absence in ipairs(store.absences or {}) do
        if absence.setBy ~= author then
            table.insert(kept, absence)
        end
    end

    for _, absence in ipairs(absences or {}) do
        if absence.id and absence.name and absence.from then
            table.insert(kept, {
                id = absence.id,
                name = absence.name,
                key = SYL.Players.GUIDForName(absence.name) or nil,
                from = absence.from,
                to = absence.to or absence.from,
                reason = absence.reason,

                -- Stamped from the sender rather than from the payload, so a
                -- client cannot broadcast on somebody else's behalf.
                setBy = author,
                source = "shared",
                addedAt = time(),
            })
        end
    end

    store.absences = kept

    return #absences
end

-- Run at login, unconditionally, because the guard is the nil itself. An
-- absence written before ids existed is otherwise unreachable by anything that
-- reconciles, and would be re-sent forever as a new one.
function Absences.BackfillAbsenceIDs()
    local store = Store()

    if not store then
        return 0
    end

    local assigned = 0

    for index, absence in ipairs(store.absences or {}) do
        if type(absence) == "table" and not absence.id then
            absence.setBy = absence.setBy or Absences.Author()

            absence.id = table.concat({
                "legacy",
                tostring(absence.setBy),
                tostring(absence.addedAt or 0),
                tostring(index),
            }, "|")

            assigned = assigned + 1
        end
    end

    return assigned
end

function Absences.ClearExpired(beforeKey)
    local store = Store()

    if not store then
        return 0
    end

    beforeKey = beforeKey or TodayKey()

    local kept, dropped = {}, 0

    for _, absence in ipairs(store.absences) do
        if absence.to >= beforeKey then
            table.insert(kept, absence)
        else
            dropped = dropped + 1
        end
    end

    if dropped > 0 then
        store.absences = kept
    end

    return dropped
end

-- One person's absences covering one day, removed — but only the ones this
-- client wrote. Returns how many went and how many were left alone because
-- somebody else set them, so a caller can say which happened.
--
-- Somebody else's claim is theirs to retract: their client is authoritative
-- for it and would put it straight back on the next broadcast, so deleting it
-- here would look like it worked and then silently undo itself.
function Absences.RemoveAbsencesFor(name, dayKey)
    local store = Store()

    if not store or not name or name == "" or not dayKey then
        return 0, 0, nil
    end

    local wanted = tostring(name):lower()
    local author = Absences.Author()
    local removed, theirs, setByWhom = 0, 0, nil

    for index = #store.absences, 1, -1 do
        local absence = store.absences[index]

        if tostring(absence.name):lower() == wanted
            and absence.from <= dayKey and absence.to >= dayKey
        then
            if absence.setBy == author then
                table.remove(store.absences, index)

                removed = removed + 1
            else
                theirs = theirs + 1
                setByWhom = absence.setBy or setByWhom
            end
        end
    end

    return removed, theirs, setByWhom
end

-- Everyone out on a given day. String comparison is safe because the keys are
-- ISO and fixed width, which is the reason they are stored that way.
function Absences.WhoIsOut(dayKey)
    local store = Store()
    local out = {}

    if not store or not dayKey then
        return out
    end

    -- ONE ENTRY PER PERSON, NOT PER CHARACTER.
    --
    -- Two of somebody's characters marked out on the same night is one person
    -- who is not coming, and the calendar was listing both -- which reads as
    -- two people missing and is the arithmetic every attendance figure
    -- underneath it depends on.
    --
    -- Aimee: "my calendar is showing Saebie and Talestra out. they are the
    -- same person." Folding is the fix for the CLASS of bug; those two are
    -- not linked in her registry, so the addon has no way to know they are
    -- one person until they are. Once she maps one as the other's alt, this
    -- shows one name -- the main's.
    --
    -- The first one wins rather than the last, so a shared absence cannot
    -- displace one she set herself.
    local seen = {}

    for index, absence in ipairs(store.absences) do
        local person = absence.key
            and SYL.Players.ResolveToMain(absence.key)
            or absence.key
            or absence.name

        if absence.from <= dayKey and absence.to >= dayKey
            and not seen[person]
        then
            seen[person] = true

            local record = absence.key and SYL.Players.Get(person)

            table.insert(out, {
                index = index,
                id = absence.id,

                -- The person's name, which is the main's when the character
                -- marked out was an alt. Falls back to what was recorded for
                -- anybody the registry has never seen.
                name = (record and record.name) or absence.name,
                class = record and record.class,

                key = absence.key,
                reason = absence.reason,
                source = absence.source,

                -- Carried through so the calendar can name who said so. An
                -- absence somebody disagrees with is a conversation, and it
                -- needs a person on the other end of it.
                setBy = absence.setBy,

                from = absence.from,
                to = absence.to,
                multiDay = absence.from ~= absence.to,
            })
        end
    end

    table.sort(out, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return out
end

function Absences.AllAbsences()
    local store = Store()

    return (store and store.absences) or {}
end
