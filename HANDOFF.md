# Handoff — Show Us Your Loot

Rewritten 2026-08-09 for a session starting fresh. The previous version was
written when the whole review triage was open; nearly all of it has since been
done, and a patched list of finished work is worse than no list.

This file is what is **open**, what has been **decided**, and what has already
**cost somebody time**. Finished work is in `git log`, which explains it
better than a summary would.

Not shipped in the addon zip — see `.pkgmeta`.

---

## 1. Where the project stands

WoW retail addon (Interface 120007, Midnight). Records group-loot drops from
Blizzard's Loot History API, plus chat-captured loot, and answers who is due
an upgrade, who turned up, and what each boss has given.

- **Repo:** https://github.com/princess-crapbag/Show-Us-Your-Loot (public)
- **CurseForge:** project 1642383, live at **v0.2.0-alpha**
- **`main` is 17 commits ahead of that tag.** Everything after it is on GitHub
  and in Aimee's game, and has reached no user.
- 89 Lua files in the .toc, 8 test suites in `tools/`, all run before a
  release by `.github/workflows/release.yml`.

**Aimee runs the addon from a symlink**, `Interface/AddOns/ShowUsYourLoot ->
Desktop/ShowUsYourLoot`. Edits are live in game immediately; only a `/reload`
is needed. There is no build step for local testing.

### THE MOST IMPORTANT THING ON THIS PAGE

**None of the fairness maths has ever run on a real raid night.**

Three passes have now changed how attendance is counted, how droughts are
measured, what counts as an upgrade, when things are recomputed and what is on
screen. A fourth has changed *who is on the list at all* — it now defaults to
the ten players marked as the raid team. Not one of those changes has been
watched happening with real data.

The next raid is the single highest-value event for this project. Running
`/syl due` before and after that night will say more than another review pass
would. Until then, treat every number as plausible rather than correct.

### The rule about releasing

**Say plainly which of these happened.** They are one command apart and read
identically in a terminal.

- **Pushed to GitHub** — `git push origin main`. No user is affected. The
  release workflow triggers on `v*` tags only and does not even start.
- **Released to CurseForge** — a `v*` tag was pushed, a zip was built and
  uploaded, real people download it.

Releasing: write the CHANGELOG entry, bump `## Version:` in the .toc **by
hand**, commit, tag, push the tag. The `-alpha` suffix is what marks the file
Alpha rather than a full release. See CURSEFORGE.md.

---

## 2. Working here

- **`python tools/syl_check.py` after every change.** It validates
  `SYL.Module.Member` references, bare module globals, members on a file's own
  module table, block balance, .toc-against-disk and column widths.
- **It is a regex heuristic, not a parser.** It passed clean through four
  crash-level bugs in one day. A clean run means "nothing obvious", not "this
  works".
- **Check whether syl_check already covers it before writing a new tool.** A
  `test_references.py` was written and committed to catch unresolved
  `SYL.Module.Member` calls; `syl_check` had done that since before this file
  existed, and says so three lines above. It was reverted in the next commit.
- **What it still cannot see:** a local used before its declaration.
  `HideTarget`, called twenty lines above the `local function` that defined
  it, was a nil global and shipped. `luacheck` with a WoW globals definition
  would catch it and is the open tooling item (§6).
- **The tests need `lupa`**, which embeds a Lua interpreter:

  ```bash
  python -m venv .venv && .venv/Scripts/python -m pip install lupa
  ```

  There are 8: `test_duelist`, `test_incomingroster`, `test_lootmessages`,
  `test_lootsort`, `test_migrations`, `test_syncchunks`, `test_syntax`,
  `test_windowplacement`.
  Each reads its Lua straight out of the addon, so they cannot drift from the
  code, and each exits non-zero on failure. `release.yml` runs the lot before
  it builds a zip, so a failing suite blocks a release — unlike `syl_check`,
  which does not (see above).

  `test_duelist` is the one to extend when the fairness maths changes. It is
  the only test of the number the whole addon is named after.
- **Read the whole `syl_check` output, not the tail.** Its sections print in a
  fixed order and SIZE EXEMPTIONS is last, so `| tail -3` shows the exemptions
  and hides everything above them. Four files went over the limit in one
  evening behind exactly that mistake.
