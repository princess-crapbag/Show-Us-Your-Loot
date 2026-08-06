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

## 1. Discord — create an app  (OPTIONAL, skip it)

Only needed if you specifically want Discord identities. It requires
two-factor authentication on your Discord account before it will reveal
the client secret. Email sign-in needs none of this and is the default.

<details><summary>Discord steps, if you want them anyway</summary>


1. https://discord.com/developers/applications → **New Application**.
   Name it anything.
2. **OAuth2** in the sidebar. Copy the **Client ID** and **Client Secret**.
3. Leave the tab open — you add a redirect URL in step 3.

</details>

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
5. Collect two values.

   **Project URL** — Settings, then Data API. Or read it off the dashboard
   address bar: `.../project/<ref>` means your URL is
   `https://<ref>.supabase.co`.

   **API key** — Settings, then API Keys. Supabase now shows two systems:

   | Tab | What to take |
   |---|---|
   | Publishable and secret | The **Publishable key**, `sb_publishable_...` |
   | Legacy anon, service_role | Or the **anon** key, if publishable 401s |

   Never use the **Secret key**. It bypasses row level security entirely,
   so whoever holds it can read and write everything regardless of the
   policies. It belongs on a server, not in a browser or a config file.

## 3. Run the page locally  (2 min)

**This step is not optional.** A page served from claude.ai cannot reach
Supabase: published artifacts run under a Content Security Policy that
blocks every outbound request. The hosted copy is still fine for dragging
a SavedVariables file onto, which needs no network at all.

```powershell
cd "C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\web"
python -m http.server 8000
```

Leave that window open and visit <http://localhost:8000>.

Serve it rather than double-clicking the file: opening index.html directly
gives the page a file:// origin, which browsers distrust for cross-site
requests. http://localhost is a real origin and works.

Then in Supabase, **Authentication -> URL Configuration -> Redirect URLs**,
add:

    http://localhost:8000

## 3b. Discord login  (OPTIONAL)

1. **Authentication → Providers → Discord**. Enable it.
2. Paste the Client ID and Client Secret from step 1.
3. Copy the **Callback URL** Supabase shows you.
4. Back in Discord: **OAuth2 → Redirects → Add Redirect**, paste it, save.

## 4. Uploader  (2 min)

In PowerShell. The full path works from any folder, and the quotes matter
because the path contains a space:

```powershell
python "C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\tools\syl_upload.py" --configure
```

It asks for four things:

- Path to `ShowUsYourLoot.lua` — under
  `World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/`
- Project URL (step 2.5)
- Publishable key (step 2.5)
- The guild key you chose in step 2.4

Then test it without waiting:

```powershell
python "C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\tools\syl_upload.py" --once
```

Expect something like `sent 5 drops and 0 raid nights -> {'ok': True, ...}`.

To leave it running while you play:

```powershell
python "C:\Users\Taylor Swift\Desktop\ShowUsYourLoot\tools\syl_upload.py"
```

WoW writes SavedVariables on `/reload` and at logout, so data appears
within a reload — never mid-pull.

## 5. Sign in and add yourself  (3 min)

1. At <http://localhost:8000>, expand **sign in to see synced guild data**,
   paste the Project URL and API key, enter your email and click
   **Email me a sign-in link**. Click the link in the mail; check spam, as
   Supabase's default sender often lands there.
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
- **Failed to fetch** — the page is being served from claude.ai, whose CSP
  blocks outbound requests, or straight off disk as file://. Serve it on
  http://localhost instead.
- **Email link does nothing** — http://localhost:8000 is not in the
  Supabase redirect URL list.
- **`unsupported schemaVersion`** — the addon and schema have drifted; the
  addon writes v1 and the SQL expects v1.
- **401 or invalid API key** — try the other key tab. Publishable and legacy
  anon both work. Secret must never be used.
- **can't open file ...syl_upload.py** — PowerShell was in a different
  folder. Use the full quoted path rather than a relative one.
- **function gen_salt does not exist** — run
  `web/supabase/fix-search-path.sql`.

## What the dashboard can still do without any of this

Drag `ShowUsYourLoot.lua` straight onto it. No project, no login, no
uploader. The hosted path is additive, never required.
