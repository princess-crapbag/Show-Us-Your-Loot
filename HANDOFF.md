# Handoff — Show Us Your Loot

Rewritten 2026-08-09, after the session that built the dashboard; revised
2026-08-15 after v0.3.2, again on 2026-08-17 after v0.3.3 and v0.3.4, and
again on 2026-08-23 after v0.4.0 — see §3y, which is the one to read first.
The version before the rewrite had grown to 638 lines carrying design notes
for things since built — the same fault it was rewritten
for that morning, and the one to watch for here.

**§3 is a record of an argued order of work, not a to-do list.** Most of it is
marked DONE and kept because the order is the argument. What is actually open
is on page one and in §3a.

This file is what is **open**, what has been **decided**, and what has already
**cost somebody time**. Finished work is in `git log`, which explains it better
than a summary could.

Not shipped in the addon zip — see `.pkgmeta`.

---

## 1. Where the project stands

WoW retail addon (Interface 120100, Midnight). Records group-loot drops from
Blizzard's Loot History API plus chat-captured loot, and answers who is due an
upgrade, who turned up, and what each boss has given.

- **Repo:** https://github.com/princess-crapbag/Show-Us-Your-Loot (public)
- **CurseForge:** project 1642383, live at **v0.3.4**, shipped 2026-08-17 as
  `12.1.0 release`. **Real people can download this now.** v0.3.0 was the first
  non-alpha; v0.3.1 was the 12.1.0 compatibility bump.
- **`main` is pushed and reads 0.3.5 in the `.toc`. There is no v0.3.5 tag,
  so nothing has reached a user.** Verify rather than trust this line:
  `git log --oneline v0.3.4..main` and `git tag --sort=-v:refname`.
- 156 Lua files in the `.toc`, 45 test suites in `tools/`.

**Aimee runs the addon from a symlink**, `Interface/AddOns/ShowUsYourLoot ->
Desktop/ShowUsYourLoot`. Edits are live in game immediately; only a `/reload`
is needed. There is no build step for local testing. **Her SavedVariables are
readable from here** —
`_retail_/WTF/Account/ARCANGELA/SavedVariables/ShowUsYourLoot.lua` — which
settles "is this a display bug or is the data like that" in one grep and has
done twice. They are written on `/reload` and logout only, so a file that
disagrees with what she just did is stale rather than wrong.

### THE THREE MOST IMPORTANT THINGS ON THIS PAGE

**1. TUESDAY 2026-08-18 IS THE VERIFICATION DAY.** Midnight Season 2 opens, and
three separate claims get tested at once by things outside this addon's
control:

| What | What should happen | If it does not |
|---|---|---|
| Mythic 0 lockouts flip weekly → daily | The Keys grid countdowns change from `2d 19h` to hours, **with no release** | The design claim is wrong. `Core/Lockouts.lua` stores when each lockout expires and never which period is in force; stale multi-day timers on Wednesday mean it is reading something else |
| `Enum.ItemBind` | `/syl api` prints two lines; the numbers on the second appear on the first | The warbound fallback numbering was used and may be wrong, so warbound gear is silently counting as upgrades again. **Nothing on screen would look wrong** |
| The tier tile | Fills with real Season 2 bosses as they are pulled | It is reading a season boundary that is in the wrong place — check the active season's contents before the code |

**2. Three features have never run between two clients** — down from four.
**Key requests worked, over a real guild, on 2026-08-17.** Ask, reply, and the
answer arriving on the other client all work; the only fault was that the reply
was drawn cut off, fixed in v0.3.4. That is the first of these ever proven.

| What | Needs |
|---|---|
| **Roster sharing** | **Shipped in v0.3.3, and the first attempt failed** — the send burst below meant the messages never all arrived. v0.3.4 paces them. Still unproven. Turn the switch on, have them `/reload`, and the Raiders tab should fill and say "shared by". **Fails silently** — an empty roster looks exactly like a roster nobody has set up |
| **Absence sharing** | A second client. **Fails quietly**: a bad merge says somebody is available when they are not, which is worse than an error. Mark somebody out on one client, check the "set by" on the other, remove it, check it disappears |
| Sync roll lists | A second client. `/syl sync backfill` on one and the roll lists should appear on the other. **Command-only, which breaks the rule in §2** — it needs a home |

**Every sharing switch except roster sharing gates receiving as well as
sending, and they are all off by default.** A fresh install is deaf to absences
and keystones until its owner finds a setting nobody told them about — which is
most of why the guildie on 2026-08-17 saw nothing. Worth deciding whether that
is right for the other three; roster sharing departed from it deliberately and
`Core/RosterSync.lua` argues why.

**3. The fairness maths has run on real raid nights, but never on a full team.**
The LFR run on 2026-08-10 proved attendance and loot capture on live data — and
proved nothing about the ranking, because one ranked raider makes every
ordering agree by accident. It hid a real fault that way: `/syl due` sorted by
drought while the board sorted by share. **The first full guild night with
several ranked raiders is still the highest-value event for this project**, and
Tuesday is a raid night.

Still unverified against a live client: **`/syl schedule import`**
(`Core/GuildCalendar.lua` — if it finds nothing, distrust it before
`Core/RaidSchedule.lua`, which is tested and depends on none of it), and the
**trade advisor** and **trade tracker**, which need a raid and a real trade
respectively.

### The rule about releasing

**Say plainly which of these happened.** They are one command apart and read
identically in a terminal.

- **Pushed to GitHub** — `git push origin main`. No user is affected. The
  release workflow triggers on `v*` tags only and does not start.
- **Released to CurseForge** — a `v*` tag was pushed, a zip was built and
  uploaded, real people download it.

Releasing: write the CHANGELOG entry, bump `## Version:` in the `.toc` **by
hand**, commit, tag, push the tag. See CURSEFORGE.md.

**Five releases have now gone out this way and all five worked**, so the
process is not the risk it was. Watch the run finish anyway: `gh run watch`,
then grep the log for `Uploading` — a red workflow does not mean nothing
shipped, which §5 explains.

**The CurseForge invisibility is fixed.** The addon was unfindable because all
three early uploads were type Alpha and CurseForge indexes a project by its
latest **non-alpha** file, so the project's own Files tab read "No Results"
until "Show alpha files" was ticked. Shipping a tag without the `-alpha` suffix
fixed both, from v0.3.0 onwards. Keep it that way: an alpha tag now would make
the project invisible again and the cause would not be obvious a second time.

**Version numbers are Aimee's call, and she reads them as a maintainer.**
v0.3.2 shipped a feature set that looked like a minor bump, because in her
words the warbound change is "not a change, it's fixing something I should have
already accounted for" — the rule was always bind-on-pickup, and warbound gear
was slipping through it. That reading is right. Do not argue semver at her; say
what a number signals to a reader and let her choose.

---

## 2. Working here

