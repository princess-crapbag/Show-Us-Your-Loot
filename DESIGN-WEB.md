# Browser access and sync — design options

Status: **direction confirmed 2026-08-05.** Browser access and sync are now
wanted, and the original "no server, no companion app" rule is explicitly
relaxed to get them.

Building in this order:

1. **Versioned data export** — BUILT. One JSON document with a schema
   version covering seasons, drops, rolls, raid sessions and guild ranks.
   Every option below reads exactly this, so it is correct work regardless
   of which route is taken.
2. **Local browser dashboard** — BUILT. Drag the SavedVariables file onto a
   page and read the whole history. No server, nothing to install.
3. **In-game officer sync** — next. Makes any one officer's file complete.
4. **Hosted dashboard** — open, now that the constraint is lifted. Worth
   doing only once 1 to 3 are proven, and it is a service rather than an
   addon feature.

## The hard constraint

WoW addons have no network access. None. No HTTP, no sockets, no way to
reach a URL. This is a sandbox rule, not an API gap, and there is no
workaround inside the addon.

Data can leave the game in exactly three ways:

1. **SavedVariables** — `WTF/Account/<ACCOUNT>/SavedVariables/ShowUsYourLoot.lua`,
   written on logout or `/reload`, never during play.
2. **Manual copy** — the export window, pasted somewhere by a person.
3. **Addon comms** — messages to other players' WoW clients, in game only.
   This reaches other officers, never the internet.

So a browser view means something outside the game reads that file. The
only question is what.

## The constraint that was relaxed

The original handoff said: *"No server. No external database. No required
companion app."* That has been set aside deliberately in favour of browser
access and sync.

One part of it still holds and should keep holding: **a raider who installs
the addon and never opens a browser must notice no difference.** Everything
here is additive. Nothing in the addon may come to depend on an export
having happened, a page having been opened, or another officer being
online.

## What "sync" could mean

These are different problems and want different answers:

- **Between officers** — several people record loot, one merged history.
  This is the one that actually matters for a guild, and it is solvable
  *inside* the game.
- **Between your own devices** — your data readable on your phone.
  A file-sharing problem, not a WoW problem.
- **Shared with the guild** — read-only page raiders can look at.
  A publishing problem, and the only one that genuinely needs hosting.

## Option 1 — Local page, drag and drop

A single self-contained `SYL.html`. Open it, drag the SavedVariables file
onto it, get the full dashboard. Parsing Lua tables in JavaScript is
straightforward for data this shape.

- No server, no install, works offline, no ongoing cost
- Nothing to maintain but one file
- No sync at all; manual and per-person
- Data is only as fresh as the last `/reload`

## Option 2 — Local watcher

A small script watches the SavedVariables file, converts it, and serves
`localhost`. The page refreshes itself when you reload in game.

- Feels live, still no hosting
- Requires running a script — a companion app in all but name
- Still one person's data on one machine

## Option 3 — In-game officer sync, then a local page

Officers' addons share captured drops with each other over addon comms
during raid. Every officer's SavedVariables ends up holding the full
picture. Then Option 1 is enough, because one file is already complete.

- Solves the sync that matters, with no server and no external anything
- Stays inside the addon's existing rules
- Merge is well defined: drops already carry stable ids
  (`runID-encounterID-lootListID`), so merging is idempotent
- Needs care: addon comms are real traffic to other players, rate limited,
  and should be officer-only and opt-in
- Does not help across devices or give the guild a link

## Option 4 — Hosted dashboard

Uploader plus an API plus a web app plus accounts.

- The only option that gives shareable links and true multi-device access
- Breaks the no-server rule outright, and adds cost, maintenance,
  authentication, and a place where guild data lives that is not a
  player's own machine
- Everything else on this list is a weekend; this is a product

## Recommendation

**Option 3, then Option 1.** In-game sync first, local page second.

That order matters. In-game sync is the piece that makes the data
*complete*, and it is worth having whether or not a browser view ever
exists — it fixes the current situation where loot is only recorded if one
particular person is present and online. Once any officer's file holds
everything, a browser view is just a reader, and the simplest possible
reader will do.

Option 4 stays open afterwards. Nothing in this path forecloses it, and by
then the export format will have been exercised for real.

## Work that is worth doing under every option

Independent of the decision, and the sensible first step:

- **A versioned, machine-readable export.** One JSON document with a
  schema version, seasons, drops, rolls, raid sessions and guild ranks.
  Every option above consumes exactly this. The current export is
  human-readable text aimed at Discord, which is a different job.
- **Stable identity.** Drops already have stable ids and players are keyed
  by GUID. Raid sessions are keyed by instance, difficulty and date.
  Merging any two exports is already well defined.
- **A schema version field**, so a page written today can refuse or adapt
  to a file written by a much later addon.

## Open questions

1. Does "no server" still hold? A hosted dashboard is the only way to get
   shareable links, and it changes the project from an addon into a
   service with all that implies.
2. Which sync actually matters first — officers merging their data, your
   own devices, or a read-only page for the guild?

## True sync with a hosted page — architecture

Requested 2026-08-05. This section is the concrete version of Option 4.

### The piece that cannot be removed

The addon cannot make a web request, so something on the PC must carry the
data out. Every design below has three parts and there is no version with
two:

    WoW  ->  SavedVariables.lua  ->  uploader  ->  API  ->  web page

The uploader is a small background program that watches the file and posts
it when it changes. SavedVariables is only written on `/reload` or logout,
so "live" means "within a reload", never mid-pull. Worth setting that
expectation early: a raider cannot refresh the page mid-fight and see the
last kill.

### What the uploader does

- Watches `WTF/Account/<ACCOUNT>/SavedVariables/ShowUsYourLoot.lua`
- Parses it, converts to the schema v1 JSON the addon already produces
- POSTs to a configured URL with a key identifying the guild
- Retries on failure and keeps a local copy, so a dropped connection never
  loses a raid night

It is stack-agnostic: point it at any endpoint. Writing it does not depend
on choosing a host.

### Merge on the server

Several officers upload. The server merges rather than overwrites, which
the existing ids already make safe:

- Drops key on `runID-encounterID-lootListID`
- Raid sessions key on instance, difficulty and date
- Players key on GUID

Rule: a record with a roll list always beats one without, so a full local
capture is never replaced by a partial synced header. Otherwise newest
wins. This is the same rule the in-game sync already follows.

### Hosting options

**Serverless (recommended)** — Cloudflare Workers plus KV, or Supabase.
Free tier covers a guild comfortably. Real API, real auth, a real URL,
nothing to patch or keep running.

**Static plus private repo** — uploader commits JSON to a private repo,
page served from Pages. Free and versioned, but authentication is awkward
and the data is one misconfiguration away from public.

**A box you rent** — most control, most maintenance. Hard to justify here.

### What this needs that the addon never did

- An account somewhere, and possibly a card on file
- A decision about who can read the page. Guild loot is not secret, but it
  is a list of real people and their history, and a public URL is a public
  URL
- Someone to keep it alive. An addon that stops being updated still works;
  a service that stops being paid for disappears

### Open decisions

1. Where does it live? This determines the API and the auth model.
2. Who can see it — you only, officers, the whole guild, anyone with a
   link?
3. Does the uploader run only on your machine, or on every officer's?