- **Correctness warnings now fail the run; size warnings do not.** A missing
  `SYL.Module.Member` exits 1, so `release.yml` blocks on it. Size prints under
  its own SIZE heading and exits 0 — it has an opt-out with a required reason,
  and a size limit that blocks releases is one people satisfy by deleting
  comments, which has happened here twice.
- **Four files are over the limit right now and need splitting**, all of them
  grown on 2026-08-09: `Core/Utilities.lua` 427, `UI/RosterWindow.lua` 422,
  `Core/SlashCommands.lua` 419, `UI/MainWindow.lua` 404. None is exempt and
  none should be without a real reason. `Utilities` has the obvious seam — the
  item helpers (`GetItemLevel`, `GetItemIDFromLink`, `NormalizeItemLink`,
  `GetItemNameFromLink`, `IsBindOnEquip`) are a module.
- **400-line limit is a warning, not an error.** A file opts out with
  `-- syl-check: size-exempt — reason` in its first 40 lines. Three files do,
  and each says why. **Never delete a comment to get under it** — that
  happened twice before the escape hatch existed. Splitting is usually the
  right answer; five files were split that way in one day.
- Commit identity is repo-local. `gh` is authenticated as `princess-crapbag`;
  pushes need no prompt. Never put a token in a URL.

### Write commit messages from the diff, not from the intent

The commit "Fix four crashes and three wrong numbers found by review" opens by
describing a fix to `UI/FilterDropdown.lua` in detail. It does not touch that
file. `git show --stat` lists seven files and that is not one of them.

The bug was real, was reported as fixed, and stayed broken for days — every
filter dropdown threw on click and none of them opened. Nobody noticed because
the message said otherwise.

Treat the rest of that commit's claims with the same suspicion. More
generally: check the diff before describing it.

---

## 3. What is open

### Aimee's list

Everything except these is done.

| # | Item | State |
|---|---|---|
| F7 | Roster shareable as a link | Blocked on a decision — see below |
| F9 | Droptimizer import | Cannot be done in the addon — see below |
| F10 | Re-take the screenshots | Waiting on UI work settling |

**F7 is blocked earlier than it looks, and not on the roster existing.** The
raid team is real and in use — Aimee has ten players marked, and both the due
list and the players window now default to showing only them. What is missing
is on the *server* side: `Core/DataExport.lua` sends seasons — drops, chat
loot, raid nights with their per-night rosters — and nothing else. Team
membership, roles and alt mappings live in `ShowUsYourLootDB.players`, which
is account level and never leaves the machine, so there is nothing on the
server for a link to point at.

(An earlier draft of this file said "the roster is not uploaded at all",
which read as though no roster existed. It does. Only the upload does not.)

**Both decisions are now made** (2026-08-09), and neither is urgent — Aimee:
"i do want this but it can wait until later if needed. its not urgent, just a
bonus for guildies."

1. **Yes, team, role and alt data may be uploaded.**
2. **Access is guild members, not the public.** In her words: "the link should
   be accessible to anyone who claims a character in the guild... if you have
   a guild rank you can access the link."

That second one is harder than public-read and harder than login-only, and it
is worth knowing why before starting. **Nothing on the web can verify WoW guild
membership.** The login is Discord (see the auth notes), and Discord knows
nothing about WoW characters. Battle.net OAuth could, but that is a second
identity provider to add.

The workable shape without adding one: the officer's upload *is* the roster,
so the web side already holds the list of names. A visitor logs in with
Discord, claims a character name from that list, and an officer confirms —
which makes "has a guild rank" a fact the addon uploaded rather than one the
web tried to check. The claim step is the piece that does not exist yet.

The transport to copy either way is the one `syl_upload` already uses: a
`SECURITY DEFINER` function keyed on a share token, so the tables are never
opened to `anon` and revoking is deleting a token.

**F9 cannot be an in-game import. WoW addons cannot make HTTP requests.** That
is the whole answer and it does not depend on what Raidbots exposes.
(`/reports/<id>/data.json` answers 403 rather than 404, which hints the route
exists behind bot protection; `simbot/report/<id>` returns the app shell for
any id, so it proves nothing. Neither was confirmed.)

That leaves pasting hundreds of kilobytes into a WoW edit box, or fetching it
from `tools/syl_upload.py` — which already runs outside the game and already
talks to Supabase — and joining it on the web side. Only the second works, and
it makes F9 a web feature rather than an addon one.

