# Changelog

What changed, for the person installing it. The commit history explains why;
this says what you will notice.

## Unreleased

### Added
- **A dashboard, and it is what the window opens on.** Six tiles plus a status
  strip: last raid night, next raid night, who is due, readiness, tier
  progress, links, and whether the addon is actually recording. Click any tile
  to open the tab it is about. Every widget can be switched off and reordered
  in Settings.
- **The window has tabs now** — Dashboard, Loot, Raiders, Nights, Bosses,
  Keys, Archives — and **Settings moved to a cogwheel** in the top corner. The
  six footer buttons are gone; every one of them was a tab or the cogwheel.
- **Loot is scored rather than counted.** A Need win is worth 100, offspec and
  greed 20 each, transmog 0 and no deduction. Who is due is now ranked by
  score divided by raid nights attended, so somebody with perfect attendance
  ranks above somebody there half the time on the same amount of loot. Nobody
  with fewer than three nights is ranked at all — they are listed with the
  reason, rather than sorted to the top on an empty score.
- **Links.** A few URLs of your own on the dashboard. Click one and it opens
  a box with the address selected to copy — an addon cannot open a browser or
  write to your clipboard. `/syl link add <name> <url>` adds one,
  `/syl link remove <name>` takes it away, `/syl link` lists them.
- **The roster hides characters nobody has played for a month.** An **Active**
  button on the roster window, on by default. Anyone joining the guild is
  never hidden by it, and neither is anyone the client has not reported on
  yet. Press it for everyone.
- **Mythic+ keystones, yours and your guild's.** `/syl keys` lists what your
  characters hold, kept current at login, when a dungeon finishes, and when a
  key is rerolled. Turn on **Share Mythic+ keys with the guild** in Settings
  under Features and it also shows everyone else's — for anyone in your guild
  running the addon with the same switch on. Nothing can read another
  player's bags, so that is the only way it can work. What goes out is one
  line about the character you are on: dungeon, key level, class. No loot, no
  attendance, and nothing anybody sees in chat. Keys older than a week are
  dropped rather than shown stale. Off by default.
- **Add someone who is joining but is not in the guild yet.**
  `/syl addraider Aimee-Silvermoon mage`. They appear on the roster marked
  **Joining**, count towards raid buff coverage, and can be put on the raid
  team before they arrive — so "we have no Mage" is right for the raid you are
  actually bringing. The class has to be typed because the client cannot look
  up a character it has never seen. When they join the guild they move onto
  the roster by themselves, keeping their team place and role.
  `/syl dropraider Name-Realm` removes one.
- **Sort the loot list by any column.** Click PLAYER, ITEM, TYPE, WHERE or
  DATE; click again to reverse. It opens on newest first, as before.
- **Ignore a record.** Tick rows and press **Ignore** to take them out of
  every number — the due list, droughts, player stats — for when a capture is
  simply wrong. The rows stay in the list, marked, and it is reversible.
  Nothing is deleted.
- **Hide or ignore every copy of an item.** Hold Shift when you press either
  button. Hiding one Dawn Crystal used to leave the other two.
- **Features can be switched off.** Settings has a Features list: raid buff
  coverage, Mythic+ scores, boss loot tables, officer sync and the developer
  tools. Each says what it costs when it is on. Anything switched off is not
  built at all rather than built and hidden, so a `/reload` applies it.
- **Windows no longer open on top of each other.** They are laid out as a set
  and centred as a group, so opening the loot list and the due list puts them
  side by side. Drag a window and the addon stops rearranging that one.
- **Officer sync can send messages longer than 255 bytes.** Groundwork only:
  what it sends is unchanged, still drop headers and never roll lists.
- **The list says how many rows are selected.** On the summary line, beside
  the item and hidden counts. There was a separate label for it that drew on
  top of that sentence.
- **Show the raid team, the guild, or everyone.** A button on the due list and
  the players window switches between the three, and `/syl scope` does the
  same from chat. Both windows share the one setting.

### Changed
- **A drought is now reset by one thing only:** a Need or offspec win, on a
  bind-on-pickup item, from group loot, on a night that counted as a raid
  night. Everything else — the vault, Mythic+ chests, the catalyst, delves,
  personal loot handed out mid-raid, and BoEs — is still recorded and still
  on the loot list, but no longer changes who is due.