### A SLASH COMMAND IS NOT A FEATURE

Aimee's, after it happened twice in one session, and it is the rule most likely
to be broken by somebody who does not know it:

> "when you add features or fix things for me, they also need to work for other
> people who use the addon which means just putting a command in wont work"

**She ships this to a guild.** A guildie will never find a command nobody told
them about. Both times the failure looked complete from the inside and was not:

- **Alt mapping** could be *created* from the roster screen and only *removed*
  with `/syl alts clear`. A character stuck as somebody's alt dragged that
  person onto every list, and the button beside "Alt of" said "Untick all" —
  which is what a person hunting for an undo presses, and it changed nothing.
- **Absences** could only be set with `/syl out <name>`, on a calendar that
  displayed them nowhere.

So: put the control on the panel that already shows the data, and treat the
command as the second route. **Anything that can be created must be undoable
from the same screen.** Then check the surfaces around it — the button tooltip,
the message printed on success, and the report somebody lands on when they go
looking. `/syl alts` listed the mappings and offered no way out of them, which
is how the gap survived.

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

They need `lupa`, which embeds a Lua interpreter, and `luaparser`,
which parses Lua into an AST for the scope check. **It is already installed on
the system python on this machine** — `python tools/test_load.py` runs as is.
There is no `.venv`, despite what this file used to say; if it is ever needed
again:

```bash
python -m venv .venv && .venv/Scripts/python -m pip install lupa
```

Forty-five suites. Each reads its Lua straight out of the addon, so none can drift
from the code, and each exits non-zero on failure. `release.yml` runs the lot
before building a zip, so a failing suite blocks a release.

The ones that matter most — and see "Testing this addon" in §5 for the ways a
test here has managed to prove nothing while passing:

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
- **`test_tradeadvisor`** — asserts the **cold start first**: with no seasons,
  no nights and no prior drops, everybody who rolled and lost is still named.
  That is the reason the feature exists, so it is the assertion to keep.
- **`test_tradetracker`** — asserts a traded item moves the score **and** the
  drought together. Reverting the fix on either side alone fails it, which is
  the point: two lists disagreeing about who won an item is worse than both
  being wrong the same way.
- **`test_seasons`** — the archive boundary. It counts calls to the all-time
  accessors while driving the real panels, because a panel reading across
  archives looks completely normal; comparing numbers would not catch it.
- **`test_absencesync`** — the three ways sharing fails silently: a
  half-delivered set committing a fragment, a removal not travelling, and one
  author clobbering another.
- **`test_archives`** — that a merge loses nothing and takes only the seasons
  it was given. Merges **three** seasons with a fourth standing by, which is
  the smallest fixture that can catch the removal walking the wrong way.
- **`test_alts`** — the round trip. Whatever the roster screen can do to
  identity it must be able to undo, and its last assertion checks the UI still
  calls `ClearMain` at all, because no behavioural test can see a button that
  was never built.

**Every test written this session was confirmed to fail on a planted fault
before being trusted.** Do the same. A test that has never failed proves
nothing — and this is not a formality. Planting the fault is what showed that
the trade tracker's acceptance gate was not covered at all: removing it changed
no result, because no case exercised a half-accepted trade. The assertion that
now covers it was written afterwards.

**Anything the fairness files call needs a stub in `test_duelist` and
`test_lootscore`.** Both load their modules individually rather than the whole
`.toc`, so a new dependency inside `DueList` or `LootScore` breaks them at the
first call. `TradeTracker` was the most recent.

### Ten files are over the size limit

None is exempt and none should be without a real reason. Run `syl_check` for
the current list rather than trusting this one — it has been stale three times.
As of 2026-08-16 the worst are `Core/SlashCommands.lua`, `UI/MainWindow.lua`,
`Core/Utilities.lua`, `UI/KeysPanel.lua` and `Core/Database.lua`, all past 470.
`KeysPanel` is the one this list kept missing: it sits above `Database` and was
named nowhere.

`Utilities` has the obvious seam: the item helpers (`GetItemLevel`,
`GetItemIDFromLink`, `NormalizeItemLink`, `GetItemNameFromLink`,
`IsBindOnEquip`, `IsWarbound`) are a module — but it is 12 call sites across 8
files, and the test suites load those modules individually, so it ripples into
`tools/` too. `SlashCommands` could shed the roster and link commands.
**Never delete a comment to get under the limit** — that happened twice before
the escape hatch existed.

**Splitting works, and `Core/Absences.lua` is the worked example.**
`RaidSchedule` was 578 lines doing two unrelated jobs and came apart into 293
and 309 with nothing changed but the namespace and one accessor. Do it as its
own commit: a move mixed with a change shows as hundreds of deleted and added
lines and nobody can tell which are which. Two things caught what the move
broke — `syl_check` found three internal calls that had been file-local and
became nil globals, and a test failed on a call site held in a local that no
search could match. Expect both.

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

## 3y. The 2026-08-23 session — READ THIS FIRST

**v0.4.0 is live on CurseForge. The settings redesign is finished and is NOT
released.** Everything under it sits on `main` after the v0.4.0 tag, so no
user has any of it. 45 suites green, `syl_check` exit 0, working tree clean,
`.toc` still reads 0.4.0.

To release it: the CHANGELOG's `## Unreleased` block is already written, bump
`## Version:` in the `.toc` by hand, commit, tag, push the tag. See §1.

### The drawing, which is the spec, and which now matches the addon

`screenshots/settings-five-tabs.png` — the five tabs at the real 560px width.
Aimee on the morning version: **"i love it."** `tools/mockup_settings_tabs.py`
makes it and reads `tools/mockup_settings.json` and `tools/mockup_commands.json`
beside it. **Re-run it after changing a tab.** It also measures every label in
the real game font and prints what overflows, which is the check that caught
"Announce gear in chat" being three pixels too wide.

`screenshots/clear-season-dialog.png` and `tools/mockup_clear_dialog.py` are
the second drawing: the erase-a-season guard, in both its locked and unlocked
states.

Tab heights, which is what decides the window size: Recording 462, Scoring
428, Features 296, Display 378, Tools 610. The old single column was 656.

### What was built, in the order it was asked for

**The editable-number widget** — `UI/SettingsNumberRow.lua`. The thing the
whole redesign was blocked on: every row in this window was a checkbox or a
value that cycles, and cycling is wrong for a weight. Label, right-aligned
field, commit on Enter **and on focus lost**, Escape reverts, refusal printed
rather than clamped.

**It does not use `SetNumeric(true)`**, and the comment in that file says why
at length: a numeric EditBox eats every non-digit including the ones the
widget writes itself, so the guild threshold's "80%" would have come back as
"80" or as nothing. It filters in `OnTextChanged` instead. **The test client's
EditBox is a stub that accepts anything, so no suite can see this.**

