# Changelog

What changed, for the person installing it. The commit history explains why;
this says what you will notice.

## 0.4.0 — 2026-08-15

### Added

- **Mythic 0 lockouts, on the Keys tab.** A grid of your characters against
  this season's dungeons, marked where each one is saved, with a countdown per
  row. Mythic+ has no lockout so it is not tracked; Mythic 0 is weekly during a
  patch week and daily once the season opens, and the addon never stores which
  — it reads when each lockout actually expires, so the changeover needs no
  update. The dungeon list comes from the game, so next season needs none
  either.
- **Absences on the calendar, with buttons.** Pick a day and mark somebody out
  or back in. The box starts with your own character, so marking yourself out
  is one click. Every absence records who set it and says so on the calendar.
- **Share who is out with the guild.** Off by default, its own switch in
  Settings. Everyone running the addon sees the same absences and who set each
  one. You can only take back the ones you set — somebody else's is theirs to
  remove, and the addon says who to ask.
- **The calendar shows the nights you raid.** Days with nothing recorded used
  to be blank, which was most of the future. Upcoming raid nights and anybody
  marked out now show on the grid. **Today** returns from wherever you have
  scrolled to.
- **Archived seasons can be renamed and merged.** Tick them on the Archives
  tab. Merging folds several into one — useful when a season boundary was
  taken a few days before the tier really changed. Nothing is deleted, though
  which season each record came from cannot be recovered afterwards, so it
  asks twice.
- **Type filter gains Ignored and Bonus roll**, so rows you have set aside can
  be gathered in one place instead of hunted for.

### Changed

- **Warbound gear no longer counts toward score or drought.** It goes to the
  account rather than to the raider who was standing there, which is the same
  reason a bind-on-equip drop has never counted. This changes existing numbers
  for anyone who has won one.
- **Bonus rolls are labelled.** They already counted for nothing — a bonus
  roll is not loot the raid awarded — but nothing on screen said so.

### Fixed

- **An alt mapping can be undone.** The roster screen could make one and had
  no way to remove it, so a character stuck as somebody's alt dragged that
  person onto every list, and the only way out was a command nobody had been
  told about. There is a **Not an alt** button now, and four places say so.
- **Two seasons could share an id** when one was archived and the next started
  in the same second, which made them indistinguishable to anything holding a
  reference to one. Existing collisions are repaired when you log in.

## 0.3.1 — 2026-08-11

**Updated for patch 12.1.0.** Without this the game marks the addon out of
date and will not load it unless you tick "Load out of date AddOns".

### Fixed

- **Archiving a season now actually starts you fresh.** Tier progress, the
  Raiders board, who is due, attendance and the calendar were all still
  counting archived seasons, so archiving changed nothing on screen: a new
  tier opened with the last tier's bosses listed and everybody carrying their
  old score. They read the current season only now.

  Nothing was deleted to fix this and nothing needs clearing. Your archived
  seasons are untouched and still readable on the Archives tab — the numbers
  were in the right place all along, and the screens were reading past them.

- **Settings no longer opens on top of the main window.** Once you had dragged
  any window, the step that decides where a new one goes was handed nothing to
  work around, and then left the window exactly where it was built — dead
  center, which is where the main window sits. Windows you have moved are
  counted now, and a window that cannot find a clear gap steps aside instead of
  sitting still. On a full screen it can still overlap; it will no longer land
  squarely on top.

- The addon list no longer labels this ALPHA. It stopped being an alpha at
  0.3.0 and the tag was left behind.

## 0.3.0 — 2026-08-10

**The first release that is not an alpha.** Every earlier upload was marked
Alpha, and CurseForge indexes a project by its latest non-alpha file — which is
why searching for this addon turned up six other things and not this one.

### Added

- **A dashboard, and it is what the window opens on.** Six tiles plus a
  full-width strip: last raid night, next raid night, who is due, readiness,
  tier progress and who is out, with recording and your links along the bottom.
  Click any tile to open the tab it is about. Every widget can be switched off
  in Settings.
- **The window has tabs** — Dashboard, Loot, Raiders, Calendar, Bosses, Keys,
  Archives — and **Settings moved to a cogwheel** in the top corner. The six
  footer buttons are gone; every one of them was a tab or the cogwheel.
- **Raiders is a board, not a table.** One bar per raider, its length being
  what they have taken per raid night, with the raid average drawn across it.
  Click anyone and the pane on the right shows where their number came from:
  every win that counted, what each was worth, and the total those add up to.
  A **Roster** view on the same tab is where you tick who is on the team and
  set their role — the two are the same people asked two questions, and the
  answer to the second decides who appears in the first.
