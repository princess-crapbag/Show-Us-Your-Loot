# Changelog

What changed, for the person installing it. The commit history explains why;
this says what you will notice.

## 0.4.4 — 2026-09-03

### Added

- **Send my roster.** A button on the Raiders → Raid team screen, next to
  Clear shared, that sends your raid team to the guild once. It works whether
  or not the sharing switch is on, because pressing it *is* the asking, and it
  says afterwards where the switch lives if you want the guild kept up to date
  automatically.

- **Send loot history.** New on Settings → Tools, beside Export for Discord.
  Gives one officer this season's drops — who won each item, who rolled, and
  the credit corrections you set by hand — so their Raiders board scores the
  same items the same way yours does. An officer who installed the addon
  mid-tier had no way to get the weeks before they arrived, and their board
  showed a dash for nearly everyone on it.

  It goes to one person, never the guild, and they are asked first: they see
  how many drops, from which season, and how long it will take before anything
  arrives. A season of 130 drops is about four minutes of trickle, with a
  progress bar and a Stop. Anything they already recorded is kept — where you
  both hold the same drop, theirs keeps its own roll list and takes your credit
  mark, because that is the part somebody typed rather than watched.

### Fixed

- **A shared raid team could replace yours without asking.** A roster
  broadcast over the guild channel used to become yours on the spot, with
  nothing but a caption underneath naming who sent it. That works while
  exactly one person in the guild is sharing. The moment a second person turns
  the switch on, two rosters compete for one slot and the newest one wins
  silently — so an officer who ticked two names onto their own list put those
  two names on everybody else's board.

  A roster from a name you have not agreed to now waits and asks, showing the
  names and roles in it so you can tell at a glance whether it is the list you
  want. Say yes once and that person's later changes arrive quietly; say no and
  they are not asked about again. Nobody else can replace what you accepted or
  empty it. **Clear shared** still removes it, and now also forgets the
  agreement, so the next offer asks again rather than putting it straight back.

- **An officer with nobody ticked could wipe the guild's roster, repeatedly.**
  Every client asks the guild for a roster at login, and everyone sharing
  answers. Somebody sharing with an empty raid team answered with an empty
  roster — a real message, meaning *"I have cleared my team"* — and every
  client obeyed it. Their own team was empty precisely because everything they
  could see belonged to somebody else's shared roster, which is deliberately
  not rebroadcast. The list did not even go visibly blank: with nobody marked,
  the scope button quietly fell through to Guild and filled with everyone in
  the guild instead.

  Nothing is sent now when there is nothing to say, and an empty roster is only
  obeyed from the person whose roster you accepted.

- **A shared roster could go missing for good at login.** The addon asks the
  guild for a roster the moment you log in, but only accepts an answer from
  somebody it can see in the guild list — which has not loaded yet at the
  moment the question goes out. An answer arriving in those first seconds was
  thrown away in silence, the sender stayed quiet for twenty more, and nothing
  ever asked again. It asks a second time now, once the guild list is there.

### Changed

- **The roster sharing switch is worded so it cannot be read backwards.** It
  said *"Share your raid team with the guild"*, which somebody who wants a
  roster reads as the switch that gets them one — and turning it on for that
  reason is what caused the trouble above. It now says **"Keep the guild's copy
  of my raid team up to date"**, and says plainly that you need nothing at all
  switched on to receive somebody else's.

## 0.4.3 — 2026-09-02

### Added

- **Archived raiders.** Taking somebody off the raid team takes them off the
  Raiders board, which is what the board is for — but it used to take their
  season with them, and their nights, items and rolls were nowhere on the
  screen that holds them. There is a fourth button on the Raiders tab now:
  **Archived** lists everyone in your guild who has raided this season and is
  not on the raid team any more, on the same board, with the same detail pane.
  Nothing was ever deleted; there was simply no longer a door.

  Their bars are drawn against the **raid team's** scale rather than against
  each other, so you can still see where somebody stood next to the people
  still raiding, and the line underneath says whose average that marker is.
  Pugs are left out: the addon already records who was in the guild on each
  night, so a stranger who rolled in one of your raids is not listed as a
  raider you lost — and somebody who was one of yours on the night is still
  listed even if they have left the guild since.

