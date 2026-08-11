# CurseForge submission — everything to paste

Working document. Not shipped in the addon zip.

Fields verified against the live submission guide on 2026-08-06, not from
memory. If a field below is not on the form, the form changed — read it
rather than trusting this.

---

## Before you start

Two things block the form and are worth having ready:

1. **A Twitch account.** CurseForge has no login of its own: the sign-in page
   says "Use your Twitch account or create one". This is not mentioned
   anywhere in the addon docs and is the single most likely thing to stop you
   at minute one.
2. **A logo.** Required on the submission form, not addable later. Minimum
   400×400, 1:1, `.png`, and explicitly **not** a blank single-color square.
   `python tools/syl_logo.py` writes one to `dist/logo-400.png` in the
   addon's own colors. Replace it whenever something better exists.

---

## Field by field

**Game** — World of Warcraft

**Project name** — `Show Us Your Loot`

> No version number, no "addon" in the name; both are called out in the
> guide. Check nothing similar already exists before submitting.

**Logo** — `dist/logo-400.png`

**Summary** (one line, what it does, not who it is for):

```
Loot history, attendance and fairness analytics for guilds using Group Loot.
```

**Class** — Addons

**Main category** — Guild

**Additional categories** — Data Export, Miscellaneous

**Allow Comments** — On. It is the only bug channel this has.

**Experimental** — Off.

> Experimental means the project does not sync with the CurseForge
> ecosystem, and the guide recommends it only for authors who already know
> what that costs. Alpha is communicated by the file's release type, which is
> set per upload, not by this toggle.

**Editor** — WYSIWYG. There is no BBCode option, whatever an older draft of
this file implied; Markdown is the only alternative and its formatting does not
come out right either.

**License** — All Rights Reserved, matching `LICENSE` and the `.toc`.

> Worth a thought rather than a default: All Rights Reserved means nobody can
> legally fork this if you stop maintaining it. If that is not what you want,
> change `LICENSE`, the `.toc` `X-License` line and this field together.

---

## Description — paste this

PLAIN TEXT, NOT BBCODE. The earlier version of this file used [b] tags and
they are not supported — CurseForge offers WYSIWYG and Markdown, and the
tags paste in as literal text. This pastes into the WYSIWYG editor as is;
bold the section headings there if you want them to stand out.

Rewritten for 0.3.0, the first non-alpha release. Three things in the
previous version had become false: it opened on an Alpha caveat saying the
due list had never had a night of data through it, it described the ranking
as nights-since-upgrade rather than loot per night, and it said officer sync
never sends roll lists. It sends them now.

