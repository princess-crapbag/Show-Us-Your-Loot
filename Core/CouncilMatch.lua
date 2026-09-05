-- Core/CouncilMatch.lua
--
-- Every drop this season where RCLootCouncil disagrees with what is credited,
-- gathered in one pass so an officer can fix a night in one press.
--
-- WHY IT EXISTS. Aimee: "after i give out loot i need to go into the loot
-- window and select each item and credit the loot to match what rclc said
-- along with changing a need roll to need when it sometimes says need but
-- lists it in my drop detail window as greed. shouldnt it by default match
-- rclc and i change it if needed?"
--
-- Core/CouncilLoot.lua already answers this for ONE drop, and UI/DropCredit
-- has had a "Match to RCLootCouncil" button on it for a while. The missing
-- piece was never the lookup, it was having to find every drop by hand.
--
-- WHY IT IS NOT SILENT AND AUTOMATIC, which is what she asked for first.
-- RCLootCouncil awards land AFTER the drop is captured -- sometimes minutes
-- after, when the council finishes voting -- so a client that matched at
-- capture time would miss most of them and never say which. Worse, matching
-- rewrites who a scored item belongs to: it moves points between real people
-- on a board those people read. That is a thing to be shown before it
-- happens, not discovered afterwards.
--
-- So the sweep is a press and it shows its work first. Aimee, choosing
-- between that and doing it automatically: "i like review for matching the
-- rclootcouncil".
--
-- BOTH HALVES OF THE MISMATCH ARE CARRIED. The name is the obvious one. The
-- RESPONSE matters as much and is the half she named -- "changing a need roll
-- to need when it sometimes says need but lists it in my drop detail window
-- as greed" -- because under a council the recorded state is the master
-- looter's roll rather than the recipient's answer. Core/DropRules.lua has
-- measured that before: six of eleven drops on 2026-08-18 carried the wrong
-- weight and four of those were Transmog, which weighs nothing at all.

local SYL = _G.ShowUsYourLoot

local CouncilMatch = {}
SYL.CouncilMatch = CouncilMatch

local ROLL_STATE = SYL.LootHistoryAPI.ROLL_STATE

-- RCLootCouncil'S ANSWER, TURNED INTO ONE OF OURS -- and the reason this is
-- done by WORDS rather than by their response number.
--
-- Their defaults are three buttons: 1 Mainspec/Need, 2 Offspec/Greed, 3 Minor
-- Upgrade, read straight out of their Core/Defaults.lua. But every guild
-- rewrites them -- Aimee's has a Mog button their defaults do not ship, which
-- is why her drop detail shows Need, Greed and Mog. So a number means
-- whatever that guild made it mean, and matching on it would silently score
-- one guild's Mog as another guild's Minor Upgrade.
--
-- The text is what the officer actually clicked and what they will recognize
-- in the review list, so that is what is read. Lowercased and searched for
-- the words every guild's buttons are built out of.
--
-- NIL IS A REAL ANSWER and the important one: anything this cannot place
-- leaves the recorded response alone and says "name only" in the review, so
-- an unrecognized button moves the item to the right person without inventing
-- a weight for it. Core/CouncilLoot.lua's header calls the mapping "the part
-- that cannot be right for every guild"; this is that caution kept.
local function StateFor(suggestion)
    local text = suggestion and suggestion.response

    if type(text) ~= "string" then
        return nil
    end

    text = text:lower()

    -- Offspec first: "Offspec/Greed" holds both words, and the offspec half
    -- is the one that names what the person asked for. Both weigh 20 in
    -- Core/LootScore.lua, so the distinction is about what a screen says
    -- rather than about points.
    if text:find("offspec", 1, true) then
        return ROLL_STATE.NeedOffSpec
    end

    if text:find("need", 1, true) or text:find("mainspec", 1, true) then
        return ROLL_STATE.NeedMainSpec
    end

    if text:find("mog", 1, true) then
        return ROLL_STATE.Transmog
    end

    if text:find("greed", 1, true) then
        return ROLL_STATE.Greed
    end

    if text:find("pass", 1, true) then
        return ROLL_STATE.Pass
    end

    return nil
