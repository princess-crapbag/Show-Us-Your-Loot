-- UI/NightFigures.lua
--
-- The four figures on the raid-night pane, and the names behind each of them.
--
-- WHY FOUR, WHEN THERE WERE EIGHT. Aimee read the eight one at a time and
-- doubted half: "lets only track and show the info that makes sense and is
-- useful to a guild or raid or even a player." An audit agreed with her on
-- every one she named and found more. Two were cut, four were wrong, and the
-- thing that was actually missing was names.
--
-- WHAT WENT, AND WHY:
--
--   "N% of pulls killed" was figure one's two numbers divided. It could not
--   say anything figure one did not, and it read backwards -- 50% on the
--   night they cleared five bosses, 17% on the night they killed three.
--
--   "N drops per raider" was a mean over a distribution that is never even,
--   and on her data it was not even a mean over the right set.
--
--   "Xh YYm in the instance" was neither the instance nor, on a multi-session
--   night, the whole evening. It has moved into the subheading, where it can
--   say what it actually measures.
--
-- WHAT THE FIGURES CANNOT DO IS NAME ANYBODY, which was the real gap. The
-- pane could name exactly one kind of person: the ones who did not come.
-- Every argument an officer settles is about names. So each figure carries a
-- hover, and the hovers are most of this file.
--
-- CLASS COLOR IN A TOOLTIP IS AN ESCAPE CODE, not SetTextColor -- a tooltip
-- line is a string. UI/ClassColor.lua's Name does it and falls back to a
-- plain name rather than half a sequence.

local SYL = _G.ShowUsYourLoot

local NightFigures = {}
SYL.NightFigures = NightFigures

-- How many names to list before saying "and N more". A tooltip that runs off
-- the bottom of the screen has stopped being one.
local NAME_LIMIT = 24

--------------------------------------------------------------------------
-- Shared bits
--------------------------------------------------------------------------

local function Names(people)
    local shown, extra = {}, 0

    for _, person in ipairs(people) do
        if #shown < NAME_LIMIT then
            table.insert(
                shown, SYL.ClassColor.Name(person.name, person.class)
            )
        else
            extra = extra + 1
        end
    end

    if extra > 0 then
        table.insert(shown, "and " .. extra .. " more")
    end

    return table.concat(shown, ", ")
end

local function ByName(left, right)
    return tostring(left.name or "") < tostring(right.name or "")
end

-- Everybody who was in the group at any pull of any session that counted,
-- folded to one entry per person.
local function Attended(day)
    local people = {}

    for key, member in pairs(day.roster or {}) do
        if type(member) == "table" then
            table.insert(people, {
                key = key,
                name = member.name or key,
                class = member.class,
            })
        else
            local player = SYL.Players.Get(key)

            table.insert(people, {
                key = key,
                name = (player and player.name) or key,
                class = player and player.class,
            })
        end
    end

    table.sort(people, ByName)

    return people
end

--------------------------------------------------------------------------
-- Bosses
--------------------------------------------------------------------------

-- HOW MANY BOSSES THE NIGHT'S INSTANCES HOLD, or nil when the journal has
-- not been read.
--
-- Asked of the fights rather than of the sessions, because a session records
-- the instance the client reported and the journal is keyed on bosses. One
-- number per instance, added up, so a night in two raids says how many bosses
-- both of them hold between them.
function NightFigures.BossTotal(day)
    local seen, total = {}, 0

    for _, fight in ipairs(day.fights or {}) do
        local instance = fight.instanceName or "?"

        if not seen[instance] then
            local count = fight.encounterID
                and SYL.EncounterJournal.BossCountFor(fight.encounterID)

            -- ONE UNKNOWN INSTANCE MAKES THE WHOLE NIGHT UNKNOWN. Adding up
            -- the ones that are known would produce a denominator smaller
            -- than the truth, and "5 of 1" is worse than "5".
            if not count then
                return nil
            end

            seen[instance] = true
            total = total + count
        end
    end

    if total <= 0 then
        return nil
    end

    return total
end

function NightFigures.Bosses(day)
    local total = NightFigures.BossTotal(day)

    local value = total
        and (day.bossCount .. " of " .. total)
        or tostring(day.bossCount)

    local lines = {}
    local instance

    for _, fight in ipairs(day.fights or {}) do
        if fight.instanceName ~= instance then
            instance = fight.instanceName

            table.insert(lines, tostring(instance or "Unknown"))
        end

        local how = SYL.Utilities.ShortDifficulty(fight.difficultyID)

        table.insert(lines, "  " .. tostring(fight.name)
            .. (how and how ~= "" and ("  " .. how) or "")
            .. "  -  "
            .. (fight.killedAt
                and ("killed " .. SYL.Utilities.FormatClock(fight.killedAt))
                or "no kill")
            .. (fight.pulls > 1
                and (", " .. fight.pulls .. " pulls")
                or ""))
    end

    -- SAID PLAINLY WHEN THE DENOMINATOR IS MISSING, because otherwise the
    -- figure silently changes shape between one raid and the next and nobody
    -- can tell why. Aimee: "can a raid lead see boss total is unknown and we
    -- need to scan [...] but has to be obvious to other users on curse."
    if not total then
        table.insert(lines, "")
        -- NAMES THE REAL BUTTON. "Read the Adventure Guide" is what it says
        -- on the Bosses tab (UI/BossesPanel.lua), and telling somebody to
        -- press a control that does not exist under that name is the same
        -- fault the Raiders board tooltip had.
        table.insert(lines,
            "How many bosses this raid holds is not known yet. Press \"Read "
            .. "the Adventure Guide\" on the Bosses tab once, and this "
            .. "becomes \"" .. day.bossCount .. " of 8\" instead of just \""
            .. day.bossCount .. "\".")
    end

    return value, "bosses down", table.concat(lines, "\n")