**The Scoring tab** — `UI/SettingsScoring.lua`. Rank floor, guild threshold,
three weight rows, the offspec-split checkbox, and the caution in red on the
tab. It **rebuilds itself** when the offspec link is broken, because that adds
a fourth row and the tab is 20px taller with it: `SettingsScoring.onHeightChanged`
to `tabs.onResize` to the window re-applying its height.

**The item types** — `Core/ItemTypes.lua`, `UI/SettingsItemTypes.lua`. Nine
rows, three across, under the qualities. Gates capture in the same two places
quality does and an item must pass both. Everything on by default, so an addon
upgrading from 0.4.0 records exactly what it recorded yesterday.

**The Tools tab** — `UI/SettingsToolsList.lua` (what) and `UI/SettingsTools.lua`
(how). Twenty-four rows in six groups, two columns **packed into whichever
column is shorter** rather than alternating — alternating put 18 rows against
8 and wasted 90px of window.

**Three dialogs** — `UI/ClearSeasonDialog.lua` and `UI/NamePromptDialog.lua`
are new; the two that already existed are wired to their rows.

### The clear guard, which is Aimee's design and not a default

Her words: *"dont make it a normal button. or make it harder to do. make sure
there is an explanation as to why someone should use this button and what will
happen if they do. maybe have a danger image near it. or it can just be a
slash command. but dont make it a normal button and give an explanation of
what it does so they youngest user can understand."*

Four guards, and **none of them is decoration**:

1. It is **not a row in the Tools list**. Own block at the bottom, own warning
   rule, the client's alert icon, warning color.
2. The dialog **explains before it asks** — real counts, what goes, what
   stays, what to do instead, in short words.
3. **The season's name has to be typed.** Not "confirm", which is what the
   command takes and which can be typed without reading. The name cannot.
4. **Erase is dead until it matches**, and a line under the box says which of
   the two states it is in.

Archive is offered first and is the larger button. The dialog runs
`/syl clear confirm` rather than emptying the tables itself, so the
account-wide `Recovery.NoteDeliberateClear` stamp cannot be forgotten in one
of two copies — an alt would otherwise report data loss on its next login.

**`tools/test_settingstabs.py` asserts that no Tools row clears a season, both
by label and by running every row and watching what it dispatches. Do not
delete that assertion to make a refactor pass.**

### Four bugs fixed on the way, three of them shipped-and-invisible

- **All seven dashboard widget tooltips were dead.** `UI/SettingsWidgets.lua`
  built the row as a `Frame` with no `EnableMouse(true)`, and `Tooltips.Attach`
  hooks OnEnter, which such a frame never fires. Every note in
  `Core/Dashboard.lua:33-78` was unreachable text. **This is a whole class of
  bug in this codebase** — check `EnableMouse` before believing a tooltip.
- **A stray paragraph was drawn through four of the five tabs.**
  `BuildToggleSection` anchored its closing note at `ToggleSectionTop()`, an
  offset for the column the tabs replaced, and ignored the `top` it was given
  — so every tab drew that sentence 244px down its own page. It shipped in
  `7efaad7`. `BuildQualitySection` had the same fault and agreed with the
  Recording tab **by two pixels of luck**; both derive from `top` now.
- **The Raiders board told people something untrue** — that adding a recruit
  lived in the full roster window. `IncomingRoster.Add` had no caller in `UI/`
  at all. There is a real dialog now and the tooltip points at it.
- **Export had no door.** Its only button was inside `UI/PlayerWindow.lua`,
  reachable only by typing `/syl players`.

### The one thing inferred rather than confirmed

**"Sparks and hides" and "Profession supplies" are a split taken from the
labels, not one the client draws.** Housing decor is confirmed — class 20,
against five installed addons — and the other eight rows key on confirmed
class and subclass ids. But the client has no category that separates a
raid-drop reagent from an ordinary crafting material, so:

- **Sparks and hides** = Tradegoods, Reagent, ItemEnhancement. Catches Spark
  of Radiance and Void-Tempered Hide from her season — **and Bright Linen and
  Resilient Leather with them.**
- **Profession supplies** = Recipe and Profession. Recipes, patterns, tools.

If she wants ordinary mats separated from raid reagents that is a real change,
and the honest way is a name list rather than a class rule.

### Decided, so nobody re-asks

- Weights **editable**, with the caution on the tab. Her call over my
  objection that mid-tier edits rewrite history.
- Guild threshold a **real setting**. Since `bbcf4dc` it also gates
  `DropRules.CountsAsUpgrade`, so moving it re-scores nights already raided.
- Three weight rows, four in the data. Offspec follows greed unless split.
- Housing decor **ships as a real filter**, class 20.
- Item types **all on by default** — an upgrade must not change what is
  captured.
- **Two rows the drawing did not have**: "Raiders board", because the headline
  screen had no door of its own anywhere in the addon, and "Full roster"
  renamed from "Roster" so the two screens are not confused. Both flagged to
  her.

### Traps this session paid for

- **`UI/SettingsRows.lua`'s size exemption had gone stale and was being used
  to hold things it was not written for.** Its note said "three sections of
  one window sharing a row factory"; those three are separate files now. The
  eight toggle declarations moved to `UI/SettingsToggles.lua` and the note was
  rewritten. **Anything that is a LIST rather than a mechanism belongs outside
  that file.**
- **Moving `PERSONAL_LOOT_NOTE` left a dangling `SettingsRows.` reference** in
  `UI/SettingsTabs.lua`, which would have drawn nil as an empty paragraph.
  Both `syl_check` and the suite caught it — which is the shape a rename
  always leaves behind, exactly as §2 says.
- **The test client returns the parent frame itself from `CreateFontString`.**
  Every "font string" in a suite is therefore the same table, so a harness
  that wrapped `SetText` to record what was drawn NESTED its wrappers and
  every count came back a multiple of the truth. `rawget` is needed for the
  guard, because a plain field read on that stub answers a function, which is
  truthy.
- **`Enum` is `{}` in the test client**, so `Enum.ItemClass.Housing` throws.
  `Core/ItemTypes.lua` carries the numbers as fallbacks and reads the live
  enum when it exists, resolved lazily and never at load.

### Still open, and none of it is this work

- **`Core/Sync.lua` sends the item id and never the item link**, so a
  co-officer's synced drops arrive with no icon, no quality color, no tooltip
  and no track letter on the Raiders detail pane. **Aimee's decision, not a
  fix to slip in.** Appending a field is backward compatible; bumping
  `PROTOCOL` is not, and would break sync with guildmates who have not
  updated.
- **Aimee's own next task: CurseForge project screenshots.** `SCREENSHOTS.md`
  has ten shots and the Raiders board is not one of them — the headline screen
  has never had a picture on the project page. Shoot Settings **after** this
  ships. `CURSEFORGE.md` already holds the description text.