- **Bosses is a rail and a loot table**, and it opens on what a boss has
  **never** given you. That is the one thing the loot list cannot tell you.
  Reading the Adventure Guide is a button rather than automatic, because it
  walks every raid tier and moves your own Journal selection.
- **Calendar** — a month of your raid nights, each shaded with what died, and a
  dense stat panel for whichever day you click. Two sessions in one evening are
  one night, and a raid running past midnight belongs to the night it started.
- **Keys** — every Mythic+ key the addon knows about, sortable, and you can ask
  a guildie to run theirs. A request is whispered to that one person and never
  broadcast: two people asking for the same key never learn about each other.
  Answer with Yes, Maybe or No, and only a No can be asked again. Dismissing a
  request hides it from the count and keeps it on the list until the weekly
  reset, so closing a popup can never lose one. Off by default.
- **The trade window advisor.** When you win something, a small window names
  everyone who rolled Need or offspec and lost, most owed first, with the clock
  on your two hours. **It works on the very first drop with no history at all**,
  which nothing else here does. An addon cannot click a trade button, so this
  only ever tells you who asked.
- **Traded loot follows the item.** Trade away something you won and the score
  credits whoever received it. Every traded item used to be two wrong numbers
  at once: you kept credit for loot you gave away, and the person wearing it
  looked like they had gone without.
- **A raid schedule that needs no calendar.** `/syl schedule days tue wed` once,
  and the next raid night is answered from then on. `/syl out Dravok 7 holiday`
  marks somebody out for a week and `/syl in Dravok` cancels it.
  `/syl schedule import` reads your in-game guild calendar on top of that, and
  never overwrites a night you typed. Absences are typed because an addon
  cannot read your Discord.
- **Loot is scored rather than counted.** A Need win is worth 100, offspec and
  greed 20 each, transmog 0 and no deduction. Who is due is ranked by score
  divided by raid nights attended, so somebody with perfect attendance ranks
  above somebody there half the time on the same amount of loot. Nobody with
  fewer than three nights is ranked at all — they are listed with the reason,
  rather than sorted to the top on an empty score.
- **Links.** A few URLs of your own, on the recording strip. Click one and it
  opens a box with the address selected to copy — an addon cannot open a
  browser or write to your clipboard. The Warcraft Logs and Raider.IO defaults
  point at your own guild page, built from your realm and guild name.
  `/syl link add <name> <url>` replaces one.
- **Officer sync sends roll lists.** A received drop is no longer partial, so
  it counts in the analytics and can say who lost as well as who won.
  `/syl sync backfill` asks the raid for the lists you are missing. Still off
  by default, still raid channel only, still guild members only.
- **Mythic+ keystones, yours and your guild's.** `/syl keys` lists what your
  characters hold, kept current at login, when a dungeon finishes, and when a
  key is rerolled. Turn on **Share Mythic+ keys with the guild** in Settings
  and it also shows everyone else's — for anyone in your guild running the
  addon with the same switch on. Nothing can read another player's bags, so
  that is the only way it can work. What goes out is one line about the
  character you are on: dungeon, key level, class. Off by default.
- **The roster hides characters nobody has played for a month.** An **Active**
  button, on by default. Anyone joining the guild is never hidden by it, and
  neither is anyone the client has not reported on yet.
- **Add someone who is joining but is not in the guild yet.**
  `/syl addraider Aimee-Silvermoon mage`. They appear marked **Joining**, count
  towards raid buff coverage, and can be put on the raid team before they
  arrive. When they join they move onto the roster by themselves, keeping their
  team place and role. `/syl dropraider Name-Realm` removes one.
- **Sort the loot list by any column.** Click PLAYER, ITEM, TYPE, WHERE or
  DATE; click again to reverse.
- **Ignore a record.** Tick rows and press **Ignore** to take them out of every
  number, for when a capture is simply wrong. The rows stay in the list,
  marked, and it is reversible. Nothing is deleted.
- **Hide or ignore every copy of an item.** Hold Shift when you press either
  button.
- **Features can be switched off.** Settings has a Features list — raid buff
  coverage, Mythic+ scores, boss loot tables, officer sync, key sharing, key
  requests, the trade advisor, following traded loot and the developer tools.
  Each says what it costs. Anything switched off is not built at all rather
  than built and hidden, so a `/reload` applies it.