end

--------------------------------------------------------------------------
-- Raiders
--------------------------------------------------------------------------

-- WHO WAS ON THE TEAM AND DID NOT TURN UP, which no screen in this addon has
-- ever answered.
--
-- Deliberately kept apart from "marked out". They are different facts about
-- different people: one said beforehand that they would not be there, and the
-- other simply was not. Folding them together would let a silent no-show hide
-- among the people who did the right thing.
function NightFigures.NeverCame(day, dayKey)
    local excused, missing = {}, {}

    for _, entry in ipairs(SYL.Absences.WhoIsOut(dayKey or day.key) or {}) do
        local key = entry.key and SYL.Players.ResolveToMain(entry.key)

        excused[key or tostring(entry.name)] = true
        excused[tostring(entry.name)] = true
    end

    for key, player in pairs(SYL.Players.GetRegistry() or {}) do
        local main = SYL.Players.ResolveToMain(key) or key

        if main == key
            and SYL.RaidTeam.IsMember(key)
            and not day.roster[key]
            and not excused[key]
            and not excused[tostring(player.name)]
        then
            table.insert(missing, {
                key = key,
                name = player.name or key,
                class = player.class,
            })
        end
    end

    table.sort(missing, ByName)

    return missing
end

function NightFigures.Raiders(day, dayKey)
    local there = Attended(day)
    local lines = { Names(there) }

    local out = {}

    for _, entry in ipairs(SYL.Absences.WhoIsOut(dayKey or day.key) or {}) do
        local player = entry.key and SYL.Players.Get(entry.key)

        table.insert(out, {
            name = entry.name,
            class = player and player.class,
        })
    end

    if #out > 0 then
        table.insert(lines, "")
        table.insert(lines, "Marked out: " .. Names(out))
    end

    local missing = NightFigures.NeverCame(day, dayKey)

    if #missing > 0 then
        table.insert(lines, "")
        table.insert(lines, "Never came: " .. Names(missing))
    end

    return day.rosterCount, "raiders there", table.concat(lines, "\n")
end

-- WHERE THE NIGHT ACTUALLY WENT, in one line.
--
-- Aimee, on the first drawing: "longest fight maybe should read as 'most pull
-- attempts' but i like how it says the name and the number of pulls." Her
-- 2026-08-20 reads "3 of 9 bosses down" and "17 pulls", and neither of those
-- says the thing a raid leader remembers about that evening, which is that
-- The Coiled Altar ate eleven of the seventeen.
--
-- Nothing to say when every boss died on the first pull, which is a clean
-- night and does not need a story.
function NightFigures.MostPulls(day)
    local worst

    for _, fight in ipairs(day.fights or {}) do
        if not worst or fight.pulls > worst.pulls then
            worst = fight
        end
    end

    if not worst or worst.pulls < 2 then
        return nil
    end

    local how = SYL.Utilities.ShortDifficulty(worst.difficultyID)

    return "Most pull attempts: " .. tostring(worst.name)
        .. (how and how ~= "" and (" " .. how) or "")
        .. ", " .. worst.pulls
        .. (day.pulls > worst.pulls
            and (" of the night's " .. day.pulls)
            or "")
end

--------------------------------------------------------------------------
-- Loot
--------------------------------------------------------------------------

function NightFigures.Loot(day)
    local body =
        "Loot that counts toward fairness. Bind-on-equip and warbound gear "
        .. "are recorded but never counted, and neither is anything from a "
        .. "session that was not a guild night."

    return day.drops, "pieces of loot", body
end

--------------------------------------------------------------------------
-- Who went home with something
--------------------------------------------------------------------------

function NightFigures.Gear(day)
    local got, nothing = {}, {}

    for _, person in ipairs(Attended(day)) do
        if day.gotGear[person.key] then
            table.insert(got, person)
        else
            table.insert(nothing, person)
        end
    end

    local lines = {}

    if #got > 0 then
        table.insert(lines, "Got gear")
        table.insert(lines, Names(got))
    end

    if #nothing > 0 then
        if #lines > 0 then
            table.insert(lines, "")
        end

        table.insert(lines, "Nothing")
        table.insert(lines, Names(nothing))
    end

    table.insert(lines, "")
    table.insert(lines,
        "Need, offspec and greed. A transmog does not count as going home "
        .. "with gear.")

    return day.upgrades .. " of " .. day.rosterCount,
        "went home with gear",
        table.concat(lines, "\n")
end