- **She has a list of minor issues** she wants worked next, mentioned at the
  end of this session. Ask her for it.

---

## 3z. The 2026-08-20 session

**`main` is pushed and carries a dated 0.3.5 changelog and a bumped `.toc`.
No tag, so nothing has reached a CurseForge user.** Tagging is the only
remaining step and it was deliberately left for Aimee — see "The release that
is one step away" below. 37 suites green, `syl_check` exit 0.

Written after her first real raid night produced eleven improvement requests,
then extended through the afternoon as she tested each fix in the client.

### The release that is one step away

`v0.3.5` needs one action: push the tag. The changelog is written and dated,
the `.toc` reads 0.3.5, and `tools/syl_package.py` builds
`dist/ShowUsYourLoot-0.3.5.zip` clean.

**It was not tagged because she was away and most of it had not run in the
client at the time.** Since then she confirmed in game: the credit line, the
picker, Undo, persistence across a reload, the window layering and the close
button. What is in the release and has still never run in game is the
duplicate-drop repair — verified instead against her live saved variables
through the shipped Lua, which is the strongest evidence available short of
the client.

### What she confirmed in the client, this session

The credit block appears only on real drops, the picker opens in front and
lists all eleven raiders, hovering a name lights the row, `credited now`
follows the correction, the front window is solid and the back one
translucent, and clicking either swaps them. Her words on the last one: "the
two windows show correctly now."

### The eleven corrections are already in her database

All eleven 08-18 awards are applied. Eight were written into her
SavedVariables directly while the client was closed; one she had already made
by hand; **two needed no override at all** — Boots of the Reckless Wayfarer
and Shellbound Bracers were already recorded as hers on the same response the
council gave them, and writing one would have made them read "set by hand"
for a correction that corrected nothing. A backup sits beside the file as
`ShowUsYourLoot.lua.before-credit-import`.

**Editing SavedVariables is only safe with the client closed.** WoW holds the
file in memory and rewrites it on `/reload` and logout, so an edit made while
it is running is thrown away without a word. Check for `Wow.exe` first.

### The one thing that matters more than the rest

**THE RAIDERS BOARD IS WRONG FOR HER GUILD AND EVERYTHING ELSE DEPENDS ON IT.**
She reports every raider at 0 and Arcangila at 820. That is faithful to what
the addon knows and false about what happened: she is master looter, she wins
every roll, and she hands items out through **RCLootCouncil**, which SYL cannot
see. Credit only moves when SYL witnesses a real trade window.

Her RCLC data is readable from this machine and was read — do not re-derive it:

- `WTF/Account/ARCANGELA/SavedVariables/RCLootCouncil.lua`, globals
  `RCLootCouncilDB` and `RCLootCouncilLootDB`.
- `RCLootCouncilLootDB.factionrealm["Alliance - Area 52"]` holds ~380 award
  records keyed by player, each with `lootWon`, `response`, `responseID`,
  `isAwardReason`, `boss`, `date`, `time`, `instance`, `iClass`, `iSubClass`.
- **`responseID` IS NOT A STABLE KEY.** Real counts: `Need`=1, but so are
  `Disenchant` (13), `Major Upgrade` (11) and `BiS` (2). `Greed`=2 and so are
  `Minor Upgrade` and `Banking`. `Major Upgrade` appears under BOTH 1 and 2.
  Scoring by id gives Disenchant 100 points. **Score on the response TEXT and
  filter on `isAwardReason`.**
- Non-numeric ids exist: `PL` (Personal Loot, 56), `BONUSROLL` (51), `PASS`,
  `TIMEOUT`. Personal loot is already outside the fairness math; keep it out.
- Aimee's rule: Need 100, and offspec/sidegrade/minor upgrade all Greed at 20.
  Mog 0. **The award counts, and changing an award must move the credit.**
- Build the **manual reassign screen FIRST**. Nothing on any screen today shows
  or reverses a credit, so without it a wrong one cannot be undone.

### What she decided this session, so nobody re-asks

- Guild raid = **80% of the group guilded**, per SESSION not per night. Her two
  recorded sessions on 08/18 are 1-of-49 (LFR) and 12-of-12 (Normal).
- Rank floor: **Off / 2 / 3**. "1" was dropped — nothing ever has zero nights,
  so it and Off are the same rule.
- Loot tab: default hides her solo loot; **"My loot" gets its own tab**.
  Warbound is recorded, hidden from the main view, shown there.
- **Warbound is never scored.** It is personal loot and personal loot is not in
  the fairness math. That is a rule, not a setting.
- Keys: **the asker picks which character**, which means alt keys broadcast.
- **NOTHING MAY REQUIRE A SLASH COMMAND.** Hardened from a preference to an
  absolute. Only `/reload` and bare `/syl` are fair to type. A Settings tab of
  buttons is an acceptable home; putting the control where the data lives is
  still better. Six features are command-only today.
- **Show her a visual before changing any layout**, built from her real saved
  data. She approved a five-tab Settings mockup with three changes: decor row
  greyed out and unclickable, 80% made changeable, and the weights line reading
  "Need 100 · Greed/Offspec 20 · Transmog 0" with its spacing fixed.

### Open, in her priority order

1. **RCLootCouncil credit** — above. **The manual half is built, confirmed in
   game, and the automatic half is not.** `Core/LootCredit.lua` stores an override carrying
   both a person and a response; `DropRules.CreditedKey` and the new
   `CreditedState` beside it are the one door, and LootScore, DueList and
   Analytics all go through them. The control is the credit line on the drop
   detail window — Change… opens a picker, Undo clears it. 53 assertions in
   `tools/test_lootcredit.py`. **Confirmed in game on 2026-08-20**: the line,
   the picker, Undo, and that a correction survives a reload.
   What is left is the import: read the award history, match on `itemLink`,
   and write the same override the picker writes. On the 08-18 night all
   **11 of 11** items matched their council award on the link with nothing
   left over, so the matcher is the easy part. Score on the response TEXT —
   `Off-Spec/Sidegrade` is responseID 3, the same id as `Mog`, which is a
   second proof of the rule in §3z above and not a restatement of it.
2. **Make the calendar figures inspectable.** She does not trust "11 raiders,
   0 went home with nothing, 3.0 drops per raider" because nothing shows the
   people behind them. The 11 is CORRECT — 12 characters fold to 11 people
   because `Razørshift` has `mainGUID` = `Razørtongue` — but the card never
   says so. Click a figure, see the data.
3. **Settings in five tabs**, as approved.
4. **Window frame levels — DONE, and it was one cause under three symptoms.**
   `UI/WindowStack.lua` keeps an explicit stack and paints the levels from it,
   40 apart because a window's own popups take its level plus 10 or 20. That
   fixed the picker opening behind, the front window never being painted
   solid, and `IsTopmost` answering true for everything at once. A second pass
   pulls any direct child sitting at or above the next band back under it —
   the corner close button is a Blizzard template with a level of its own and
   was showing through the window in front. Confirmed in game by Aimee.
