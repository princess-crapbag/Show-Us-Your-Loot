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
   400×400, 1:1, `.png`, and explicitly **not** a blank single-colour square.
   `python tools/syl_logo.py` writes one to `dist/logo-400.png` in the
   addon's own colours. Replace it whenever something better exists.

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

**Allow Comments** — On. It is the only bug channel an alpha has.

**Experimental** — Off.

> Experimental means the project does not sync with the CurseForge
> ecosystem, and the guide recommends it only for authors who already know
> what that costs. Alpha is communicated by the file's release type, which is
> set per upload, not by this toggle.

**Editor** — WYSIWYG unless you want Markdown.

**License** — All Rights Reserved, matching `LICENSE` and the `.toc`.

> Worth a thought rather than a default: All Rights Reserved means nobody can
> legally fork this if you stop maintaining it. If that is not what you want,
> change `LICENSE`, the `.toc` `X-License` line and this field together.

---

## Description — paste this

```
[b]Alpha.[/b] Loot capture is solid and has been used in a real raid. Raid
nights, attendance and the due list have not yet had a full night of data
through them. Nothing is ever deleted, so the worst case is a number that
reads wrong, not history that disappears.

[b]This is not a loot council addon.[/b] It does not decide who gets an item
and it does not change how loot is awarded. It records what actually
happened, using Blizzard's default Group Loot, and answers the questions that
come up afterwards.

[b]What it records[/b]

Every group-loot drop, taken from Blizzard's Loot History API rather than
from chat: the item, who won it, what they rolled, and every player who was
eligible along with what each of them chose.

Raid nights are recorded separately, from the group roster read at every
pull. That distinction matters more than it sounds: roll lists only name
players an item could drop for, so a healer who raided all night without
being eligible for a single drop would otherwise look absent.

[b]What it answers[/b]

- Who is due? Ranked by raid nights attended since their last upgrade.
- Who turned up? Attendance from the roster, not inferred from loot.
- What has this boss given us? Pulls, kills, drops and upgrades per boss,
  kept separate by difficulty.
- How did tonight go? A summary when you leave the instance, leading with how
  many people went home without an upgrade.

Need, offspec, transmog and greed wins are counted apart from each other
throughout. A transmog win is not an upgrade, and folding them together makes
loot look fairer than it was.

[b]Commands[/b]

/syl opens the window. The minimap button does the same on left click, and
lists every command on right click. /syl help prints the rest.

[b]Officer sync[/b]

Off by default. When enabled it shares drop headers with other officers in
your raid — never roll lists, never anything outside your own group, never a
message a player sees — so loot is still recorded when you were not online
for it. Records arriving this way are marked partial and are left out of the
fairness numbers, because they carry no roll list and counting them would
report "nobody was eligible" rather than "we do not know".

[b]Your data[/b]

Everything is stored locally in your SavedVariables. Nothing is deleted
unless you clear it deliberately, and archived seasons are never touched.
```

---

## After the project exists

1. CurseForge issues a **project ID**. Put it in `ShowUsYourLoot.toc`, on its
   own line under `X-License`:

   ```
   ## X-Curse-Project-ID: 123456
   ```

   The commented placeholder is already there. The release workflow builds the
   zip fine without it and then has nowhere to send it, which looks like a
   broken build rather than a missing ID.

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
git tag v0.0.9-alpha
git push origin v0.0.9-alpha
```

None of that is needed to get one officer running. That is a zip.