**F10 is bigger than one screenshot.** All seven are stale and two show a UI
that no longer exists:

- 1 "The main window, Drops tab" and 5 "Chat Loot tab" — those tabs were
  merged into a single Loot tab.
- 4 "Player statistics" — pre-dates the M+ column, and ROLLED ON is now
  ELIGIBLE.
- 6 "Settings" — no Features section; the two action rows still drawn as
  checkboxes.
- 7 "The minimap command menu" — still lists commands that were removed.
- 2 "Filters in use" and 3 "A drop's detail" — closest to current, missing the
  Ignore button and the item level line.

They are tracked in git now and excluded from the zip in `.pkgmeta`. They are
uploaded to the CurseForge page by hand, so the repo never pushes them — but
the live project page currently shows v0.1.0-alpha's interface beside a
v0.2.0-alpha download.

### The same asymmetry still exists on the personal-loot path

`Core/DueList.lua` now only lets an upgrade reset a clock if it came from
content that counts as a raid night. `MergePersonalLoot`, in the same file,
does not: `Core/PersonalLoot.lua` classifies with `GetContentType` and accepts
**raid, dungeon and scenario alike**, so a delve, a Mythic+ chest or a
Timewalking vault item still resets a raid drought.

That is arguably deliberate — the setting is called "gear taken without a roll
counts", and a vault item is real gear however it arrived. It is also
inconsistent with the drops path as of this commit, and the two feed the same
number. Decide it deliberately rather than let the discrepancy stand by
accident.

It is **off by default** (`countPersonalLoot`), so nobody is affected until
they turn it on. That is the only reason this is a note rather than a fix.

### Guild keystone sharing — built, and unproven

`Core/Keystone.lua` reads this character's key; `Core/KeystoneSync.lua` tells
the guild and remembers theirs. The three questions this section used to pose
are answered:

- **Its own feature switch**, `keystoneSharing`, not sync's. Sync sends drop
  headers to officers in your group; this sends one line to the whole guild.
  Wanting either without the other is reasonable.
- **On change, plus ask-and-answer.** A fresh login announces once and asks
  once; answers are throttled to one per 20 seconds per client so twenty
  people logging in together is not four hundred messages.
- **Keys expire after a week** and are dropped from the store on read, so it
  does not accumulate people who left the guild.

**None of it has been seen working.** It cannot be tested from one client:
the whole feature is two copies of the addon talking, and everything checked
so far is the wire format in isolation. `tools/test_keystonesync.py` covers
encode, decode and every malformed input a foreign client could send — it
caught a pattern bug that made *every* announce unparseable, which is the
failure this would otherwise have shipped with. What it cannot cover is
whether `C_MythicPlus` answers what this expects, or whether the GUILD
channel behaves as assumed.

Two people with the addon and the switch on, in the same guild, is the test.

### The dashboard — BUILT 2026-08-09, untested in game

Everything below this heading was the design. It is now code. What actually
shipped, and what did not:

**Built and working, as far as static checking can tell:**

- `Core/Dashboard.lua` — the widget registry, all on by default, saved order,
  tested against orders saved by older versions.
- `Core/LootScore.lua` — Need 100, offspec 20, greed 20, transmog 0, ranked by
  score over nights with a three-night floor. 28 assertions.
- `Core/Links.lua` — a few URLs and a copy box.
- `UI/DashboardTab.lua`, `DashboardParts.lua`, `DashboardWidgets.lua` — the
  grid and six working widgets.
- `UI/TabPanels.lua` — the five non-list tabs.
- `UI/SettingsWidgets.lua` — tick and reorder, in Settings.
- Seven tabs and a cogwheel in `UI/MainWindow.lua`; the footer is empty.

**Deliberately not built, and each says so on screen:**

- **Next raid night** is a tile that says it is waiting on the calendar.
- **Raiders, Nights, Bosses and Keys** are real tabs that open the windows
  which already answer them. The board, the calendar and the two-pane boss
  screen are designed and unbuilt. Folding six windows into one is a refactor
  touching all of them, and doing it in the same change as new widgets would
  have meant a broken dashboard and a broken roster with no way to tell which
  broke first.

**Reordering is arrows, not drag.** Dragging inside a settings panel means
cursor tracking and re-anchoring for a list of eight; arrows cannot drop a
widget anywhere ambiguous. The saved order is identical either way, so a drag
handle can replace them without touching `Core/Dashboard.lua`.