5. Loot views, calendar out-list layout, the Tue/Thu schedule UI (the data
   layer is DONE and has zero UI; her `schedule.weekdays` is already `{3,5}`).
6. Guild-only for the fairness math — **DONE, she made the call on 08-20.**
   Her words: "why is LFR being counted? its not 80% + guild members so it
   doesnt matter in the fairness log." Both sides moved in one commit, as
   `RaidSession.RaidsOnly`'s note required: nights through `NightsOnly`, and
   `DropRules.CountsAsUpgrade` refusing any win from a session that is not a
   guild night. **It applies to history**, which was the other question that
   note asked — her season is two sessions, so "from today on" would have left
   the contamination until she archived.
   The trap: a drop is attributed to the last session that had **started**,
   not the one whose `startedAt..endedAt` contains it. Her LFR session is
   recorded as ending at 17:32 with six of its drops stamped after, because
   `endedAt` is only written when the client notices the raid end.

### Traps this session paid for

- **She runs from a symlink, so every save is live.** A `/reload` during a
  multi-file edit loads a half-written addon. Tabs "broke" this way once.
- **An invisible mouse-enabled child STEALS clicks from same-level siblings**,
  even when created first. A drag handle over the title bar killed the settings
  cog while the close button beside it survived — because that one is a
  Blizzard template with its own frame level. Proof: her observation, not
  reasoning. A subagent proved the opposite from frame ordering and was wrong.
  Dragging is a cursor-position test in `OnDragStart` now, with no extra frame.
- **Column widths are MEASURED, never estimated.** `Theme.MeasureText` exists
  for it and was used in 4 places out of 128 files. Each Keys column declares
  the widest string it can hold. Offline, the real font is at
  `_retail_/Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf` and PIL can measure
  it. **Too wide is a defect too** — her words: "it doesn't look professional."
- **Name forms differ between stores.** `recordedBy` carries a realm
  (`Arcangila-Area52`); roster members do not (`Arcangila`). A direct compare
  matched nobody and silently disabled the whole guild filter while appearing
  to work. Suspected to be the same bug in `KeystoneRequests.IsOnline`.
- The player registry field is **`mainGUID`**, not `mainKey`.
- `Enum.ItemBind` **is present on 12.1.0 build 69382** and warbound is
  correctly excluded — one of the three Tuesday verifications, now closed. The
  fallback table had every key mapped to the wrong number and it never mattered
  because only the value SET is used; corrected anyway.

### Traps the 08-20 afternoon paid for

- **A SLASH-COMMAND-SHAPED BUG: two clients, two record ids, one drop.** A
  record id starts with the *local* session's start timestamp, so the same
  drop is `1787100146-3470-1` here and `1787100144-3470-1` on the client that
  broadcast it. `Core/Sync.lua` deduped on the id alone and stored a second
  copy of everything a guildmate sent. Eleven of them from one night, all
  crediting the master looter, and **invisible in the loot list because a
  synced record carries no item name**. Her board read 560 where it should
  have read 200. `Core/DropIdentity.lua` is the answer and
  `Migrations.DedupeSyncedDrops` clears out what shipped.
- **Test suites that stub frames prove loading, not working.** An adversarial
  pass over code that had never run in the client found four real faults the
  37 suites could not: the credit block drawn on chat-captured loot where it
  could never work, `credited now` marking the wrong person, `PlayerHistory`
  still reading the roll instead of the credit, and a hover highlight built
  and never wired. Budget a review of that kind for any UI written between
  raids.
- **Two of the eleven council awards needed no override.** The addon already
  had them right, and writing one would have made them read "set by hand" for
  a correction that corrected nothing — which is the case the picker turns
  into a Clear. Check before writing in bulk.
- **Her SavedVariables can only be edited with the client closed.** WoW holds
  the file in memory and rewrites it on `/reload` and logout. Check for
  `Wow.exe` in `tasklist` first, and take a backup beside the file.

### Verified in game vs only tested

Confirmed by Aimee after reloading: tabs, close button, cogwheel, dates, US
formatting, Keys layout, roster spacing, right-click copy, alt suggestions,
roster scrolling and selection, the rank-floor setting, window drag, position
memory — and, on 08-20, the credit line, the picker opening in front and
listing all eleven raiders, row hover, `credited now` following a correction,
Undo, persistence across a reload, and the window layering in both directions.

**Never run in game:** Recovery, the keystone staleness filter, the
duplicate-drop repair, the guild-night filter's effect on her numbers, the
need-and-greed count on the Raiders detail pane, and the Reset window sizes
row in Settings.

The duplicate repair and the guild-night filter are the two worth reading the
caveat on. Both were verified against her live saved variables through the
shipped Lua rather than in the client, which is the strongest evidence
available short of logging in and is not the same thing. Together they take
the season board from Arcangila 560 and ten LFR strangers to exactly her
eleven raiders, with the six who took loot reading Arcangila 1, Rakahasa 1,
Jtkurayami 2, Phreestyle 2, Razørtongue 2, Pringlesbop 2 — the list she gave,
to the item.

**The board's 820 was reproduced exactly from her saved variables** before any
of it was written — 23 wins, 7 Need, 6 Greed, 10 Transmog, of which the guild
night is 360. Worth repeating rather than trusting if the math ever looks
wrong again: matching her reported number to the point is the cheapest proof
that a change is reading the same rules the addon does.

---

## 3a. What is actually open, 2026-08-17

Everything below in §3 predates v0.3.2 and is nearly all DONE. This is the live
list.

1. **Tuesday's three verifications.** The table on page one. The
   `Enum.ItemBind` one is the only one where being wrong is invisible.
2. **Second-client testing**, roster sharing first now that it has shipped
   untested, absences second. Also on page one.
3. **The remaining screenshots**, and then `SCREENSHOTS.md` rewritten or
   retired. Aimee's, parked until the newer screens have data. Item 19.
4. **`/syl archive <name>` names the wrong thing** — see §5. It has caught the
   only person using it twice.
5. **Ten files over the size limit.** `Absences.lua` is the worked example of
   fixing one.
6. **DONE in v0.3.3.** The changelog's warbound entry moved from Changed to
   Fixed, which was Aimee's reading and the right one.
7. **E6 repositioning is effectively done.** The store description was
   rewritten for 0.3.2 and opens on the pass data, in a scene rather than a
   slogan. The tagline itself is gone. See CURSEFORGE.md, which now holds
   Aimee's live text rather than the draft.
8. Still genuinely open from Tiers 3–5: **E7 the licence** and the
   **personal-loot asymmetry** in §4. Both are decisions, not work.

