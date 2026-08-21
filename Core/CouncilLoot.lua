-- Core/CouncilLoot.lua
--
-- What RCLootCouncil knows about a drop that this addon cannot see for itself.
--
-- WHY THIS EXISTS. Aimee, 2026-08-20: "i cant see who rolled need/greed/mog on
-- items. i see i won it and who i gave it to but not who else rolled through
-- rclc on it." She is right, and the reason is not in this addon: the client
-- reports the group-loot roll, where under a council everybody passes and the
-- master looter takes it. The real answers — who wanted it and how badly —
-- happen inside RCLootCouncil and are never broadcast to the game.
--
-- THE ANSWER IS NOT RECORDED BY DEFAULT, AND THAT IS THE WHOLE PROBLEM.
-- RCLootCouncil has a setting, "Send Session Responses", which is **off** on a
-- fresh install — its own description says "can hurt comms performance". With
-- it off, nothing anywhere keeps who responded: not this addon, and not
-- RCLootCouncil's own history screen either. Her install had never stored a
-- single one, so the night that prompted this is not recoverable by anybody.
--
-- So the first job of this file is to notice that and say so, with a way to
-- turn it on. A screen that simply showed nothing would look like a bug in
-- this addon and would waste an evening being reported as one.
--
-- READ-ONLY, EXCEPT FOR THAT ONE SETTING, and that one is only ever written
-- when somebody presses the button. Reaching into another addon's saved
-- variables to change how it behaves is not something to do quietly.
--
-- EVERYTHING HERE IS GUARDED. RCLootCouncil may be absent, a different major
-- version, or mid-load, and none of those are this addon's business to crash
-- over. Every call into it goes through pcall and answers nil rather than
-- propagating; a missing integration must degrade to the screen this addon
-- already drew.

local SYL = _G.ShowUsYourLoot

local CouncilLoot = {}
SYL.CouncilLoot = CouncilLoot

CouncilLoot.SETTING_LABEL = "Send Session Responses"

--------------------------------------------------------------------------
-- Is it there
--------------------------------------------------------------------------

local function Addon()
    local council = _G.RCLootCouncil

    if type(council) ~= "table" then
        return nil
    end

    return council
end

function CouncilLoot.IsPresent()
    return Addon() ~= nil
end

-- The profile table, or nil. AceDB builds this on load, so a nil here means
-- RCLootCouncil is present but has not finished starting.
local function Profile()
    local council = Addon()

    if not council then
        return nil
    end

    local ok, profile = pcall(function()
        return council.db and council.db.profile
    end)

    if not ok then
        return nil
    end

    return type(profile) == "table" and profile or nil
end

-- Three answers, not two: nil means "cannot tell", which is different from
-- "off" and must not be drawn as it. A screen that says "turn this on" to
-- somebody who does not run RCLootCouncil at all is noise.
function CouncilLoot.IsRecordingResponses()
    local profile = Profile()

    if not profile then
        return nil
    end

    return profile.sendSessionResponses == true
end

-- Only ever from a button. Returns whether it is on afterwards, so a caller
-- can report the truth rather than the intention.
function CouncilLoot.StartRecordingResponses()
    local profile = Profile()

    if not profile then
        return false
    end

    profile.sendSessionResponses = true

    return profile.sendSessionResponses == true
end

--------------------------------------------------------------------------
-- Finding the award for a drop
--------------------------------------------------------------------------

-- RCLootCouncil:GetHistoryDB() hands back its factionrealm scope, already
-- resolved for the character logged in. Asking for the scope by name would
-- mean building the key "Alliance - Area 52" here and getting it wrong on
-- somebody else's realm.
local function HistoryDB()
    local council = Addon()

    if not council or type(council.GetHistoryDB) ~= "function" then
        return nil
    end

    local ok, db = pcall(council.GetHistoryDB, council)

    if not ok or type(db) ~= "table" then
        return nil
    end

    return db
end

-- MATCHED ON THE ITEM LINK, which is exact rather than close. A link carries
-- the bonus ids, so two drops of the same item at different levels are
-- different strings — on the 2026-08-18 night all eleven items matched their
-- award this way with nothing left over.
--
-- The date is checked as well, because the same item can be awarded on two
-- different nights and the link would match both. RCLootCouncil stores its own
-- date as YYYY/MM/DD; this addon stores YYYY-MM-DD.
local function SameDay(entry, drop)
    if not entry.date or not drop.dateText then
        return true
    end

    return (entry.date:gsub("/", "-")) == drop.dateText
end

