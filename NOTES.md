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

- Nothing here has been exercised in game. The likeliest problems are the
  filter dropdown's frame level and the date boxes' focus handling.
- Filtering by player on the Drops tab matches the **winner**. Matching
  anyone who rolled would answer different questions ("who keeps losing
  rolls") and is worth adding later as a separate option.
- Drops have no all-time or archived view yet; the All-Time tab still
  shows chat loot only. It will matter once a season is archived.
- The Archives list still cannot scroll past about nine seasons. Tracked
  separately; it predates all of this.
