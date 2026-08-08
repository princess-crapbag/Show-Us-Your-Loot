# Notes

Requirements captured outside the code, so they survive between sessions.
Not a changelog — see `git log` for what has been built.

## Loot list filtering (requested 2026-08-05) — BUILT, UNTESTED IN GAME

The main window needs filtering across four fields:

- Player
- Item name
- Location
- Date

**Every one of these must support multi-select** — e.g. show loot for
Aimee *and* Dravok, in Manaforge Omega *and* Rotmire, across two chosen
raid nights. Not one value per field.

Implications worth deciding before building:

- Multi-select implies a dropdown with checkboxes per field, not a text
  box. A free-text search box is a separate feature and may still be
  wanted alongside it.
- Filter options should be derived from the records actually present, not
  a hardcoded list, so a new raid tier populates them automatically.
- Date filtering uses arbitrary start/end ranges.
- Filters need to compose with the existing Active / All-Time / Archive
  views rather than replace them.

## Row selection and per-line archiving (requested 2026-08-05) — BUILT, UNTESTED IN GAME

Two interaction ideas, possibly both:

- A checkbox on each row to mark it
- Shift-click to select a range of rows

Then archive everything selected in one action.

Decided:

- The per-line action is **Hide**, stored as a `hidden` boolean on the
  record. "Archive" stays reserved for archiving a whole season, so the
  two never get confused.
- Hiding is purely a display state and always reversible. Nothing is
  deleted, and a "Show hidden" toggle brings lines back.
- Hidden lines still count for analytics. Excluding a line from fairness
  maths is a separate concern and keeps its own
  `excludedFromAnalytics` flag.
- Date filtering is **arbitrary ranges**, not a list of raid nights.
- Both a free-text search box **and** multi-select filters, side by side.

Resolved while building: shift-clicking a row body already inserts the
item link into chat, which is a WoW convention worth keeping. So the
checkbox is the selection target and shift-click on a *checkbox* extends
the range. Both requested behaviours, neither at the cost of linking.

## Still open

- **Nothing in the addon has been run in game since the Loot History
  rework.** `python tools/syl_check.py` proves the files parse, that the
  .toc matches disk, and that every `SYL.Module.Member` reference
  resolves — it cannot prove behaviour. The next raid is the real test.
- Officer sync still sends drop headers only, never roll lists, so synced
  records sit out of the fairness maths. `/syl sync` reports how much of
  a season that covers. Chunked roll lists or a backfill handshake are
  the obvious next step and are deliberately not written blind: it is the
  only code that transmits to other players and needs two clients to
  test.
- Nothing here has been exercised in game. The likeliest problems are the
  filter dropdown's frame level and the date boxes' focus handling.