**NONE OF IT HAS RUN IN THE GAME.** The first `/reload` is still the first
time any of it draws on a real screen. What *is* established:

- All 98 files load in `.toc` order against a stubbed client
  (`tools/test_load.py`).
- All six working renderers draw against an empty database and a populated
  one, and the grid refreshes with every widget off
  (`tools/test_dashboardrender.py`). Both tests were confirmed to fail on a
  planted fault before being trusted.
- Three review passes found nine defects. All nine are fixed and in git log:
  a grid 136px taller than its frame, a cogwheel under the close button, a
  first-draw width that overran, a strip that ignored that guard, settings
  rows too short for wrapped text, a headline clipped by the row beneath it,
  loot-list chrome left on top of every panel, a tile routing to a tab label
  instead of a tab key, and the Due window left unreachable.

What no test here can reach: whether a font renders at the size assumed,
whether a colour reads, and whether any of it is usable. That is tomorrow.

### The design it was built from

Aimee rearranged the widget mocks by hand and that arrangement is the one to
build: two tall columns pinning the outer edges (Last raid night, Who is due)
with short widgets stacked between them, then a full-width Recording strip.
Eight widgets, all on by default, all switchable off, drag to reorder.

**Agreed in this session, so do not reopen:**

- Nav becomes Dashboard · Loot · Raiders · Nights · Bosses · Keys, with a
  cogwheel in the corner. Players and Roster merge into **Raiders** — the
  difference between them is the audience scope button, which already exists.
- Every widget tile is a link into its tab. The whole tile, not just the arrow.
- Keys comes **off** the dashboard and lives on the Keys tab.
- Widgets default on. Off means not built, not hidden — the rule already
  written down for features, so a change wants a `/reload`.

**Drag to reorder is agreed and is not risky if it stays dumb.** The order is a
saved list of widget names. Unknown name in the list: skip it. Widget missing
from the list: append it. Both cases then draw a working dashboard rather than
an empty one, which is what makes a list saved by an older version safe.

**"Nights dry" replaced "6 dry".** Aimee flagged the wording. The row carries a
bare number under a column header, matching the DRY NIGHTS column the Due
window already uses, so the two screens teach the same vocabulary.

**Attendance became "Who is out"** — upcoming absences rather than a sparkline
of the last eight nights. Her change and the right one: absences are actionable
tonight, a trend line is something to study.

**Links needs confirming before it is built.** Addons cannot open a browser or
write to the clipboard. The most any addon does is pop a box with the URL
selected so the user presses Ctrl-C. So that widget is three configurable URLs
and a copy box, and it is worth checking that is still wanted.

### Weighted loot value — Aimee's idea, and it replaces the drought

Raised 2026-08-09 and explicitly parked: "we will also need to work on the
scoring but thats another topic". Her shape: **a win is worth an amount, not a
yes.** Need 100%, greed around 20%, and an officer can mark a rare item at
200%.

This does not sit alongside `nightsSinceUpgrade` — it replaces it. A drought is
a binary clock; a score says how much somebody has actually taken, which is a
better answer to the same question and the one that survives an argument about
a greed win.

**Four questions, none answered, each of which changes every number:**

1. **What are offspec and transmog worth?** The two she did not name. Today
   offspec counts fully and transmog counts as nothing.
2. **Does score decay?** A Need win in March cannot weigh the same as one last
   night, or a raider is punished all tier for a single item.
3. **Is it per night attended?** Raw score punishes attendance — whoever turns
   up most accrues most. Score over nights is the fair shape, and it is the
   same trap `DueList` already avoids for droughts.
4. **Marked rare — set by whom, and does it sync?** It is an officer's
   judgement about an item, the same category as the roster data.

**Do this after the LFR run, not before.** It changes every number the addon
reports, and a wrong number cannot be told from a wrong weight if both arrive
at once.

### Requesting somebody's key — agreed, unbuilt

Press Request on a row in the Keys tab and the holder is notified, with an
Invite button on the notification. The channel exists: `Core/KeystoneSync.lua`
already has guildies talking on the `SYLKEY` prefix, and a request is one more
message shape on it.

Three things to settle first, with my recommendation:

- **Offline holders.** An addon message does not reach them. Recommend
  online-only rather than a queue.