- **Archive a raider yourself.** The Archived list fills itself from who raided
  and who is on the team, which cannot reach a trial who joined, never raided
  and drifted off — they have no nights to be derived from, so they sat on your
  roster for good. Now you can file them by hand. On the Raiders tab, pick
  somebody on the Roster and the footer offers **Archive Misothelioma**; pick
  them on Archived and it offers **Bring Misothelioma back**. The full roster
  window has an **Archive** button beside Remove, so a ticked set of three goes
  in one press.

  Archiving takes somebody off the raid team and off both rosters, and nothing
  else: their nights, items and every roll are kept, and the roster window says
  how many are filed away so nobody vanishes without a count. Guild rank plays
  no part in it, the same as adding and removing — officers who never raid hold
  the top rank and trials who raid hold the bottom one.

### Fixed

- **A raider who left the guild could not be taken off the raid team.** Team
  membership is remembered per account, so it survives a season being archived
  — but the roster was built from your live guild list alone. The moment
  somebody left the guild their tick outlived the only row that could clear it:
  they stayed on the Raiders board for good, the roster's Raid team filter drew
  nothing, and the line above the empty list read *"0 on the raid team · 2
  marked as raiding"* with neither number wrong. Anyone still ticked onto the
  team is now listed whether or not they are in the guild, marked **Not in
  guild** and sorted to the bottom, so there is a box to untick. Untick them and
  they move to Archived, where their season is kept.

### Changed

- **The minimap button's right-click menu is gone.** Every command in it is a
  button on Settings → Tools, which is where they have been since 0.4.1, and
  the right button now drags the icon instead. The same menu was still on the
  Titan Panel plugin and the Addons compartment entry — it has gone from those
  too, so a click anywhere opens the loot window and there is nothing else to
  learn.

### Fixed

- **The trade advisor came back after you dismissed it.** Dismissing an item
  took it off the list, but the addon re-reads each drop as its roll list fills
  in — and the next pass put it straight back, so the window reopened for
  something you had already waved away, for as long as the two-hour trade
  window lasted. Dismissed now means dismissed.

## 0.4.2 — 2026-08-25

### Fixed

- **The minimap button was sitting inside the minimap**, on top of the map,
  instead of on the ring around it. It was placed at a distance that assumed a
  minimap the game stopped drawing years ago. It reads the real size now, so it
  lands on the edge whatever size your minimap is — including after Edit Mode
  has resized it, and on a squared-off one.

### Added

- **Ask for what you lost.** Somebody else wins something you rolled on, a
  small window opens, and one button writes the message for you: *"Hi there,
  could I have [item] if you don't need it?"* It puts that in your chat box
  with the item link and their name already in it. **Nothing is sent until you
  press Enter**, and you can change any word first.

  It is for LFR and for pug raids — anywhere the standard roll option is in
  force and you are with people you do not know. It knows who won because it
  already reads the roll list, and it addresses the whisper properly across
  realms, which a name off a roll list alone does not do.

  **The wording is yours.** Type your own over it and it is saved and used from
  then on; the default can be put back at any time. `[item]` becomes the item
  link and `[player]` becomes their name, and a preview under the box shows the
  exact line, counted — an item link is about 110 characters of the 255 a
  whisper allows before you have written a word.

  **Any roll you actually made counts** — Need, offspec, Mog and Greed. LFR
  will refuse you a Need roll on the wrong armor type and sometimes refuses Mog
  for no visible reason, so greed is often the only button you were given
  rather than anything you meant by it. Passing does not count, so a night of
  passing on everything does not open a window on every drop.

  On a Mog roll it checks the appearance is still missing before it offers,
  which matters when two of the same item drop in one wing and you won the
  first.

  Off until you turn it on, under Settings → Features. Asked for by a guildie
  who remembered one from Remix.

