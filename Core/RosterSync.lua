-- Core/RosterSync.lua
--
-- Sending the raid team to the guild, and showing what arrives.
--
-- ONE BROADCASTER, EVERYBODY ELSE RECEIVES. Aimee's call, and it is what makes
-- this the smallest of the three shapes considered: there is no merge, no
-- per-author set to reconcile, and no way for two officers to disagree that
-- somebody then has to resolve. The officer who keeps the roster turns sharing
-- on and nobody else has to do anything at all.
--
-- WHICH IS WHY RECEIVING IS NOT BEHIND THE SWITCH. Every other sharing feature
-- here registers its prefix inside Enable, so a client with the switch off is
-- deaf as well as silent. That is right for the symmetric ones — absences and
-- keystones are a trade, and somebody who sends nothing has no claim on what
-- everyone else sends. This one is asymmetric on purpose: the guildies it
-- exists for are exactly the people who will never turn anything on, and a
-- switch they have to find first would leave the roster invisible to all of
-- them. "The addon does not talk unless asked" is a rule about talking.
-- Listening costs nothing and says nothing.
--
-- WHAT IS SENT, in full: for each character on the raid team or holding a
-- role — the registry key, the name, the class, whether they are on the team,
-- and the role. Recruits from IncomingRoster travel the same way, because a
-- roster missing the person joining on Friday is not the roster.
--
-- WHAT IS NOT SENT, and the omission is deliberate: alt mapping. Team
-- membership and role only ever change what a screen shows or how a list is
-- scoped — no fairness module reads either, which was checked rather than
-- assumed. Alt mapping is different in kind: it folds two characters into one
-- person inside the scoring, so broadcasting it would move other people's
-- numbers rather than their view. That is a decision to take on its own.
--
-- WHAT ARRIVES NEVER TOUCHES THE REGISTRY. It lands in its own block, and
-- RaidTeam reads it only where the local answer is empty — so a receiver who
-- has marked their own team keeps it, and clearing a shared roster leaves
-- nothing of somebody else's behind in your own data. Same rule as Sync.lua,
-- which marks arriving drops partial rather than letting them overwrite.
--
-- THE SENDER DECIDES THE SOURCE, NOT THE PAYLOAD. The name stamped on a
-- received roster is the one the addon channel reports, so a client cannot
-- claim to be broadcasting somebody else's. With one broadcaster that costs
-- nothing today; it is what stops this being a way to impersonate an officer
-- the first time a second person turns the switch on.

local SYL = _G.ShowUsYourLoot

local RosterSync = {}
SYL.RosterSync = RosterSync

-- Its own prefix, so a client running an older build never hands these to a
-- parser written for something else.
local PREFIX = "SYLROST"
local VERSION = "1"

local REQUEST = "?"

local frame
local listening = false

local ANSWER_THROTTLE_SECONDS = 20
local lastAnswerAt = 0

-- Sets being assembled, keyed by sender. A set is committed only once every
-- piece has arrived, so a half-delivered broadcast never shows a roster with
-- half the team missing — which would read as people having been dropped.
local pending = {}

local function Author()
    return (SYL.Keystone and SYL.Keystone.CharacterKey()) or "unknown"
end

local function IsSharing()
    return (SYL.Features and SYL.Features.IsEnabled("rosterSharing")) or false
end

local function CanSend()
    return C_ChatInfo
        and C_ChatInfo.SendAddonMessage
        and IsInGuild()
        and true
        or false
end

-- Queued, not sent. A roster is one message per raider and the set commits
-- only when every piece has arrived, so a single message thrown away by the
-- client's rate limit leaves it half-assembled forever — and looks exactly
-- like nobody having shared one. Core/SendQueue.lua has the whole argument.
local function Send(payload)
    if not CanSend() then
        return false
    end

    return SYL.SendQueue.Queue(PREFIX, payload, "GUILD", nil, CanSend)
end

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

