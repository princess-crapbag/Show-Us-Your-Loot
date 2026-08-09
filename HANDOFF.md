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
- **`main` is 10 commits ahead of that tag.** Everything after it is on GitHub
  and in Aimee's game, and has reached no user.
- 87 Lua files in the .toc, 7 test suites in `tools/`, all run before a
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
- **It exits 0 on warnings, and a broken cross-module call is a warning.**
  `SYL.PlayerRows.Build never assigned` — the shape a rename leaves behind when
  a call site is missed — prints, and `syl_check` still returns success. So the
  "Check the Lua before shipping it" step in `release.yml` cannot block a
  release on it. Verified by renaming a call and reading the exit code.
  Whether to make warnings fatal is a judgement about the false-positive rate:
  it currently reports zero across the addon, and caught a deliberately broken
  reference exactly, which is evidence it could be. Not changed, because that
  is a decision about the release pipeline.
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

  Then `.venv/Scripts/python tools/test_lootmessages.py`, and the same for
  `test_migrations`, `test_lootsort`, `test_windowplacement`,
  `test_syncchunks`. Each reads its Lua straight out of the addon, so they
  cannot drift from the code. All five exit non-zero on failure.
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

Two decisions, in order. First: should team, role and alt data be uploaded at
all? That is officers' judgements about people, which is a different category
from a record of what dropped. Only then: should a link make it readable
without a login? If both are yes, the mechanism to copy is the one
`syl_upload` already uses — a `SECURITY DEFINER` function keyed on a share
token, so the tables are never opened to `anon` and revoking is deleting a
token.

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