- **The minimap button drags anywhere on the screen — right-click and drag.**
  It used to orbit the minimap and nothing else, so the only choice you had was
  which point on one circle. Put it where you want it and it stays there
  between sessions. Drop it on or near the minimap and it snaps back onto the
  ring.

  **Left-click opens the addon and no longer drags**, and right-click no longer
  lists the commands — the Tools tab in Settings has all of them as buttons
  now, which is what freed the right button up for the drag.

  It cannot be dragged off the edge of the screen, and **Reset windows and
  minimap button** on Settings → Tools brings it back to the ring if it ends up
  somewhere awkward — under the bags, behind another addon's frame, or off in a
  corner of a screen you have since changed the resolution of.

- **Titan Panel, Bazooka and ChocolateBar can show it.** The addon now
  publishes a Data Broker launcher, so it appears in the plugin list of
  whichever of those you use, with the same two clicks: left opens the loot
  window, right lists every command.

- **It is in the game's own Addons list too** — the compartment behind the plus
  sign on the minimap, with the same two clicks again.

  Between the three of them, the button on the ring is now a preference rather
  than the only way in: turn it off in Settings → Display and the addon is
  still one click away.

## 0.4.1 — 2026-08-24

### Added

- **Settings is five tabs.** Recording, Scoring, Features, Display and Tools —
  what gets written down, the numbers the boards argue about, what runs at
  all, look and noise, and everything you go looking for rather than set once.

  It used to be one 656-pixel column that scrolled, and the order in it was
  the order things happened to be built in — so the rank floor, the number
  that decides who gets ranked at all, sat between "record group loot" and
  "show the minimap button". Nothing scrolls now, nothing is below the fold,
  and the window is as tall as the tab you are looking at rather than as tall
  as the longest one. It remembers which tab you left it on.

- **The Scoring tab can be typed into.** Need, Greed and Mog are numbers you
  set, not constants somebody else chose, and the guild threshold — the
  percentage of a raid that has to be guild before the night counts at all —
  is a real setting beside them. Type a number, press Enter or click away, and
  it takes. Press Escape and it goes back.

  A weight that is refused says so instead of being quietly rounded into
  something else. Negatives are refused: a win cannot be worth a penalty.

  The caution is on the tab in red, not hidden in a tooltip. Changing a weight
  re-scores **every night already raided**, not just the next one, and so does
  moving the guild threshold. Set these before a season and leave them.

  Three rows, four weights. Your client reports offspec separately from greed;
  unless you tick **Score offspec separately** they are worth the same, so only
  one row shows and offspec follows it. Untick the link and a fourth row
  appears.

- **Choose which KINDS of item get recorded**, on the Recording tab, beside the
  qualities. Nine rows: raid gear, warbound gear, pets, mounts, toys, housing
  decor, profession supplies, quest items, and sparks and hides. A Mythic night
  drops gear, a mount, a decor piece and a fistful of reagents, and they are
  all the same purple — quality alone could never tell them apart.

  Everything is recorded until you turn something off, so nothing you already
  capture stops being captured. Unticking never removes records you already
  have. Every row explains what it catches on hover.

- **A Tools tab: every command as something you click.** Twenty-four of them,
  grouped by what you came looking for — open a screen, this season, people,
  sharing and trades, reports in chat, and if something goes wrong. The
  minimap menu already listed most of these, but the minimap button is a
  checkbox, and turning it off used to strand about thirteen commands with no
  click anywhere.

  Three of them could not simply be wired to their own names, and are fixed
  here: **Bosses** opens the Bosses tab rather than the old standalone window,
  **Who is due** opens a window rather than printing to chat, and **Who the
  boards show** — the raid team / guild / everyone switch that the due list and
  the players window both read — has a click for the first time, with the
  current setting in its own label.

  **Adding and removing a recruit** are real boxes now. Both were
  `/syl addraider Name-Realm CLASS` and nothing else, and the Raiders board
  told you they lived in the full roster window, where they never were.

  **Export for Discord** has a door. Its only button was inside a window you
  could reach only by typing `/syl players`.

