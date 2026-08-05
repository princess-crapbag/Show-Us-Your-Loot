# Sync setup — every step

Three pieces:

| Piece | Job | Auth |
|---|---|---|
| Addon | Records loot in game | none |
| Uploader | Carries data out of WoW | machine key (write only) |
| Dashboard | Shows it in a browser | Discord login (read only) |

Writes and reads are split on purpose. The uploader is a background script
and cannot complete an interactive login, so it keeps a key that can only
add data. People sign in with Discord and can only read.

---

## 1. Discord — create an app  (5 min)

1. https://discord.com/developers/applications → **New Application**.
   Name it anything.
2. **OAuth2** in the sidebar. Copy the **Client ID** and **Client Secret**.
3. Leave the tab open — you add a redirect URL in step 3.

## 2. Supabase — create the project  (5 min)

1. https://supabase.com → **New project**. Free tier is fine.
   Pick a region near you and save the database password somewhere.
2. Wait for it to finish provisioning.
3. **SQL Editor → New query**. Paste all of `web/supabase/schema.sql`
   and press **Run**. It should say Success.
4. Still in SQL Editor, run this once with a long random string of your
   own choosing — this is the uploader's key:

   ```sql
   select syl_create_guild('Show Us Your Kitties', 'paste-a-long-random-key-here');
   ```

   Save that key. It is hashed and cannot be read back, only replaced.
5. **Project Settings → API**. Copy the **Project URL** and the
   **anon public** key. The anon key is meant to be public.

## 3. Supabase — turn on Discord login  (3 min)

1. **Authentication → Providers → Discord**. Enable it.
2. Paste the Client ID and Client Secret from step 1.
3. Copy the **Callback URL** Supabase shows you.
4. Back in Discord: **OAuth2 → Redirects → Add Redirect**, paste it, save.

## 4. Uploader  (2 min)

```bash
python tools/syl_upload.py --configure
```

It asks for four things:

- Path to `ShowUsYourLoot.lua` — under
  `World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/`
- Project URL (step 2.5)
- anon public key (step 2.5)
- The guild key you chose in step 2.4

Then test it without waiting:

```bash
python tools/syl_upload.py --once
```

Expect something like `sent 5 drops and 0 raid nights -> {'ok': True, ...}`.

To leave it running while you play:

```bash
python tools/syl_upload.py
```

WoW writes SavedVariables on `/reload` and at logout, so data appears
within a reload — never mid-pull.

## 5. Sign in and add yourself  (3 min)

1. Open the dashboard, expand **sign in to see synced guild data**, paste
   the Project URL and anon key, click **Sign in with Discord**.
2. You will land back on the page signed in — and with no access yet.
   That is correct: signing in proves who you are, it does not grant
   anything.
3. In Supabase SQL Editor, add yourself:

   ```sql
   insert into syl_members (guild_id, user_id)
   select g.id, u.id
   from syl_guilds g, auth.users u
   where g.name = 'Show Us Your Kitties'
     and u.email = 'your-discord-email@example.com';
   ```

4. Back on the page, click **Load data**.

## 6. Adding an officer

1. Send them the dashboard link, the Project URL and the anon key.
   **Not** the uploader key — they do not need it to read.
2. They sign in with Discord once.
3. You run the same `insert into syl_members` with their email.

To revoke someone:

```sql
delete from syl_members
where user_id = (select id from auth.users where email = 'them@example.com');
```

One row. No key rotation, nobody else disturbed. That is the whole reason
for using logins instead of a shared password.

## If something goes wrong

- **`unknown key` from the uploader** — the guild key does not match what
  step 2.4 created.
- **Signed in but no data** — you are not in `syl_members` yet. Step 5.3.
- **Discord redirect error** — the callback URL from step 3.3 is not in the
  Discord app's redirect list.
- **`unsupported schemaVersion`** — the addon and schema have drifted; the
  addon writes v1 and the SQL expects v1.

## What the dashboard can still do without any of this

Drag `ShowUsYourLoot.lua` straight onto it. No project, no login, no
uploader. The hosted path is additive, never required.
