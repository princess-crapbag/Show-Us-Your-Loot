# Handoff — Show Us Your Loot

Rewritten 2026-08-09, late, after the session that built the dashboard. The
previous version had grown to 638 lines carrying design notes for things since
built — the same fault it was rewritten for that morning.

This file is what is **open**, what has been **decided**, and what has already
**cost somebody time**. Finished work is in `git log`, which explains it better
than a summary could.

Not shipped in the addon zip — see `.pkgmeta`.

---

## 1. Where the project stands

WoW retail addon (Interface 120007, Midnight). Records group-loot drops from
Blizzard's Loot History API plus chat-captured loot, and answers who is due an
upgrade, who turned up, and what each boss has given.

- **Repo:** https://github.com/princess-crapbag/Show-Us-Your-Loot (public)
- **CurseForge:** project 1642383, live at **v0.2.0-alpha**
- **`main` is 44 commits ahead of that tag.** All of it is on GitHub and in
  Aimee's game. **None of it has reached a user.**
- 105 Lua files in the `.toc`, 17 test suites in `tools/`.

**Aimee runs the addon from a symlink**, `Interface/AddOns/ShowUsYourLoot ->
Desktop/ShowUsYourLoot`. Edits are live in game immediately; only a `/reload`
is needed. There is no build step for local testing.

### THE TWO MOST IMPORTANT THINGS ON THIS PAGE

**1. The dashboard has drawn, and Aimee confirmed it works.** Loaded 2026-08-09
late. That was the top item on this page for a day and it is closed. What she
reported back became the work below: several tabs were placeholders, and not
every list of people honoured the raid team / guild / everyone order.

**The three new tabs have NOT drawn.** Raiders, Bosses and Nights were all
built after she went to bed. Static checks and 17 suites pass, which
establishes that they load, that every path runs, and that the numbers agree
with each other — not that a bar is legible, that the average line lands where
the eye expects, that 16 rows fit the space they were measured for, or that a
calendar cell is big enough to read. **Every layout constant in them was
measured against a 900×596 window on paper and has never been seen.** Expect
to spend the first ten minutes nudging sizes.

**2. The fairness maths has still never run on a real raid night.** Five passes
have now changed how attendance is counted, how droughts are measured, what
counts as an upgrade, who is on the list at all, and replaced the drought with
a weighted score. Not one has been watched with real data. Treat every number
as plausible rather than correct.

The next raid remains the highest-value event for this project.

### The rule about releasing

**Say plainly which of these happened.** They are one command apart and read
identically in a terminal.

- **Pushed to GitHub** — `git push origin main`. No user is affected. The
  release workflow triggers on `v*` tags only and does not start.
- **Released to CurseForge** — a `v*` tag was pushed, a zip was built and
  uploaded, real people download it.

Releasing: write the CHANGELOG entry, bump `## Version:` in the `.toc` **by
hand**, commit, tag, push the tag. See CURSEFORGE.md.

**The addon is invisible on CurseForge, and this is not a moderation problem.**
Verified against the live site 2026-08-09: searching the exact phrase returns
six unrelated addons and not this one, and the project's own Files tab reads
"No Results" until "Show alpha files" is ticked. All three uploads are type
Alpha, and CurseForge indexes projects by their latest non-alpha file.
**Shipping a tag without the `-alpha` suffix fixes both.** Aimee wants that
after the LFR test.

---

## 2. Working here

### The checks

- **`python tools/syl_check.py` after every change**, and **read the whole
  output, not the tail.** Sections print in a fixed order with SIZE EXEMPTIONS
  last, so `| tail -3` shows the exemptions and hides everything above them.
  Four files went over the size limit in one evening behind exactly that.
- **Correctness warnings fail the run; size warnings do not.** A missing
  `SYL.Module.Member` exits 1, so `release.yml` blocks on it — that is the
  shape a rename leaves behind when a call site is missed, and Lua only finds
  it at the moment of the call. Size exits 0, because a size limit that blocks
  releases is one people satisfy by deleting comments, which has happened
  twice.
