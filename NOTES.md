# Notes

Requirements captured outside the code, so they survive between sessions.
Not a changelog — see `git log` for what has been built.

## Loot list filtering (requested 2026-08-05)

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
- Date multi-select probably means picking raid nights or days rather
  than arbitrary ranges. Worth confirming which.
- Filters need to compose with the existing Active / All-Time / Archive
  views rather than replace them.

## Row selection and per-line archiving (requested 2026-08-05)

Two interaction ideas, possibly both:

- A checkbox on each row to mark it
- Shift-click to select a range of rows

Then archive everything selected in one action.

Open questions to settle before implementing:

- **"Archive" currently means something else.** Today it archives an
  entire *season* — locks it and starts a new one. Archiving individual
  loot lines is a new concept and needs its own name and semantics, or
  the two will be confused in the UI.
- What should archiving a line actually do? Candidates: hide it from the
  default view, exclude it from fairness/analytics maths, or move it into
  a separate store. These are different features.
- Loot records already carry unused `archived` and
  `excludedFromAnalytics` booleans (set in `Core/LootCapture.lua`), so
  there is already a home for this without a schema migration.
- Nothing should ever be deleted, per the project's data philosophy.
  Archiving must stay reversible, which means the UI needs a way to view
  and un-archive lines.

## Relationship to Loot History storage

Multi-select filtering and per-row selection both push toward records
that are cheap to query and select individually. Worth weighing when
choosing between one record per drop versus one record per player-roll
for Loot History storage — that decision is still open.