function CouncilLoot.AwardFor(drop)
    if not drop or not drop.itemLink then
        return nil
    end

    local db = HistoryDB()

    if not db then
        return nil
    end

    for _, awards in pairs(db) do
        if type(awards) == "table" then
            for _, entry in ipairs(awards) do
                if entry.lootWon == drop.itemLink and SameDay(entry, drop) then
                    return entry
                end
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- Who responded
--------------------------------------------------------------------------

-- DECODED BY RCLootCouncil, NOT HERE. What is saved is a packed string keyed
-- by a transmit id — "ilvl@class@response@roll@votes@note" — and the module
-- that wrote it owns the format. Unpacking it here would be a second copy of
-- their wire format in somebody else's addon, wrong the first time they change
-- it and wrong silently.
local function Decoded(entry)
    if type(entry.sessionResponses) == "table" then
        return entry.sessionResponses
    end

    if type(entry.SR) ~= "table" then
        return nil
    end

    local council = Addon()

    if not council or type(council.GetModule) ~= "function" then
        return nil
    end

    local ok, history = pcall(council.GetModule, council, "RCLootHistory")

    if not ok or type(history) ~= "table"
        or type(history.DecodeSessionResponses) ~= "function"
    then
        return nil
    end

    if not pcall(history.DecodeSessionResponses, history, entry) then
        return nil
    end

    return type(entry.sessionResponses) == "table"
        and entry.sessionResponses
        or nil
end

-- The response id is meaningless on its own — Core/LootCredit.lua's header
-- records that Disenchant, Need, BiS and Major Upgrade all share id 1 — so it
-- is resolved to text by the addon that defines it, per item type.
local function ResponseText(council, entry, responseID)
    if responseID == nil then
        return nil
    end

    if type(council.GetResponse) ~= "function" then
        return nil
    end

    local ok, response = pcall(
        council.GetResponse, council, entry.typeCode or "default", responseID
    )

    if not ok or type(response) ~= "table" then
        return nil
    end

    return response.text
end

local function ByResponseThenRoll(left, right)
    if left.isWinner ~= right.isWinner then
        return left.isWinner == true
    end

    if (left.roll or -1) ~= (right.roll or -1) then
        return (left.roll or -1) > (right.roll or -1)
    end

    return tostring(left.name) < tostring(right.name)
end

-- Everyone who answered on this drop, or nil when there is nothing recorded.
--
-- nil and an empty list mean different things and both happen: nil is "nobody
-- kept this", which is the setting being off, and empty is "kept, and nobody
-- answered", which is a real thing on an item the whole raid passed.
function CouncilLoot.ResponsesFor(drop)
    local entry = CouncilLoot.AwardFor(drop)

    if not entry then
        return nil
    end

    local responses = Decoded(entry)

    if not responses then
        return nil
    end

    local council = Addon()
    local list = {}

    for name, data in pairs(responses) do
        if type(data) == "table" then
            -- The winner's own answer lives on the award rather than in the
            -- response table — RCLootCouncil stores only their item level and
            -- roll there, because the rest is already on the entry.
            local isWinner = entry.player ~= nil and name == entry.player
                or (entry.owner ~= nil and name == entry.owner
                    and data.response == nil)

            table.insert(list, {
                name = name,
                class = isWinner and entry.class or data.class,
                response = isWinner
                    and entry.response
                    or ResponseText(council, entry, data.response),
                roll = data.roll,
                ilvl = data.ilvl,
                votes = isWinner and entry.votes or data.votes,
                note = data.note,
                isWinner = isWinner,
            })
        end
    end

    table.sort(list, ByResponseThenRoll)

    return list
end

--------------------------------------------------------------------------
-- What a screen should say about all this
--------------------------------------------------------------------------

-- One place, because three screens would otherwise each invent their own
-- wording for the same four states and one of them would say "no responses"
-- about an addon that is not installed.
--
--   "absent"     — no RCLootCouncil. Say nothing; this is not their workflow.
--   "off"        — installed, not recording. The one worth a button.
--   "none"       — recording, but nothing kept for this drop. Either it
--                  predates the setting, or it was not a council award.
--   "responses"  — the answer, with the list.
function CouncilLoot.Describe(drop)
    if not CouncilLoot.IsPresent() then
        return { state = "absent" }
    end

    local recording = CouncilLoot.IsRecordingResponses()
    local responses = CouncilLoot.ResponsesFor(drop)

    if responses then
        return { state = "responses", responses = responses }
    end

    if recording == false then
        return { state = "off" }
    end

    return { state = "none" }
end