- **Spam.** Recommend one request per key per person per hour, alongside the
  existing answer throttle.
- **Does the requester hear back?** Recommend not — "sent", and nothing more.
  Anything richer is a chat client and the game already ships one.

### Warcraft Logs has an API. It still cannot feed the calendar.

Aimee found the Web API page and asked what it gives us. Checked 2026-08-09
against the public docs.

**Two separate walls, and both stand.**

1. **The addon cannot call it.** WoW addons make no HTTP requests, to Warcraft
   Logs or anywhere. Same wall as F9. An API key changes nothing about that.
2. **There is no calendar in the API.** The v2 GraphQL guild type exposes
   `attendance(guildTagID, limit, page, zoneID)`, `members(...)` and
   `zoneRanking(zoneId:)`. No events, no signups, no schedule. A forum thread
   asking for an attendance CSV endpoint suggests export is deliberately thin.

**And the page she linked is not a schedule.** `warcraftlogs.com/guild/calendar/<id>`
renders as a *Report* Calendar — a grid of past uploaded logs. Even with an API
it would answer "when did we raid", not "when are we raiding and who signed
up". (Not confirmed directly: the page is behind a bot check, which was not
bypassed. The title of another guild's public calendar is the evidence.)

So **the next-raid-night widget cannot come from Warcraft Logs**, and the two
sources named earlier are still the only two: `C_Calendar` in game, or an
officer typing the schedule in.

**What the API is genuinely good for, later.** `tools/syl_upload.py` already
runs outside the game and already talks to Supabase, so it could also pull
guild attendance from logs as an independent cross-check of what the addon
recorded. Worth knowing that **the addon's own attendance is the better
record**: it reads the group roster at every pull, so it counts the healer who
never appeared in a log segment, and it does not depend on anybody remembering
to upload.

**If that is ever built, two practical notes.** `attendance` is v2 only, and v2
needs an OAuth2 client — id and secret from "manage your V2 clients", not the
V1 key. Rate limit is 18,000 points/hour, which is generous at guild scale.

**Getting anything back into the addon** has exactly one honest path: an
external tool writes a generated Lua file into the addon folder, which the
addon loads at startup. RaiderIO ships its whole dataset that way. It needs
the tool run and a `/reload`, and it is never live.

**The V1 key in that screenshot is burned** and should be reset — it was
readable in an image pasted into a chat.

### The calendar is the blocking piece

Two widgets need it and nothing else does: **Next raid night** and **Who is
out**. Both come from `C_Calendar` — guild events plus signup status.

Nothing in the addon has ever read a calendar, so this is a new event source
rather than a rearrangement, and `C_Calendar` has real quirks: it needs the
month opened before it returns anything, and signup lists arrive separately
from events. The alternative is an officer typing the next raid by hand, which
is an afternoon's work and always correct but never updates itself.

**Aimee has asked for the calendar**, so the direction is settled.

### Screen-by-screen notes from the design pass

Mockups of all six tabs exist and are agreed. Points that came out of review
and would otherwise be lost:

- **Raiders** merges Players and Roster. The union is fourteen columns and does
  not fit; the cut is role as a chip on the name, "alt of" as a suffix, no Team
  column at team scope, and Eligible/Mog/alt list behind the row click. The
  word **"dry" is rejected** — the column is *Waiting* and rows carry their
  unit, "6 nights" rather than "6".
- **Nights** is a month calendar with a week toggle, not a table with a box on
  top. Past nights come from what the addon recorded; future ones from
  `C_Calendar`, so a guild that does not keep events sees an empty half-month
  and the screen should say so rather than look broken.
- **Bosses** is two panes — a fixed boss rail and that boss's loot table with
  drop counts, defaulting to items that have **not** dropped. The item list is
  the Encounter Journal, which the `lootTables` feature already reads, so this
  needs no new source. Open question: the Journal lists what a boss can drop
  for *any* spec, so "never dropped" includes items nobody in your raid can
  use. Filtering to your raid's classes is a decision, not a given.
- **Loot** keeps its tick column. It was in the addon and missing from the
  first mock, which is the sort of thing a mock must not quietly do.

### Keys tab, later — Aimee's words: "this part is not urgent"