```
Group Loot remembers who won. This remembers who passed.

Show Us Your Loot records every group-loot drop in your raid — the item, who
won it, what they rolled, and every player who was eligible along with what
each of them chose. That last part is the bit nothing else keeps, and it is
what makes the rest of this possible.

This is not a loot council addon. It does not decide who gets an item and it
does not change how loot is awarded. It uses Blizzard's default Group Loot and
answers the questions that come up afterwards.


It is useful on the very first drop

Most history addons need a tier of data before they tell you anything. This one
does not. The moment you win something, a small window names everyone who
rolled Need or offspec and lost, sorted by who is owed most, with the clock
running on your two-hour trade window.

That works on install night with no history at all, because the roll list is
complete the moment the item is awarded. An addon cannot click a trade button
for you, so it only ever tells you who asked.

If you do trade the item, the score follows it to whoever received it.


What it records

Every group-loot drop, taken from Blizzard's Loot History API rather than from
chat: the item, the winner, the roll, and the full list of eligible players and
their choices.

Raid nights are recorded separately, from the group roster read at every pull.
That distinction matters more than it sounds: roll lists only name players an
item could drop for, so a healer who raided all night without being eligible
for a single drop would otherwise look absent.


What it answers

Who is due? Ranked by loot taken per raid night, so somebody with perfect
attendance ranks above somebody there half the time on the same amount of loot.
Need is worth 100, offspec and greed 20 each, transmog nothing. Click any
raider to see exactly where their number came from — every win that counted and
what each was worth. Nobody with fewer than three nights is ranked; they are
listed with the reason instead.

Who turned up? Attendance from the roster, not inferred from loot.

What has this boss never given us? A loot table per boss showing what it can
drop and has not, kept separate by difficulty.

When did we raid? A month calendar of your raid nights, each shaded with what
died, and a stat panel for any day you click.

How did tonight go? A summary when you leave the instance, leading with how
many people went home without an upgrade.

Need, offspec, transmog and greed are counted apart from each other throughout.
A transmog win is not an upgrade, and folding them together makes loot look
fairer than it was.


Mythic+ keys

Every key your characters hold, kept current at login, when a dungeon finishes,
and when a key is rerolled. Turn on key sharing and it shows your guild's too,
for anyone running the addon with the same switch on — nothing can read another
player's bags, so that is the only way it can work.

You can also ask a guildie to run theirs. The request is whispered to that one
person and never broadcast, so two people asking for the same key never learn
about each other. Off by default.


Raid schedule

Tell it which nights you raid once, and it answers "when is the next raid
night" from then on. Mark somebody out for a week with one line. It can also
read your in-game guild calendar, and never overwrites a night you typed in.


Officer sync

Off by default. When enabled it shares drops with other officers in your raid —
never outside your own group, never a message a player sees — so loot is still
recorded when you were not online for it.


Everything can be switched off

Raid buff coverage, Mythic+ scores, boss loot tables, officer sync, key
sharing, key requests, the trade advisor and trade tracking are each a switch
in Settings, and each says what it costs when it is on. Anything switched off is
not built at all rather than built and hidden.


Your data

Everything is stored locally in your SavedVariables. Nothing is ever deleted
unless you clear it deliberately, and archived seasons are never touched. Hiding
a row and ignoring a row are both reversible.


Commands

/syl opens the window. The minimap button does the same on left click, and lists
every command on right click. /syl help prints the rest.


A note on how young this is

History starts the day you install it and cannot be backfilled. The addon has
been used in live raids and the numbers have been checked against real nights,
but it is new — comments are the fastest way to reach me if something reads
wrong.
```

---

## Submitted 2026-08-06

Project ID **1642383**, slug `show-us-your-loot`, already written into the
`.toc`. The author dashboard is **authors.curseforge.com**, which is a
separate site from the project pages and hash routed, so links into it look
like `authors.curseforge.com/#/projects/1642383/files`.

Status on submission was **New**: awaiting a moderator, not visible to
anyone, and files do not sync across CurseForge until it clears.

## After the project exists

2. Upload the first file by hand — **Files → Upload File** — rather than
   waiting on automation. Set the release type to **Alpha**.

3. Only then bother with the API token and tags. See below.

---

## Automating releases later

The workflow in `.github/workflows/release.yml` already does this. It needs:

- The `X-Curse-Project-ID` line above.
- A repository secret named `CF_API_KEY`, from the CurseForge account
  settings under API Tokens.
- A GitHub remote, which this repository does not currently have.

Then a release is:

```
git tag v0.1.0-alpha
git push origin v0.1.0-alpha
```

The `-alpha` suffix is not decoration: the packager reads it and marks the
file Alpha on CurseForge. Confirmed on the v0.1.0-alpha run, which uploaded
as `12.0.7 alpha`. A tag without it publishes as a full release.

**Write the CHANGELOG.md entry before tagging.** `.pkgmeta` points the
packager at it, and a manual changelog always beats the generated one. Left
empty, CurseForge would show the commit messages between the two tags —
written for whoever maintains this, full of reasoning and rejected
alternatives, and the wrong thing to hand somebody deciding whether to
update. Write what they will notice, not why it exists.

**Bump `## Version:` in the .toc to match, in the same commit as the tag.**
The packager rewrites that line in the zip it builds, so CurseForge is always
right — but it never touches the working copy. Anyone running the addon from
a checkout, which includes a symlinked development install, reads the .toc
and sees whatever was last typed there. That drifted once already: v0.1.0
shipped while the .toc still said 0.0.9-alpha, so the game reported a version
that had not existed for a while.

None of that is needed to get one officer running. That is a zip.