- Filtering by player on the Drops tab matches the **winner**. Matching
  anyone who rolled would answer different questions ("who keeps losing
  rolls") and is worth adding later as a separate option.
- Drops have no all-time or archived view yet; the All-Time tab still
  shows chat loot only. It will matter once a season is archived.
- The Archives list still cannot scroll past about nine seasons. Tracked
  separately; it predates all of this.

## Ten features to make this indispensable (drafted 2026-08-05)

Ordered roughly by effort. The first five are built; the rest need a
decision or are large enough to be worth discussing first.

1. **Raid sessions and true attendance** — BUILT. Eligibility is not
   attendance: roll lists only name players an item could drop for, so a
   healer who raided all night without being eligible looked absent. The
   group roster is now read at every pull and stored per night.
2. **Raids window** — BUILT. Every raid night: instance, difficulty,
   bosses pulled, kills, duration, how many people were there.
3. **Attendance in player stats** — BUILT. Nights present now come from
   the raid roster, and "attended but got no upgrade" is answerable for
   real rather than inferred from who happened to be eligible.
4. **Filter by win type** — BUILT. Need, offspec, transmog and greed are
   selectable filters, so "show me every transmog win" is one click.
5. **Item tooltips** — BUILT. Hovering any item anywhere in the game shows
   who won it and when, if this addon has seen it drop.
6. **Player detail window** — click a player to see their full history:
   every drop they rolled on, what they chose, what they won, their
   droughts. Medium effort; mostly a new window over existing data.
7. **Boss history** — BUILT. Per boss: pulls, kills, drops and upgrades,
   keyed by encounter *and* difficulty so Heroic and Mythic stay apart.
   Pulls come from raid sessions and drops from loot records, which are
   not the same age, so a boss farmed before sessions existed shows a
   dash rather than a zero. "Which items have never dropped" is still
   open: it needs a loot table to compare against, which nothing here
   has.
8. **A "due" list** — BUILT, with the judgement calls stated at the top
   of `Core/DueList.lua` rather than buried. Transmog and greed wins do
   not reset the clock; drought counts nights attended, not days elapsed
   or items rolled on. The ranking is one comparable number rather than a
   weighted score, so disagreeing means changing a rule, not retuning
   constants. **Both calls are open to challenge** — they were made to
   avoid blocking, not because they are settled.
9. **Officer sync** — share captured loot between officers over addon
   comms so no one person has to be present for everything. Technically
   possible and genuinely useful, but it is real network traffic to other
   players and needs a deliberate decision about what gets sent.
10. **Automatic raid-night summary** — post the night's loot to the chat
    window when the raid ends, ready to paste. Small, but it needs a rule
    for when a night has actually ended.

## Where things stand (end of 2026-08-05)

Confirmed working in game: the addon loads, boss history renders, the theme
picker works, and Nightfall is the default. Confirmed working end to end in
the browser: WoW to SavedVariables to uploader to Supabase to dashboard, 5
drops and 25 players, signed in with Discord.

Next session, roughly in order:

1. **Raid nights is still unproven.** The window has never had data in it —
   sessions only started recording after the raid that produced the current
   5 drops, so it shows 0. The next real pull is the first test of
   RaidSession, the attendance roster, and the end of night summary that
   fires on leaving the instance.
2. **The due list has no attendance to rank yet**, for the same reason. It
   will stay empty until raid nights exist.
3. **The two judgement calls in DueList.lua are open**: transmog and greed
   not resetting the drought, and drought counted in nights attended.
   Neither has been agreed, only assumed.
4. **Officer sync still has no protocol work** — headers only, no roll
   lists, no backfill. Needs two clients to test, so it needs a second
   person more than it needs code.
5. Sign-in on the dashboard is Discord only in practice. Email magic links
   are built but the free tier fights them; see README-SYNC.md.

## Competitive position and the player registry (drafted 2026-08-06)

Researched against CurseForge rather than assumed. Two findings decide
everything below.

**The top of the download charts is not the competition.** DBM, Details!,
WeakAuras, Plater, Bagnon, Raider.IO — combat, UI, inventory, navigation.
None of them touch loot history and none of them can be absorbed. "One
addon instead of many" is an unwinnable pitch aimed there.

**The loot and guild officer shelf, on the other hand, is nearly empty.**
RCLootCouncil (33.2M) records history only as a byproduct of running a
council, so a guild on Group Loot gets nothing from it. Method Raid Tools
(53.1M) has a loot log buried in a large raid-tools suite. Guild Roster
Manager (4.8M) has no loot at all. Below those: Guild Raid Attendance
(26.7k, last updated 2021), Guild Loot Tracker (3.4k, 2022, classic only,
author says it is not ready), Loot History (1.1k, classic only), PlusOne
(751), Guild Loot Distribution (124). Retail plus Group Loot plus
guild-wide history plus fairness is not currently served by anything with
users.

So the pitch is not "replace twenty addons". It is that an officer today
runs RCLootCouncil for a history they do not use a council for, a vault
addon, GRM, and a spreadsheet — and this can be all four.

### What the features actually need

Seven features were picked out of that research: alt mapping, gear
acquired outside the raid, real upgrade detection, wishlists, a
who-should-this-go-to panel, trade tracking, and a Raider.IO tie-in.

They all want the same missing thing. The data model is drop-centric —
`season.drops` holds records with embedded roll lists, and DueList,
Analytics and BossStats all work by sweeping that array. There is no
durable per-player entity, and every one of these features attaches facts
to a player over time rather than to a drop.

`season.players` has been created by `EnsureSeasonStructure` since the
beginning and written to by nothing, exactly as `season.raids` sat unused
until RaidSession filled it. That is the home.

**Decided: one resolver, one choke point.** `Players.ResolveToMain(key)`
is the only place alt identity is applied. DueList and Analytics route
their roster and roll keys through it and are otherwise untouched. Getting
this wrong in one place is recoverable; scattering it is not.

### Phase 0 — Core/Players.lua

The registry, keyed by GUID: identity (`mainGUID`, `identitySource`), gear
(`equipped`, `itemLevel`, `spec`), external (`raiderIO`), and weekly state
(`vault`, `currencies`, `tierCount`). Local data and a resolver, nothing
that transmits.

### Phase 1 — main and alt mapping

Three sources, priority ordered: manual mapping always wins, then guild
note parsing, then inference that is only ever *suggested* and never
applied on its own.

Guild notes are the cheap win. `Guild.Refresh` already calls
`GetGuildRosterInfo` and reads four positional fields; the public note is
index **7** and the officer note index **8**, with the GUID at 17 that the
file already reads. The near-universal convention is the main's name
written in one of them.

**Mappings apply retroactively.** The moment one is added, historical due
list numbers change. That is correct, and it will still surprise someone,
so the UI has to say how many mappings are folded into the numbers it is
showing.

### Phase 2 — gear and real upgrade detection

The first draft of this was wrong twice and both corrections matter.

It proposed depending on Pawn. Pawn is still maintained, but
`PawnGetItemValue` evaluates an item against *your* scale for *your* spec
on *your* client — there is no way to ask what an item is worth to someone
else, which is the only question this addon has. Wrong dependency
regardless of popularity. **Cut entirely.**

It then proposed reading other players' gear by inspection.
`NotifyInspect` is throttled and async and cannot cover 25 people at drop
time. But SimulationCraft works precisely because it reads *your own*
character, where `GetInventoryItemLink("player", slot)` is unrestricted,
complete and instant. The inspect problem is an artefact of assuming one
client reads everyone.

**Decided: self-report, not inspection.** Each client reports its own
state. Inspection demotes to a fallback for players not running this, and
what it produces is marked partial in the same way synced drops already
are. Upgrade detection then stops being the hardest item on the list and
becomes a consequence of Phase 3.

Do not copy from simc-addon: it is GPLv3 and this project is All Rights
Reserved. Reading nineteen slots with Blizzard APIs is a dozen lines and
avoids the question.

### Phase 3 — weekly state: vault, crests, catalyst, tier

Not four features. One payload, sent at one moment.

- **Vault.** `C_WeeklyRewards.GetActivities()` returns per row: `type`
  (Raid / Activities / RankedPvP / World), `threshold`, `progress`,
  `level`, `raidString`, `claimID`, and a `rewards` array of
  `{type, id, quantity, itemDBID}`.
- **Crests and catalyst charges.** Plain currencies via
  `C_CurrencyInfo.GetCurrencyInfo`.
- **Tier pieces, 0–5.** `C_Item.GetItemInfo` returns `setID` as its 16th
  value. Count matching setIDs across equipped slots. This is *derived*
  from Phase 2's gear and costs no extra collection. Catalyst-made pieces
  carry the same setID as dropped ones, so conversions count for free.

**Decided: user-initiated, at the vault.** Reward item data is not
reliably populated until the vault frame has been loaded — there is an
addon whose entire description is that it exists because Blizzard made
this hard. A share button pressed while the vault is open is the moment
the data is guaranteed good *and* is consent by construction. That
removes the need to change the background sync posture at all, which was
otherwise the largest open question in this plan.

**Still open, and it is the same judgement call DueList already faced
once:** someone who never presses the button is invisible, and it will be
the same people every week. "Took nothing" and "did not tell us" must not
collapse into each other, exactly as synced drops are marked `partial`
rather than being read as "nobody was eligible".

Currency IDs rotate every season — the catalyst charge was 2533 one
season and 2796 the next. Do not hardcode them. Either discover them by
category at runtime or ship a table that is updated per patch and knows
when it is stale; silently reporting zero crests for the whole guild is
the failure mode.

There is no API for another player's vault. Self-report or nothing, and
weeks before install are permanently blank.

### Phase 4 — wishlists, folded into Droptimizer import

Raiders already run SimulationCraft and Raidbots. A Droptimizer result is
a ranked wishlist with real simulated numbers attached, so importing one
gives both the wishlist and the upgrade values. No separate wishlist
builder.

The addon cannot fetch anything, so in-game this is a paste. The natural
home for the fetching and compaction is the existing Python toolchain
next to `syl_upload.py`, with the web dashboard doing the bulk work.

**Verify before designing against it:** whether Raidbots exposes report
data at a stable JSON endpoint for a report id. Not confirmed. If it does
not, this degrades to each raider exporting their own.

### Phase 5 — who should this go to

Ranks the eligible players during the two-hour trade window by due
position, wishlist match, upgrade delta and vault-adjusted drought.

Protected loot buttons cannot be clicked by an addon — Guild Loot
Distribution hit that wall and had to fall back to announcing. Purely
informational is the only option, which happens to be exactly the stated
positioning rather than a compromise.

### Phase 6 — trade tracking

Group Loot's defining mechanic is that a win is tradable for two hours,
and nothing tracks whether the winner honoured it. `TRADE_SHOW` and
`TRADE_ACCEPT_UPDATE` plus slot scanning give "X traded Y to Z". Only the
winner's client knows, so it is another self-report. DueList should then
credit the recipient rather than the winner — another correctness fix
wearing a feature's clothes.

### Raider.IO

Guild.lua already states the constraint correctly: addons have no network
access. So this splits in two.

In game, a soft dependency on the installed addon — 442M downloads, so
nearly everyone has it. `RaiderIO.GetProfile(name, realm)` returns
`mythicKeystoneProfile`, `raidProfile` and `recruitmentProfile`;
`RaiderIO.GetScoreColor(score)` gives consistent colouring. Guarded, with
`## OptionalDeps: RaiderIO` in the .toc. Their data is a static bundle
shipped with their releases, so it lags live by days — fine for roster
context, wrong for anything time sensitive.

The web dashboard is not an addon and can call the real API. Live scores
and progress belong there. That split is a genuine advantage over
pure-addon competitors.

### Order, and the one real cost

Phase 0, then Phase 1 and Raider.IO — both small, independent, and
verifiable without a raid. Phase 3 next as the biggest win, then Phase 2,
then 4 and 5. Phase 6 is independent and can slot anywhere.

**Chunked sync is now the real prerequisite.** Gear alone is nineteen
slots of itemID and ilvl, roughly 210 bytes before headers against the
250 byte cap in Sync.lua. Vault and currencies push well past it. Three
separate features now depend on the protocol work that has been deferred
since sync was written. Accepted deliberately: the payload will grow and
the transport has to grow with it.

**The honest risk:** none of raid nights, attendance or the due list has
been through a full raid yet. This plan stacks four more untested systems
on three untested ones. Phase 1 and Raider.IO are cheap and independently
checkable, which is why they go first.

## Built on 2026-08-06, none of it run in game

Phase 0, Phase 1, Raider.IO and the loot tables. `syl_check.py` is clean
across all 57 files, which proves they parse and that every reference
resolves — it cannot prove behaviour.

**Core/Players.lua** — the registry, account level, with
`ResolveToMain` as the single choke point. DueList, Analytics and
`RaidSession.BuildAttendance` all route their keys through it.

**Core/AltDetect.lua** — guild note parsing. Proposes, never applies; see
the reasoning in the file header. Accepted proposals are stored as
`manual` so a later note edit cannot quietly undo an officer.

**Core/AltCommands.lua** — `/syl alts`, `scan`, `apply`, `set`, `clear`.

**Core/RaiderIO.lua** — soft dependency, every call guarded and wrapped.
`AttachScores` stamps the score onto Analytics entries before sorting.
The players window has an M+ column and widened to 820 to fit it.

**Core/LootTable.lua** — the Encounter Journal, and the answer to "which
items have never dropped" that this file listed as blocked.

Three things worth knowing about it:

- **The two id spaces are not the same number.** ENCOUNTER_START and the
  loot history give a *dungeonEncounterID*; `EJ_SelectEncounter` wants a
  *journalEncounterID*. Passing one for the other returns another boss's
  loot, which is worse than returning none. `EJ_GetEncounterInfoByIndex`
  returns both, so a bridge is walked once and held in memory.
- **BossStats did not store the encounter id**, only baked it into its
  key as text. It carries it as a field now.
- **Reading the journal moves it.** Selecting an instance, difficulty and
  encounter changes what the player is looking at, so the selection is
  saved and restored. The walk is also behind a button rather than run on
  window open, because it covers every raid tier.

### Judgement calls made while building, all open to challenge

1. **The registry is account level, not `season.players`.** Reasoned
   above. It contradicts the plan two sections up, which was written
   first.
2. **An alt and a main in the same raid is one night, not two.** Counting
   it twice would push somebody *down* the due list for turning up.
   Pulls still sum across every character they brought.
3. **Name lookups are case-insensitive.** Notes and slash commands are
   typed by people; rosters are not. Both indices lowercase their keys.
4. **A name that two realms share resolves to nobody** rather than to a
   guess. `nameIndex` stores `false` for the collision.

### Still not done

Phases 2, 3, 5 and 6, all of which need chunked sync first. Phase 4
follows from Phase 2. Nothing has been tested against a second client or
a live raid, and the likeliest disappointment is the note patterns not
matching how this guild actually writes them — `/syl alts scan` changes
nothing, so it is safe to run and read.

## How the competition is built (researched 2026-08-08)

Read from source where possible rather than from descriptions.

### RCLootCouncil — the one worth copying from

Ace3-based, and organised as **nine modules loaded from Modules/Modules.xml**:
lootFrame, versionCheck, votingFrame, sessionFrame, options, History/
lootHistory, History/CSVImport, TradeUI, Sync. Core is separate from
modules, and Classes/ splits Data, Services and Utils.

The important lesson is the shape, not the framework: **features are modules
with their own file and their own enable state**, not branches inside one
window. That is what makes "turn this off" possible at all.

**Its loot history UI** uses lib-st (LibScrollingTable) rather than
hand-rolled rows. Columns are declared as data:

    { name = _G.NAME, width = 100, sortnext = 3, defaultsort = 1 }

with optional `comparesort` and `DoCellUpdate` per column. Sorting,
tie-breaking to another column, and per-cell rendering are all declarative.
Ours hand-builds rows and hardcodes sort comparators per window — three
windows now carry near-identical sorting code.

**Its filtering is three dimensions at once**: response (Need/Greed/Pass/
autopass/status), class, and a single selected name plus a single selected
date. Name and date are not dropdowns — they are **two small scrolling tables
beside the main one**, and clicking a row in either restricts the main table.
That is a better fit for "which of my raiders" than our multi-select
dropdown, and worth stealing.

Its data is stored **hierarchically**, `data[date][playerName] = { entries }`,
which makes date and player grouping free. Ours is a flat array swept per
draw.

**TradeUI is a whole module** and is the closest thing to the trade-window
advisor four reviewers asked for. It registers `TRADE_SHOW`, `TRADE_CLOSED`,
`TRADE_ACCEPT_UPDATE` and `UI_INFO_MESSAGE`, watches for
`LE_GAME_ERR_TRADE_COMPLETE` to confirm a trade landed, reads the target from
`TradeFrameRecipientNameText:GetText()`, and runs a 5-minute repeating timer
to expire items past the two-hour window. That is the event set to copy.

### The others

- **WoWAudit** is a website with a companion addon. Roster, vault, wishlists
  and attendance live server-side. Competing with it in-game is a losing
  fight; NOTES Phases 3-5 are its core product.
- **Raider.IO** ships a static data bundle and exposes GetProfile to other
  addons. We already consume it correctly.
- **MRT** is a large suite where the loot log is one module among many.

### Modules, the ElvUI way

ElvUI's appeal is that every module can be switched off and the rest keeps
working. Same principle here, and RCLootCouncil already proves the file
layout: one feature, one file, one enable flag, checked at load and honoured
at runtime.

**Decided direction:** a registry where each feature declares a key, a
default, and what it costs when on. Settings gets a Features list. Windows
and commands for a disabled feature do not register at all, rather than
being drawn and then hidden — a feature that is off should cost nothing.

Candidates for toggles, from the reviews: raid buff coverage, the Raider.IO
column, boss loot tables, officer sync, personal-loot counting, the
developer window, capture announcements.