- **Raid lockouts, per character, the way keystones already worked.** Which
  raids each of your characters is saved to this week, at which difficulty,
  how many bosses are already dead on each and which ones are still standing.
  It fills in as you log into them — there is no API for an alt's lockouts —
  and a character it has never seen says so rather than showing an empty row.
  It is on the Bosses tab, not in Keys.

- **The raid-night pane says what actually happened.** Clicking a night on the
  calendar now gives you the bosses by name and difficulty on hover, "11 of 13
  raiders" with the names of who was out, loot counted by the fairness rules
  rather than by everything that dropped, and the raid's own boss total — so
  "5 of 8", not "5 killed". Times are 12-hour with your own time zone.

  It records when the group zoned in and out, and when each pull STARTED, so
  the evening is the evening rather than the stretch between the first pull
  and the last. A ten-minute pull begun at 9:10 is no longer filed at 9:20.

  "50% of pulls killed" and "drops per raider" are gone. Neither meant
  anything on a progression night.

- **Non-guild nights are on the calendar in their own colour**, so guild raids
  stand out — and nothing on them counts toward fairness, drought or attendance.

- **Match against RCLootCouncil history.** A button that reads its award
  history and pre-fills the credit picker for you to confirm. It never files
  anything on its own.

- **Tier tokens show which track they came from.** A token has no track of its
  own, but the difficulty it dropped at decides it: Veteran from LFR, Champion
  from Normal, Hero from Heroic, Myth from Mythic.

- **Sort the Raiders board by any column**, and filter the loot list from the
  column headers — the name sorts, the caret beside it filters, and a column
  that is both says both.

- **Difficulty is its own column** on the loot list, spelled out: LFR, Normal,
  Heroic, Mythic. It sorts and filters like anything else.

### Changed

- **The loot list opens on what you actually want.** Gear only and Raids only
  are the defaults now, along with the difficulty of the last raid you were
  in. Clear still opens everything up; reopening the window puts the defaults
  back.

- **The loot list's second row of filters is gone.** Its dropdowns moved into
  the column headers they belong to, and Select all, Deselect all, Ignore,
  Hide, Hide all and Show hidden moved to the bottom of the window. The list
  gained a row.

- **The top row and the button row are a size smaller**, and every button on
  the footer is now sized from the widest label it can ever hold rather than
  from a number somebody typed.

- **Windows are solid again.** The window that has focus is marked by its
  border rather than by being slightly less transparent than the others.

- **Today is easier to find on the calendar.**

- **Erasing a season is behind four locks now**, and it is not a button in a
  list. It sits at the bottom of the Tools tab under its own warning rule with
  an alert icon, and it says in plain words what goes, what stays, and what to
  do instead. Opening it does not erase anything: you have to type the
  season's own name before the Erase button will do anything at all, and
  **Archive instead** is offered first and larger, because that is what almost
  everybody who gets there actually wanted.

  `/syl clear confirm` still works exactly as it did.

### Fixed

- **Every dashboard widget tooltip was dead.** All seven had explanations
  written for them and none of them could ever appear — the row did not take
  the mouse, so pointing at one did nothing. They work now.

- **A stray sentence was being drawn through four of the five tabs**, 244
  pixels down, at a position left over from the single scrolling column the
  tabs replaced. It now appears once, on the Recording tab, where it belongs.

- **The Raiders board no longer tells you something untrue.** Its full-roster
  button said adding a recruit lived in that window. It never did.

- **The Default order button on the Display tab** could be drawn off the bottom
  of the window in some layouts.

- **Nothing on the loot page is drawn on top of anything else.** The count
  line was printed straight through the From and To date boxes. "Hide all"
  covered most of "All seasons" and took its clicks. The fourteenth row of the
  list was drawn below the frame that clips it, which meant the last record in
  your list could never be scrolled to.

