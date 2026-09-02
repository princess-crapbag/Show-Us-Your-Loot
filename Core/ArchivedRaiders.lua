-- Core/ArchivedRaiders.lua
--
-- Raiders who have fallen off the board, and the season they took with them.
--
-- THE PROBLEM THIS EXISTS FOR, in Aimee's words: "i have removed 2 of these
-- people from the roster... when i see the board it should only be active
-- members of the raid team. but i dont want to lose the history from this
-- screen either." Both halves are right and they fight: the board is scoped to
-- the raid team, so unticking somebody is exactly what makes them vanish, and
-- their nights and their wins vanish with them.
--
-- Nothing is deleted when that happens -- the drops and the session rosters
-- are untouched -- so this is not a recovery problem. It is a list that was
-- never built.
--
-- THE RULE, and it is deliberately derived rather than recorded:
--
--   in the guild, raided a night that counted, and not on the raid team now.
--
-- A recorded rule would be sharper. Marking somebody off the team could write
-- the date and this could list exactly those people, which is the version that
-- can say "off the team since the 27th" -- but it can only start recording
-- from the build that ships it, and the two raiders this was asked for were
-- already gone. A derived rule answers for them tonight. That was Aimee's
-- call, offered against the recorded one.
--
-- WHY PUGS ARE OUT. Every pug who has ever rolled in a guild raid is a person
-- with nights and no team tick, and they would outnumber the raiders this list
-- is for. The session roster records a guild rank per member on the night, so
-- "was one of ours at the time" is already a fact rather than a guess.
--
-- AND WHY IT IS ASKED OF THE NIGHT AND NOT ONLY OF THE GUILD LIST. Somebody
-- who was removed from the team and then left the guild is off the guild
-- roster entirely, and asking only "are they in the guild" would drop the one
-- person most likely to be argued about. What they were on the night does not
-- change afterwards.

local SYL = _G.ShowUsYourLoot

local ArchivedRaiders = {}
SYL.ArchivedRaiders = ArchivedRaiders

--------------------------------------------------------------------------
-- Archiving somebody by hand
--------------------------------------------------------------------------

-- THE DERIVED RULE CANNOT REACH EVERYBODY, which is what this is for.
--
-- Aimee: "there are a few trials showing on my roster that i want to archive."
-- A trial who joined, sat through no raid night and drifted off is in the
-- guild and has no nights, so the rule above will never list them and the
-- roster will list them forever. There is nothing to derive from: the fact
-- that they are done is a thing only a person knows.
--
-- GUILD RANK HAS NOTHING TO DO WITH IT, and must not acquire anything to do
-- with it. Aimee: "someone could join the raid in any rank so i need to be
-- able to add and remove no matter their rank." Core/RaidTeam.lua's header
-- makes the same point about the team flag for the same reason -- officers who
-- do not raid hold the top rank and trials who do raid hold the bottom one.
-- Nothing here reads a rank.
--
-- Kept on the player registry beside inRaidTeam, and per character for the
-- same reason team membership is: you archive a character you can see on a
-- row, not an abstract person. Stored as nil rather than false when off, so a
-- registry of seven hundred does not carry seven hundred false flags into
-- SavedVariables.
local function Record(key)
    if not key then
        return nil
    end

    return SYL.Players.Get(key)
end

function ArchivedRaiders.IsArchivedCharacter(key)
    local player = Record(key)

    return (player and player.archived) and true or false
end

-- The person, not the character. Every list this is compared against has
-- folded alts onto the main already, so asking the fold key alone would answer
-- no for somebody whose archived character is not the one the fold picked.
-- The mirror of AnyCharacterOnTeam in Core/Audience.lua, and deliberately the
-- same shape.
function ArchivedRaiders.IsArchived(key)
    if ArchivedRaiders.IsArchivedCharacter(key) then
        return true
    end

    for _, alt in ipairs(SYL.Players.GetAlts(key) or {}) do
        if alt.guid and ArchivedRaiders.IsArchivedCharacter(alt.guid) then
            return true
        end
    end

    return false
end

