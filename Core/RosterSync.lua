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

-- THE RECEIPT, and the reason a roster broadcast now gets an answer at all.
--
-- Aimee: "how do i know if the other people received my roster?" She could
-- not. Send printed that the messages had left this client and nothing ever
-- came back, so a roster that never arrived and one that landed on nine
-- screens looked identical from the sender's side. Core/RosterReceipts.lua
-- carries the full argument.
--
-- Two characters, and a client sends one of each in its life per source: when
-- it starts using somebody's roster, and when it stops. Never per broadcast --
-- that would turn one officer ticking a box into a whisper from every guildie
-- who runs the addon, every time.
local USING = "+"
local STOPPED = "-"

local frame
local listening = false

local ANSWER_THROTTLE_SECONDS = 20

-- PER ASKER, NOT ONE CLOCK FOR THE WHOLE GUILD.
--
-- It was a single timestamp, which was survivable only because the reply was
-- a broadcast: three people logging in inside twenty seconds got one answer
-- between them and it happened to reach all three. Now that an answer is
-- addressed, that same clock would answer the first and leave the other two
-- with nothing -- which is indistinguishable from nobody having shared a
-- roster, the exact failure RequestWhenReady's note is about.
local lastAnswerAt = {}

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

        -- Nobody can be using a roster that no longer exists, and the other
        -- clients have nothing new to report -- they will drop it silently.
        -- Left standing, the count would be a number about nothing.
        SYL.RosterReceipts.Clear()

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
--
-- AND IT IS WHISPERED TO WHOEVER ASKED, which is the half that was missing.
--
-- Aimee, 2026-09-07, on logging in: "as soon as i logged in i received the
-- raid team from pringles. i thought this was changed to only send on
-- demand." She had asked for nothing. She already held a roster, so her own
-- client had not even sent a request -- RequestWhenReady declines when
-- SharedRoster.HasShared. Somebody ELSE in the guild logged in without one,
-- their client asked, and this answered by broadcasting a full team to the
-- entire guild. Every client in it raised a prompt.
--
-- The manual path was fixed in 0.4.5 and this one was not, which is why it
-- reads as a regression when it is the opposite: "Send my raid team" grew a
-- window with one player, the raid team, or the guild on it, and the reply to
-- a request kept going out the old way, to everyone, for a question one
-- person had asked.
--
-- A REQUEST IS FROM ONE CLIENT AND SO IS ITS ANSWER. Announce stays a
-- broadcast and is still right for what it is -- an officer saying "here is
-- my team" on purpose, and the only way to send the empty set that tells
-- everybody a team was cleared. This is not that.
local function Answer(asker)
    if not IsSharing() or not CanSend() or not asker then
        return false
    end

    local mine = RosterSync.Own()

    if #mine == 0 then
        return false
    end

    serial = serial + 1

    for index, member in ipairs(mine) do
        SYL.SendQueue.Queue(
            PREFIX, RosterSync.Encode(serial, index, #mine, member),
            "WHISPER", asker, CanSend
        )
    end

    return true
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
-- Telling somebody you are using theirs
--------------------------------------------------------------------------

-- Whispered rather than broadcast: it is one person's answer to one person,
-- and it names a choice about somebody else's roster. Queued like everything
-- else so a login's worth of these cannot burst.
local function Confirm(target, kind, count)
    if not target or target == Author() or not CanSend() then
        return false
    end

    return SYL.SendQueue.Queue(
        PREFIX, kind .. tostring(count or 0), "WHISPER", target, CanSend
    )
end

-- Called when this client accepts somebody's roster. The count is what WE
-- took, not what they think they sent, so a disagreement between the two is
-- visible on their screen rather than averaged away.
function RosterSync.ConfirmUse(source, count)
    return Confirm(source, USING, count)
end

-- The undo, and the reason the sender's number does not just climb forever.
-- Reads the accepted source BEFORE clearing, because Clear takes it with it.
function RosterSync.StopUsing()
    local source = SYL.SharedRoster.AcceptedFrom()

    SYL.SharedRoster.Clear()

    if source then
        Confirm(source, STOPPED)
    end

    return source
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

-- EXPORTED, for the reason Receive and ReceiveReceipt already are: the
-- interesting behavior here is the ANSWERING decision -- who it goes to and
-- how often -- and that lives nowhere else. It is unreachable through the
-- event frame from a test, and it is the half that shipped wrong.
function RosterSync.OnMessage(prefix, payload, _, sender)
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

        if now - (lastAnswerAt[sender] or 0) < ANSWER_THROTTLE_SECONDS then
            return
        end

        lastAnswerAt[sender] = now

        Answer(sender)

        return
    end

    -- A receipt: somebody saying they have started or stopped using ours.
    -- Handled before Decode, which would read either as a malformed roster
    -- and answer nil -- correct, and silent, which is the whole problem this
    -- pair of messages exists to end.
    local kind, count = payload:match("^([%+%-])(%d*)$")

    if kind then
        RosterSync.ReceiveReceipt(sender, kind, tonumber(count))

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

-- Somebody has told us what they did with our roster. Exported for the same
-- reason Receive is: the interesting behavior is what the sender's screen
-- says afterwards, and that is unreachable through an event handler.
--
-- Printed as well as recorded. The count on the roster screen is what you
-- look at later; the line in chat is what tells you the press you just made
-- actually reached somebody, which is the question that started this.
function RosterSync.ReceiveReceipt(sender, kind, count)
    if not sender or sender == Author() then
        return false
    end

    local who = SYL.Utilities.ShortName(sender)

    if kind == "+" then
        SYL.RosterReceipts.Record(sender, count)

        SYL:Print(
            who .. " is using your raid team ("
            .. SYL.Utilities.Count(count or 0, "raider") .. ")."
        )
    elseif kind == "-" then
        if not SYL.RosterReceipts.Get(sender) then
            return false
        end

        SYL.RosterReceipts.Remove(sender)

        SYL:Print(who .. " has stopped using your raid team.")
    else
        return false
    end

    if SYL.RefreshMainWindow then
        SYL:RefreshMainWindow()
    end

    return true
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
            RosterSync.OnMessage(...)
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
-- WHO TO SEND TO, and the reason there is a choice at all.
--
-- Aimee: "is it sending the roster sync anytime anyone in guild who has the
-- addon logs in or logs onto another character? it seems to be so. lets
-- change this to have a button to share it with individual players, all raid
-- roster players (and their alts), or all guild."
--
-- It was, three ways over: at her own login, in answer to everybody else's
-- login, and again on every tick and role change. The login broadcast is
-- gone; what is left is this, and it only ever runs from a press.
--
-- THE WHOLE GUILD GOES OVER THE GUILD CHANNEL, one message per raider, which
-- is what that channel is for. The other two are whispers, one message per
-- raider PER PERSON -- eleven raiders to eleven teammates is 121 messages,
-- about half a minute through the queue. Worth saying out loud rather than
-- discovering, which is why Count exists below and the window prints it.
RosterSync.SCOPES = { "player", "team", "guild" }

-- Everybody on the raid team, and their alts, as names to whisper.
--
-- The alts matter and are not decoration: a roster is per character, so
-- somebody logged onto their alt is a client that will never hear a whisper
-- addressed to their main. "and their alts" was Aimee's own parenthesis.
--
-- Only characters this client can see as online, because a whisper to
-- somebody offline is not delivered and there is nothing to say about it
-- afterwards.
function RosterSync.TeamTargets()
    local names = {}
    local seen = {}
    local me = SYL.Utilities.GetPlayerFullName()

    local function Add(name)
        if not name or seen[name] then
            return
        end

        local member = SYL.Guild.GetMember(nil, name)

        if not member or not member.isOnline then
            return
        end

        if SYL.Utilities.SameCharacter(member.name, me) then
            return
        end

        seen[member.name] = true

        table.insert(names, member.name)
    end

    for key, player in pairs(SYL.Players.GetRegistry()) do
        if player.inRaidTeam then
            Add(player.fullName or player.name)

            for _, alt in ipairs(SYL.Players.GetAlts(key) or {}) do
                Add(alt.fullName or alt.name)
            end
        end
    end

    table.sort(names)

    return names
end

-- How many messages a scope actually costs, so the window can say so before
-- anybody presses it rather than after.
function RosterSync.Count(scope, target)
    local mine = #RosterSync.Own()

    if scope == "guild" then
        return mine
    end

    if scope == "player" then
        return target and mine or 0
    end

    return mine * #RosterSync.TeamTargets()
end

-- Returns how many raiders were sent and to how many people, or nil and a
-- reason. The reason is shown rather than swallowed: "nothing happened" and
-- "nobody on your team is online" look identical otherwise.
function RosterSync.SendNow(scope, target)
    scope = scope or "guild"

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

    local targets

    if scope == "player" then
        if not target then
            return nil, "pick somebody to send to first"
        end

        targets = { target }
    elseif scope == "team" then
        targets = RosterSync.TeamTargets()

        if #targets == 0 then
            return nil, "nobody on your raid team is online right now"
        end
    end

    serial = serial + 1

    if not targets then
        for index, member in ipairs(mine) do
            Send(RosterSync.Encode(serial, index, #mine, member))
        end

        return #mine, nil, 0
    end

    for _, name in ipairs(targets) do
        for index, member in ipairs(mine) do
            SYL.SendQueue.Queue(
                PREFIX, RosterSync.Encode(serial, index, #mine, member),
                "WHISPER", name, CanSend
            )
        end
    end

    return #mine, nil, #targets
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
