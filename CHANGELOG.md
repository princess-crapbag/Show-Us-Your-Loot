# Changelog

What changed, for the person installing it. The commit history explains why;
this says what you will notice.

## Unreleased

### Added

- **Gear you were given, not just gear you rolled for.** Retail hands out a
  lot of loot with no roll at all: the Great Vault, the catalyst, and every
  dungeon and Mythic+ item, which are personal loot. None of it went through
  a group-loot roll, so none of it was in the drop history. Press **Gear
  only** on the Chat Loot tab to see it.

  It does **not** count towards the due list unless you turn it on with `/syl
  personalloot`, and it is worth knowing why before you do. Your client only
  ever sees other people's loot while you are grouped with them — nobody
  claims their vault standing next to you — so with it on, the only vault
  claims in the database are your own. Your drought resets every week and
  nobody else's does, and you sink to the bottom of your own list. With it
  on, only gear received while you were in a group is counted, which keeps
  the comparison even, and `/syl due` says how many items were left out.
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

- **The addon only worked in English.** Loot lines were matched against the
  literal English "receives loot:", so on any other client nothing matched and
  every record was filed under one invented player called "Unknown". The
  patterns are now built from the client's own strings, so it reads Korean and
  Russian as well as it reads English. A line it genuinely cannot read is
  skipped rather than credited to nobody.
- **A raid night that ran two difficulties counted as two nights.** Clearing
  Heroic and then pulling Mythic on the same evening put everyone who stayed
  for both a night ahead of everyone who came to one, on the only number the
  due list ranks by. The record still shows both runs; attendance counts the
  night once.
- **Attendance stopped completely if loot capture was off.** `/syl capture`
  off also silenced raid nights, rosters and the due list, with nothing said.
  Attendance no longer depends on loot capture.
- **A `/reload` mid-raid could record that boss's drops twice**, which reads
  as somebody winning the same item twice. A pull now keeps its identity
  across a reload.
- **Crafting counted as gear you received.** Making a piece for somebody else
  prints down the loot channel, so a guild's crafter looked permanently
  showered in loot and never appeared in the due list.
- **A world blue reset a Mythic raider's drought**, and so did a guild tabard.
  Only epics count now, and cosmetic slots never did belong.
- **Guild rank could change between refreshes** for anyone with alts, because
  it was read off whichever character came up first. It is the main's rank.
- **Roster ticks were being dropped.** Ticking three people found one at a
  time by searching, then pressing a bulk action, applied it only to whoever
  happened to be on screen — and cleared the rest without saying so.
- **Roles could not be changed for anyone the game called damage.** Clicking
  ROLE did nothing at all, permanently, for most of a raid group.
- **Guild members who had never raided had no class**, so most of a large
  guild showed up in the roster with no colour and no class.
- **Alts declared in a public note were missed** if the character had an
  officer note of any kind — a trial date or a spec reminder was enough. Both
  notes are read now.
- **Delves were filed as world loot**, alongside a quest reward from a city.
- **A solo Story clear opened a one-person raid night.** Story, Follower,
  Event and Timewalking are recorded, and are not raid nights.
- **Item names and class colours went grey** everywhere except the main list
  after changing the theme, until a `/reload`.
- **Shift-clicking a chat-captured row pasted a broken link** into chat.
- **The same person appeared twice in the Player filter**, once per capture
  path, so filtering to them hid half their loot.
- **Clicking a column header that could not sort** re-sorted by name and then
  drew the arrow over the column you clicked.
- **Open dropdowns swallowed every right-click in the game**, and both the
  command menu and the filter dropdowns were left floating over the world
  when the window they belonged to closed.
- **Item level is recorded** on every drop from now on, so a Champion piece
  and a Myth piece are no longer indistinguishable. It is shown on the drop
  detail window; what the fairness maths does with it is still an open
  question and has not been changed.
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
