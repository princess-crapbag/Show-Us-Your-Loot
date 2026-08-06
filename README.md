# Show Us Your Loot

Loot history, attendance and fairness analytics for guilds running Blizzard's
default **Group Loot**.

This is not a loot council addon. It does not decide who gets an item, and it
does not change how loot is awarded. It records what actually happened and
answers the questions that come up afterwards.

## What it records

Every group-loot drop, taken from Blizzard's Loot History API rather than from
chat: the item, who won it, what they rolled, and every player who was
eligible along with what each of them chose.

Raid nights are recorded separately, from the group roster read at every pull.
That distinction matters more than it sounds: roll lists only name players an
item *could* drop for, so a healer who raided all night without being eligible
for a single drop would otherwise look absent.

## What it answers

- **Who is due?** Ranked by raid nights attended since their last upgrade.
- **Who turned up?** Attendance from the roster, not inferred from loot.
- **What has this boss given us?** Pulls, kills, drops and upgrades per boss,
  kept separate by difficulty.
- **How did tonight go?** A summary when you leave the instance, leading with
  how many people went home without an upgrade.

Need, offspec, transmog and greed wins are counted apart from each other
throughout. A transmog win is not an upgrade, and folding them together makes
loot look fairer than it was.

## Commands

`/syl` opens the window. The minimap button does the same on left click, and
lists every command on right click.

| Command | |
|---|---|
| `/syl drops` | Recent drops with winners and rolls |
| `/syl due` | Who has gone longest without an upgrade |
| `/syl players` | Per-player eligibility, wins and droughts |
| `/syl raids` | Every raid night |
| `/syl bosses` | Kills, pulls and drops per boss |
| `/syl tonight` | Summary of the night in progress |
| `/syl sync` | Officer sync status |
| `/syl theme` | Change the colour scheme |
| `/syl export` | Copy the whole history out |
| `/syl help` | Everything else |

## Officer sync

Off by default. When enabled it shares drop *headers* — never roll lists,
never anything outside your own raid group, never a message a player sees — so
loot is still recorded when you were not online for it. Records that arrive
this way are marked partial and are left out of the fairness numbers, because
they carry no roll list and counting them would report "nobody was eligible"
rather than "we do not know". `/syl sync` shows how much of a season that
covers.

## Data

Everything is stored locally in your SavedVariables. Nothing is deleted unless
you clear it deliberately, and archived seasons are never touched.

The repository also contains an optional uploader and web dashboard for
officers who want their history in a browser. Neither ships with the addon,
and the addon never depends on them — a raider who installs this and never
opens a browser sees no difference.