- **Show the raid team, the guild, or everyone.** One button, shared by every
  screen that lists people, and `/syl scope` does the same from chat.

### Changed

- **Everything that ranks people ranks the same way.** `/syl due` sorted by
  nights-since-upgrade for a while after the board had moved to
  score-per-night. With one raider the two agree by accident; with a roster
  they name different people as most owed.
- **A drought is reset by one thing only:** a Need or offspec win, on a
  bind-on-pickup item, from group loot, on a night that counted as a raid
  night. The vault, Mythic+ chests, the catalyst, delves, personal loot handed
  out mid-raid and BoEs are all still recorded and still on the loot list, but
  no longer change who is due.
- **Settings fits on a screen.** Item qualities and features are three columns
  across rather than one long list, and what a feature costs is a tooltip
  rather than a second line under every row.
- **Lists of people default to your raid team**, then your guild, then
  everyone — whichever is the narrowest that can still show somebody. Keys is
  the exception, because half the names on a key list are not people you raid
  with.
- **Loot is no longer announced in chat as it is recorded.** Turn it back on in
  Settings or with `/syl announce`. Existing installs are switched off once,
  with a message saying so.
- **"Count gear taken without a roll towards droughts" is gone**, along with
  `/syl personalloot`.
- **The Refresh button is gone.** Every window already redraws when it opens.
- **`/syl recent`, `/syl player` and `/syl count` are gone**, replaced by the
  loot list and its filters.
- **`/syl dev`, `api`, `debug` and `output` are off the minimap menu.** They
  still work when typed and are listed by `/syl help all`.

### Fixed

- **Windows no longer open on top of each other.** They were being positioned
  before they were shown, and a window that has never been drawn cannot be
  measured — so the layout gave up and dropped them a few pixels from centre,
  which is to say onto whatever was already there.
- **The settings window was empty.** It drew its first heading and then nothing
  at all: no qualities, no toggles, no features. It read as an empty screen
  rather than the crash it actually was.
- **Keystones expire at your realm's actual weekly reset** rather than seven
  days after the addon heard about them.
- **Dates read MM-DD-YYYY everywhere.** Three different formats were in use
  depending on which window drew the row. The date filter boxes take
  MM-DD-YYYY too, and still accept YYYY-MM-DD if you paste one.
- **Some older records could not be ticked at all.** Rows captured before
  records carried an id drew a checkbox that did nothing. They are given one at
  login now, and the addon says how many it fixed, once.
- **Clear now clears the toggles too** — This season, Gear only and Raids only,
  not just the search box, the dropdowns and the dates.
- **A Timewalking raid could wipe somebody's drought.** Raid nights have never
  counted Timewalking, Story, Follower or Event difficulties, but *wins* were
  counted from everywhere — so a Timewalking raid on a Tuesday reset the clock
  without adding a night. Ordinary LFR is unaffected: it is group loot with
  real rolls and counts on both sides.
- **The chosen output window was remembered by position, not by identity.**
  Deleting any chat window shifted the ones below it, so the addon started
  writing into whichever window had moved into that slot.

## 0.2.0-alpha

A large update. Several of these change the numbers the addon reports, so
they are worth reading before your next raid night. Nothing is deleted by any
of it — history recorded under the old behavior stays, and the counting is
corrected when it is read.

### Added
- **A window for who is due.** The question this addon exists to answer was
  chat-only. There is now a **Due** button, first in the footer: dry nights,
  nights attended, when each raider last took an upgrade, and above the list a
  line saying what went into those numbers. Click a row for that raider's
  whole history.
- **A raid roster.** Everyone in the guild, with class, rank, nights raided
  and Mythic+ score, and — the point of it — which raid buffs nobody covers.
  Tick names to add them to the raid team, set what they play, or map several
  at once as alts of one main. Team and role are per character, because you
  bring a character rather than a person.
- **Gear you were given, not just gear you rolled for.** A lot of retail
  gearing never touches a roll: the Great Vault, the catalyst, and every
  dungeon and Mythic+ item. Press **Gear only** to see it. Whether it counts
  towards droughts is a setting — see *Changed* below.
- **Raid loot and dungeon loot can be told apart.** A button cycles between
  all content, raids only and dungeons only. It works on history recorded
  before this update.
- **Item level is recorded** on every drop from now on, and shown in the drop
  detail window.
