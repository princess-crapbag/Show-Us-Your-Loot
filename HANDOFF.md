# Handoff — Show Us Your Loot

Written 2026-08-08 for a session starting fresh. Everything here is a
decision waiting to be made or a fault waiting to be fixed. Nothing in this
file is finished work; `git log` has that.

Not shipped in the addon zip — see `.pkgmeta`.

---

## 1. Where the project stands

WoW retail addon (Interface 120007, Midnight). Records group-loot drops from
Blizzard's Loot History API, plus chat-captured loot, and answers who is due
an upgrade, who turned up, and what each boss has given.

- **Repo:** https://github.com/princess-crapbag/Show-Us-Your-Loot (public)
- **CurseForge:** project 1642383, live at **v0.1.0-alpha**
- **`main` is many commits ahead of that tag.** Everything after
  `v0.1.0-alpha` is on GitHub and in Aimee's game, and has reached no user.

**Aimee runs the addon from a symlink**, `Interface/AddOns/ShowUsYourLoot ->
Desktop/ShowUsYourLoot`. Edits are live in game immediately; only a
`/reload` is needed. There is no build step for local testing.

### The rule about releasing

**Say plainly which of these happened.** They are one command apart and read
identically in a terminal.

- **Pushed to GitHub** — `git push origin main`. No user is affected. The
  release workflow triggers on `v*` tags only and does not even start.
- **Released to CurseForge** — a `v*` tag was pushed, a zip was built and
  uploaded, real people download it.

Releasing: write the CHANGELOG entry, bump `## Version:` in the .toc *by
hand*, tag, push the tag. The `-alpha` suffix is what marks the file Alpha.
See CURSEFORGE.md.

### Working here

- `python tools/syl_check.py` after every change. There is no Lua
  interpreter on this machine and, apart from `tools/test_lootmessages.py`
  (§4A), no tests.
- **The checker is a regex heuristic, not a parser.** It validates
  `SYL.Module.Member` references, block balance, .toc-against-disk and
  column widths. It passed clean through four crash-level bugs in one day.
  It does **not** catch bare module globals — `RaidSession.RaidsOnly(...)`
  without the `SYL.` prefix sailed through and was a nil global. Closing
  that gap is worth doing (see G1).
- 400-line limit per file is a warning, not an error. A file may opt out
  with `-- syl-check: size-exempt — reason` in its first 40 lines. **Never
  delete a comment to get under it**; that happened twice before the escape
  hatch existed.
- Commit identity is set repo-local. `gh` is installed and authenticated as
  `princess-crapbag`; pushes need no prompt. Never put a token in a URL.

---

## 2. What just happened

Five expert reviewers went over the addon: a raid officer, a retail-systems
specialist, a WoW addon API reviewer, a UX specialist, and a competitive
analyst. Their findings are triaged in §4.