Shipped in v0.3.3, so do not read these as open: **guild roster sharing, in
game.** F7's cheap shape, built rather than the web one — one broadcaster,
everybody else receives, riding the guild channel AbsenceSync already uses.
`Core/SharedRoster.lua` holds what arrives and `Core/RosterSync.lua` moves it.
The web version of F7 stays parked; the two share almost no code, and this was
the decision §3b said to take before writing either. Alt mapping is
deliberately not shared and is still open as its own decision — it is the one
piece of roster data that moves the fairness numbers rather than the display.

Shipped in v0.3.2, so do not read these as open: the Mythic 0 lockout grid,
absences on the calendar with buttons and guild sharing, archive rename and
merge, warbound exclusion, bonus-roll labelling, the Ignored filter, alt
unmapping, and the season-id repair.

---

## 3b. The web app, parked 2026-08-16

**Aimee: "put a hold on all webapp stuff for now."** F7 and F9 are not open, they
are parked. What follows is what a session of research turned up, recorded so
it is not paid for twice. **Everything about Raidbots below is a snapshot of
2026-08-16 and should be re-checked before it is relied on.** The repo findings
do not go stale.

### One live bug, and it is in the repo rather than in a feature

**`README-SYNC.md` produces a broken setup today.** There are two
access-control designs installed at once: `schema.sql` defines `syl_members`,
and `web/supabase/migrate-email-access.sql` replaces the read policies with
`syl_allowed`. The page's own no-access error says "an officer adds it to
**syl_allowed**", while the guide teaches `insert into syl_members` in four
places and never mentions running the migration at all. Follow it verbatim on a
fresh project and you get signed in with no data and no pointer to the file
that fixes it.

Three smaller things found beside it:

- **Email magic link is still the default**, in the UI and in the guide, though
  Discord is the path that works. `README-SYNC.md` contradicts itself: step 1
  says skip Discord, step 6.2 says "they sign in with Discord once".
- **No token refresh and no expiry check.** Only `access_token` is captured;
  the page keeps saying "Signed in" after it dies and then 401s. Sign-out is
  local only and never calls `/auth/v1/logout`.
- **`syl_allowed.role` defaults to `'officer'`**, so every address added by
  hand becomes an officer.

The page has not been touched since 2026-08-05 and is not deployed anywhere.
The documented way to run it is `python -m http.server 8000`.

### F9, and why the obvious build is the wrong one

Raidbots **does** document machine-readable report files, on a page current as
of 2026-08-16: `https://www.raidbots.com/simbot/report/{id}/data.json`, with
`data.json` and `input.txt` described as "Always available". Three findings
change the design:

- **The documented URL cannot be fetched from a browser.** It 302s to
  `/reports/{id}/data.json` and the redirect carries no
  `access-control-allow-origin`, so the CORS check kills it. The *undocumented*
  alias is served off Google Cloud Storage with `ACAO: *` and works. Confirmed
  independently twice. Building on it means depending on a bucket config
  Raidbots never promised.
- **Sims expire after 28 days**, and an expired report and a typo both return
  the same 403, so a page cannot tell them apart. Parse once at import and
  store the result; never re-fetch.
- **The terms are in tension with their own developer docs.** The TOU dated
  2023-10-26 prohibits using Raidbots content "as input into or for the
  development or training of ... algorithms, software, or related
  technologies", which on a plain reading covers this feature, while the
  Developers page invites you to fetch and cache the files. Aimee's call, and
  worth an email to support@raidbots.com before building on it.

**All three problems disappear if the file is dragged onto the page** rather
than fetched. `web/index.html` already has a drop zone that sniffs content. The
parser is the actual work and the ingest mode is a garnish.

The join key is the profileset name, `instanceId/encounterId/difficulty/itemId/
ilvl/enchantId/slot///`, but **the leading field count has changed across
expansions**, so it must be validated against a real report rather than
hardcoded. Nobody could validate the field names, because every report findable
in search was already past its 28 days. Getting one live report is the first
step of any F9 work.

Free static data at `https://www.raidbots.com/static/data/live/*.json` is
CORS-open and needs no auth; `metadata.json` was fetched successfully and
returned build 12.1.0.69299.

### F7 has a cheaper shape nobody had considered

The web version is real work: new tables, the first write path this schema has
ever had, roster in the export, uploader changes, UI. Six to eight sessions,
against something Aimee called "not urgent, just a bonus for guildies".

**The addon already broadcasts to the whole guild and already knows guild
rank.** `Core/AbsenceSync.lua` sends on the GUILD channel, shipped, and
`guildRankIndex` is on every roll record in `Core/DataExport.lua`. A roster
guildies can see could ride the channel that already works, in game, with no
web app, no Discord login, no claim step and no hosting. **Decide web or
in-game before writing either**, because they share almost no code.

On the impersonation worry that shaped the earlier design: it was overstated.
The link is unlisted, the data is loot history the whole raid already watched,
and Aimee had already set the bar at "if you have a guild rank you can access
the link". What survives is narrower. Any write must be scoped to the caller's
own `auth.uid()`, and **the roster upload is the access list** — derive access
from the newest upload and somebody who leaves the guild loses it on the next
one, with no revocation flow to remember.

### Addon-side, cheap, and not blocked by the hold

**`tools/syl_upload.py` throws away `itemLevel`.** `Core/DataExport.lua:60`
emits it and `syl_drops` has no column for it. Sims are per item level, so
without it any future join can only match on item id. Worth fixing whenever the
uploader is next touched.

---

## 3. What is open

**The list below is the agreed order of work**, built 2026-08-09 from what
Aimee asked for after loading the addon, plus the strategy items recovered from
the pre-rewrite version of this file. Numbered so they can be referred to.
Items 2 and 5 are done; they are left in place with what was built, because the
order is the argument and deleting the finished ones hides it.

### Tiers 1 to 4 — all but five items are done

Items 1 to 8 are built and shipped: the four route panels became real screens
(Raiders, Bosses, Nights, Keys), audience scope reached the three surfaces that
never asked for it, the schedule and absences arrived without needing the
in-game calendar, the score breakdown reads back the wins behind a total, and
the trade advisor, trade tracker and roll-list sync all exist. Item 14 became
`tools/syl_scope.py` rather than luacheck. `git log` carries the reasoning and
what was rejected on the way, which is why the detail is not repeated here.

**What the order was arguing**, and the part worth keeping: Aimee's own list
after first loading the addon came before every strategy item recovered from
the older file, and the trade advisor went first among those **because it is
the only feature with no cold start** — it works on install night with no
history, where every other screen reads as empty. That is still the right
tiebreak for anything new.

Still open from those tiers:

9. **E6 — reposition.** The unique asset is the pass data. Suggested line:
   *"Group Loot remembers who won. This remembers who passed."*
10. **E7 — reconsider All Rights Reserved.** Tells an officer they are stranded
    if the author stops. Aimee's call, no code.