- **Ticking a box in a filter no longer closes it.** Multi-select was one
  value per opening, every time. Clicking another column's filter now opens
  that filter instead of just closing the one you had open.

- **"None" in a filter showed everything.** It had, for as long as the button
  had existed — an empty selection meant "no constraint". It now means none,
  while Clear still means "back to the defaults".

- **The Bosses tab's caveat was printed over the last two rows** of the
  never-dropped list, and the lockouts view's column headings ran up into the
  button that switches back to the boss list.

- **One person marked out on two of their characters counted as two people
  missing**, which every attendance figure underneath was built on.

- **A character who changed name kept the old one** on the raid-night pane.

- **The loot list's dates were on a 24-hour clock** and did not say which time
  zone they were in.

- **An item name that was too long for its column** was being cut off 8 pixels
  early: the column was budgeted at one type size and drawn at a larger one.

- **The Close button's bottom-right corner belonged to the resize grip**, so
  clicking there started a resize.

- **The Archives bar had a hairline drawn through it.**

## 0.4.0 — 2026-08-22

### Changed

- **A raider's loot, grouped by the night they took it**, with the item's real
  link on it. Click somebody on the Raiders board and every item is now a card:
  its icon, its name in its quality color, how it was won, the boss it came
  off, and its upgrade track as a single letter — V, C, H or M. Hovering an
  item gives the game's own tooltip and shift-clicking pastes it into chat,
  which plain gray text never did.

  The nights are the raid's, not the calendar's. A raid that runs past midnight
  stamps tomorrow's date on tonight's last few drops, and grouping on that
  would put a heading on the pane for a raid night that never happened.

  The three figures across the top — raid nights, items, points — say at a
  glance what the arithmetic underneath adds up to.

- **Transmog now reads "Mog"** everywhere it appears: the loot list, the
  breakdown that explains a score, the settings screen and every item card.

- **The Raiders board has column headings, and its numbers now line up under
  them.** Four numbers sat in a row with nothing naming them, and you had to
  remember which was which. They are titled now — RAIDER, # ITEMS RECEIVED,
  RAID NIGHTS, POINTS PER NIGHT, TOTAL POINTS — all left justified, all four
  right-hand columns the same width, evenly spaced, with the names set in from
  the edge rather than against it.

  It is still a board and not a table. The bar is still what answers who is
  behind; the headings only make the numbers beside it checkable.

- **RAID NIGHTS now reads "attended of held"** — 2 of 2, or 1 of 2 — so a
  raider's attendance is a figure you can check rather than one you have to
  hold the raid total in your head to read. Guild nights only, the same ones
  every other attendance figure counts.

- **Bars are colored by difficulty**, using WoW's own quality colors: rare blue
  for Normal, epic purple for Heroic, legendary orange for Mythic. A bar is cut
  by points rather than by item count, so the colors always add up to the
  length. Two raiders on the same total now read differently when one of them
  got there on Heroic drops.

- **The raid average is a mark above each bar** instead of a line drawn through
  the whole list. Through the bars you could not tell a bar that stopped at the
  average from one that crossed it.

- **Pointing at a raider explains their row** — why somebody is not ranked,
  which used to be printed in a column too narrow to hold it, and the split of
  their bar by difficulty.

## 0.3.6 — 2026-08-20

### Added

- **Who else responded on an item, through RCLootCouncil.** Open a drop and the
  list underneath now shows what the council was told — who needed it, who
  greeded, who wanted it for transmog, their rolls, item levels and votes —
  instead of the group-loot roll, which under a council reads "everybody
  passed, the master looter took it" on every single item.

  **You have to turn one thing on in RCLootCouncil first, and it is off by
  default.** Its options have a setting called **Send Session Responses**;
  until it is ticked, nothing anywhere keeps who responded — not this addon,
  and not RCLootCouncil's own history screen either. Open any drop and this
  addon will tell you if it is off and offer a button that turns it on.

  It only applies from the next loot session onwards. Nights already raided
  cannot be filled in, by anything, because the answers were never written
  down.