- **It is a regex heuristic, not a parser.** A clean run means "nothing
  obvious". It passed clean through four crash-level bugs in one day.
- **Check whether `syl_check` already covers it before writing a new tool.** A
  `test_references.py` was written to catch unresolved `SYL.Module.Member`
  calls; `syl_check` had done that all along. Reverted the next commit.

### The tests

They need `lupa`, which embeds a Lua interpreter. **It is already installed on
the system python on this machine** — `python tools/test_load.py` runs as is.
There is no `.venv`, despite what this file used to say; if it is ever needed
again:

```bash
python -m venv .venv && .venv/Scripts/python -m pip install lupa
```

Seventeen suites. Each reads its Lua straight out of the addon, so none can
drift from the code, and each exits non-zero on failure. `release.yml` runs the
lot before building a zip, so a failing suite blocks a release.

The four that matter most:

- **`test_load`** — every file in the `.toc` loads, in order, against a stubbed
  client. Catches load-order faults and file-scope nils, which are not syntax
  errors and do not appear until the game loads the addon.
- **`test_dashboardrender`** — calls all six renderers against a fresh database
  and a populated one, and refreshes the grid with every widget off. It
  deliberately bypasses the `pcall` the addon wraps renderers in, which would
  otherwise let a broken renderer pass as "could not be drawn".
- **`test_lootscore`** and **`test_duelist`** — the fairness maths. Extend
  these whenever it changes. They are the only tests of the numbers this addon
  is named after.
- **`test_raiderspanel`** — builds the Raiders board and refreshes it empty,
  populated, and with the scope hiding everybody, then renders the detail pane.
  It asserts the breakdown **sums to the score on the bar**, which is the one
  way that screen can be wrong while looking fine.
- **`test_audience`** — the raid team / guild / everyone order, the computed
  default's fall-through, and the three surfaces that used to ignore it.
- **`test_bossespanel`** — **counts calls to `LootTable.GetMissing`** rather
  than trusting that the journal walk stays behind its button. A panel that
  quietly walked it would look completely normal and freeze the game.
- **`test_nightspanel`** — the calendar arithmetic, and that two sessions on
  one night stay one night. Its past-midnight fixture is a full 24 hours apart
  on purpose: a realistic gap lands on the same day in some timezones and not
  others, so the first version passed or failed depending on the machine.

**Every test written this session was confirmed to fail on a planted fault
before being trusted.** Do the same. A test that has never failed proves
nothing.

### Four files are over the size limit

None is exempt and none should be without a real reason:

- `UI/MainWindow.lua` 517
- `Core/SlashCommands.lua` 509
- `Core/Utilities.lua` 439
- `UI/RosterWindow.lua` 422

`Utilities` has the obvious seam: the item helpers (`GetItemLevel`,
`GetItemIDFromLink`, `NormalizeItemLink`, `GetItemNameFromLink`,
`IsBindOnEquip`) are a module — but it is 12 call sites across 8 files, and the
test suites load those modules individually, so it ripples into `tools/` too.
`SlashCommands` could shed the roster and link commands. **Never delete a
comment to get under the limit** — that happened twice before the escape hatch
existed.

**A new screen does not have to grow `MainWindow`.** `UI/TabPanels.lua` builds
the panels and hands back `mode -> panel`, so three whole tabs were added
without touching `MainWindow` by a line. The size limit is not what stands
between here and the remaining tab.

**A panel is two files, not one.** Raiders, Bosses and Nights each went over
400 lines as a single file and each split the same way: the grid or the rail in
one, the detail pane in the other. Assume that shape from the start rather than
writing one file and splitting it afterwards.

### Write commit messages from the diff, not from the intent

The commit "Fix four crashes and three wrong numbers found by review" opens by
describing a fix to `UI/FilterDropdown.lua` in detail. It does not touch that
file. The bug was real, was reported as fixed, and stayed broken for days —
every filter dropdown threw on click. Nobody noticed because the message said
otherwise. Check the diff before describing it.

