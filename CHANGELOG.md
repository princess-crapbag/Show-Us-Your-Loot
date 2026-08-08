# Changelog

What changed, for the person installing it. The commit history explains why;
this says what you will notice.

## Unreleased

### Added

- **Gear you were given, not just gear you rolled for.** Retail hands out a
  lot of loot with no roll at all: the Great Vault, the catalyst, and every
  dungeon and Mythic+ item, which are personal loot. None of it went through
  a group-loot roll, so none of it was in the drop history — and the due list
  could not see it. Press **Gear only** on the Chat Loot tab to see it, and
  it now resets a drought like any other upgrade. `/syl personalloot` turns
  that off if you would rather rank on raid rolls alone.
- **Raid loot and dungeon loot can be told apart.** A button cycles between
  all content, raids only and dungeons only. It works on history recorded
  before this, because the difficulty already says which is which even where
  nothing else did.
- **A raid roster.** Everyone in the guild, with class, rank, nights raided
  and Mythic+ score, and — the point of it — which raid buffs nobody covers.
  Tick names to add them to the raid team, set what they play, or map several
  at once as alts of one main. Team and role are per character, because you
  bring a character rather than a person.
- **Click a player** in the players window for their whole record: every drop
  they could have had, what they chose, and what they got.

### Fixed

- **Dungeons were being recorded as raid nights.** Any instance opened one, so
  every Mythic+ run added a five-person raid night to attendance. The due list
  ranks by nights attended, so a guild that runs keys together was partly
  ranked on dungeons. New nights are raids only, and existing dungeon
  sessions are left in the database but no longer counted — a counting bug is
  not a reason to delete history.

## 0.1.0-alpha

### Added

- **Alts count as one person.** Map a raider's second character to their main
  and every number — attendance, drought, the due list — treats them as one.
  `/syl alts scan` reads your guild notes and suggests mappings; nothing is
  applied until you accept it, because a mapping changes past numbers as well
  as future ones.
- **Mythic+ scores** in the players window, when the Raider.IO addon is
  installed. Sort by the column to rank your roster. Nothing in the fairness
  maths reads it — it is context, not an input.
- **Whole guild** toggle, so the players window shows every guild member
  rather than only those this addon has recorded loot for.
- **Boss loot tables.** Press *Loot tables* in the boss window to see how much
  of each boss's table you have actually seen drop, read from the in-game
  Adventure Guide. Hover the count for the item names, split into what has
  dropped and what never has.
- **Player history.** Click any row in the players window for that player's
  whole record: every drop they were eligible for, what they chose, what they
  rolled, and what they got. Eleven eligibles and no upgrades reads very
  differently depending on whether they passed eleven times or lost eleven
  rolls, and this is the window that tells you which.
- **Escape closes windows**, like every other panel in the game.
- **`/syl resetwindows`** puts every window back to its default size and
  centres it.

### Fixed

- **Scrolling hid rows as you went.** A scrolled list showed fewer and fewer
  entries with blank space below them, and the ones still visible were the
  wrong records. Only affected lists longer than about thirteen rows, which is
  why it went unnoticed.
- **Archived seasons never showed their group loot.** The records were kept
  correctly and simply never drawn, so archiving a season made its drops
  invisible. Opening an archive now shows them, with a button to switch to its
  chat loot.
- **Windows could be dragged larger than the screen**, taking the resize grip
  off the monitor with them and leaving no way back. Resizing is now bounded,
  and an oversized window saved from before is brought back on load.
- **The addon reported the wrong version** in exported data.