- **"Count gear taken without a roll towards droughts" is gone**, along with
  `/syl personalloot`. It only ever fed the calculation above, and that
  calculation no longer counts any of it under any setting.
- **The due list and the players window now open on your raid team.** They
  used to open on everyone the addon had ever seen, which includes anybody
  you pugged a raid or a key with — and somebody seen once who won nothing
  ranks *above* a raider of two years, because one night without an upgrade
  is still a drought. If nobody is marked as being on the team they open on
  your guild instead, and if you are not in a guild, on everyone. Mark the
  team in the roster window's TEAM column.
- **Loot is no longer announced in chat as it is recorded.** It is still
  recorded — the addon just does not say so every time, and a full clear no
  longer fills your chat with lines nobody asked for. Turn it back on in
  Settings or with `/syl announce`. Existing installs are switched off once,
  with a message saying so.
- **"Guild only" on the players window is now part of the scope button**, and
  "Whole guild" is called **Include non-raiders**, which is what it does: it
  adds guild members with no recorded history to the list.
- **One line at login instead of two.** "Show Us Your Loot loaded!" said
  nothing the "Ready." line a moment later does not.
- **The Refresh button is gone.** Every window already redraws when it opens
  and whenever anything changes, so it was a button that did nothing you
  could see.
- **`/syl recent`, `/syl player` and `/syl count` are gone**, replaced by the
  loot list and its filters, which read the same records and rather more.
- **`/syl dev`, `api`, `debug` and `output` are off the minimap menu.** They
  still work when typed and are listed by `/syl help all`.

### Fixed
- **Keystones now expire at your realm's actual weekly reset** rather than
  seven days after the addon heard about them. A key learned on Monday used to
  survive Tuesday's reset and sit in the list claiming to be current.
- **Dates read MM-DD-YYYY everywhere.** Three different formats were in use
  depending on which window drew the row — `08/05/2026`, `08/05/26` and
  `2026-08-05`. The date filter boxes take MM-DD-YYYY now too, and still
  accept the old YYYY-MM-DD if you paste one.
- **Some older records could not be ticked at all.** Rows captured before
  records carried an id drew a checkbox that did nothing: Select all skipped
  them, and Hide and Ignore could never reach them. They are given an id at
  login now and behave like any other row. The addon says how many it fixed,
  once. Aimee hit this with twenty records that survived a Select all → Hide
  and looked like a bug in Hide.
- **Clear now clears the toggles too** — This season, Gear only and Raids
  only, not just the search box, the dropdowns and the dates. A list that
  said it was cleared while Gear only was still on was hiding every reagent,
  which is how the twenty above went unnoticed. Show hidden is deliberately
  left alone: everything else narrows the list, so clearing shows more, and
  that one would show less.
- **A Timewalking raid could wipe somebody's drought.** Raid nights have never
  counted Timewalking, Story, Follower or Event difficulties — but *wins* were
  counted from everywhere, so a Timewalking raid on a Tuesday reset the clock
  without adding a night. A raider two months dry showed zero dry nights and
  dropped off the list the list exists to build. Upgrades now count only from
  content that would have counted as a night. Ordinary LFR is unaffected: it
  is group loot with real rolls and counts on both sides, as it always did.
- **The chosen output window was remembered by position, not by identity.**
  Deleting any chat window shifts the ones below it, so the addon started
  writing into whichever window had moved into that slot. It remembers the
  window's name now.

## 0.2.0-alpha

A large update. Several of these change the numbers the addon reports, so
they are worth reading before your next raid night. Nothing is deleted by any
of it — history recorded under the old behaviour stays, and the counting is
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
  Mythic+ run no longer repeats every grey and reagent back at you.
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
  guild showed up in the roster with no colour.
- **Alts declared in a public note were missed** if the character had an
  officer note of any kind — a trial date was enough. Both notes are read now.
- **Delves were filed as world loot**, alongside a quest reward from a city.
- **The same person appeared twice in the Player filter**, once per capture
  path, so filtering to them hid half their loot.
- **Item names and class colours went grey** everywhere except the main list
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