end

CouncilMatch.StateFor = StateFor

local function ResponseText(suggestion)
    if not suggestion then
        return nil
    end

    return suggestion.response
end

-- Every drop in a season that RCLootCouncil would change, oldest first.
--
-- Returns a list of { drop, id, itemName, itemLink, fromName, toName,
-- response, dateText }, and the reason it carries the FROM as well as the TO
-- is that a review with only the new name cannot be checked against anything.
function CouncilMatch.Build(season)
    local changes = {}

    if not SYL.CouncilLoot.IsPresent() then
        return changes, "RCLootCouncil is not loaded"
    end

    for _, drop in ipairs((season and season.drops) or {}) do
        local suggestion = SYL.CouncilLoot.SuggestedCredit(drop)

        if suggestion and suggestion.name then
            local current = SYL.LootCredit.Describe(drop)

            table.insert(changes, {
                drop = drop,
                id = drop.id,
                itemName = drop.itemName or "?",
                itemLink = drop.itemLink,
                fromName = (current and current.name) or drop.winnerName,
                toName = suggestion.name,
                response = ResponseText(suggestion),
                state = StateFor(suggestion),
                dateText = drop.dateText,
                timestamp = drop.timestamp,
            })
        end
    end

    table.sort(changes, function(left, right)
        return (left.timestamp or 0) < (right.timestamp or 0)
    end)

    return changes
end

-- Applies one change. Split out so the window can apply a subset later
-- without this file growing a second way to do the same thing.
function CouncilMatch.Apply(change)
    if not change or not change.id then
        return false, "that drop is no longer in the database"
    end

    return SYL.LootCredit.Set(change.id, {
        name = change.toName,
        guid = SYL.Players.GUIDForName(change.toName),

        -- nil means "keep the recorded response", which is the right answer
        -- when RCLootCouncil has not told us one. LootCredit.Set documents
        -- the same rule at its own call site.
        state = change.state,
    })
end

-- Returns how many were applied and how many failed. Failures are counted
-- rather than swallowed: a sweep that silently skips a drop is a sweep whose
-- number cannot be trusted the next time it is run.
function CouncilMatch.ApplyAll(changes)
    local applied, failed = 0, 0

    for _, change in ipairs(changes or {}) do
        if CouncilMatch.Apply(change) then
            applied = applied + 1
        else
            failed = failed + 1
        end
    end

    if applied > 0 then
        SYL.LootHistoryStore.RebuildIndex()
    end

    return applied, failed
end

-- One line per change, for the review list and for /syl output.
function CouncilMatch.Describe(change)
    if not change then
        return ""
    end

    local text = tostring(change.itemName) .. ": "
        .. SYL.Utilities.ShortName(change.fromName or "?")
        .. " → " .. SYL.Utilities.ShortName(change.toName)

    if change.response then
        text = text .. " (" .. tostring(change.response) .. ")"
    end

    if change.response and not change.state then
        -- Says so rather than looking like the response moved too. An
        -- unrecognized button is not a failure -- the name still moves -- but
        -- somebody reading the list has to know the weight did not.
        text = text .. " · name only"
    end

    return text
end

-- The sentence under the list. Says nothing rather than "0 drops" when there
-- is nothing to do: an officer who has already matched a night should be told
-- they are done, not shown an empty table with a number on it.
function CouncilMatch.Summarize(changes, reason)
    if reason then
        return reason
    end

    if #changes == 0 then
        return "Everything already matches RCLootCouncil."
    end

    local people = {}
    local count = 0

    for _, change in ipairs(changes) do
        if not people[change.toName] then
            people[change.toName] = true
            count = count + 1
        end
    end

    return SYL.Utilities.Count(#changes, "drop") .. " would move, across "
        .. SYL.Utilities.Count(count, "person", "people")
        .. ". Nothing changes until you apply it."
end
