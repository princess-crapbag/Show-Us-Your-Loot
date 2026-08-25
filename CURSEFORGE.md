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

> Kept after a review on 2026-08-15. Every distinguishing feature is
> guild-scoped, and Guild is where officers actually browse. Boss Encounters
> is the bigger PvE pool, which is the argument against it: a loot-history
> addon lands far below the boss mods there.

**Additional categories** — Boss Encounters, Chat & Communication, Data
Export, Tooltip

> Four of a possible four, where three slots were being used and one of those
> was filler. Each is earned in code rather than claimed:
>
> - **Boss Encounters** — `Core/BossStats.lua`, `Core/LootTable.lua`,
>   `Core/EncounterJournal.lua`, `UI/BossLoot.lua`. It is the de facto raid
>   bucket on CurseForge and the biggest single gap in the old set.
> - **Chat & Communication** — six sync modules on the addon channel. Off by
>   default, which does not make the capability less real.
> - **Data Export** — `Core/DataExport.lua` with a versioned JSON schema, plus
>   five export buttons. Earned rather than filler.
> - **Tooltip** — `UI/ItemTooltip.lua` hooks the real game tooltip via
>   `TooltipDataProcessor`. The weakest of the four; cut this one first if a
>   slot is ever needed.
>
> **Miscellaneous was dropped.** Zero discovery value, and it was occupying a
> slot two honest categories needed.
>
> Rejected deliberately: Bags & Inventory (the addon records loot after the
> fact and never touches bags), Map & Minimap (a launcher button is not what
> that category is for).
>
> **Data Broker is now honest and was not before.** It was rejected here
> because no LDB feed existed — grepped, and true at the time. `UI/Launchers.lua`
> publishes a launcher object, so Titan Panel, Bazooka and ChocolateBar can all
> show this addon. Four categories is the maximum, so taking it means dropping
> one of the four above; Tooltip is the one already marked as first to go.

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

Rewritten 2026-08-15 for 0.3.2, fact-checked line by line against the code,
then edited by Aimee and pasted live. **This block is her live text**, not the
draft it came from: she added the bullet lists, Oxford commas, and moved the
Retail-only line to the end. Copy it from here rather than rewriting from the
draft. **No em dashes anywhere in it, on
purpose**, so a rewrite that reintroduces one is a rewrite that stopped
following the brief.

Six claims in the drafts had to be pulled because the code does not support
them, and they are the ones to watch for if this is ever rewritten again:

- **"the game forgets who lost"** is wrong. Blizzard's Loot History API is
  where these records come from, so the game does keep the roll list. It
  discards it later, and does not divide it by attendance. The hook has to say
  *kept*, not *recorded*.
- **Anything about what other addons do or do not keep.** No competitor was
  ever audited. That sentence lands on a page with comments enabled, next to
  RCLootCouncil and Gargul.
- **"records everything anybody received"** is contradicted by the addon's own
  settings text: your client only sees other people's loot while you are
  grouped with them.
- **"alts count as one person"** only after somebody accepts a mapping.
  `Core/AltDetect.lua` proposes and never applies.
- **The Bosses tab** cannot say what never dropped until Loot tables has been
  pressed. Promising it on install night sends people to an empty screen.
- **"used in live raids every week"** was invented. One real raid night has
  been through the fairness math.

```
Six people rolled Need on the same weapon. One of them won it. Ask a month later who the other five were and nobody can tell you, because the game does not keep that list.

Show Us Your Loot keeps it.

Every group loot drop gets recorded off Blizzard's Loot History API: the item, who won, what they rolled, and every player who was eligible, along with what each one chose. Need, offspec, greed, Mog, or pass. That last part is what makes the rest of this work. Eleven people eligible and no upgrades reads completely differently depending on whether they passed or lost.

This is not a loot council addon. It awards nothing and changes nothing about how loot is handed out. You keep using Group Loot. This answers the argument afterwards.


Who is due

* Ranked by loot taken per raid night rather than by raw count, so somebody with perfect attendance sits above somebody who turns up half the time on the same amount of gear. Need is worth 100, offspec and greed 20 each, Mog nothing, divided by the nights attended.
* Click any raider and you get the arithmetic, and the loot itself. Every item they took is listed under the raid night they took it on, with the real item link, the boss it came off, how it was won and its upgrade track. Hover one for the game's own tooltip; shift-click to paste it into chat. Underneath, every win that counted, what each was worth, and the total those add up to. When somebody thinks their number is wrong, that is the screen they stand at.
* The board itself is a bar per raider against the raid average, with the bar colored by the difficulty the loot came from -- rare blue for Normal, epic purple for Heroic, legendary orange for Mythic -- so two raiders on the same total read differently when one of them got there on Heroic drops.
* Under three raid nights nobody is ranked at all. They are listed with the reason instead, because one lucky night should not sit at the top of the list.
* Vault gear, M+ chests, catalyst, delves, BoEs, bonus rolls, and warbound items are all recorded where your client can see them, and none of them move the ranking.


It is useful on the first drop

* Win something and a small window opens naming everyone who rolled Need or offspec and lost, most owed first, with your two hour trade window counting down. That works on install night with no history behind it, because the roll list is complete the moment the item is awarded.
* An addon cannot click a trade button for you. It tells you who rolled and stops there. If you do hand the item over, the score follows it to whoever received it.


The rest of it

* Attendance is read from the group roster at every pull rather than worked out from loot, so a healer who was there all night without being eligible for a single drop still gets the night.
* Mythic+ keys for your own characters, and your guild's as well if they run this with key sharing on. A second view on the same tab shows which of your characters is already saved to which Mythic 0 this week.
* A month calendar of your raid nights. Mark somebody out for a day or a fortnight, or mark yourself out, and every absence carries the name of whoever set it.
* Boss loot tables showing what a boss has never given you, kept apart by difficulty. Reading the Adventure Guide is a button rather than something that happens on its own, because it walks every raid tier and moves your own Journal selection while it does.
* Seasons archive when a tier ends, and stay browsable afterwards.


What it will not do

* History starts the day you install it. There is no backfill and there cannot be one.
* Nothing can read another player's bags. Guild keys only appear for people running this with the same switch turned on.
* Your client only sees other people's loot while you are grouped with them, so gear taken without a roll mostly counts yours.
* Officer sync, key sharing, key requests and absence sharing each have their own switch and all four are off until you turn them on. Absence sharing goes to the whole guild with your name attached to anything you set.
* Everything is stored in your SavedVariables. Exports are copy and paste. Addons have no network access at all, so nothing is uploaded and nothing reaches Discord.


This is new, and comments are the fastest way to reach me if you have any feedback or concerns. Retail only, patch 12.1.0.
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