-- Tab separated, like the absence payloads, because a registry key already
-- contains the dash this addon builds names with.
local function Clean(text)
    return (tostring(text or ""):gsub("[\t\n|]", " "))
end

function RosterSync.Encode(serial, index, count, member)
    local body = ""

    if member then
        body = table.concat({
            Clean(member.key),
            Clean(member.name),
            Clean(member.class),
            member.inRaidTeam and "1" or "",
            Clean(member.raidRole),
        }, "\t")
    end

    return table.concat({
        VERSION, tostring(serial), tostring(index), tostring(count), body
    }, "\t")
end

-- Returns serial, index, count, member. The member is nil for the empty-set
-- marker, which is a real message and the one that clears a shared roster.
function RosterSync.Decode(payload)
    if type(payload) ~= "string" then
        return nil
    end

    local version, serial, index, count, body =
        payload:match("^(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")

    if version ~= VERSION then
        return nil
    end

    serial = tonumber(serial)
    index = tonumber(index)
    count = tonumber(count)

    if not serial or not index or not count then
        return nil
    end

    if count == 0 then
        return serial, index, count, nil
    end

    -- A fragment claiming to be the ninth of three cannot be placed, and used
    -- to be counted anyway: `seen` went up, the member landed under an index
    -- the ordering loop never reads, and the set completed holding fewer people
    -- than it said. A roster arriving quietly short, which is the failure this
    -- file is least able to notice.
    if index < 1 or index > count then
        return nil
    end

    local key, name, class, team, role =
        body:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.*)$")

    if not key or key == "" or not name or name == "" then
        return nil
    end

    return serial, index, count, {
        key = key,
        name = name,
        class = (class ~= "" and class) or nil,
        inRaidTeam = team == "1",
        raidRole = (role ~= "" and role) or nil,
    }
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

-- Everyone marked onto the team or given a role, from both places a roster
-- lives. A role without team membership still travels: an officer who has
-- typed somebody's role has said something about them worth carrying.
function RosterSync.Own()
    local mine = {}

    for key, player in pairs(SYL.Players.GetRegistry()) do
        if player.inRaidTeam or player.raidRole then
            table.insert(mine, {
                key = key,
                name = player.name or player.fullName or key,
                class = player.class,
                inRaidTeam = player.inRaidTeam and true or false,
                raidRole = player.raidRole,
            })
        end
    end

    for _, entry in ipairs(SYL.IncomingRoster.List() or {}) do
        if entry.inRaidTeam or entry.raidRole then
            table.insert(mine, {
                key = entry.key,
                name = entry.name or entry.fullName or entry.key,
                class = entry.class,
                inRaidTeam = entry.inRaidTeam and true or false,
                raidRole = entry.raidRole,
            })
        end
    end

    -- Sorted, so the same roster encodes to the same messages in the same
    -- order every time. pairs over the registry does not promise that, and a
    -- test comparing two broadcasts would fail on the ordering alone.
    table.sort(mine, function(left, right)
        return left.key < right.key
    end)

    return mine
end

local serial = 0

