# Setting up sync

Three pieces: the addon (already installed), Supabase (holds the data), and
the uploader (carries data out of WoW, because addons cannot make web
requests).

## 1. Supabase

1. Create a free project at supabase.com.
2. Open **SQL Editor → New query**, paste all of `web/supabase/schema.sql`,
   and run it.
3. Run this once, with a long random key of your choosing:

   ```sql
   select syl_create_guild('Show Us Your Kitties', 'your-long-random-key');
   ```

   Keep that key. It is hashed in the database and cannot be read back,
   only replaced.
4. From **Project Settings → API**, copy the **Project URL** and the
   **anon public** key.

The anon key is meant to be public. The guild key is not — it is the thing
that actually grants access, and the tables refuse every request without it.

## 2. Uploader

```bash
python tools/syl_upload.py --configure
```

It asks for the SavedVariables path, the project URL, the anon key, and your
guild key, then stores them in `~/.syl-upload.json`.

Then leave it running while you play:

```bash
python tools/syl_upload.py
```

WoW writes SavedVariables on `/reload` and at logout, so data appears within
a reload — never mid-pull. Nothing is sent until you configure it, and only
to the URL you gave it.

## 3. The page

Open `web/index.html`, expand **Connect to Supabase**, paste the project
URL, anon key and guild key, and press Load. They are remembered in that
browser only.

The page still reads a dropped SavedVariables file too, so it works with no
setup at all if you would rather not host anything.

## Giving an officer access

Send them the project URL, the anon key and the guild key. Anyone with all
three can read and upload. To revoke, mint a new key:

```sql
update syl_guilds
set key_hash = crypt('a-new-long-random-key', gen_salt('bf'))
where name = 'Show Us Your Kitties';
```

Everyone then needs the new key. There are no per-person accounts by
design — that was the tradeoff for not needing logins.