The Keys tab should show more keys than the dashboard widget did, sortable by
**dungeon, key level and player**. Sorting is `SYL.SortHeader`, which every
other list already uses, so this is a list view rather than new machinery. The
data arrives from `Core/KeystoneSync.lua`.

### Strategy — none of this is started

Reviewer arguments, unchanged except where noted. **It is a menu, not a plan.**

| # | Item |
|---|---|
| E1 | **Trade-window advisor.** On a win, tell the winner who rolled Need and lost, with their droughts and time remaining. **Unanimous top pick, and it has no cold start** — the roll list is complete on the very first drop, so it works on install night before any history exists. RCLootCouncil's `Modules/TradeUI.lua` is the reference: `TRADE_SHOW`, `TRADE_CLOSED`, `TRADE_ACCEPT_UPDATE`, `UI_INFO_MESSAGE` watching `LE_GAME_ERR_TRADE_COMPLETE`, target from `TradeFrameRecipientNameText:GetText()`, 5-minute timer for the two-hour window |
| E2 | **Trade tracking** — credit the recipient, not the winner. Today every traded item is two errors |
| ~~E3~~ | ~~Store item level~~ — **done**. Recorded on every drop and shown in the drop detail. What the fairness maths does with it is still open, and is the interesting half |
| E4 | **Scope every number to the raid team.** `RaidTeam` exists and feeds nothing that matters |
| E5 | **Something that reaches other people** — there is no `SendChatMessage` anywhere. Currently a private notebook |
| E6 | **Reposition.** The unique asset is the pass data: every eligible player and what each chose. Nothing else on the market has it. Suggested line: *"Group Loot remembers who won. This remembers who passed."* |
| E7 | Reconsider **All Rights Reserved** — tells an officer they are stranded if the author stops |
| E8 | **Sync backfill handshake.** The transport can now carry it (F8) |
| E9 | Screenshots show nothing differentiated; the end-of-night summary is missing |
| E10 | The alpha warning appears in the README, the CurseForge description **and** the .toc |

### The commercial risk nobody had named

A guild running Group Loot has, by definition, **chosen not to have a loot
process.** Handing them fairness analytics invites drama they opted out of. E1
is the proposed answer: make the history a means to a decision people already
need, rather than an end in itself.

### NOTES.md phases

Phases 2, 3, 5 and 6 were blocked on sync being unable to send more than a
drop header. **That block is gone** — see F8 in §4 — but nothing has been
built on top of it, and doing so means deciding to transmit more about people
than the addon currently does.

---

## 4. Decisions already made

These were argued once. Reopen them deliberately if at all, but do not
rediscover them.

**`countPersonalLoot` defaults off, and migrates existing installs off.** One
client only ever sees its owner's solo loot — nobody claims a vault standing
next to the officer — so counting it counted almost entirely the officer's own
gear, resetting their drought weekly and nobody else's. It put them at the
bottom of a list they wrote. When on, only gear received while grouped counts,
which is the largest subset where coverage is even.

**Gear means epic and above, and never a tabard or shirt.** Rare is levelling
gear; a blue ring from Dornogal was resetting a Mythic raider's drought.

**Crafted items never count as gear received.** A create line says an item was
made, never that the maker kept it, and a wrongly-counted crafter drops off
the due list for the tier.

**A night is one night however many difficulties it passed through.** Fixed
where nights are counted, not by merging the sessions, so the record of what
happened stays intact and existing history corrects itself.

**F2 is an ignore flag, not a delete.** It does everything a delete would do
to the numbers and stays reversible. The addon's one promise about your data
is that it does not remove things.

**F8 is transport only.** Payloads of any size now split and reassemble. What
is actually sent is unchanged — still drop headers, still no roll lists.
Widening that is a decision to take on purpose, not to inherit from a roomier
pipe.

**Features are off means not built.** `Core/Features.lua` holds five toggles
(raid buffs, Raider.IO, loot tables, sync, developer tools). A disabled
feature registers no events, creates no frames and puts nothing in the menu.
The price is that a change needs a `/reload`, and the toggle says so.

**D1–D6 were kept, not cut.** Five reviewers wanted them deleted; they became
default-on toggles instead. "Some guilds do not want this" and "nobody wants
this" are different claims and only the first was argued.