11. **F7 — roster as a link. The in-game half shipped in v0.3.3**, which is
    the cheaper shape §3b argued for and answers the actual ask: guildies can
    see the roster. The *web* version is untouched and parked —
    `Core/DataExport.lua` still sends seasons only, so there is nothing on the
    server to point a link at, and the Discord claim step does not exist.
12. **F9 — Droptimizer.** Web-side only; the addon makes no HTTP requests.
15. **The personal-loot asymmetry.** Dormant, not wrong — see §4.
16. **NOTES Phases 2, 3, 5, 6.** Phase 6 is item 7, which is built.

Item 13, the size limit, has its own section in §2 and is no longer blocking
anything.

### Tier 5 — shipping

17. **DONE. The LFR run.** See page one for what it proved and what it did not.
18. **DONE. Released as v0.3.0**, the first non-alpha file, then v0.3.1 for
    patch 12.1.0, v0.3.2 for the work in §3a, and v0.3.3 for roster sharing.
19. **F10 — screenshots. PARTLY DONE, and parked at Aimee's request.** Five new
    ones are on CurseForge and in `screenshots/`: Dashboard, Loot, Raiders
    (Roster), Bosses, Settings. The numbering has gaps at 4, 6, 7 and 8 because
    **the rest of the gallery is still the old shots** — the newer screens have
    no data behind them yet to photograph. `screenshots/old/` is tracked for
    exactly that reason; it was briefly gitignored as "superseded", which was
    wrong, and git was missing images live on the page.

    `SCREENSHOTS.md` is a ten-shot list describing the pre-tabs UI and matches
    neither the new set nor her numbering. **Do not act on it.** Rewrite or
    retire it once the remaining shots exist.

    Nothing shows the Keys tab's Lockouts grid, which is the most
    demonstrable thing added since.

### Two small decisions, still open since 2026-08-09

- **Is the due window superseded?** The Raiders board answers the same question
  better, but `UI/DueWindow.lua` has a recency toggle the board does not. Making
  the tab a panel deleted its last route, so `/syl due window` was added rather
  than leaving two files loading and unreachable. If the board is enough, delete
  `DueWindow.lua` and `DueRows.lua` and drop that subcommand.
- **The players and roster windows** are still reachable only via `/syl players`
  and `/syl roster`. Folding them into the Raiders tab is the rest of item 1a.

### The calendar — no longer a blocker

**Nothing is blocked on it.** Both tiles answer from `Core/RaidSchedule.lua`,
which is typed and tested. `Core/GuildCalendar.lua` reads `C_Calendar` on top
and is **unverified against a live client** — if it silently finds nothing,
distrust it rather than the schedule.

What was decided, and why, after Aimee asked whether Discord could feed this:

- **Discord cannot reach the addon by any route.** WoW makes no HTTP requests,
  so this is the same wall as Warcraft Logs and Droptimizer. A bot could feed
  the **web dashboard** — the login is already Discord, so that side is easy —
  but the web can only ever display, never push into the game.
- **`C_Calendar` is the only automatic in-game source**, and it only knows who
  is out if people click Declined on the in-game event. A guild that posts
  absences in Discord produces nothing there. That is why typed absences are
  the primary path and not the fallback.
- **Once other people run the addon**, absences could ride the sync channel —
  an officer marks somebody out and it propagates. Not built.

**Warcraft Logs cannot feed this, and having an API key does not change that.**
Checked against the public docs 2026-08-09. Two walls: an addon makes no HTTP
requests at all, and the v2 guild type exposes `attendance`, `members` and
`zoneRanking` — no events, no signups, no schedule. The page Aimee linked is a
*Report* calendar, a grid of past uploaded logs, so even via an API it would
answer "when did we raid" rather than "when are we raiding". Her V1 key was
screenshotted into a chat and has been reset.

The alternative is an officer typing the schedule in. Recommendation: both —
read the in-game calendar, allow a manual override.

### The four designed screens are all built

Raiders, Nights, Bosses and Keys were mockups signed off on 2026-08-09 and are
real tabs now. Two things from that design survive as constraints rather than
as history:

- **Aimee rejected two table designs for Raiders before accepting the board.
  Do not go back to a table.** One bar per raider, length being loot taken per
  night, with the raid average drawn across it. The detail pane is the screen
  somebody stands at when they disagree with their number, so it shows the
  arithmetic and is asserted to sum to the bar beside it.
- **A grid is still right where the data is boolean.** The Keys tab's Lockouts
  view is a table on purpose — saved or not saved, eight columns, a handful of
  rows, nothing to rank. The Raiders lesson is about hiding a comparison, not
  about tables being wrong.

**Folding the six separate windows into the main window** is the refactor
behind all of it and is still only partly done: the players and roster windows
remain reachable only via `/syl players` and `/syl roster`.


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

**Archiving a season is a boundary, not a label.** Decided 2026-08-11, on the
first archive ever taken. Everything about a *person* — the Raiders board,
`/syl due`, attendance, the Nights calendar, tier progress, the trade advisor,
the end-of-night summary — reads the active season and nothing else, through
`SYL.GetActiveDrops` and `SYL.GetActiveRaids`. A new tier starts everybody at
zero, which is the whole reason an officer archives.

`SYL.GetAllDrops` and `SYL.GetAllRaids` still exist and still span the
archives. They are for questions about an *item* or about the database:
the item tooltip's "has this ever dropped", `Core/DataExport.lua`, the loot
list's all-seasons view, and the `allTime` counter in `LootHistoryStore`.
Those four are the only callers left, and a fifth should have a reason.

**Warbound gear is excluded, like a BoE.** Aimee's call, 2026-08-15, and she
was right that it is a fix rather than a change: the rule was always that a
drought resets on a **bind-on-pickup** win, and warbound gear was slipping
through it. Account gear is not the upgrade of the raider who was standing
there. `Utilities.IsWarbound` reads bind type from the stored link at the
moment it is asked — the same trick `IsBindOnEquip` uses — so the rule applied
to history already recorded and **no backfill was needed**. Unknown still
counts, because an uncached item answers nil and reading that as warbound would
stop counting real upgrades.

**Anybody may mark anybody absent, and everybody sees who did.** Attribution
instead of authorization, Aimee's call. Absences are the only thing this addon
sends that is somebody's *claim* rather than something a client observed — a
keystone is a fact about the sender's own bags, a drop header is what the whole
raid watched. So every absence carries `setBy`, the calendar prints it on every
line, and **the sender of an addon message decides the author, never the
payload**, which is the only thing stopping a client broadcasting on somebody
else's behalf. Each client owns what it wrote and broadcasts that whole set;
removal needs no message of its own because a deleted absence simply is not in
the next one.