- **How many items each raider has taken**, on the Raiders board beside their
  bar. Need and greed, not transmog. The bar answers how much; this answers how
  often.

### Fixed

- **The drop list has column headings**, which it never had, and the window is
  sized to the number of players in it rather than always reserving room for
  fourteen.

## 0.3.5 — 2026-08-20

### Added

- **You can correct who a drop counted for.** Open any group-loot drop from
  the Loot tab and there is a new **CREDITED TO** line under the winner: who
  it counts for, what response it is scored on, and where that came from —
  won the roll, traded to them, or set by hand. **Change…** picks a different
  raider, **Undo** puts it back.

  This is for anyone running a loot council. The addon can only see what the
  client tells it, and the client says the master looter won every single
  item — so a guild that hands loot out through RCLootCouncil or by trading
  after the fact had one person holding the whole raid's score and everybody
  else on nothing.

  Two things needed correcting per drop, not one. The **response** is wrong as
  often as the person is, because the roll it records is the master looter's
  and not the recipient's — so the picker chooses the response too. On one
  real raid night, six of eleven drops carried the wrong weight and four of
  those were transmog, which is worth nothing: moving only the name would have
  moved no points at all on more than a third of them.

  Nothing is rewritten. "Won by ... with 51" still says exactly that
  afterwards, because that is what happened. Only the credit moves, and Undo
  is available for as long as the record exists.

- **How many items somebody actually received**, on the Raiders detail pane,
  counting need and greed and not transmog. A transmog win costs the raid
  nothing, so counting it there would say somebody had been looked after when
  they had not.

### Fixed

- **LFR and pug runs counted towards the fairness board.** The calendar and
  the dashboard have applied the "80% of the group in your guild" rule since it
  was written; the Raiders board never did. So a 49-person LFR run with one
  guildie in it fed the same board your raid team is ranked on, and people you
  have never raided with sat on it holding points. Both the nights and the
  wins from a session that is not your guild's now stay out of it, back through
  your whole season — a boss tile still shows every drop it gave, because that
  is a record rather than a ranking.

- **Sharing stored a second copy of every drop.** If somebody else in your
  raid also runs this addon with sharing on, every drop they broadcast was
  saved again alongside your own. The copies were nearly invisible — they
  carry no item name, so nothing appeared in the loot list — but they counted
  in the fairness math, and they credited whoever won the roll. On a
  master-looted night that is one person's score inflated by the whole raid.
  One officer's board read 560 where it should have read 200.

  The cause was that a record's id starts with the timestamp of when *your*
  session began, and two people in the same raid start theirs a second or two
  apart, so the same drop never matched itself. Copies already saved are
  removed when you log in, and the addon says in chat how many it removed.

- **The front window really is in front now.** 0.3.4 said this was fixed and
  it was not: every window sat on the same layer, so nothing could be ordered
  against anything else. A window opened from a button on another window could
  appear *behind* it, clicking a buried window did not raise it, and two
  overlapping windows stayed see-through. One cause under all three.

- **A window's close button no longer shows through the window in front of
  it.**

- **The Raiders detail pane said "wins that counted" and counted transmog**,
  which is the one kind that does not count.

- **The settings cog could not be clicked.** The whole top of the window was
  an invisible drag handle, and it took the clicks meant for the controls
  under it. There is no handle now — dragging still works from the title bar,
  and nothing is drawn over it.

- **You could not select text or click a row without dragging the window.**

- **`/syl clear` could empty your season from the minimap menu**, with no
  confirmation and no way back. It now names what it would destroy and refuses
  unless you type the word.

- **Anybody in your party or instance group could replace your shared
  roster**, and a longer incoming roll list could overwrite one this client had
  watched for itself. Both now check who sent them.

- **The Players window and the Discord export disagreed with the Raiders
  board.** A bind-on-equip, warbound, Timewalking or Mythic+ win counted as an
  upgrade in one place and as nothing in the other, and the export credited
  whoever won the roll rather than whoever the item went to. All four screens
  read one rule now.