**Lists of people default to the raid team, then the guild, then everyone.**
`Core/Audience.lua`, shared by the due window, the players window and
`/syl due`. The due list is built from raid-night rosters, which are whoever
was in the group — a pug seen once and given nothing outranks a raider of two
years, because one night without an upgrade is still a drought. The default is
computed rather than written down: team only if a team is marked, guild only
if in one. A correct default that opens an empty window is not a correct
default. Team membership is per character but every list folds alts, so the
test is "any of this person's characters", or marking somebody's raiding alt
would hide them.

**The addon does not talk unless asked.** `announceCaptures` defaults off and
migrates existing installs off; the load banner in `Main.lua` is gone, since
`ADDON_LOADED` prints a better line a moment later. It had already been
narrowed once from every quality down to gear, which was the wrong axis: the
problem was not which items it announced but that a recording tool was
narrating at all. Everything it said is in the loot list, and it is recorded
either way.

---

## 5. Traps that have already bitten

Each of these cost real time.

- **Retail dungeons and M+ award personal loot.** There are no need/greed
  rolls, so `C_LootHistory` records nothing and the drops list is correctly
  empty of dungeons however many keys were run. Dungeon gear arrives as chat
  loot. This looked exactly like a capture bug.
- **Winning a roll also prints a chat loot line**, so `season.loot` overlaps
  `season.drops` almost entirely inside a raid. Any merge must subtract the
  overlap or it double-counts every raid drop.
- **`EJ_GetEncounterInfoByIndex` takes a `journalInstanceID` and ignores
  it** — the encounter list comes from the *current selection*, so the
  instance must be selected first.
- **`ENCOUNTER_START` gives a dungeonEncounterID; `EJ_SelectEncounter` wants a
  journalEncounterID.** Different numbers for the same boss, and passing the
  wrong one returns another boss's loot rather than failing.
- **The journal's tier walk reads raid instances only.** A dungeon boss can
  never be in it, so searching for one walks all thirteen tiers and fails.
  Misses are remembered now; they were not, and it froze the game per hover.
- **The packager rewrites the .toc version in the zip only.** The working copy
  is untouched, so a symlinked install reports whatever was last typed there.
- **`GITHUB_TOKEN` is read-only by default.** v0.1.0-alpha uploaded to
  CurseForge successfully and *then* failed creating the GitHub release. **A
  red workflow does not mean nothing shipped.** Fixed since, and v0.2.0-alpha
  went green.
- **`itemEquipLoc` is not a reliable "is this gear" test.** Some
  non-equippable items report `INVTYPE_NON_EQUIP_IGNORE`. Item class is.
- **A migration must guard on its own version, not on `DATABASE_VERSION`.**
  Written the second way it re-fires on every later schema bump and overrules
  a choice the user made after it ran. `tools/test_migrations.py` caught
  exactly this.
- **Blizzard's format strings carry grammar directives** — `|1을;를;`,
  `|4item:items;`, `|3-1(...)` — which are resolved before the line reaches
  chat. A pattern built from a format string must strip them or it matches
  nothing.

---

## 6. Tooling

`syl_check.py` gained two rules in two days, both written after the fault
rather than before, and both for mistakes a Lua parser would simply refuse to
load:

- bare `Module.Member` where the file never made `Module` a local;
- `Module.Member` on a file's *own* module table where the member is never
  assigned anywhere.

**The open item is `luacheck` with a WoW globals definition.** It parses
instead of pattern-matching, and it catches the class both of those rules were
written for plus the one neither covers — a local used before its declaration.
The cost is a Lua toolchain and a first-run triage across 83 files. Note the
ground has moved: installing `lupa` for the tests means there **is** a Lua
interpreter on this machine now.

---

## 7. Where the finished work is

`git log` since 2026-08-08, newest first. The messages explain the reasoning
and what was rejected on the way, which is why `.pkgmeta` keeps them out of
the user-facing changelog.

- `a09b508` screenshots tracked and excluded from the zip
- `7e7fa6e` chunked sync transport; F7 and F9 answered rather than guessed
- `e1bb3bb` feature registry, non-overlapping window layout
- `b45dc15` sortable list, ignore flag, hide-all-copies, D7/D8/D9 cuts
- `35acdf1` personal-loot default migrated for existing installs
- `1e32473` release 0.2.0-alpha
- `4059149` the filter dropdowns, which had never opened
- `e99146f` the B and C lists — performance and UX
- `d424bf2` the A list — every wrong number and crash the review found
