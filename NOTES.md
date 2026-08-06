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