**`drops` is group loot; `loot` is chat capture; the fairness maths reads only
`drops`.** Worth knowing before somebody "fixes" a bonus roll not counting. A
bonus roll has no Need or Greed on it and never reaches the Loot History API,
so it lands in `loot` and is counted nowhere — which is exactly the behavior
Aimee asked for, arrived at by architecture rather than by rule. What was
missing was only the label.

**A lockout period is read, never written down.** Mythic 0 is weekly during a
patch week and daily once the season opens — Midnight Season 2 flipped on
2026-08-18. `Core/Lockouts.lua` stores the moment each lockout expires, taken
from `GetSavedInstanceInfo`'s `reset`, so both periods are the same code and
the flip needed no release. The season's dungeons come from
`C_ChallengeMode.GetMapTable` for the same reason: a list typed in today would
be wrong in three months and wrong silently. Mythic+ has no lockout and never
has, so only Mythic 0 is tracked.

The join between them is **by name**, because `GetMapTable` deals in
challenge-mode map ids and `GetSavedInstanceInfo` knows only instance names,
and nothing converts one to the other. A miss gives the dungeon its own column
rather than dropping it: an unmatched name is untidy, a hidden lockout sends
somebody to a dungeon they are saved to.

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

- **`GetAllDrops` is not `GetActiveDrops`, and for a year nothing could tell.**
  With one season and no archives the two return the identical list, so
  fifteen call sites picked the all-time one and every screen agreed with
  every other. The first archive taken made all fifteen wrong at once: the
  tier tile still showed the previous raid's bosses and the board still ranked
  people on the previous tier's loot. It reads as data that will not delete —
  the reason somebody goes looking for a reset — when the data is correct and
  the screens are reading past it. `tools/test_seasons.py` covers it by
  counting calls to the all-time accessors while driving the real panels,
  because a panel making that call looks completely normal.
- **A season id was unique only to the second.** `GenerateSeasonID` was the
  timestamp alone, and archiving then starting a new season is one keystroke —
  so two seasons could share an id and become indistinguishable to anything
  holding a reference to one. Ticking a season on the Archives tab ticked every
  season sharing its id, and a merge would then have taken seasons nobody
  chose. Ids carry a serial now and collisions are repaired at login. **Found
  by writing the selection test, not by reading the code.**
- **`/syl archive <name>` names the NEW season, not the one being archived.**
  It has caught Aimee twice in a row: she typed the name she wanted on the
  archive and it landed on the fresh season, leaving the active season called
  "Season 1 tail" and later colliding with an existing archive's name. The
  behaviour is defensible — you are naming what you are starting — but the
  command reads the other way. Worth a rename, or at least a message that says
  which season got the name.

- **The client rate-limits addon messages and throws away the overflow.**
  Login sent twenty-four in one frame — eight absences, thirteen raiders, two
  requests, a keystone — and printed "The number of messages that can be sent
  is limited". A set that commits only when every piece arrives is then broken
  forever by one discarded message, which is what made roster sharing look like
  it was not working. `Core/SendQueue.lua` paces everything through one shared
  queue; the limit is per client, so per-module pacing would still add up.
  `Core/SyncTransport.lua` reached the same conclusion for RAID chunks first
  and keeps its own queue.

### Testing this addon

- **A Blizzard StaticPopup cannot be driven from this harness at all, and the
  Archive Season button shipped doing nothing because of it.** The dialog
  opened, took a name, and ended no season, on two clients, on the last night
  of a pre-season. `ArchiveCurrentSeason` was never at fault — driven directly
  it works — so the break was inside frame code this addon does not own, with
  no way to reach it from a test. It is an ordinary window built from Theme and
  Widgets now, and the logic is a function with no frame in it that the button
  and the suite both call. **Anything that can only be exercised by a human
  clicking it will eventually ship broken**; the fix is to make the part that
  matters callable, not to test harder.
- **A two-item fixture cannot catch an off-by-one in a removal loop.** Merging
  two archives removes exactly one, and removing one index is the same job from
  either end. It takes **three** before the renumbering bites. The first
  version of `test_archives` asserted "the season not merged is untouched" and
  passed with the loop walking the wrong way; only a three-way merge with a
  fourth season standing by made the planted fault fail.
- **A check guarded behind a fixture key that does not exist passes while
  proving nothing.** The first bonus-roll test read
  `data.get("LOOT_ITEM_BONUS_ROLL_SELF")` from a locale table that never
  defined it, so it skipped itself in every locale and stayed green with the
  feature stubbed to `return false`. **Planting the fault is what found it** —
  nothing else would have.
- **Stub frames answer anything, so a nil check on a frame field is not a nil
  check.** `frame.headers or {}` took a function under the test stub and blew
  up on `#`; `frame:GetFrameLevel() + 10` did arithmetic on a table. Keep view
  state in module-level locals the way `UI/KeysPanel.lua` does, rather than
  hanging it off the frame. **This has now bitten twice.** The second was
  v0.3.3's shared-roster button, cached as `frame.sharedClear` behind
  `if frame.sharedClear then return it end` — which returned a function on the
  first call and failed four assertions in `test_raiderspanel` on the next.
  Lazily-created widgets are the shape that keeps walking into it.
- **`lupa` turns multiple Lua returns into a tuple.** `Update()` returning
  `entry, changed` arrives as one object, so `entry.count` silently reads the
  tuple's method and the failure looks like a code bug. Unpack every call to a
  function returning more than one value — it has cost time four times now.
- **A rename cannot find a call site held in a local.** `test_raidschedule`
  holds `SYL.RaidSchedule` as `S`, so its absence calls read `S.AddAbsence` and
  no search for `RaidSchedule.AddAbsence` would ever match them. `syl_check`
  catches the Lua side of this; nothing catches the Python side but running it.
- **A cascade that starts at zero moves nothing.** `WindowStack`'s fallback
  runs only once placement has already failed, and its first step was a no-op
  return — so the window kept its creation position, and every window here is
  created with `SetPoint("CENTER")`. Settings opened squarely on the dashboard,
  and it read as the layout being broken rather than as the fallback doing
  nothing. The same function also dropped user-dragged windows from the
  obstacle list, so dragging anything turned the layout off. `test_windowplacement`
  stayed green through both: it lifts the arithmetic out of `WindowLayout.lua`,
  and neither fault was in the arithmetic. `tools/test_windowstack.py` covers
  the layer that decides *what to hand* the layout.
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

**Do not summarise it here.** This section used to hold a paragraph per
session, and every one of them went stale the moment the next session started.
`git log --oneline v0.3.0..` reads better and cannot be wrong.

Five tags so far: **v0.3.0** the first non-alpha, **v0.3.1** for patch
12.1.0, **v0.3.2** for lockouts, absences, archives and warbound, **v0.3.3**
for guild roster sharing, **v0.3.4** for the archive button, message pacing
and four things two-client testing turned up. The commit messages
carry the reasoning and what was rejected on the way, which is why `.pkgmeta`
keeps them out of the user-facing changelog.