-- ARCHIVING TAKES SOMEBODY OFF THE RAID TEAM, always.
--
-- The two states are contradictory -- archived means "not somebody I am going
-- to bring", and the board is "who is owed loot for turning up" -- and a
-- character in both would be on the board and off the roster at once, which is
-- the exact disagreement the archived screen was built to end.
--
-- Done here rather than left to the caller so it cannot be forgotten at one of
-- the two call sites. RaidTeam.SetMember clears the archived flag going the
-- other way, for the same reason.
function ArchivedRaiders.Archive(key)
    local player = Record(key)

    if not player then
        return false
    end

    player.archived = true
    player.inRaidTeam = nil

    return true
end

-- The undo, and it does exactly one thing: puts them back on the roster. It
-- deliberately does NOT put them back on the raid team -- being on the roster
-- and being on the team are two different marks, and restoring a mark nobody
-- made is how somebody ends up back on the board without having been added.
--
-- CLEARS THE PERSON, WHERE Archive MARKS A CHARACTER, and the asymmetry is
-- deliberate rather than an oversight. You archive a row you can see on the
-- roster, which is a character. You un-archive a row on the archived board,
-- which is a person with their alts already folded onto them -- so the flag
-- being cleared may well sit on a character that row never named. Clearing
-- only the fold key would leave the person archived and the button looking
-- broken.
function ArchivedRaiders.Restore(key)
    local cleared = false

    local function Clear(candidate)
        local player = candidate and Record(candidate)

        if player and player.archived then
            player.archived = nil
            cleared = true
        end
    end

    Clear(key)

    for _, alt in ipairs(SYL.Players.GetAlts(key) or {}) do
        Clear(alt.guid)
    end

    return cleared
end

function ArchivedRaiders.Count()
    local total = 0

    for _, player in pairs(SYL.Players.GetRegistry()) do
        if player.archived then
            total = total + 1
        end
    end

    return total
end

--------------------------------------------------------------------------
-- The derived half
--------------------------------------------------------------------------

-- Everybody who carried a guild rank on a night that counted.
--
-- Folded to the main, because every list this is compared against has been:
-- somebody who brought a guilded alt to raid is one of ours, and asking the
-- alt's own key would answer no for the person.
--
-- Nights only, and the same ones the board counts -- see
-- RaidSession.NightsOnly. A 49-person LFR run is not evidence of anything
-- about a raid team, and it is where most of the strangers come from.
function ArchivedRaiders.GuildedOnANight(sessions)
    local seen = {}

    for _, session in ipairs(SYL.RaidSession.NightsOnly(sessions or {})) do
        for rawKey, member in pairs(session.roster or {}) do
            if member.guildRank then
                seen[SYL.Players.ResolveToMain(rawKey)] = true
            end
        end
    end

    return seen
end

-- `guilded` is the table above, passed in so a list of four hundred entries
-- does not sweep every session once per row.
function ArchivedRaiders.Includes(entry, guilded)
    if not entry then
        return false
    end

    -- ARCHIVED BY HAND SKIPS EVERY TEST BELOW, which is the point of having a
    -- flag at all. A trial with no nights fails the raided test and a raider
    -- who has left the guild fails the guild test, and both are exactly the
    -- people somebody reaches for this control to file away.
    if ArchivedRaiders.IsArchived(entry.key) then
        return true
    end

    -- Somebody who has never raided has no history to keep, so there is
    -- nothing for this screen to show them for. They are on the roster, which
    -- is the list of who could raid, and that is the right place for them.
    if (entry.nights or 0) < 1 then
        return false
    end

    -- The whole point: on the team is on the board, and a name cannot be in
    -- both places at once without the two screens disagreeing about who is
    -- raiding.
    if SYL.Audience.Includes("team", entry.key, entry.guid, entry.name) then
        return false
    end

    if guilded and guilded[entry.key] then
        return true
    end

    return SYL.Guild.GetMemberForPlayer(entry.key, entry.guid, entry.name)
        ~= nil
end