Commit identity is repo-local. `gh` is authenticated as `princess-crapbag`;
pushes need no prompt. Never put a token in a URL.

---

## 3. What is open

**The list below is the agreed order of work**, built 2026-08-09 from what
Aimee asked for after loading the addon, plus the strategy items recovered from
the pre-rewrite version of this file. Numbered so they can be referred to.
Items 2 and 5 are done; they are left in place with what was built, because the
order is the argument and deleting the finished ones hides it.

### Tier 1 — what she asked for after loading it

1. **The route panels were stubs.** Raiders, Nights, Bosses and Keys each drew
   a heading, a blurb and a button opening the old window. **Three of the four
   are DONE** and only Keys still routes.

   - **1a Raiders — DONE.** `UI/RaidersPanel.lua`, `UI/RaidersDetail.lua`.
   - **1b Bosses — DONE.** `UI/BossesPanel.lua`, `UI/BossLoot.lua`. Boss rail
     plus that boss's loot table, defaulting to what has *not* dropped. The
     any-spec caveat is printed on the pane rather than left in a comment:
     the Journal lists what a boss can drop for every specialisation, so
     "never dropped" includes items nobody in the raid can use.
   - **1d Nights — DONE except the accent.** `UI/NightsPanel.lua`,
     `UI/NightStats.lua`, `Core/NightIndex.lua`. Month grid with a week
     toggle, nights shaded with their kill count, one stat panel below. The
     **next** raid night is still not drawn — that is item 3, not an oversight,
     and the caption says so.
   - **1c Keys — STILL A ROUTE.** The only one left. The sortable list is
     easy; the request flow is the rest of it and is fully specified (role
     picker on the ask; approve, tentative, deny, whisper, dismiss for the
     holder; a "requests to you" list so a dismissed popup is never a lost
     request; per account throughout; online only; only Denied gets "Ask
     again"; cleared at reset in the existing sweep). **It sends messages
     between players, so like officer sync it needs a second client more than
     it needs code** — which is why it was left rather than guessed at.
2. **DONE. Audience scope on every list of people.** Three surfaces never asked
   `Core/Audience.lua`: the Readiness tile (called `RaidTeam.Filter` directly,
   so it was the one list that could not widen), the end-of-night summary (swept
   the whole roster, then pointed at `/syl due`, which is scoped — it said nine
   where the list showed three), and the player filter dropdown (plain
   alphabetical, so a pug sat above the raid team).

   The dropdown is **ordered, not filtered**, and that is the call worth
   challenging: it drives the loot list, which is a record of drops rather than
   a list of people, so removing a pug's name would leave a visible row no
   filter could reach. Keys is exempt, per Aimee and per `UI/MainWindow.lua`.

   The raid, boss and player-detail screens turned out **not** to need this —
   they carry no list of people. Raid nights shows `rosterCount`, which is a
   historical fact about who was there and must stay unscoped.

### Tier 2 — the placeholder that needs a data source

3. **The calendar.** Two widgets need it and nothing else does. See below.
4. **"Who is out" is not built at all** — designed, but absent from the widget
   registry rather than placeheld. Same blocker.

### Tier 3 — the strategy items never got to

Recovered from the pre-rewrite file, section E. E4 became `Core/Audience.lua`;
item 2 above finished it. E5 is effectively done — keystone sharing added the
first `SendChatMessage` in the addon.

5. **DONE, as part of 1a. E3 — the score breakdown.** `LootScore.Add` took a
   weight, so a total had no route back to the wins behind it. It takes the
   roll state now and `LootScore.Breakdown` reads it back. *(Storing item level
   on each record — the other half of E3 — is still open, and still the cheap
   change that turns item-count fairness into gearing fairness.)*
6. **E1 — the trade-window advisor.** The unanimous reviewer top pick, and the
   only feature on this list with **no cold start**: the roll list is complete
   on the first drop, so it works on install night with no history. On a win,
   tell the winner who rolled Need and lost, with droughts and time remaining.
   RCLootCouncil's `Modules/TradeUI.lua` is the reference — `TRADE_SHOW`,
   `TRADE_CLOSED`, `TRADE_ACCEPT_UPDATE`, `UI_INFO_MESSAGE` watching
   `LE_GAME_ERR_TRADE_COMPLETE`, target from
   `TradeFrameRecipientNameText:GetText()`, 5-minute timer for the two-hour
   window. It is also the answer to the risk in §4: a guild on Group Loot chose
   not to have a loot process, and this makes the history serve a decision they
   already have to make.
7. **E2 — trade tracking.** Credit the recipient, not the winner; today every
   traded item is two wrong numbers. Falls out of item 6 nearly free.
8. **E8 — sync backfill, or turn sync off.** Officer sync still sends drop
   headers only, so synced records sit outside the fairness maths as `partial`.
   Needs two clients more than it needs code.
9. **E6 — reposition.** The unique asset is the pass data. Suggested line:
   *"Group Loot remembers who won. This remembers who passed."*
10. **E7 — reconsider All Rights Reserved.** Tells an officer they are stranded
    if the author stops. Aimee's call, no code.

### Tier 4 — started here and unfinished

11. **F7 — roster as a link.** Both decisions made; `Core/DataExport.lua` still
    sends seasons only, so there is nothing on the server to point a link at,
    and the Discord claim step does not exist. Not urgent, her words.
12. **F9 — Droptimizer.** Web-side only; the addon makes no HTTP requests.
13. **Four files over the size limit** — `MainWindow` 517, `SlashCommands` 509,
    `Utilities` 439, `RosterWindow` 422. **This is no longer blocking the tab
    work**: `TabPanels.CreateAll` is the seam, and Raiders was added without
    `MainWindow` growing by a line. `Utilities` still has the obvious seam —
    the five item helpers are a module — but it is 12 call sites across 8 files
    and the test suites load those modules individually, so it ripples further
    than it looks. Never delete a comment to get under the limit.
14. **`luacheck` with WoW globals.** The one open tooling item: catches a local
    used before its declaration, which nothing here covers and which shipped
    once as `HideTarget`. `lupa` is installed, so there is a Lua interpreter.
15. **The personal-loot asymmetry.** Dormant, not wrong — see §4.
16. **NOTES Phases 2, 3, 5, 6.** Phase 6 is item 7.

### Tier 5 — shipping

17. **The LFR run**, with `/syl due` before and after.
18. **Release from alpha** once the maths has been watched. Also fixes the
    CurseForge invisibility.
19. **F10 — re-take the screenshots.** All seven stale. Do this last.

### Open decisions from tonight, both small

- **Is the due window superseded?** The Raiders board answers the same question
  better, but `UI/DueWindow.lua` has a recency toggle the board does not. Making
  the tab a panel deleted its last route, so `/syl due window` was added rather
  than leaving two files loading and unreachable. If the board is enough, delete
  `DueWindow.lua` and `DueRows.lua` and drop that subcommand.
- **The players and roster windows** are still reachable only via `/syl players`
  and `/syl roster`. Folding them into the Raiders tab is the rest of item 1a.

### The calendar — the one real blocker

Two dashboard widgets need it and nothing else does: **Next raid night** and
**Who is out**. Next raid night currently draws a tile saying it is waiting on
the calendar, which is honest rather than blank.

`C_Calendar` is the only in-game source. It needs the month opened before it
returns anything, and signup lists arrive separately from events.

**Warcraft Logs cannot feed this, and having an API key does not change that.**
Checked against the public docs 2026-08-09. Two walls: an addon makes no HTTP
requests at all, and the v2 guild type exposes `attendance`, `members` and
`zoneRanking` — no events, no signups, no schedule. The page Aimee linked is a
*Report* calendar, a grid of past uploaded logs, so even via an API it would
answer "when did we raid" rather than "when are we raiding". Her V1 key was
screenshotted into a chat and has been reset.

The alternative is an officer typing the schedule in. Recommendation: both —
read the in-game calendar, allow a manual override.

### Designed and agreed, not built

The mockups are settled and signed off. Each of these is a real tab today that
opens the window already answering it, and says so on the panel.

- ~~**Raiders**~~ — **BUILT**, `UI/RaidersPanel.lua` and `UI/RaidersDetail.lua`.
  A board, one bar per raider, length = loot taken per night, line at the raid
  average, detail pane on click. **Aimee rejected two table designs before
  this; do not go back to a table.** The pane's "where the score came from" is
  the screen somebody stands at when they disagree with their number, so it
  shows the arithmetic and is asserted to sum to the bar beside it. Not yet
  drawn by the real client.
- **Nights** — a month calendar with a week toggle, past nights shaded with
  their kill count, the next one accented. Clicking a day fills one dense stat
  panel below. The table that used to sit under it was deleted: it repeated the
  grid.
- **Bosses** — two panes, a fixed boss rail and that boss's loot table with
  drop counts, defaulting to items that have **not** dropped. Needs no new data
  source; the Encounter Journal is already read by the `lootTables` feature.
  Open question: the Journal lists what a boss can drop for *any* spec, so
  "never dropped" includes items nobody in your raid can use.
- **Keys** — a sortable list, plus requesting somebody's key. The request flow
  is fully specified: a role picker on the ask; approve, tentative, deny,
  whisper and dismiss for the holder; a "requests to you" list so a dismissed
  popup is never a lost request; per account throughout, so two people asking
  for the same key never learn about each other; online only; only Denied gets
  an "Ask again" button. Requests clear at reset, in the sweep that already
  drops stale keys.

**Folding the six separate windows into the main window is the refactor behind
all of this**, and it was deliberately kept out of the dashboard change: a
broken dashboard and a broken roster at once, with no way to tell which broke
first.

### F7 — sharing the roster as a link

Both decisions are made and neither is urgent. Aimee: "it can wait until later
if needed. its not urgent, just a bonus for guildies."

1. **Yes**, team, role and alt data may be uploaded.
2. **Access is guild members**, not the public: "if you have a guild rank you
   can access the link."

The second is harder than either alternative. **Nothing on the web can verify
WoW guild membership.** The login is Discord, which knows nothing about WoW
characters. The workable shape without adding Battle.net OAuth: the officer's
upload *is* the roster, so a visitor logs in with Discord, claims a name from
that list, and an officer confirms. The claim step does not exist.

`Core/DataExport.lua` sends seasons and nothing else, so there is still nothing
on the server for a link to point at.

### F9 — Droptimizer import

**Cannot be done in the addon.** WoW addons make no HTTP requests. That is the
whole answer and it does not depend on what Raidbots exposes. The only route is
`tools/syl_upload.py`, which already runs outside the game, joining the data on
the web side — which makes it a web feature.

### The personal-loot asymmetry

`Core/DueList.lua` and `Core/LootScore.lua` both count only content that would
have counted as a raid night. `Core/PersonalLoot.lua` classifies with
`GetContentType` and accepts raid, dungeon and scenario alike. Nothing reads it
for the drought any more, so this is dormant rather than wrong — but if
personal loot is ever wired back into a number, that is where it will disagree.

### Tooling

**`luacheck` with a WoW globals definition** remains the open item. It parses
rather than pattern-matching and catches the one class nothing here covers: a
local used before its declaration. `HideTarget` was called twenty lines above
the `local function` that defined it, was a nil global, and shipped. Note that
`lupa` is installed now, so there is a Lua interpreter on this machine.

---

## 4. Decisions already made

Argued once. Reopen them deliberately if at all, but do not rediscover them.

**Weighted loot value replaced the drought.** Need 100, offspec 20, greed 20,
transmog 0 with no deduction, no decay. The ranking is **Share** — score
divided by raid nights attended, lowest first — which is the whole of "someone
with perfect attendance should be valued higher for needing loot than someone
who is only there half the time", with no separate attendance bonus. Two
raiders on 240 points are not equal if one earned it over thirteen nights and
the other over seven.

**Nobody under three nights is ranked.** Share is score over nights, so a trial
with one night and no loot scores zero and would top the list ahead of raiders
who have been there all tier. They are listed with the reason instead. Three
matches the "recent raiders" window already in use.

**The star is a label worth nothing.** Aimee dropped the 200% rare multiplier
for an officer marking a won item with a star. It changes no total — it is the
thing you point at in an argument rather than the thing that wins it.

**A drought, and now a score, is reset only by** a Need or offspec win, on a
bind-on-pickup item, from group loot, on a night that counted as a raid night.
The vault, Mythic+ chests, the catalyst, delves, personal loot handed out
mid-raid, and BoEs are all recorded and all excluded.

**Timewalking, Story, Event, Follower and Timewalking LFR are not raid nights**
on either side of that sum. Applying the exclusion to nights but not to wins
let a Timewalking raid wipe a two-month drought.

**Ordinary LFR is group loot and counts fully.** It was reverted from personal
loot when group loot came back to raids. An earlier claim in this file that LFR
awards personal loot was wrong.

**The player filter dropdown is ordered by that scope, not filtered by it.**
Every other people-list narrows; this one re-orders and keeps everybody. It
drives the loot list, and the loot list is a record of drops rather than a list
of people — a pug's win is a row already on screen, so dropping their name
would leave a visible row that no filter could reach. Aimee said "besides the
keys tab everything should focus on that order", and ordering is the reading
that does not break the list underneath it. Open to challenge.

**Lists of people default to raid team, then guild, then everyone.**
`Core/Audience.lua`. The default is computed rather than written down — team
only if a team is marked, guild only if in one — because a correct default that
opens an empty window is not a correct default. Team membership is per
character but every list folds alts, so the test is "any of this person's
characters".

**The addon does not talk unless asked.** `announceCaptures` defaults off and
migrated existing installs off; the load banner is gone.

**Dates are MM-DD-YYYY everywhere.** Two ISO strings are deliberately
untouched: RaidSession's night key and the season id. Both are identifiers
built by concatenation, and reformatting either would re-key every night
already recorded.

**Every record must have an id.** Selection is keyed by it, so a record without
one draws a checkbox that does nothing and no button can reach. Backfilled at
login, unconditionally, because the guard is the nil itself.

**Sharing anything is off by default and has its own switch.** Officer sync
sends drop headers to officers inside your group; keystone sharing sends one
line to the whole guild. Wanting either without the other is reasonable, so
they are separate features — and a test asserts that with keystone sharing off
the addon sends nothing and does not even register its prefix.

**Keys expire at the client's own weekly reset**, read from
`C_DateAndTime.GetSecondsUntilWeeklyReset`. Aimee's realm is Tuesday;
hardcoding a weekday would be wrong for most installs.

**Dashboard widgets default on, and off means not built.** Same rule as
features, so a change wants a `/reload`. The saved order is a dumb list of
names: an unknown name is skipped, a missing widget is appended, so an order
saved by an older version still draws a working dashboard.

**Reordering is arrows, not drag.** Dragging inside a settings panel means
cursor tracking and re-anchoring for a list of eight. The saved order is
identical either way, so a drag handle can replace them without touching
`Core/Dashboard.lua`.

**Features are off means not built, not hidden.** `Core/Features.lua` holds six
toggles. A disabled feature registers no events, creates no frames and puts
nothing in the menu.

**F2 is an ignore flag, not a delete.** The addon's one promise about your data
is that it does not remove things.

**F8 is transport only.** Payloads split and reassemble; what is sent is
unchanged.

---

## 5. Traps that have already bitten

Each of these cost real time.

### The client

- **Retail dungeons and M+ award personal loot.** No need/greed rolls, so
  `C_LootHistory` records nothing and the drops list is correctly empty of
  dungeons however many keys were run. This looked exactly like a capture bug.
- **Winning a roll also prints a chat loot line**, so `season.loot` overlaps
  `season.drops` almost entirely inside a raid. Any merge must subtract the
  overlap or it double-counts every raid drop.
- **`EJ_GetEncounterInfoByIndex` takes a `journalInstanceID` and ignores it** —
  the encounter list comes from the *current selection*, so the instance must
  be selected first.
- **`ENCOUNTER_START` gives a dungeonEncounterID; `EJ_SelectEncounter` wants a
  journalEncounterID.** Different numbers for the same boss, and the wrong one
  returns another boss's loot rather than failing.
- **The journal's tier walk reads raid instances only.** A dungeon boss can
  never be in it. Misses are remembered now; they were not, and it froze the
  game per hover.
- **`itemEquipLoc` is not a reliable "is this gear" test.** Some
  non-equippable items report `INVTYPE_NON_EQUIP_IGNORE`. Item class is.
- **Blizzard's format strings carry grammar directives** — plural and case
  markers resolved before the line reaches chat. A pattern built from a format
  string must strip them or it matches nothing.
- **`SetBackdrop` lives on `BackdropTemplateMixin`, not on plain frames.** Any
  `CreateFrame` whose result reaches `Theme.StyleWindow` must pass
  `"BackdropTemplate"`. One that did not was a crash on first click and leaked
  a frame per attempt.

### This addon

- **A migration must guard on its own version, not on `DATABASE_VERSION`.**
  Written the second way it re-fires on every later schema bump and overrules a
  choice the user made after it ran.
- **A tab's key is not its label.** A dashboard tile carried `tab = "loot"`;
  the key is `"feed"`. Clicking it selected a mode no tab matched, so the whole
  strip went dark and the subtitle blanked while the body drew anyway — it read
  as a rendering glitch rather than a bad link.
- **Tiles are pooled by grid position.** Anything a renderer writes onto a tile
  must be cleared, or the next widget in that slot inherits it. A leftover
  layout offset pushed rows 24px down and off the body.
- **Removing a route can orphan a window.** Emptying the footer took away the
  only caller of `SYL:OpenDueWindow`, leaving two files loaded and unreachable.
  Check callers before deleting a button.
- **Hiding a list is not hiding a screen.** `HideAllRows` hides rows. The count
  line, the empty-state text and the scroll frame are separate, and sat on top
  of every dashboard tile.
- **A settings section's heading is parented to the window, not the section.**
  Rebuilding a section without removing it stacks headings.
- **The packager rewrites the `.toc` version in the zip only.** A symlinked
  install reports whatever was last typed there.
- **`GITHUB_TOKEN` is read-only by default.** v0.1.0-alpha uploaded to
  CurseForge successfully and *then* failed creating the GitHub release. **A
  red workflow does not mean nothing shipped.** Fixed since.

---

## 6. Where the finished work is

`git log`. The messages explain the reasoning and what was rejected on the way,
which is why `.pkgmeta` keeps them out of the user-facing changelog.

The late 2026-08-09 session, after Aimee confirmed the dashboard drew: the
audience scope wired into the three screens that never asked for it, then
Raiders, Bosses and Nights turned from routing stubs into real screens — a
board with a detail pane that shows the arithmetic behind a raider's number, a
boss rail with the loot table that boss still owes you, and a month calendar
keyed on the night a raid belongs to rather than the day its clock reached.

The earlier 2026-08-09 session, in order: the audience scope and quiet-by-default chat,
the record-id backfill, the Timewalking drought fix, recruits before they join,
keystone tracking and guild sharing, MM-DD-YYYY dates, weighted loot value, the
dashboard and six-tab navigation, and thirteen defects found by three review
passes and fixed.