**Seven bugs were fixed and pushed** (commit "Fix four crashes and three
wrong numbers found by review"):

- `FilterDropdown.ResetSearch` was called but never defined — every filter
  dropdown threw on click
- No palette defined `warning`, so `unpack(Theme.colors.warning)` errored on
  any unparseable date
- Archive popup read `self.EditBox`; StaticPopup provides `self.editBox`, so
  archiving could never complete
- `Selection.ApplyHidden` called `HideTarget` declared below it — a nil
  global, so Hide and Unhide did nothing
- Paladin missing from battle resurrection (Intercession, since Dragonflight)
- `DueList.FilterRecent` built its cutoff from unfiltered sessions, so keys
  emptied the due list
- `LootFeed.DropType` defaulted unknown roll states to "need"

**Then the whole A list was fixed** — see §4A. Twenty-one items across
thirty-six files.

**Untested in game.** No raid night has ever gone through the fairness maths.
The next raid is ~2 weeks out. That was true before the A-list pass and is
still true after it: the A fixes changed how several numbers are computed and
not one of them has been watched happening.

---

## 3. Aimee's outstanding requests

She will pick from §4 too. These are hers, unprompted.

| # | Item | Notes |
|---|---|---|
| F1 | Hide **all copies** of an item, or choose one vs all | Hiding one Dawn Crystal leaves the other two |
| F2 | **Delete selected**, or an "ignore" flag excluding a record from every count | For when capture is wrong |
| F3 | **Windows should not overlap** when opened | See C3 — it is worse than overlap |
| F4 | **Sort the main list by column** — Player, Item, Where | `SortHeader.lua` exists and is reusable |
| F5 | **`/syl output` does not persist** the chosen chat window | Setting is stored but not reapplied on load |
| F6 | **Modular enable/disable, ElvUI-style** | Her explicit ask. See §5 |
| F7 | **Roster shareable as a link** outside the addon | Needs a public-read decision on Supabase RLS |
| F8 | **Chunked sync** | Blocks NOTES Phases 2/3/5/6. 250-byte cap in Sync.lua |
| F9 | **Droptimizer import** | Verify Raidbots exposes report JSON before designing |
| F10 | **Re-take screenshot 4** | Shows the old Players window, pre-M+ column |

---

## 4. Reviewer findings, triaged

Aimee is choosing from this list. **Do not start any of it unprompted.**

### A. Wrong numbers and crashes — ALL FIXED, 2026-08-08

A1–A21 are done and on GitHub. Nothing has shipped to CurseForge. **None of
it has been in a raid**, and the fairness maths has still never run on a real
night — see §2.

Four judgement calls were made while fixing these. They are decisions, not
findings, and they can be reversed:

- **`countPersonalLoot` now defaults OFF** (A1). One client cannot see
  anybody's solo loot but its own, so counting it put the officer at the
  bottom of their own due list. When it is on, only gear received while
  grouped is counted, which is the largest subset where coverage is even.
  `/syl due` reports how many records were left out. The full reasoning is in
  `Database.lua` next to the default.
- **The quality floor for "did they get geared" is now epic** (A13), because
  every gear track a raider chases awards epics and blue is levelling gear.
  Tabards and shirts are excluded outright.
- **Crafted items never count as gear received** (A2). A create line says an
  item was made, never that the maker kept it, and the two errors are not
  symmetric.
- **Item level is now recorded but changes no ranking** (A14). Storing it was
  the bug; weighting the due list by it is a policy decision and is still
  Aimee's to make. Crest upgrades remain invisible and always will be — they
  fire no loot event of any kind.

Two files took a size exemption rather than being split: `LootHistory.lua`
and `RaidSession.lua`. Both say why in their headers.

`Core/LootMessages.lua` is new — the locale-aware chat parser, split out of
`LootCapture.lua`. There are **real tests for it**, the first in this project,
and they found two bugs that reading the code did not:

```bash
python -m venv .venv && .venv/Scripts/python -m pip install lupa
```

Then `.venv/Scripts/python tools/test_lootmessages.py`. It embeds a Lua
interpreter and reads the parsing block straight out of the addon, so it
cannot drift from the code. Six locales, exits non-zero on failure. See G1 —
this is not a substitute for the checker knowing about module globals.

<details>
<summary>The original A-list, for reference</summary>


| # | Item |
|---|---|
| A1 | **`countPersonalLoot` default on inverts the due list against whoever runs the addon.** `CHAT_MSG_LOOT` only ever sees your own out-of-raid loot plus your current group's; nobody claims a vault while grouped with the officer. So your vault resets your drought and no one else's does. Two reviewers independently. **The single most consequential item here.** |
| A2 | Crafting **for other people** counts as gear you received — `PersonalLoot.Build` never consults `LootTypeOf`. A guild crafter never appears due |
| A3 | A **two-difficulty night counts twice** — `BuildSessionID` keys on instance + difficulty + date, and `nightsSinceUpgrade` is the sole ranking key |
| A4 | **Attendance dies silently when loot capture is off** — `ENCOUNTER_START/END` are registered inside `LootHistory.Enable()` |
| A5 | **Non-English clients file every chat-loot record under one fake player "Unknown."** `DetermineRecipient` matches literal English. Fix by moving to `ENCOUNTER_LOOT_RECEIVED`, already registered, which carries `playerName` and is locale-free — also fixes M+/dungeon attribution |
| A6 | **Role cycle is a permanent no-op** for anyone the game assigned DAMAGER — `ROLES[4]` is nil, so it resets to the detected value |
| A7 | **Roster bulk actions apply only to the post-search list** — ticks made under a different search are silently discarded, then cleared |
| A8 | **Guild rank read off whichever alt `pairs()` reached first** — varies between refreshes |
| A9 | **Class dropped for non-raiding guild members** — `AltDetect.EnsureGuildMembers` never passes `member.class` |
| A10 | **Quality colours wiped** when the theme is changed, until `/reload` |
| A11 | **Shift-click on chat-captured rows inserts a malformed link** — the capture pattern drops `|cff…`/`|r` |
| A12 | **One person appears twice** in the Player filter — chat stores full name, the API stores short |
| A13 | `MINIMUM_QUALITY = 3` is too low — any world blue resets a Mythic raider's drought; tabards and shirts pass the slot check despite a comment saying otherwise |
| A14 | **No item level or upgrade track anywhere.** A Champion M+ piece and a Myth vault piece count the same. Crest upgrades produce no loot event at all and are entirely invisible |
| A15 | **`/reload` mid-raid may duplicate that boss's drops** — `runID` is memory-only and re-minted. **Unverified**; needs one deliberate test |
| A16 | Sortable headers for `select` and `main` have no comparator — silently sort by name |
| A17 | `AltDetect` uses `officerNote or publicNote`, so anyone with any officer note never has their public note scanned |
| A18 | **Delves classify as "world"** — `instanceType == "scenario"` is handled nowhere |
| A19 | Missing difficulty IDs: Story, Follower, Event, Timewalking LFR. A solo Story clear opens a one-person raid night |
| A20 | Roll-state constants hardcoded in three files while `LootHistoryAPI` reverse-maps the live enum |
| A21 | Click-catchers never `RegisterForClicks`, so they swallow right-clicks; both panels float over the game after their window closes |

</details>

### B. Performance

| # | Item |
|---|---|
| B1 | **Merged feed rebuilt 3–5× per redraw** — `GetFiltered`, `DescribeCount`, `CountHiddenInScope`, `SelectionBar.Update`, plus a fifth on wheel. Each pass allocates per record, indexes drops, sorts with a `tostring` tiebreak, and with Gear only on calls `C_Item.GetItemInfo` per entry. Dominant cost on a full season |
| B2 | **Polls every 0.6s** for uncached items instead of registering `GET_ITEM_INFO_RECEIVED`; a never-resolving item loops forever |
| B3 | **Full roster rebuild per keystroke** — `RosterData.lua` explicitly warns against this and `Refresh` does it anyway |
| B4 | **Multi-second freeze** hovering a dungeon-boss row — `Find` walks every remaining tier, the stutter `LootTable`'s header promises to avoid |
| B5 | Item tooltip scans and sorts all drops on every hover, including mousing across bags |
| B6 | **`Sync.Send` has no throttle** — five drops send five back-to-back addon messages with no ChatThrottleLib |

### C. UX

| # | Item |
|---|---|
| C1 | **`announceCaptures` on + every quality tracked = chat spam.** Named the uninstall trigger: one M+ run doubles the user's loot chat with greys |
| C2 | **"Who is due" has no window** — the README's headline pitch is chat-only, and the footer has no Due or Tonight |
| C3 | **Windows open dead-centre, nothing calls `Raise()`, footer buttons toggle.** Clicking a buried window's button *hides* it and nothing visibly happens |
| C4 | Empty states never say **history starts now and cannot be backfilled** |
| C5 | First-run chat never mentions `/syl` and reads "0 drops, 0 item records" |
| C6 | **No tooltips** on roughly 26 main-window controls |
| C7 | Toggle labels inconsistent — four name their state, one names an action then flips to a state |
| C8 | Two Settings rows are **permanently-unticked checkboxes** (`isChecked` hard-returns false for action rows) |
| C9 | `countPersonalLoot` is **not in Settings** despite changing the headline number |
| C10 | **`ROLLED ON` counts eligibility, not rolls** — officers will quote it in a dispute and be wrong |
| C11 | The roster's "Main's name…" box is built with `SearchBox` and a no-op callback — looks like the real search 100px above it |
| C12 | `/syl help` dumps 29 lines on any typo; README documents 10 and omits roster, settings, alts |
| C13 | **Archive Season is the most prominent button** and the one a new user should never press |
| C14 | Hardcoded default season name "Midnight Season 1" |
| C15 | Dead empty-state string in MainWindow, overwritten every draw |

### D. Cut candidates — reviewers say remove, not improve

| # | Item | Argument |
|---|---|---|
| D1 | **Raid buff coverage** | Never reads the live raid group; MRT and WeakAuras answer "what are we missing now" better. Recomputes on the post-search list, so typing a name announces missing buffs |
| D2 | **Raider.IO column** | Feeds nothing in the maths; everyone who cares already has Raider.IO |
| D3 | **Boss loot tables** | Best-engineered file in the repo, competing with the Adventure Guide and Wowhead |
| D4 | **The web dashboard** | Competes with WoWAudit, and `web/index.html:373` double-counts raiders so the two export paths disagree |
| D5 | **Officer sync** | Only reaches people who already captured everything; produces `partial` records excluded from the maths |
| D6 | **NOTES Phases 3–5** (vault, crests, Droptimizer wishlists) | WoWAudit's core product |
| D7 | **Refresh button** | Everything refreshes on show; it holds the leftmost footer slot |
| D8 | `/syl dev`, `api`, `debug`, `count`, `output` in the user-facing menu |
| D9 | `/syl recent`, `player`, `count` | Superseded by the merged list; they read raw chat capture |

**Note:** if F6 (modularity) lands first, most of D1–D5 become *default-off
toggles* rather than deletions. Worth deciding F6 before acting on D.

### E. Strategy

| # | Item |
|---|---|
| E1 | **Trade-window advisor.** On a win, tell the winner who rolled Need and lost, with their droughts and time remaining. **Unanimous top pick, and it has no cold start** — the roll list is complete on the very first drop, so it is useful on install night before any history exists. RCLootCouncil's `Modules/TradeUI.lua` is the reference: `TRADE_SHOW`, `TRADE_CLOSED`, `TRADE_ACCEPT_UPDATE`, `UI_INFO_MESSAGE` watching `LE_GAME_ERR_TRADE_COMPLETE`, target from `TradeFrameRecipientNameText:GetText()`, 5-minute timer to expire the two-hour window |
| E2 | **Trade tracking** — credit the recipient, not the winner. Today every traded item is two errors |
| E3 | **Store item level** on each record — one `GetDetailedItemLevelInfo` call turns item-count fairness into gearing fairness |
| E4 | **Scope every number to the raid team.** `RaidTeam` exists and feeds nothing that matters |
| E5 | **Something that reaches other people** — there is no `SendChatMessage` anywhere. Currently a private notebook |
| E6 | **Reposition.** The unique asset is the pass data: every eligible player and what each chose. Nothing else on the market has it. Suggested line: *"Group Loot remembers who won. This remembers who passed."* |
| E7 | Reconsider **All Rights Reserved** — tells an officer they are stranded if the author stops |
| E8 | **Sync backfill handshake**, or turn sync off |
| E9 | Screenshots show nothing differentiated; the end-of-night summary is missing |
| E10 | The alpha warning appears in the README, the CurseForge description **and** the .toc |

### F. The commercial risk nobody had named

A guild running Group Loot has, by definition, **chosen not to have a loot
process.** Handing them fairness analytics invites drama they opted out of.
E1 is the proposed answer: make the history a means to a decision people
already need, rather than an end in itself.

### G. Tooling

| # | Item |
|---|---|
| G1 | **`syl_check.py` does not catch bare module globals.** `RaidSession.RaidsOnly(...)` without `SYL.` passed clean and was a nil global. It knows every module name already, so flagging a bare one is cheap and would have caught three of today's bugs |

---

## 5. The modularity ask (F6), in more detail

Aimee wants ElvUI-style feature toggles: *"if people don't want things they
can turn it off."*

**RCLootCouncil is the model to copy** — not Ace3 itself, but the shape.
Nine modules loaded from `Modules/Modules.xml`, each one file with its own
enable state, core kept separate from modules.

**Decided direction, from NOTES.md:** a registry where each feature declares
a key, a default, and what it costs when on. Settings gets a Features list.
**Windows and commands for a disabled feature should not register at all**,
rather than being built and hidden — a feature that is off should cost
nothing.

Candidate toggles: raid buff coverage, the Raider.IO column, boss loot
tables, officer sync, personal-loot counting, the developer window, capture
announcements.

---

## 6. Traps that have already bitten

Written down because each cost real time.

- **Retail dungeons and M+ award personal loot.** There are no need/greed
  rolls, so `C_LootHistory` records nothing and the drops list is correctly
  empty of dungeons however many keys were run. Dungeon gear arrives as chat
  loot. This looked exactly like a capture bug.
- **Winning a roll also prints a chat loot line**, so `season.loot` overlaps
  `season.drops` almost entirely inside a raid. Any merge must subtract the
  overlap or it double-counts every raid drop.
- **`EJ_GetEncounterInfoByIndex` takes a `journalInstanceID` and ignores
  it** — the encounter list comes from the *current selection*, so the
  instance must be selected first. The documented parameter does not do
  what its name implies.
- **`ENCOUNTER_START` gives a dungeonEncounterID; `EJ_SelectEncounter`
  wants a journalEncounterID.** Different numbers for the same boss, and
  passing the wrong one returns another boss's loot rather than failing.
- **The packager rewrites the .toc version in the zip only.** The working
  copy is untouched, so a symlinked install reports whatever was last typed
  there.
- **`GITHUB_TOKEN` is read-only by default.** The first release uploaded to
  CurseForge successfully and *then* failed creating the GitHub release. A
  red workflow does not mean nothing shipped.
- **`itemEquipLoc` is not a reliable "is this gear" test.** Some
  non-equippable items report `INVTYPE_NON_EQUIP_IGNORE`. Item class is.