-- Takes the due list -- unscoped, every person the season has a night for --
-- and returns the ones this screen is about.
function ArchivedRaiders.Filter(entries, sessions)
    local guilded = ArchivedRaiders.GuildedOnANight(sessions)
    local kept = {}

    for _, entry in ipairs(entries or {}) do
        if ArchivedRaiders.Includes(entry, guilded) then
            table.insert(kept, entry)
        end
    end

    return kept
end

-- The archived list, and the list its bars are measured against.
--
-- ONE SWEEP FOR BOTH. DueList.Build is the season's every drop and session
-- folded onto people, and this screen needs that list twice over -- once
-- filtered to the people who are archived, once filtered to the raid team to
-- get a scale. Building it twice would do the expensive half twice for one
-- screen.
--
-- THE SCALE IS THE RAID TEAM'S, ALWAYS, and not whatever the scope button was
-- left on. A bar is only a picture of anything next to the other bars on the
-- board, and an ex-raider measured against the other ex-raiders answers a
-- question nobody asked. Measured against the people still raiding, it answers
-- the one they do: where did this person stand.
--
-- Returns the archived entries, the team to measure them against, and how many
-- people the season had a night for at all -- which is what tells an empty
-- list which kind of empty it is.
function ArchivedRaiders.Build()
    local sessions = SYL.GetActiveRaids()
    local drops = SYL.GetActiveDrops()

    local everybody = SYL.DueList.Build(drops, sessions)

    local entries = ArchivedRaiders.Filter(everybody, sessions)
    local team = SYL.Audience.Filter(everybody, "team")

    -- AND ANYONE ARCHIVED WHO IS NOT IN THAT LIST AT ALL.
    --
    -- DueList.Build only makes an entry for somebody who was in a session
    -- roster, so a trial archived without ever raiding has nothing to be
    -- filtered -- and would be archived into a list that never showed them,
    -- which is a name disappearing rather than being filed. They draw with
    -- dashes down the row, which is the truth about them.
    local seen = {}

    for _, entry in ipairs(entries) do
        seen[entry.key] = true
    end

    for key, player in pairs(SYL.Players.GetRegistry()) do
        local personKey = SYL.Players.ResolveToMain(key)

        if player.archived and not seen[personKey] then
            seen[personKey] = true

            table.insert(entries, {
                key = personKey,
                guid = player.guid or key,
                name = player.name or player.fullName,
                class = player.class,
                nights = 0,
                nightsSinceUpgrade = 0,
                everWon = false,
            })
        end
    end

    SYL.LootScore.Rank(entries, drops)
    SYL.LootScore.Rank(team, drops)

    return entries, team, #everybody
end

-- Said under an empty list, and it has to distinguish the two ways of getting
-- there: a season nobody has raided yet, and a season where everybody who
-- raided is still on the team. The first is waiting for data and the second is
-- the answer.
function ArchivedRaiders.ExplainEmpty(totalBeforeFilter)
    if (totalBeforeFilter or 0) == 0 then
        return "Nothing recorded yet. This fills in from your next raid night."
    end

    return "Nobody is archived. Everyone in the guild who has raided this "
        .. "season is still marked as being on the raid team."
end

-- The sentence under a list that is not empty, in the same slot the board
-- prints Audience.Note into. Says the rule, because a list somebody did not
-- build by hand has to explain how a name got onto it.
ArchivedRaiders.NOTE =
    "in your guild, raided this season, not on the raid team now"

-- SAYS WHOSE AVERAGE THAT MARKER IS. The number is the raid team's and the
-- rows are not, which is the whole point of the screen and also exactly the
-- sort of thing somebody would otherwise read as this list's own average and
-- quote back at you.
--
-- `average` and `ranked` are the raid team's, from LootScore.Average.
function ArchivedRaiders.Caption(shown, average, ranked)
    local measure

    if (ranked or 0) > 0 then
        measure = string.format(
            "bars and the marker are the raid team's, averaging %.1f per night",
            average or 0
        )
    else
        measure = "nobody on the raid team is ranked yet, so there are no "
            .. "bars to measure against"
    end

    return string.format(
        "%d shown · %s · %s", shown, ArchivedRaiders.NOTE, measure
    )
end