function RosterSync.Announce()
    if not IsSharing() or not CanSend() then
        return false
    end

    local mine = RosterSync.Own()

    serial = serial + 1

    -- The empty set is sent, not skipped, for the same reason it is in
    -- AbsenceSync: an officer who has unmarked their last raider has to be
    -- able to say so, and silence would leave the old roster standing on every
    -- other client forever.
    if #mine == 0 then
        Send(RosterSync.Encode(serial, 0, 0, nil))

        return true
    end

    for index, member in ipairs(mine) do
        Send(RosterSync.Encode(serial, index, #mine, member))
    end

    return true
end

-- THE ANSWER TO A REQUEST, WHICH IS NOT THE SAME AS A BROADCAST.
--
-- Announce above sends the empty set when there is nobody on the team, and it
-- has to: an officer who has unmarked their last raider needs a way to say so.
-- Answering somebody else's question is different. "I have nothing" is not an
-- answer worth sending, and sending it was the bug.
--
-- What happened on Aimee's guild: an officer with the switch on and an empty
-- local team -- empty because everything they could see was HER roster, and
-- Own() deliberately does not include a received one -- answered every login
-- in the guild with the empty set. Every client that had her roster lost it,
-- over and over, and the screen did not even go blank: Audience.Default falls
-- through to "guild" once nobody is marked, so the scope button silently
-- moved to Guild and the list filled with all fifteen guildies. "Their entire
-- raid team disappeared", from a client that was only being polite.
--
-- SharedRoster now refuses an empty set from anyone but the accepted source,
-- which is the guard that matters. This is the other half: do not send it.
-- Nothing to say, so say nothing.
local function Answer()
    if not IsSharing() or not CanSend() then
        return false
    end

    if #RosterSync.Own() == 0 then
        return false
    end

    return RosterSync.Announce()
end

-- Asked by a client that has just logged in. Answering is gated on sharing;
-- asking is not, because the asker is the one with nothing.
function RosterSync.Request()
    if not CanSend() then
        return false
    end

    Send(REQUEST)

    return true
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

-- Hands a complete set to the store. Everything about *whether* it is complete
-- is above; everything about what a roster is is in SharedRoster. The guard on
-- the sender stays here, because it is the transport that knows a message
-- without one is not a message.
--
-- OFFERED, NOT WRITTEN, and the difference is the fix. Returns what became of
-- it -- "applied", "pending" or "ignored" -- which is SharedRoster's decision
-- to make and this file's only job to carry.
function RosterSync.Commit(sender, members)
    if not sender then
        return "ignored"
    end

    return SYL.SharedRoster.Offer(sender, members or {})
end

local function Accumulate(sender, serialID, index, count, member)
    if count == 0 then
        pending[sender] = nil

        return RosterSync.Commit(sender, {})
    end

    local set = pending[sender]

    -- A new serial from the same sender supersedes whatever was half
    -- assembled: they have said something newer and the old set is stale.
    if not set or set.serial ~= serialID then
        set = { serial = serialID, count = count, items = {}, seen = 0 }
        pending[sender] = set
    end

    if not set.items[index] then
        set.seen = set.seen + 1
    end

    set.items[index] = member

    if set.seen < set.count then
        return nil
    end

    local ordered = {}

    for position = 1, set.count do
        if set.items[position] then
            table.insert(ordered, set.items[position])
        end
    end

    pending[sender] = nil

    return RosterSync.Commit(sender, ordered)
end

-- One message from one sender. Exported because the interesting behavior is
-- what happens *between* the messages of a set — a fragment must never reach
-- the store — and that is unreachable through an event handler.
--
-- Returns what became of the set — "applied", "pending" or "ignored" — or nil
-- while it is still being assembled.
function RosterSync.Receive(sender, payload)
    -- Our own broadcast comes back to us. The registry is the authority on
    -- what this client marked, so storing our own set would give us a shared
    -- copy of our own roster and a screen claiming somebody sent it to us.
    if not sender or sender == Author() then
        return nil
    end

    local serialID, index, count, member = RosterSync.Decode(payload)

    if not serialID then
        return nil
    end

    return Accumulate(sender, serialID, index, count, member)
end

-- Guild members only, the same test SyncTransport makes and for the same
-- reason. The header above argues that listening costs nothing — it does, but
-- only from the guild. This is the one listener registered unconditionally at
-- login, so it was reachable by anybody in a party, raid or instance group,
-- which on a raid night is a room full of strangers. And SharedRoster.Replace
-- is a single slot rather than one per sender, so a set from outside does not
-- sit beside the real one, it becomes it and takes the "shared by" line too.
-- The empty set is a legitimate message, so the guard belongs on the sender.
local function FromGuildMember(sender)
    if not sender then
        return false
    end

    local shortName = sender:match("^([^-]+)")

    return SYL.Guild.IsMember(nil, shortName)
        or SYL.Guild.IsMember(nil, sender)
end

local function OnMessage(prefix, payload, _, sender)
    if prefix ~= PREFIX then
        return
    end

    if not FromGuildMember(sender) then
        return
    end

    if payload == REQUEST then
        if sender == Author() or not IsSharing() then
            return
        end

        local now = time()

        if now - lastAnswerAt < ANSWER_THROTTLE_SECONDS then
            return
        end

        lastAnswerAt = now

        Answer()

        return
    end

    local outcome = RosterSync.Receive(sender, payload)

    if outcome == "pending" then
        -- The one thing this file does not decide. A roster from a name
        -- nobody has agreed to is a question, and the question belongs on
        -- screen rather than in the database.
        if SYL.SharedRosterPrompt then
            SYL.SharedRosterPrompt.Show()
        end

        return
    end

    if outcome == "applied" and SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end
end

--------------------------------------------------------------------------
-- Switching on
--------------------------------------------------------------------------

function RosterSync.IsListening()
    return listening
end

-- Called unconditionally at login. See the header: the switch decides whether
-- this client broadcasts, never whether it can hear.
function RosterSync.Listen()
    if listening then
        return true
    end

    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return false
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    frame = frame or CreateFrame("Frame")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            OnMessage(...)
        end
    end)

    frame:RegisterEvent("CHAT_MSG_ADDON")

    listening = true

    return true
end

-- Called whenever this client's own roster changes, so the guild sees a raider
-- added or dropped without waiting for the next login.
function RosterSync.OnOwnRosterChanged()
    if not IsSharing() then
        return
    end

    RosterSync.Announce()
end

--------------------------------------------------------------------------
-- Pressing send
--------------------------------------------------------------------------

-- THE BUTTON, and the reason there is one.
--
-- Sharing was a switch and nothing else, labelled "Share your raid team with
-- the guild". Read at speed by somebody who wants a roster rather than wants
-- to give one, that is the switch you flip to GET the roster -- which is what
-- Aimee's officer did, and it made them a broadcaster. A switch you can
-- misread in the useful direction is a trap.
--
-- So sending is a thing you press, and it says what it did. The switch still
-- exists and still means what it says: it keeps the guild up to date without
-- you pressing anything. Somebody who has not turned it on can still send
-- once, deliberately, which is the case the switch could never express.
--
-- Returns how many were sent, or nil and a reason. The reason is shown rather
-- than swallowed: "nothing happened" and "you are not in a guild" look
-- identical otherwise.
function RosterSync.SendNow()
    if not IsInGuild() then
        return nil, "you are not in a guild"
    end

    if not CanSend() then
        return nil, "this client cannot send addon messages right now"
    end

    local mine = RosterSync.Own()

    if #mine == 0 then
        return nil, "nobody is marked as being on the raid team yet"
    end

    serial = serial + 1

    for index, member in ipairs(mine) do
        Send(RosterSync.Encode(serial, index, #mine, member))
    end

    return #mine
end

-- ASKED AGAIN ONCE THE GUILD LIST IS ACTUALLY THERE.
--
-- Every arriving roster is dropped unless the sender is in the cached guild
-- list -- rightly, see FromGuildMember above -- but the request goes out at
-- PLAYER_LOGIN, before GUILD_ROSTER_UPDATE has filled that cache. An answer
-- arriving in those first seconds was discarded in silence, the answer
-- throttle then kept the sender quiet for twenty more, and nothing ever asked
-- again. The roster simply never appeared, which is indistinguishable from
-- nobody having shared one.
--
-- Called from the guild roster event, and only once, and only by a client
-- that has nothing: somebody already holding a roster does not need to make
-- the whole guild answer again.
local asked = false

function RosterSync.RequestWhenReady()
    if asked or not IsInGuild() then
        return false
    end

    if SYL.Guild.GetMemberCount() == 0 then
        return false
    end

    asked = true

    if SYL.SharedRoster.HasShared() or SYL.SharedRoster.PendingOffer() then
        return false
    end

    return RosterSync.Request()
end