- **The Keys table was far too wide.** Every column is measured against the
  widest text it can hold instead of guessed at; the table went from 508
  pixels to 387. The RESPONSE heading also sat a few pixels high and changed
  alignment depending on what a row was showing.

- **A 399-person roster could not be scrolled**, and clicking a name in it did
  nothing.

- **Window positions are remembered** between sessions.

### Changed

- Right-click any name in the roster to copy it, and the "Alt of" box suggests
  from the roster as you type.
- American spellings throughout, including two that were visible in the
  interface.

## 0.3.4 — 2026-08-17

### Fixed

- **The Archive Season button did nothing.** The dialog opened, took a name,
  and ended nothing — on every client, which made it impossible to close a
  season from the interface at the one moment a tier ends. The dialog is
  rebuilt and works. It now also names the season being closed and says, in
  those words, that the box is naming the **new** one — which is the thing
  `/syl archive` has always got backwards.
- **Sharing sent too many messages at once and the client threw some away.**
  Logging in fired more than twenty addon messages in a single frame — your
  absences, your roster, your keystone — and the game rate-limits them, prints
  "The number of messages that can be sent is limited", and discards the rest.
  A shared roster arrives as one message per raider and only appears once all
  of them land, so a single dropped message meant it never appeared at all and
  nothing said why. Everything is now sent at a steady pace instead.
- **Who is out was invisible on the calendar.** A day with somebody marked out
  said "1 person out" and stopped. The names, reasons and who set each one were
  being worked out correctly and written somewhere that could only draw one
  line. Click a day and they are listed underneath.
- **A reply to a key request was cut off**, drawn as "? Ma…" because the answer
  was being squeezed into the key level column. Replies have their own column
  now: **player, dungeon, key level, response**.
- **The front window is no longer see-through.** Windows are drawn slightly
  transparent, which reads as depth on one window and as a mess on two — the
  back one's text showing through the front one's body. Whichever window is on
  top is now solid.
- **Clicking a window brings it to the front.** Windows only ever rose when
  something opened them, so two overlapping windows could not be swapped by
  hand at all: the one underneath stayed underneath until you closed the other.

### Added

- **Rename Season**, beside Archive Season on the Archives tab. The name of the
  season running now could only be changed with a command; an archived one has
  been renameable since 0.3.2. The name is typed once, in a hurry, at the
  moment a tier ends — getting it wrong is ordinary and there is a way back now.

## 0.3.3 — 2026-08-17

### Added

- **Share your raid team with the guild.** Off by default, its own switch in
  Settings. Turn it on and everyone in your guild running the addon sees who
  is on the team and what each person plays — **and they do not have to turn
  anything on to see it.** Every other sharing switch here works both ways; a
  roster only travels one way, so the people it is for are not asked to find a
  setting first.

  The Raiders tab says who a shared roster came from, and **Clear shared**
  removes it. Anyone you marked yourself is untouched by that, and your own
  ticks always win over a shared one. Raiders you have added who have not
  joined the guild yet travel with the roster, so a team that is half recruits
  still arrives whole.

  Alt mapping is deliberately not shared. Team and role only change what a
  screen shows; alt mapping changes the numbers, so it stays something you
  decide on your own client.

## 0.3.2 — 2026-08-15

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

- **Bonus rolls are labeled.** They already counted for nothing — a bonus
  roll is not loot the raid awarded — but nothing on screen said so.

### Fixed

- **Warbound gear no longer counts toward score or drought.** It goes to the
  account rather than to the raider who was standing there, which is the same
  reason a bind-on-equip drop has never counted. This changes existing numbers
  for anyone who has won one. Filed under Changed when 0.3.2 shipped; the rule
  was always bind-on-pickup and warbound gear was slipping through it, which
  makes this a fix.
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
  measured — so the layout gave up and dropped them a few pixels from center,
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
  math reads it — it is context, not an input.
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