- **Tooltips on the controls.** Roughly two dozen buttons had no explanation
  anywhere. "All content", "Gear only" and "All seasons" all narrow or widen
  the same list in different ways, and the only way to find out which was to
  press one and see what changed.
- **Empty lists say why they are empty**, including the thing nobody could
  have known: recording starts when you install the addon and cannot be
  backfilled.

### Changed
- **Gear taken without a roll no longer counts towards droughts by default.**
  This is the most important line here. Your client only ever sees other
  people's loot while you are grouped with them — nobody claims their vault
  standing next to you — so counting it counted almost entirely *your* gear.
  Your drought reset every week and nobody else's did, which quietly moved you
  to the bottom of your own due list.

  **If you were running the previous version this is turned off for you on
  update**, and the addon says so when it does. It was never reachable from
  the interface before now, so nobody chose it — it was on because it
  defaulted on. It is in **Settings** from this version, and when it is on
  only gear received while you were in a group is counted, which keeps the
  comparison even. `/syl due` says how many records were left out.
- **The ROLLED ON column is now ELIGIBLE**, because that is what it counts.
  Appearing on a roll list is not the same as rolling — a pass puts you on it
  too — and it is a number an officer would otherwise quote in a loot dispute
  and be wrong.
- **Only gear is announced in chat.** Every quality is still recorded, but a
  Mythic+ run no longer repeats every gray and reagent back at you.
- **Archive Season moved to the Archives tab** and is quieter. It ends the
  season, which is a once-a-tier action, and it was sitting top right on the
  loot list where a new user finds it first.
- **`/syl help` shows the ten commands you would actually use**, with
  `/syl help all` for the rest. A typo used to print all twenty-nine.
- **Windows raise instead of hiding when they are buried**, and no longer open
  exactly on top of each other.
- **Faster with a season of history**, most noticeably when scrolling the loot
  list, typing in the roster search, and hovering items in your bags.

### Fixed
- **The filter dropdowns did not open.** Player, Item, Location and Win type
  all threw an error when clicked, so nothing in the window could be filtered.
- **The addon only worked in English.** Loot lines were matched against
  English text, so on any other client every record was filed under one
  invented player called "Unknown". Patterns now come from the client's own
  strings.
- **A raid night that ran two difficulties counted as two nights.** Clearing
  Heroic and then pulling Mythic on the same evening put everyone who stayed
  for both a night ahead of everyone who came to one, on the only number the
  due list ranks by.
- **Dungeons were being recorded as raid nights**, so every Mythic+ run added
  a five-person raid night to attendance.
- **A solo Story clear opened a one-person raid night.** Story, Follower,
  Event and Timewalking difficulties are recorded and are not raid nights.
- **Attendance stopped completely if loot capture was off**, with nothing
  said. It no longer depends on loot capture.
- **A `/reload` mid-raid could record that boss's drops twice**, which reads
  as somebody winning the same item twice.
- **Crafting counted as gear you received**, so a guild's crafter looked
  permanently showered in loot and never appeared in the due list.
- **A world blue reset a Mythic raider's drought**, and so did a guild tabard.
  Only epics count now, and cosmetic slots never did belong.
- **Roles could not be changed for anyone the game called damage.** Clicking
  ROLE did nothing at all, permanently, for most of a raid group.
- **Roster ticks were being dropped.** Ticking three people found one at a
  time by searching, then pressing a bulk action, applied it to whoever
  happened to be on screen and cleared the rest without saying so.
- **Guild rank could change between refreshes** for anyone with alts. It is
  the main's rank.
- **Guild members who had never raided had no class**, so most of a large
  guild showed up in the roster with no color.
- **Alts declared in a public note were missed** if the character had an
  officer note of any kind — a trial date was enough. Both notes are read now.
- **Delves were filed as world loot**, alongside a quest reward from a city.
- **The same person appeared twice in the Player filter**, once per capture
  path, so filtering to them hid half their loot.
- **Item names and class colors went gray** everywhere except the main list
  after changing the theme, until a `/reload`.
- **Shift-clicking a chat-captured row pasted a broken link** into chat.
- **Hovering a dungeon boss froze the game for seconds.**
- **An open dropdown swallowed every right-click in the game**, and both the
  command menu and the filter dropdowns were left floating over the world
  after the window they belonged to closed.
- **Clicking a column header that could not sort** re-sorted by name and drew
  the arrow over the column you clicked.
- **Officer sync sent five messages back to back** when a boss dropped five
  items, in the busiest second of a raid. They are queued now.

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
  centers it.

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
